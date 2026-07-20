# Entity: test fixtures + tests/render.sh

Four consumer charts under `tests/fixtures/` exercise the library: `minimal` (3 objects), `full` (26), `stateful` (7), `daemon` (3) — counts verified by rendering 2026-07-10, re-verified 2026-07-19 (`expected_kinds()` at `scripts/lint-library.sh:95-103`; stateful gained the managed headless Service and full gained two objects in the #23–#34 correctness waves). Each depends on the library via `repository: file://../../../platform-library` with `import-values: [defaults]` (`tests/fixtures/minimal/Chart.yaml`); see [[exports-defaults-import-mechanics]].

`tests/render.sh <fixture> [helm args]` (18 lines, read in full): wipes `charts/` + `Chart.lock` (`:13`), copies `values.schema.reference.json` in as `values.schema.json` (`:16`) so Helm enforces the coalesced post-import values, then `helm dependency update` + `helm template t <dir>` (`:17-18`). Extra args pass straight to helm (`--kube-version`, `--api-versions`, `--set`).

Tracked per fixture: `Chart.yaml`, `values.yaml`, `templates/app.yaml`. Generated and gitignored: `charts/`, `Chart.lock`, `values.schema.json` — editing those is editing output ([[golden-count-oracle]] covers the committed goldens, which ARE tracked but only regenerated via `UPDATE_GOLDEN=1`).

The `full` fixture force-assumes the four CRD groups (`tests/fixtures/full/values.yaml:83-87`) and opts into cluster-scoped extras (`:92`) — the bridge for [[template-vs-cluster-capabilities]]. Fixture Chart.yamls carry no `kubeVersion` constraint (verified by grep; corrects a discovery-report claim).

Sources: files read + executed 2026-07-10, HEAD 4fb9386; anchors re-verified 2026-07-19, HEAD 8d09841.
