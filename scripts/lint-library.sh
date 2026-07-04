#!/usr/bin/env bash
# =============================================================================
# lint-library.sh — validation gate for the pure platform-library chart.
#
# A library chart is not installable, so we validate it through the test
# consumer fixtures: helm lint the library, then render each fixture across the
# supported Kubernetes version range, run a negative render proving CRD objects
# drop when their API is absent, and pipe through kubeconform.
#
# Usage: scripts/lint-library.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/platform-library"
RENDER="$REPO_ROOT/tests/render.sh"
FIXTURES=(minimal full)
KUBE_VERSIONS=(1.31 1.32 1.33 1.34 1.35 1.36)
fail=0

echo "==> helm lint $LIB"
helm lint "$LIB"

echo "==> reference schema parses"
jq empty "$LIB/values.schema.reference.json" && echo "  values.schema.reference.json OK"

for fx in "${FIXTURES[@]}"; do
  echo "==> render matrix: $fx"
  for kv in "${KUBE_VERSIONS[@]}"; do
    if out=$("$RENDER" "$fx" --kube-version "$kv" 2>&1); then
      echo "  k8s $kv: OK ($(grep -c '^kind:' <<<"$out") objects)"
    else
      echo "  k8s $kv: FAIL"; echo "$out" | tail -5; fail=1
    fi
  done

  if command -v kubeconform >/dev/null 2>&1; then
    echo "==> kubeconform: $fx"
    "$RENDER" "$fx" 2>/dev/null | \
      kubeconform -strict -ignore-missing-schemas -kubernetes-version 1.31.0 -summary || fail=1
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
