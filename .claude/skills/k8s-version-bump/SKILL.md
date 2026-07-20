---
name: k8s-version-bump
description: Use when extending or shifting the supported Kubernetes version range, or handling an apiVersion deprecation/removal in a new K8s release. Do not use for adding new Kinds (see add-library-kind) or one-off apiVersion questions (see capability-gates).
---

# Kubernetes Version Bump

## First rule
The support policy is **n-2**: the latest supported Kubernetes minor plus the two behind it — currently **1.34–1.36**. The range is declared in multiple places that MUST move together; grep for the old bounds before declaring done. A bump that only edits `KUBE_VERSIONS` tests a range the chart still refuses to install on (kubeVersion constraint) and documents wrongly. Because the window slides, a bump normally raises the floor too — and raising the floor is breaking (see step 5).

## Steps
1. The verified touch list (all anchors re-confirmed 2026-07-19 against the n-2 window):
   - `scripts/lib/schema-manifest.sh:18` — `KUBE_VERSIONS=(1.34 1.35 1.36)`, the render + kubeconform matrix (sourced by `lint-library.sh:59`; `FIXTURES`/`KUBE_VERSIONS` env subsets are accepted for local runs, `lint-library.sh:27-41`, but any entry outside the vendored schema window fails fast).
   - `tests/schemas/` — vendored kubeconform schemas. A range change must re-vendor via `scripts/vendor-schemas.sh` (driven by the same manifest); the gate is hermetic and never downloads.
   - `scripts/lint-library.sh:56` — `GOLDEN_KUBE_VERSION` (canonical golden version, currently 1.34). Changing it regenerates every golden; it moves whenever the FLOOR moves, which under n-2 is most bumps.
   - `platform-library/Chart.yaml:11` — `kubeVersion: ">=1.34.0-0 <1.37.0-0"` (upper bound is exclusive: supporting 1.37 means `<1.38.0-0`).
   - `scripts/new-app-chart.sh:81` — the scaffold heredoc stamps the same `kubeVersion` into new consumers. Fixture Chart.yamls do NOT carry kubeVersion — nothing to touch there.
   - Docs claiming the range: `README.md:12` (and the Helm version-skew section at `:24`), `docs/specs/platform-library-v2-architecture.md:17`, `CORE.md:161,176,286`, CHANGELOG entry.
2. For each newly supported version, check K8s deprecations/removals against the registry (`_capabilities.tpl:76-176`): if an apiVersion is removed in the new version, ensure a newer preference is listed FIRST (it is also the OrDefault offline fallback) and keep the old one later in the chain for older clusters. Reordering preferences changes goldens — intentional, review the diff.
3. Re-vendor, then run the matrix. Add the new version to the manifest and run `scripts/vendor-schemas.sh` (network needed once; the gate itself stays hermetic against `tests/schemas/`). A version with no vendored schemas fails fast at gate start; a brand-new K8s version whose schemas don't exist upstream yet is an upstream lag issue — report it, don't hack around it. Since helm-factory-uaw was fixed (2026-07-11), kubeconform validates each matrix version's own render inside the render loop, so version-specific apiVersion negotiation IS schema-validated per version.
4. If the floor moved (the normal case under n-2): update `GOLDEN_KUBE_VERSION` and the `isStable` comment ("always present on a real cluster >=1.34", `_capabilities.tpl:217`). Moving the golden version regenerates every golden — expect a large, reviewable diff.
5. Version/CHANGELOG: widening the range without dropping the floor is a minor bump; RAISING the floor drops supported clusters — **breaking, major bump** (the 1.31→1.34 n-2 tightening shipped as a `feat!`).
6. Full gate; review any golden diffs (negotiated apiVersions may have shifted).

## Commands
```bash
grep -rn "1\.34\|1\.36\|1\.37" scripts/ platform-library/Chart.yaml README.md CORE.md docs/specs/   # every range claim (adjust to the OLD bounds you are replacing)
tests/render.sh full --kube-version 1.37                       # spot-check a new version renders (expect 26 kinds)
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh   # full matrix; currently 1.34-1.36
```
`UPDATE_GOLDEN=1 scripts/lint-library.sh` if negotiated versions changed (not run in staging; mechanism at `lint-library.sh:229-236`) — then review `git diff tests/golden/` hunk by hunk.

## Quality bar
(1) Gate `==> PASS` across the NEW matrix, every version green; (2) no capability gate loosened to survive a version — a Kind that loses its API in the new version must skip (strict) or fall forward (preference reorder), never hardcode; (3) `kubeVersion` constraint, matrix, scaffold, and doc claims all state the same range — consumers read the docs as contract.

## Verification checklist
- [ ] Grep for the OLD bounds returns only CHANGELOG/history hits
- [ ] `KUBE_VERSIONS`, `kubeVersion` (library + scaffold), README/CORE/spec claims all match
- [ ] Registry preference order reviewed against the new version's deprecations; golden diff explained
- [ ] `tests/render.sh full --kube-version <new>` renders the expected 26 objects
- [ ] Gate `==> PASS` on the new matrix; kubeconform legs green for the new version
- [ ] Version bump + CHANGELOG entry classify the change (widen=minor, floor-raise=major)

## Stop and ask before
- raising the version floor (drops supported clusters — breaking)
- changing `GOLDEN_KUBE_VERSION` (regenerates every golden; large review surface)
- removing an old apiVersion from a registry preference chain (older-cluster consumers may depend on it)
- hardcoding an apiVersion anywhere to dodge a negotiation problem

## Common mistakes
- Editing only `KUBE_VERSIONS` — the chart's `kubeVersion` constraint still blocks install on the new version.
- Forgetting the scaffold heredoc — new consumers get stamped with the stale constraint.
- Assuming the kubeconform gap still exists — since 2026-07-11 (helm-factory-uaw) each version's own render is validated; don't add redundant by-eye checks for that.
- Accepting a golden diff full of apiVersion shifts without checking each one is the intended negotiation outcome.
- Bumping docs to a range CI does not actually exercise.

## Done means
- Grep-for-old-bounds output (clean), full-gate `==> PASS` on the new matrix pasted, golden diff summary with each apiVersion shift justified, and the semver classification stated.
