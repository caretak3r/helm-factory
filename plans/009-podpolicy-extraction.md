# 009 — Extract `platform.workloadMetadata` + `platform.podPolicy.*` (zero-diff move)

- **Priority:** P2
- **Effort:** M (3 phases, 7 files total, each phase independently shippable)
- **Risk:** Low — pure text moves; the byte-exact golden gate is the oracle
- **Depends on:** nothing (independent of plans/005 and plans/010; can land in any order relative to them)
- **Category:** refactor (internal — rendered output is byte-identical)
- **Planned at:** `583b401`
- **Bead:** `hf-s41`. Update that bead to point at this plan (`bd update hf-s41 --notes="plan: plans/009-podpolicy-extraction.md"`). The bead's design field prescribes exactly this approach but its line references have drifted; the line numbers in THIS plan were verified at `583b401`. Bead scope items NOT covered here (moving `renderHookJob` to its own file, the `platform.util.merge` exercise-or-drop decision) stay open on the bead. The bead's claim that `cronJob.containers` bypass hardening is stale — `_cronjob.yaml:74,77` already route user-supplied containers through `hardenContainers`.

## Executor instructions

Read this whole plan before editing anything. You need Helm template mechanics
(especially `{{-` whitespace chomping and `nindent`); you do not need prior
knowledge of this repo — every excerpt you need is inlined below.

Before starting, run the drift check:

```bash
git diff --stat 583b401..HEAD -- \
  platform-library/templates/_helpers.tpl \
  platform-library/templates/_deployment.yaml \
  platform-library/templates/_statefulset.yaml \
  platform-library/templates/_daemonset.yaml \
  platform-library/templates/_cronjob.yaml \
  scripts/lint-library.sh
```

If any of these files changed since `583b401`, re-read the touched file and
re-verify the excerpts below against current content before editing. If an
excerpt no longer matches byte-for-byte, adjust the moved text to the CURRENT
bytes — the invariant is "move current text verbatim", not "restore the text
this plan quotes".

Also read the repo skills before editing: `template-house-style` (any `_*.yaml`
/ `_*.tpl` edit), `security-posture-invariants` (this touches token mounting
and pod security context), `validate-factory` (definition of done).

## Why this matters

Pod-level policy — service-account token mounting, service links, pod
`securityContext`, image-pull-secret precedence — is written out three times:

1. the shared main-workload path `platform.podTemplateSpec` (`platform-library/templates/_helpers.tpl:255-448`),
2. the CronJob generator (`platform-library/templates/_cronjob.yaml:50-98`),
3. the hook-Job renderer `platform.renderHookJob` (`platform-library/templates/_helpers.tpl:703-869`).

Workload top-level metadata (labels/annotations precedence) is written out
three more times, byte-identically, in `_deployment.yaml`, `_statefulset.yaml`,
`_daemonset.yaml` (lines 7-23 of each).

A policy change today is a synchronized 3-way (or 6-way) edit; the 2026-07
correctness waves showed what that costs. This plan collapses each policy to
one definition by MOVING template text into named helpers, with **zero golden
diffs** as the acceptance bar (design invariant 4). Any behavior alignment
discovered along the way is a follow-up, never smuggled into this change.

## Current state (verified at `583b401`)

### The three pod-spec sites emit shared fields in DIFFERENT orders

This is the load-bearing discovery: a single monolithic "podPolicy" helper is
IMPOSSIBLE at zero golden diffs, because YAML field order equals literal
template order and the three sites disagree:

| Site | Field order |
|---|---|
| `podTemplateSpec` (`_helpers.tpl:287-307`) | serviceAccountName → automount → enableServiceLinks → **imagePullSecrets** → **securityContext** |
| CronJob (`_cronjob.yaml:51-72`) | serviceAccountName → automount → enableServiceLinks → restartPolicy → **securityContext** → **imagePullSecrets** |
| hook Job (`_helpers.tpl:840-861`) | restartPolicy → serviceAccountName(hook) → automount → enableServiceLinks → **securityContext** → **imagePullSecrets** |

