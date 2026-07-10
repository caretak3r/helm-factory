#!/usr/bin/env bash
# Rebuild the platform-library dependency into a fixture and render it.
# Usage: tests/render.sh <fixture> [helm template extra args...]
#   tests/render.sh full
#   tests/render.sh full --kube-version 1.34 --api-versions rbac.authorization.k8s.io/v1
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="${1:?usage: render.sh <fixture> [helm args...]}"; shift || true
dir="$here/fixtures/$fixture"
rm -rf "$dir/charts" "$dir/Chart.lock"
# Enforce the root values contract exactly like a generated consumer chart:
# Helm validates values.schema.json against the coalesced (post-import) values.
cp "$here/../platform-library/values.schema.reference.json" "$dir/values.schema.json"
helm dependency update "$dir" >/dev/null
helm template t "$dir" "$@"
