#!/usr/bin/env bash
# Rebuild the platform-library dependency into a fixture and render it.
# Usage: tests/render.sh <fixture> [helm template extra args...]
#   tests/render.sh full
#   tests/render.sh full --kube-version 1.34 --api-versions cert-manager.io/v1/Certificate
# NOTE: --api-versions needs the full group/version/Kind form; a bare
# group/version does NOT satisfy the capability gate (silent skip, exit 0).
# Only the capabilities.apiVersions values list accepts bare group/version.
#
# The library dependency is served from a content-addressed package cache
# (tests/.dep-cache/<sha256-of-library-contents>/platform-*.tgz) so ~60 gate
# renders don't each pay a full `helm dependency update` (~2.8s -> ~0.1s).
# Any edit under platform-library/ changes the key and forces a repackage.
# RENDER_DEP_CACHE=0 bypasses the cache (plain helm dependency update).
# Safe to `rm -rf tests/.dep-cache` at any time.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="${1:?usage: render.sh <fixture> [helm args...]}"; shift || true
dir="$here/fixtures/$fixture"
lib="$here/../platform-library"
rm -rf "$dir/charts" "$dir/Chart.lock"
# Enforce the root values contract exactly like a generated consumer chart:
# Helm validates values.schema.json against the coalesced (post-import) values.
cp "$lib/values.schema.reference.json" "$dir/values.schema.json"
if [[ "${RENDER_DEP_CACHE:-1}" == "0" ]]; then
  helm dependency update "$dir" >/dev/null
else
  cache_root="$here/.dep-cache"
  key=$( (cd "$lib/.." && find platform-library -type f -print0 \
      | LC_ALL=C sort -z | xargs -0 shasum -a 256) | shasum -a 256 | awk '{print $1}')
  entry="$cache_root/$key"
  if ! ls "$entry"/platform-*.tgz >/dev/null 2>&1; then
    mkdir -p "$entry"
    tmp=$(mktemp -d "$cache_root/.tmp.XXXXXX")
    helm package "$lib" -d "$tmp" >/dev/null
    tgz=$(basename "$tmp"/platform-*.tgz)
    # Two-step rename: readers only ever see an absent or complete file.
    # A lost race overwrites with identical bytes (key == content hash).
    mv "$tmp/$tgz" "$entry/.$tgz.$$.partial"
    mv "$entry/.$tgz.$$.partial" "$entry/$tgz"
    rm -rf "$tmp"
  fi
  mkdir -p "$dir/charts"
  cp "$entry"/platform-*.tgz "$dir/charts/"
fi
helm template t "$dir" "$@"
