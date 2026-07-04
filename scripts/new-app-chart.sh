#!/usr/bin/env bash
# =============================================================================
# new-app-chart.sh — scaffold a new application chart wired to platform-library.
#
# platform-library is a pure library chart: it ships no installable templates.
# A product chart consumes it as a dependency (with import-values: [defaults])
# and renders everything through the single entrypoint `platform.render`.
#
# Usage:
#   scripts/new-app-chart.sh <name> [options]
#
# Options:
#   --dir <path>       Output directory (default: ./<name>)
#   --repo <url>       Library repository. Default: file://../platform-library
#                      For distribution use e.g. oci://registry.example.com/charts
#   --version <range>  Library version constraint (default: ">=2.0.0-0")
#   --app-version <v>  appVersion for the new chart (default: "0.1.0")
#   -h, --help         Show this help
#
# Example:
#   scripts/new-app-chart.sh billing --repo oci://ghcr.io/acme/charts --version "^2.0.0"
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$REPO_ROOT/platform-library"

name=""
out_dir=""
repo="file://../platform-library"
version=">=2.0.0-0"
app_version="0.1.0"

die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)         out_dir="${2:?}"; shift 2 ;;
    --repo)        repo="${2:?}"; shift 2 ;;
    --version)     version="${2:?}"; shift 2 ;;
    --app-version) app_version="${2:?}"; shift 2 ;;
    -h|--help)     sed -n '2,30p' "$0"; exit 0 ;;
    -*)            die "unknown option: $1" ;;
    *)             if [[ -z "$name" ]]; then name="$1"; else die "unexpected argument: $1"; fi; shift ;;
  esac
done

[[ -n "$name" ]] || die "chart name is required (usage: new-app-chart.sh <name>)"
[[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || \
  die "chart name must be lowercase alphanumeric with dashes (RFC 1123): '$name'"
: "${out_dir:=$name}"
[[ ! -e "$out_dir" ]] || die "output path already exists: $out_dir"

mkdir -p "$out_dir/templates"

cat > "$out_dir/Chart.yaml" <<EOF
apiVersion: v2
name: ${name}
description: ${name} — generated from platform-library
type: application
version: 0.1.0
appVersion: "${app_version}"
kubeVersion: ">=1.31.0-0 <1.37.0-0"
dependencies:
  - name: platform
    version: "${version}"
    repository: ${repo}
    # REQUIRED: without import-values the library defaults never reach the root
    # values scope, and every generator sees empty values.
    import-values:
      - defaults
EOF

cat > "$out_dir/templates/app.yaml" <<'EOF'
{{/*
Single entrypoint. platform.render composes the opinionated primary-app objects
plus the generic capability-gated long-tail (extraObjects) and the raw escape
hatch (extraManifests). Configure everything through values.yaml.
*/}}
{{ include "platform.render" . }}
EOF

cat > "$out_dir/values.yaml" <<EOF
# ${name} — overrides only. The library's exports.defaults are imported at the
# root of these values, so set fields at the top level (image:, service:, ...).

image:
  repository: example/${name}
  # A tag or digest is REQUIRED — rendering fails without one. Prefer an
  # immutable digest pin in production:
  # digest: "sha256:<64-hex>"
  tag: "${app_version}"

service:
  enabled: true
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP

# When rendering without a cluster (CI), force-assume the CRD groups you use so
# their objects are not skipped:
# capabilities:
#   apiVersions:
#     - cert-manager.io/v1
#     - monitoring.coreos.com/v1

# Long-tail Kubernetes objects (capability-negotiated, standard-labelled):
# extraObjects:
#   Role:
#     - name: ${name}-reader
#       rules:
#         - apiGroups: [""]
#           resources: ["configmaps"]
#           verbs: ["get", "list", "watch"]
EOF

cat > "$out_dir/.helmignore" <<'EOF'
.git
.gitignore
*.tmproj
.vscode/
.idea/
*.bak
EOF

if [[ -f "$LIB_DIR/values.schema.reference.json" ]]; then
  cp "$LIB_DIR/values.schema.reference.json" "$out_dir/values.schema.json"
fi

cat <<EOF

Created ${out_dir}/
  Chart.yaml            (depends on platform @ ${version} from ${repo})
  templates/app.yaml    ({{ include "platform.render" . }})
  values.yaml           (overrides only)
  values.schema.json    (root contract)
  .helmignore

Next:
  helm dependency update ${out_dir}
  helm template ${name} ${out_dir}
EOF
