#!/usr/bin/env bash
# =============================================================================
# preflight-release.sh — validate tag readiness BEFORE pushing a release tag.
#
# release.yaml's gate job re-runs these same checks (tag <-> Chart.yaml
# version, CHANGELOG heading) AFTER the tag already exists — a bad tag needs
# manual deletion before retry. Run this script on the release-prep branch
# first so a bad tag never gets pushed in the first place.
#
# Usage:
#   scripts/preflight-release.sh
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_FILE="$REPO_ROOT/platform-library/Chart.yaml"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"

die() { echo "error: $*" >&2; exit 1; }

[[ -f "$CHART_FILE" ]] || die "missing $CHART_FILE"
[[ -f "$CHANGELOG_FILE" ]] || die "missing $CHANGELOG_FILE"

version="$(awk '$1 == "version:" {print $2}' "$CHART_FILE")"
[[ -n "$version" ]] || die "could not parse version: from $CHART_FILE"

if ! grep -qE "^## \[${version//./\\.}\]" "$CHANGELOG_FILE"; then
  die "CHANGELOG.md has no '## [${version}]' heading — add a dated entry before tagging"
fi

existing_tag="$(git -C "$REPO_ROOT" tag -l "v${version}")"
[[ -z "$existing_tag" ]] || die "tag v${version} already exists — bump platform-library/Chart.yaml version before tagging again"

echo "preflight OK: ready to tag v${version}"
