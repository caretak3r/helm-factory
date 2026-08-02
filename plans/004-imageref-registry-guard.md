# Plan 004 — imageRef: stop double-prefixing the registry (both call paths)

Planned at: 583b401

## Executor instructions

Read this plan top to bottom before touching anything. Every excerpt was read
from the repo at commit `583b401` and is quoted verbatim. Drift check first:

```bash
git diff --stat 583b401..HEAD -- \
  platform-library/templates/_helpers.tpl \
  scripts/lint-library.sh \
  CHANGELOG.md
```

If non-empty, re-anchor by CONTENT, not line number; if an excerpt is gone,
STOP and report.

Sequencing: plan 002 also edits `_helpers.tpl` (the `renderHookJob` work guard,
~lines 750-761). Different hunks, but execute the two plans sequentially — not
in parallel worktrees — to avoid a needless conflict.

**Correction to the survey finding (read before implementing):** finding #12
says the main `imageRef` path "lacks the hasPrefix guard that hook path :738
has". The hook path's guard exists but is INEFFECTIVE — its `hasPrefix`
arguments are inverted (see evidence below), so it only suppresses the prefix
in the degenerate case where the repository string itself starts with the
registry-name-plus-slash as a *prefix of the registry* comparison — in
practice, almost never. **Both** sites must be fixed; fixing only the main path
per the finding's literal wording would leave the hook path still
double-prefixing.

## Status

| Field | Value |
|---|---|
| Priority | P2 |
| Effort | S |
| Risk | LOW |
| Depends on | none (sequencing note re plan 002 above) |
| Category | correctness |
| Planned at | 583b401 |
| Finding | .uplift/survey-findings.md #12 (scope corrected: BOTH paths broken) |

## Why this matters

A consumer whose `image.repository` already carries a registry host (the common
"fully qualified repository" style, e.g. `docker.io/library/busybox` or a value
copied from another chart) gets the registry prepended AGAIN, producing
`docker.io/docker.io/library/busybox:1.36` — a pull failure discovered at
deploy time, not render time. The library default `image.registry: docker.io`
means every consumer is one qualified repository string away from this. Both
the main workload path and the hook Job path are affected.

## Current state (verbatim excerpts @ 583b401)

**Main path** — `platform-library/templates/_helpers.tpl:94-105`
(`platform.imageRef`, used by the main container, CronJob, and dict-form
sidecar/init images via `platform.hardenContainers`):

```
{{- define "platform.imageRef" -}}
{{- $img := .image -}}
{{- $path := .path -}}
{{- $repository := trimPrefix "/" ($img.repository | default "") -}}
{{- if not $repository }}
{{- fail (printf "platform-library: %s.repository is empty. Set it to the image repository (e.g. \"org/app\")." $path) }}
{{- end }}
{{- $global := .ctx.Values.global.imageRegistry | default "" -}}
{{- $registry := ternary $global ($img.registry | default "") (ne $global "") -}}
{{- if $registry }}
  {{- $repository = printf "%s/%s" $registry $repository -}}
{{- end }}
```

The prepend at 103-105 is UNCONDITIONAL whenever a registry resolves — no
prefix check at all.

**Hook path** — `_helpers.tpl:738-740` (inside `platform.renderHookJob`):

```
{{- if and $registry $imageCfg.repository (not (hasPrefix $imageCfg.repository (printf "%s/" $registry))) }}
  {{- $_ := set $imageCfg "repository" (printf "%s/%s" $registry (trimPrefix "/" $imageCfg.repository)) -}}
{{- end }}
```

**Evidence the hook guard is inverted.** Sprig's `hasPrefix` takes the PREFIX
as the FIRST argument: `hasPrefix PREFIX STRING`. Verified empirically during
planning with a throwaway chart (`helm template` on a one-template chart, Helm
4.x):

```
hasPrefix "ghcr.io/" "ghcr.io/org/app"  → true    (prefix first: correct form)
hasPrefix "ghcr.io/org/app" "ghcr.io/"  → false   (the form at line 738)
```

So at line 738 the guard asks "does `<registry>/` start with `<repository>`?"
— false for any real repository longer than the registry string — and the
prepend runs anyway. Reproduction of the double prefix (hook path, at HEAD):
`jobs.image.repository=docker.io/library/busybox` with the library default
`image.registry: docker.io` resolves to
`docker.io/docker.io/library/busybox:<tag>`.

**Interaction map** (why nothing else changes):
- `platform.hardenContainers` resolves dict-form container images through
  `platform.imageRef`, so sidecars/initContainers inherit the main-path fix
  automatically. Plain-STRING container images (e.g.
  `image: docker.io/library/busybox:1.36.1`) bypass `imageRef` entirely by
  design and are already covered by a gate check asserting no rewrite
  (`lint-library.sh:428-432`).
- Existing gate checks stay green under the fixed guard because none of their
  repositories start with their resolved registry: `example/minimal` +
  `docker.io` (digest pin, line 398-404), `org/sidecar` +
  `mirror.example.internal` (passthrough, 415-427), `example/other` hook repo
  (406-412, fails on the pin before registry logic matters).
