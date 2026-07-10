#!/usr/bin/env bash
# =============================================================================
# vendor-schemas.sh — (re)download the JSON schemas kubeconform validates
# against and commit them into tests/schemas/. This is the ONLY script in this
# repo allowed to make network requests for schema data; scripts/lint-library.sh
# validates purely against the vendored copies this script produces, so CI
# never depends on cdn.jsdelivr.net (or any other CDN) being reachable.
#
# Usage:
#   scripts/vendor-schemas.sh          # refresh tests/schemas/ for the
#                                       # current KUBE_VERSIONS window
#
# After bumping KUBE_VERSIONS or the Kind lists in
# scripts/lib/schema-manifest.sh (e.g. widening the supported Kubernetes
# window, or a new fixture rendering a new Kind), re-run this script and
# commit the resulting tests/schemas/ changes.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_DIR="$REPO_ROOT/tests/schemas"
NATIVE_DIR="$SCHEMA_DIR/native"
CRD_DIR="$SCHEMA_DIR/crd"

# shellcheck source=scripts/lib/schema-manifest.sh
source "$REPO_ROOT/scripts/lib/schema-manifest.sh"

NATIVE_SOURCE_BASE='https://cdn.jsdelivr.net/gh/yannh/kubernetes-json-schema@master'
CRD_SOURCE_BASE='https://cdn.jsdelivr.net/gh/datreeio/CRDs-catalog@main'

fetch_json() {
  local url="$1" dest="$2"
  local tmp
  tmp="$(mktemp)"
  if ! curl -fsSL --max-time 30 "$url" -o "$tmp"; then
    echo "FAIL: could not download $url" >&2
    rm -f "$tmp"
    return 1
  fi
  if ! jq empty "$tmp" >/dev/null 2>&1; then
    echo "FAIL: $url did not return valid JSON" >&2
    rm -f "$tmp"
    return 1
  fi
  mkdir -p "$(dirname "$dest")"
  mv "$tmp" "$dest"
  echo "  vendored $dest"
}

fail=0

echo "==> native Kubernetes schemas (${KUBE_VERSIONS[*]})"
for kv in "${KUBE_VERSIONS[@]}"; do
  variant="v${kv}.0-standalone-strict"
  for kind in "${NATIVE_SCHEMA_KINDS[@]}"; do
    url="$NATIVE_SOURCE_BASE/$variant/$kind.json"
    dest="$NATIVE_DIR/$variant/$kind.json"
    fetch_json "$url" "$dest" || fail=1
  done
done

echo "==> CRD schemas"
for path in "${CRD_SCHEMA_PATHS[@]}"; do
  url="$CRD_SOURCE_BASE/$path.json"
  dest="$CRD_DIR/$path.json"
  fetch_json "$url" "$dest" || fail=1
done

if [[ "$fail" -ne 0 ]]; then
  echo "==> FAIL: one or more schemas failed to vendor" >&2
  exit 1
fi

retrieved_date="$(date -u +%Y-%m-%d)"
readme="$SCHEMA_DIR/README.md"
cat > "$readme" <<EOF
# Vendored kubeconform schemas

Everything under this directory is fetched from upstream by
\`scripts/vendor-schemas.sh\` — the only script in this repo allowed to make
network requests for schema data. \`scripts/lint-library.sh\` validates
against these local copies only; it makes zero network requests.

Last refreshed: **$retrieved_date** for Kubernetes ${KUBE_VERSIONS[*]}
(see \`scripts/lib/schema-manifest.sh\` for the authoritative version/Kind
list this snapshot covers).

## Layout

- \`native/v<X.Y.Z>-standalone-strict/<kind>.json\` — core Kubernetes object
  schemas, mirroring the layout of
  [yannh/kubernetes-json-schema](https://github.com/yannh/kubernetes-json-schema)
  (\`standalone-strict\` variant, self-contained with no external \`\$ref\`s).
  One directory per supported Kubernetes version.
- \`crd/<group>/<kind>_<apiVersion>.json\` — CRD schemas mirroring the layout
  of [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog).
  Not versioned per Kubernetes release, since CRDs are cluster-installed
  independently of core Kubernetes.

Both layouts intentionally match kubeconform's default \`-schema-location\`
templating so \`scripts/lint-library.sh\` only had to swap the remote base URL
for a local \`file://\` path — see that script's \`NATIVE_SCHEMA_LOCATION\` /
\`CRD_SCHEMA_LOCATION\` variables.

## Refreshing

\`\`\`bash
scripts/vendor-schemas.sh
\`\`\`

Re-run after editing \`scripts/lib/schema-manifest.sh\` (e.g. bumping
\`KUBE_VERSIONS\` for a new supported Kubernetes window, or adding a schema
stem/path for a new Kind a fixture renders), then commit the resulting diff
under \`tests/schemas/\`.

## Provenance

| Source | Upstream | Variant |
| --- | --- | --- |
| Core Kubernetes schemas | \`https://cdn.jsdelivr.net/gh/yannh/kubernetes-json-schema@master\` | \`{version}-standalone-strict\` |
| CRD schemas | \`https://cdn.jsdelivr.net/gh/datreeio/CRDs-catalog@main\` | n/a |

Only the schema stems/paths listed in \`scripts/lib/schema-manifest.sh\` are
vendored — the subset actually exercised by \`tests/fixtures/*\` across the
render matrix, not the full upstream catalogs (which run into the hundreds of
MB per Kubernetes version).
EOF
echo "  wrote $readme"

echo "==> done"
