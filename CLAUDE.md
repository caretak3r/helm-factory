# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

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

_Add your build and test commands here_

```bash
# Example:
# npm install
# npm test
```

## Architecture Overview

_Add a brief overview of your project architecture_

## Conventions & Patterns

_Add your project-specific conventions here_

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
