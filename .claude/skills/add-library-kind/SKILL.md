---
name: add-library-kind
description: Use when adding support for a new Kubernetes resource type, CRD, or opinionated feature block to platform-library. Do not use for one-off objects a single consumer needs (see extra-objects-runbook) or for changing existing values keys only (see values-contract-change).
---

# Add a Kind to the Library

## First rule
Sources of truth are only: `platform-library/templates/_*.{yaml,tpl}`, `platform-library/values.yaml` (under `exports.defaults`), `platform-library/values.schema.reference.json`, and fixture `values.yaml`/`Chart.yaml`. Never edit rendered output, `tests/golden/*.yaml`, fixture `templates/app.yaml`, or fixture `charts/`/`values.schema.json` (generated, gitignored, overwritten on every render).

## Steps
The complete checklist (README.md:1124-1131). Skipping any step produces a silent failure, not an error.
1. **Generator**: create `platform-library/templates/_<resource>.yaml` with exactly one `define "platform.<resource>"` block. Follow template-house-style (list/dict calling convention, labels block, no leading `---`, prescriptive `fail` messages).
2. **Registry**: add the Kind to `platform.capabilities.registry` (`_capabilities.tpl:76-176`) with an *ordered* apiVersion preference list, newest GA first. If the Kind is cluster-scoped, also add it to the `clusterScoped` set (`_capabilities.tpl:304-306`). Missing registry entry ⇒ `apiVersionFor` returns `""` ⇒ the object never renders, silently.
3. **Wire into `_app.yaml`** in rendering-order position, wrapped in emit. Decide the gate mode: a CRD-backed Kind must ALSO be added to the `gatedKinds` map (`_capabilities.tpl:259-265`, `Kind: <values-block-name>`) and wrapped with `platform.capabilities.gateOpen` (`_capabilities.tpl:273-280` — it folds the `.enabled` check and the strict `apiVersionFor` gate together, and the same map drives the NOTES skipped-Kind warning; pattern at `_app.yaml:24,36,66,86,90`). A built-in Kind gets a plain `.Values.<resource>.enabled` gate and uses `apiVersionForOrDefault` inside the generator. No exceptions exist in the codebase — see capability-gates.
   ```
   {{- if include "platform.capabilities.gateOpen" (list . "<Kind>") }}
   {{- include "platform.emit" (include "platform.<resource>" .) }}
   {{- end }}
   ```
4. **Defaults**: add the `<resource>:` block under `exports.defaults` in `platform-library/values.yaml` (8-space effective indent), `enabled: false` unless the feature is part of the secure zero-config posture. Top-level keys outside `exports.defaults` are never exported to consumers.
5. **Schema**: extend `values.schema.reference.json` with the new block. Keep the schema draft 2020-12 and match the existing style (enums for closed sets, prescriptive `description`).
6. **Fixtures + oracle**: enable the feature in a fixture (`tests/fixtures/full/values.yaml` for CRD-backed Kinds — add the CRD group to its `capabilities.apiVersions` force-assume list at `values.yaml:83-87` if it's a new group). Bump `expected_kinds()` in `scripts/lint-library.sh:95-103`. Regenerate goldens with `UPDATE_GOLDEN=1 scripts/lint-library.sh` and review the diff. If the Kind is CRD-backed, extend the negative-render grep at `scripts/lint-library.sh:263` so the gate proves it drops when the API is absent.
7. **Docs (triple-entry)**: README consumer reference block, CORE.md rendering order + directory listing, CHANGELOG `[Unreleased]`; architecture-level changes also touch `docs/specs/platform-library-v2-architecture.md`.
8. Validate per validate-factory.

## Commands
```bash
tests/render.sh full                          # quick render while iterating
tests/render.sh full --set capabilities.apiVersions=null   # CRD Kind must vanish here
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh
```
Golden regeneration (`UPDATE_GOLDEN=1 scripts/lint-library.sh`) not run in staging; mechanism verified from `scripts/lint-library.sh:230-240`. Review `git diff tests/golden/` afterward.

## Quality bar
(1) Full gate passes across k8s 1.34-1.36 with the new Kind counted and golden-snapshotted; (2) the new generator ships with the same hardening posture as its peers (fail-closed on unsafe input, no weakened defaults); (3) the new values block is additive only — no existing key renamed or moved. A new Kind with no fixture coverage does not exist as far as the regression oracle is concerned.

## Verification checklist
- [ ] Kind appears in `tests/render.sh full` output with the expected apiVersion
- [ ] CRD-backed Kind disappears under `--set capabilities.apiVersions=null` (and the gate's negative grep covers it)
- [ ] `expected_kinds` bumped by exactly the number of new objects; gate `==> PASS`
- [ ] Golden diff reviewed hunk by hunk; only the new Kind's docs appear
- [ ] Schema: `check-jsonschema --check-metaschema platform-library/values.schema.reference.json` still `ok`
- [ ] README + CORE.md + CHANGELOG updated

## Stop and ask before
- choosing `apiVersionForOrDefault` for a CRD-backed Kind (renders objects that fail admission on clusters without the CRD — violates the never-conflict-on-deploy contract)
- shipping a new Kind `enabled: true` by default (changes every consumer's zero-config output)
- renaming any existing values key while you're in there (breaking change, major bump)
- adding a non-underscore template file to the library (breaks `type: library` purity — the chart must never self-render)

## Common mistakes
- Missing the registry entry: `apiVersionFor` returns `""`, wrapper gate is falsy, object silently never renders — looks like "my template is ignored". Same symptom if a gated Kind is missing from the `gatedKinds` map (`_capabilities.tpl:259-265`): `gateOpen` looks its values block up there and never opens.
- Forgetting the `platform.emit` wrapper: the new doc merges into the previous document (everything renders from one consumer template file). Emit invariant at `_util.tpl:14-20`.
- Malformed YAML inside the registry define: it's YAML-in-a-define parsed with `fromYaml` at every call site — one bad line breaks every render with a cryptic error far from your edit.
- Forgetting the fixture force-assume entry for a new CRD group: renders fine on a cluster, count-fails in CI.
- Adding defaults at the top level of `values.yaml` instead of under `exports.defaults`: silently unexported.
- Bumping `expected_kinds` without checking the fixture actually renders the new object (a gate that passes for the wrong reason).

## Done means
- New Kind rendered in fixture output, negative render proven for CRDs, `==> PASS` gate output pasted, golden diff summarized, triple-entry docs updated, and the gate-mode decision (strict vs OrDefault) stated with its justification.
