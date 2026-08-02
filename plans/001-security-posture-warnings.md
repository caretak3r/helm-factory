# Plan 001 — NOTES warnings for weakened security posture and active escape hatches

Planned at: 583b401

## Executor instructions

Read this plan top to bottom before touching anything. It is self-contained: every
excerpt below was read from the repo at commit `583b401` and is quoted verbatim.
Before you start, run the drift check:

```bash
git diff --stat 583b401..HEAD -- \
  platform-library/templates/_notes.tpl \
  scripts/lint-library.sh \
  platform-library/values.yaml \
  CHANGELOG.md
```

If that diff is non-empty, re-read the touched files and re-anchor every edit in
this plan by CONTENT (the quoted excerpts), not by line number, before
proceeding. If an excerpt no longer exists in the file, STOP and report.

## Status

| Field | Value |
|---|---|
| Priority | P1 |
| Effort | S |
| Risk | LOW (NOTES-only; zero manifest-output change) |
| Depends on | none |
| Category | security / operator visibility |
| Planned at | 583b401 |
| Findings | .uplift/survey-findings.md #1 and #3 |

## Why this matters

The library's whole premise is hardened-by-default with loud, visible
deviations. Today two classes of deviation are silent:

1. **Weakened container hardening** (finding #1, orchestrator-VERIFIED):
   `tests/render.sh minimal --set containerSecurityContext.privileged=true`
   renders successfully with `privileged: true` in the pod spec, exit 0, and
   emits **no warning anywhere**. Likewise `containerSecurityContext.enabled=false`
   silently strips every per-container hardening default (design invariant 6).
   Ironically, `_notes.tpl:41-43` already warns when a *sidecar* sets
   `privileged: true` — but the main container path has no equivalent.
2. **Escape hatches active without warning** (finding #3):
   `mtls.allowAllPrincipals=true` renders the wildcard principal
   `cluster.local/ns/*/sa/*` (see `platform-library/templates/_mtls.yaml:5-6`),
   and `allowClusterScopedExtras=true` opens the cluster-scoped extraObjects
   gate — neither has a NOTES branch. Project convention (CLAUDE.md, "Security
   defaults are invariants") says escape hatches "stay opt-in and warned"; the
   second half is not implemented.

These stay warnings, not `fail`s: the keys are legitimate opt-outs (a consumer
may genuinely need privileged for a CNI-adjacent workload). Fail-closed applies
to *invalid* config; this is *dangerous-but-valid* config, which is exactly what
the NOTES warning channel exists for.

## Current state (verbatim excerpts @ 583b401)

`platform-library/templates/_notes.tpl` is the single warnings helper. Its
comment header (lines 7-10) documents the property this plan relies on:

```
Renders nothing when there is nothing to warn about. NOTES.txt content never
appears in `helm template` manifest output (verified with Helm 4.2.0), so
golden snapshots, kind counts, and kubeconform are unaffected; warnings show
on `helm install`/`helm upgrade` (including --dry-run).
```

The house pattern to extend (`_notes.tpl:16` and the branch style at 25-27):

```
{{- $warnings := list -}}
...
{{- if and .Values.ingress.enabled .Values.ingress.hostname (not .Values.ingress.tls) -}}
{{- $warnings = append $warnings (printf "Ingress host %q is served over PLAIN HTTP (ingress.tls=false). Set ingress.tls=true with ingress.existingSecret, or use cert-manager via the certificate block / an ingress annotation." .Values.ingress.hostname) -}}
{{- end -}}
```

and the final output loop (`_notes.tpl:48-51`):

```
{{- range $w := $warnings }}
WARNING: {{ $w }}
{{ end -}}
```

Relevant defaults in `platform-library/values.yaml` (hardening block, ~501-511):
`containerSecurityContext` ships `enabled: true`, `runAsUser: 1001`,
`runAsNonRoot: true`, `readOnlyRootFilesystem: true`,
`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`,
`seccompProfile.type: RuntimeDefault`. `podSecurityContext` ships
`enabled: true`. `mtls` ships `enabled: false`, `allowedPrincipals: []`,
`allowAllPrincipals: false` (~316-320). `allowClusterScopedExtras: false` (~655).
So **no new warning may fire on library defaults** — the lint gate asserts the
minimal fixture emits zero warnings (`scripts/lint-library.sh:746-751`).

The gate's NOTES harness (`scripts/lint-library.sh:712-718`):

```bash
notes_of() {
  local fixture="$1"; shift
  local dir="$REPO_ROOT/tests/fixtures/$fixture"
  cp "$LIB/values.schema.reference.json" "$dir/values.schema.json"
  helm dependency update "$dir" >/dev/null 2>&1
  helm install notes-check "$dir" --dry-run=client "$@"
}
```

Fixture facts that matter:
- `tests/fixtures/full/values.yaml` sets `allowClusterScopedExtras: true` and
  `mtls.enabled: true` **with explicit `allowedPrincipals`** (not the wildcard).
  Only the `minimal` fixture has a "no warnings at all" gate assertion; `full`
  already emits the ClusterRole-extras warning today, so a new
  `allowClusterScopedExtras` warning on `full` breaks nothing.
- The existing wildcard-principal positive test (`lint-library.sh:537-542`) uses
  `full --set mtls.allowedPrincipals=null --set mtls.allowAllPrincipals=true` —
  reuse exactly this values shape for the NOTES test.

All values keys used below exist in `values.schema.reference.json`
(`containerSecurityContext.privileged` and `.enabled` are booleans;
`mtls.allowAllPrincipals` is a boolean), so every `--set` in the test plan
passes helm-side schema validation.

## Commands

| Command | Purpose |
|---|---|
| `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` | THE gate; must end `==> PASS` |
| `tests/render.sh minimal --set containerSecurityContext.privileged=true` | manual smoke: still renders (warning is NOTES-only) |
| `helm install x tests/fixtures/minimal --dry-run=client --set containerSecurityContext.privileged=true` | see the new warning by eye (after `helm dependency update` + schema copy, or just use the gate) |
| `shellcheck -x scripts/lint-library.sh` | after editing the gate script |

## Suggested executor toolkit

Helm 4.x, kubeconform, check-jsonschema, shellcheck (all on PATH via homebrew/
pipx). No cluster needed. Skills to load: `template-house-style` (you are
editing a `_*.tpl`), `security-posture-invariants`, `validate-factory`.

## Scope

**In scope**
- `platform-library/templates/_notes.tpl` — new warning branches only.
- `scripts/lint-library.sh` — new NOTES assertions (guarded idiom).
- `CHANGELOG.md` — `[Unreleased]` entry.

**Out of scope (do NOT touch)**
- Any change to what manifests render. This plan is warnings-only.
- Turning any of these conditions into a `fail` (that is a contract change).
- Warning on sidecar/extras YAML beyond one `contains` addition is explicitly
  deferred (see Maintenance notes).
- `values.schema.reference.json` — no new values keys are introduced.
- Findings #2, #5, #12 (separate plans 002-004).

## Git workflow

Branch off `main` (e.g. `feat/notes-posture-warnings`). One commit:
`feat(notes): warn when containerSecurityContext weakens hardening or escape hatches are active`.
PR to `main` with CI green; squash-merge. Never push directly to `main`.

## Steps

### Step 1 — add posture-weakening branches to `_notes.tpl`

Insert the following block into `platform.notes`, immediately BEFORE the line
that begins `{{- $extrasYaml := printf` (line 37 at 583b401). This keeps
security-posture warnings grouped ahead of the extras substring scans.

```
{{- $csc := .Values.containerSecurityContext | default dict -}}
{{- if not $csc.enabled -}}
{{- $warnings = append $warnings "containerSecurityContext.enabled=false disables the per-container hardening defaults (runAsNonRoot, readOnlyRootFilesystem, allowPrivilegeEscalation=false, capabilities drop ALL, seccompProfile RuntimeDefault) for EVERY container in the release. The pod no longer meets the PSS restricted profile. Re-enable it and override individual keys instead." -}}
{{- else -}}
{{- $weakened := list -}}
{{- if $csc.privileged -}}
{{- $weakened = append $weakened "privileged=true (disables all container isolation)" -}}
{{- end -}}
{{- if $csc.allowPrivilegeEscalation -}}
{{- $weakened = append $weakened "allowPrivilegeEscalation=true" -}}
{{- end -}}
{{- if and (hasKey $csc "runAsNonRoot") (not $csc.runAsNonRoot) -}}
{{- $weakened = append $weakened "runAsNonRoot=false" -}}
{{- end -}}
{{- if and (hasKey $csc "runAsUser") (eq (int $csc.runAsUser) 0) -}}
{{- $weakened = append $weakened "runAsUser=0 (root)" -}}
{{- end -}}
{{- if and $csc.seccompProfile (eq ($csc.seccompProfile.type | default "") "Unconfined") -}}
{{- $weakened = append $weakened "seccompProfile.type=Unconfined" -}}
{{- end -}}
{{- $badCaps := list -}}
{{- if $csc.capabilities -}}
{{- range $cap := ($csc.capabilities.add | default list) -}}
{{- if ne (printf "%v" $cap) "NET_BIND_SERVICE" -}}
{{- $badCaps = append $badCaps (printf "%v" $cap) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if $badCaps -}}
{{- $weakened = append $weakened (printf "capabilities.add grants %s (PSS restricted allows only NET_BIND_SERVICE)" (join ", " $badCaps)) -}}
{{- end -}}
{{- if $weakened -}}
{{- $warnings = append $warnings (printf "containerSecurityContext WEAKENS the default hardened posture: %s. The pod may fail PSS-restricted admission or run with elevated privilege — make sure this is intentional and reviewed." (join "; " $weakened)) -}}
{{- end -}}
{{- end -}}
{{- if not .Values.podSecurityContext.enabled -}}
{{- $warnings = append $warnings "podSecurityContext.enabled=false removes the pod-level hardening defaults (fsGroup, runAsNonRoot, seccompProfile RuntimeDefault). The pod no longer meets the PSS restricted profile." -}}
{{- end -}}
```

Design notes for the reviewer:
- `hasKey` distinguishes "consumer explicitly set runAsNonRoot: false /
  runAsUser: 0" from "key absent" — absent keys must not warn.
- `printf "%v"` on capability names follows house style for numeric-capable
  scalars (`template-house-style` rule 6).
- Library defaults trip NONE of these branches (enabled=true, runAsNonRoot=true,
  runAsUser=1001, no add caps, seccomp RuntimeDefault, podSecurityContext
  enabled) — required by the minimal-fixture silence assertion.

**Verify:** proceed to Step 3's checks; for a quick eyeball,
`tests/render.sh minimal --set containerSecurityContext.privileged=true` must
still succeed with unchanged manifest output.

### Step 2 — add escape-hatch branches to `_notes.tpl`

Insert immediately after the Step 1 block (still before `$extrasYaml`):

```
{{- if and .Values.mtls.enabled .Values.mtls.allowAllPrincipals (empty (.Values.mtls.allowedPrincipals | default list)) -}}
{{- $warnings = append $warnings "mtls.allowAllPrincipals=true authorizes the wildcard principal cluster.local/ns/*/sa/*: any workload in the mesh may call this service (mTLS identity without meaningful authorization). List explicit principals under mtls.allowedPrincipals when possible." -}}
{{- end -}}
{{- if .Values.allowClusterScopedExtras -}}
{{- $warnings = append $warnings "allowClusterScopedExtras=true: extraObjects may render cluster-scoped Kinds (ClusterRole, PriorityClass, StorageClass, webhooks, ...). Cluster-scoped objects outlive the namespace and affect the whole cluster — keep them least-privilege and reviewed." -}}
{{- end -}}
```

Design notes:
- The mtls warning fires only when the wildcard is actually what renders
  (`_mtls.yaml:5-6` uses the wildcard only when `allowedPrincipals` is empty);
  explicit principals + a stray `allowAllPrincipals: true` is inert and stays
  quiet.
- The `allowClusterScopedExtras` warning fires whenever the flag is true — the
  flag being left on is itself the hazard. This complements (does not replace)
  the existing ClusterRole-specific branch at `_notes.tpl:44-47`. Note the
  `full` fixture sets this flag, so `notes_of full` gains one warning; the only
  "must be silent" assertions in the gate are minimal/no-WARNING and
  full/no-"SKIPPED KINDS", and neither is affected.

### Step 3 — gate assertions (guarded idiom, invariant 5)

In `scripts/lint-library.sh`, insert a new section AFTER the block that ends
`  FAIL: helm template failed for stateful fixture` (the
"`helm template` never includes NOTES" check, lines 756-765) and BEFORE
`echo "==> NOTES: Kinds enabled in values but skipped by capability gating"`
(line 767). Every check uses the guarded `if out=$(...)` idiom — a bare
`var=$(...)` under `set -e` (line 43: `set -euo pipefail`) aborts the whole
gate silently, which is design invariant 5.

```bash
echo "==> NOTES warnings: weakened security posture and active escape hatches"
# privileged=true renders (valid opt-out) but must be loudly warned.
if out=$(notes_of minimal --set containerSecurityContext.privileged=true 2>&1); then
  if grep -q "containerSecurityContext WEAKENS" <<<"$out" &&
     grep -q "privileged=true" <<<"$out"; then
    echo "  OK: privileged=true emits the posture-weakening NOTES warning"
  else
    echo "  FAIL: privileged=true did not emit the posture-weakening NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal with privileged=true"; echo "$out" | tail -5; fail=1
fi

# Disabling the whole hardening block is the biggest hammer — dedicated warning.
if out=$(notes_of minimal --set containerSecurityContext.enabled=false 2>&1); then
  if grep -q "containerSecurityContext.enabled=false disables" <<<"$out"; then
    echo "  OK: containerSecurityContext.enabled=false emits the hardening-disabled NOTES warning"
  else
    echo "  FAIL: containerSecurityContext.enabled=false did not emit the expected NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal with hardening disabled"; echo "$out" | tail -5; fail=1
fi

# Wildcard principal escape hatch (same values shape as the render-path test above).
if out=$(notes_of full --set mtls.allowedPrincipals=null --set mtls.allowAllPrincipals=true 2>&1); then
  if grep -q "allowAllPrincipals=true authorizes the wildcard principal" <<<"$out"; then
    echo "  OK: mtls.allowAllPrincipals=true emits the wildcard-principal NOTES warning"
  else
    echo "  FAIL: mtls.allowAllPrincipals=true did not emit the wildcard-principal NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for full with allowAllPrincipals"; echo "$out" | tail -5; fail=1
fi

# Cluster-scoped extras escape hatch (full fixture sets allowClusterScopedExtras=true).
if out=$(notes_of full 2>&1); then
  if grep -q "allowClusterScopedExtras=true" <<<"$out"; then
    echo "  OK: allowClusterScopedExtras=true emits the escape-hatch NOTES warning"
  else
    echo "  FAIL: allowClusterScopedExtras=true did not emit the escape-hatch NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for full fixture"; echo "$out" | tail -5; fail=1
fi
```

The existing minimal-fixture silence check (`lint-library.sh:746-751`) is the
false-positive guard for ALL new branches: it must stay green untouched.

**Verify:** `shellcheck -x scripts/lint-library.sh` clean, then the full gate.

### Step 4 — mutation tests (prove every new check can go RED)

For each new check, one at a time: apply the mutation, run the full gate,
confirm the specific `FAIL:` line appears and the gate ends `==> FAIL` with
exit 1, then restore the file (`git checkout -- platform-library/templates/_notes.tpl`)
and re-run to green before the next mutation. Required mutations:

1. Delete the `{{- if $csc.privileged -}}...{{- end -}}` branch → the
   privileged check must go RED.
2. Delete the `{{- if not $csc.enabled -}}` warning append (keep the else arm)
   → the enabled=false check must go RED.
3. Delete the mtls `allowAllPrincipals` branch → the wildcard check must go RED.
4. Delete the `allowClusterScopedExtras` branch → the escape-hatch check must go RED.

Record in the PR description which mutations were run and that each went RED.

### Step 5 — CHANGELOG

Under `## [Unreleased]` in `CHANGELOG.md` (currently "Nothing yet." — replace
that placeholder), add:

```markdown
### Added — NOTES warnings for weakened posture and escape hatches

- `platform.notes` now warns when `containerSecurityContext` weakens the
  hardened defaults (`privileged`, `allowPrivilegeEscalation`,
  `runAsNonRoot=false`, `runAsUser=0`, non-NET_BIND_SERVICE `capabilities.add`,
  `seccompProfile.type=Unconfined`), when `containerSecurityContext.enabled=false`
  or `podSecurityContext.enabled=false` disables hardening outright, and when
  the `mtls.allowAllPrincipals` or `allowClusterScopedExtras` escape hatches
  are active. Warnings appear on `helm install`/`upgrade` (including
  `--dry-run`); rendered manifests are unchanged.
```

## Golden-file impact

**Zero.** `_notes.tpl`'s header (quoted above) and the gate's own invariant
check (`lint-library.sh:756-765`) establish that NOTES content never appears in
`helm template` output. Done criterion: `git status tests/golden/` shows no
modifications and the gate's golden comparison passes without `UPDATE_GOLDEN`.
If ANY golden file diffs, your change leaked into manifest output — STOP,
that is a bug in the change, do not regenerate goldens.

## Test plan / verification

1. `shellcheck -x scripts/*.sh tests/render.sh` — clean.
2. `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh`
   must end `==> PASS` (exit 0). This is the definition of done; paste the
   tail of its output in the PR. `FIXTURES=minimal` subset runs skip the
   guardrail suite and are NOT sufficient.
3. All four Step 4 mutations demonstrated RED, then restored to green.
4. `git status` — only `_notes.tpl`, `lint-library.sh`, `CHANGELOG.md` modified.

Do not run the gate (or `tests/render.sh`) while any sibling agent/session is
also rendering — `tests/render.sh` and `notes_of` mutate fixture `charts/` dirs
and `Chart.lock` in place, and concurrent runs race (known repo constraint).

## STOP conditions

- Any golden file diff.
- The minimal-fixture no-warning check goes RED with your branches in place
  (means a default triggers a warning — your condition is wrong; fix the
  condition, never the default and never the check).
- You find yourself wanting to `fail` instead of warn — that is a contract
  change; stop and escalate.
- A mutation does NOT turn its check RED — the check is vacuous; fix the check.
- Drift check shows `_notes.tpl` changed since 583b401 in the regions quoted.

## Maintenance notes

- Deferred (out of scope, candidate follow-up): add
  `contains "allowPrivilegeEscalation: true"` to the `$extrasYaml` substring
  scan at `_notes.tpl:37-43` so sidecars/extras get parity for that key too.
- If a future PSS profile changes the allowed capability set, the
  NET_BIND_SERVICE allowlist in Step 1 is the single place to update.
- These warnings intentionally read from `.Values` (post `import-values`
  merge), not from rendered output — same trade-off as every existing branch
  in `_notes.tpl`.
