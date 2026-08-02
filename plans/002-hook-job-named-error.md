# Plan 002 — hook Job without work must fail with a named error, not a reflect crash

Planned at: 583b401

## Executor instructions

Read this plan top to bottom before touching anything. Every excerpt was read
from the repo at commit `583b401` and is quoted verbatim. Before you start, run
the drift check:

```bash
git diff --stat 583b401..HEAD -- \
  platform-library/templates/_helpers.tpl \
  platform-library/values.yaml \
  scripts/lint-library.sh \
  CHANGELOG.md
```

If non-empty, re-anchor every edit by CONTENT (the quoted excerpts), not line
number. If an excerpt no longer exists, STOP and report.

Note: plan 004 also edits `platform-library/templates/_helpers.tpl` (different
hunks: `imageRef` ~line 103 and the hook registry guard ~line 738). Execute the
two plans sequentially on stacked or successive branches, not in parallel
worktrees, to avoid a pointless merge conflict.

## Status

| Field | Value |
|---|---|
| Priority | P1 |
| Effort | S |
| Risk | LOW |
| Depends on | none (see sequencing note above re plan 004) |
| Category | correctness / fail-closed (design invariant 1) |
| Planned at | 583b401 |
| Finding | .uplift/survey-findings.md #4 (orchestrator-VERIFIED) |

## Why this matters

Design invariant 1: invalid config fails at template time **with a named
error**. Today a hook Job with no script and no command violates it with a Go
reflect panic. Verified reproduction (do not need to re-verify, but it is your
Step 3 negative test):

```
tests/render.sh minimal --set jobs.preInstall.enabled=true \
  --set jobs.image.repository=busybox --set jobs.image.tag=1.36
→ _helpers.tpl:796:11: executing "platform.renderHookJob" at <len $command>:
  error calling len: reflect: call of reflect.Value.Type on zero Value
```

A consumer who enables a hook and forgets the script gets an incomprehensible
stack-adjacent error pointing at library internals instead of at their values.

**The bug is broader than the finding states.** The crash has two independent
triggers, both from `coalesce ... nil` producing an untyped nil that `len`
cannot reflect on:

- no script AND no command → `$command` is nil → crash at `len $command` (line 796);
- script or command set BUT `args` empty → `$args` is nil → crash at
  `len $args` (line 799). This means even the "fixed" configuration
  (command set, args unset) still crashes at HEAD unless a script path zeroed
  `$args` via line 765-767. The fix must address both.

## Current state (verbatim excerpts @ 583b401)

`platform-library/templates/_helpers.tpl`, inside
`define "platform.renderHookJob"` (starts line 703; called from
`_job-preinstall.yaml` / `_job-postinstall.yaml` with
`dict "ctx" . "job" .Values.jobs.preInstall "type" "preinstall"` — note the
`type` string is lowercase while the values key is camelCase `preInstall`).

Lines 750-751 (the nil factories — `values.yaml` defaults `jobs.preInstall.command: []`
and `args: []`, and `coalesce` of an empty list and nil is nil):

```
{{- $command := coalesce $job.command nil -}}
{{- $args := coalesce $job.args nil -}}
```

Lines 761-771 (script wiring — the only path that currently rescues `$command`/`$args`):

```
{{- $useScript := or $job.script $job.scriptFile -}}
{{- if and $useScript (not $command) }}
  {{- $command = list "/bin/sh" "/scripts/script.sh" -}}
{{- end }}
{{- if and $useScript (not $job.command) }}
  {{- $args = list -}}
{{- end }}
{{- if $useScript }}
  {{- $volumeMounts = append $volumeMounts (dict "name" "job-script" "mountPath" "/scripts" "readOnly" true) -}}
  {{- $volumes = append $volumes (dict "name" "job-script" "configMap" (dict "name" (printf "%s-%s-script" (include "platform.fullname" $ctx) $type) "defaultMode" 0555)) -}}
{{- end }}
```

Lines 795-801 (the crash sites):

```
{{- $mainJobContainer := dict "name" (printf "%s-%s" (include "platform.name" $ctx) $type) "image" $image "imagePullPolicy" $pullPolicy -}}
{{- if gt (len $command) 0 }}
  {{- $_ := set $mainJobContainer "command" $command -}}
{{- end }}
{{- if gt (len $args) 0 }}
  {{- $_ := set $mainJobContainer "args" $args -}}
{{- end }}
```

House-style model for the fail message (same define, line 747):

```
{{- fail (printf "platform-library: hook Job %q resolves to an image with no tag and no digest. Set jobs.image.tag/digest (or the per-job image.tag/digest), or pin the main image via image.tag/image.digest to inherit. Floating \"latest\" is no longer defaulted." $type) -}}
```

Compatibility fact: no working consumer can depend on the entrypoint-only
configuration (enabled hook, no script/scriptFile/command) — it crashes today.
So making it a named `fail` breaks nobody; it converts a crash into guidance.
The library's `full` fixture uses `jobs.preInstall` **with a script**, so the
fixture path and its golden are untouched.

