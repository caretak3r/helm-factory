#!/usr/bin/env bash
# Rebuild the platform-library dependency into a fixture and render it.
# Usage: tests/render.sh <fixture> [helm template extra args...]
#   tests/render.sh full
#   tests/render.sh full --kube-version 1.31 --api-versions rbac.authorization.k8s.io/v1
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="${1:?usage: render.sh <fixture> [helm args...]}"; shift || true
dir="$here/fixtures/$fixture"
rm -rf "$dir/charts" "$dir/Chart.lock"
helm dependency update "$dir" >/dev/null 2>&1
helm template t "$dir" "$@"
