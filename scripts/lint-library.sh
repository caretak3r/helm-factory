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
#   FIXTURES=minimal scripts/lint-library.sh       # fast local loop: subset of fixtures
#   FIXTURES="full stateful" KUBE_VERSIONS=1.36 scripts/lint-library.sh  # subset of both
#   ALLOW_MISSING_VALIDATORS=1 scripts/lint-library.sh  # explicit degraded run, see below
#
# FIXTURES and KUBE_VERSIONS accept space-separated subsets for a fast local
# feedback loop; both default to the full CI matrix (all four fixtures × the
# vendored k8s window from scripts/lib/schema-manifest.sh), so a bare
# invocation — and CI — is unchanged. A subset run covers the per-fixture
# legs only: values validation, render matrix, kubeconform, and golden diffs
# (goldens always render at GOLDEN_KUBE_VERSION regardless of KUBE_VERSIONS,
# and UPDATE_GOLDEN only rewrites the selected fixtures' goldens). The
# guardrail and negative-render suite is SKIPPED in subset mode (it exercises
# fixed fixture+version combinations outside any slice) and the run ends
# "==> PASS (subset)" so it can never masquerade as full-gate evidence — run
# the bare gate before push. KUBE_VERSIONS entries must be inside the vendored
# schema window; anything else has no kubeconform schemas and fails fast here
# rather than confusingly mid-run.
#
# A missing kubeconform/check-jsonschema binary FAILS the gate by default —
# it would otherwise silently downgrade every schema-validation leg to a
# thin no-op PASS. REQUIRE_KUBECONFORM=1/REQUIRE_CHECK_JSONSCHEMA=1 (CI's
# knobs) always fail on a missing tool. Everywhere else, ALLOW_MISSING_VALIDATORS=1
# is the one explicit escape hatch for a deliberately degraded run (e.g. a
# workstation without kubeconform installed yet): the missing-tool FAIL
# downgrades to a WARN, and the run says so in its own final line —
# "==> DEGRADED PASS (missing: ...)" (or "==> DEGRADED PASS (subset, missing:
# ...)") — which never collides with the bare "==> PASS" a full-coverage run
# produces, so a degraded run can never masquerade as gate evidence.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/platform-library"
RENDER="$REPO_ROOT/tests/render.sh"
GOLDEN_DIR="$REPO_ROOT/tests/golden"
SCHEMA_DIR="$REPO_ROOT/tests/schemas"
# Capture env overrides (see usage above) before the defaults below and the
# manifest source clobber the variables.
FIXTURES_ENV="${FIXTURES:-}"
KUBE_VERSIONS_ENV="${KUBE_VERSIONS:-}"

FIXTURES=(minimal full stateful daemon)
GOLDEN_KUBE_VERSION=1.34   # canonical version for golden snapshots

# shellcheck source=scripts/lib/schema-manifest.sh
source "$REPO_ROOT/scripts/lib/schema-manifest.sh"   # sets KUBE_VERSIONS (full vendored window)

if [[ -n "$FIXTURES_ENV" ]]; then
  read -ra FIXTURES <<<"$FIXTURES_ENV"
  for fx in "${FIXTURES[@]}"; do
    if [[ ! -d "$REPO_ROOT/tests/fixtures/$fx" ]]; then
      echo "FATAL: unknown fixture '$fx' in \$FIXTURES — valid: minimal full stateful daemon" >&2
      exit 2
    fi
  done
fi

if [[ -n "$KUBE_VERSIONS_ENV" ]]; then
  KUBE_VERSIONS_ALL=("${KUBE_VERSIONS[@]}")
  read -ra KUBE_VERSIONS <<<"$KUBE_VERSIONS_ENV"
  for kv in "${KUBE_VERSIONS[@]}"; do
    if [[ " ${KUBE_VERSIONS_ALL[*]} " != *" $kv "* ]]; then
      echo "FATAL: KUBE_VERSIONS entry '$kv' has no vendored schemas — supported: ${KUBE_VERSIONS_ALL[*]} (see scripts/lib/schema-manifest.sh)" >&2
      exit 2
    fi
  done
fi

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
    full)     echo 37 ;;
    stateful) echo 8 ;;
    daemon)   echo 7 ;;
    *)        echo "unknown fixture: $1" >&2; return 1 ;;
  esac
}

# Strip content that is nondeterministic under `helm template`: tlsSelfSigned
# generates a fresh throwaway cert (and a freshly computed not-after
# timestamp) on every offline render (its Secret lookup is empty without a
# cluster), so the tls Secret data lines and the platform/tls-not-after
# annotation are redacted. webhooks' cert Secret follows the identical
# whole-Secret lookup/reuse idiom (same offline-always-regenerates story) and
# adds a ca.key sibling key, so it rides the same pattern rather than the
# separate platform/generated marker below — house-consistent with
# tlsSelfSigned, whose Secrets also don't carry that marker. The caBundle
# stamped into every ValidatingWebhookConfiguration/MutatingWebhookConfiguration
# item is that same freshly-generated ca.crt, so it is redacted too.
# generatedSecrets is the same story for arbitrary credential material
# (random passwords, bcrypt htpasswd hashes): every Secret it emits carries
# annotation `platform/generated: "true"`, so the awk pass below redacts
# every `data:` line of any document carrying that annotation, doc-scoped so
# unrelated Secrets/ConfigMaps are untouched.
normalize_render() {
  sed -E \
    -e 's/^(  (tls\.crt|tls\.key|ca\.crt|ca\.key): ).*/\1REDACTED/' \
    -e 's/^(      caBundle: ).*/\1REDACTED/' \
    -e 's#^(    platform/tls-not-after: ).*#\1REDACTED#' \
  | awk '
      function flush() {
        in_data = 0
        for (i = 1; i <= n; i++) {
          line = buf[i]
          if (marked && line == "data:") { in_data = 1; print line; continue }
          if (marked && in_data && match(line, /^  [A-Za-z0-9._-]+: /)) {
            print substr(line, 1, RLENGTH) "REDACTED"; continue
          }
          if (in_data && line !~ /^  /) { in_data = 0 }
          print line
        }
        n = 0; marked = 0
      }
      /^---[[:space:]]*$/ { flush(); print; next }
      {
        n++; buf[n] = $0
        if ($0 == "    platform/generated: \"true\"") marked = 1
      }
      END { flush() }
    '
}

# Shared per-document extractor: prints the rendered document whose kind is $1
# and metadata.name is $2, reading a multi-doc render on stdin. kind+name is
# the only unique per-document key in a render — objects of different Kinds
# legitimately share a name (the pre-install hook ServiceAccount and hook Job
# are both "<fullname>-preinstall"), so per-document assertions must never key
# on name alone: a name-only extractor silently reads whichever same-named
# document the render emits first (helm-factory-4b1).
doc_of() {
  awk -v kind="$1" -v name="$2" '
    function flush() {
      if (kd == kind && nm == name) { printf "%s", buf; found = 1 }
      buf = ""; kd = ""; nm = ""
    }
    /^---[[:space:]]*$/ { flush(); if (found) exit; next }
    { buf = buf $0 "\n" }
    /^kind: / { kd = $2 }
    /^  name: / && nm == "" { nm = $2 }
    END { flush() }
  '
}

# validate_render <label> <rendered-yaml> [kube-version] [allow-missing]
# Schema-checks a successful guardrail render with kubeconform against the
# vendored schemas. MUST be called from the parent shell (never inside a
# $(...) substitution) so fail=1 propagates. Pass allow-missing=1 ONLY for
# legs that render a Kind the vendored catalog cannot supply a schema for
# (documented at the call site), never to paper over a real schema mismatch.
validate_render() {
  local label="$1" rendered="$2" kv="${3:-$GOLDEN_KUBE_VERSION}" allow_missing="${4:-0}"
  if [[ "$have_kubeconform" != "1" ]]; then return 0; fi
  local kc_extra_args=()
  if [[ "$allow_missing" == "1" ]]; then kc_extra_args=(-ignore-missing-schemas); fi
  local kc_out
  if kc_out=$(kubeconform -strict -summary \
        -kubernetes-version "$kv.0" \
        -schema-location "$NATIVE_SCHEMA_LOCATION" \
        -schema-location "$CRD_SCHEMA_LOCATION" \
        "${kc_extra_args[@]}" <<<"$rendered" 2>&1); then
    :
  else
    printf '%s\n' "$kc_out"
    echo "  FAIL: kubeconform ($label)"; fail=1
  fi
}

# check_golden <fixture> <kube-version> <rendered> — diffs a normalized
# render against its golden. Uses tests/golden/<fixture>@<kv>.yaml when
# present (the escape hatch for a future K8s version whose render
# legitimately diverges), otherwise the base tests/golden/<fixture>.yaml —
# a free cross-version identity assertion today because 1.34/1.35/1.36
# render byte-identically. UPDATE_GOLDEN=1 writes ONLY the base golden (at
# GOLDEN_KUBE_VERSION) and refreshes an override file that ALREADY exists;
# it never creates a new override — creating one is a deliberate manual act
# (cp the diverging version's normalized render, with review). MUST be
# called from the parent shell (never inside $(...)) so fail=1 propagates.
check_golden() {
  local fx="$1" kv="$2" rendered="$3"
  local override="$GOLDEN_DIR/$fx@$kv.yaml"
  local golden="$GOLDEN_DIR/$fx.yaml" label="base ($fx.yaml)"
  if [[ -f "$override" ]]; then
    golden="$override"; label="override ($fx@$kv.yaml)"
  fi

  if [[ "${UPDATE_GOLDEN:-0}" == "1" ]]; then
    if [[ "$kv" == "$GOLDEN_KUBE_VERSION" ]]; then
      mkdir -p "$GOLDEN_DIR"
      printf '%s\n' "$rendered" > "$GOLDEN_DIR/$fx.yaml"
      echo "  k8s $kv: updated $GOLDEN_DIR/$fx.yaml"
      return 0
    elif [[ -f "$override" ]]; then
      printf '%s\n' "$rendered" > "$override"
      echo "  k8s $kv: updated $override"
      return 0
    fi
    # Non-canonical version with no existing override: fall through to a
    # plain diff below — UPDATE_GOLDEN never creates a new override file.
  fi

  if [[ ! -f "$golden" ]]; then
    echo "  k8s $kv: FAIL — missing golden $golden"
    fail=1
  elif diff -u "$golden" <(printf '%s\n' "$rendered"); then
    echo "  k8s $kv: OK (matches $label)"
  else
    echo "  k8s $kv: FAIL — $fx at k8s $kv drifted from $label (run UPDATE_GOLDEN=1 to accept, or if this is legitimate cross-version divergence create tests/golden/$fx@$kv.yaml manually from this render)"
    fail=1
  fi
}

echo "==> helm lint $LIB"
helm lint "$LIB"

echo "==> reference schema parses"
if command -v jq >/dev/null 2>&1; then
  jq empty "$LIB/values.schema.reference.json" && echo "  values.schema.reference.json OK"
else
  echo "WARN: jq not installed - JSON parse check skipped (metaschema check below covers it when check-jsonschema is present)"
fi

# A missing validator must never silently downgrade a run to a thin PASS: by
# default a missing tool FAILS the gate. ALLOW_MISSING_VALIDATORS=1 is the
# explicit escape hatch for a deliberately degraded run (e.g. a workstation
# without kubeconform installed yet) — it downgrades the missing-tool FAIL to
# a WARN, but the run's own final line says so ("==> DEGRADED PASS
# (missing: ...)"), never the bare "==> PASS" a full-coverage run gets.
# REQUIRE_KUBECONFORM/REQUIRE_CHECK_JSONSCHEMA (CI's normal knobs) always win:
# they FAIL regardless of ALLOW_MISSING_VALIDATORS.
degraded=""

have_kubeconform=0
if command -v kubeconform >/dev/null 2>&1; then
  have_kubeconform=1
elif [[ "${REQUIRE_KUBECONFORM:-0}" == "1" ]]; then
  echo "FAIL: kubeconform is required (REQUIRE_KUBECONFORM=1) but not installed"
  fail=1
elif [[ "${ALLOW_MISSING_VALIDATORS:-0}" == "1" ]]; then
  echo "WARN: kubeconform not installed — schema validation SKIPPED (ALLOW_MISSING_VALIDATORS=1)"
  degraded="${degraded}kubeconform "
else
  echo "FAIL: kubeconform not installed — schema validation would be silently skipped. Install kubeconform, or set ALLOW_MISSING_VALIDATORS=1 for an explicit degraded run (ends '==> DEGRADED PASS', never '==> PASS')."
  fail=1
fi

have_check_jsonschema=0
if command -v check-jsonschema >/dev/null 2>&1; then
  have_check_jsonschema=1
elif [[ "${REQUIRE_CHECK_JSONSCHEMA:-0}" == "1" ]]; then
  echo "FAIL: check-jsonschema is required (REQUIRE_CHECK_JSONSCHEMA=1) but not installed"
  fail=1
elif [[ "${ALLOW_MISSING_VALIDATORS:-0}" == "1" ]]; then
  echo "WARN: check-jsonschema not installed — values schema validation SKIPPED (ALLOW_MISSING_VALIDATORS=1)"
  degraded="${degraded}check-jsonschema "
else
  echo "FAIL: check-jsonschema not installed — values schema validation would be silently skipped. Install check-jsonschema, or set ALLOW_MISSING_VALIDATORS=1 for an explicit degraded run (ends '==> DEGRADED PASS', never '==> PASS')."
  fail=1
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

      # Pin every version's render to the golden, not just GOLDEN_KUBE_VERSION
      # (see check_golden above): a version-specific render drift is a real
      # regression the gate should catch, not something only the canonical
      # version happens to see.
      check_golden "$fx" "$kv" "$(normalize_render <<<"$out")"
    else
      echo "  k8s $kv: FAIL"; echo "$out" | tail -5; fail=1
    fi
  done
done

# Fast local loop (hf-3p0): a FIXTURES/KUBE_VERSIONS subset covers only the
# per-fixture legs above. The guardrail and negative-render suite below
# exercises fixed fixture+version combinations regardless of the requested
# slice, so it is skipped outright rather than silently half-run — and the
# summary line says so. The bare invocation (and CI) always runs it in full.
if [[ -n "$FIXTURES_ENV" || -n "$KUBE_VERSIONS_ENV" ]]; then
  echo "==> guardrail + negative-render suite: SKIPPED (FIXTURES/KUBE_VERSIONS subset — run bare scripts/lint-library.sh for the full gate)"
  if [[ $fail -ne 0 ]]; then
    echo "==> FAIL"
  elif [[ -n "$degraded" ]]; then
    echo "==> DEGRADED PASS (subset, missing: ${degraded% })"
  else
    echo "==> PASS (subset)"
  fi
  exit $fail
