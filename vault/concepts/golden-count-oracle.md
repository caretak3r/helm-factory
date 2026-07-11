# Concept: the golden/count regression oracle

The library has no unit tests; its regression oracle is two committed expectations in [[lint-library-gate]]:

1. **Object counts**: `expected_kinds()` (`scripts/lint-library.sh:41-49`) asserts each fixture's `^kind:` line count across the whole k8s matrix (minimal 3, full 24, stateful 6, daemon 3).
2. **Golden snapshots**: `tests/golden/*.yaml`, a full normalized render of each fixture at canonical k8s 1.31, diffed byte-for-byte. `normalize_render` (`:54-56`) redacts tlsSelfSigned cert data, the only nondeterministic content (offline renders mint a fresh cert every time because `lookup` is empty under `helm template`).

The oracle's value is that it changes **only when a render change is intended**. Discipline:
- Goldens are never hand-edited; only `UPDATE_GOLDEN=1 scripts/lint-library.sh` regenerates them (`:136-139`), followed by a hunk-by-hunk review of `git diff tests/golden/` — the diff is a review artifact, not noise.
- Counts are never bumped to silence a failure; a count change must map to a deliberate object addition/removal.
- Gaming either (bump-and-pray, regenerate-and-accept) converts the oracle into a rubber stamp — the highest-leverage way a careless agent destroys this repo's safety net.

Fixture generated artifacts (`charts/`, `Chart.lock`, `values.schema.json`) are gitignored and rebuilt per render; goldens are the only committed render output ([[fixtures-and-render-script]]).

Sources: raw/lint-library-header.md; gate executed `==> PASS` 2026-07-10, HEAD 4fb9386. `UPDATE_GOLDEN=1` not executed (mutating); mechanism verified from source.
