#!/usr/bin/env bash
# =============================================================================
# scenario-packaged-consumer.sh — consume the chart Helm actually packages.
#
# Helm file:// dependencies accept an unpacked chart directory, not a .tgz
# archive. This scenario therefore packages platform-library first, extracts
# that immutable artifact into a fresh directory, and points the existing
# consumer scenario at the extracted package contents. No dependency or render
# step reads templates or defaults from the source chart directory.
#
# Usage:
#   scripts/scenario-packaged-consumer.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for tool in helm kubeconform tar; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "FATAL: $tool is required by the packaged-artifact consumer scenario — run 'make tools' for install hints" >&2
    exit 2
  }
done

work=$(mktemp -d)
cleanup() {
  rm -rf "$work"
}
trap cleanup EXIT

package_dir="$work/package"
extracted_dir="$work/extracted"
mkdir -p "$package_dir" "$extracted_dir"

echo "==> package artifact: helm package platform-library"
if package_out=$(helm package "$REPO_ROOT/platform-library" \
      --destination "$package_dir" 2>&1); then
  printf '  %s\n' "$package_out"
else
  printf '%s\n' "$package_out"
  echo "  FAIL: packaging step 'helm package platform-library'"
  exit 1
fi

archives=("$package_dir"/platform-*.tgz)
if [[ "${#archives[@]}" -ne 1 || ! -f "${archives[0]}" ]]; then
  echo "  FAIL: packaging step produced no unique platform-*.tgz artifact"
  exit 1
fi
archive="${archives[0]}"

echo "==> extract packaged artifact: $(basename "$archive")"
if extract_out=$(tar -xzf "$archive" -C "$extracted_dir" 2>&1); then
  :
else
  printf '%s\n' "$extract_out"
  echo "  FAIL: cannot extract artifact produced by the packaging step"
  exit 1
fi

packaged_chart="$extracted_dir/platform"
for required_file in Chart.yaml values.yaml values.schema.reference.json templates/_app.yaml; do
  if [[ -f "$packaged_chart/$required_file" ]]; then
    echo "  OK: packaged $required_file"
  else
    echo "  FAIL: packaging step omitted $required_file"
    exit 1
  fi
done

echo "==> consume packaged artifact through file:// extracted contents"
if scenario_out=$(SCENARIO_LIBRARY_REPOSITORY="file://$packaged_chart" \
      "$REPO_ROOT/scripts/scenario-consumer.sh" 2>&1); then
  printf '%s\n' "$scenario_out"
else
  printf '%s\n' "$scenario_out"
  echo "  FAIL: packaged-artifact consumer check after packaging step 'helm package platform-library'"
  exit 1
fi

echo "==> packaged-artifact consumer scenario PASS"
