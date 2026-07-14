#!/usr/bin/env bash
# =============================================================================
# lint-library.sh — validation gate for the pure platform-library chart.
#
# A library chart is not installable, so we validate it through the test
# consumer fixtures: helm lint the library, render each fixture across the
# supported Kubernetes version range with expected-object-count assertions,
# diff each fixture's canonical render against its committed golden snapshot,
# validate every rendered object with kubeconform against the vendored,
# hermetic schema copies in tests/schemas/ (native + CRD schemas, across the
# version matrix — see tests/schemas/README.md for provenance and
# scripts/vendor-schemas.sh to refresh them), run a negative render proving
# CRD objects drop when their API is absent, enforce image pinning, and
# validate the values
# contract: the reference JSON Schema against its metaschema, every fixture's
# values against it (check-jsonschema), and helm-side rejection of
# schema-violating values (the schema is copied into each fixture as
# values.schema.json at render time), and exercise posture guardrails for mTLS,
# cluster-scoped extras, and pre-existing Secrets.
#
# Usage:
#   scripts/lint-library.sh                        # run all checks
#   UPDATE_GOLDEN=1 scripts/lint-library.sh        # regenerate tests/golden/*.yaml
#   REQUIRE_KUBECONFORM=1 scripts/lint-library.sh  # fail if kubeconform missing (CI)
#   REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh  # fail if check-jsonschema missing (CI)
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/platform-library"
RENDER="$REPO_ROOT/tests/render.sh"
GOLDEN_DIR="$REPO_ROOT/tests/golden"
SCHEMA_DIR="$REPO_ROOT/tests/schemas"
FIXTURES=(minimal full stateful daemon)
GOLDEN_KUBE_VERSION=1.34   # canonical version for golden snapshots

# shellcheck source=scripts/lib/schema-manifest.sh
source "$REPO_ROOT/scripts/lib/schema-manifest.sh"   # sets KUBE_VERSIONS

# Schema validation is fully hermetic: both locations point at schemas
# vendored into tests/schemas/ (see tests/schemas/README.md for provenance),
# refreshed by scripts/vendor-schemas.sh. No network access happens here —
# this used to hit the jsdelivr CDN mirror at test time, which intermittently
# returned hard 403s that survived retries and flaked CI.
NATIVE_SCHEMA_LOCATION="$SCHEMA_DIR/native/{{ .NormalizedKubernetesVersion }}-standalone{{ .StrictSuffix }}/{{ .ResourceKind }}{{ .KindSuffix }}.json"
# CRD schemas: covers cert-manager, Gateway API, Prometheus Operator, and
# Istio — every CRD-backed Kind the library emits.
CRD_SCHEMA_LOCATION="$SCHEMA_DIR/crd/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
fail=0

# Expected number of rendered objects (top-level `kind:` lines) per fixture.
# Update these alongside any fixture values change.
expected_kinds() {
  case "$1" in
    minimal)  echo 3 ;;
    full)     echo 25 ;;
    stateful) echo 6 ;;
    daemon)   echo 3 ;;
    *)        echo "unknown fixture: $1" >&2; return 1 ;;
  esac
}

# Strip content that is nondeterministic under `helm template`: tlsSelfSigned
# generates a fresh throwaway cert (and a freshly computed not-after
# timestamp) on every offline render (its Secret lookup is empty without a
# cluster), so the tls Secret data lines and the platform/tls-not-after
# annotation are redacted.
normalize_render() {
  sed -E \
    -e 's/^(  (tls\.crt|tls\.key|ca\.crt): ).*/\1REDACTED/' \
    -e 's#^(    platform/tls-not-after: ).*#\1REDACTED#'
}

echo "==> helm lint $LIB"
helm lint "$LIB"

echo "==> reference schema parses"
if command -v jq >/dev/null 2>&1; then
  jq empty "$LIB/values.schema.reference.json" && echo "  values.schema.reference.json OK"
else
  echo "WARN: jq not installed - JSON parse check skipped (metaschema check below covers it when check-jsonschema is present)"
fi

have_kubeconform=0
if command -v kubeconform >/dev/null 2>&1; then
  have_kubeconform=1
elif [[ "${REQUIRE_KUBECONFORM:-0}" == "1" ]]; then
  echo "FAIL: kubeconform is required (REQUIRE_KUBECONFORM=1) but not installed"
  fail=1