fi

echo "==> negative render: CRDs must drop without force-assume (full fixture)"
# Guarded so a render failure here reports and lets the remaining gate run,
# instead of set -e aborting the whole script (and the guardrail suite below)
# with stderr discarded. Keep stderr for a diagnosable message.
if ! neg=$("$RENDER" full --set capabilities.apiVersions=null 2>&1); then
  echo "  FAIL: negative render itself failed"; echo "$neg" | tail -5; fail=1
else
  validate_render "CRD-drop (full, no force-assume)" "$neg"
  if grep -qE '^kind: (Certificate|HTTPRoute|GRPCRoute|PeerAuthentication|AuthorizationPolicy|ServiceMonitor|PodMonitor|PrometheusRule|VerticalPodAutoscaler)$' <<<"$neg"; then
    echo "  FAIL: a CRD-backed object rendered without a present API"; fail=1
  else
    echo "  OK: CRD-backed objects skipped"
  fi
  if grep -qE '^\{\}\s*$' <<<"$neg"; then
    echo "  FAIL: empty {} document emitted"; fail=1
  else
    echo "  OK: no empty documents"
  fi
fi

echo "==> negative render: partially-served features honor their composition policy (hf-vh8)"
# AuthorizationPolicy/GRPCRoute ride the PeerAuthentication/HTTPRoute wrapper
# gate in _app.yaml but are separate CRDs negotiated on their own. The negative
# render above (zero APIs served) does NOT catch a regression here — with zero
# APIs served the wrapper gate closes the whole template before these secondary
# Kinds are ever reached. These legs serve the SIBLING API only, so the partial
# case is what has to hold the line, per the feature's composition policy.
#
# mtls is composition: atomic (plan 010, supersedes plan 005's per-Kind skip
# assertion here). Rendering PeerAuthentication without the AuthorizationPolicy
# that carries allowedPrincipals is MORE permissive than rendering neither, so
# the whole pair must drop — this leg is strictly more fail-closed than the
# "PeerAuthentication present, AuthorizationPolicy absent" it replaces.
if ! neg=$("$RENDER" full --set capabilities.apiVersions=null \
    --api-versions security.istio.io/v1beta1/PeerAuthentication 2>&1); then
  echo "  FAIL: partial-serving render (PeerAuthentication only) itself failed"; echo "$neg" | tail -5; fail=1
else
  validate_render "partial-serving (PeerAuthentication only)" "$neg"
  if grep -qE '^kind: (PeerAuthentication|AuthorizationPolicy)$' <<<"$neg"; then
    echo "  FAIL: atomic mtls rendered a half-pair when only PeerAuthentication's API is served"
    echo "        (an unrestricted PeerAuthentication without its principal-restricting"
    echo "        AuthorizationPolicy is fail-OPEN; the whole feature must skip)"; fail=1
  else
    echo "  OK: atomic mtls skips both Kinds when only PeerAuthentication's API is served"
  fi
  if grep -qE '^\{\}\s*$' <<<"$neg"; then
    echo "  FAIL: empty {} document emitted"; fail=1
  else
    echo "  OK: no empty documents"
  fi
fi
if ! neg=$("$RENDER" full --set capabilities.apiVersions=null \
    --set gatewayApi.grpcRoute.enabled=true \
    --api-versions gateway.networking.k8s.io/v1/HTTPRoute 2>&1); then
  echo "  FAIL: partial-serving render (HTTPRoute only) itself failed"; echo "$neg" | tail -5; fail=1
else
  validate_render "partial-serving (HTTPRoute only)" "$neg"
  if grep -qE '^kind: HTTPRoute$' <<<"$neg" && ! grep -qE '^kind: GRPCRoute$' <<<"$neg"; then
    echo "  OK: GRPCRoute skipped when only HTTPRoute's API is served"
  else
    echo "  FAIL: expected HTTPRoute present and GRPCRoute absent"; fail=1
  fi
fi
# Positive control: no over-skip once AuthorizationPolicy's own API is served too.
if ! pos=$("$RENDER" full --set capabilities.apiVersions=null \
    --api-versions security.istio.io/v1beta1/PeerAuthentication \
    --api-versions security.istio.io/v1beta1/AuthorizationPolicy 2>&1); then
  echo "  FAIL: positive-control render failed"; echo "$pos" | tail -5; fail=1
else
  validate_render "positive control (PeerAuthentication + AuthorizationPolicy served)" "$pos"
  if grep -qE '^kind: PeerAuthentication$' <<<"$pos" && \
     grep -qE '^kind: AuthorizationPolicy$' <<<"$pos" && \
     grep -A1 '^kind: AuthorizationPolicy$' <<<"$pos" | grep -q '.' && \
     grep -B1 '^kind: AuthorizationPolicy$' <<<"$pos" | grep -q '^apiVersion: security.istio.io/v1beta1$'; then
    echo "  OK: atomic mtls renders BOTH Kinds once both APIs are served"
    echo "      (no over-skip; AuthorizationPolicy negotiated to security.istio.io/v1beta1)"
  else
    echo "  FAIL: expected BOTH PeerAuthentication and AuthorizationPolicy (the latter at"
    echo "        security.istio.io/v1beta1) once both APIs are served — atomic composition"
    echo "        must hold the pair back only while an API is genuinely missing"; fail=1
  fi
fi

echo "==> extraManifests skips entries that render to nothing (hf-8k3)"
# The raw escape hatch must apply the same "separator only when non-empty"
# rule as platform.emit/extraObjects: a string manifest whose template
# collapses to empty (or an empty map) must emit no document at all, while a
# real entry in the same list still renders. minimal renders 3 kinds, so the
# live ConfigMap makes exactly 4 document separators — an unguarded generator
# emits 6 (one stray per empty entry).
if out=$("$RENDER" minimal --set-json 'extraManifests=["{{- if false }}never{{- end }}", {}, {"apiVersion":"v1","kind":"ConfigMap","metadata":{"name":"em-live"},"data":{"k":"v"}}]' 2>&1); then
  validate_render "extraManifests empty-entry skip" "$out"
  seps=$(grep -c '^---' <<<"$out" || true)
  if [[ "$seps" != "4" ]]; then
    echo "  FAIL: expected 4 document separators (3 minimal kinds + live ConfigMap), got $seps — an extraManifests entry that renders to nothing emitted a stray document"; fail=1
  elif grep -qE '^\{\}\s*$' <<<"$out"; then
    echo "  FAIL: empty {} document emitted from an empty-map extraManifests entry"; fail=1
  elif ! grep -q '^  name: em-live$' <<<"$out"; then
    echo "  FAIL: the non-empty extraManifests entry did not render"; fail=1
  else
    echo "  OK: empty extraManifests entries skipped, live entry rendered"
  fi
else
  echo "  FAIL: extraManifests render itself failed"; echo "$out" | tail -5; fail=1
fi

echo "==> rollout checksum annotations reach every workload type"
# Config/Secret changes must roll pods on ALL workload types (hf-bk0): the
# checksum annotations were once gated on workload.type == Deployment, leaving
# StatefulSet/DaemonSet pods running stale config after helm upgrade. full is
# the Deployment path (configMap enabled), stateful the StatefulSet path
# (configMap + secret enabled).
check_rollout_checksum() {
  local fixture="$1" annotation="$2"
  local out
  if out=$("$RENDER" "$fixture" 2>&1); then
    validate_render "rollout checksum ($fixture $annotation)" "$out"
    if grep -q "$annotation:" <<<"$out"; then
      echo "  OK: $fixture pod template carries $annotation"
    else
      echo "  FAIL: $fixture pod template missing $annotation — config/secret changes will not roll pods"; fail=1
    fi
  else
    echo "  FAIL: render failed for $fixture $annotation check"; echo "$out" | tail -3; fail=1
  fi
}
check_rollout_checksum full checksum/config
check_rollout_checksum stateful checksum/config
check_rollout_checksum stateful checksum/secret

echo "==> imagePullSecrets: dedupe across global and image paths, global first"
# A secret named in both global.imagePullSecrets and image.pullSecrets must
# render once (hf-k9c), and global entries must stay ahead of image ones.
if out=$("$RENDER" minimal \
    --set 'global.imagePullSecrets[0]=shared-pull' \
    --set 'global.imagePullSecrets[1]=global-only' \
    --set 'image.pullSecrets[0]=shared-pull' \
    --set 'image.pullSecrets[1]=image-only' 2>&1); then
  validate_render "imagePullSecrets dedupe (minimal)" "$out"
  got=$(doc_of Deployment t-minimal <<<"$out" |
        awk '/^ *imagePullSecrets:$/ { inblk = 1; next }
             inblk { if ($1 == "-") print $3; else exit }' | paste -sd, -)
  if [[ "$got" == "shared-pull,global-only,image-only" ]]; then
    echo "  OK: merged list is deduped and ordered global-first"
  else
    echo "  FAIL: expected imagePullSecrets [shared-pull,global-only,image-only], got [$got]"; fail=1
  fi
else
  echo "  FAIL: render failed for imagePullSecrets dedupe check"; echo "$out" | tail -3; fail=1
fi
# All three aggregation sites (workload pod spec, CronJob, hook Job) dedupe:
# the full fixture renders exactly one pod spec of each, so the shared name
# must appear exactly 3 times.
if out=$("$RENDER" full \
    --set 'global.imagePullSecrets[0]=shared-pull' \
    --set 'image.pullSecrets[0]=shared-pull' 2>&1); then
  validate_render "imagePullSecrets dedupe (full, per-site)" "$out"
  got=$(grep -c 'name: shared-pull' <<<"$out" || true)
  if [[ "$got" -eq 3 ]]; then
    echo "  OK: workload, CronJob, and hook Job pod specs each list the shared secret once"
  else
    echo "  FAIL: expected 3 occurrences of the shared pull secret (one per pod spec), got $got"; fail=1
  fi
else
  echo "  FAIL: render failed for imagePullSecrets per-site dedupe check"; echo "$out" | tail -3; fail=1
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
    validate_render "updateStrategy compatibility ($label)" "$out"
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
  validate_render "default RollingUpdate strategy (minimal)" "$out"
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
if out=$("$RENDER" minimal --set image.tag= --set image.digest="$digest" 2>&1); then
  validate_render "digest-only image pin" "$out"
  if grep -q "image: docker.io/example/minimal@$digest" <<<"$out"; then
    echo "  OK: digest-only pin renders repo@digest"
  else
    echo "  FAIL: digest-only pin did not render repo@digest"; fail=1
  fi
else
  echo "  FAIL: render failed for digest-only pin check"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" full --set image.tag= --set image.digest="$digest" --set jobs.image.repository=example/other 2>&1); then
  echo "  FAIL: hook Job rendered with a foreign repo and no usable pin"; fail=1
elif grep -q "hook Job" <<<"$out"; then
  echo "  OK: hook Job with un-inheritable pin fails with actionable message"
else
  echo "  FAIL: hook Job failed without the expected message"; echo "$out" | tail -3; fail=1
fi

echo "==> hook Job fail-closed: must define work"
# Enabled hook with no script/scriptFile/command used to crash with a Go
# reflect error (len of untyped nil); it must fail with a named message.
if out=$("$RENDER" minimal --set jobs.preInstall.enabled=true \
  --set jobs.image.repository=busybox --set jobs.image.tag=1.36 2>&1); then
  echo "  FAIL: hook Job rendered with no script, scriptFile, or command"; fail=1
elif grep -q "defines no work to run" <<<"$out"; then
  echo "  OK: workless hook Job fails with actionable message"
else
  echo "  FAIL: workless hook Job failed without the expected message (reflect crash regression?)"; echo "$out" | tail -3; fail=1
fi

# command-only hook (no script, args unset) must render — this is the nil-$args
# regression test: it crashed at `len $args` before the default(list) fix.
if out=$("$RENDER" minimal --set jobs.preInstall.enabled=true \
  --set jobs.image.repository=busybox --set jobs.image.tag=1.36 \
  --set 'jobs.preInstall.command[0]=/bin/true' 2>&1); then
  validate_render "command-only hook Job (nil-args)" "$out"
  if grep -q "kind: Job" <<<"$out" && grep -q -- '- /bin/true' <<<"$out"; then
    echo "  OK: command-only hook Job renders (empty args is nil-safe)"
  else
    echo "  FAIL: command-only hook Job rendered without the expected Job/command"; fail=1
  fi
else
  echo "  FAIL: command-only hook Job failed to render"; echo "$out" | tail -3; fail=1
fi

echo "==> passthrough container image resolution"
if out=$("$RENDER" minimal --set global.imageRegistry=mirror.example.internal \
  --set sidecars.enabled=true \
  --set 'sidecars.containers[0].name=resolver-probe' \
  --set 'sidecars.containers[0].image.repository=org/sidecar' \
  --set 'sidecars.containers[0].image.tag=9.9.9' \
  --set 'sidecars.containers[1].name=plain' \
  --set 'sidecars.containers[1].image=docker.io/library/busybox:1.36.1' 2>&1); then
  validate_render "passthrough container image resolution" "$out"
  if grep -A1 "image: mirror.example.internal/org/sidecar:9.9.9" <<<"$out" | \
     grep -q "imagePullPolicy: IfNotPresent"; then
    echo "  OK: dict sidecar image resolves through global.imageRegistry with the default pull policy"
  else
    echo "  FAIL: dict sidecar image did not resolve to mirror.example.internal/org/sidecar:9.9.9 with default imagePullPolicy"; fail=1
  fi
  if grep -q "image: docker.io/library/busybox:1.36.1" <<<"$out"; then
    echo "  OK: plain-string sidecar image stays verbatim (no registry rewrite)"
  else
    echo "  FAIL: plain-string sidecar image was rewritten"; fail=1
  fi
else
  echo "  FAIL: render failed for passthrough container image check"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --set sidecars.enabled=true \
  --set 'sidecars.containers[0].name=sc' \
  --set 'sidecars.containers[0].image.repository=org/sidecar' 2>&1); then
  echo "  FAIL: dict sidecar image rendered with neither tag nor digest"; fail=1
elif grep -q 'container "sc" image.tag and' <<<"$out"; then
  echo "  OK: unpinned dict sidecar image fails with actionable message"
