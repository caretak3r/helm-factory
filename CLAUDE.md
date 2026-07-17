# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

## What this project is

`platform` (source dir `platform-library/`, published as
`oci://ghcr.io/caretak3r/charts/platform`) is a **Helm 4 pure library chart** —
it ships no installable templates of its own. Product/app charts declare it as a
dependency with `import-values: [defaults]` and render *everything* through one
entrypoint: `{{ include "platform.render" . }}`.

**The product outcome:** an app team describes intent in ~30 lines of values and
gets hardened (PSS-restricted), capability-negotiated, policy-consistent
manifests — workloads (Deployment/StatefulSet/DaemonSet/CronJob), networking
(Service/Ingress/Gateway API), TLS, monitors, PDB/HPA/NetworkPolicy, lifecycle
hook Jobs, plus an `extraObjects` escape hatch for the long tail. **The
platform-owner outcome:** one place to fix a class of bug for every consumer at
once — the 2026-07 correctness waves (selector scoping, annotation precedence,
hook ordering) each shipped as one library change instead of N app-chart fixes.

### Design invariants (violating any of these is a bug, not a style choice)

1. **Fail closed.** Invalid or ambiguous config fails at template time with a
   named error — never render a dangling/invalid object and let the API server
   or (worse) production discover it.
2. **Capability negotiation.** Never emit an apiVersion the cluster doesn't
   serve. CRD-backed Kinds gate on the `_capabilities.tpl` registry; skipped
   Kinds are warned in NOTES. `helm template` has no cluster: always pass the
   full `group/version/Kind` form to `--api-versions` — the bare `group/version`
   form silently skips objects.
3. **Specific beats common.** Resource-specific values/labels/annotations always
   win over `common*`/`global` on key collision. Sprig `merge` keeps the
   DESTINATION's keys — use the range+set idiom or `mergeOverwrite` with the
   specific map last.
4. **Goldens are the contract.** `tests/golden/*.yaml` are byte-exact rendered
   output. A golden diff you can't explain means your change is wrong; never
   regenerate to make red go green.
5. **Gates are guarded and mutation-tested.** Every lint-gate assertion uses the
   guarded `if out=$(...)` idiom (a bare `var=$(...)` under `set -e` aborts the
   whole gate silently), and every new check must be proven able to go RED by
   temporarily reverting the fix it guards.
6. **Hardening is default-on and per-container.** PSS-restricted is evaluated
   per container — one unhardened sidecar fails admission for the whole pod, so
   passthrough containers get the same hardening pass as the main container,
   with user-supplied keys winning via `mergeOverwrite`.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

## Beads tracker notes (project-specific)

- The issue prefix is `hf` (set in `.beads/config.yaml` `issue-prefix`); issues render as `hf-<hash>`.
- `.beads/issues.jsonl` is the git-tracked interchange artifact (25 seed issues filed 2026-07-06); the local Dolt DB under `.beads/embeddeddolt/` is NOT tracked.
- The Dolt remote (`refs/dolt/data`) has NOT yet been hydrated with these 25 seed issues, so despite the managed block above calling `.beads/issues.jsonl` a "passive export", the git-tracked JSONL is the seed of record until a maintainer imports it into the Dolt DB on a healthy checkout (e.g. `bd import` from the JSONL) and syncs. Until then do not run `bd sync` from a checkout whose Dolt data lacks the seed, as it could clobber or shadow the JSONL seed.
- Known pitfall in fresh worktrees: the local Dolt DB can exist without an `issue_prefix`, making every `bd create` fail with "database not initialized", while `bd init` refuses to reinit because `.beads/config.yaml` declares a `sync.remote`. Do NOT run `bd sync`/`bd bootstrap` to fix this from a disposable worktree. Working fallback: `bd init --prefix hf` in a scratch directory outside the repo, file issues there, then `bd export -o <repo>/.beads/issues.jsonl`.

See [AGENTS.md](AGENTS.md) for the same notes alongside the full agent instructions.

## Build & Test

Toolchain: Helm 4.x, `kubeconform`, `check-jsonschema`, `shellcheck` (all via
homebrew/pipx). K8s schema versions are vendored under `tests/schemas/`
(`scripts/vendor-schemas.sh`); the supported version matrix comes from
`scripts/lib/schema-manifest.sh`.

```bash
# THE gate — must end "==> PASS" (exit 0). This is the definition of done.
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh

# Fast local loop (~14s vs ~4min): subset run, ends "==> PASS (subset)",
# SKIPS the guardrail suite — never sufficient to claim work is done.
FIXTURES=minimal scripts/lint-library.sh

shellcheck -x scripts/*.sh tests/render.sh   # CI uses -x (follows sourced files)
helm lint platform-library/
tests/render.sh <fixture> [--set k=v ...]    # render one fixture the gate's way
UPDATE_GOLDEN=1 scripts/lint-library.sh      # accept INTENTIONAL render changes only
scripts/new-app-chart.sh <name>              # scaffold a new consumer chart
```

