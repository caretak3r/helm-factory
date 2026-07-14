---
name: validate-factory
description: Use when any change touched platform-library/, tests/fixtures/, tests/render.sh, scripts/, or the values schema, or when deciding whether library work is actually done. Do not use for authoring new consumer charts outside this repo (see author-consumer-chart) or for diagnosing a specific render error (see debug-render-failure).
---

# Validate the Helm Factory

## First rule
`helm lint platform-library/` proves nothing. The library is `type: library` — every template is `_`-prefixed and renders nothing by itself, so lint passes even when every generator is broken. Only a consumer-fixture render is evidence. Work is done when `scripts/lint-library.sh` prints `==> PASS`, not before.

## Steps
1. Run the cheap ladder first: `helm lint`, then a single fixture render (`tests/render.sh minimal` or the fixture nearest your change). This catches parse errors in seconds.
2. If your change touched shell scripts, run `shellcheck scripts/*.sh tests/render.sh`.
3. If your change touched `values.schema.reference.json`, run the metaschema check.
4. Run the full gate in CI-strict mode (command below). It runs: helm lint → schema metaschema + per-fixture values validation → render matrix across k8s 1.34-1.36 with expected-object-count assertions (`expected_kinds()` at `scripts/lint-library.sh:52-60`: minimal 3, full 24, stateful 6, daemon 3) → golden diff at canonical k8s 1.34 → kubeconform strict across the matrix → negative CRD-drop render → image-pin, helm-side schema, and posture guardrail negative tests.
5. Read every `FAIL:` line; each one names the failing leg. A count mismatch says "update expected_kinds if intentional" — decide whether the change was intended before touching the number.
6. If the golden diff fails and the render change was *intended*: run `UPDATE_GOLDEN=1 scripts/lint-library.sh`, then read `git diff tests/golden/` line by line — the diff is a review artifact, not noise. Then re-run the strict gate clean.
7. Confirm `git status --porcelain` shows no unexpected tracked-file changes (fixture `charts/`, `Chart.lock`, and `values.schema.json` copies are gitignored and expected to regenerate).

## Commands
```bash
helm lint platform-library/
tests/render.sh minimal          # or: full | stateful | daemon; extra helm args pass through
shellcheck scripts/*.sh tests/render.sh
check-jsonschema --check-metaschema platform-library/values.schema.reference.json
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh   # THE gate; ~1-2 min warm
```
`UPDATE_GOLDEN=1 scripts/lint-library.sh` regenerates `tests/golden/*.yaml` (mechanism at `scripts/lint-library.sh:185-188`; not run in staging — it mutates committed files). Always follow it with a manual `git diff tests/golden/` review and a clean strict-gate re-run.

## Quality bar
In merge-bar order: (1) the gate passes across the full k8s 1.34-1.36 matrix; (2) no hardening default or fail-closed guardrail was weakened to get there; (3) no consumer-facing values key was renamed, moved, or retyped without acknowledging it as a breaking change. A green gate obtained by bumping counts or regenerating goldens without reading the diff fails the bar.

## Verification checklist
- [ ] `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` exits 0, last line `==> PASS`
- [ ] Any `expected_kinds` change matches an intentional object-count change, stated in your report
- [ ] Any `tests/golden/*.yaml` diff was read line by line and every hunk is explained
- [ ] `git status --porcelain` clean of tracked-file surprises
- [ ] The first run after a network change may need the datreeio CRD schema download; a kubeconform network failure is an environment problem, not a code problem — say so, don't "fix" code

## Stop and ask before
- running `UPDATE_GOLDEN=1` when you cannot explain every hunk of the resulting diff
- bumping `expected_kinds` numbers to silence a count failure you did not intend
- weakening or deleting any negative test in `lint-library.sh` (they are the guardrail contract)
- editing `normalize_render` (`scripts/lint-library.sh:67-75`) — the tlsSelfSigned redaction exists because offline renders mint a fresh cert every time

## Common mistakes
- Declaring victory after `helm lint` (§ First rule).
- Treating a golden diff as noise and accepting it wholesale — the goldens and counts are the regression oracle.
- Misreading `--set foo=null` in the gate's negative legs (`lint-library.sh:166,223`): it *deletes* the key from coalesced values, it does not set a literal null.
- Assuming kubeconform checks a single canonical render: since helm-factory-uaw was fixed (2026-07-11), each matrix version validates its OWN render inside the render loop — a kubeconform failure at k8s X.Y points at that version's render specifically.
- Running the gate but not reading past the first FAIL — later legs often localize the real cause.

## Done means
- `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` output ending `==> PASS` pasted into your report, plus an explicit statement of whether goldens/counts changed and why.
