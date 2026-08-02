# Plan 007: Close the gate's validation gaps — kubeconform everywhere, no silent PASS, cross-version goldens

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 583b401..HEAD -- scripts/lint-library.sh scripts/lib/schema-manifest.sh scripts/vendor-schemas.sh tests/schemas tests/golden`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition. In particular, if plans/005 landed
> first (it also edits `scripts/lint-library.sh`), rebase on its state — the
> sections it adds are ADOPTERS of this plan's helper, not conflicts.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none hard. Soft ordering: after plans/005 (both edit
  `scripts/lint-library.sh`; 005 adds renders this plan should validate) and
  after plans/006 (renders get ~30x cheaper; this plan adds ~50 kubeconform
  invocations).
- **Category**: tests
- **Planned at**: commit `583b401`, 2026-07-28

## Why this matters

Three validation gaps let the gate claim more than it checks (survey findings
#6, #10, #15):

1. Only the 12 render-matrix renders (4 fixtures x 3 K8s versions) pass
   through kubeconform. The ~50 guardrail-section renders that follow are
   grepped for specific strings and discarded — a guardrail `--set` that
   produces schema-invalid output (wrong type, misplaced field) passes today.
2. A bare `scripts/lint-library.sh` run with kubeconform or check-jsonschema
   missing prints a WARN, skips the entire schema-validation layer, and still
   ends `==> PASS` — the gate silently thins itself. Everything in this repo
   treats `==> PASS` as the definition of done.
3. Goldens are diffed only at K8s 1.34 (`GOLDEN_KUBE_VERSION`), while the
   matrix renders 1.34/1.35/1.36. Those renders are byte-identical today, so
   pinning all versions to the golden is a free assertion that catches any
   future version-dependent render drift — without adding a single new golden
   file.

## Current state

Files and roles:

- `scripts/lint-library.sh` (1150 lines) — the gate. Structure: config +
  tool detection (`:55` `FIXTURES=(minimal full stateful daemon)`, `:56`
  `GOLDEN_KUBE_VERSION=1.34`, tool detection `:147-165`), render matrix +
  golden diff (`:189-243`), subset-mode early exit (`:250-254`), then 30+
  guardrail sections (`:256` onward), final verdict at `:1149`.
- `scripts/lib/schema-manifest.sh` — single source of truth:
  `KUBE_VERSIONS=(1.34 1.35 1.36)`, `NATIVE_SCHEMA_KINDS`, and
  `CRD_SCHEMA_PATHS`.
- `scripts/vendor-schemas.sh` — downloads schemas into `tests/schemas/`
  (network required; also regenerates `tests/schemas/README.md`).
- `tests/schemas/{native,crd}/` — vendored schemas kubeconform runs against
  (hermetic; no network at gate time).
- `tests/render.sh` — render entrypoint (`$RENDER` in the gate).

### Tool detection today (`scripts/lint-library.sh:147-165`)

```bash
have_kubeconform=0
if command -v kubeconform >/dev/null 2>&1; then
  have_kubeconform=1
elif [[ "${REQUIRE_KUBECONFORM:-0}" == "1" ]]; then
  echo "FAIL: kubeconform is required (REQUIRE_KUBECONFORM=1) but not installed"
  fail=1
else
  echo "WARN: kubeconform not installed — schema validation SKIPPED (set REQUIRE_KUBECONFORM=1 to fail instead)"
fi

have_check_jsonschema=0
if command -v check-jsonschema >/dev/null 2>&1; then
  have_check_jsonschema=1
elif [[ "${REQUIRE_CHECK_JSONSCHEMA:-0}" == "1" ]]; then
  echo "FAIL: check-jsonschema is required (REQUIRE_CHECK_JSONSCHEMA=1) but not installed"
  fail=1
else
  echo "WARN: check-jsonschema not installed - values schema validation SKIPPED (set REQUIRE_CHECK_JSONSCHEMA=1 to fail instead)"
