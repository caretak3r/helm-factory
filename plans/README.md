# Uplift plans — index

Advisory pass planned at commit `583b401` (2026-07-28). Each plan is
self-contained: executors read the plan top to bottom, run its drift check
first, and re-anchor by quoted content (never line numbers) if the tree moved.
Executors update the **Status** column here when they start/finish a plan,
unless a reviewer dispatched them and owns this index.

Status values: `planned` → `in progress` → `landed` (PR merged).

| Plan | Title | Bead | Priority / Effort / Risk | Status |
|---|---|---|---|---|
| [001](001-security-posture-warnings.md) | NOTES warnings for weakened security posture and active escape hatches | helm-factory-mik | P1 / S / LOW | landed (PR #56 → 7ea708f) |
| [002](002-hook-job-named-error.md) | Hook Job without work fails with a named error, not a reflect crash | helm-factory-87x | P1 / S / LOW | landed (PR #55 → 8a6aba8) |
| [003](003-extraobjects-fail-closed.md) | extraObjects: fail closed on unknown Kinds | hf-gra | P1 / M / MEDIUM | landed (PR #60 → 3419a79) |
| [004](004-imageref-registry-guard.md) | imageRef: stop double-prefixing the registry (both call paths) | helm-factory-wvy | P2 / S / LOW | planned |
| [005](005-capability-gate-secondary-kinds.md) | Capability-gate AuthorizationPolicy and GRPCRoute | helm-factory-vh8 | P1 / M / MED | landed (PR #57 → 5dc79f6) |
| [006](006-gate-render-speed.md) | Cache the fixture dependency build (~97% of gate render overhead) | helm-factory-jgg | P2 / M / MED | landed (PR #58 → aeb1a69) |
| [007](007-gate-validation-coverage.md) | Close the gate's validation gaps (kubeconform everywhere, no silent PASS) | helm-factory-bkv | P2 / M / MED | landed (PR #63 → 16e6212) |
| [008](008-supply-chain-ci-hardening.md) | Supply-chain / CI hardening | hf-ocq | P2 / M / LOW-MED | landed (PR #59 → b3f85bd) |
| [009](009-podpolicy-extraction.md) | Pod-policy + workload-metadata extraction (zero golden diffs) | hf-s41 | P2 / M / LOW | landed (PR #61 → a6e1aff) |
| [010](010-capability-registry-unification.md) | Unify capability representations into one feature registry | helm-factory-cfm | P2 / L / MEDIUM | planned |

## Landed PRs (this uplift batch — all merged 2026-07-31)

Squash-merge order: #55 → #58 → #56 → #57 → #59 → #60 → #61. Each was
rebased onto the moving `main` before merge; conflicts were confined to
`CHANGELOG.md [Unreleased]` (union-resolved) except #60, whose
`scripts/lint-library.sh` hunk carried a stale copy of the count-based
anti-drift check that #57 had already replaced with the name-set version —
resolved by keeping the name-set check and inserting only #60's three new
extraObjects NOTES assertions. Post-rebase full strict gate re-run locally
for #60 and #61 (`==> PASS`, exit 0); CI green on every merge.

- 002 → [#55](https://github.com/caretak3r/helm-factory/pull/55) → `8a6aba8`
- 006 → [#58](https://github.com/caretak3r/helm-factory/pull/58) → `aeb1a69` (gate now ~25s in CI)
- 001 → [#56](https://github.com/caretak3r/helm-factory/pull/56) → `7ea708f`
- 005 → [#57](https://github.com/caretak3r/helm-factory/pull/57) → `5dc79f6`
- 008 → [#59](https://github.com/caretak3r/helm-factory/pull/59) → `b3f85bd`
- 003 → [#60](https://github.com/caretak3r/helm-factory/pull/60) → `3419a79`
- 009 → [#61](https://github.com/caretak3r/helm-factory/pull/61) → `a6e1aff`
- 007 → [#63](https://github.com/caretak3r/helm-factory/pull/63) → `16e6212`
  (merged 2026-08-01, after the 2026-07-31 batch; bead helm-factory-bkv closed)

Beads closed to match: helm-factory-87x, helm-factory-jgg, helm-factory-mik,
helm-factory-vh8, hf-ocq, hf-gra, hf-s41.

## Sequencing constraints

- **002 and 004 are sequential**, never parallel worktrees — both edit
  `platform-library/templates/_helpers.tpl` (different hunks; avoids a
  pointless merge conflict).
- **010 hard-depends on 005 being merged** (bead dependency wired:
  helm-factory-cfm blocked by helm-factory-vh8; plan 010's Phase 0 verifies).
  Between 005 and 010 landing, a PeerAuth-only cluster renders
  PeerAuthentication without AuthorizationPolicy — NOTES-warned and no
  unserved apiVersion (strictly better than HEAD), but fail-open on
  principals until 010. Land 010 promptly after 005.
- **Soft ordering**: 006 before 007 (007 adds ~50 validated renders that
  benefit from the cache); 007 after 005 (both edit `scripts/lint-library.sh`;
  005's new renders are adopters of 007's helper, not conflicts).
- **008 updates existing bead hf-ocq** — do not file a duplicate bead.
- **005 vs hf-dtj**: if hf-dtj (fixture coverage) lands first and enables
  grpcRoute in the full fixture, re-verify plan 005's zero-golden claim.

## Ground rules for executors

- Goldens are the contract: a golden diff you can't explain means the change
  is wrong. Plans 001/005/006/009/010 must land with byte-identical goldens.
- Definition of done, every plan:
  `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh`
  ends `==> PASS`. Never run two gate invocations concurrently
  (fixture-artifact race).
- Every new gate check ships with a mutation test proving it can go RED.
- PR-only main, squash-merge, Conventional Commits.
- Stall prevention (see `.claude/operating/fable-to-opus.md` §9): long commands run
  FOREGROUND with a raised timeout (up to 600000 ms) — never raw shell `&`/`nohup`, and don't
  trust `run_in_background` to wake a stopped executor (observed failing 2026-07-31). Never
  end a turn "waiting"; stop deliberately with a resumable state instead. Keep the worktree
  untouched for a gate's full duration — mid-run mutations contaminate the verdict.