else
  echo "WARN: kubeconform not installed — schema validation SKIPPED (set REQUIRE_KUBECONFORM=1 to fail instead)"
fi

have_check_jsonschema=0
if command -v check-jsonschema >/dev/null 2>&1; then
  have_check_jsonschema=1
elif [[ "${REQUIRE_CHECK_JSONSCHEMA:-0}" == "1" ]]; then
  echo "FAIL: check-jsonschema is required (REQUIRE_CHECK_JSONSCHEMA=1) but not installed"
  fail=1
else
  echo "WARN: check-jsonschema not installed - values schema validation SKIPPED (set REQUIRE_CHECK_JSONSCHEMA=1 to fail instead)"
fi

if [[ "$have_check_jsonschema" == "1" ]]; then
  echo "==> values schema: metaschema + fixture values"
  if check-jsonschema --check-metaschema "$LIB/values.schema.reference.json" >/dev/null; then
    echo "  OK: reference schema is a valid JSON Schema"
  else
    echo "  FAIL: reference schema failed metaschema validation"
    check-jsonschema --check-metaschema "$LIB/values.schema.reference.json" || true
    fail=1
  fi
  for fx in "${FIXTURES[@]}"; do
    if check-jsonschema --schemafile "$LIB/values.schema.reference.json" \
         "$REPO_ROOT/tests/fixtures/$fx/values.yaml" >/dev/null; then
      echo "  OK: fixture $fx values conform to the reference schema"
    else
      echo "  FAIL: fixture $fx values violate the reference schema:"
      check-jsonschema --schemafile "$LIB/values.schema.reference.json" \
        "$REPO_ROOT/tests/fixtures/$fx/values.yaml" || true
      fail=1
    fi
  done
fi

for fx in "${FIXTURES[@]}"; do
  want="$(expected_kinds "$fx")"

  echo "==> render matrix: $fx (expect $want objects)"
  for kv in "${KUBE_VERSIONS[@]}"; do
    if out=$("$RENDER" "$fx" --kube-version "$kv" 2>&1); then
      got=$(grep -c '^kind:' <<<"$out" || true)
      if [[ "$got" -eq "$want" ]]; then
        echo "  k8s $kv: OK ($got objects)"
      else
        echo "  k8s $kv: FAIL — rendered $got objects, expected $want (update expected_kinds if intentional)"
        fail=1
      fi

      if [[ "$have_kubeconform" == "1" ]]; then
        # Validate THIS version's own render (not the canonical golden render):
        # version-specific apiVersion negotiation must be schema-checked at the
        # version that produced it.
        if kc_out=$(kubeconform -strict -summary \
               -kubernetes-version "$kv.0" \
               -schema-location "$NATIVE_SCHEMA_LOCATION" \
               -schema-location "$CRD_SCHEMA_LOCATION" \
               <<<"$out" 2>&1); then
          printf '%s\n' "$kc_out"
        else
          printf '%s\n' "$kc_out"
          echo "  k8s $kv: FAIL — kubeconform"; fail=1
        fi
      fi
    else
      echo "  k8s $kv: FAIL"; echo "$out" | tail -5; fail=1
    fi
  done

  if ! raw=$("$RENDER" "$fx" --kube-version "$GOLDEN_KUBE_VERSION" 2>/dev/null); then
    echo "==> golden snapshot: $fx — FAIL (render failed)"; fail=1
    continue
  fi
  rendered=$(normalize_render <<<"$raw")

  echo "==> golden snapshot: $fx (k8s $GOLDEN_KUBE_VERSION)"
  if [[ "${UPDATE_GOLDEN:-0}" == "1" ]]; then
    mkdir -p "$GOLDEN_DIR"
    printf '%s\n' "$rendered" > "$GOLDEN_DIR/$fx.yaml"
    echo "  updated $GOLDEN_DIR/$fx.yaml"
  elif [[ ! -f "$GOLDEN_DIR/$fx.yaml" ]]; then
    echo "  FAIL: missing golden $GOLDEN_DIR/$fx.yaml (run: UPDATE_GOLDEN=1 scripts/lint-library.sh)"
    fail=1
  elif diff -u "$GOLDEN_DIR/$fx.yaml" <(printf '%s\n' "$rendered"); then
    echo "  OK: matches golden"
  else
    echo "  FAIL: rendered output drifted from golden (run: UPDATE_GOLDEN=1 scripts/lint-library.sh to accept)"
    fail=1
  fi