fi
```

### Matrix-loop kubeconform (the ONLY kubeconform today, `:189-215` area)

```bash
if out=$("$RENDER" "$fx" --kube-version "$kv" 2>&1); then
  ...
  if [[ "$have_kubeconform" == "1" ]]; then
    # Validate THIS version's own render (not the canonical golden render):
    # version-specific apiVersion negotiation must be schema-checked at the
    # version that produced it.
    if kc_out=$(kubeconform -strict -summary \
           -kubernetes-version "$kv.0" \
           -schema-location "$NATIVE_SCHEMA_LOCATION" \
           -schema-location "$CRD_SCHEMA_LOCATION" \
           <<<"$out" 2>&1); then
      printf '%s\n' "$kc_out"
    else
      printf '%s\n' "$kc_out"
      echo "  k8s $kv: FAIL — kubeconform"; fail=1
```

The golden diff (against `tests/golden/<fixture>.yaml`) happens in the same
loop but ONLY for `GOLDEN_KUBE_VERSION`; `UPDATE_GOLDEN=1` rewrites goldens
there. Read the live loop (`:189-243`) before editing — the normalization
applied before diffing must be reused verbatim for the cross-version check.

### Subset-mode early exit (`:250-254`)

```bash
if [[ -n "$FIXTURES_ENV" || -n "$KUBE_VERSIONS_ENV" ]]; then
  echo "==> guardrail + negative-render suite: SKIPPED (FIXTURES/KUBE_VERSIONS subset — run bare scripts/lint-library.sh for the full gate)"
  if [[ $fail -eq 0 ]]; then echo "==> PASS (subset)"; else echo "==> FAIL"; fi
  exit $fail
fi
```

### Final verdict (`:1149`)

```bash
if [[ $fail -eq 0 ]]; then echo "==> PASS"; else echo "==> FAIL"; fi
```

### Guardrail-section render idiom (what will adopt the helper, `:259+`)

Sections follow the guarded pattern (invariant 5 — a bare `var=$(...)` under
`set -e` silently aborts the gate):

```bash
if ! neg=$("$RENDER" full --set capabilities.apiVersions=null 2>&1); then
  echo "  FAIL: negative render itself failed"; ...; fail=1
else
  if grep -qE '^kind: (...)$' <<<"$neg"; then ...