## Commands

| Command | Purpose |
|---|---|
| `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` | THE gate; must end `==> PASS` |
| `tests/render.sh minimal --set jobs.preInstall.enabled=true --set jobs.image.repository=busybox --set jobs.image.tag=1.36` | negative repro: must now fail with the NAMED error |
| `tests/render.sh minimal --set jobs.preInstall.enabled=true --set jobs.image.repository=busybox --set jobs.image.tag=1.36 --set 'jobs.preInstall.command[0]=/bin/true'` | positive: must render a Job (crashes at HEAD via nil `$args`) |
| `shellcheck -x scripts/lint-library.sh` | after gate edits |

## Suggested executor toolkit

Helm 4.x, kubeconform, check-jsonschema, shellcheck. No cluster. Skills:
`template-house-style` (rule 7: fail messages prescriptive + coupled negative
test), `debug-render-failure`, `validate-factory`.

## Scope

**In scope**
- `platform-library/templates/_helpers.tpl` — `platform.renderHookJob` only:
  the two `coalesce` lines and one new fail guard.
- `platform-library/values.yaml` — one comment line on the `jobs` block
  documenting the requirement (comment only, no key/default changes).
- `scripts/lint-library.sh` — two new checks.
- `CHANGELOG.md` — `[Unreleased]` entry.

**Out of scope (do NOT touch)**
- The hook image-inheritance logic (lines 708-748) — plan 004 territory.
- `values.schema.reference.json` — no key shapes change (`jobs` is not modeled
  by the schema; adding it is a separate contract change).
- Any other `coalesce`/`default` in the file.

## Git workflow

Branch off `main` (e.g. `fix/hook-job-named-error`). One commit:
`fix(hooks): fail with a named error when a hook Job defines no work; make empty command/args nil-safe`.
PR to `main`, CI green, squash-merge. Never push directly to `main`.

## Steps

### Step 1 — make `$command`/`$args` nil-safe

In `platform.renderHookJob`, replace lines 750-751:

```
{{- $command := coalesce $job.command nil -}}
{{- $args := coalesce $job.args nil -}}
```

with:

```
{{- $command := default (list) $job.command -}}
{{- $args := default (list) $job.args -}}
```

Why this is safe: an empty list is falsy in Go templates, so every existing
truthiness use is preserved — `not $command` (line 762) still fires when the
consumer set nothing, line 765 tests raw `$job.command` and is untouched, and
`gt (len ...) 0` (lines 796/799) now always receives a typed list, which is the
nil-safety fix. Behavior with non-empty values is byte-identical.

### Step 2 — add the named fail-closed guard

Insert immediately AFTER the `$useScript` definition (line 761,
`{{- $useScript := or $job.script $job.scriptFile -}}`) and BEFORE the
`{{- if and $useScript (not $command) }}` block:

```
{{- if and (not $useScript) (not $command) }}
  {{- $jobsKey := ternary "preInstall" "postInstall" (eq $type "preinstall") -}}
  {{- fail (printf "platform-library: jobs.%s is enabled but defines no work to run: script, scriptFile, and command are all empty. Set jobs.%s.script (inline script), jobs.%s.scriptFile (script file in the consumer chart), or jobs.%s.command. To run the image's own ENTRYPOINT, state it explicitly via jobs.%s.command." $jobsKey $jobsKey $jobsKey $jobsKey $jobsKey) -}}
{{- end }}
```