else
  echo "  FAIL: unpinned dict sidecar image failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --set sidecars.enabled=true \
  --set 'sidecars.containers[0].name=sc' \
  --set 'sidecars.containers[0].image.tag=9.9.9' 2>&1); then
  echo "  FAIL: dict sidecar image rendered with an empty repository"; fail=1
elif grep -q 'container "sc" image.repository is empty' <<<"$out"; then
  echo "  OK: dict sidecar image without repository fails with actionable message"
else
  echo "  FAIL: repository-less dict sidecar image failed without the expected message"; echo "$out" | tail -3; fail=1
fi

echo "==> image registry double-prefix guard"
# A repository that already carries the registry host must not get it again.
if out=$("$RENDER" minimal --set image.repository=docker.io/library/busybox \
  --set image.tag=1.36 2>&1); then
  validate_render "qualified main repository (no double prefix)" "$out"
  if grep -q "image: docker.io/library/busybox:1.36" <<<"$out" &&
     ! grep -q "docker.io/docker.io" <<<"$out"; then
    echo "  OK: qualified main repository is not double-prefixed"
  else
    echo "  FAIL: main image path double-prefixed the registry"; grep "image:" <<<"$out" | head -3; fail=1
  fi
else
  echo "  FAIL: render failed for main double-prefix check"; echo "$out" | tail -3; fail=1
fi

# Same for the hook Job image resolution path.
if out=$("$RENDER" minimal --set jobs.preInstall.enabled=true \
  --set jobs.preInstall.script='echo hi' \
  --set jobs.image.repository=docker.io/library/busybox --set jobs.image.tag=1.36 2>&1); then
  validate_render "qualified hook Job repository (no double prefix)" "$out"
  if grep -q "image: docker.io/library/busybox:1.36" <<<"$out" &&
     ! grep -q "docker.io/docker.io" <<<"$out"; then
    echo "  OK: qualified hook Job repository is not double-prefixed"
  else
    echo "  FAIL: hook Job image path double-prefixed the registry"; grep "image:" <<<"$out" | head -3; fail=1
  fi
else
  echo "  FAIL: render failed for hook double-prefix check"; echo "$out" | tail -3; fail=1
fi

# The guard must not suppress LEGITIMATE prefixing: an unqualified repository
# still gets the registry.
if out=$("$RENDER" minimal 2>&1); then
  validate_render "unqualified repository keeps its registry prefix" "$out"
  if grep -q "image: docker.io/example/minimal:1.0.0" <<<"$out"; then
    echo "  OK: unqualified repository still receives the registry prefix"
  else
    echo "  FAIL: unqualified repository lost its registry prefix"; grep "image:" <<<"$out" | head -3; fail=1
  fi
else
  echo "  FAIL: render failed for baseline prefix check"; echo "$out" | tail -3; fail=1
fi

echo "==> schema enforcement (helm-side): invalid values must fail"
if out=$("$RENDER" minimal --set workload.type=deployment 2>&1); then
  echo "  FAIL: render succeeded with workload.type=deployment (schema not enforced)"; fail=1
elif grep -q "workload/type" <<<"$out"; then
  echo "  OK: lowercase workload.type rejected by values.schema.json"
else
  echo "  FAIL: render failed without a schema error"; echo "$out" | tail -3; fail=1
fi

# Even without the schema (library consumers may not copy it), the template
# itself must refuse an unknown workload.type instead of silently rendering
# a Deployment.
if out=$("$RENDER" minimal --skip-schema-validation --set workload.type=Bogus 2>&1); then
  echo "  FAIL: render succeeded with workload.type=Bogus and no schema (silent Deployment fallback)"; fail=1
elif grep -q 'unknown workload.type "Bogus"' <<<"$out"; then
  echo "  OK: unknown workload.type fails in-template without the schema"
else
  echo "  FAIL: schema-less workload.type=Bogus failed without the expected message"; echo "$out" | tail -3; fail=1
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

# rbac.rules is a permission grant: a malformed rule that the schema lets
# through renders a Role the API server rejects at install time, or (worse) one
# that grants something other than what was written. verbs is not optional.
if out=$("$RENDER" minimal --set rbac.enabled=true \
  --set 'rbac.rules[0].apiGroups[0]=' --set 'rbac.rules[0].resources[0]=pods' 2>&1); then
  echo "  FAIL: render succeeded with an rbac rule that has no verbs"; fail=1
elif grep -q "rbac/rules" <<<"$out"; then
  echo "  OK: rbac rule without verbs rejected by values.schema.json"
else
  echo "  FAIL: render failed without a schema error"; echo "$out" | tail -3; fail=1
fi

# nonResourceURLs is a ClusterRole-only field. Accepted in a namespaced Role it
# is silently ignored by the API server, so the app gets none of the access the
# consumer believes they granted — additionalProperties:false catches the typo class.
if out=$("$RENDER" minimal --set rbac.enabled=true \
  --set 'rbac.rules[0].apiGroups[0]=' --set 'rbac.rules[0].resources[0]=pods' \
  --set 'rbac.rules[0].verbs[0]=get' --set 'rbac.rules[0].nonResourceURLs[0]=/healthz' 2>&1); then
  echo "  FAIL: render succeeded with nonResourceURLs in a namespaced rbac rule"; fail=1
elif grep -q "rbac/rules" <<<"$out"; then
  echo "  OK: ClusterRole-only nonResourceURLs rejected by values.schema.json"
else
  echo "  FAIL: render failed without a schema error"; echo "$out" | tail -3; fail=1
fi

echo "==> PodDisruptionBudget: invalid unhealthyPodEvictionPolicy fails closed"
# values.schema.reference.json already enforces the enum, but library
# consumers may not copy the schema — the template itself must also refuse
# an invalid value instead of rendering it verbatim (invariant 1: fail closed).
if out=$("$RENDER" full --skip-schema-validation --set podDisruptionBudget.unhealthyPodEvictionPolicy=Bogus 2>&1); then
  echo "  FAIL: render succeeded with podDisruptionBudget.unhealthyPodEvictionPolicy=Bogus and no schema"; fail=1
elif grep -q "podDisruptionBudget.unhealthyPodEvictionPolicy" <<<"$out"; then
  echo "  OK: unknown unhealthyPodEvictionPolicy fails in-template without the schema"
else
  echo "  FAIL: schema-less unhealthyPodEvictionPolicy=Bogus failed without the expected message"; echo "$out" | tail -3; fail=1
fi

echo "==> PodDisruptionBudget: minAvailable and maxUnavailable are mutually exclusive"
# _pdb.yaml:17 fails closed when both are set. The schema only documents the
# exclusion in its property descriptions, it does not structurally forbid
# both keys, so the template guard is what actually stops a consumer from
# rendering a PodDisruptionBudget the API server rejects.
if out=$("$RENDER" full --set podDisruptionBudget.minAvailable=1 --set podDisruptionBudget.maxUnavailable=1 2>&1); then
  echo "  FAIL: render succeeded with both minAvailable and maxUnavailable set"; fail=1
elif grep -q "mutually exclusive" <<<"$out"; then
  echo "  OK: setting both minAvailable and maxUnavailable fails closed"
else
  echo "  FAIL: render failed without the expected mutually-exclusive message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" full --set podDisruptionBudget.minAvailable=null --set podDisruptionBudget.maxUnavailable=1 2>&1); then
  pdb_doc=$(doc_of PodDisruptionBudget t-full <<<"$out")
  if grep -q '^  maxUnavailable: 1$' <<<"$pdb_doc"; then
    echo "  OK: maxUnavailable alone renders without over-firing the mutual-exclusion guard"
  else
    echo "  FAIL: PodDisruptionBudget rendered without maxUnavailable"; echo "$pdb_doc" | tail -8; fail=1
  fi
else
  echo "  FAIL: render failed with only maxUnavailable set"; echo "$out" | tail -3; fail=1
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
if out=$("$RENDER" full --set mtls.allowedPrincipals=null --set mtls.allowAllPrincipals=true 2>&1); then
  validate_render "mtls.allowAllPrincipals=true" "$out"
  if grep -q 'cluster.local/ns/\*/sa/\*' <<<"$out"; then
    echo "  OK: mtls.allowAllPrincipals=true renders the wildcard principal"
  else
    echo "  FAIL: mtls.allowAllPrincipals=true did not render the wildcard principal"; fail=1
  fi
else
  echo "  FAIL: render failed for mtls.allowAllPrincipals=true check"; echo "$out" | tail -3; fail=1
fi

# Cluster-scoped extraObjects are refused unless explicitly allowed.
if out=$("$RENDER" full --set allowClusterScopedExtras=false 2>&1); then
  echo "  FAIL: render succeeded with cluster-scoped extraObjects and gate=false"; fail=1
elif grep -q 'cluster-scoped Kind "ClusterRole"' <<<"$out"; then
  echo "  OK: cluster-scoped extraObjects refused, message names ClusterRole"
else
  echo "  FAIL: gate=false failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# extraObjects with a Kind the registry does not know must fail closed, not
# silently drop the object.
if out=$("$RENDER" minimal --set-json 'extraObjects={"WidgetFrobber":[{"name":"w1"}]}' 2>&1); then
  echo "  FAIL: render succeeded with an unknown extraObjects Kind (silent drop)"; fail=1
elif grep -q 'unknown Kind "WidgetFrobber"' <<<"$out"; then
  echo "  OK: unknown extraObjects Kind fails closed with actionable message"
else
  echo "  FAIL: unknown extraObjects Kind failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# An explicit per-entry apiVersion is the documented escape: renders verbatim.
if out=$("$RENDER" minimal --set-json 'extraObjects={"WidgetFrobber":[{"name":"w1","apiVersion":"widgets.example.io/v1","spec":{"size":1}}]}' 2>&1); then
  # WidgetFrobber/widgets.example.io is a fictional Kind for this test — no
  # catalog will ever ship a schema for it, so this is the one legitimate
  # allow-missing leg (everything else validates against a real schema).
  validate_render "extraObjects unknown Kind + explicit apiVersion" "$out" "$GOLDEN_KUBE_VERSION" 1
  if grep -q "kind: WidgetFrobber" <<<"$out" && grep -q "apiVersion: widgets.example.io/v1" <<<"$out"; then
    echo "  OK: unknown Kind with explicit apiVersion renders verbatim"
  else
    echo "  FAIL: pinned unknown Kind did not render as specified"; fail=1
  fi
else
  echo "  FAIL: render failed for pinned unknown extraObjects Kind"; echo "$out" | tail -3; fail=1
fi

# Known CRD Kind whose API is unserved still SKIPS (invariant 2) — the render
# must succeed and must not contain the object.
if out=$("$RENDER" minimal --set-json 'extraObjects={"VirtualService":[{"name":"vs1"}]}' 2>&1); then
  validate_render "unserved registry Kind in extraObjects (VirtualService skipped)" "$out"
  if grep -q "kind: VirtualService" <<<"$out"; then
    echo "  FAIL: unserved VirtualService extraObject rendered anyway"; fail=1
  else
    echo "  OK: unserved registry Kind in extraObjects is skipped from manifests"
  fi
else
  echo "  FAIL: render failed for unserved extraObjects Kind"; echo "$out" | tail -3; fail=1
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
  validate_render "secret.existingSecret suppresses managed Secret" "$out"
  secret_count=$(grep -c '^kind: Secret' <<<"$out" || true)
  if [[ "$secret_count" -eq 0 ]]; then
    echo "  OK: existingSecret suppresses the chart-managed Secret"
  else
    echo "  FAIL: chart still rendered a Secret with secret.existingSecret set"; fail=1
  fi
else
  echo "  FAIL: render failed while checking secret.existingSecret suppression"; echo "$out" | tail -3; fail=1
fi

# generatedSecrets: duplicate entry names must fail closed.
if out=$("$RENDER" minimal --set-json 'generatedSecrets=[{"name":"admin","keys":[{"key":"password","kind":"password"}]},{"name":"admin","keys":[{"key":"password","kind":"password"}]}]' 2>&1); then
  echo "  FAIL: render succeeded with duplicate generatedSecrets entry names"; fail=1
elif grep -q 'generatedSecrets contains duplicate name "admin"' <<<"$out"; then
  echo "  OK: duplicate generatedSecrets entry name rejected"
else
  echo "  FAIL: duplicate generatedSecrets entry name failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# generatedSecrets: duplicate key within one entry must fail closed.
if out=$("$RENDER" minimal --set-json 'generatedSecrets=[{"name":"admin","keys":[{"key":"password","kind":"password"},{"key":"password","kind":"password"}]}]' 2>&1); then
  echo "  FAIL: render succeeded with a duplicate generatedSecrets key"; fail=1
elif grep -q 'has duplicate key "password"' <<<"$out"; then
  echo "  OK: duplicate generatedSecrets key rejected"
else
  echo "  FAIL: duplicate generatedSecrets key failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# generatedSecrets: entry name colliding with a reserved release Secret suffix
# must fail closed (naming hygiene, not a real name collision).
if out=$("$RENDER" minimal --set-json 'generatedSecrets=[{"name":"app-secret","keys":[{"key":"password","kind":"password"}]}]' 2>&1); then
  echo "  FAIL: render succeeded with a reserved-suffix generatedSecrets name"; fail=1
elif grep -q 'collides with a reserved release Secret name pattern' <<<"$out"; then
  echo "  OK: reserved-suffix generatedSecrets name rejected"
else
  echo "  FAIL: reserved-suffix generatedSecrets name failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# generatedSecrets: htpasswd password/passwordFrom are mutually exclusive.
if out=$("$RENDER" minimal --set-json 'generatedSecrets=[{"name":"admin","keys":[{"key":"password","kind":"password"},{"key":"auth","kind":"htpasswd","username":"admin","password":"x","passwordFrom":"password"}]}]' 2>&1); then
  echo "  FAIL: render succeeded with both htpasswd password and passwordFrom set"; fail=1
elif grep -q 'password and passwordFrom are mutually exclusive' <<<"$out"; then
  echo "  OK: htpasswd password/passwordFrom XOR violation rejected"
