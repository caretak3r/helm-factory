# Concept: thin-ice surfaces (exist but unproven by the gate)

Features present in the library that the regression oracle ([[golden-count-oracle]]) does not exercise. All items below are **UNVERIFIED** — render-verify before building on any of them:

- ~~**`global.*` umbrella helpers**, **`serviceEndpoints`**, **`platform.util.merge`**~~ — REMOVED 2026-07-12 (bead `helm-factory-b01`). `serviceEndpoints` was not merely untested but structurally broken: it ranged over every map-valued key in `.Values` and called each one a subchart, so under v2's flattened `import-values` contract it emitted `podSecurityContext-endpoint: podSecurityContext.default.svc.cluster.local:80`. The rest had zero call sites. Goldens unchanged after removal.
- **kubeconform matrix gap — CLOSED 2026-07-11**: the gate now validates each matrix version's own render inside the render loop (beads helm-factory-uaw, fixed). Historical: it previously validated only the canonical render against each version's schemas.
- **Real-cluster behavior** (live `.Capabilities`, tlsSelfSigned `lookup` reuse, `helm upgrade --dry-run=server`): never executed in this environment; source-and-spec claims only ([[template-vs-cluster-capabilities]]).
- **Release publish path** to GHCR: read-only verified ([[ci-release-workflows]]).

Other tracked-but-accepted quirks live in CORE.md's Known Issues table (raw/core-known-issues.md) — notably the Service-selector `commonLabels` leak, which is a known issue to avoid copying, not a pattern.

Sources: raw/discovery-could-not-verify.md; helper define locations re-verified by grep 2026-07-10, HEAD 4fb9386.