So the extraction is a FAMILY of composable sub-helpers, called at each site in
that site's current order.

`serviceAccountName` stays at the call sites on purpose: hook Jobs use the
distinctly named hook ServiceAccount (`platform.hookServiceAccountName`,
`_helpers.tpl:841`) — a same-named copy of the release SA would let
`before-hook-creation` delete the LIVE SA on every upgrade. Never unify SA
selection. `restartPolicy` also stays local (differs per site).

### Site 1 — `platform.podTemplateSpec`, `_helpers.tpl:287-307`

```
spec:
  serviceAccountName: {{ include "platform.serviceAccountName" $ctx }}
  automountServiceAccountToken: {{ $ctx.Values.serviceAccount.automountServiceAccountToken | default false }}
  enableServiceLinks: {{ $ctx.Values.enableServiceLinks | default false }}
  {{- $pullSecrets := list -}}
  {{- range $ctx.Values.global.imagePullSecrets }}
    {{- $pullSecrets = append $pullSecrets . -}}
  {{- end }}
  {{- range $ctx.Values.image.pullSecrets }}
    {{- $pullSecrets = append $pullSecrets . -}}
  {{- end }}
  {{- /* uniq keeps the first occurrence: global entries stay ahead of image ones */ -}}
  {{- $pullSecrets = $pullSecrets | uniq -}}
  {{- if gt (len $pullSecrets) 0 }}
  imagePullSecrets:
    {{- range $name := $pullSecrets }}
    - name: {{ $name }}
    {{- end }}
  {{- end }}
  {{- if $ctx.Values.podSecurityContext.enabled }}
  securityContext: {{- omit $ctx.Values.podSecurityContext "enabled" | toYaml | nindent 4 }}
  {{- end }}
```

Successor construct: `{{- if and $ctx.Values.initContainers.enabled ...` (line 308) — starts with `{{-`, so an empty include before it contributes zero bytes.

### Site 2 — CronJob, `_cronjob.yaml:50-72`

```
        spec:
          serviceAccountName: {{ include "platform.serviceAccountName" . }}
          automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken | default false }}
          enableServiceLinks: {{ .Values.enableServiceLinks | default false }}
          restartPolicy: OnFailure
          {{- if .Values.podSecurityContext.enabled }}
          securityContext: {{- omit .Values.podSecurityContext "enabled" | toYaml | nindent 12 }}
          {{- end }}
          {{- $pullSecrets := list -}}
          {{- range .Values.global.imagePullSecrets }}
            {{- $pullSecrets = append $pullSecrets . -}}
          {{- end }}
          {{- range .Values.image.pullSecrets }}
            {{- $pullSecrets = append $pullSecrets . -}}
          {{- end }}
          {{- /* uniq keeps the first occurrence: global entries stay ahead of image ones */ -}}
          {{- $pullSecrets = $pullSecrets | uniq -}}
          {{- if gt (len $pullSecrets) 0 }}
          imagePullSecrets:
            {{- range $pullSecrets }}
            - name: {{ . }}
            {{- end }}
          {{- end }}
```

Successor: `{{- if .Values.cronJob.initContainers }}` (line 73) — empty-safe.

### Site 3 — hook Job, `_helpers.tpl:840-861`

