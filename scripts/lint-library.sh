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
# when their API is absent, and enforce image pinning.
#
# Usage:
#   scripts/lint-library.sh                        # run all checks
#   UPDATE_GOLDEN=1 scripts/lint-library.sh        # regenerate tests/golden/*.yaml
#   REQUIRE_KUBECONFORM=1 scripts/lint-library.sh  # fail if kubeconform missing (CI)
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
jq empty "$LIB/values.schema.reference.json" && echo "  values.schema.reference.json OK"

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

if [[ $fail -eq 0 ]]; then echo "==> PASS"; else echo "==> FAIL"; fi
exit $fail
