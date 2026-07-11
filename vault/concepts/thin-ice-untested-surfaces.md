# Concept: thin-ice surfaces (exist but unproven by the gate)

Features present in the library that the regression oracle ([[golden-count-oracle]]) does not exercise. All items below are **UNVERIFIED** — render-verify before building on any of them:

- **`global.*` umbrella helpers** (`_helpers.tpl:483+`: `global.subchartEndpoint`, `global.enabledSubcharts`, `global.allEndpointsDynamic`, `global.allEndpoints`) and **`serviceEndpoints`** (`platform.serviceEndpoints.configmap`, `_helpers.tpl:567`; wired at `_app.yaml:90-92`): zero fixture coverage; output shape untested by the gate.
- **`platform.util.merge`** (`_util.tpl:31-36`): defined, documented, but has no call sites in the library — public API for advanced consumers per the spec. Dead-ish code; do not remove without a deprecation pass.
- **kubeconform matrix gap**: the gate validates the single canonical 1.31 render against each matrix version's schemas, not per-version renders (`scripts/lint-library.sh:129` captures once, `:158` reuses). Tracked as beads issue helm-factory-uaw. Do not claim full per-version validation.
- **Real-cluster behavior** (live `.Capabilities`, tlsSelfSigned `lookup` reuse, `helm upgrade --dry-run=server`): never executed in this environment; source-and-spec claims only ([[template-vs-cluster-capabilities]]).
- **Release publish path** to GHCR: read-only verified ([[ci-release-workflows]]).

Other tracked-but-accepted quirks live in CORE.md's Known Issues table (raw/core-known-issues.md) — notably the Service-selector `commonLabels` leak, which is a known issue to avoid copying, not a pattern.

Sources: raw/discovery-could-not-verify.md; helper define locations re-verified by grep 2026-07-10, HEAD 4fb9386.