- Fixture repositories (`example/minimal`, `example/app`, ...) never start
  with `docker.io/`, so rendered refs are byte-identical → zero golden impact.

## Commands

| Command | Purpose |
|---|---|
| `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` | THE gate; must end `==> PASS` |
| `tests/render.sh minimal --set image.repository=docker.io/library/busybox --set image.tag=1.36` | main path: must render `image: docker.io/library/busybox:1.36`, never `docker.io/docker.io/...` |
| `tests/render.sh minimal --set jobs.preInstall.enabled=true --set jobs.preInstall.script='echo hi' --set jobs.image.repository=docker.io/library/busybox --set jobs.image.tag=1.36` | hook path: same assertion on the Job container |
| `shellcheck -x scripts/lint-library.sh` | after gate edits |

(`image.repository` has `minLength: 1` and no pattern in
`values.schema.reference.json`, and `jobs.*` is unmodeled with root
`additionalProperties: true` — all commands pass helm-side schema validation.)

## Suggested executor toolkit

Helm 4.x, kubeconform, check-jsonschema, shellcheck. No cluster. Skills:
`template-house-style`, `validate-factory`.

## Scope

**In scope**
- `_helpers.tpl` — the `imageRef` prepend guard and the `renderHookJob`
  argument order. Nothing else in either define.
- `scripts/lint-library.sh` — new checks.
- `CHANGELOG.md` — `[Unreleased]` entry.

**Out of scope (do NOT touch)**
- Plain-string container image passthrough (by-design verbatim).
- Registry stripping/normalization beyond the prefix guard (e.g. detecting a
  DIFFERENT registry already present in the repository — see Maintenance
  notes).
- The hook image inheritance logic (lines 708-737) and plan 002's work guard.

## Git workflow

Branch off `main` (e.g. `fix/imageref-double-prefix`). One commit:
`fix(image): do not double-prefix the registry in imageRef and hook Job image resolution`.
PR to `main`, CI green, squash-merge. Never push directly to `main`.

## Steps

### Step 1 — guard the main path

In `platform.imageRef`, replace lines 103-105:

```
{{- if $registry }}
  {{- $repository = printf "%s/%s" $registry $repository -}}
{{- end }}
```

with (prefix FIRST — the correct sprig argument order):

```
{{- if and $registry (not (hasPrefix (printf "%s/" $registry) $repository)) }}
  {{- $repository = printf "%s/%s" $registry $repository -}}
{{- end }}
```

The compared prefix includes the trailing `/` so a repository like
`docker-io-mirror/app` is NOT mistaken for already carrying registry
`docker-io`.

### Step 2 — fix the hook-path argument order

Replace line 738:

```
{{- if and $registry $imageCfg.repository (not (hasPrefix $imageCfg.repository (printf "%s/" $registry))) }}
```

with:

```
{{- if and $registry $imageCfg.repository (not (hasPrefix (printf "%s/" $registry) $imageCfg.repository)) }}
```

(Only the two `hasPrefix` arguments swap; the surrounding line, including the
`trimPrefix` in the body below it, is untouched.)

