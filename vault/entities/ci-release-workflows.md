# Entity: CI and release workflows

**CI** (`.github/workflows/ci.yaml`, read in full 2026-07-10): on PR and push-to-main — installs helm pinned to **4.2.0** (`:23`) and kubeconform **0.8.0** (`:29`), then shellcheck (`-x`, `:37`) → helm lint → schema metaschema → `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` (`:46`). Locally installed helm matches the CI pin exactly (discovery verified). Since 2026-07-17 the active `main-pr-only` ruleset makes the lint-library check required on `main` — PR-only, squash-merge, zero bypass actors. See [[lint-library-gate]].

**Release** (`.github/workflows/release.yaml`, read in full): on `v*.*.*` tags —
1. Refuses tags that don't match `platform-library/Chart.yaml` `version:` (`:37-45`).
2. Refuses tags without a matching `^## [X.Y.Z]` CHANGELOG heading (`:47-51`) — added post-discovery.
3. Reruns the entire CI gate (shellcheck `:57`, helm lint `:60`, metaschema `:63`, strict gate `:66`) — "a tag never ships unvalidated code."
4. `helm package` + `helm push` to `oci://ghcr.io/<owner>/charts`, owner lowercased for GHCR (`:75-82`, lowercase at `:79`), using workflow `GITHUB_TOKEN` with `packages: write`.
5. Cosign signing/provenance deliberately deferred (`:84`, references fable5-review.md #14).

VERIFIED 2026-07-15: the publish path was executed for real — tag `v2.0.0` ran the workflow green (run 29384461101) and published `platform-2.0.0.tgz` to `oci://ghcr.io/caretak3r/charts`. In-repo consumers still use `file://`. Gates run AFTER the tag exists — a failed release run leaves a bad tag needing manual deletion before retry.

Tool versions in the two workflows mirror each other by explicit comment (`release.yaml:21`) — bumping one means bumping both.

Sources: both workflow files read 2026-07-10, HEAD 4fb9386; anchors re-verified 2026-07-19, HEAD 8d09841; release run verified via `gh run list --workflow=release.yaml`.
