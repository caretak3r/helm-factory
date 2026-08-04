#!/usr/bin/env bash
# Verify the local toolchain matches what the CI gate needs.
# Usage:
#   scripts/check-tools.sh          # quiet: prints nothing when everything is fine
#   scripts/check-tools.sh --list   # full table: found version, floor, CI pin
#
# Quiet-on-success is deliberate: `make lint` depends on this target, and a
# preamble printed before every gate run is noise people learn to scroll past.
# When something IS wrong it reports EVERY problem at once with an install
# line for each — a checker that stops at the first missing tool turns one
# fix-and-rerun cycle into five.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/tool-versions.sh
source "$REPO_ROOT/scripts/lib/tool-versions.sh"

list=0
case "${1:-}" in
  --list|-l) list=1 ;;
  "") ;;
  *) echo "usage: ${0##*/} [--list]" >&2; exit 2 ;;
esac

# Version strings in the wild carry prefixes, git suffixes, and product names:
# "v4.2.3+g43e8b7f", "check-jsonschema, version 0.37.2", "jq-1.8.2". Reduce to
# the first bare dotted-numeric run and compare that.
tool_version() {
  local raw
  case "$1" in
    helm)             raw=$(helm version --short 2>/dev/null) ;;
    kubeconform)      raw=$(kubeconform -v 2>/dev/null) ;;
    check-jsonschema) raw=$(check-jsonschema --version 2>/dev/null) ;;
    shellcheck)       raw=$(shellcheck --version 2>/dev/null | awk '$1 == "version:" { print $2 }') ;;
    jq)               raw=$(jq --version 2>/dev/null) ;;
    *)                return 1 ;;
  esac
  grep -oE '[0-9]+(\.[0-9]+)+' <<<"$raw" | head -1
}

# Numeric per-component compare; `sort -V` is not portable enough to trust and
# a string compare gets 0.10.0 < 0.9.0 wrong.
version_ge() {
  awk -v have="$1" -v want="$2" '
    BEGIN {
      nh = split(have, h, "."); nw = split(want, w, ".")
      n = (nh > nw ? nh : nw)
      for (i = 1; i <= n; i++) {
        hi = (i <= nh ? h[i] + 0 : 0); wi = (i <= nw ? w[i] + 0 : 0)
        if (hi > wi) exit 0
        if (hi < wi) exit 1
      }
      exit 0
    }'
}

problems=()
drift=()

for record in "${REQUIRED_TOOLS[@]}"; do
  IFS='|' read -r name floor pin hint <<<"$record"

  if ! command -v "$name" >/dev/null 2>&1; then
    problems+=("$name is not installed (need >= $floor) — $hint")
    [[ $list -eq 1 ]] && printf '  ✗ %-18s %-12s floor %-8s %s\n' "$name" "not installed" "$floor" "${pin:+CI pins $pin}"
    continue
  fi

  found=$(tool_version "$name" || true)
  if [[ -z "$found" ]]; then
    # Present but unparseable. Not fatal: an unrecognised version string is a
    # reason to stop guessing, not a reason to block a working toolchain.
    [[ $list -eq 1 ]] && printf '  ◐ %-18s %-12s floor %-8s %s\n' "$name" "unknown" "$floor" "version string not recognised"
    continue
  fi

  if ! version_ge "$found" "$floor"; then
    problems+=("$name $found is older than the $floor floor — $hint")
    [[ $list -eq 1 ]] && printf '  ✗ %-18s %-12s floor %-8s %s\n' "$name" "$found" "$floor" "TOO OLD"
    continue
  fi

  if [[ -n "$pin" && "$found" != "$pin" ]]; then
    drift+=("$name $found (CI pins $pin)")
    [[ $list -eq 1 ]] && printf '  ◐ %-18s %-12s floor %-8s CI pins %s\n' "$name" "$found" "$floor" "$pin"
    continue
  fi

  [[ $list -eq 1 ]] && printf '  ✓ %-18s %-12s floor %-8s %s\n' "$name" "$found" "$floor" "${pin:+CI pins $pin}"
done

if [[ ${#problems[@]} -gt 0 ]]; then
  echo "FAIL: the CI gate cannot run with this toolchain." >&2
  for p in "${problems[@]}"; do echo "  - $p" >&2; done
  echo >&2
  echo "Versions are pinned in scripts/lib/tool-versions.sh; run 'make tools' for the full table." >&2
  exit 1
fi

if [[ $list -eq 1 ]]; then
  if [[ ${#drift[@]} -gt 0 ]]; then
    echo
    echo "◐ Local versions differ from the CI pins. Usually harmless — a gate that"
    echo "  passes here and fails in CI is the one case where it is not:"
    for d in "${drift[@]}"; do echo "    $d"; done
  fi
  echo
  echo "Pins live in scripts/lib/tool-versions.sh (sourced by CI, so they cannot drift)."
fi
