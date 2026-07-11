# Entity: lint-library.sh — THE validation gate

`scripts/lint-library.sh` is the single gate that proves library work. Sequence (verified by running it in CI-strict mode 2026-07-10, HEAD 4fb9386 — result `==> PASS`, exit 0, ~1-2 min warm):

1. `helm lint` the library (weak on its own — [[platform-library-chart]]).
2. Reference-schema metaschema check + every fixture's values against it (check-jsonschema) (`:89-109`).
3. Per-fixture render matrix across `KUBE_VERSIONS=(1.31..1.36)` (`:31`) with expected-object-count assertions — `expected_kinds()` at `:41-49`: minimal 3, full 24, stateful 6, daemon 3. See [[golden-count-oracle]].
4. Golden snapshot diff at canonical k8s 1.31 (`GOLDEN_KUBE_VERSION`, `:32`); `normalize_render` (`:54-56`) redacts nondeterministic tlsSelfSigned cert data. `UPDATE_GOLDEN=1` regenerates (`:136-139`).
5. kubeconform strict across the matrix with datreeio CRDs-catalog schemas (`:150-162`). Known gap: it validates the single canonical render against each version's schemas, not per-version renders (beads helm-factory-uaw; raw/discovery-could-not-verify.md).
6. Negative render: nulling force-assume must drop all 7 CRD-backed Kinds and emit no `{}` docs (`:165-176`).
7. Image-pin, helm-side schema, and posture-guardrail negative tests (`:178-268`) — each greps the exact `fail` message; see [[fail-closed-guardrail-pattern]].

CI-strict invocation (what CI and release run): `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh`. Note `--set key=null` in the negative legs *deletes* the key ([[set-null-deletes-key]]).

Sources: raw/lint-library-header.md; full script read + executed 2026-07-10.
