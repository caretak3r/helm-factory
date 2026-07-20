---
name: release-platform-library
description: Use when cutting, tagging, or publishing a platform-library release, or preparing version/CHANGELOG for one. Do not use for day-to-day validation (see validate-factory) — and never push tags or commits without explicit user instruction (Conservative profile default).
---

# Release the Platform Library

## First rule
The tag must equal the chart version. `.github/workflows/release.yaml:37-45` refuses `v<X.Y.Z>` tags that don't match `platform-library/Chart.yaml` `version:`, and `release.yaml:47-55` refuses a tag with no matching `## [X.Y.Z]` CHANGELOG heading — align Chart.yaml, CHANGELOG, and the tag BEFORE tagging, because a rejected tag still exists on the remote and needs cleanup.

## Steps
1. Decide the version by semver against the merge bar: any breaking values/template contract change (renamed key, changed default behavior, helper signature) = major; additive features = minor; fixes = patch. Current: `version: 2.0.0` in `platform-library/Chart.yaml`.
2. Update `platform-library/Chart.yaml` `version:` (and `appVersion` if tracked).
3. CHANGELOG.md (Keep a Changelog): retitle `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD`, start a fresh `[Unreleased]` section. Breaking changes go under "Changed (breaking)" with migration notes.
4. Run the exact CI-strict gate locally — the release workflow reruns it (`release.yaml:57-67`: shellcheck, helm lint, metaschema, then the strict gate) and a tag never ships unvalidated code, but finding failure pre-tag is far cheaper.
5. Commit via PR; CI (`.github/workflows/ci.yaml`) must pass on main.
6. Tag and push — ONLY with explicit user instruction (pushes are outside the Conservative profile):
   `git tag vX.Y.Z && git push origin vX.Y.Z`
7. The workflow then packages and pushes `dist/platform-X.Y.Z.tgz` to `oci://ghcr.io/<owner>/charts` (owner lowercased for GHCR, `release.yaml:79`) using the workflow `GITHUB_TOKEN` with `packages: write`. Cosign signing/provenance is tracked future work (`release.yaml:84`), not something to improvise.
8. Verify the run in Actions; a consumer then depends on `repository: oci://ghcr.io/caretak3r/charts`, `name: platform`, `version: X.Y.Z`.

## Commands
```bash
awk '$1 == "version:" {print $2}' platform-library/Chart.yaml        # what the tag must match
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh   # the gate the release reruns; passes at HEAD 8d09841 (re-run 2026-07-19: ==> PASS)
shellcheck -x scripts/*.sh tests/render.sh   # -x follows sourced files, as CI does; bare shellcheck false-alarms SC1091
check-jsonschema --check-metaschema platform-library/values.schema.reference.json
gh run list --workflow release.yaml --limit 3                        # verify the release run (after tagging)
```
The tag→GHCR publish path runs only in Actions, but it is proven: `v2.0.0` was published to `oci://ghcr.io/caretak3r/charts` on 2026-07-15 (release run 29384461101, green end-to-end). Each new release still verifies its own run in Actions — in-repo consumers use `file://` and never exercise the OCI path.

## Quality bar
(1) The strict gate passes locally AND in the release run — the workflow is the final arbiter; (2) the release contains no hardening regression (diff review of security defaults since last tag); (3) semver honestly reflects contract changes — an under-versioned breaking release is the worst outcome this process exists to prevent.

## Verification checklist
- [ ] Chart.yaml version == CHANGELOG heading == intended tag (checked before tagging)
- [ ] Local strict gate `==> PASS` at the release commit
- [ ] CHANGELOG breaking entries carry migration notes
- [ ] Explicit user go-ahead recorded before `git push origin vX.Y.Z`
- [ ] Release workflow run green end-to-end (gate + package + push steps)

## Stop and ask before
- pushing any tag or commit (hard requirement — Conservative profile; releases are irreversible-ish public artifacts)
- releasing with a golden/count change you cannot explain
- re-tagging or force-moving an existing tag
- changing the OCI destination or workflow permissions

## Common mistakes
- Tagging before bumping Chart.yaml — the workflow errors, and the bad tag must be deleted from the remote.
- Editing CHANGELOG without moving `[Unreleased]` — the next release inherits stale notes.
- Assuming the local gate is optional because the workflow reruns it — a failed release run leaves a version-bumped main with no published artifact.
- Calling a values-key rename a "refactor" and shipping it as a minor version.
- Improvising chart signing — cosign is explicitly deferred future work.

## Done means
- Version/CHANGELOG/tag alignment shown, local strict-gate `==> PASS` pasted, user authorization for the push quoted, and the green release-workflow run linked/identified.
