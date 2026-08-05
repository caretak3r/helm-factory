#!/usr/bin/env bash
# =============================================================================
# scenario-consumer.sh — the day-one consumer journey, end to end.
#
# Scaffold a chart with new-app-chart.sh, resolve its dependency, render it,
# and schema-check every object. No cluster.
#
# The curated fixtures under tests/fixtures/ are hand-written and committed, so
# they cannot catch a regression in the SCAFFOLD itself: a broken dependency
# stanza, a dropped `import-values: [defaults]`, a renamed entrypoint, a
# values.schema.json that drifted from the library's reference. Every one of
# those keeps the gate green and breaks the first command a new consumer runs.
# This closes that gap by generating the consumer instead of curating it.
#
# Usage:
#   scripts/scenario-consumer.sh      # or: make smoke
#
# Env:
#   KEEP_SCENARIO_DIR=1   leave the scaffold on disk and print its path
#   SCENARIO_LIBRARY_REPOSITORY=file://...  override the source library path
#                                             (used by the packaged-artifact leg)
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_DIR="$REPO_ROOT/tests/schemas"
LIBRARY_REPOSITORY="${SCENARIO_LIBRARY_REPOSITORY:-file://$REPO_ROOT/platform-library}"

# shellcheck source=scripts/lib/schema-manifest.sh
source "$REPO_ROOT/scripts/lib/schema-manifest.sh"   # sets KUBE_VERSIONS
# Render at the OLDEST supported version: a scaffold that renders there renders
# everywhere in the window, and this way the version follows the manifest
# instead of rotting in a literal here.
KUBE_VERSION="${KUBE_VERSIONS[0]}"

NATIVE_SCHEMA_LOCATION="$SCHEMA_DIR/native/{{ .NormalizedKubernetesVersion }}-standalone{{ .StrictSuffix }}/{{ .ResourceKind }}{{ .KindSuffix }}.json"
CRD_SCHEMA_LOCATION="$SCHEMA_DIR/crd/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

for tool in helm kubeconform; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "FATAL: $tool is required by the consumer scenario — run 'make tools' for install hints" >&2
    exit 2
  }
done

work=$(mktemp -d)
cleanup() {
  if [[ "${KEEP_SCENARIO_DIR:-0}" == "1" ]]; then
    echo "  scaffold kept at $work/scenario"
  else
    rm -rf "$work"
  fi
}
trap cleanup EXIT

chart="$work/scenario"
fail=0

# The scaffolder's name guard is checked here rather than in lint-library.sh
# because this script is the one that owns new-app-chart.sh's contract. Both
# bounds matter: over 63 is illegal outright, and over 45 is legal but leaves
# no room for the suffixes the generators append after fullname truncation.
echo "==> assert: scaffolder rejects names that cannot render"
long64=$(printf 'a%.0s' $(seq 1 64))
if out=$("$REPO_ROOT/scripts/new-app-chart.sh" "$long64" --dir "$work/toolong" 2>&1); then
  echo "  FAIL: a 64-character chart name was accepted"; fail=1
elif ! grep -q "RFC 1123 label limit" <<<"$out"; then
  echo "  FAIL: 64-character name rejected without naming the limit: $out"; fail=1
elif [[ -e "$work/toolong" ]]; then
  echo "  FAIL: rejected name still created $work/toolong"; fail=1
else
  echo "  OK: 64-character name rejected"
fi

long50=$(printf 'a%.0s' $(seq 1 50))
if out=$("$REPO_ROOT/scripts/new-app-chart.sh" "$long50" --dir "$work/headroom" 2>&1) \
     && grep -q '^warning: chart name is 50 characters' <<<"$out"; then
  echo "  OK: 50-character name scaffolds with a headroom warning"
else
  echo "  FAIL: a 50-character name should scaffold AND warn about suffix headroom"; fail=1
fi
rm -rf "$work/headroom"

echo "==> scaffold: scripts/new-app-chart.sh scenario"
"$REPO_ROOT/scripts/new-app-chart.sh" scenario \
  --dir "$chart" \
  --repo "$LIBRARY_REPOSITORY" >/dev/null

# A representative overlay, not a kitchen sink: workload + service come from the
# scaffold, and ingress + serviceMonitor add one core Kind and one CRD-backed
# Kind. The CRD one is the point — it is the only way this scenario proves the
# capability gate still opens for a generated chart, and it forces the
# --api-versions form below to be exercised for real.
cat >> "$chart/values.yaml" <<'EOF'

ingress:
  enabled: true
  hostname: scenario.example.com

serviceMonitor:
  enabled: true
EOF

echo "==> dependency: helm dependency build"
if ! dep=$(helm dependency build --skip-refresh "$chart" 2>&1); then
  printf '%s\n' "$dep"
  echo "  FAIL: the scaffolded chart cannot resolve platform-library"
  exit 1
fi

# Full group/version/Kind form. A bare `monitoring.coreos.com/v1` does NOT
# satisfy the gate — the ServiceMonitor is silently skipped and this scenario
# would still exit 0, which is exactly the class of bug it exists to catch.
echo "==> render: helm template --kube-version $KUBE_VERSION"
if ! rendered=$(helm template scenario "$chart" \
      --kube-version "$KUBE_VERSION" \
      --api-versions monitoring.coreos.com/v1/ServiceMonitor 2>&1); then
  printf '%s\n' "$rendered"
  echo "  FAIL: the scaffolded chart does not render"
  exit 1
fi

echo "==> assert: expected Kinds present"
for kind in ServiceAccount Deployment Service Ingress ServiceMonitor; do
  if grep -qx "kind: $kind" <<<"$rendered"; then
    echo "  OK: $kind"
  else
    echo "  FAIL: scaffolded chart rendered no $kind"; fail=1
  fi
done

# An empty document is not a render failure to helm, but it IS a bug here: it
# means a generator emitted its separator and then bailed, and `kubectl apply`
# accepts the file without creating the object anyone was expecting.
echo "==> assert: no empty documents"
if empties=$(awk '
      function flush() { if (started && content == 0) print doc; buf = "" }
      /^---[[:space:]]*$/ { flush(); started = 1; content = 0; doc = NR; next }
      started && !/^[[:space:]]*(#.*)?$/ { content = 1 }
      END { flush() }
    ' <<<"$rendered") && [[ -z "$empties" ]]; then
  echo "  OK: every document has content"
else
  echo "  FAIL: empty rendered document(s) after separator at line(s): $(tr '\n' ' ' <<<"$empties")"
  fail=1
fi

echo "==> kubeconform -strict (vendored schemas, k8s $KUBE_VERSION)"
if kc_out=$(kubeconform -strict -summary \
      -kubernetes-version "$KUBE_VERSION.0" \
      -schema-location "$NATIVE_SCHEMA_LOCATION" \
      -schema-location "$CRD_SCHEMA_LOCATION" <<<"$rendered" 2>&1); then
  printf '  %s\n' "$kc_out"
else
  printf '%s\n' "$kc_out"
  echo "  FAIL: kubeconform rejected the scaffolded chart's output"; fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "==> CONSUMER SCENARIO FAILED"
  exit 1
fi
echo "==> consumer scenario PASS"