**Verify:** both `tests/render.sh` commands from the Commands table; grep each
output for `docker.io/docker.io` — must be absent — and for
`image: docker.io/library/busybox:1.36` — must be present (in the second
command, on the hook Job's container).

### Step 3 — gate assertions (guarded idiom, invariant 5)

In `scripts/lint-library.sh`, insert a new section AFTER the final passthrough
check (the block at lines 447-455 ending
`  FAIL: repository-less dict sidecar image failed without the expected message"; ...`
and its `fi`) and BEFORE
`echo "==> schema enforcement (helm-side): invalid values must fail"` (line 457):

```bash
echo "==> image registry double-prefix guard"
# A repository that already carries the registry host must not get it again.
if out=$("$RENDER" minimal --set image.repository=docker.io/library/busybox \
  --set image.tag=1.36 2>&1); then
  if grep -q "image: docker.io/library/busybox:1.36" <<<"$out" &&
     ! grep -q "docker.io/docker.io" <<<"$out"; then
    echo "  OK: qualified main repository is not double-prefixed"
  else
    echo "  FAIL: main image path double-prefixed the registry"; grep "image:" <<<"$out" | head -3; fail=1
  fi
else
  echo "  FAIL: render failed for main double-prefix check"; echo "$out" | tail -3; fail=1
fi

# Same for the hook Job image resolution path.
if out=$("$RENDER" minimal --set jobs.preInstall.enabled=true \
  --set jobs.preInstall.script='echo hi' \
  --set jobs.image.repository=docker.io/library/busybox --set jobs.image.tag=1.36 2>&1); then
  if grep -q "image: docker.io/library/busybox:1.36" <<<"$out" &&
     ! grep -q "docker.io/docker.io" <<<"$out"; then
    echo "  OK: qualified hook Job repository is not double-prefixed"
  else
    echo "  FAIL: hook Job image path double-prefixed the registry"; grep "image:" <<<"$out" | head -3; fail=1
  fi
else
  echo "  FAIL: render failed for hook double-prefix check"; echo "$out" | tail -3; fail=1
fi

# The guard must not suppress LEGITIMATE prefixing: an unqualified repository
# still gets the registry.
if out=$("$RENDER" minimal 2>&1); then
  if grep -q "image: docker.io/example/minimal:1.0.0" <<<"$out"; then
    echo "  OK: unqualified repository still receives the registry prefix"
  else
    echo "  FAIL: unqualified repository lost its registry prefix"; grep "image:" <<<"$out" | head -3; fail=1
  fi
else
  echo "  FAIL: render failed for baseline prefix check"; echo "$out" | tail -3; fail=1
fi
```

(The hook check uses the script path so the render is otherwise valid; plan
002, if merged first, does not interact — a script is defined. Baseline values
for check 3 come from the minimal fixture: `example/minimal` + tag `1.0.0` +
library-default registry `docker.io`, already asserted in the digest test at
line 400.)

**Verify:** `shellcheck -x scripts/lint-library.sh` clean, then the full gate.

### Step 4 — mutation tests (prove RED)

One at a time, full gate each, restore between:

1. Revert Step 1 (restore the unconditional `{{- if $registry }}`) → check 1
   must go RED. (Checks 1 and 2 are ALSO red at unmodified HEAD — you can
   demonstrate this before Step 1 as a bonus baseline, since the checks
   double as the bug's reproduction.)
2. Revert Step 2 (restore the inverted argument order) → check 2 must go RED.
3. In Step 1's guard, drop the `printf "%s/"` and compare against bare
   `$registry` → check 3 must stay green but this mutation is NOT acceptable
   to ship; instead prove the trailing-slash matters by temporarily setting
   check 1's repository to `docker.io-mirror/app` expecting a
   `docker.io/docker.io-mirror/app:...` image — optional, do not commit that
   probe. (If this feels fussy, at minimum keep mutations 1-2.)

Record RED runs in the PR description.

### Step 5 — CHANGELOG

Under `## [Unreleased]` in `CHANGELOG.md`:

```markdown
### Fixed — image resolution

- `platform.imageRef` no longer double-prefixes the registry when
  `image.repository` (or a dict-form sidecar/init/hook repository) already
  starts with the resolved registry host — e.g. `docker.io/library/busybox`
  with the default `image.registry: docker.io` now renders
  `docker.io/library/busybox:<tag>`, not `docker.io/docker.io/...`. The hook
  Job path had a prefix guard with inverted `hasPrefix` arguments; both paths
  now share the same (correct) semantics. Unqualified repositories are
  prefixed exactly as before.
```

## Golden-file impact

**Zero.** No fixture repository starts with its resolved registry host, so
every rendered image reference is byte-identical. Done criterion:
`git status tests/golden/` clean; golden comparison passes without
`UPDATE_GOLDEN`. Any golden diff means the guard changed an unqualified-repo
render — STOP, do not regenerate.

## Test plan / verification

1. `shellcheck -x scripts/*.sh tests/render.sh` — clean.
2. `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh`
   ends `==> PASS` (exit 0); paste the tail in the PR. Subset runs are not
   sufficient.
3. Mutations 1-2 demonstrated RED, restored, gate green.
4. Existing image checks stayed green untouched: unpinned fail (390-396),
   digest pin (398-404), hook foreign-repo pin fail (406-412), passthrough
   dict + plain-string sidecars (414-435), sidecar pin/repository fails
   (437-455).
5. `git status`: only `_helpers.tpl`, `lint-library.sh`, `CHANGELOG.md`
   modified.

Do not run the gate or `tests/render.sh` concurrently with sibling
agents/sessions (fixture-artifact race).

## STOP conditions

- Any golden diff.
- The passthrough or digest checks go RED — the guard is suppressing
  legitimate prefixing; your `hasPrefix` arguments are wrong-way-round (the
  exact bug being fixed — re-read the evidence block).
- You start normalizing/stripping registries beyond the prefix guard —
  contract change; escalate.
- A mutation does not turn its check RED.
- Drift check shows `imageRef` or line 738 changed since 583b401.

## Maintenance notes

- Known limitation (accepted, documented here deliberately): a repository
  qualified with a DIFFERENT registry (e.g. `ghcr.io/org/app` while
  `image.registry: docker.io`) still gets prefixed
  (`docker.io/ghcr.io/org/app`) — same as today. Detecting "any registry-like
  first segment" (contains `.` or `:`) is a behavior change with real
  ambiguity (`my.org.namespace/app`); if consumers hit it, that is a new plan
  with a values-contract discussion, not a tweak to this guard.
- If plan 002 merged first, expect its `renderHookJob` hunks nearby; rebase
  normally — no semantic interaction.