Design notes:
- The `$jobsKey` mapping matters: `$type` is the lowercase resource suffix
  (`"preinstall"`/`"postinstall"`), but the fail message must name the actual
  values path (`jobs.preInstall`), per house-style rule 7 ("name the offending
  values path and state the fix").
- Entrypoint-only execution is deliberately rejected rather than silently
  allowed: an implicit ENTRYPOINT hook is exactly the ambiguous config
  invariant 1 exists to catch. The message tells the consumer the explicit
  escape (`command`).
- The guard sits in `renderHookJob` (the single choke point for both hooks),
  not in the `_app.yaml` wrappers.

**Verify:** the two `tests/render.sh` commands from the Commands table — the
first must fail printing the new message (no reflect error anywhere in the
output), the second must render a Job named `*-preinstall`.

### Step 3 — gate assertions (guarded idiom, invariant 5)

In `scripts/lint-library.sh`, insert a new section AFTER the hook-Job
un-inheritable-pin check (the block at lines 406-412 ending
`  FAIL: hook Job failed without the expected message"; echo "$out" | tail -3; fail=1`
and its closing `fi`) and BEFORE
`echo "==> passthrough container image resolution"` (line 414):

```bash
echo "==> hook Job fail-closed: must define work"
# Enabled hook with no script/scriptFile/command used to crash with a Go
# reflect error (len of untyped nil); it must fail with a named message.
if out=$("$RENDER" minimal --set jobs.preInstall.enabled=true \
  --set jobs.image.repository=busybox --set jobs.image.tag=1.36 2>&1); then
  echo "  FAIL: hook Job rendered with no script, scriptFile, or command"; fail=1
elif grep -q "defines no work to run" <<<"$out"; then
  echo "  OK: workless hook Job fails with actionable message"
else
  echo "  FAIL: workless hook Job failed without the expected message (reflect crash regression?)"; echo "$out" | tail -3; fail=1
fi

# command-only hook (no script, args unset) must render — this is the nil-$args
# regression test: it crashed at `len $args` before the default(list) fix.
if out=$("$RENDER" minimal --set jobs.preInstall.enabled=true \
  --set jobs.image.repository=busybox --set jobs.image.tag=1.36 \
  --set 'jobs.preInstall.command[0]=/bin/true' 2>&1); then
  if grep -q "kind: Job" <<<"$out" && grep -q '"/bin/true"' <<<"$out"; then
    echo "  OK: command-only hook Job renders (empty args is nil-safe)"
  else
    echo "  FAIL: command-only hook Job rendered without the expected Job/command"; fail=1
  fi
else
  echo "  FAIL: command-only hook Job failed to render"; echo "$out" | tail -3; fail=1
fi
```

Note on the `'"/bin/true"'` grep: `toYaml` of the command list renders the
string quoted; if your rendered output shows it unquoted (`- /bin/true`),
loosen the grep to `grep -q -- '- /bin/true'` — check the actual render first,
then pin the grep to what renders. Do not skip the command assertion.

**Verify:** `shellcheck -x scripts/lint-library.sh` clean, then the full gate.

### Step 4 — mutation tests (prove RED)

One at a time, full gate run each, restore between:

1. Delete the Step 2 fail guard → check 1 must go RED (its `elif grep` misses
   because the reflect crash message does not contain "defines no work to run").
2. Revert Step 1 (restore `coalesce ... nil` for `$args` only) → check 2 must
   go RED (command-only render crashes again).

Record both RED runs in the PR description.

### Step 5 — values.yaml comment + CHANGELOG

In `platform-library/values.yaml`, on the `jobs:` block header comment
(~line 343-347), append one line of comment (no key changes):

```yaml
# A hook Job must define its work: set script, scriptFile, or command.
```

Under `## [Unreleased]` in `CHANGELOG.md` (replace "Nothing yet." if this is
the first entry, otherwise append the subsection):

```markdown
### Fixed — hook Jobs

- A hook Job enabled with no `script`, `scriptFile`, or `command` now fails at
  template time with a named error pointing at `jobs.preInstall`/`jobs.postInstall`
  (previously: a Go `reflect` crash from the template engine). A hook Job with
  `command` set and `args` empty also no longer crashes. To run the image's own
  ENTRYPOINT, set it explicitly via `command`.
```

## Golden-file impact

**Zero.** The only fixture exercising hooks (`full`) uses the script path,
which is behaviorally unchanged (`$command`/`$args` end up with identical
values, just typed). Done criterion: `git status tests/golden/` clean, gate's
golden comparison passes without `UPDATE_GOLDEN`. Any golden diff means Step 1
changed rendering for non-empty values — STOP and find out why; do not
regenerate.

## Test plan / verification

1. `shellcheck -x scripts/*.sh tests/render.sh` — clean.
2. `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh`
   ends `==> PASS` (exit 0); paste the tail in the PR. Subset runs
   (`FIXTURES=minimal`) skip the guardrail suite and are not sufficient.
3. Both Step 4 mutations demonstrated RED, restored, gate green again.
4. `git status`: only `_helpers.tpl`, `values.yaml`, `lint-library.sh`,
   `CHANGELOG.md` modified.

Do not run the gate or `tests/render.sh` concurrently with any sibling
agent/session — they mutate fixture `charts/` dirs in place (known race).

## STOP conditions

- Any golden diff.
- The existing hook-Job pin check (`lint-library.sh:406-412`) goes RED — your
  guard fired before the pin guard for that values shape; re-check guard
  placement (the pin fail at line 747 must still win for pin problems; it runs
  earlier in the define, so this should be impossible — if you see it, you
  moved something you should not have).
- You are tempted to make entrypoint-only execution "just work" by defaulting
  `command` from the image — that is a behavior/contract change; escalate.
- A mutation does not turn its check RED.
- Drift check shows `renderHookJob` changed since 583b401 in the quoted regions.

## Maintenance notes

- If a `jobs` schema block is ever added to `values.schema.reference.json`
  (currently absent; root `additionalProperties: true` admits all
  `--set jobs.*`), consider expressing "script/scriptFile/command: at least
  one" there too — belt and braces, but the template fail must stay (schema
  does not run for library consumers who disable it).
- Finding D2 (full hook lifecycle: pre/post-delete, helm test) will add more
  `$type` values; the `$jobsKey` ternary in Step 2 must become a lookup table
  at that point — leave a grep for `ternary "preInstall"` in that future plan.