else
  echo "  FAIL: htpasswd password/passwordFrom XOR violation failed without the expected message"; echo "$out" | tail -3; fail=1
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
    validate_render "container hardening posture ($label)" "$out"
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
  validate_render "securityContext merge-direction (daemon)" "$out"
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
# document — same kind+name key rule as doc_of (the hook ServiceAccount and the
# hook Job share a name, so the kind is part of the key).
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
  validate_render "hook Job dependency ordering ($label)" "$out"
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
    # Scoped to the hook Job document: the hook ServiceAccount shares its name,
    # so a whole-render (or name-keyed) scan could be satisfied by the wrong doc.
    job_sa=$(doc_of Job t-full-preinstall <<<"$out" |
      awk '/^      serviceAccountName: t-full-preinstall$/ { n++ } END { print n + 0 }')
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
  validate_render "post-install script ConfigMap stays normal resource" "$out"
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
  # Do NOT swallow this failure. A dependency update that dies here leaves a
  # STALE charts/ in place, so every NOTES assertion below silently tests the
  # PREVIOUS library build and reports OK. Capture the output rather than
  # letting it stream: callers run `out=$(notes_of ... 2>&1)` and grep $out, so
  # dependency-resolution chatter on the happy path would be grep fodder.
  local dep
  if ! dep=$(helm dependency update "$dir" 2>&1); then
    echo "helm dependency update failed for fixture '$fixture':" >&2
    echo "$dep" >&2
    return 1
  fi
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

# Existing warnings unaffected: minimal fixture has no secret/ingress config, so no
# WARNING at all once resources are set (isolates this check from the NO RESOURCES
# CONFIGURED warning below, which minimal fires on by default — see hf-uup).
if out=$(notes_of minimal --set resources.requests.cpu=100m --set resources.limits.memory=128Mi 2>&1); then
  if grep -q "WARNING:" <<<"$out"; then
    echo "  FAIL: minimal fixture unexpectedly emitted a NOTES warning"; echo "$out" | tail -5; fail=1
  else
    echo "  OK: minimal fixture emits no NOTES warnings"
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal fixture"; echo "$out" | tail -5; fail=1
fi

echo "==> NOTES: containers with no resources configured (hf-uup)"
# Zero-config default: minimal fixture sets no resources anywhere, so the main
# container is named in a WARNING (BestEffort QoS otherwise ships silently).
if out=$(notes_of minimal 2>&1); then
  if grep -q "NO RESOURCES CONFIGURED" <<<"$out" && grep -q "container(s) minimal have no CPU/memory" <<<"$out"; then
    echo "  OK: zero-config minimal fixture names the main container in a NO RESOURCES CONFIGURED warning"
  else
    echo "  FAIL: zero-config minimal fixture did not warn about its resource-less main container"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal fixture"; echo "$out" | tail -5; fail=1
fi

# Setting resources on the main container silences the warning for it (mutation test:
# reverting this override must bring the FAIL above back).
if out=$(notes_of minimal --set resources.requests.cpu=100m --set resources.limits.memory=128Mi 2>&1); then
  if grep -q "NO RESOURCES CONFIGURED" <<<"$out"; then
    echo "  FAIL: main container resources set but NO RESOURCES CONFIGURED warning still fired"; echo "$out" | tail -5; fail=1
  else
    echo "  OK: setting main container resources silences the warning"
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal fixture with resources set"; echo "$out" | tail -5; fail=1
fi

# A sidecar/initContainer with no resources of its own is named too, even when the
# main container has resources set (per-container detection, not chart-wide).
if out=$(notes_of minimal \
  --set resources.requests.cpu=100m \
  --set sidecars.enabled=true \
  --set 'sidecars.containers[0].name=log-shipper' \
  --set 'sidecars.containers[0].image=busybox:1.36' \
  --set initContainers.enabled=true \
  --set 'initContainers.containers[0].name=wait-for-db' \
  --set 'initContainers.containers[0].image=busybox:1.36' 2>&1); then
  if grep -q "log-shipper (sidecar)" <<<"$out" && grep -q "wait-for-db (initContainer)" <<<"$out"; then
    echo "  OK: resource-less sidecar and initContainer are both named in the warning"
  else
    echo "  FAIL: resource-less sidecar/initContainer were not named in the NO RESOURCES CONFIGURED warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal fixture with sidecar/initContainer"; echo "$out" | tail -5; fail=1
fi

# Giving the sidecar and initContainer their own resources fully silences the warning.
if out=$(notes_of minimal \
  --set resources.requests.cpu=100m \
  --set sidecars.enabled=true \
  --set 'sidecars.containers[0].name=log-shipper' \
  --set 'sidecars.containers[0].image=busybox:1.36' \
  --set 'sidecars.containers[0].resources.requests.cpu=50m' \
  --set initContainers.enabled=true \
  --set 'initContainers.containers[0].name=wait-for-db' \
  --set 'initContainers.containers[0].image=busybox:1.36' \
  --set 'initContainers.containers[0].resources.limits.memory=64Mi' 2>&1); then
  if grep -q "NO RESOURCES CONFIGURED" <<<"$out"; then
    echo "  FAIL: all containers have resources set but NO RESOURCES CONFIGURED warning still fired"; echo "$out" | tail -5; fail=1
  else
    echo "  OK: giving every container resources silences the warning entirely"
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal fixture with sidecar/initContainer resources set"; echo "$out" | tail -5; fail=1
fi

# No false positives: the full fixture (byte-exact golden, no resources overrides) must
# still trip the warning for its main container — proves the check runs on every fixture,
# not just minimal, and confirms no golden-affecting side effect crept into the generators.
if out=$(notes_of full 2>&1); then
  if grep -q "NO RESOURCES CONFIGURED" <<<"$out" && grep -q "container(s) full have no CPU/memory" <<<"$out"; then
    echo "  OK: full fixture also warns about its resource-less main container"
  else
    echo "  FAIL: full fixture did not warn about its resource-less main container"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for full fixture"; echo "$out" | tail -5; fail=1
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

echo "==> NOTES warnings: weakened security posture and active escape hatches"
# privileged=true renders (valid opt-out) but must be loudly warned.
if out=$(notes_of minimal --set containerSecurityContext.privileged=true 2>&1); then
  if grep -q "containerSecurityContext WEAKENS" <<<"$out" &&
     grep -q "privileged=true" <<<"$out"; then
    echo "  OK: privileged=true emits the posture-weakening NOTES warning"
  else
    echo "  FAIL: privileged=true did not emit the posture-weakening NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal with privileged=true"; echo "$out" | tail -5; fail=1
fi

# Disabling the whole hardening block is the biggest hammer — dedicated warning.
if out=$(notes_of minimal --set containerSecurityContext.enabled=false 2>&1); then
  if grep -q "containerSecurityContext.enabled=false disables" <<<"$out"; then
    echo "  OK: containerSecurityContext.enabled=false emits the hardening-disabled NOTES warning"
  else
    echo "  FAIL: containerSecurityContext.enabled=false did not emit the expected NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal with hardening disabled"; echo "$out" | tail -5; fail=1
fi

# Wildcard principal escape hatch (same values shape as the render-path test above).
if out=$(notes_of full --set mtls.allowedPrincipals=null --set mtls.allowAllPrincipals=true 2>&1); then
  if grep -q "allowAllPrincipals=true authorizes the wildcard principal" <<<"$out"; then
    echo "  OK: mtls.allowAllPrincipals=true emits the wildcard-principal NOTES warning"
  else
    echo "  FAIL: mtls.allowAllPrincipals=true did not emit the wildcard-principal NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for full with allowAllPrincipals"; echo "$out" | tail -5; fail=1
fi

# Cluster-scoped extras escape hatch (full fixture sets allowClusterScopedExtras=true).
if out=$(notes_of full 2>&1); then
  if grep -q "allowClusterScopedExtras=true" <<<"$out"; then
    echo "  OK: allowClusterScopedExtras=true emits the escape-hatch NOTES warning"
  else
    echo "  FAIL: allowClusterScopedExtras=true did not emit the escape-hatch NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for full fixture"; echo "$out" | tail -5; fail=1
fi

echo "==> NOTES: Kinds enabled in values but skipped by capability gating"
# A CRD-backed Kind whose API is neither served nor force-assumed renders NOTHING.
# Without a warning the operator believes cert-manager Certificates or ServiceMonitors
# deployed when they did not — a silent security/observability gap.
if out=$(notes_of minimal \
  --set certificate.enabled=true --set certificate.issuer=letsencrypt \
  --set serviceMonitor.enabled=true \
  --set prometheusRule.enabled=true 2>&1); then
  if grep -q "SKIPPED KINDS" <<<"$out" &&
     grep -q "Certificate (tried cert-manager.io/v1)" <<<"$out" &&
     grep -q "ServiceMonitor (tried monitoring.coreos.com/v1)" <<<"$out" &&
     grep -q "PrometheusRule (tried monitoring.coreos.com/v1)" <<<"$out"; then
    echo "  OK: enabled-but-skipped Kinds are named in a NOTES warning with the apiVersions tried"
  else
    echo "  FAIL: enabled-but-skipped Certificate/ServiceMonitor/PrometheusRule produced no naming NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal fixture with gated Kinds enabled"; echo "$out" | tail -5; fail=1
fi