```
    spec:
      restartPolicy: {{ $restartPolicy }}
      serviceAccountName: {{ include "platform.hookServiceAccountName" (list $ctx $type) }}
      automountServiceAccountToken: {{ $ctx.Values.serviceAccount.automountServiceAccountToken | default false }}
      enableServiceLinks: {{ $ctx.Values.enableServiceLinks | default false }}
      {{- if $ctx.Values.podSecurityContext.enabled }}
      securityContext: {{- omit $ctx.Values.podSecurityContext "enabled" | toYaml | nindent 8 }}
      {{- end }}
      {{- $hookPullSecrets := list -}}
      {{- range $ctx.Values.global.imagePullSecrets }}
        {{- $hookPullSecrets = append $hookPullSecrets . -}}
      {{- end }}
      {{- range $ctx.Values.image.pullSecrets }}
        {{- $hookPullSecrets = append $hookPullSecrets . -}}
      {{- end }}
      {{- /* uniq keeps the first occurrence: global entries stay ahead of image ones */ -}}
      {{- $hookPullSecrets = $hookPullSecrets | uniq -}}
      {{- if gt (len $hookPullSecrets) 0 }}
      imagePullSecrets:
        {{- range $hookPullSecrets }}
        - name: {{ . }}
        {{- end }}
      {{- end }}
```

Successor: `{{- if gt (len $initContainers) 0 }}` (line 862) — empty-safe.

Indentation summary (field column / list-item-or-key column):
podTemplateSpec 2/4, CronJob 10/12, hook Job 6/8.

### The metadata block — byte-identical in three generators

`_deployment.yaml:7-23`, `_statefulset.yaml:7-23`, `_daemonset.yaml:7-23` are
the same bytes:

```
  labels:
    {{- include "platform.labels" . | nindent 4 }}
    {{- range $k, $v := .Values.commonLabels }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
    {{- range $k, $v := .Values.labels }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
  {{- if or .Values.commonAnnotations .Values.annotations }}
  annotations:
    {{- range $k, $v := .Values.commonAnnotations }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
    {{- range $k, $v := .Values.annotations }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
  {{- end }}
```

Emission order carries invariant 3 (specific beats common): `commonLabels`
then `labels`, `commonAnnotations` then `annotations` — later duplicate YAML
keys win on the API server, so specific-last is the precedence mechanism. Do
not "clean this up" into a merge.

CronJob metadata (`_cronjob.yaml` top) is intentionally DIFFERENT (uses
`labelsFor` with a component, no `.Values.labels`, no `commonAnnotations`) —
that inconsistency is survey finding #13 and is OUT of scope here.

## Commands

| Command | Purpose |
|---|---|
| `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` | THE gate; must end `==> PASS`. Definition of done for every phase. ~4 min. Never run two instances concurrently (fixture-artifact race). |
| `FIXTURES=minimal scripts/lint-library.sh` | fast inner loop (~14s); ends `==> PASS (subset)`; never sufficient to claim done |
| `tests/render.sh <fixture>` | render one fixture exactly as the gate does |
| `git diff --stat tests/golden/` | must ALWAYS be empty in this plan (never run `UPDATE_GOLDEN=1`) |
| `helm lint platform-library/` | quick syntax sanity |
| `shellcheck -x scripts/lint-library.sh` | required after the Phase 3 gate edit |

## Scope

**In scope**
- New helpers in `_helpers.tpl`: `platform.workloadMetadata`,
  `platform.podPolicy.identity`, `platform.podPolicy.securityContext`,
  `platform.podPolicy.imagePullSecrets` — bodies are verbatim moves.
- Call-site replacement in `_deployment.yaml`, `_statefulset.yaml`,
  `_daemonset.yaml`, `_cronjob.yaml`, and the two `_helpers.tpl` sites.
- One new lint-gate section asserting single-source (Phase 3), guarded idiom +
  mutation-proven RED.

**Out of scope — smuggling temptations, refuse all of them**
- Unifying `serviceAccountName` selection (live-SA-deletion hazard, see above).
- Routing the CronJob default container (`_cronjob.yaml:79-88`) through
  `hardenContainers` — changes byte layout (`toYaml` key sorting) and posture;
  follow-up bead.
