#!/usr/bin/env bash
# =============================================================================
# sync-consumer-schema.sh — refresh a consumer chart's values.schema.json from
# platform-library's reference schema.
#
# scripts/new-app-chart.sh copies platform-library/values.schema.reference.json
# into <chart>/values.schema.json ONCE, at scaffold time. When the consumer
# later bumps its `platform` dependency to a library version with new or
# changed values keys, that copy silently goes stale and the chart validates
# against an outdated contract. Run this script after every dependency bump.
#
# It never edits Chart.yaml: it reads the declared `platform` dependency
# version for reporting only, and copies the schema this checkout ships.
#
# Usage:
#   scripts/sync-consumer-schema.sh <consumer-chart-dir> [options]
#
# Options:
#   --dry-run    Report what would change; write nothing
#   --check      Like --dry-run, but exit 1 if drifted/missing, 0 if in sync
#                (write-free, for gate/CI use)
#   -h, --help   Show this help
#
# Example:
#   scripts/sync-consumer-schema.sh ../billing
#   scripts/sync-consumer-schema.sh tests/fixtures/full --dry-run
#   scripts/sync-consumer-schema.sh tests/fixtures/full --check
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$REPO_ROOT/platform-library"
REFERENCE_SCHEMA="$LIB_DIR/values.schema.reference.json"
DIFF_PREVIEW_LINES=40

chart_dir=""
dry_run=0
check=0

die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --check)   check=1; dry_run=1; shift ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    -*)        die "unknown option: $1" ;;
    *)         if [[ -z "$chart_dir" ]]; then chart_dir="$1"; else die "unexpected argument: $1"; fi; shift ;;
  esac
done

[[ -n "$chart_dir" ]] || die "consumer chart directory is required (usage: sync-consumer-schema.sh <consumer-chart-dir>)"
[[ -d "$chart_dir" ]] || die "not a directory: $chart_dir"
[[ -f "$chart_dir/Chart.yaml" ]] || die "no Chart.yaml in $chart_dir - not a chart directory"
[[ -f "$REFERENCE_SCHEMA" ]] || die "missing $REFERENCE_SCHEMA - nothing to sync from"
command -v helm >/dev/null 2>&1 || die "helm is required to read $chart_dir/Chart.yaml"

# --- declared dependency version ---------------------------------------------
# `helm show chart` re-emits Chart.yaml canonically (keys sorted, one two-space
# indent level per list item), so this stays a fixed-shape parse rather than a
# general YAML reader. Keys land alphabetically, so `name` precedes `version`.
chart_meta="$(helm show chart "$chart_dir")" || die "helm could not read $chart_dir/Chart.yaml"
dep_version="$(printf '%s\n' "$chart_meta" | awk '
  /^dependencies:/    { in_deps = 1; next }
  in_deps && /^[^ -]/ { in_deps = 0 }
  !in_deps            { next }
  {
    line = $0
    if (line ~ /^- /) { name = ""; line = "  " substr(line, 3) }
    if (line ~ /^  name:[ \t]/)    { name = line;    sub(/^  name:[ \t]+/, "", name) }
    if (line ~ /^  version:[ \t]/) { version = line; sub(/^  version:[ \t]+/, "", version)
                                     if (name == "platform") { print version; exit } }
  }
')"
[[ -n "$dep_version" ]] || \
  die "$chart_dir/Chart.yaml declares no 'platform' dependency - is this a platform-library consumer?"
dep_version="${dep_version#[\"\']}"
dep_version="${dep_version%[\"\']}"

lib_version="$(helm show chart "$LIB_DIR" | awk '/^version:/ { print $2; exit }')"

dest="$chart_dir/values.schema.json"
echo "==> $chart_dir"
echo "  declared platform dependency: ${dep_version}"
echo "  library in this checkout:     ${lib_version}  ($REFERENCE_SCHEMA)"

# --- what would change --------------------------------------------------------
drifted=0
if [[ ! -f "$dest" ]]; then
  echo "  values.schema.json: MISSING - will be created"
  drifted=1
elif cmp -s "$REFERENCE_SCHEMA" "$dest"; then
  echo "  values.schema.json: already in sync - nothing to do"
  exit 0
else
  # Guarded assignment: `diff` exits 1 on difference, which a bare
  # `var=$(...)` would turn into a silent `set -e` abort. The `then` branch
  # (files identical) is already ruled out by the `cmp` above.
  if diff_out="$(diff -u "$dest" "$REFERENCE_SCHEMA")"; then
    diff_out=""
  fi
  added="$(printf '%s\n' "$diff_out" | grep -c '^+[^+]' || true)"
  removed="$(printf '%s\n' "$diff_out" | grep -c '^-[^-]' || true)"
  echo "  values.schema.json: DRIFTED (+${added} / -${removed} lines)"
  drifted=1

  if command -v jq >/dev/null 2>&1; then
    key_delta="$(diff \
      <(jq -r '.properties // {} | keys[]' "$dest" 2>/dev/null || true) \
      <(jq -r '.properties // {} | keys[]' "$REFERENCE_SCHEMA") \
      | sed -n 's/^> /    + /p; s/^< /    - /p' || true)"
    if [[ -n "$key_delta" ]]; then
      echo "  top-level values keys:"
      printf '%s\n' "$key_delta"
    fi
  fi

  echo "  diff (first ${DIFF_PREVIEW_LINES} lines; full: diff -u $dest $REFERENCE_SCHEMA):"
  printf '%s\n' "$diff_out" | sed -n "1,${DIFF_PREVIEW_LINES}p" | sed 's/^/    /'
  if [[ "$(printf '%s\n' "$diff_out" | wc -l)" -gt "$DIFF_PREVIEW_LINES" ]]; then
    echo "    ... (truncated)"
  fi
fi

if [[ "$check" -eq 1 && "$drifted" -eq 1 ]]; then
  echo "  --check: out of sync - run '$0 $chart_dir' (without --check) to resync"
  exit 1
fi

if [[ "$dry_run" -eq 1 ]]; then
  echo "  --dry-run: no files written"
  exit 0
fi

cp "$REFERENCE_SCHEMA" "$dest"
echo "  wrote $dest"
echo
echo "Next:"
echo "  helm template <release> $chart_dir   # schema is enforced on render"
