# Entity: lint-library.sh — THE validation gate

`scripts/lint-library.sh` (1150 lines) is the single gate that proves library work. Sequence (verified by running it in CI-strict mode 2026-07-10 at HEAD 4fb9386 and again 2026-07-19 at HEAD 8d09841 — result `==> PASS`, exit 0, ~4 min):

1. `helm lint` the library (weak on its own — [[platform-library-chart]]).
2. Reference-schema metaschema check + every fixture's values against it (check-jsonschema) (`:168+`).
3. Per-fixture render matrix across `KUBE_VERSIONS=(1.34..1.36)` (now sourced from `scripts/lib/schema-manifest.sh:18`; lint-library.sh accepts env-var subsets, `:27-39`) with expected-object-count assertions — `expected_kinds()` at `:95-103`: minimal 3, full 26, stateful 7, daemon 3. See [[golden-count-oracle]].
4. Golden snapshot diff at canonical k8s 1.34 (`GOLDEN_KUBE_VERSION`, `:56`); `normalize_render` (`:110`) redacts nondeterministic tlsSelfSigned cert data. `UPDATE_GOLDEN=1` regenerates (`:230-240`).
5. kubeconform strict against the schemas **vendored** under `tests/schemas/` (`scripts/vendor-schemas.sh`; hermetic, no network — the datreeio catalog is only the vendoring *source*). Each matrix version validates its OWN render inside the render loop (`:203-215`) — the old single-canonical-render gap (bead helm-factory-uaw) was fixed 2026-07-11.
6. Negative render: nulling force-assume must drop all 7 CRD-backed Kinds and emit no `{}` docs (`:256-270`, guarded `if neg=$(...)` idiom).
7. Image-pin, helm-side schema, and posture-guardrail negative tests (legs spread across `:389-560`) — each greps the exact `fail` message; see [[fail-closed-guardrail-pattern]].

CI-strict invocation (what CI and release run): `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh`. Subset runs (`FIXTURES=minimal`, ~14 s) end `==> PASS (subset)` and skip the guardrail suite — never done-evidence. Note `--set key=null` in the negative legs *deletes* the key ([[set-null-deletes-key]]).

Sources: raw/lint-library-header.md (archival, pre-vendoring); full script read + executed 2026-07-10; anchors re-verified + gate re-executed 2026-07-19.