```

Helper functions in this script run in the PARENT shell so `fail=1`
propagates — a helper called inside `$(...)` cannot set `fail`. Preserve
this property.

### Vendored CRD schema inventory (`tests/schemas/crd/` at `583b401`)

```
cert-manager.io/certificate_v1.json
gateway.networking.k8s.io/httproute_v1.json
monitoring.coreos.com/podmonitor_v1.json
monitoring.coreos.com/servicemonitor_v1.json
security.istio.io/authorizationpolicy_v1beta1.json
security.istio.io/peerauthentication_v1beta1.json
```

**Gap that constrains workstream (a)**: guardrail sections deliberately
exercise OTHER negotiated versions — the Gateway API negotiation checks
(`:898-939`) render HTTPRoute at `v1beta1` and GRPCRoute at `v1alpha2`/`v1`
(no GRPCRoute schema is vendored at all). kubeconform `-strict` FAILS on a
Kind it has no schema for. So adopting kubeconform in those sections requires
either vendoring the missing schema versions (preferred; sourced from the
datreeio CRDs-catalog via `scripts/vendor-schemas.sh` + `CRD_SCHEMA_PATHS` in
`scripts/lib/schema-manifest.sh`) or a per-call opt-out for legs whose
schema the catalog does not carry.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| THE gate (definition of done) | `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` | ends `==> PASS`, exit 0 |
| Fast subset loop | `FIXTURES=minimal scripts/lint-library.sh` | ends `==> PASS (subset)` |
| Re-vendor schemas (network) | `scripts/vendor-schemas.sh` | exit 0; `tests/schemas/` updated |
| Shellcheck | `shellcheck -x scripts/*.sh tests/render.sh` | exit 0 |
| Golden diff check | `git diff --exit-code tests/golden/` | exit 0 |
| Syntax check | `bash -n scripts/lint-library.sh` | exit 0 |

## Scope

**In scope** (the only files you should modify):
- `scripts/lint-library.sh`
- `scripts/lib/schema-manifest.sh` (add CRD schema versions)
- `tests/schemas/**` (regenerated by `scripts/vendor-schemas.sh` only — never
  hand-edit vendored schema files)

**Out of scope** (do NOT touch):
- `tests/golden/*.yaml` — zero diffs expected; never `UPDATE_GOLDEN` here.
- `platform-library/**` — no template changes in this plan.
- `tests/render.sh` — plans/006's territory.
- `.github/workflows/**` — CI already invokes the `REQUIRE_*` form and keeps
  working unchanged; workflow hardening is plans/008.
- `CLAUDE.md`/`AGENTS.md` — their "THE gate" wording stays valid (the bare
  invocation becomes strictly stronger); doc touch-ups are a maintenance
  follow-up, not this plan.
- `scripts/vendor-schemas.sh` itself — its source-ref pinning is plans/008;
  you only RUN it here. (If plans/008 already landed, it runs with pinned
  refs — fine.)

## Git workflow

- Branch: `advisor/007-gate-validation-coverage` off `main` (rebase onto
  plans/005's merge if it landed).
- Conventional Commits, e.g.
  `test(gate): kubeconform guardrail renders, fail-loud validators, cross-version goldens`.
- Repo rule is PR-only main with squash-merge; do NOT push or open a PR
  unless the operator instructed it.

## Steps

### Step 1: Vendor the missing CRD schema versions

In `scripts/lib/schema-manifest.sh`, extend `CRD_SCHEMA_PATHS` (match the
existing entry format exactly — read the array first) with the versions the
guardrail sections negotiate:

- `gateway.networking.k8s.io/httproute_v1beta1`
- `gateway.networking.k8s.io/grpcroute_v1`
- `gateway.networking.k8s.io/grpcroute_v1alpha2`
- `security.istio.io/authorizationpolicy_v1`
- `security.istio.io/peerauthentication_v1`

Then run `scripts/vendor-schemas.sh`. Before relying on them, confirm each
new path actually exists in the datreeio CRDs-catalog (the script will fail
or fetch an error page if not — inspect the downloaded files are JSON:
`head -c 200 tests/schemas/crd/gateway.networking.k8s.io/grpcroute_v1alpha2.json`).
If the catalog lacks one (most likely candidate: `grpcroute_v1alpha2`), drop
that entry and rely on the per-call opt-out from Step 2 for the affected leg,
with a comment naming the missing schema.

**Verify**: `scripts/vendor-schemas.sh` exits 0;
`ls tests/schemas/crd/gateway.networking.k8s.io/` lists the new files;
`git diff --stat tests/schemas/` shows only additions (plus README
regeneration). If any PRE-EXISTING vendored schema file changed content,
STOP (see STOP conditions).

### Step 2: Add the `validate_render` helper

In `scripts/lint-library.sh`, next to the other helper functions (before the
guardrail sections), add a parent-shell helper:

```bash
# validate_render <label> <rendered-yaml> [kube-version] [allow-missing]
# Schema-checks a successful guardrail render with kubeconform against the
# vendored schemas. MUST be called from the parent shell (never inside a
# $(...) substitution) so fail=1 propagates. Pass allow-missing=1 ONLY for
# legs that negotiate an apiVersion the vendored catalog cannot supply, with
# a comment at the call site naming the missing schema.
validate_render() {
  local label="$1" rendered="$2" kv="${3:-$GOLDEN_KUBE_VERSION}" allow_missing="${4:-0}"
  if [[ "$have_kubeconform" != "1" ]]; then return 0; fi
  local extra=()
  if [[ "$allow_missing" == "1" ]]; then extra=(-ignore-missing-schemas); fi
  local kc_out
  if kc_out=$(kubeconform -strict -summary \
        -kubernetes-version "$kv.0" \
        -schema-location "$NATIVE_SCHEMA_LOCATION" \
        -schema-location "$CRD_SCHEMA_LOCATION" \
        "${extra[@]}" <<<"$rendered" 2>&1); then
    :
  else
    printf '%s\n' "$kc_out"
    echo "  FAIL: kubeconform ($label)"; fail=1
  fi
}
```

(Use the exact variable names `NATIVE_SCHEMA_LOCATION`/`CRD_SCHEMA_LOCATION`
as the matrix loop does — read `:189-215` for the live spelling.)

**Verify**: `bash -n scripts/lint-library.sh` → exit 0.

### Step 3: Adopt the helper in every positive guardrail render

Mechanical rule — enumerate all render call sites:

```bash
grep -n '"\$RENDER"' scripts/lint-library.sh
```

For each site AFTER the subset early-exit (`:250-254`) where the section
treats a SUCCESSFUL render as the expected path (i.e. the `if out=$(...)`
success branch contains the section's assertions), insert
`validate_render "<section label>" "$out"` at the top of that success branch.
Pass the section's `--kube-version` value when it sets one; default
otherwise. Do NOT adopt in:

- negative renders where the render itself is EXPECTED to fail (the
  assertions live in the failure branch);
- NOTES / `helm install --dry-run` helpers (not manifest streams);
- renders of deliberately partial output (none known at `583b401`, but apply
  judgment per the rule above — expected-successful full-manifest renders
  adopt, everything else does not).

For the Gateway API negotiation legs (`:898-939`) rendering
HTTPRoute v1beta1 / GRPCRoute v1alpha2: if Step 1 vendored their schemas,
adopt normally; otherwise pass `allow-missing=1` with a comment naming the
missing catalog schema.

Expect roughly 40-50 adoption sites. Keep each insertion one line — the
section's own assertions stay untouched.

**Verify**: `bash -n scripts/lint-library.sh` → exit 0; then run the full
gate once (expect `==> PASS`; kubeconform failures here mean either a real
latent bug — report it — or a missing schema → revisit Step 1). Record
the wall-time delta in your report (~50 kubeconform runs at ~0.1-0.3s each;
with plans/006 landed the gate should still be far under the 4 min baseline).

### Step 4: Fail loudly on missing validators (with explicit degraded mode)

Decision (made in planning, justified here so a reviewer can re-litigate):
**bare `scripts/lint-library.sh` fails when validators are missing**, instead
of a PASS-with-banner. Rationale: `==> PASS` is the machine-checked done
signal across this repo's docs and skills; a gate that silently thins itself
violates the spirit of invariant 5; CI already always sets `REQUIRE_*`, so
nothing in automation changes. An explicit escape hatch preserves the
run-degraded workflow for machines without the tools.

Rules:
- Missing tool + `ALLOW_MISSING_VALIDATORS=1` → WARN, record degraded, run.
- Missing tool otherwise → FAIL with install hint (`brew install
  kubeconform`, `pipx install check-jsonschema`).
- `REQUIRE_KUBECONFORM=1`/`REQUIRE_CHECK_JSONSCHEMA=1` keep today's meaning
  and WIN over `ALLOW_MISSING_VALIDATORS` (missing tool is FAIL regardless).
- A degraded run that otherwise passes must NOT print the plain PASS line.
  Final line: `==> DEGRADED PASS (missing:<tools>)`. This string deliberately
  does NOT contain the substring `==> PASS`, so every existing
  "ends with ==> PASS" check (docs, skills, CI grep) correctly refuses a
  degraded run. Subset variant: `==> DEGRADED PASS (subset, missing:<tools>)`
  — likewise must not contain `==> PASS (subset)`.

Implementation: initialize `degraded=""` near the top; rewrite the two
detection blocks (`:147-165`) to the rules above (append the tool name to
`degraded` in the allowed-degraded branch); update the subset exit
(`:250-254`) and final verdict (`:1149`):

```bash
if [[ $fail -eq 0 ]]; then
  if [[ -n "$degraded" ]]; then
    echo "==> DEGRADED PASS (missing:$degraded)"
  else
    echo "==> PASS"
  fi
else
  echo "==> FAIL"
fi
```

Also update the usage comment block at the top of `scripts/lint-library.sh`
to document `ALLOW_MISSING_VALIDATORS` and the degraded final line.

**Verify** (PATH-shim mutation, also serves as Step 6's mutation for this
workstream): build a shim dir exposing helm but not the brew-installed
validators, then run the subset gate:

```bash
shim=$(mktemp -d); ln -s "$(command -v helm)" "$shim/helm"
PATH="$shim:/usr/bin:/bin" FIXTURES=minimal scripts/lint-library.sh; echo "exit=$?"
PATH="$shim:/usr/bin:/bin" ALLOW_MISSING_VALIDATORS=1 FIXTURES=minimal scripts/lint-library.sh | tail -1
PATH="$shim:/usr/bin:/bin" ALLOW_MISSING_VALIDATORS=1 REQUIRE_KUBECONFORM=1 FIXTURES=minimal scripts/lint-library.sh; echo "exit=$?"
```

Expected: first → `FAIL:` lines for both validators, final `==> FAIL`,
`exit=1`. Second → last line `==> DEGRADED PASS (subset, missing: kubeconform check-jsonschema)`
(exact tool-list formatting yours; the `==> PASS` substring must be absent —
check with `| tail -1 | grep -c '==> PASS'` → `0`). Third → `exit=1`
(REQUIRE wins). (`/usr/bin:/bin` lacks the homebrew tools but supplies
bash/grep/sed; if `tests/render.sh` needs another brew tool, symlink it into
the shim and note it.)

### Step 5: Pin goldens across the K8s version matrix

In the matrix loop (`:189-243`): today the normalize-and-diff against
`tests/golden/<fixture>.yaml` runs only when `kv == GOLDEN_KUBE_VERSION`.
Change: run it for EVERY version, with an override lookup —

- If `tests/golden/<fixture>@<kv>.yaml` exists, diff that version's
  normalized render against it (escape hatch for a future K8s version whose
  render legitimately diverges).
- Otherwise diff against the base `tests/golden/<fixture>.yaml` (the
  cross-version identity assertion — free today because 1.34/1.35/1.36
  render byte-identically).
- `UPDATE_GOLDEN=1` keeps writing ONLY the base golden from
  `GOLDEN_KUBE_VERSION`'s render, plus refreshing any override file that
  ALREADY exists from its own version's render. It never creates override
  files — creating one is a deliberate manual act (`cp` the failing
  version's normalized render, with review). Document this in a comment at
  the lookup site.

Reuse the loop's existing normalization pipeline verbatim (factor it into a
small function if it is inline duplicated). FAIL message must name fixture,
version, and whether base or override golden was compared. Guarded idiom
throughout.

**Verify**: full gate → `==> PASS` (no override files exist; all three
versions match base goldens — confirming finding #15's premise);
`ls tests/golden/` → still exactly `daemon.yaml full.yaml minimal.yaml stateful.yaml`.

### Step 6: Mutation tests — prove each new check can go RED

(Invariant 5: every new gate check must be demonstrated RED. Commit your work
first so `git checkout -- <file>` reverts only mutations.)

1. **validate_render**: temporarily add a schema-invalid object to one
   adopted section's render via the raw escape hatch, e.g. append to that
   section's `$RENDER` args:
   `--set-json 'extraManifests=[{"apiVersion":"v1","kind":"Service","metadata":{"name":"bad-mutation"},"spec":{"ports":"not-a-list"}}]'`
   → run the gate; the section must print `FAIL: kubeconform (<label>)` and
   the run must end `==> FAIL`. Revert.
2. **Missing-validator fail-loud**: already proven by Step 4's PATH-shim runs
   (FAIL without the escape hatch; DEGRADED line with it; REQUIRE wins).
3. **Cross-version pinning**: temporarily corrupt one non-golden version's
   normalized stream inside the loop (e.g. for `kv == 1.36` append a line
   `mutation: true` to the normalized variable before the diff) → gate must
   FAIL naming fixture + 1.36 vs base golden. Revert.

**Verify**: after reverts, `git status --short` shows only intended plan
files; full gate `==> PASS`.

## Test plan

The gate is the test suite; this plan's tests are its new checks plus their
mutation proofs (Step 6). Structural pattern for new/edited sections: the
guarded negative render at `scripts/lint-library.sh:256-273`. Final proof:

- `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh`
  → `==> PASS`, exit 0.
- `git diff --exit-code tests/golden/` → exit 0.
- No CHANGELOG entry: developer-gate tooling only, no consumer-visible chart
  change — state this in the completion report.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` ends `==> PASS`, exit 0
- [ ] `git diff --exit-code tests/golden/` exits 0; `ls tests/golden/` unchanged (4 files)
- [ ] `grep -c 'validate_render ' scripts/lint-library.sh` ≥ 30 (helper + adoption sites)
- [ ] PATH-shim bare run (Step 4) exits 1 with `==> FAIL`
- [ ] PATH-shim `ALLOW_MISSING_VALIDATORS=1` run's last line contains `DEGRADED` and `tail -1 | grep -c '==> PASS'` → `0`
- [ ] All three Step 6 mutations demonstrated RED and reverted
- [ ] `shellcheck -x scripts/*.sh tests/render.sh` exits 0
- [ ] Only in-scope files modified (`git status`); `tests/schemas/` changes are vendor-script output only

## STOP conditions

Stop and report back (do not improvise) if:

- `git diff tests/schemas/` shows a PRE-EXISTING vendored schema file
  changing content after re-vendoring — upstream drifted; accepting it
  silently could change gate outcomes. Report the diff.
- A needed schema is absent from the datreeio catalog AND the affected leg
  cannot cleanly use `allow-missing` (e.g. the whole point of the leg is
  validating that Kind).
- Step 3's first full-gate run surfaces kubeconform failures in guardrail
  renders that look like REAL library bugs (not missing schemas) — that is a
  finding, not something to paper over with `allow-missing`.
- The three matrix versions do NOT render byte-identically at your base
  commit (Step 5's premise, verified free at `583b401`) — the cross-version
  assertion needs the override mechanism on day one; report which
  fixture/version diverges and why before proceeding.
- Any golden file changes.
- The live tool-detection block or matrix loop differs materially from the
  excerpts above.

## Maintenance notes

- When a future K8s version bump (`k8s-version-bump` skill) introduces a
  legitimately divergent render, create
  `tests/golden/<fixture>@<version>.yaml` manually from that version's
  normalized render; `UPDATE_GOLDEN` will maintain it thereafter.
- Every new guardrail section from now on should call `validate_render` in
  its success branch — reviewers should flag sections that don't.
- `allow-missing` call sites (if any) are debt: re-check the datreeio
  catalog periodically and vendor the schema when it appears.
- Reviewer scrutiny: helper must never be invoked inside `$(...)` (fail=1
  would be lost — the exact silent-thinning failure mode this plan removes);
  degraded final lines must not contain the `==> PASS` substring.
- Explicitly deferred: kubeconform for `helm install --dry-run` NOTES
  outputs (not manifest streams); CI workflow changes (plans/008).
