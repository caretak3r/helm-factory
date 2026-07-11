# Concept: exports.defaults / import-values mechanics

How consumers get the library's 600+ lines of defaults with one dependency stanza:

```yaml
dependencies:
  - name: platform
    version: ">=2.0.0-0"
    repository: file://../../../platform-library    # dev; prod: oci://ghcr.io/caretak3r/charts
    import-values:
      - defaults
```

Helm's `import-values` merges the library's `exports.defaults` map ([[values-contract]]) into the consumer's **root** values scope. Three consequences that cause most consumer confusion:

1. **Missing `import-values: [defaults]`** = every generator sees empty values = chart renders empty or fails confusingly. The #1 consumer pitfall.
2. **Overrides go at root**, never nested under `platform:` — values nested under the dependency name are silently ignored by the generators, which read `.Values.<block>` at root.
3. **Library-side keys outside `exports.defaults` are unexported** — adding a default at values.yaml top level silently does nothing for consumers.

The schema is shaped for the *post-import* root scope, which is why it ships as `values.schema.reference.json` and is copied into consumers as `values.schema.json` rather than living at the library root ([[values-contract]], `tests/render.sh:13`).

Working reference: `tests/fixtures/minimal/` ([[fixtures-and-render-script]]); generator: [[scaffold-new-app-chart]].

Sources: fixture Chart.yaml + values.yaml head read, minimal render executed (3 kinds) 2026-07-10, HEAD 4fb9386.