- Aligning CronJob/hook metadata or adding `commonLabels` to the 6 generators
  missing it (finding #13) — a rendered-output change; follow-up enabled by
  this extraction.
- Adding scheduling fields (affinity/topologySpread/priorityClassName) to
  CronJob/hook pods — behavior change; follow-up.
- Moving `renderHookJob` into `_hook-job.tpl` (bead hf-s41 item) — file
  reorganization noise; separate change.
- Fixing the `| default false` truthiness quirk or any other behavior found
  while moving text — record it, don't fix it here.
- `UPDATE_GOLDEN=1` for any reason.

## Git workflow

Branch `refactor/009-podpolicy-extraction` off current `main`. One commit per
phase (Conventional Commits, e.g.
`refactor(library): extract platform.workloadMetadata helper (hf-s41)`), PR to
`main`, squash-merge, `ci` workflow green. Never push directly to `main`. No
`Claude-Session:`/AI attribution trailers in commits.

## Steps

### Phase 1 — `platform.workloadMetadata` (4 files)

Files: `_helpers.tpl`, `_deployment.yaml`, `_statefulset.yaml`, `_daemonset.yaml`.

1. In `platform-library/templates/_helpers.tpl`, after the
   `platform.selectorLabelsFor` define (ends near line 88), add:

   ```
   {{/*
   platform.workloadMetadata — shared top-level metadata labels/annotations for
   the three primary workload generators (Deployment/StatefulSet/DaemonSet).
   Verbatim move of the block each generator previously inlined; emission order
   carries the specific-beats-common precedence. No right-trim on the define:
   the body starts with a newline so the call site reproduces the original
   bytes exactly. CronJob metadata is intentionally NOT unified here.
   Usage (immediately after the namespace: line):
     {{- include "platform.workloadMetadata" . }}
   */}}
   {{- define "platform.workloadMetadata" }}
     labels:
       <BODY>
   {{- end }}
   ```

   where `<BODY>` is the verbatim moved block quoted in "Current state" (from
   `  labels:` through the final `  {{- end }}`), at its ORIGINAL indentation
   (2 spaces for `labels:`). Copy it from `_deployment.yaml:7-23`, not from
   this plan. Critical details:
   - `{{- define "platform.workloadMetadata" }}` — left-trim only. A `-}}`
     right-trim would eat the body's leading newline and corrupt the bytes.
   - `{{- end }}` closing the define — left-trim eats the newline after the
     body's last line, so the rendered body has no trailing newline.

2. In each of `_deployment.yaml`, `_statefulset.yaml`, `_daemonset.yaml`,
   delete lines 7-23 (the block you just moved) and insert one line in their
   place, so the file head reads:

   ```
   metadata:
     name: {{ include "platform.fullname" . }}
     namespace: {{ .Release.Namespace }}
     {{- include "platform.workloadMetadata" . }}
   spec:
   ```

   Why this is byte-exact: the include's `{{-` chomps the `\n  ` before it;
   the helper body re-emits `\n  labels:...` — the same bytes the file
   contained; the literal `\nspec:` after the include line is unchanged.

3. Verify:

   ```bash
   REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh
   git diff --stat tests/golden/
   ```

   Gate must end `==> PASS` with `OK: matches golden` for all four fixtures;
   the golden diff must be empty. Commit Phase 1.

### Phase 2 — `platform.podPolicy.*` sub-helpers (2 files)

Files: `_helpers.tpl`, `_cronjob.yaml`.

1. Add three helpers to `_helpers.tpl` (near `platform.hardenContainers`,
   which ends around line 179). Exact text:

   ```
   {{/*
   platform.podPolicy.identity — pod-level SA-token and service-link policy
   shared by every pod-bearing generator. serviceAccountName intentionally
   stays at each call site: hook Jobs use the distinct hook ServiceAccount
   (platform.hookServiceAccountName) and must never share the release SA name.
   Never empty, so call sites pipe through nindent.
   Usage: {{- include "platform.podPolicy.identity" $ctx | nindent 2 }}
   */}}
   {{- define "platform.podPolicy.identity" -}}
   automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken | default false }}
   enableServiceLinks: {{ .Values.enableServiceLinks | default false }}
   {{- end -}}

   {{/*
   platform.podPolicy.securityContext — pod securityContext from
   .Values.podSecurityContext (minus the enabled flag). Emits NOTHING when
   disabled. Because of that, call sites must NOT pipe through nindent (an
   empty string through nindent leaves a whitespace-only line); the field
   indentation is passed as the second list element instead, and keys render
   two columns deeper.
   Usage: {{- include "platform.podPolicy.securityContext" (list $ctx 2) }}
   */}}
   {{- define "platform.podPolicy.securityContext" -}}
   {{- $ctx := index . 0 -}}
   {{- $indent := index . 1 -}}
   {{- if $ctx.Values.podSecurityContext.enabled -}}
   {{- printf "securityContext:" | nindent $indent -}}
   {{- omit $ctx.Values.podSecurityContext "enabled" | toYaml | nindent (add $indent 2 | int) -}}
   {{- end -}}
   {{- end -}}

   {{/*
   platform.podPolicy.imagePullSecrets — merged pull secrets:
   global.imagePullSecrets first, then image.pullSecrets, uniq keeping the
   first occurrence so global entries stay ahead of image ones. Emits NOTHING
   when the merged list is empty — same call convention as
   podPolicy.securityContext (indent argument, no nindent at the call site).
   Usage: {{- include "platform.podPolicy.imagePullSecrets" (list $ctx 2) }}
   */}}
   {{- define "platform.podPolicy.imagePullSecrets" -}}
   {{- $ctx := index . 0 -}}
   {{- $indent := index . 1 -}}
   {{- $pullSecrets := list -}}
   {{- range $ctx.Values.global.imagePullSecrets -}}
   {{- $pullSecrets = append $pullSecrets . -}}
   {{- end -}}
   {{- range $ctx.Values.image.pullSecrets -}}
   {{- $pullSecrets = append $pullSecrets . -}}
   {{- end -}}
   {{- /* uniq keeps the first occurrence: global entries stay ahead of image ones */ -}}
   {{- $pullSecrets = $pullSecrets | uniq -}}
   {{- if gt (len $pullSecrets) 0 -}}
   {{- printf "imagePullSecrets:" | nindent $indent -}}
   {{- range $pullSecrets -}}
   {{- printf "- name: %v" . | nindent (add $indent 2 | int) -}}
   {{- end -}}
   {{- end -}}
   {{- end -}}
   ```

   Notes for the executor:
   - `printf "- name: %v"` mirrors `{{ . }}`'s `%v` formatting exactly.
   - The `| int` cast in `nindent (add $indent 2 | int)` is REQUIRED: sprig's
     `add` returns int64, `nindent`'s count parameter is int, and text/template
     does NOT convert between them — the uncast form fails at render time with
     "wrong type for value; expected int; got int64" (verified on Helm 4).
   - `omit ... | toYaml | nindent (add $indent 2 | int)` is the same function
     chain as the originals (`nindent 4`/`12`/`8`), so key sorting and quoting
     are byte-identical.

2. Replace the three call sites, preserving each site's field ORDER:

   **`_helpers.tpl` `podTemplateSpec`** — replace lines 288-307 (automount
   through the securityContext `{{- end }}`) with:

   ```
     {{- include "platform.podPolicy.identity" $ctx | nindent 2 }}
     {{- include "platform.podPolicy.imagePullSecrets" (list $ctx 2) }}
     {{- include "platform.podPolicy.securityContext" (list $ctx 2) }}
   ```

   (`serviceAccountName` line 287 stays; order here is pullSecrets THEN
   securityContext — this site's original order.)

   **`_cronjob.yaml`** — replace lines 52-53 (automount/enableServiceLinks)
   with `          {{- include "platform.podPolicy.identity" . | nindent 10 }}`;
   keep `restartPolicy: OnFailure`; replace lines 55-57 (securityContext
   block) with `          {{- include "platform.podPolicy.securityContext" (list . 10) }}`;
   replace lines 58-72 (pull-secrets block) with
   `          {{- include "platform.podPolicy.imagePullSecrets" (list . 10) }}`.
   Order: identity → restartPolicy → securityContext → imagePullSecrets.

   **`_helpers.tpl` `renderHookJob`** — replace lines 842-843 with
   `      {{- include "platform.podPolicy.identity" $ctx | nindent 6 }}`;
   replace lines 844-846 with
   `      {{- include "platform.podPolicy.securityContext" (list $ctx 6) }}`;
   replace lines 847-861 with
   `      {{- include "platform.podPolicy.imagePullSecrets" (list $ctx 6) }}`.
   (`restartPolicy` and the hook `serviceAccountName` lines stay untouched.)

   Empty-include safety was verified at all three sites: every successor
   construct starts with `{{-`, so a helper that emits nothing contributes
   zero bytes.

3. Verify exactly as Phase 1 (full gate `==> PASS`, empty
   `git diff --stat tests/golden/`). Exercise the conditional branches
   explicitly before committing:

   ```bash
   tests/render.sh minimal --set 'global.imagePullSecrets[0]=regcred' \
     --set 'image.pullSecrets[0]=regcred' --set 'image.pullSecrets[1]=extra' \
     | grep -A3 imagePullSecrets:
   ```

   Expect one `- name: regcred` then `- name: extra` (uniq, global-first) in
   every pod spec. Commit Phase 2.

### Phase 3 — lint-gate single-source check (1 file)

File: `scripts/lint-library.sh`. Insert a new section after the capability
anti-drift block (after line ~824, before `==> selector stability`):

```bash
echo "==> pod policy single source: extracted helpers have no re-inlined copies"
# 009 moved pull-secret precedence, pod securityContext, the automount/
# enableServiceLinks pair, and workload metadata into platform.podPolicy.* /
# platform.workloadMetadata. A re-inlined copy (e.g. a new pod-bearing
# generator hand-rolling the block) forks policy again — the drift the
# extraction closed. Counts are guarded with `|| true` because a zero match
# would otherwise abort the gate under set -e.
pull_total=$(cat "$LIB"/templates/*.tpl "$LIB"/templates/*.yaml | grep -c 'Values.global.imagePullSecrets' || true)
psc_total=$(cat "$LIB"/templates/*.tpl "$LIB"/templates/*.yaml | grep -c 'podSecurityContext "enabled"' || true)
# 3 = the identity helper + the two ServiceAccount OBJECT templates
# (_helpers.tpl:484,553), which legitimately set the field on the SA resource.
amt_total=$(cat "$LIB"/templates/*.tpl "$LIB"/templates/*.yaml | grep -c 'automountServiceAccountToken: {{' || true)
meta_calls=$(cat "$LIB"/templates/_deployment.yaml "$LIB"/templates/_statefulset.yaml "$LIB"/templates/_daemonset.yaml | grep -c 'platform.workloadMetadata' || true)
if [[ "$pull_total" -eq 1 && "$psc_total" -eq 1 && "$amt_total" -eq 3 && "$meta_calls" -eq 3 ]]; then
  echo "  OK: pull-secret precedence, pod securityContext, token policy, and workload metadata are single-source"
else
  echo "  FAIL: pod policy re-inlined somewhere (pullSecrets=$pull_total want 1, podSecurityContext=$psc_total want 1, automount=$amt_total want 3, workloadMetadata calls=$meta_calls want 3)"; fail=1
fi
```

Note the comment-line hazard: the helper comment blocks in `_helpers.tpl` must
not repeat the grepped literals (`Values.global.imagePullSecrets` etc.) or the
counts break. The helper texts in Phase 2 above were written to avoid that; if
you reworded comments, re-check the counts by running the greps by hand.

**Mutation tests — both must go RED before you commit:**

```bash
# Mutation 1: resurrect the pre-extraction CronJob (pull_total -> 2, psc_total -> 2)
git checkout 583b401 -- platform-library/templates/_cronjob.yaml
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh   # expect the new FAIL line, ==> FAIL
git restore --source=HEAD -- platform-library/templates/_cronjob.yaml

# Mutation 2: resurrect the pre-extraction DaemonSet metadata (meta_calls -> 2)
git checkout 583b401 -- platform-library/templates/_daemonset.yaml
REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh   # expect the new FAIL line, ==> FAIL
git restore --source=HEAD -- platform-library/templates/_daemonset.yaml
```

Using `583b401` as the mutation source is deliberate: the mutation is
literally "the world before the extraction", and it still renders valid output
— which proves the NEW check (not a render failure) is what catches it.

Then: `shellcheck -x scripts/lint-library.sh`, full gate `==> PASS`, commit.

## Test plan

- Full gate per phase: `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` ends `==> PASS`.
- `git diff --stat tests/golden/` empty at every phase (zero golden diffs is the acceptance criterion, not a hope).
- Phase 2 branch exercise: pull-secrets render probe above; plus
  `tests/render.sh minimal --set podSecurityContext.enabled=false` renders no
  pod-level `securityContext:` and no stray whitespace-only lines
  (`grep -nE ' +$'` on the output finds nothing new).
- Phase 3 mutation tests RED then restored GREEN.
- `shellcheck -x scripts/*.sh tests/render.sh` clean.

## Done criteria (machine-checkable)

1. `grep -c 'Values.global.imagePullSecrets' platform-library/templates/*` totals 1; `podSecurityContext "enabled"` totals 1; `automountServiceAccountToken: {{` totals 3.
2. All three workload generators contain `platform.workloadMetadata` and none contain `range $k, $v := .Values.commonLabels`.
3. Full gate ends `==> PASS`; `git diff 583b401..HEAD -- tests/golden/` is empty.
4. New gate section present, proven RED under both mutations (paste the FAIL lines in the PR description).
5. `CHANGELOG.md` untouched — **no entry needed**: rendered output is byte-identical and no consumer-facing values key changed; the lint-gate addition is repo-internal. State this explicitly in the PR description so the release gate reviewer doesn't hunt for a missing entry.
6. Bead `hf-s41` updated to reference this plan; remaining bead scope items noted there.

## STOP conditions

- **Any golden diff at any phase.** The gate prints
  `FAIL: rendered output drifted from golden`. This means the move was not a
  move. STOP, do not run `UPDATE_GOLDEN=1`, do not rationalize the diff —
  revert the phase and re-derive the whitespace mechanics.
- The new gate check cannot be made to go RED under mutation — the check is
  vacuous; fix the check, never ship it green-only.
- The drift check shows one of the six in-scope files changed since `583b401`
  in a way that invalidates an excerpt, and you cannot re-verify the current
  bytes confidently.
- You find yourself editing behavior (defaults, ordering, hardening) "while
  you're in there" — that is the smuggling this plan exists to prevent.

## Maintenance notes

- Future pod-bearing generators call the `podPolicy.*` family instead of
  hand-rolling policy; the Phase 3 gate check enforces it mechanically.
- Follow-ups unlocked (file as beads, do not do here): finding #13
  commonLabels propagation via `workloadMetadata` adoption in more generators;
  CronJob default-container hardening unification; scheduling-field parity for
  CronJob/hook pods; `renderHookJob` relocation (hf-s41 remainder).
- If plan 010 lands and reshapes gate sections, this plan's Phase 3 section is
  independent of it (different greps, different files) — no coordination
  needed beyond normal rebase.
