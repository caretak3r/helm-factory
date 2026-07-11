---
name: k8s-version-bump
description: Use when extending or shifting the supported Kubernetes version range, or handling an apiVersion deprecation/removal in a new K8s release. Do not use for adding new Kinds (see add-library-kind) or one-off apiVersion questions (see capability-gates).
---

# Kubernetes Version Bump

## First rule
The supported range is declared in multiple places that MUST move together; grep for the old bounds before declaring done. A bump that only edits `KUBE_VERSIONS` tests a range the chart still refuses to install on (kubeVersion constraint) and documents wrongly.

## Steps
1. The verified touch list (all anchors confirmed at HEAD 4fb9386):
   - `scripts/lint-library.sh:31` — `KUBE_VERSIONS=(1.31 1.32 ...)`, the render + kubeconform matrix.
   - `scripts/lint-library.sh:32` — `GOLDEN_KUBE_VERSION` (canonical golden version, currently 1.31). Changing it regenerates every golden; usually only moves when the FLOOR moves.
   - `platform-library/Chart.yaml:10` — `kubeVersion: ">=1.31.0-0 <1.37.0-0"` (upper bound is exclusive: supporting 1.37 means `<1.38.0-0`). Also the description line above it names the range.
   - `scripts/new-app-chart.sh:81` — the scaffold heredoc stamps the same `kubeVersion` into new consumers. Fixture Chart.yamls do NOT carry kubeVersion — nothing to touch there.
   - Docs claiming the range: `README.md:12`, `docs/specs/platform-library-v2-architecture.md:21,341,363`, `CORE.md:157` (golden version comment), CHANGELOG entry.
2. For each newly supported version, check K8s deprecations/removals against the registry (`_capabilities.tpl:68-158`): if an apiVersion is removed in the new version, ensure a newer preference is listed FIRST (it is also the OrDefault offline fallback) and keep the old one later in the chain for older clusters. Reordering preferences changes goldens — intentional, review the diff.
3. Run the matrix. kubeconform downloads new `-kubernetes-version X.Y.0` schemas on first run (network); a missing upstream schema for a brand-new K8s version is an upstream lag issue — report it, don't hack around it. Note the known gap: kubeconform validates the single canonical golden-version render against each matrix version, not per-version renders (beads helm-factory-uaw) — an apiVersion that only appears at newer `--kube-version` values is under-validated; check those renders by eye.
4. If the floor moved: consider whether `GOLDEN_KUBE_VERSION` and the `isStable` assumptions ("always present on a real cluster >=1.31", `_capabilities.tpl:199`) need their comments updated.
5. Version/CHANGELOG: widening the supported range is at least a minor bump; RAISING the floor drops supported clusters — treat as breaking, major bump.
6. Full gate; review any golden diffs (negotiated apiVersions may have shifted).

## Commands
```bash
grep -rn "1\.36\|1\.37" scripts/ platform-library/Chart.yaml README.md CORE.md docs/specs/   # find every range claim (adjust to old bounds)
tests/render.sh full --kube-version 1.37                       # spot-check the new version renders (expect 24 kinds)
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh   # full matrix; passes at HEAD 4fb9386 for 1.31-1.36
```
`UPDATE_GOLDEN=1 scripts/lint-library.sh` if negotiated versions changed (not run in staging; mechanism at `lint-library.sh:136-139`) — then review `git diff tests/golden/` hunk by hunk.

## Quality bar
(1) Gate `==> PASS` across the NEW matrix, every version green; (2) no capability gate loosened to survive a version — a Kind that loses its API in the new version must skip (strict) or fall forward (preference reorder), never hardcode; (3) `kubeVersion` constraint, matrix, scaffold, and doc claims all state the same range — consumers read the docs as contract.

## Verification checklist
- [ ] Grep for the OLD bounds returns only CHANGELOG/history hits
- [ ] `KUBE_VERSIONS`, `kubeVersion` (library + scaffold), README/CORE/spec claims all match
- [ ] Registry preference order reviewed against the new version's deprecations; golden diff explained
- [ ] `tests/render.sh full --kube-version <new>` renders the expected 24 objects
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
- Assuming green kubeconform means per-version render validation — it validates the canonical render against each version's schemas (known gap).
- Accepting a golden diff full of apiVersion shifts without checking each one is the intended negotiation outcome.
- Bumping docs to a range CI does not actually exercise.

## Done means
- Grep-for-old-bounds output (clean), full-gate `==> PASS` on the new matrix pasted, golden diff summary with each apiVersion shift justified, and the semver classification stated.
