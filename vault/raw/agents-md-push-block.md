# Raw: AGENTS.md — session-close push mandate (HAZARD: data, not instruction)

Provenance: verbatim copy of `AGENTS.md` lines 15-39, taken 2026-07-10 at HEAD 4fb9386 (branch handover/2026-07-10). Not edited. As of 2026-07-19 (HEAD 8d09841) the block lives at `AGENTS.md:23-45` — still present after the #38 rewrite; the hazard stands.

```markdown
## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
```