done

echo "==> negative render: CRDs must drop without force-assume (full fixture)"
neg=$("$RENDER" full --set capabilities.apiVersions=null 2>/dev/null)
if grep -qE '^kind: (Certificate|HTTPRoute|GRPCRoute|PeerAuthentication|AuthorizationPolicy|ServiceMonitor|PodMonitor)$' <<<"$neg"; then
  echo "  FAIL: a CRD-backed object rendered without a present API"; fail=1
else
  echo "  OK: CRD-backed objects skipped"
fi
if grep -qE '^\{\}\s*$' <<<"$neg"; then
  echo "  FAIL: empty {} document emitted"; fail=1
else
  echo "  OK: no empty documents"
fi

echo "==> updateStrategy compatibility"
# rollingUpdate is only valid when type is RollingUpdate. The library ships
# rollingUpdate defaults, so a consumer flipping only .type would otherwise get an
# object the API server rejects ("may not be specified when strategy type is ...").
# Each of these fixtures renders exactly one workload, so a bare grep for
# rollingUpdate over the whole render is a sound check.
check_no_rolling_update() {
  local fixture="$1" label="$2"; shift 2
  local out
  if out=$("$RENDER" "$fixture" "$@" 2>&1); then
    if grep -q 'rollingUpdate' <<<"$out"; then
      echo "  FAIL: $label still emits rollingUpdate — the API server would reject this object"; fail=1
    else
      echo "  OK: $label emits no rollingUpdate"
    fi
  else
    echo "  FAIL: render failed for $label"; echo "$out" | tail -3; fail=1
  fi
}
check_no_rolling_update minimal "Deployment strategy.type=Recreate" --set updateStrategy.type=Recreate
check_no_rolling_update stateful "StatefulSet updateStrategy.type=OnDelete" --set statefulSet.updateStrategy.type=OnDelete
check_no_rolling_update daemon "DaemonSet updateStrategy.type=OnDelete" --set daemonSet.updateStrategy.type=OnDelete

# ...and the stripping must not over-reach: the RollingUpdate default keeps its tuning.
if out=$("$RENDER" minimal 2>&1); then
  if grep -q 'maxSurge' <<<"$out"; then
    echo "  OK: default RollingUpdate strategy keeps its rollingUpdate block"
  else
    echo "  FAIL: default RollingUpdate strategy lost its rollingUpdate block"; fail=1
  fi
else
  echo "  FAIL: render failed for default updateStrategy check"; echo "$out" | tail -3; fail=1
fi

echo "==> image pin enforcement"
if out=$("$RENDER" minimal --set image.tag= 2>&1); then
  echo "  FAIL: render succeeded with no image.tag and no image.digest"; fail=1
elif grep -q "image.tag and image.digest are both empty" <<<"$out"; then
  echo "  OK: unpinned image fails with actionable message"
else
  echo "  FAIL: unpinned image failed without the expected message"; echo "$out" | tail -3; fail=1
fi

digest="sha256:1111111111111111111111111111111111111111111111111111111111111111"
if "$RENDER" minimal --set image.tag= --set image.digest="$digest" 2>/dev/null | \
   grep -q "image: docker.io/example/minimal@$digest"; then
  echo "  OK: digest-only pin renders repo@digest"
else
  echo "  FAIL: digest-only pin did not render repo@digest"; fail=1
fi

if out=$("$RENDER" full --set image.tag= --set image.digest="$digest" --set jobs.image.repository=example/other 2>&1); then
  echo "  FAIL: hook Job rendered with a foreign repo and no usable pin"; fail=1
elif grep -q "hook Job" <<<"$out"; then
  echo "  OK: hook Job with un-inheritable pin fails with actionable message"
else
  echo "  FAIL: hook Job failed without the expected message"; echo "$out" | tail -3; fail=1
fi

echo "==> schema enforcement (helm-side): invalid values must fail"
if out=$("$RENDER" minimal --set workload.type=deployment 2>&1); then
  echo "  FAIL: render succeeded with workload.type=deployment (schema not enforced)"; fail=1
elif grep -q "workload/type" <<<"$out"; then
  echo "  OK: lowercase workload.type rejected by values.schema.json"
else
  echo "  FAIL: render failed without a schema error"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --set image.tag=latest 2>&1); then
  echo "  FAIL: render succeeded with image.tag=latest"; fail=1
