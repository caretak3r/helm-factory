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

if [[ $fail -eq 0 ]]; then echo "==> PASS"; else echo "==> FAIL"; fi
exit $fail
