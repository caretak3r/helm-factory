# Raw: lint-library.sh — header, matrix, expected_kinds, normalize

Provenance: verbatim copy of `scripts/lint-library.sh` lines 1-56, taken 2026-07-10 at HEAD 4fb9386 (branch handover/2026-07-10). Not edited.

```bash
#!/usr/bin/env bash
# =============================================================================
# lint-library.sh — validation gate for the pure platform-library chart.
#
# A library chart is not installable, so we validate it through the test
# consumer fixtures: helm lint the library, render each fixture across the
# supported Kubernetes version range with expected-object-count assertions,
# diff each fixture's canonical render against its committed golden snapshot,
# validate every rendered object with kubeconform (native + CRD schemas,
# across the version matrix), run a negative render proving CRD objects drop
# when their API is absent, enforce image pinning, and validate the values
# contract: the reference JSON Schema against its metaschema, every fixture's
# values against it (check-jsonschema), and helm-side rejection of
# schema-violating values (the schema is copied into each fixture as
# values.schema.json at render time), and exercise posture guardrails for mTLS,
# cluster-scoped extras, and pre-existing Secrets.
#
# Usage:
#   scripts/lint-library.sh                        # run all checks
#   UPDATE_GOLDEN=1 scripts/lint-library.sh        # regenerate tests/golden/*.yaml
#   REQUIRE_KUBECONFORM=1 scripts/lint-library.sh  # fail if kubeconform missing (CI)
#   REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh  # fail if check-jsonschema missing (CI)
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/platform-library"
RENDER="$REPO_ROOT/tests/render.sh"
GOLDEN_DIR="$REPO_ROOT/tests/golden"
FIXTURES=(minimal full stateful daemon)
KUBE_VERSIONS=(1.31 1.32 1.33 1.34 1.35 1.36)
GOLDEN_KUBE_VERSION=1.31   # canonical version for golden snapshots
KUBECONFORM_CACHE="${TMPDIR:-/tmp}/kubeconform-schema-cache"
# CRD schemas: the datreeio CRDs-catalog covers cert-manager, Gateway API,
# Prometheus Operator, and Istio — every CRD-backed Kind the library emits.
CRD_SCHEMA_LOCATION='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
fail=0

# Expected number of rendered objects (top-level `kind:` lines) per fixture.
# Update these alongside any fixture values change.
expected_kinds() {
  case "$1" in
    minimal)  echo 3 ;;
    full)     echo 24 ;;
    stateful) echo 6 ;;
    daemon)   echo 3 ;;
    *)        echo "unknown fixture: $1" >&2; return 1 ;;
  esac
}

# Strip content that is nondeterministic under `helm template`: tlsSelfSigned
# generates a fresh throwaway cert on every offline render (its Secret lookup
# is empty without a cluster), so the tls Secret data lines are redacted.
normalize_render() {
  sed -E 's/^(  (tls\.crt|tls\.key|ca\.crt): ).*/\1REDACTED/'
}
```
