# Entity: test fixtures + tests/render.sh

Four consumer charts under `tests/fixtures/` exercise the library: `minimal` (3 objects), `full` (24), `stateful` (6), `daemon` (3) — counts verified by rendering 2026-07-10. Each depends on the library via `repository: file://../../../platform-library` with `import-values: [defaults]` (`tests/fixtures/minimal/Chart.yaml`); see [[exports-defaults-import-mechanics]].

`tests/render.sh <fixture> [helm args]` (15 lines, read in full): wipes `charts/` + `Chart.lock` (`:10`), copies `values.schema.reference.json` in as `values.schema.json` (`:13`) so Helm enforces the coalesced post-import values, then `helm dependency update` + `helm template t <dir>` (`:14-15`). Extra args pass straight to helm (`--kube-version`, `--api-versions`, `--set`).

Tracked per fixture: `Chart.yaml`, `values.yaml`, `templates/app.yaml`. Generated and gitignored: `charts/`, `Chart.lock`, `values.schema.json` — editing those is editing output ([[golden-count-oracle]] covers the committed goldens, which ARE tracked but only regenerated via `UPDATE_GOLDEN=1`).

The `full` fixture force-assumes the four CRD groups (`tests/fixtures/full/values.yaml:75-80`) and opts into cluster-scoped extras (`:85`) — the bridge for [[template-vs-cluster-capabilities]]. Fixture Chart.yamls carry no `kubeVersion` constraint (verified by grep; corrects a discovery-report claim).

Sources: files read + executed 2026-07-10, HEAD 4fb9386.
