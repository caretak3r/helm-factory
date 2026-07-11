---
name: values-contract-change
description: Use when adding, renaming, retyping, or re-defaulting any consumer-facing values key, or editing values.schema.reference.json. Do not use for template-only changes with no values impact (see template-house-style) or security-default changes (see security-posture-invariants first).
---

# Change the Values Contract

## First rule
The consumer values contract is merge bar #3. Renaming or moving a values key is a breaking change requiring a major version bump even if every render still passes — consumers' values files break silently, which is worse than loudly.

## Steps
1. Classify the change first: **additive** (new key, safe default) vs **breaking** (rename/move/retype/behavior-changing re-default). Breaking ⇒ major bump in `platform-library/Chart.yaml` + CHANGELOG "Changed (breaking)" entry + migration note. If in doubt, it's breaking.
2. Place the default under `exports.defaults` in `platform-library/values.yaml` — the library's entire consumer surface lives there (file starts `exports:\n  defaults:`; effective indent 8 spaces for leaf keys). A key at the top level of values.yaml is never exported to consumers via `import-values: [defaults]`.
3. Extend `platform-library/values.schema.reference.json` (draft 2020-12, `additionalProperties: true` at root). Match house patterns: enums for closed sets (`workload.type`: `Deployment|StatefulSet|DaemonSet`; `image.pullPolicy`; `service.type`; `mtls.policy`), `image.tag` rejects `"latest"` via `not: {const: latest}`, conditional requirements where applicable (gateway `parentRefs`). Descriptions are prescriptive.
4. Know why the schema is NOT `values.schema.json` at the library root: the library's own values are wrapped under `exports.defaults` and would fail the post-import-shaped schema. It ships as `values.schema.reference.json` and is *copied into consumers* as `values.schema.json` (scaffold at generation time; `tests/render.sh:13` on every fixture render), so Helm validates the coalesced post-import values. Never add a root `values.schema.json` to the library; never edit a fixture's copy.
5. Propagate to fixtures: exercise the new key in at least one fixture's `values.yaml`; if it changes rendered output, regenerate goldens intentionally and bump `expected_kinds` if the object count changed.
6. Triple-entry docs: README consumer reference, CORE.md where relevant, CHANGELOG `[Unreleased]`.
7. Validate: metaschema, per-fixture schema conformance, and the full gate.

## Commands
```bash
check-jsonschema --check-metaschema platform-library/values.schema.reference.json
check-jsonschema --schemafile platform-library/values.schema.reference.json tests/fixtures/full/values.yaml
tests/render.sh minimal --set <new.key>=<value>               # exercise the key end-to-end
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh   # passes at HEAD 4fb9386
```

## Quality bar
(1) Gate passes across the 1.31-1.36 matrix including the helm-side schema-rejection legs; (2) no new key weakens a hardening default and no schema constraint is loosened (the `latest` rejection, enum exact-casing, and pin requirements are guardrails, not suggestions); (3) contract stability: additive-only unless a major bump is explicitly on the table.

## Verification checklist
- [ ] Default lives under `exports.defaults`, not top-level values.yaml
- [ ] Schema updated in `values.schema.reference.json` only; metaschema check `ok`
- [ ] All four fixture values still conform (`check-jsonschema` per fixture — the gate runs this)
- [ ] Key exercised in a render; output verified by eye
- [ ] Breaking? — stated explicitly, version bump + CHANGELOG breaking entry present
- [ ] Gate `==> PASS`; golden/count changes intentional

## Stop and ask before
- renaming, moving, or retyping any existing key (breaking; requires owner sign-off on the major bump)
- loosening any schema constraint (enum, `tag: latest` rejection, required fields)
- changing an existing default's value — even "harmless" re-defaults change every consumer's rendered output
- adding a root `values.schema.json` to the library

## Common mistakes
- Adding the key at values.yaml top level — silently unexported; the consumer sees nothing and the "feature" no-ops.
- Editing `tests/fixtures/*/values.schema.json` — a generated copy, overwritten by the next `tests/render.sh` run.
- Lowercase enum values in examples/fixtures (`deployment`, `latest`, unquoted numeric tags) — rejected at render time; docs must match enums exactly.
- Renaming `extraObjects` or nesting it differently — it is deliberately not called `resources` to avoid colliding with container `resources:`.
- Documenting the new key in README but not the schema (consumers get no validation) or vice versa (consumers get no docs).

## Done means
- Additive/breaking classification stated; metaschema + fixture-conformance + gate `==> PASS` outputs pasted; render snippet showing the key in effect; docs/CHANGELOG diffs listed.