# Force-assuming the APIs closes the gap: the objects render, so there is nothing
# to warn about. With the gate open the PrometheusRule generator actually runs,
# so its empty-groups fail guard demands at least one group here.
if out=$(notes_of minimal \
  --set certificate.enabled=true --set certificate.issuer=letsencrypt \
  --set serviceMonitor.enabled=true \
  --set prometheusRule.enabled=true \
  --set 'prometheusRule.groups[0].name=basic' \
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

# No false positives: the features registry covers 9 Kinds — 7 representatives
# gated in _app.yaml (Certificate, PeerAuthentication, HTTPRoute, ServiceMonitor,
# PodMonitor, PrometheusRule, VerticalPodAutoscaler) plus 2 secondary Kinds gated
# inside their own feature template (AuthorizationPolicy, GRPCRoute). The full
# fixture enables mtls and both routes (httpRoute and grpcRoute) and
# force-assumes every API those enabled Kinds need, so it must stay silent.
if out=$(notes_of full 2>&1); then
  if grep -q "SKIPPED KINDS" <<<"$out"; then
    echo "  FAIL: full fixture warns about skipped Kinds it actually renders"; echo "$out" | tail -5; fail=1
  else
    echo "  OK: full fixture (all gated APIs force-assumed) emits no skipped-Kind warning"
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for full fixture"; echo "$out" | tail -5; fail=1
fi

# Atomic set, nothing served: an enabled mtls feature with no force-assume has
# neither API. BOTH Kinds of the set must be named — a warning that mentions only
# the representative reads as "PeerAuthentication is missing" and leaves the
# operator believing the AuthorizationPolicy carrying allowedPrincipals deployed.
if out=$(notes_of minimal --set mtls.enabled=true --set mtls.allowAllPrincipals=true 2>&1); then
  if grep -q "SKIPPED KINDS" <<<"$out" &&
     grep -q "PeerAuthentication (tried" <<<"$out" &&
     grep -q "AuthorizationPolicy (tried" <<<"$out"; then
    echo "  OK: NOTES names both Kinds of the atomic mtls set when neither API is served"
  else
    echo "  FAIL: NOTES did not name both PeerAuthentication and AuthorizationPolicy as skipped"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal fixture with mtls enabled"; echo "$out" | tail -5; fail=1
fi

# Secondary-Kind NOTES coverage (hf-vh8, extended by plan 010): AuthorizationPolicy
# has no _app.yaml wrapper gate of its own, but a skip must still surface in NOTES
# like any other gated Kind. Force-assume only PeerAuthentication's API: mtls is
# atomic, so the missing AuthorizationPolicy API holds the whole feature back —
# and the HELD-BACK Kind has to be named too. PeerAuthentication's own API IS
# served here, so it is the atomic expansion in skippedKinds, and nothing else,
# that puts it in the warning; without it the operator sees a PeerAuthentication
# the cluster can serve, no warning about it, and no object.
if out=$(notes_of full --set 'capabilities.apiVersions={security.istio.io/v1beta1/PeerAuthentication}' 2>&1); then
  if grep -q "SKIPPED KINDS" <<<"$out" &&
     grep -q "AuthorizationPolicy (tried" <<<"$out" &&
     grep -q "PeerAuthentication (tried" <<<"$out"; then
    echo "  OK: NOTES names BOTH mtls Kinds when only PeerAuthentication's API is served"
    echo "      (the served-but-held-back half of an atomic set is reported, not silent)"
  else
    echo "  FAIL: NOTES did not name both the skipped secondary Kind AuthorizationPolicy and"
    echo "        the served-but-held-back PeerAuthentication"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for full fixture with PeerAuthentication-only force-assume"; echo "$out" | tail -5; fail=1
fi

# The skip above must be VISIBLE: unserved extraObjects entries get their own
# NOTES warning naming Kind/name and the apiVersions tried.
if out=$(notes_of minimal --set-json 'extraObjects={"VirtualService":[{"name":"vs1"}]}' 2>&1); then
  if grep -q "SKIPPED EXTRA OBJECTS" <<<"$out" &&
     grep -qF "VirtualService/vs1 (tried networking.istio.io/v1, networking.istio.io/v1beta1, networking.istio.io/v1alpha3)" <<<"$out"; then
    echo "  OK: unserved extraObjects entry is named in a NOTES warning with the apiVersions tried"
  else
    echo "  FAIL: unserved extraObjects entry produced no naming NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal with unserved extraObject"; echo "$out" | tail -5; fail=1
fi

# Force-assuming the API closes the gap: the object renders, warning disappears.
if out=$(notes_of minimal --set-json 'extraObjects={"VirtualService":[{"name":"vs1"}]}' \
  --set 'capabilities.apiVersions[0]=networking.istio.io/v1' 2>&1); then
  if grep -q "SKIPPED EXTRA OBJECTS" <<<"$out"; then
    echo "  FAIL: force-assumed extraObjects API still reported as skipped"; echo "$out" | tail -5; fail=1
  else
    echo "  OK: force-assumed apiVersion suppresses the skipped-extras warning"
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal with force-assumed extraObject API"; echo "$out" | tail -5; fail=1
fi

# No false positives: full's extraObjects are all stable built-ins.
if out=$(notes_of full 2>&1); then
  if grep -q "SKIPPED EXTRA OBJECTS" <<<"$out"; then
    echo "  FAIL: full fixture warns about skipped extraObjects it actually renders"; echo "$out" | tail -5; fail=1
  else
    echo "  OK: full fixture (stable extraObjects) emits no skipped-extras warning"
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for full fixture"; echo "$out" | tail -5; fail=1
fi

echo "==> capability anti-drift: features registry vs gate sites vs emitters (content, hf-vh8)"
# platform.capabilities.features is the ONE place that knows which Kinds a gated
# feature emits. Counting gate sites against table rows (pre-005) could not see a
# renamed row; 005's name-set check could, but only against a HARDCODED secondary
# set. These checks compare CONTENT in every direction and derive the secondary
# set from the registry itself, so a Kind emitted by a generator but missing from
# its feature's row — the bug class behind AuthorizationPolicy/GRPCRoute — is
# structurally detectable. The registry's literal-YAML shape is load-bearing for
# this sed/grep parser; the define's comment in _capabilities.tpl says so.
feat_block=$(sed -n '/define "platform.capabilities.features"/,/^{{- end -}}/p' \
  "$LIB/templates/_capabilities.tpl" || true)
# Every Kind of every feature, and the representatives (first Kind of each row).
feat_all_kinds_raw=$(grep -oE 'kinds: \[[^]]+\]' <<<"$feat_block" | sed 's/kinds: //' \
  | tr -d '[] ' | tr ',' '\n' | LC_ALL=C sort || true)
feat_all_kinds=$(LC_ALL=C uniq <<<"$feat_all_kinds_raw" || true)
feat_rep_kinds=$(grep -oE 'kinds: \[[^]]+\]' <<<"$feat_block" \
  | sed -E 's/kinds: \[([^],]+).*/\1/' | LC_ALL=C sort -u || true)
# Kind names are the only "Quoted" capitalized tokens on gateOpen lines
# ("platform.capabilities.gateOpen" itself starts lowercase).
gate_kinds=$(grep 'platform.capabilities.gateOpen' "$LIB/templates/_app.yaml" \
  | grep -oE '"[A-Z][A-Za-z]+"' | tr -d '"' | LC_ALL=C sort -u || true)
# Kinds a generator negotiates STRICTLY on its own (apiVersionFor, not
# ...OrDefault): exactly the secondary Kinds that gate inside their template.
emitter_gated_kinds=$(grep -hoE 'apiVersionFor" \(list \. "[A-Z][A-Za-z]+"' "$LIB"/templates/_*.yaml \
  | grep -oE '"[A-Z][A-Za-z]+"$' | tr -d '"' | LC_ALL=C sort -u || true)
raw_gates=$(grep -c 'platform.capabilities.apiVersionFor' "$LIB/templates/_app.yaml" || true)
if [[ -z "$feat_all_kinds" || -z "$feat_rep_kinds" || -z "$gate_kinds" ]]; then
  echo "  FAIL: could not parse the features registry or the _app.yaml gate sites"
  echo "        (literal-YAML shape contract broken, or no gateOpen call sites)"; fail=1
fi
registry_fail=0
# Every feature declares exactly one composition policy, spelled one of the two
# ways platform.capabilities.kindAvailable understands. A typo'd or missing
# policy fails closed at render time, but only for a values combination that
# actually enables that feature — catch it statically instead.
feat_rows=$(grep -cE '^  kinds: \[' <<<"$feat_block" || true)
feat_comps=$(grep -cE '^  composition: (atomic|independent)$' <<<"$feat_block" || true)
if [[ "$feat_rows" -gt 0 && "$feat_comps" -eq "$feat_rows" ]]; then
  echo "  OK: all $feat_rows features declare a valid composition policy (atomic|independent)"
else
  echo "  FAIL: features registry has $feat_rows Kind set(s) but $feat_comps valid composition"
  echo "        line(s) — each feature needs exactly one 'composition: atomic' or"
  echo "        'composition: independent'"
  registry_fail=1
fi
feat_dupes=$(LC_ALL=C uniq -d <<<"$feat_all_kinds_raw" || true)
if [[ -n "$feat_dupes" ]]; then
  echo "  FAIL: Kind(s) registered under more than one feature: $(tr '\n' ' ' <<<"$feat_dupes")"
  registry_fail=1
else
  echo "  OK: every registered Kind belongs to exactly one feature"
fi
# Representatives are gated in _app.yaml; secondaries are gated in their generator.
for reg_kind in $feat_rep_kinds; do
  if ! grep -q "platform.capabilities.gateOpen\" (list . \"$reg_kind\")" "$LIB/templates/_app.yaml"; then
    echo "  FAIL: representative Kind $reg_kind has no gateOpen site in _app.yaml"
    registry_fail=1
  fi
done
feat_secondary=$(comm -23 <(printf '%s\n' "$feat_all_kinds") <(printf '%s\n' "$feat_rep_kinds") || true)
for reg_kind in $feat_secondary; do
  if grep -q "platform.capabilities.gateOpen\" (list . \"$reg_kind\")" "$LIB/templates/_app.yaml"; then
    echo "  FAIL: secondary Kind $reg_kind has an _app.yaml gate site; secondary Kinds"
    echo "        gate inside their own generator (make it a representative instead)"
    registry_fail=1
  fi
  if ! grep -qw "$reg_kind" <<<"$emitter_gated_kinds"; then
    echo "  FAIL: secondary Kind $reg_kind is registered but no generator negotiates it"
    echo "        with the strict platform.capabilities.apiVersionFor — it would ride"
    echo "        its sibling's gate and emit an apiVersion the cluster may not serve"
    registry_fail=1
  fi
done
# Every registered Kind must actually be emitted by a generator.
for reg_kind in $feat_all_kinds; do
  if ! grep -qE "^kind: $reg_kind\$" "$LIB"/templates/_*.yaml; then
    echo "  FAIL: features registry lists $reg_kind but no generator emits it"
    registry_fail=1
  fi
done
# Reverse direction: every gate site and every strictly-negotiated emitter Kind
# must be registered.
for reg_kind in $gate_kinds; do
  if ! grep -qw "$reg_kind" <<<"$feat_all_kinds"; then
    echo "  FAIL: _app.yaml gates on $reg_kind, which is not in the features registry"
    registry_fail=1
  fi
done
for reg_kind in $emitter_gated_kinds; do
  if ! grep -qw "$reg_kind" <<<"$feat_all_kinds"; then
    echo "  FAIL: a generator strictly negotiates $reg_kind, which is not in the features"
    echo "        registry — its skip would never reach NOTES SKIPPED KINDS"
    registry_fail=1
  fi
done
if [[ "$registry_fail" -eq 0 ]]; then
  echo "  OK: registry <-> gate sites <-> emitters agree in both directions"
  echo "      (representatives gate in _app.yaml: $(tr '\n' ' ' <<<"$feat_rep_kinds"))"
  echo "      (secondaries gate in their generator: $(tr '\n' ' ' <<<"$feat_secondary"))"
else
  fail=1
fi
if [[ "$raw_gates" -eq 0 ]]; then
  echo "  OK: no raw apiVersionFor calls in _app.yaml"
else
  echo "  FAIL: _app.yaml must gate via gateOpen, found $raw_gates raw apiVersionFor call(s)"; fail=1
fi

echo "==> pod policy single source: extracted helpers have no re-inlined copies"
# 009 moved pull-secret precedence, pod securityContext, the automount/
# enableServiceLinks pair, and workload metadata into platform.podPolicy.* /
# platform.workloadMetadata. A re-inlined copy (e.g. a new pod-bearing
# generator hand-rolling the block) forks policy again — the drift the
# extraction closed. Counts are guarded with `|| true` because a zero match
# would otherwise abort the gate under set -e.
pull_total=$(cat "$LIB"/templates/*.tpl "$LIB"/templates/*.yaml | grep -c 'Values.global.imagePullSecrets' || true)
psc_total=$(cat "$LIB"/templates/*.tpl "$LIB"/templates/*.yaml | grep -c 'podSecurityContext "enabled"' || true)
# 3 = the identity helper + the two ServiceAccount OBJECT templates
# (_helpers.tpl serviceaccount/hook-serviceaccount), which legitimately set
# the field on the SA resource.
amt_total=$(cat "$LIB"/templates/*.tpl "$LIB"/templates/*.yaml | grep -c 'automountServiceAccountToken: {{' || true)
meta_calls=$(cat "$LIB"/templates/_deployment.yaml "$LIB"/templates/_statefulset.yaml "$LIB"/templates/_daemonset.yaml | grep -c 'platform.workloadMetadata' || true)
if [[ "$pull_total" -eq 1 && "$psc_total" -eq 1 && "$amt_total" -eq 3 && "$meta_calls" -eq 3 ]]; then
  echo "  OK: pull-secret precedence, pod securityContext, token policy, and workload metadata are single-source"
else
  echo "  FAIL: pod policy re-inlined somewhere (pullSecrets=$pull_total want 1, podSecurityContext=$psc_total want 1, automount=$amt_total want 3, workloadMetadata calls=$meta_calls want 3)"; fail=1
fi

echo "==> selector stability"
# Selectors land in immutable fields (workload spec.selector) and in the Service/PDB
# selectors. They must contain ONLY name/instance/component. A user-settable value
# such as commonLabels leaking in here means changing that label orphans the running
# pods — and on workloads it makes helm upgrade fail outright.
if out=$("$RENDER" minimal --set service.enabled=true --set commonLabels.canary=leak 2>&1); then
  validate_render "selector stability (commonLabels leak)" "$out"
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
  validate_render "component separation (CronJob/hook-Job vs main workload)" "$out"
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

echo "==> annotation precedence: resource-specific beats commonAnnotations"
# Sprig `merge` keeps EXISTING keys (dest wins), so the old
# `merge (dict) .Values.commonAnnotations <resource>.annotations` silently let
# commonAnnotations override resource-specific annotations on the Ingress and
# the Gateway API routes. Set the same keys in both maps and assert the
# specific value renders (house pattern: range commonAnnotations first, then
# the specific map — last write wins; see _service.yaml).
# Key `precedence` guards the ingress/httpRoute/grpcRoute sites; key `shared`
# (set only in commonAnnotations and gatewayApi.annotations) guards the shared
# gatewayApi map, which route-specific overrides would otherwise mask.
if out=$("$RENDER" full \
    --set commonAnnotations.precedence=common \
    --set commonAnnotations.shared=common \
    --set ingress.annotations.precedence=ingress \
    --set gatewayApi.annotations.precedence=gateway \
    --set gatewayApi.annotations.shared=gateway \
    --set gatewayApi.httpRoute.annotations.precedence=http \
    --set gatewayApi.grpcRoute.enabled=true \
    --set gatewayApi.grpcRoute.annotations.precedence=grpc 2>&1); then
  validate_render "annotation precedence (Ingress/HTTPRoute/GRPCRoute)" "$out"
  ing=$(grep -c 'precedence: "ingress"' <<<"$out" || true)
  http=$(grep -c 'precedence: "http"' <<<"$out" || true)
  grpc=$(grep -c 'precedence: "grpc"' <<<"$out" || true)
  gw_shared=$(grep -c 'shared: "gateway"' <<<"$out" || true)
  gw_leak=$(grep -c 'precedence: "gateway"' <<<"$out" || true)
  if [[ "$ing" -eq 1 && "$http" -eq 1 && "$grpc" -eq 1 && "$gw_shared" -eq 2 && "$gw_leak" -eq 0 ]]; then
    echo "  OK: resource-specific annotations win over commonAnnotations (Ingress/HTTPRoute/GRPCRoute)"
  else
    echo "  FAIL: annotation precedence inverted — expected ingress/http/grpc counts 1/1/1, shared-gateway 2, leaked-gateway 0; got $ing/$http/$grpc, $gw_shared, $gw_leak (commonAnnotations must not override resource-specific annotations)"; fail=1
  fi
else
  echo "  FAIL: render failed for annotation-precedence check"; echo "$out" | tail -3; fail=1
fi

echo "==> Gateway API apiVersion negotiation (no hardcoded default)"
# gatewayApi.apiVersion ships empty so each route negotiates its own Kind
# through the capability registry; a non-empty value is an explicit override.
# Clear the fixture's capabilities.apiVersions force-assume list so the
# --api-versions flags (full group/version/Kind form) are the only statement
# of what the cluster serves, then check a pre-1.0 Gateway API install.
if out=$("$RENDER" full --set capabilities.apiVersions=null \
    --set gatewayApi.grpcRoute.enabled=true \
    --api-versions gateway.networking.k8s.io/v1beta1/HTTPRoute \
    --api-versions gateway.networking.k8s.io/v1alpha2/GRPCRoute 2>&1); then
  validate_render "Gateway API negotiation (pre-1.0: HTTPRoute v1beta1, GRPCRoute v1alpha2)" "$out"
  http_api=$(grep -B1 '^kind: HTTPRoute$' <<<"$out" | grep '^apiVersion:' || true)
  grpc_api=$(grep -B1 '^kind: GRPCRoute$' <<<"$out" | grep '^apiVersion:' || true)
  if [[ "$http_api" == "apiVersion: gateway.networking.k8s.io/v1beta1" \
     && "$grpc_api" == "apiVersion: gateway.networking.k8s.io/v1alpha2" ]]; then
    echo "  OK: routes negotiate per Kind on a pre-1.0 Gateway API cluster (HTTPRoute v1beta1, GRPCRoute v1alpha2)"
  else
    echo "  FAIL: expected negotiated HTTPRoute v1beta1 / GRPCRoute v1alpha2, got '${http_api:-none}' / '${grpc_api:-none}' (a hardcoded gatewayApi.apiVersion default defeats negotiation and can emit an unserved apiVersion)"; fail=1
  fi
else
  echo "  FAIL: render failed for v1beta1/v1alpha2 negotiation check"; echo "$out" | tail -3; fail=1
fi
if out=$("$RENDER" full --set capabilities.apiVersions=null \
    --api-versions gateway.networking.k8s.io/v1/HTTPRoute 2>&1); then
  validate_render "Gateway API negotiation (v1 served)" "$out"
  http_api=$(grep -B1 '^kind: HTTPRoute$' <<<"$out" | grep '^apiVersion:' || true)
  if [[ "$http_api" == "apiVersion: gateway.networking.k8s.io/v1" ]]; then
    echo "  OK: HTTPRoute still negotiates v1 when v1 is served"
  else
    echo "  FAIL: expected negotiated HTTPRoute apiVersion v1, got '${http_api:-none}'"; fail=1
  fi
else
  echo "  FAIL: render failed for v1 negotiation check"; echo "$out" | tail -3; fail=1
fi
# The shared gatewayApi.apiVersion override applies to BOTH routes, and the
# versions are not interchangeable: GRPCRoute has no v1beta1 upstream. The
# per-route override is what makes the shared one usable here, so this leg
# asserts the two-level precedence (per-route beats shared beats negotiated)
# rather than the shared key alone.
if out=$("$RENDER" full --set gatewayApi.apiVersion=gateway.networking.k8s.io/v1beta1 \
  --set gatewayApi.grpcRoute.apiVersion=gateway.networking.k8s.io/v1alpha2 2>&1); then
  validate_render "Gateway API negotiation (explicit override)" "$out"
  http_api=$(grep -B1 '^kind: HTTPRoute$' <<<"$out" | grep '^apiVersion:' || true)
  grpc_api=$(grep -B1 '^kind: GRPCRoute$' <<<"$out" | grep '^apiVersion:' || true)
  if [[ "$http_api" == "apiVersion: gateway.networking.k8s.io/v1beta1" ]]; then
    echo "  OK: explicit gatewayApi.apiVersion override still wins over negotiation"
  else
    echo "  FAIL: expected overridden HTTPRoute apiVersion v1beta1, got '${http_api:-none}'"; fail=1
  fi
  if [[ "$grpc_api" == "apiVersion: gateway.networking.k8s.io/v1alpha2" ]]; then
    echo "  OK: per-route grpcRoute.apiVersion beats the shared gatewayApi.apiVersion"
  else
    echo "  FAIL: expected per-route GRPCRoute apiVersion v1alpha2, got '${grpc_api:-none}'"; fail=1
  fi
else
  echo "  FAIL: render failed for explicit-override check"; echo "$out" | tail -3; fail=1
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

echo "==> tlsSelfSigned.mtls guards"
# mtls.enabled requires tlsSelfSigned.enabled=true. This guard is evaluated
# unconditionally (not nested under tlsSelfSigned.enabled), so it must be
# provable even when tlsSelfSigned is off — use minimal, which defaults
# tlsSelfSigned.enabled=false, rather than full (certificate.enabled=true
# there would trip the TLS mechanism collision guard first) or daemon
# (tlsSelfSigned.enabled=true there by default).
if out=$("$RENDER" minimal --set tlsSelfSigned.mtls.enabled=true 2>&1); then
  echo "  FAIL: render succeeded with tlsSelfSigned.mtls.enabled=true and tlsSelfSigned.enabled=false"; fail=1
elif grep -q "tlsSelfSigned.mtls.enabled is true but tlsSelfSigned.enabled is false" <<<"$out"; then
  echo "  OK: mtls without tlsSelfSigned.enabled rejected"
else
  echo "  FAIL: mtls/tlsSelfSigned collision failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# clients must be non-empty when mtls.enabled. daemon fixture has
# tlsSelfSigned.mtls.enabled=true with 2 clients by default.
if out=$("$RENDER" daemon --set tlsSelfSigned.mtls.clients=null 2>&1); then
  echo "  FAIL: render succeeded with tlsSelfSigned.mtls.enabled=true and empty clients"; fail=1
elif grep -q "tlsSelfSigned.mtls.clients is empty" <<<"$out"; then
  echo "  OK: mtls with empty clients rejected"
else
  echo "  FAIL: empty mtls.clients failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# client name must be a DNS-1123 label, unique, and not collide with a
# reserved release Secret name suffix. --skip-schema-validation: the
# reference schema's own pattern constraint on clients[].name would
# otherwise reject this before the template guard runs — same reasoning as
# the ExternalName/certificate.issuer legs above.
if out=$("$RENDER" daemon --skip-schema-validation --set 'tlsSelfSigned.mtls.clients[0].name=Worker_1' \
    --set 'tlsSelfSigned.mtls.clients[1].name=reader' 2>&1); then
  echo "  FAIL: render succeeded with an invalid mtls client name"; fail=1
elif grep -q "is not a valid DNS-1123 label" <<<"$out"; then
  echo "  OK: invalid mtls client name rejected"
else
  echo "  FAIL: invalid mtls client name failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" daemon --set 'tlsSelfSigned.mtls.clients[0].name=worker' \
    --set 'tlsSelfSigned.mtls.clients[1].name=worker' 2>&1); then
  echo "  FAIL: render succeeded with duplicate mtls client names"; fail=1
elif grep -q "contains duplicate name" <<<"$out"; then
  echo "  OK: duplicate mtls client name rejected"
else
  echo "  FAIL: duplicate mtls client name failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" daemon --set 'tlsSelfSigned.mtls.clients[0].name=worker-ca' \
    --set 'tlsSelfSigned.mtls.clients[1].name=reader' 2>&1); then
  echo "  FAIL: render succeeded with a reserved-suffix mtls client name"; fail=1
elif grep -q "collides with a reserved release Secret name pattern" <<<"$out"; then
  echo "  OK: reserved-suffix mtls client name rejected"
else
  echo "  FAIL: reserved-suffix mtls client name failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# Per-container mount coverage: the daemon fixture's pod has a main
# container, 2 sidecars (metrics-proxy, log-shipper), and 1 initContainer
# (init-wait) — 4 containers total. mtls.mount.enabled must wire the same 4
# volumeMounts (server, 2 clients, ca-bundle) into ALL of them, not just the
# main container. mountPath only appears under containers[].volumeMounts
# (the pod-level volumes: block uses secretName/configMap.name instead), so
# counting mountPath occurrences is a clean per-container-instance count.
if out=$("$RENDER" daemon 2>&1); then
  validate_render "mtls mount coverage (daemon, per-container)" "$out"
  server_mounts=$(grep -c 'mountPath: /etc/platform-tls/server$' <<<"$out" || true)
  worker_mounts=$(grep -c 'mountPath: /etc/platform-tls/client-worker$' <<<"$out" || true)
  reader_mounts=$(grep -c 'mountPath: /etc/platform-tls/client-reader$' <<<"$out" || true)
  ca_mounts=$(grep -c 'mountPath: /etc/platform-tls/ca$' <<<"$out" || true)
  if [[ "$server_mounts" -eq 4 && "$worker_mounts" -eq 4 && "$reader_mounts" -eq 4 && "$ca_mounts" -eq 4 ]]; then
    echo "  OK: all 4 mtls mounts (server/client-worker/client-reader/ca) present in all 4 containers"
  else
    echo "  FAIL: expected 4/4/4/4 mtls mounts (server/worker/reader/ca) across containers, got $server_mounts/$worker_mounts/$reader_mounts/$ca_mounts"; fail=1
  fi
  # Isolate the pod-level volumes: list (a single list, not per-container) so
  # this can't accidentally double-count the volumeMounts already checked
  # above. Sprig's toYaml sorts dict keys alphabetically, so the ca-bundle
  # entry's own "name" key sorts after "configMap" and lands on a
  # continuation line rather than the leading "- name:" the other 3 use —
  # match on the isolated block's content, not a single line shape.
  volumes_block=$(awk '/^      volumes:$/{flag=1; next} /^      [a-zA-Z]/{flag=0} flag' <<<"$out")
  volumes=$(grep -c 'name: mtls-' <<<"$volumes_block" || true)
  if [[ "$volumes" -eq 4 ]]; then
    echo "  OK: exactly 4 pod-level mtls volumes (not duplicated per container)"
  else
    echo "  FAIL: expected 4 pod-level mtls volumes, got $volumes"; fail=1
  fi
else
  echo "  FAIL: render failed for mtls mount coverage check"; echo "$out" | tail -5; fail=1
fi

echo "==> HPA/VPA conflict guard"
# full fixture already has autoscaling.enabled=true (targetCPU 80) and
# verticalAutoscaling.enabled=true with updateMode "Off" (recommend-only,
# allowed alongside HPA). Flipping updateMode to an actively-mutating mode
# must fail closed: HPA and VPA fighting over the same CPU/memory target is
# a known anti-pattern.
if out=$("$RENDER" full --set verticalAutoscaling.updateMode=Auto 2>&1); then
  echo "  FAIL: render succeeded with autoscaling.enabled and verticalAutoscaling.updateMode=Auto both true"; fail=1
elif grep -q "HPA and VPA fighting over the same resource" <<<"$out"; then
  echo "  OK: HPA/VPA CPU-memory conflict rejected"
else
  echo "  FAIL: HPA/VPA conflict failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# updateMode: Off is the escape hatch — recommend-only VPA must coexist with HPA.
if out=$("$RENDER" full 2>&1); then
  if grep -q '^kind: VerticalPodAutoscaler$' <<<"$out"; then
    echo "  OK: verticalAutoscaling.updateMode=Off renders alongside autoscaling.enabled"
  else
    echo "  FAIL: VerticalPodAutoscaler did not render with updateMode=Off"; fail=1
  fi
else
  echo "  FAIL: full fixture render failed (updateMode=Off should coexist with HPA)"; echo "$out" | tail -3; fail=1
fi

# verticalAutoscaling.updateMode is validated at template time too (defense in
# depth beyond the values schema): an invalid value fails closed naming the
# allowed set. --skip-schema-validation isolates the template-level guard from
# the schema-level rejection of the same bad value.
if out=$("$RENDER" minimal --set verticalAutoscaling.enabled=true \
    --set verticalAutoscaling.updateMode=Bogus \
    --api-versions autoscaling.k8s.io/v1/VerticalPodAutoscaler \
    --skip-schema-validation 2>&1); then
  echo "  FAIL: render succeeded with an invalid verticalAutoscaling.updateMode"; fail=1
elif grep -q 'verticalAutoscaling.updateMode "Bogus" is invalid' <<<"$out"; then
  echo "  OK: invalid verticalAutoscaling.updateMode rejected at template time"
else
  echo "  FAIL: invalid updateMode failed without the expected message"; echo "$out" | tail -3; fail=1
fi

echo "==> TLS secret name convergence (ingress <-> managed cert sources)"
# tlsSelfSigned writes the Secret named by platform.tlsSecretName; the Ingress
# spec.tls default must reference the SAME Secret. (Historically it defaulted
# to "<hostname>-tls", which nothing creates unless hostname == fullname.)
# secretName appears only under spec.tls within the Ingress document, so the
# doc_of-scoped grep needs no indent gymnastics.
# (service.enabled=true because the daemon fixture has no Service and the
# ingress-without-service guard would otherwise fail these renders.)
ingress_tls_secret_of() {
  doc_of Ingress "$1" | awk '/^ *secretName: /{print $2; exit}'
}
if out=$("$RENDER" daemon --set ingress.enabled=true --set ingress.tls=true \
  --set service.enabled=true 2>&1); then
  validate_render "TLS secret convergence (daemon, tlsSelfSigned)" "$out"
  # kind+type keyed: the name of the server kubernetes.io/tls Secret document.
  # mtls (default-enabled on this fixture) also writes a CA Secret
  # (<fullname>-ca) and one per client (<fullname>-mtls-client-<name>), all
  # equally type: kubernetes.io/tls — exclude those so this stays scoped to
  # the one Secret the Ingress is actually supposed to converge on.
  tls_secret=$(awk '
    function flush() { if (kd == "Secret" && tls && nm !~ /-ca$/ && nm !~ /-mtls-client-/) print nm; kd = ""; nm = ""; tls = 0 }
    /^---[[:space:]]*$/ { flush(); next }
    /^kind: / { kd = $2 }
    /^  name: / && nm == "" { nm = $2 }
    /^type: kubernetes.io\/tls$/ { tls = 1 }
    END { flush() }' <<<"$out")
  ing_secret=$(ingress_tls_secret_of t-daemon <<<"$out")
  if [[ -n "$tls_secret" && "$ing_secret" == "$tls_secret" ]]; then
    echo "  OK: Ingress spec.tls references the tlsSelfSigned Secret ($tls_secret)"
  else
    echo "  FAIL: tlsSelfSigned writes Secret '$tls_secret' but Ingress spec.tls references '$ing_secret'"; fail=1
  fi
else
  echo "  FAIL: render failed for daemon with ingress + tlsSelfSigned TLS"; echo "$out" | tail -3; fail=1
fi

# Same convergence for cert-manager: the Ingress default must equal the
# Certificate's spec.secretName (full fixture has certificate.enabled=true).
if out=$("$RENDER" full --set ingress.tls=true 2>&1); then
  validate_render "TLS secret convergence (full, cert-manager Certificate)" "$out"
  cert_secret=$(doc_of Certificate t-full-tls <<<"$out" | awk '/^  secretName: /{print $2; exit}')
  ing_secret=$(ingress_tls_secret_of t-full <<<"$out")
  if [[ -n "$cert_secret" && "$ing_secret" == "$cert_secret" ]]; then
    echo "  OK: Ingress spec.tls references the Certificate's secretName ($cert_secret)"
  else
    echo "  FAIL: Certificate targets Secret '$cert_secret' but Ingress spec.tls references '$ing_secret'"; fail=1
  fi
else
  echo "  FAIL: render failed for full with ingress.tls + certificate"; echo "$out" | tail -3; fail=1
fi

# ingress.existingSecret still beats every managed default.
if out=$("$RENDER" daemon --set ingress.enabled=true --set ingress.tls=true \
  --set service.enabled=true --set ingress.existingSecret=byo-tls 2>&1); then
  validate_render "TLS secret convergence (ingress.existingSecret override)" "$out"
  ing_secret=$(ingress_tls_secret_of t-daemon <<<"$out")
  if [[ "$ing_secret" == "byo-tls" ]]; then
    echo "  OK: ingress.existingSecret overrides the managed TLS secret name"
  else
    echo "  FAIL: ingress.existingSecret=byo-tls but Ingress spec.tls references '$ing_secret'"; fail=1
  fi
else
  echo "  FAIL: render failed for daemon with ingress.existingSecret"; echo "$out" | tail -3; fail=1
fi

# No managed cert source: the conventional "<hostname>-tls" fallback is kept
# (consumer provisions it; library default hostname is app.local).
if out=$("$RENDER" minimal --set ingress.enabled=true --set ingress.tls=true 2>&1); then
  validate_render "TLS secret convergence (no managed cert source, fallback)" "$out"
  ing_secret=$(ingress_tls_secret_of t-minimal <<<"$out")
  if [[ "$ing_secret" == "app.local-tls" ]]; then
    echo "  OK: without a managed cert source the <hostname>-tls fallback is preserved"
  else
    echo "  FAIL: expected fallback secretName 'app.local-tls', got '$ing_secret'"; fail=1
  fi
else
  echo "  FAIL: render failed for minimal with ingress.tls"; echo "$out" | tail -3; fail=1
fi

echo "==> Cross-field guards (ExternalName / certificate.issuer / dangling backends)"
# Three cross-field combinations used to render objects the API server rejects
# or that dangle against a Service that does not exist. Each now fails at
# template time with a prescriptive message. The ExternalName and issuer legs
# use --skip-schema-validation because the helm-side schema also rejects those
# values — the template guard is the layer that survives consumer schema drift.

# ExternalName is now supported properly: type + externalName only, no
# ports/selector (the API server rejects ExternalName without externalName,
# and ports/selector are meaningless for it).
if out=$("$RENDER" minimal --set service.type=ExternalName \
  --set service.externalName=db.example.com 2>&1); then
  validate_render "ExternalName Service (valid render)" "$out"
  svc_doc=$(doc_of Service t-minimal <<<"$out")
  if grep -q '^  externalName: db.example.com$' <<<"$svc_doc" \
    && ! grep -q '^  selector:' <<<"$svc_doc" && ! grep -q '^  ports:' <<<"$svc_doc"; then
    echo "  OK: ExternalName Service renders spec.externalName with no ports/selector"
  else
    echo "  FAIL: ExternalName Service must render spec.externalName and omit ports/selector"; echo "$svc_doc" | tail -8; fail=1
  fi
else
  echo "  FAIL: render failed for minimal with a valid ExternalName Service"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --skip-schema-validation --set service.type=ExternalName 2>&1); then
  echo "  FAIL: render succeeded with service.type=ExternalName and no service.externalName"; fail=1
elif grep -q "service.type is ExternalName but service.externalName is empty" <<<"$out"; then
  echo "  OK: ExternalName without service.externalName rejected"
else
  echo "  FAIL: ExternalName without externalName failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" full --skip-schema-validation --set certificate.issuer= 2>&1); then
  echo "  FAIL: render succeeded with certificate.enabled=true and an empty certificate.issuer"; fail=1
elif grep -q "certificate.enabled is true but certificate.issuer is empty" <<<"$out"; then
  echo "  OK: certificate with empty issuer rejected"
else
  echo "  FAIL: empty certificate.issuer failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --set ingress.enabled=true --set service.enabled=false 2>&1); then
  echo "  FAIL: render succeeded with ingress.enabled=true and service.enabled=false"; fail=1
elif grep -q "ingress.enabled is true but service.enabled is false" <<<"$out"; then
  echo "  OK: ingress without the backing Service rejected"
else
  echo "  FAIL: ingress-without-service failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# Gateway API routes default their backendRefs to the release Service; guard
# fires only for that defaulted path — explicit backendRefs stay allowed.
# webhooks.enabled=false: full's fixture defaults webhooks on, and its own
# service.enabled guard would otherwise fire first and mask the guard this
# test targets.
if out=$("$RENDER" full --set service.enabled=false --set ingress.enabled=false \
  --set webhooks.enabled=false 2>&1); then
  echo "  FAIL: render succeeded with a defaulted HTTPRoute backend and service.enabled=false"; fail=1
elif grep -q "gatewayApi.httpRoute has no backendRefs" <<<"$out"; then
  echo "  OK: defaulted HTTPRoute backend without the Service rejected"
else
  echo "  FAIL: defaulted-backend-without-service failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# The GRPCRoute leg of the same guard: it defaults its backendRefs identically,
# and is reached only once HTTPRoute's copy is satisfied (explicit backendRefs
# below), so it needs its own negative render or the branch stays dead.
if out=$("$RENDER" full --set service.enabled=false --set ingress.enabled=false \
  --set webhooks.enabled=false \
  --set 'gatewayApi.httpRoute.backendRefs[0].name=other' \
  --set 'gatewayApi.httpRoute.backendRefs[0].port=8080' 2>&1); then
  echo "  FAIL: render succeeded with a defaulted GRPCRoute backend and service.enabled=false"; fail=1
elif grep -q "gatewayApi.grpcRoute has no backendRefs" <<<"$out"; then
  echo "  OK: defaulted GRPCRoute backend without the Service rejected"
else
  echo "  FAIL: defaulted-GRPCRoute-backend-without-service failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" full --set service.enabled=false --set ingress.enabled=false \
  --set webhooks.enabled=false \
  --set 'gatewayApi.httpRoute.backendRefs[0].name=other' \
  --set 'gatewayApi.httpRoute.backendRefs[0].port=8080' \
  --set 'gatewayApi.grpcRoute.backendRefs[0].name=other-grpc' \
  --set 'gatewayApi.grpcRoute.backendRefs[0].port=9090' 2>&1); then
  validate_render "HTTPRoute/GRPCRoute explicit backendRefs (no release Service)" "$out"
  echo "  OK: explicit route backendRefs render without the release Service"
else
  echo "  FAIL: explicit backendRefs must not require service.enabled"; echo "$out" | tail -3; fail=1
fi

# parentRefs is REQUIRED on every route — a route with none is accepted by the
# API server and attaches to nothing. Both legs fall back to gatewayApi.parentRefs,
# so each negative render clears the shared base plus that route's own list. The
# HTTPRoute check runs first in the template, so the GRPCRoute leg must leave
# HTTPRoute's own parentRefs intact to reach its guard at all. Schema-skipped:
# the reference schema also requires parentRefs, and the template guard is the
# layer that survives consumer schema drift.
if out=$("$RENDER" full --skip-schema-validation --set gatewayApi.parentRefs=null \
  --set gatewayApi.httpRoute.parentRefs=null 2>&1); then
  echo "  FAIL: render succeeded with gatewayApi.httpRoute.enabled and no parentRefs"; fail=1
elif grep -q "gatewayApi.httpRoute.enabled but no parentRefs configured" <<<"$out"; then
  echo "  OK: HTTPRoute without parentRefs rejected"
else
  echo "  FAIL: HTTPRoute-without-parentRefs failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" full --skip-schema-validation --set gatewayApi.parentRefs=null \
  --set gatewayApi.grpcRoute.parentRefs=null 2>&1); then
  echo "  FAIL: render succeeded with gatewayApi.grpcRoute.enabled and no parentRefs"; fail=1
elif grep -q "gatewayApi.grpcRoute.enabled but no parentRefs configured" <<<"$out"; then
  echo "  OK: GRPCRoute without parentRefs rejected"
else
  echo "  FAIL: GRPCRoute-without-parentRefs failed without the expected message"; echo "$out" | tail -3; fail=1
fi

echo "==> webhooks guardrails"
# clientConfig.service on every webhook item targets the release Service.
if out=$("$RENDER" minimal --set webhooks.enabled=true --set service.enabled=false 2>&1); then
  echo "  FAIL: render succeeded with webhooks.enabled=true and service.enabled=false"; fail=1
elif grep -q "webhooks.enabled is true but service.enabled is false" <<<"$out"; then
  echo "  OK: webhooks without the backing Service rejected"
else
  echo "  FAIL: webhooks-without-service failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --set webhooks.enabled=true 2>&1); then
  echo "  FAIL: render succeeded with webhooks.enabled=true and no validating/mutating entries"; fail=1
elif grep -q "webhooks.enabled is true but both webhooks.validating and webhooks.mutating are empty" <<<"$out"; then
  echo "  OK: webhooks with no entries rejected"
else
  echo "  FAIL: empty webhooks.validating/mutating failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# --skip-schema-validation: the reference schema's own required:[name,path,rules]
# would otherwise reject these before the template guard runs — same reasoning
# as the ExternalName/certificate.issuer/mtls-client-name legs above.
if out=$("$RENDER" minimal --skip-schema-validation --set webhooks.enabled=true \
    --set 'webhooks.validating[0].path=/validate' \
    --set 'webhooks.validating[0].rules[0].apiGroups[0]=' \
    --set 'webhooks.validating[0].rules[0].apiVersions[0]=v1' \
    --set 'webhooks.validating[0].rules[0].operations[0]=CREATE' \
    --set 'webhooks.validating[0].rules[0].resources[0]=pods' 2>&1); then
  echo "  FAIL: render succeeded with a webhooks.validating entry missing name"; fail=1
elif grep -q 'webhooks.validating\[0\].name is required' <<<"$out"; then
  echo "  OK: validating entry missing name rejected"
else
  echo "  FAIL: missing validating name failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --skip-schema-validation --set webhooks.enabled=true \
    --set 'webhooks.validating[0].name=validate.example.com' \
    --set 'webhooks.validating[0].rules[0].apiGroups[0]=' \
    --set 'webhooks.validating[0].rules[0].apiVersions[0]=v1' \
    --set 'webhooks.validating[0].rules[0].operations[0]=CREATE' \
    --set 'webhooks.validating[0].rules[0].resources[0]=pods' 2>&1); then
  echo "  FAIL: render succeeded with a webhooks.validating entry missing path"; fail=1
elif grep -q 'webhooks.validating\[0\].path is required' <<<"$out"; then
  echo "  OK: validating entry missing path rejected"
else
  echo "  FAIL: missing validating path failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --skip-schema-validation --set webhooks.enabled=true \
    --set 'webhooks.validating[0].name=validate.example.com' \
    --set 'webhooks.validating[0].path=/validate' 2>&1); then
  echo "  FAIL: render succeeded with a webhooks.validating entry missing rules"; fail=1
elif grep -q 'webhooks.validating\[0\].rules is required and must be non-empty' <<<"$out"; then
  echo "  OK: validating entry missing rules rejected"
else
  echo "  FAIL: missing validating rules failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# The mutating leg is a separately-ranged block with its own fail message —
# prove it independently rather than assuming the validating leg's coverage
# extends to it.
if out=$("$RENDER" minimal --skip-schema-validation --set webhooks.enabled=true \
    --set 'webhooks.mutating[0].path=/mutate' \
    --set 'webhooks.mutating[0].rules[0].apiGroups[0]=' \
    --set 'webhooks.mutating[0].rules[0].apiVersions[0]=v1' \
    --set 'webhooks.mutating[0].rules[0].operations[0]=CREATE' \
    --set 'webhooks.mutating[0].rules[0].resources[0]=pods' 2>&1); then
  echo "  FAIL: render succeeded with a webhooks.mutating entry missing name"; fail=1
elif grep -q 'webhooks.mutating\[0\].name is required' <<<"$out"; then
  echo "  OK: mutating entry missing name rejected"
else
  echo "  FAIL: missing mutating name failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --skip-schema-validation --set webhooks.enabled=true \
    --set 'webhooks.mutating[0].name=mutate.example.com' \
    --set 'webhooks.mutating[0].rules[0].apiGroups[0]=' \
    --set 'webhooks.mutating[0].rules[0].apiVersions[0]=v1' \
    --set 'webhooks.mutating[0].rules[0].operations[0]=CREATE' \
    --set 'webhooks.mutating[0].rules[0].resources[0]=pods' 2>&1); then
  echo "  FAIL: render succeeded with a webhooks.mutating entry missing path"; fail=1
elif grep -q 'webhooks.mutating\[0\].path is required' <<<"$out"; then
  echo "  OK: mutating entry missing path rejected"
else
  echo "  FAIL: missing mutating path failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# The mutating leg's rules guard was covered in the template from the start
# but had no lint test proving it — add it alongside path for full independent
# coverage of the mutating range, matching the validating range above.
if out=$("$RENDER" minimal --skip-schema-validation --set webhooks.enabled=true \
    --set 'webhooks.mutating[0].name=mutate.example.com' \
    --set 'webhooks.mutating[0].path=/mutate' 2>&1); then
  echo "  FAIL: render succeeded with a webhooks.mutating entry missing rules"; fail=1
elif grep -q 'webhooks.mutating\[0\].rules is required and must be non-empty' <<<"$out"; then
  echo "  OK: mutating entry missing rules rejected"
else
  echo "  FAIL: missing mutating rules failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# Per-container mount coverage: the daemon fixture's pod has a main
# container, 2 sidecars (metrics-proxy, log-shipper), and 1 initContainer
# (init-wait) — 4 containers total, same shape the mtls coverage check above
# exercises. webhooks.enabled must wire the serving-cert mount into ALL of
# them via the same $mtlsMounts/$mtlsVolumes mechanism. daemon defaults
# service.enabled to false (no explicit service: block), so it is set
# explicitly here. Also asserts caBundle on both webhook items byte-equals
# the Secret's ca.crt — doc_of isolates the webhook-cert Secret specifically,
# since daemon's tlsSelfSigned.enabled=true default renders its own Secret
# with the same ca.crt/tls.crt/tls.key key names.
if out=$("$RENDER" daemon --set service.enabled=true --set webhooks.enabled=true \
    --set 'webhooks.validating[0].name=validate.example.com' \
    --set 'webhooks.validating[0].path=/validate' \
    --set 'webhooks.validating[0].rules[0].apiGroups[0]=' \
    --set 'webhooks.validating[0].rules[0].apiVersions[0]=v1' \
    --set 'webhooks.validating[0].rules[0].operations[0]=CREATE' \
    --set 'webhooks.validating[0].rules[0].resources[0]=pods' \
    --set 'webhooks.mutating[0].name=mutate.example.com' \
    --set 'webhooks.mutating[0].path=/mutate' \
    --set 'webhooks.mutating[0].rules[0].apiGroups[0]=' \
    --set 'webhooks.mutating[0].rules[0].apiVersions[0]=v1' \
    --set 'webhooks.mutating[0].rules[0].operations[0]=CREATE' \
    --set 'webhooks.mutating[0].rules[0].resources[0]=pods' 2>&1); then
  validate_render "webhooks mount coverage (daemon, per-container)" "$out"
  webhook_mounts=$(grep -c 'mountPath: /etc/webhook-tls$' <<<"$out" || true)
  if [[ "$webhook_mounts" -eq 4 ]]; then
    echo "  OK: webhook-tls mount present in all 4 containers"
  else
    echo "  FAIL: expected 4 webhook-tls mounts across containers, got $webhook_mounts"; fail=1
  fi
  secret_doc=$(doc_of "Secret" "t-daemon-webhook-cert" <<<"$out")
  ca_crt=$(grep '^  ca\.crt: ' <<<"$secret_doc" | awk '{print $2}')
  bundle_count=$(grep -c "^      caBundle: $ca_crt\$" <<<"$out" || true)
  if [[ -n "$ca_crt" && "$bundle_count" -eq 2 ]]; then
    echo "  OK: caBundle byte-equals the Secret's ca.crt on both webhook items"
  else
    echo "  FAIL: expected 2 caBundle occurrences equal to ca.crt, got $bundle_count (ca_crt empty: $([[ -z "$ca_crt" ]] && echo yes || echo no))"; fail=1
  fi
else
  echo "  FAIL: render failed for webhooks mount coverage check"; echo "$out" | tail -5; fail=1
fi

echo "==> hook script source guard"
# jobs.*.scriptFile silently produced an EMPTY script.sh when the file was
# missing from the consumer chart: the hook Job then ran a no-op and reported
# success, so a failed migration looked like a clean install.
if out=$("$RENDER" full --set jobs.preInstall.script=null \
  --set jobs.preInstall.scriptFile=does-not-exist.sh 2>&1); then
  echo "  FAIL: render succeeded with jobs.preInstall.scriptFile pointing at a missing file"; fail=1
elif grep -q "Script file not found: does-not-exist.sh" <<<"$out"; then
  echo "  OK: missing scriptFile rejected by name"
else
  echo "  FAIL: missing scriptFile failed without the expected message"; echo "$out" | tail -3; fail=1
fi

echo "==> ResourceQuota / LimitRange / PrometheusRule guardrails (empty spec enforces nothing)"
if out=$("$RENDER" minimal --skip-schema-validation --set resourceQuota.enabled=true 2>&1); then
  echo "  FAIL: render succeeded with resourceQuota.enabled=true and no resourceQuota.hard"; fail=1
elif grep -q "resourceQuota.enabled is true but resourceQuota.hard is empty" <<<"$out"; then
  echo "  OK: resourceQuota with empty hard rejected"
else
  echo "  FAIL: empty resourceQuota.hard failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --set resourceQuota.enabled=true --set resourceQuota.hard.pods=10 2>&1); then
  echo "  OK: resourceQuota with hard set renders"
else
  echo "  FAIL: resourceQuota with hard.pods set must render"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --skip-schema-validation --set limitRange.enabled=true 2>&1); then
  echo "  FAIL: render succeeded with limitRange.enabled=true and no default/defaultRequest/max/min"; fail=1
elif grep -q "limitRange.enabled is true but none of limitRange.default" <<<"$out"; then
  echo "  OK: limitRange with no bounds rejected"
else
  echo "  FAIL: empty limitRange failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --set limitRange.enabled=true --set limitRange.min.cpu=50m 2>&1); then
  echo "  OK: limitRange with only min set renders"
else
  echo "  FAIL: limitRange with min set must render"; echo "$out" | tail -3; fail=1
fi

# PrometheusRule is capability-gated, so the gate must be forced open with the
# full group/version/Kind form for the generator (and its guard) to run at all.
if out=$("$RENDER" minimal --skip-schema-validation \
  --api-versions monitoring.coreos.com/v1/PrometheusRule \
  --set prometheusRule.enabled=true 2>&1); then
  echo "  FAIL: render succeeded with prometheusRule.enabled=true and no prometheusRule.groups"; fail=1
elif grep -q "prometheusRule.enabled is true but prometheusRule.groups is empty" <<<"$out"; then
  echo "  OK: prometheusRule with empty groups rejected"
else
  echo "  FAIL: empty prometheusRule.groups failed without the expected message"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" minimal --skip-schema-validation \
  --api-versions monitoring.coreos.com/v1/PrometheusRule \
  --set prometheusRule.enabled=true \
  --set prometheusRule.groups[0].name=basic 2>&1); then
  echo "  OK: prometheusRule with a group set renders"
else
  echo "  FAIL: prometheusRule with a group set must render"; echo "$out" | tail -3; fail=1
fi

echo "==> RBAC binds the chart's OWN identity (helm-factory-buw)"
# The whole point of the generator is that the consumer never writes a subject
# name by hand: the RoleBinding must resolve through platform.serviceAccountName
# so it tracks the ServiceAccount the pods actually use. A hardcoded fullname
# renders identically in the default case and only breaks under an override —
# so the override case is the assertion that matters.
if out=$("$RENDER" full 2>&1); then
  rb=$(doc_of RoleBinding t-full <<<"$out")
  role=$(doc_of Role t-full <<<"$out")
  sa_subject=$(awk '/^subjects:/{s=1} s && /name:/{print $2; exit}' <<<"$rb")
  role_ref=$(awk '/^roleRef:/{s=1} s && /^  name:/{print $2; exit}' <<<"$rb")
  if [[ -n "$role" ]]; then
    echo "  OK: rbac.enabled renders the namespaced Role"
  else
    echo "  FAIL: rbac.enabled=true rendered no Role named t-full"; fail=1
  fi
  if [[ "$role_ref" == "t-full" && "$sa_subject" == "t-full" ]]; then
    echo "  OK: RoleBinding points at the chart's Role and its own ServiceAccount"
  else
    echo "  FAIL: RoleBinding wiring wrong (roleRef=$role_ref subject=$sa_subject, want t-full/t-full)"; fail=1
  fi
else
  echo "  FAIL: full fixture must render with rbac enabled"; echo "$out" | tail -3; fail=1
fi

if out=$("$RENDER" full --set serviceAccount.name=custom-id 2>&1); then
  sa_subject=$(doc_of RoleBinding t-full <<<"$out" | awk '/^subjects:/{s=1} s && /name:/{print $2; exit}')
  if [[ "$sa_subject" == "custom-id" ]]; then
    echo "  OK: RoleBinding subject follows a serviceAccount.name override"
  else
    echo "  FAIL: RoleBinding subject is $sa_subject, want custom-id — the subject is not resolving through platform.serviceAccountName"; fail=1
  fi
else
  echo "  FAIL: full fixture must render with a serviceAccount.name override"; echo "$out" | tail -3; fail=1
fi

# Fail-closed #1: an empty Role grants nothing and surfaces only as a runtime
# 403. The schema catches this too; --skip-schema-validation proves the template
# guard survives a consumer whose values.schema.json copy has drifted.
if out=$("$RENDER" full --skip-schema-validation --set rbac.rules=null 2>&1); then
  echo "  FAIL: render succeeded with rbac.enabled=true and no rbac.rules"; fail=1
elif grep -q "rbac.enabled=true but rbac.rules is empty" <<<"$out"; then
  echo "  OK: rbac with empty rules rejected"
else
  echo "  FAIL: empty rbac.rules failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# Fail-closed #2: the real privilege leak. platform.serviceAccountName falls
# back to "default" when the chart neither creates nor names a ServiceAccount;
# binding the Role there grants the rules to every unowned pod in the namespace.
if out=$("$RENDER" full --set serviceAccount.create=false 2>&1); then
  echo "  FAIL: render succeeded binding the Role to the namespace default ServiceAccount"; fail=1
elif grep -q 'would bind the Role to the "default" namespace' <<<"$out"; then
  echo "  OK: binding to the default ServiceAccount rejected"
else
  echo "  FAIL: default-ServiceAccount binding failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# The grant is inert without a token, and the library default is no token —
# the most likely way to ship this feature and have it silently do nothing.
if out=$(notes_of full --set serviceAccount.automountServiceAccountToken=false 2>&1); then
  if grep -q "rbac.enabled=true but serviceAccount.automountServiceAccountToken is false" <<<"$out"; then
    echo "  OK: RBAC without a mounted token is NOTES-warned"
  else
    echo "  FAIL: no NOTES warning for rbac.enabled with automountServiceAccountToken=false"; fail=1
  fi
else
  echo "  FAIL: notes render failed for the RBAC automount warning"; echo "$out" | tail -3; fail=1
fi

if out=$(notes_of full --set 'rbac.rules[0].apiGroups[0]=*' \
  --set 'rbac.rules[0].resources[0]=*' --set 'rbac.rules[0].verbs[0]=*' 2>&1); then
  if grep -q 'rbac.rules use the "\*" wildcard at rules\[0\].apiGroups, rules\[0\].resources, rules\[0\].verbs' <<<"$out"; then
    echo "  OK: wildcard rbac rules are NOTES-warned with their paths"
  else
    echo "  FAIL: no NOTES warning for wildcard rbac.rules"; fail=1
  fi
else
  echo "  FAIL: notes render failed for the RBAC wildcard warning"; echo "$out" | tail -3; fail=1
fi

echo "==> StatefulSet governing headless Service"
# A StatefulSet's per-pod DNS (<pod>.<svc>.<ns>) only resolves when
# spec.serviceName points at a headless Service that exists. Historically the
# default pointed at "<fullname>" — a Service that may not exist and is a
# ClusterIP VIP when it does. Unless the consumer wires it themselves, the
# library now renders "<fullname>-headless" (clusterIP: None) and points at it.
headless_service_of() {
  # prints "yes" when the render contains a Service named $2 with clusterIP: None
  if doc_of Service "$2" <<<"$1" | grep -q '^  clusterIP: None$'; then echo yes; fi
}
statefulset_service_name_of() {
  doc_of StatefulSet t-stateful | awk '/^  serviceName: /{print $2; exit}'
}
if out=$("$RENDER" stateful 2>&1); then
  validate_render "StatefulSet governing headless Service (default)" "$out"
  svc_name=$(statefulset_service_name_of <<<"$out")
  if [[ "$svc_name" == *-headless && "$(headless_service_of "$out" "$svc_name")" == "yes" ]]; then
    echo "  OK: default StatefulSet render governs via managed headless Service ($svc_name)"
  else
    echo "  FAIL: StatefulSet serviceName '$svc_name' is not a rendered managed headless Service"; fail=1
  fi
else
  echo "  FAIL: render failed for stateful fixture"; echo "$out" | tail -3; fail=1
fi

# Explicit statefulSet.serviceName is consumer-managed: used verbatim, no managed Service.
if out=$("$RENDER" stateful --set statefulSet.serviceName=byo-headless 2>&1); then
  validate_render "StatefulSet governing headless Service (explicit serviceName)" "$out"
  svc_name=$(statefulset_service_name_of <<<"$out")
  extra=$(grep -c '^  name: .*-headless$' <<<"$out" || true)
  if [[ "$svc_name" == "byo-headless" && "$extra" -eq 0 ]]; then
    echo "  OK: explicit statefulSet.serviceName is used verbatim with no managed headless Service"
  else
    echo "  FAIL: statefulSet.serviceName=byo-headless rendered serviceName '$svc_name' with $extra managed headless object(s)"; fail=1
  fi
else
  echo "  FAIL: render failed for stateful with statefulSet.serviceName override"; echo "$out" | tail -3; fail=1
fi

# A primary Service that is already headless (clusterIP: None) governs directly.
if out=$("$RENDER" stateful --set service.clusterIP=None 2>&1); then
  validate_render "StatefulSet governing headless Service (primary Service already headless)" "$out"
  svc_name=$(statefulset_service_name_of <<<"$out")
  extra=$(grep -c '^  name: .*-headless$' <<<"$out" || true)
  if [[ "$svc_name" != *-headless && "$extra" -eq 0 && "$(headless_service_of "$out" "$svc_name")" == "yes" ]]; then
    echo "  OK: headless primary Service (clusterIP: None) governs directly ($svc_name), no extra Service"
  else
    echo "  FAIL: with service.clusterIP=None expected primary Service '$svc_name' to govern; managed headless count=$extra"; fail=1
  fi
else
  echo "  FAIL: render failed for stateful with service.clusterIP=None"; echo "$out" | tail -3; fail=1
fi

# Non-StatefulSet workloads never get the managed headless Service.
if out=$("$RENDER" minimal 2>&1); then
  validate_render "no managed headless Service for non-StatefulSet workloads" "$out"
  if grep -q '^  name: .*-headless$' <<<"$out"; then
    echo "  FAIL: minimal (Deployment) fixture rendered a managed headless Service"; fail=1
  else
    echo "  OK: Deployment fixture renders no managed headless Service"
  fi
else
  echo "  FAIL: render failed for minimal fixture"; echo "$out" | tail -3; fail=1
fi

echo "==> ServiceMonitor does not double-match the managed headless Service"
# Both Services carry identical standard labels, so the default matchLabels
# selector alone selects the primary AND the headless Service — Prometheus
# Operator then generates two scrape targets for the same pods
# (helm-factory-75c). The headless Service is marked platform/service-role and
# the default selector excludes it; an explicit serviceMonitor.selector still
# replaces the whole default.
if out=$("$RENDER" stateful 2>&1); then
  hl=$(doc_of Service t-stateful-headless <<<"$out")
  primary=$(doc_of Service t-stateful <<<"$out")
  sm=$(doc_of ServiceMonitor t-stateful <<<"$out")
  marker_ok=0; primary_clean=0; selector_ok=0
  grep -q '^    platform/service-role: "headless"$' <<<"$hl" && marker_ok=1
  grep -q 'platform/service-role' <<<"$primary" || primary_clean=1
  # the exclusion must live under spec.selector, not anywhere else in the doc
  if awk '/^  selector:$/{s=1;next} /^  [a-zA-Z]/{s=0} s' <<<"$sm" \
       | grep -Fq -- '- key: platform/service-role' \
    && awk '/^  selector:$/{s=1;next} /^  [a-zA-Z]/{s=0} s' <<<"$sm" \
       | grep -Fq -- 'operator: NotIn'; then
    selector_ok=1
  fi
  if [[ $marker_ok -eq 1 && $primary_clean -eq 1 && $selector_ok -eq 1 ]]; then
    echo "  OK: headless Service marked platform/service-role and excluded by the default ServiceMonitor selector"
  else
    echo "  FAIL: headless marker=$marker_ok primary-unmarked=$primary_clean selector-excludes-headless=$selector_ok"; fail=1
  fi
else
  echo "  FAIL: render failed for stateful fixture"; echo "$out" | tail -3; fail=1
fi

# An explicit serviceMonitor.selector is a full override — the library must not
# graft its exclusion onto a consumer-supplied selector.
if out=$("$RENDER" stateful --set 'serviceMonitor.selector.matchLabels.custom=only' 2>&1); then
  sm=$(doc_of ServiceMonitor t-stateful <<<"$out")
  if grep -q '^      custom: only$' <<<"$sm" && ! grep -q 'platform/service-role' <<<"$sm"; then
    echo "  OK: explicit serviceMonitor.selector replaces the default selector verbatim"
  else
    echo "  FAIL: explicit serviceMonitor.selector was not used verbatim"; echo "$sm"; fail=1
  fi
else
  echo "  FAIL: render failed for stateful with serviceMonitor.selector override"; echo "$out" | tail -3; fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "==> FAIL"
elif [[ -n "$degraded" ]]; then
  echo "==> DEGRADED PASS (missing: ${degraded% })"
else
  echo "==> PASS"
fi
exit $fail
