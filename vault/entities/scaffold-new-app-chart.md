# Entity: scripts/new-app-chart.sh — consumer scaffold

Scaffolds a complete consumer chart wired to the library. Usage: `scripts/new-app-chart.sh <name> [--dir <path>] [--repo <url>] [--version <range>] [--app-version <v>]`. Defaults: `repo=file://../platform-library`, `version=">=2.0.0-0"` (`scripts/new-app-chart.sh:28-33`).

Generates the four-piece consumer anatomy ([[exports-defaults-import-mechanics]]): Chart.yaml with the `platform` dependency + `import-values: [defaults]`, `templates/app.yaml` (`{{ include "platform.render" . }}`), overrides-only values.yaml, and a copy of the reference schema as `values.schema.json` — plus NOTES.txt and .helmignore. Stamps `kubeVersion: ">=1.31.0-0 <1.37.0-0"` into the new chart (heredoc at `:81`) — part of the version-bump touch list.

Injection-hardened: chart name must match RFC 1123 (`:49-50`); repo/version/app-version charsets are restricted so crafted arguments cannot inject YAML structure (`:58-63`).

Discovery verified the end-to-end path (scaffold → `helm dependency update` → `helm template` → 3 kinds: ServiceAccount, Service, Deployment) in a scratchpad; when the chart lives outside the repo, the `file://../platform-library` path must be rewritten to an absolute path or set via `--repo` (raw/discovery-s4-commands.md, row 8).

Sources: script read 2026-07-10, HEAD 4fb9386; execution evidence from discovery §4 (that phase's run, not re-run in AUTHOR staging).
