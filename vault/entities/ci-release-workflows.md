# Entity: CI and release workflows

**CI** (`.github/workflows/ci.yaml`, read in full 2026-07-10): on PR and push-to-main — installs helm pinned to **4.2.0** (`:23`) and kubeconform **0.8.0** (`:29`), then shellcheck → helm lint → schema metaschema → `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` (`:46`). Locally installed helm matches the CI pin exactly (discovery verified). See [[lint-library-gate]].

**Release** (`.github/workflows/release.yaml`, read in full): on `v*.*.*` tags —
1. Refuses tags that don't match `platform-library/Chart.yaml` `version:` (`:37-45`).
2. Reruns the entire CI gate (`:47-58`) — "a tag never ships unvalidated code."
3. `helm package` + `helm push` to `oci://ghcr.io/<owner>/charts`, owner lowercased for GHCR (`:66-72`), using workflow `GITHUB_TOKEN` with `packages: write`.
4. Cosign signing/provenance deliberately deferred (`:74-75`, references fable5-review.md #14).

UNVERIFIED: the tag→GHCR publish path has never been executed from this environment, and whether ghcr.io currently hosts a published `platform` 2.0.0 is unknown — in-repo consumers all use `file://` (raw/discovery-could-not-verify.md). Claims above come from reading the workflow files only.

Tool versions in the two workflows mirror each other by explicit comment (`release.yaml:21`) — bumping one means bumping both.

Sources: both workflow files read 2026-07-10, HEAD 4fb9386.