elif grep -q "image/tag" <<<"$out"; then
  echo "  OK: image.tag=latest rejected by values.schema.json"
else
  echo "  FAIL: render failed without a schema error"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" full --set networkPolicy.enabled=true --set 'networkPolicy.policyTypes[0]=Bogus' 2>&1); then
  echo "  FAIL: render succeeded with networkPolicy.policyTypes[0]=Bogus"; fail=1
elif grep -q "networkPolicy/policyTypes" <<<"$out"; then
  echo "  OK: invalid networkPolicy.policyTypes entry rejected by values.schema.json"
else
  echo "  FAIL: render failed without a schema error"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --set podSecurityContext.fsGroup=-1 2>&1); then
  echo "  FAIL: render succeeded with podSecurityContext.fsGroup=-1"; fail=1
elif grep -q "podSecurityContext/fsGroup" <<<"$out"; then
  echo "  OK: negative podSecurityContext.fsGroup rejected by values.schema.json"
else
  echo "  FAIL: render failed without a schema error"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --set 'containerSecurityContext.capabilities.drop[0]=all' 2>&1); then
  echo "  FAIL: render succeeded with containerSecurityContext.capabilities.drop[0]=all"; fail=1
elif grep -q "containerSecurityContext/capabilities/drop" <<<"$out"; then
  echo "  OK: lowercase capability name rejected by values.schema.json"
else
  echo "  FAIL: render failed without a schema error"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --set serviceAccount.name=Invalid_Name 2>&1); then
  echo "  FAIL: render succeeded with serviceAccount.name=Invalid_Name"; fail=1
elif grep -q "serviceAccount/name" <<<"$out"; then
  echo "  OK: non-RFC1123 serviceAccount.name rejected by values.schema.json"
else
  echo "  FAIL: render failed without a schema error"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --set ingress.hostname=INVALID_HOST 2>&1); then
  echo "  FAIL: render succeeded with ingress.hostname=INVALID_HOST"; fail=1
elif grep -q "ingress/hostname" <<<"$out"; then
  echo "  OK: non-RFC1123 ingress.hostname rejected by values.schema.json"
else
  echo "  FAIL: render failed without a schema error"; echo "$out" | tail -3; fail=1
fi

echo "==> posture guardrails"
# mTLS fail-closed: enabled with empty principals must fail with guidance.
# (--set key=null deletes the key from the coalesced values.)
if out=$("$RENDER" full --set mtls.allowedPrincipals=null 2>&1); then
  echo "  FAIL: render succeeded with mtls enabled and empty allowedPrincipals"; fail=1
elif grep -q "mtls.allowedPrincipals is empty" <<<"$out"; then
  echo "  OK: mtls with empty principals fails closed with actionable message"
else
  echo "  FAIL: mtls empty-principals failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# Explicit opt-in restores the wildcard principal.
if out=$("$RENDER" full --set mtls.allowedPrincipals=null --set mtls.allowAllPrincipals=true 2>&1) &&
   grep -q 'cluster.local/ns/\*/sa/\*' <<<"$out"; then
  echo "  OK: mtls.allowAllPrincipals=true renders the wildcard principal"
else
  echo "  FAIL: mtls.allowAllPrincipals=true did not render the wildcard principal"; fail=1
fi

# Cluster-scoped extraObjects are refused unless explicitly allowed.
if out=$("$RENDER" full --set allowClusterScopedExtras=false 2>&1); then
  echo "  FAIL: render succeeded with cluster-scoped extraObjects and gate=false"; fail=1
elif grep -q 'cluster-scoped Kind "ClusterRole"' <<<"$out"; then
  echo "  OK: cluster-scoped extraObjects refused, message names ClusterRole"
else
  echo "  FAIL: gate=false failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# secret.existingSecret conflicts with inline material.
if out=$("$RENDER" stateful --set secret.existingSecret=preexisting 2>&1); then
  echo "  FAIL: render succeeded with secret.existingSecret + secret.stringData"; fail=1
elif grep -q "secret.existingSecret is mutually exclusive" <<<"$out"; then
  echo "  OK: existingSecret + inline stringData rejected"
else
  echo "  FAIL: existingSecret conflict failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# secret.existingSecret suppresses the chart-managed Secret.
