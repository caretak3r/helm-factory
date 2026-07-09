#!/usr/bin/env bash
# =============================================================================
# lint-library.sh — validation gate for the pure platform-library chart.
#
# A library chart is not installable, so we validate it through the test
# consumer fixtures: helm lint the library, render each fixture across the
# supported Kubernetes version range with expected-object-count assertions,
# diff each fixture's canonical render against its committed golden snapshot,
# validate every rendered object with kubeconform (native + CRD schemas,
# across the version matrix), run a negative render proving CRD objects drop
# when their API is absent, enforce image pinning, and validate the values
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
FIXTURES=(minimal full stateful daemon)
KUBE_VERSIONS=(1.31 1.32 1.33 1.34 1.35 1.36)
GOLDEN_KUBE_VERSION=1.31   # canonical version for golden snapshots
KUBECONFORM_CACHE="${TMPDIR:-/tmp}/kubeconform-schema-cache"
# CRD schemas: the datreeio CRDs-catalog covers cert-manager, Gateway API,
# Prometheus Operator, and Istio — every CRD-backed Kind the library emits.
CRD_SCHEMA_LOCATION='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
fail=0

# Expected number of rendered objects (top-level `kind:` lines) per fixture.
# Update these alongside any fixture values change.
expected_kinds() {
  case "$1" in
    minimal)  echo 3 ;;
    full)     echo 24 ;;
    stateful) echo 6 ;;
    daemon)   echo 3 ;;
    *)        echo "unknown fixture: $1" >&2; return 1 ;;
  esac
}

# Strip content that is nondeterministic under `helm template`: tlsSelfSigned
# generates a fresh throwaway cert on every offline render (its Secret lookup
# is empty without a cluster), so the tls Secret data lines are redacted.
normalize_render() {
  sed -E 's/^(  (tls\.crt|tls\.key|ca\.crt): ).*/\1REDACTED/'
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
  mkdir -p "$KUBECONFORM_CACHE"
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

  if [[ "$have_kubeconform" == "1" ]]; then
    echo "==> kubeconform: $fx"
    for kv in "${KUBE_VERSIONS[@]}"; do
      if ! kubeconform -strict -summary \
             -kubernetes-version "$kv.0" \
             -schema-location default \
             -schema-location "$CRD_SCHEMA_LOCATION" \
             -cache "$KUBECONFORM_CACHE" \
             <<<"$raw"; then
        echo "  FAIL: kubeconform against k8s $kv.0"; fail=1
      fi
    done
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

if [[ $fail -eq 0 ]]; then echo "==> PASS"; else echo "==> FAIL"; fi
exit $fail
