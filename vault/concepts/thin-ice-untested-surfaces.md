# Concept: thin-ice surfaces (exist but unproven by the gate)

Features present in the library that the regression oracle ([[golden-count-oracle]]) does not exercise. All items below are **UNVERIFIED** — render-verify before building on any of them:

- ~~**`global.*` umbrella helpers**, **`serviceEndpoints`**, **`platform.util.merge`**~~ — REMOVED 2026-07-12 (bead `helm-factory-b01`). `serviceEndpoints` was not merely untested but structurally broken: it ranged over every map-valued key in `.Values` and called each one a subchart, so under v2's flattened `import-values` contract it emitted `podSecurityContext-endpoint: podSecurityContext.default.svc.cluster.local:80`. The rest had zero call sites. Goldens unchanged after removal.
- **kubeconform matrix gap — CLOSED 2026-07-11**: the gate now validates each matrix version's own render inside the render loop (beads helm-factory-uaw, fixed). Historical: it previously validated only the canonical render against each version's schemas.
- **Real-cluster behavior** (live `.Capabilities`, tlsSelfSigned `lookup` reuse, `helm upgrade --dry-run=server`): largely source-and-spec claims ([[template-vs-cluster-capabilities]]) — though a live `kind`-cluster install on 2026-07-14 verified hook-Job ordering end-to-end (bead hf-5oi closed with evidence). Everything else on-cluster remains unexecuted.
- **Release publish path** to GHCR — **VERIFIED 2026-07-15**: tag `v2.0.0` ran the release workflow green (run 29384461101) and published to `oci://ghcr.io/caretak3r/charts` ([[ci-release-workflows]]).

Other tracked-but-accepted quirks live in CORE.md's Known Issues table (raw/core-known-issues.md). The Service-selector `commonLabels` leak was FIXED (bead hf-7a1, P0, closed 2026-07-13): `_service.yaml:57-58` and `_service-headless.yaml:27-28` now use `platform.selectorLabels` only — and CORE.md's table was corrected 2026-07-20 to move it to the "Fixed" line (`raw/core-known-issues.md` remains an archival snapshot of the pre-fix table).

Sources: raw/discovery-could-not-verify.md; helper define locations re-verified by grep 2026-07-10 (HEAD 4fb9386) and 2026-07-19 (HEAD 8d09841).