if out=$("$RENDER" stateful --set secret.existingSecret=preexisting \
  --set secret.stringData=null 2>&1); then
  secret_count=$(grep -c '^kind: Secret' <<<"$out" || true)
  if [[ "$secret_count" -eq 0 ]]; then
    echo "  OK: existingSecret suppresses the chart-managed Secret"
  else
    echo "  FAIL: chart still rendered a Secret with secret.existingSecret set"; fail=1
  fi
else
  echo "  FAIL: render failed while checking secret.existingSecret suppression"; echo "$out" | tail -3; fail=1
fi

echo "==> container hardening posture: user-supplied containers cannot render unhardened"
# Pod Security Standards are evaluated PER CONTAINER, so a sidecar/initContainer/
# CronJob container passed through verbatim without a securityContext defeats the
# library's restricted posture for the whole pod. Every user container must inherit
# containerSecurityContext as a default, with its own keys winning on conflict.
#
# `allowPrivilegeEscalation: false` comes only from containerSecurityContext
# (podSecurityContext has no such field), so its occurrence count is exactly the
# number of hardened containers in a render.
sidecar_json='[{"name":"probe","image":"docker.io/library/busybox:1.36.1","command":["sh","-c","sleep infinity"]}]'
check_hardened_containers() {
  local fixture="$1" label="$2" want="$3"; shift 3
  local out got
  if out=$("$RENDER" "$fixture" "$@" 2>&1); then
    got=$(grep -c 'allowPrivilegeEscalation: false' <<<"$out" || true)
    if [[ "$got" -eq "$want" ]]; then
      echo "  OK: $label — $got/$want containers hardened"
    else
      echo "  FAIL: $label — $got of $want containers carry containerSecurityContext; a user container renders unhardened"; fail=1
    fi
  else
    echo "  FAIL: render failed for $label"; echo "$out" | tail -3; fail=1
  fi
}
# main app container + the bare passthrough container = 2 hardened containers.
check_hardened_containers minimal "bare sidecar" 2 \
  --set sidecars.enabled=true --set-json "sidecars.containers=$sidecar_json"
check_hardened_containers minimal "bare initContainer" 2 \
  --set initContainers.enabled=true --set-json "initContainers.containers=$sidecar_json"
check_hardened_containers minimal "bare cronJob.containers" 2 \
  --set cronJob.enabled=true --set-json "cronJob.containers=$sidecar_json"
# ...plus the hook Job's own main container = 3.
check_hardened_containers minimal "bare hook-Job sidecar" 3 \
  --set jobs.preInstall.enabled=true --set jobs.preInstall.script='echo hi' \
  --set jobs.preInstall.sidecars.enabled=true \
  --set-json "jobs.preInstall.sidecars.containers=$sidecar_json"
# The escape hatch survives: disabling containerSecurityContext injects nothing.
check_hardened_containers minimal "containerSecurityContext.enabled=false" 0 \
  --set containerSecurityContext.enabled=false \
  --set sidecars.enabled=true --set-json "sidecars.containers=$sidecar_json"

# Merge direction (sprig trap): a container's OWN securityContext key must beat the
# library default, and the default must not be mutated for containers behind it.
# The daemon fixture renders metrics-proxy (runAsUser 65532) ahead of a bare
# log-shipper, plus init-wait and the main container on the default 1001.
if out=$("$RENDER" daemon 2>&1); then
  overridden=$(grep -c 'runAsUser: 65532' <<<"$out" || true)
  defaulted=$(grep -c 'runAsUser: 1001' <<<"$out" || true)
  if [[ "$overridden" -eq 1 && "$defaulted" -eq 3 ]]; then
    echo "  OK: container securityContext override wins, library default unmutated"
  else
    echo "  FAIL: expected 1 overridden runAsUser and 3 defaulted, got $overridden/$defaulted — merge direction or default-map mutation is wrong"; fail=1
  fi
else
  echo "  FAIL: render failed for securityContext merge-direction check"; echo "$out" | tail -3; fail=1
fi