CI (`.github/workflows/ci.yaml`) runs shellcheck, `helm lint`, a metaschema
check on `values.schema.reference.json`, and the strict gate on every PR; the
`main-pr-only` ruleset makes that check required. Releases: tag `vX.Y.Z` (must
equal `platform-library/Chart.yaml` version, CHANGELOG must have a matching
`## [X.Y.Z]` section) → `release.yaml` re-runs the gates → publishes to GHCR.
Gates run AFTER the tag exists — a bad tag needs manual deletion before retry.

## Architecture Overview

Render pipeline: consumer values → `import-values: [defaults]` merge →
`platform.render` → `_app.yaml` dispatches per Kind → capability gate
(`platform.capabilities.gatedKinds` registry / `gateOpen`; skipped Kinds warned
in NOTES) → generator template (`_*.yaml`) → shared helpers in `_helpers.tpl` /
`_util.tpl` (naming, labels, image resolution, `hardenContainers`) → object.

The verification stack mirrors it: `tests/fixtures/{minimal,full,stateful,daemon}`
are curated consumer charts; `tests/render.sh` renders them exactly as the gate
does; `tests/golden/*.yaml` freeze the output; `scripts/lint-library.sh` layers
30+ guardrail sections (render matrix across the K8s versions, kubeconform
against vendored schemas, negative renders, precedence/posture/hook-ordering
assertions) on top.

One load-bearing subtlety: pre-install hook Jobs depend on a script ConfigMap
and a **distinctly named** hook ServiceAccount (`<fullname>-preinstall`),
weight-ordered below the Job. The distinct name is not cosmetic — a same-named
hook copy of the release SA would let `before-hook-creation` delete the LIVE SA
on every upgrade, invalidating running pods' tokens.

Deep dive + diagrams: `docs/specs/platform-library-v2-architecture.md`
(refresh tracked in bead `helm-factory-jdx`).

## Conventions & Patterns

- Conventional Commits; every completion states the verification command
  actually run and its result. "Should pass" is not a result.
- Template edits follow the `template-house-style` skill. Non-negotiables:
  range+set for map precedence (never bare sprig `merge`), quoted
  annotation/label values, fail-closed guards over silent fallbacks.
- Any consumer-facing values key change goes through the
  `values-contract-change` skill and updates `values.schema.reference.json`.
  New keys are features (minor bump), not patches.
- New lint-gate checks: guarded idiom + mutation test, always (invariant 5).
- Every consumer-visible change gets a `CHANGELOG.md` `[Unreleased]` entry —
  the release gate greps for the version header at tag time.
- Security defaults are invariants; read `security-posture-invariants` before
  touching hardening, tokens, or escape hatches. Escape hatches
  (`allowClusterScopedExtras`, `allowAllPrincipals`) stay opt-in and warned.

## Operating rule

Before starting work, inspect relevant project skills in `.claude/skills/`.
- Use `validate-factory` for any library/fixture/script change, or to decide whether work is done
- Use `add-library-kind` when adding a resource type/feature block to the library
- Use `author-consumer-chart` when creating or modifying a chart that consumes `platform`
- Use `debug-render-failure` when a render fails or an object is missing from output
- Use `capability-gates` when touching `_capabilities.tpl` or apiVersion negotiation
- Use `template-house-style` when editing any `_*.yaml`/`_*.tpl` template
- Use `values-contract-change` for consumer-facing values or schema changes
- Use `security-posture-invariants` for anything touching hardening or guardrails
- Use `extra-objects-runbook` when a consumer needs a Kind the library doesn't model
- Use `k8s-version-bump` for K8s range changes or apiVersion deprecations
- Use `release-platform-library` when cutting or publishing a release

Do not load unrelated skills. Do not rewrite large files unless the task requires it.
Every completion must include the verification command actually run.
For complex work, read `.claude/operating/fable-to-opus.md` first. For simple work, do not load it.

## Delivery rule: PR-only main

Every change to `main` — code, docs, CHANGELOG, anything — goes through a pull
request with the `ci` workflow green. Never push directly to `main`. Squash-merge
only (linear history). If CI fails on infra flake (e.g. a tool download reset),
re-run the job rather than bypassing it.

Stacked-PR gotcha: merging a parent PR with `--delete-branch` auto-CLOSES any
child PR based on that branch, and closed PRs cannot be retargeted or reopened
once the base ref is gone. Retarget children to `main` (`gh pr edit N --base main`)
BEFORE merging/deleting their base, then rebase them onto `main`
(`git rebase --onto origin/main <last-parent-commit> <child-branch>`) and
force-push with `--force-with-lease`.
