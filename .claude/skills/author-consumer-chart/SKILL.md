---
name: author-consumer-chart
description: Use when creating or modifying a product/app chart that consumes the platform library (fixtures under tests/fixtures/ or standalone consumer charts). Do not use for changes to the library's own templates or defaults (see add-library-kind / values-contract-change).
---

# Author a Consumer Chart

## First rule
`import-values: [defaults]` in the dependency block is non-negotiable. It merges the library's `exports.defaults` into the consumer's **root** values scope. Without it every generator sees empty values and the chart renders empty or fails confusingly. This is the #1 consumer pitfall.

## Steps
1. Prefer the scaffold — it generates all four pieces correctly:
   `scripts/new-app-chart.sh <name> [--dir <path>] [--repo <url>] [--version <range>]`.
2. If hand-writing, the consumer anatomy is exactly four pieces (compare `tests/fixtures/minimal/`):
   - `Chart.yaml` with the dependency:
     ```yaml
     dependencies:
       - name: platform
         version: ">=2.0.0-0"
         repository: file://../../../platform-library   # dev; prod: oci://ghcr.io/caretak3r/charts
         import-values:
           - defaults
     ```
     Note the dependency name is `platform` — the chart's name, not the directory name `platform-library`.
   - `templates/app.yaml` containing only `{{ include "platform.render" . }}` (`_app.yaml:116-120` is the entrypoint).
   - `values.yaml` with overrides at the **root** (not nested under `platform:` — import-values lands defaults at root, so overrides go at root too).
   - `values.schema.json` copied from `platform-library/values.schema.reference.json` so Helm enforces the coalesced post-import values (the scaffold copies it; `tests/render.sh:16` re-copies it for fixtures on every render).
3. Set the mandatory values: `image.repository` plus `image.tag` or `image.digest` — there is no default tag; an unpinned image fails render (`_helpers.tpl:111`).
4. If the chart uses CRD-backed features (certificate, mtls, gatewayApi, serviceMonitor, podMonitor) and must render offline/CI, force-assume the CRD groups (pattern at `tests/fixtures/full/values.yaml:83-87`):
   ```yaml
   capabilities:
     apiVersions:
       - gateway.networking.k8s.io/v1
       - cert-manager.io/v1
   ```
   Entries match as `group/version` or `group/version/Kind`.
5. Hook jobs: `jobs.image` inherits the main image, but the main **digest** is inherited only when repositories match; a hook with a different repo and no explicit pin fails render (`_helpers.tpl:747`). `scriptFile` paths resolve under the consumer chart's `scripts/` directory (prefix added if missing — `_configmap-script.yaml:50-51`; fail if absent — `_configmap-script.yaml:58`).
6. Render and read the output — count the kinds you expect, check the objects you enabled actually appear.

## Commands
```bash
scripts/new-app-chart.sh myapp --dir /path/to/myapp
helm dependency update /path/to/myapp && helm template myapp /path/to/myapp   # zero-config = 3 kinds
tests/render.sh <fixture> [--kube-version 1.34] [--set k=v]                   # for in-repo fixtures
```
When the consumer lives outside this repo, rewrite the scaffolded `file://../platform-library` repository to an absolute `file:///absolute/path/to/helm-factory/platform-library` (or pass `--repo`). Fixture edits additionally require the full gate: `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` (passes at HEAD 8d09841, strict gate re-run 2026-07-19: `==> PASS`).

## Quality bar
(1) The chart renders clean at every supported `--kube-version` (1.34-1.36) with its CRD groups force-assumed; (2) do not disable security contexts, re-enable token automount, or loosen guardrails in the consumer unless the application demonstrably needs it — and then per-field, never `enabled: false` wholesale; (3) consumer values use only documented library keys — check README/schema rather than inventing keys that silently no-op.

## Verification checklist
- [ ] `helm template` (or `tests/render.sh <fixture>`) exits 0 and prints the expected kinds
- [ ] Every enabled feature's object is present in the output (CRD features: also present WITHOUT a cluster because force-assume is set)
- [ ] `grep -c '^kind:'` matches your expectation; for fixtures, `expected_kinds` in `scripts/lint-library.sh:95-103` updated to match
- [ ] Fixture changes: full gate `==> PASS` and goldens regenerated intentionally
- [ ] No values nested under a `platform:` key; no `tag: latest`; enums exact-case (`Deployment`, not `deployment`)

## Stop and ask before
- flipping `podSecurityContext.enabled`/`containerSecurityContext.enabled` to false in a consumer (per-field override is the sanctioned path)
- setting `allowClusterScopedExtras: true` (widens blast radius to cluster scope)
- setting `mtls.allowAllPrincipals: true` (opts into every mesh workload)
- pointing `repository:` at a remote OCI registry in a fixture (fixtures must stay `file://` and hermetic)

## Common mistakes
- Missing `import-values: [defaults]` — everything renders empty; the symptom looks like a library bug.
- Nesting overrides under `platform:` — they are silently ignored; values land at root.
- Expecting CRD-backed objects in a bare `helm template` without force-assume — they vanish by design (see capability-gates).
- Editing a consumer's `values.schema.json` — it is a generated copy; the source is `values.schema.reference.json`.
- Expecting the hook Job to run as the release ServiceAccount: hooks get their own distinctly named, hook-created SA (`platform.serviceAccount.hook`, `_helpers.tpl:533` — `<fullname>-preinstall`, weight-ordered below the Job). The distinct name is deliberate: a same-named hook copy would let `before-hook-creation` delete the LIVE release SA on every upgrade.
- Unquoted numeric tags (`tag: 1.30`) — YAML floats; quote them.

## Done means
- Render command output (kinds present, exit 0) pasted; for fixtures, gate `==> PASS` pasted; any security-posture overrides listed explicitly with justification.