echo "==> hook Job dependency ordering (fresh install)"
# Helm creates a release's normal resources only AFTER the pre-install hooks have
# run. Anything the pre-install hook Job mounts or references must therefore be a
# hook itself, at a strictly lower weight — otherwise a fresh `helm install` hangs
# with the hook pod unable to mount its script volume, or rejected by the
# ServiceAccount admission controller. `helm template` executes no hooks, so the
# goldens can never catch this: assert the annotations directly.
#
# Prints "<kind>/<metadata.name> <hook-events|nohook> <hook-weight|noweight>" per
# document (the hook ServiceAccount and the hook Job share a name, so the kind is
# part of the key).
hook_table() {
  awk '
    function flush() {
      if (nm != "") print kd "/" nm, (hk == "" ? "nohook" : hk), (wt == "" ? "noweight" : wt)
      kd = ""; nm = ""; hk = ""; wt = ""
    }
    /^---[[:space:]]*$/ { flush(); next }
    /^kind: / { kd = $2 }
    /^  name: / && nm == "" { nm = $2 }
    /^    helm\.sh\/hook:/ { hk = $2 }
    /^    helm\.sh\/hook-weight:/ { wt = $2; gsub(/"/, "", wt) }
    END { flush() }
  '
}
hook_weight_of() {
  awk -v key="$1" '$1 == key && $2 == "pre-install,pre-upgrade" { print $3 }'
}
check_hook_ordering() {
  local label="$1"; shift
  local out table job_w cm_w sa_w job_sa
  if ! out=$("$RENDER" full "$@" 2>&1); then
    echo "  FAIL: render failed for $label"; echo "$out" | tail -3; fail=1; return
  fi
  table=$(hook_table <<<"$out")
  job_w=$(hook_weight_of "Job/t-full-preinstall" <<<"$table")
  cm_w=$(hook_weight_of "ConfigMap/t-full-preinstall-script" <<<"$table")
  sa_w=$(hook_weight_of "ServiceAccount/t-full-preinstall" <<<"$table")
  if [[ -z "$job_w" || "$job_w" == "noweight" ]]; then
    echo "  FAIL: $label — the pre-install Job lost its hook annotations"; fail=1
  elif [[ -z "$cm_w" || "$cm_w" == "noweight" ]]; then
    echo "  FAIL: $label — the pre-install script ConfigMap is not a pre-install hook; the hook pod cannot mount it on a fresh install"; fail=1
  elif [[ "$cm_w" -ge "$job_w" ]]; then
    echo "  FAIL: $label — script ConfigMap weight $cm_w is not lower than the Job's $job_w; Helm may create it after the hook pod"; fail=1
  elif [[ -z "$sa_w" || "$sa_w" -ge "$job_w" ]]; then
    echo "  FAIL: $label — the hook ServiceAccount is missing or not ordered ahead of the Job (weight $sa_w vs $job_w)"; fail=1
  else
    job_sa=$(awk '/^      serviceAccountName: t-full-preinstall$/ { n++ } END { print n + 0 }' <<<"$out")
    if [[ "$job_sa" -ne 1 ]]; then
      echo "  FAIL: $label — the pre-install Job does not reference the hook ServiceAccount"; fail=1
    else
      echo "  OK: $label — script ConfigMap ($cm_w) and hook ServiceAccount ($sa_w) both precede the Job ($job_w)"
    fi
  fi
}
check_hook_ordering "default hook weights"
# A consumer-tuned hookWeight must carry its dependencies with it, not strand them.
check_hook_ordering "jobs.preInstall.hookWeight=-20" --set jobs.preInstall.hookWeight=-20

# The post-install script ConfigMap must stay a NORMAL resource: post-install hooks
# run after the normal resources exist, and hook-annotating it would orphan it from
# the release (Helm does not track hook resources).
if out=$("$RENDER" full --set jobs.postInstall.enabled=true --set jobs.postInstall.script='echo hi' 2>&1); then
  post_hk=$(hook_table <<<"$out" | awk '$1 == "ConfigMap/t-full-postinstall-script" { print $2 }')
  if [[ "$post_hk" == "nohook" ]]; then
    echo "  OK: post-install script ConfigMap stays a release-tracked normal resource"
  else
    echo "  FAIL: post-install script ConfigMap carries hook annotations ($post_hk) — it would be orphaned from the release"; fail=1
  fi
else
  echo "  FAIL: render failed for post-install script ConfigMap check"; echo "$out" | tail -3; fail=1
fi

echo "==> NOTES warnings (SEC-3): discouraged secret/ingress paths"
# platform.notes only renders via `helm install`/`helm upgrade` (including
# --dry-run), never `helm template` — see _notes.tpl:5-8. --dry-run=client
# avoids any live cluster requirement.
notes_of() {
  local fixture="$1"; shift
  local dir="$REPO_ROOT/tests/fixtures/$fixture"
  cp "$LIB/values.schema.reference.json" "$dir/values.schema.json"
  helm dependency update "$dir" >/dev/null 2>&1
  helm install notes-check "$dir" --dry-run=client "$@"
}

# secret.enabled with inline stringData (stateful fixture already sets this).
if out=$(notes_of stateful 2>&1); then
  if grep -q "secret.stringData/secret.data contain plaintext secret material" <<<"$out"; then
    echo "  OK: secret.stringData fixture emits the plaintext-secret NOTES warning"
  else
    echo "  FAIL: secret.stringData fixture did not emit the expected NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for stateful fixture"; echo "$out" | tail -5; fail=1
fi

# ingress.secrets non-empty (full fixture has ingress.enabled=true already).
if out=$(notes_of full \
  --set 'ingress.secrets[0].name=app-tls' \
  --set 'ingress.secrets[0].certificate=dummy-cert' \
  --set 'ingress.secrets[0].key=dummy-key' 2>&1); then
  if grep -q "ingress.secrets contains inline TLS cert/key material" <<<"$out"; then
    echo "  OK: ingress.secrets override emits the inline-TLS NOTES warning"
  else
    echo "  FAIL: ingress.secrets override did not emit the expected NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for full fixture with ingress.secrets"; echo "$out" | tail -5; fail=1
fi

# Existing warnings unaffected: minimal fixture has no secret/ingress config, so no WARNING at all.
if out=$(notes_of minimal 2>&1); then
  if grep -q "WARNING:" <<<"$out"; then
    echo "  FAIL: minimal fixture unexpectedly emitted a NOTES warning"; echo "$out" | tail -5; fail=1
  else
    echo "  OK: minimal fixture emits no NOTES warnings"
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal fixture"; echo "$out" | tail -5; fail=1
fi

# Invariant: `helm template` never includes NOTES content.
if out=$("$RENDER" stateful 2>&1); then
  if grep -q "WARNING:\|^NOTES:" <<<"$out"; then
    echo "  FAIL: helm template unexpectedly rendered NOTES content"; fail=1
  else
    echo "  OK: helm template output excludes NOTES content"
  fi
else
  echo "  FAIL: helm template failed for stateful fixture"; echo "$out" | tail -5; fail=1
fi

echo "==> NOTES: Kinds enabled in values but skipped by capability gating"
# A CRD-backed Kind whose API is neither served nor force-assumed renders NOTHING.
# Without a warning the operator believes cert-manager Certificates or ServiceMonitors
# deployed when they did not — a silent security/observability gap.
if out=$(notes_of minimal \
  --set certificate.enabled=true --set certificate.issuer=letsencrypt \
  --set serviceMonitor.enabled=true 2>&1); then
  if grep -q "SKIPPED KINDS" <<<"$out" &&
     grep -q "Certificate (tried cert-manager.io/v1)" <<<"$out" &&
     grep -q "ServiceMonitor (tried monitoring.coreos.com/v1)" <<<"$out"; then
    echo "  OK: enabled-but-skipped Kinds are named in a NOTES warning with the apiVersions tried"
  else
    echo "  FAIL: enabled-but-skipped Certificate/ServiceMonitor produced no naming NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal fixture with gated Kinds enabled"; echo "$out" | tail -5; fail=1
fi

# Force-assuming the APIs closes the gap: the objects render, so there is nothing to warn about.
if out=$(notes_of minimal \
  --set certificate.enabled=true --set certificate.issuer=letsencrypt \
  --set serviceMonitor.enabled=true \
  --set 'capabilities.apiVersions[0]=cert-manager.io/v1' \
  --set 'capabilities.apiVersions[1]=monitoring.coreos.com/v1' 2>&1); then
  if grep -q "SKIPPED KINDS" <<<"$out"; then
    echo "  FAIL: force-assumed APIs still reported as skipped"; echo "$out" | tail -5; fail=1
  else
    echo "  OK: force-assumed apiVersions suppress the skipped-Kind warning"
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal fixture with force-assumed apiVersions"; echo "$out" | tail -5; fail=1
fi

# No false positives: the full fixture enables all five gated features AND force-assumes
# every one of their APIs, so it must stay silent.
if out=$(notes_of full 2>&1); then
  if grep -q "SKIPPED KINDS" <<<"$out"; then
    echo "  FAIL: full fixture warns about skipped Kinds it actually renders"; echo "$out" | tail -5; fail=1
  else
    echo "  OK: full fixture (all gated APIs force-assumed) emits no skipped-Kind warning"
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for full fixture"; echo "$out" | tail -5; fail=1
fi

# Anti-drift: the emitter gates and the warning must read the SAME table. Every
# capability gate in _app.yaml goes through platform.capabilities.gateOpen, and the
# gatedKinds table has exactly one row per gate. A new gated feature added to one
# side only would fail here instead of silently losing its warning.
gate_sites=$(grep -c 'platform.capabilities.gateOpen' "$LIB/templates/_app.yaml" || true)
gated_rows=$(sed -n '/define "platform.capabilities.gatedKinds"/,/^{{- end -}}/p' "$LIB/templates/_capabilities.tpl" |
  grep -cE '^[A-Za-z]+: [A-Za-z]+$' || true)
raw_gates=$(grep -c 'platform.capabilities.apiVersionFor' "$LIB/templates/_app.yaml" || true)
if [[ "$gate_sites" -gt 0 && "$gate_sites" -eq "$gated_rows" && "$raw_gates" -eq 0 ]]; then
  echo "  OK: all $gate_sites capability gates in _app.yaml are driven by the shared gatedKinds table"
else
  echo "  FAIL: capability gates ($gate_sites) and gatedKinds rows ($gated_rows) disagree, or _app.yaml still gates on a raw apiVersionFor ($raw_gates) — notes and emitters can drift"; fail=1
fi

echo "==> selector stability"
# Selectors land in immutable fields (workload spec.selector) and in the Service/PDB
# selectors. They must contain ONLY name/instance/component. A user-settable value
# such as commonLabels leaking in here means changing that label orphans the running
# pods — and on workloads it makes helm upgrade fail outright.
if out=$("$RENDER" minimal --set service.enabled=true --set commonLabels.canary=leak 2>&1); then
  # Every selector/matchLabels block must be free of the canary label. Extract each
  # selector block (selector: or matchLabels: through the next dedent) and grep it.
  leaked=$(awk '
    /^[[:space:]]*(selector|matchLabels):[[:space:]]*$/ { depth = match($0, /[^ ]/); inblk = 1; next }
    inblk {
      d = match($0, /[^ ]/)
      if (d <= depth || $0 ~ /^[[:space:]]*$/) { inblk = 0; next }
      print
    }' <<<"$out" | grep -c 'canary' || true)
  if [ "$leaked" -eq 0 ]; then
    echo "  OK: commonLabels do not leak into any selector"
  else
    echo "  FAIL: commonLabels leaked into $leaked selector line(s) — changing them would orphan pods"; fail=1
  fi
else
  echo "  FAIL: render failed for selector-stability check"; echo "$out" | tail -3; fail=1
fi

# The Service and PDB select the main workload only. CronJob and hook-Job pods carry
# an identical name+instance pair, so without a distinct component they would be
# matched too — routing live traffic to batch pods and skewing the disruption budget.
if out=$("$RENDER" full 2>&1); then
  cron_component=$(grep -c 'app.kubernetes.io/component: cronjob' <<<"$out" || true)
  hook_component=$(grep -c 'app.kubernetes.io/component: preinstall' <<<"$out" || true)
  if [ "$cron_component" -gt 0 ] && [ "$hook_component" -gt 0 ]; then
    echo "  OK: CronJob and hook-Job pods carry a distinct component label"
  else
    echo "  FAIL: CronJob/hook-Job pods are not distinguished from the main workload"; fail=1
  fi
else
  echo "  FAIL: render failed for component-separation check"; echo "$out" | tail -3; fail=1
fi

echo "==> TLS mechanism collision"
# certificate + tlsSelfSigned both target the <fullname>-tls Secret and collide.
# (full fixture already has certificate.enabled=true.)
if out=$("$RENDER" full --set tlsSelfSigned.enabled=true 2>&1); then
  echo "  FAIL: render succeeded with certificate.enabled and tlsSelfSigned.enabled both true"; fail=1
elif grep -q "certificate.enabled and tlsSelfSigned.enabled are both true" <<<"$out"; then
  echo "  OK: certificate + tlsSelfSigned collision rejected"
else
  echo "  FAIL: certificate/tlsSelfSigned collision failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if [[ $fail -eq 0 ]]; then echo "==> PASS"; else echo "==> FAIL"; fi
exit $fail
