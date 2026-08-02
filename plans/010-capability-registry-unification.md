# 010 — Unify the four capability representations into one feature registry

- **Priority:** P2
- **Effort:** L (3 phases + a verification-only Phase 0)
- **Risk:** Medium — Phase 2 changes gating semantics for partially-installed clusters; fixtures shield the goldens, so the gate additions in Phase 3 are the real safety net
- **Depends on:** `plans/005-capability-gate-secondary-kinds.md` — the surgical fix for the two ungated secondary Kinds (AuthorizationPolicy, GRPCRoute) ships FIRST. That plan may not exist on disk yet (authored by a sibling planning stream); do not start 010 until it exists AND its PR is merged. Phase 0 below verifies this and reconciles against what 005 actually shipped.
- **Category:** architecture (capability negotiation model)
- **Planned at:** `583b401`

## Executor instructions

Read this whole plan first. You need Helm template mechanics and shell; every
repo-specific fact you need is inlined. Before editing, run the drift check:

```bash
git diff --stat 583b401..HEAD -- \
  platform-library/templates/_capabilities.tpl \
  platform-library/templates/_app.yaml \
  platform-library/templates/_mtls.yaml \
  platform-library/templates/_gateway-api.yaml \
  platform-library/templates/_notes.tpl \
  scripts/lint-library.sh tests/render.sh CHANGELOG.md
```

Changes to `_mtls.yaml` / `_gateway-api.yaml` / `lint-library.sh` since
`583b401` are EXPECTED (that's plan 005 landing). Read the landed 005 diff
carefully — Phase 0 records what it did; this plan's registry must encode
005's LANDED behavior, not this plan's guesses about it. Changes to other
files: re-verify the excerpts before editing.

Read the repo skills first: `capability-gates` (mandatory — this is its home
turf), `template-house-style`, `values-contract-change` (only if you end up
touching values keys — this plan should not), `validate-factory`.

## Why this matters

Capability negotiation (design invariant 2: never emit an apiVersion the
cluster doesn't serve) is described as registry-driven, but its semantics live
in FOUR representations inside `_capabilities.tpl`:

1. the Kind → ordered-apiVersion registry (`:76-176`),
2. a static built-in API-group classification feeding `isStable` (`:222-233`),
3. a feature → single-representative-Kind gate table `gatedKinds` (`:259-265`),
4. a separate cluster-scoped Kind list (`:304-306`).

Representation 3 is the structural hole: one values block maps to ONE
representative Kind, but two generators emit Kind SETS — mtls emits
PeerAuthentication + AuthorizationPolicy, gatewayApi emits HTTPRoute +
GRPCRoute. The abstraction cannot say "this feature emits this set of
independently gated Kinds", which is exactly how the two OrDefault bugs
(survey finding #2, fixed by plan 005) slipped through: the gate proved the
representative's API and the secondary Kind rode along unchecked, invisible to
`skippedKinds`/NOTES. The anti-drift check (`scripts/lint-library.sh:816-824`)
compares only COUNTS (gate sites vs table rows), so a Kind added to a
generator but not to the table is structurally undetectable.

This plan replaces the gate table with one structured feature registry where
each feature declares its full emitted-Kind set plus a composition policy
(**atomic** = all-or-nothing, **independent** = per-Kind skip), derives
`gateOpen`/`skippedKinds`/NOTES from it, and upgrades the anti-drift check
from count comparison to content comparison.

## Current state (verified at `583b401`)

### The gate table and its consumers (`_capabilities.tpl:259-298`)

```
{{- define "platform.capabilities.gatedKinds" -}}
Certificate: certificate
PeerAuthentication: mtls
HTTPRoute: gatewayApi
ServiceMonitor: serviceMonitor
PodMonitor: podMonitor
{{- end -}}

{{- define "platform.capabilities.gateOpen" -}}
{{- $top := index . 0 -}}
{{- $kind := index . 1 -}}
{{- $gated := fromYaml (include "platform.capabilities.gatedKinds" $top) -}}
{{- $block := (index $top.Values (index $gated $kind)) | default dict -}}
{{- if and $block.enabled (include "platform.capabilities.apiVersionFor" (list $top $kind)) -}}true{{- end -}}
{{- end -}}

{{- define "platform.capabilities.skippedKinds" -}}
{{- $top := . -}}
{{- $skipped := list -}}
{{- range $kind, $valuesKey := fromYaml (include "platform.capabilities.gatedKinds" $top) -}}
  {{- $block := (index $top.Values $valuesKey) | default dict -}}
  {{- if and $block.enabled (not (include "platform.capabilities.apiVersionFor" (list $top $kind))) -}}
    {{- $skipped = append $skipped $kind -}}
  {{- end -}}
{{- end -}}
{{- join " " $skipped -}}
{{- end -}}
```

Five gate sites in `_app.yaml` (`:24` Certificate, `:36` PeerAuthentication,
`:66` HTTPRoute, `:86` ServiceMonitor, `:90` PodMonitor), each of the form
`{{- if include "platform.capabilities.gateOpen" (list . "Certificate") }}`.
`_notes.tpl:17-24` turns `skippedKinds` into the `SKIPPED KINDS:` warning.
NOTES content never appears in `helm template` manifest output, so NOTES
changes cannot move goldens.

### The Kind registry checks FULL group/version/Kind (`:76-176`, head excerpt)

```
{{- define "platform.capabilities.registry" -}}
# ---- core/v1 (always GA) ----
Pod: ["v1/Pod"]
...
# ---- Gateway API CRDs ----
HTTPRoute: ["gateway.networking.k8s.io/v1/HTTPRoute", "gateway.networking.k8s.io/v1beta1/HTTPRoute"]
GRPCRoute: ["gateway.networking.k8s.io/v1/GRPCRoute", "gateway.networking.k8s.io/v1alpha2/GRPCRoute"]
...
{{- end -}}
```

Entries are full `group/version/Kind` strings, so against real cluster
capabilities (`--api-versions` with the full form) PeerAuthentication and
AuthorizationPolicy ARE distinguishable even though they share
`security.istio.io/v1`. The values-based force-assume list
(`.Values.capabilities.apiVersions`) matches on bare `group/version`, so a
force-assumed group opens BOTH Kinds of a pair. Both facts matter below.

### The secondary-Kind emissions (pre-005 state)

`_mtls.yaml`: when `mtls.enabled`, emits PeerAuthentication (`:11`) AND —
unconditionally, in the same define — AuthorizationPolicy (`:25`), both via
`apiVersionForOrDefault` (never-empty). The AuthorizationPolicy is what
enforces `allowedPrincipals`; rendering PeerAuthentication without it silently
DROPS the principal restriction — the pair is semantically atomic, and
"skip just the missing half" would be fail-open.

`_gateway-api.yaml:119`: GRPCRoute (only when `gatewayApi.grpcRoute.enabled`)
via `coalesce $grpc.apiVersion $gw.apiVersion (include
"platform.capabilities.apiVersionForOrDefault" (list . "GRPCRoute"))`. The
HTTPRoute site (`:18`) carries the comment that OrDefault is safe because the
wrapper gate already proved HTTPRoute — a proof that does NOT transfer to
GRPCRoute. The two routes are independently enabled sub-blocks — per-Kind skip
(independent), not all-or-nothing.

### The count-only anti-drift check (`scripts/lint-library.sh:812-824`)

```bash
gate_sites=$(grep -c 'platform.capabilities.gateOpen' "$LIB/templates/_app.yaml" || true)
gated_rows=$(sed -n '/define "platform.capabilities.gatedKinds"/,/^{{- end -}}/p' "$LIB/templates/_capabilities.tpl" |
  grep -cE '^[A-Za-z]+: [A-Za-z]+$' || true)
raw_gates=$(grep -c 'platform.capabilities.apiVersionFor' "$LIB/templates/_app.yaml" || true)
if [[ "$gate_sites" -gt 0 && "$gate_sites" -eq "$gated_rows" && "$raw_gates" -eq 0 ]]; then
  echo "  OK: all $gate_sites capability gates in _app.yaml are driven by the shared gatedKinds table"
else
  echo "  FAIL: capability gates ($gate_sites) and gatedKinds rows ($gated_rows) disagree, ..."; fail=1
fi
```

### Fixture shielding (why goldens stay green)

`tests/fixtures/full/values.yaml:82-87` force-assumes all four gated
group/versions (`gateway.networking.k8s.io/v1`, `cert-manager.io/v1`,
`security.istio.io/v1beta1`, `monitoring.coreos.com/v1`); bare-group matching
means every Kind of every pair is available in the full fixture. The other
three fixtures enable no gated features. So a pure restructuring — and even
Phase 2's semantic change — moves zero golden bytes. The NOTES full-fixture
silence check (`lint-library.sh:800-810`) must also stay green.

### Representations 2 and 4 have consumers outside `_capabilities.tpl`

`_util.tpl:36` (`isStable` decides OrDefault-vs-skip for `genericResource`)
and `_util.tpl:43,81` (`isClusterScoped` decides namespace stamping and the
`extraObjects` cluster-scope refusal). The cluster-scoped list also contains
Kinds absent from the Kind registry (Node, ComponentStatus). Folding these two
representations in is OPTIONAL Phase 4 territory — see Scope.

## Commands

| Command | Purpose |
|---|---|
| `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` | THE gate; must end `==> PASS` per phase. ~4 min; never run concurrently. |
| `FIXTURES=minimal scripts/lint-library.sh` | fast loop; never sufficient for done |
| `tests/render.sh <fixture> [--set k=v ...]` | render one fixture the gate's way |
| `helm template` with `--api-versions <group/version/Kind>` | the ONLY way to simulate per-Kind divergence (values force-assume can't); always full form — bare group/version silently skips |
| `git diff --stat tests/golden/` | must be empty every phase |
| `shellcheck -x scripts/lint-library.sh` | after every gate edit |

## Scope

**In scope**
- One structured `platform.capabilities.features` registry (feature →
  values key, composition policy, ordered Kind set) in `_capabilities.tpl`.
- `gateOpen` / `skippedKinds` derived from it; `gatedKinds` deleted.
- Composition semantics: atomic (mtls, certificate, serviceMonitor,
  podMonitor) vs independent (gatewayApi).
- NOTES `SKIPPED KINDS` coverage extended to secondary Kinds.
- Content-based anti-drift check replacing the count check, plus per-Kind
  negative renders, all guarded + mutation-proven.
- CHANGELOG `[Unreleased]` entry (NOTES/skip behavior is consumer-visible).

**Out of scope — smuggling temptations, refuse**
- Re-doing or "improving" plan 005's fix while unifying — reconcile with it
  (Phase 0), don't relitigate it.
- Folding `isStable` (rep. 2) and `clusterScoped` (rep. 4) into the registry —
  their consumers live in `_util.tpl`, the cluster list has non-registry Kinds
  (Node, ComponentStatus), and `extraObjects`/`extraManifests` behavior is a
  separate trust boundary (brainstorm P3). File a follow-up bead; a sketch is
  in Maintenance notes.
- Changing which versions the Kind registry prefers, or `apiVersionFor` /
  `apiVersionForOrDefault` internals.
- Making values force-assume Kind-aware (bare group/version matching is a
  documented consumer contract; changing it is a values-contract change).
- New consumer values keys of any sort.
- Touching `extraObjects`/`extraManifests` negotiation.
- `UPDATE_GOLDEN=1` for any reason.

## Git workflow

Branch `refactor/010-capability-registry` off `main` AFTER 005 is merged. One
commit per phase (`refactor(capabilities): ...` / `feat(capabilities): ...`
for Phase 2 since skip behavior is consumer-visible), PR to `main`,
squash-merge, `ci` green. No direct pushes to `main`, no AI attribution
trailers.

## Steps

### Phase 0 — verify and record the 005 baseline (no edits)

1. `ls plans/005-capability-gate-secondary-kinds.md` — must exist; read it.
2. Confirm its PR merged: `git log --oneline -20 -- platform-library/templates/_mtls.yaml platform-library/templates/_gateway-api.yaml`.
3. Record in the PR description for 010: which mechanism 005 chose per Kind
   (per-site `apiVersionFor` skip guard, gate extension, hard fail, NOTES
   wiring), and which gate checks it added. The features registry in Phase 2
   must reproduce 005's landed per-Kind availability behavior; where this plan
   and 005 disagree, **005's landed behavior wins** and this plan's text gets
   annotated, not the code bent to match this plan.
4. Baseline run: full gate `==> PASS` on the merge-base you branched from.

STOP if 005 is absent or unmerged.

### Phase 1 — introduce the features registry, derive everything, keep behavior identical (2 files)

Files: `_capabilities.tpl`, `scripts/lint-library.sh`.

1. In `_capabilities.tpl`, replace the `gatedKinds` define (and its comment
   block) with:

   ```
   {{/*
   platform.capabilities.features — the single source of truth for gated
   features: the values block that enables each one, the FULL set of Kinds its
   generator can emit (first Kind = representative, used at the _app.yaml gate
   site), and the composition policy:
     atomic      — all-or-nothing: the feature renders only when EVERY Kind in
                   the set has a served/force-assumed API (fail closed: e.g.
                   PeerAuthentication without AuthorizationPolicy would drop
                   the principal restriction and be MORE permissive).
     independent — per-Kind skip: each Kind renders iff requested by its own
                   sub-block AND its API is available.
   The body must stay LITERAL YAML in exactly this shape — the lint gate
   parses it with sed/grep (anti-drift content check).
   */}}
   {{- define "platform.capabilities.features" -}}
   certificate:
     composition: atomic
     kinds: [Certificate]
   mtls:
     composition: atomic
     kinds: [PeerAuthentication, AuthorizationPolicy]
   gatewayApi:
     composition: independent
     kinds: [HTTPRoute, GRPCRoute]
   serviceMonitor:
     composition: atomic
     kinds: [ServiceMonitor]
   podMonitor:
     composition: atomic
     kinds: [PodMonitor]
   {{- end -}}
   ```

2. Rewrite `gateOpen` to read `features`, **preserving Phase 1 semantics
   exactly** (representative-Kind check only — composition is NOT enforced
   yet): find the feature whose kinds contain the queried `$kind`; open iff
   its values block `.enabled` AND `apiVersionFor` for the QUERIED kind is
   non-empty. For the five representative Kinds the truth table is identical
   to today's; `_app.yaml` is untouched.

3. Rewrite `skippedKinds` to iterate features and, for each enabled feature,
   apply today's predicate to the REPRESENTATIVE kind only (kinds[0]). Output
   (space-delimited kind names) must be byte-identical to today for every
   input — Phase 1 must not change NOTES.

4. Update the anti-drift check in `lint-library.sh` to the content check
   (replace lines 812-824). Shape (adjust to taste, keep the guarded idiom —
   command substitutions carry `|| true`, decisions are explicit `if`s;
   remember a bare `var=$(...)` that fails under `set -e` aborts the gate
   silently):

   ```bash
   echo "==> capability anti-drift: features registry vs gate sites vs emitters (content)"
   features_block=$(sed -n '/define "platform.capabilities.features"/,/^{{- end -}}/p' "$LIB/templates/_capabilities.tpl" || true)
   all_kinds=$(grep -oE 'kinds: \[[^]]+\]' <<<"$features_block" | sed 's/kinds: //' | tr -d '[] ' | tr ',' '\n' || true)
   rep_kinds=$(grep -oE 'kinds: \[[^]]+\]' <<<"$features_block" | sed -E 's/kinds: \[([^,]+).*/\1/' || true)
   if [[ -z "$all_kinds" || -z "$rep_kinds" ]]; then
     echo "  FAIL: could not parse the features registry (literal-YAML shape contract broken)"; fail=1
   fi
   for kind in $rep_kinds; do   # every representative kind has a gateOpen site
     if ! grep -q "platform.capabilities.gateOpen\" (list . \"$kind\")" "$LIB/templates/_app.yaml"; then
       echo "  FAIL: representative Kind $kind has no gateOpen site in _app.yaml"; fail=1
     fi
   done
   for kind in $all_kinds; do   # every registered kind is actually emitted by a generator
     if ! grep -qE "^kind: $kind\$" "$LIB"/templates/_*.yaml; then
       echo "  FAIL: features registry lists $kind but no generator emits it"; fail=1
     fi
   done
   # reverse direction: every gate site's Kind is registered
   gate_kinds=$(grep -oE 'gateOpen" \(list \. "[A-Za-z]+"' "$LIB/templates/_app.yaml" | grep -oE '"[A-Za-z]+"$' | tr -d '"' || true)
   for kind in $gate_kinds; do
     if ! grep -qw "$kind" <<<"$all_kinds"; then
       echo "  FAIL: _app.yaml gates on $kind, which is not in the features registry"; fail=1
     fi
   done
   raw_gates=$(grep -c 'platform.capabilities.apiVersionFor' "$LIB/templates/_app.yaml" || true)
   if [[ "$raw_gates" -ne 0 ]]; then
     echo "  FAIL: _app.yaml gates on a raw apiVersionFor ($raw_gates) instead of gateOpen"; fail=1
   fi
   ```

   Reconcile with whatever gate checks 005 added — extend, don't duplicate or
   delete them.

5. **Mutation tests (all must go RED, then be reverted):**
   - Delete the `{{- if include "platform.capabilities.gateOpen" (list . "PodMonitor") }}` block from `_app.yaml` → representative-without-gate-site FAIL.
   - Add a bogus row to features (`fake:\n  composition: atomic\n  kinds: [FakeKind]`) → registered-but-never-emitted FAIL.
   - Remove `AuthorizationPolicy` from the mtls row → whichever 005 check or the emitted-Kind reverse check covers it must FAIL; if NOTHING goes red, your content check has a hole — fix it before proceeding.

6. Verify: full gate `==> PASS`; `git diff --stat tests/golden/` empty;
   `shellcheck -x scripts/lint-library.sh`. NOTES assertions
   (`lint-library.sh:767-810`) must pass UNMODIFIED — if they don't, Phase 1
   changed behavior; stop and fix. Commit.

### Phase 2 — enforce composition policy (3 files)

Files: `_capabilities.tpl`, `_mtls.yaml`, `_gateway-api.yaml`.

1. `gateOpen` becomes composition-aware. For the feature owning the queried
   kind:
   - **atomic**: open iff `block.enabled` AND EVERY kind in the set has
     `apiVersionFor` non-empty. Concretely: on a cluster serving
     PeerAuthentication but not AuthorizationPolicy, the whole mtls feature
     now skips (fail closed) instead of rendering an unrestricted-mtls
     half-pair.
   - **independent**: open iff `block.enabled` AND the QUERIED kind's API is
     available (unchanged for HTTPRoute). Secondary independent Kinds
     (GRPCRoute) keep 005's in-generator per-Kind skip; the registry's job is
     to make `skippedKinds`/NOTES and the anti-drift check see them.

2. `skippedKinds` becomes composition-aware. For each enabled feature:
   - atomic: if ANY kind in the set lacks an API, append ALL kinds of the set
     (the served-but-held-back ones are skipped output too — the operator must
     see that PeerAuthentication did not deploy and why the set held it back).
   - independent: append each REQUESTED kind whose API is missing. "Requested"
     for GRPCRoute means `gatewayApi.grpcRoute.enabled`; HTTPRoute is
     requested whenever the feature is enabled. Keep the requested-predicate
     table inside `skippedKinds` next to the features registry with a comment
     tying each predicate to its generator condition (`_gateway-api.yaml`
     `$grpc.enabled`).
   - Keep the output format (space-delimited Kind names) so `_notes.tpl` and
     its `(tried <versions>)` rendering are untouched. A held-back atomic kind
     will read `PeerAuthentication (tried security.istio.io/v1, ...)` — the
     versions listed are the ones probed; acceptable v1 wording. Do NOT
     redesign the NOTES format here.

3. `_mtls.yaml` / `_gateway-api.yaml`: with atomic gating proven upstream,
   005's per-site guards inside `_mtls.yaml` (if any) become redundant —
   LEAVE THEM IN PLACE as defense-in-depth unless they now double-report in
   NOTES; only remove something if a 005-added check forces it, and say so in
   the commit message. `_gateway-api.yaml`'s GRPCRoute per-Kind skip from 005
   stays — it IS the independent-composition mechanism. Expected edits here
   are nil-to-minimal; if you find yourself rewriting these generators, stop —
   you are out of scope.

4. Behavioral probes (helm template directly, full group/version/Kind forms —
   check first whether `tests/render.sh` passes `--api-versions` through; if
   it does, prefer it):
   - PeerAuth-only cluster: `--api-versions security.istio.io/v1/PeerAuthentication`
     with mtls enabled → output contains NEITHER `kind: PeerAuthentication`
     NOR `kind: AuthorizationPolicy`.
   - Both served → both render.
   - HTTPRoute served, GRPCRoute not, `grpcRoute.enabled=true` → HTTPRoute
     renders, GRPCRoute does not.
5. Verify: full gate `==> PASS`; `git diff --stat tests/golden/` empty (the
   full fixture force-assumes every relevant group/version, so composition
   changes move nothing — if a golden moves, something besides gating
   changed: STOP). Full-fixture NOTES silence (`lint-library.sh:800-810`)
   still green. Commit.

### Phase 3 — verification hardening + CHANGELOG (≤3 files)

Files: `scripts/lint-library.sh`, `CHANGELOG.md`, and `tests/render.sh` ONLY
if `--api-versions` passthrough must be added to script the probes.

1. Encode the Phase 2 probes as gate sections (guarded `if out=$(...)` idiom,
   diagnosable FAIL messages, stderr kept). At minimum:
   - atomic all-or-nothing: PeerAuth-only render contains neither mtls Kind;
     both-served render contains both.
   - independent per-Kind: GRPCRoute absent + enabled → HTTPRoute yes,
     GRPCRoute no.
   - NOTES: minimal fixture + `mtls.enabled=true` + `mtls.allowAllPrincipals=true`
     + no force-assume → `SKIPPED KINDS` names BOTH `PeerAuthentication` and
     `AuthorizationPolicy` (extends the existing `notes_of` pattern at
     `lint-library.sh:771-783`). Note: `notes_of` uses `helm install
     --dry-run=client`, which has no `--api-versions`, so the
     held-back-but-served NOTES case cannot be asserted there — assert the
     nothing-served case in NOTES and the divergence cases at manifest level.
2. **Mutation tests (RED then reverted, paste FAIL lines in the PR):**
   - Revert `gateOpen` to representative-only checking (or flip mtls to
     `composition: independent` in the registry) → atomic probe FAIL.
   - Remove `GRPCRoute` from the gatewayApi row → content anti-drift FAIL.
   - Make `skippedKinds` skip the atomic expansion → the new NOTES check FAIL.
3. `CHANGELOG.md` `[Unreleased]` (replace "Nothing yet."):

   ```markdown
   ### Changed
   - Capability gating is now driven by a single structured feature registry
     (`platform.capabilities.features`) declaring each feature's full emitted
     Kind set and a composition policy. `mtls` is atomic: on clusters that
     serve `PeerAuthentication` but not `AuthorizationPolicy`, the whole mTLS
     pair is now skipped (fail closed) instead of rendering a
     PeerAuthentication without its principal-restricting AuthorizationPolicy.
     `gatewayApi` routes negotiate per Kind. The NOTES `SKIPPED KINDS` warning
     now covers secondary Kinds (`AuthorizationPolicy`, `GRPCRoute`), including
     atomic Kinds held back by a missing partner API. (plans/010, follows
     plans/005.)
   ```

   Merge this wording with whatever CHANGELOG entry 005 already added —
   amend/extend rather than contradict.
4. Verify: `shellcheck -x scripts/lint-library.sh` (+ `tests/render.sh` if
   touched); full gate `==> PASS`; `git diff --stat tests/golden/` empty.
   Commit.

## Test plan

- Full gate per phase, `==> PASS`, and empty `git diff --stat tests/golden/`
  — golden impact is ZERO in every phase, justified by fixture shielding
  (full force-assumes all gated group/versions; minimal/stateful/daemon enable
  no gated features) and by NOTES being outside `helm template` output. Any
  golden movement is a defect in the change, enumerated exceptions: none.
- Phase 1: NOTES assertions pass unmodified (proves pure restructuring).
- Phase 2: the three behavioral probes by hand.
- Phase 3: probes as gate sections; three mutation tests RED; shellcheck
  clean.
- Existing negative render (`lint-library.sh:256-264`, nothing-served case)
  must stay green throughout — it already asserts none of the seven CRD Kinds
  render without force-assume.

## Done criteria (machine-checkable)

1. `grep -c 'define "platform.capabilities.gatedKinds"' platform-library/templates/_capabilities.tpl` → 0; `define "platform.capabilities.features"` → 1; no other file references `gatedKinds`.
2. Content anti-drift section present; count-based check gone.
3. All three Phase 3 mutation tests demonstrated RED (FAIL lines pasted in PR description) and reverted.
4. Full gate ends `==> PASS`; `git diff <merge-base>..HEAD -- tests/golden/` empty.
5. CHANGELOG `[Unreleased]` contains the Changed entry.
6. PR description records the Phase 0 reconciliation: what 005 shipped and how the registry encodes it.

## STOP conditions

- plans/005 does not exist on disk or is not merged — do not start.
- Any golden diff at any phase. This plan predicts zero; an unexplained diff
  means the restructuring changed behavior. STOP, never `UPDATE_GOLDEN=1`.
- The full-fixture NOTES silence check (`lint-library.sh:800-810`) goes red —
  `skippedKinds` is misfiring on served APIs.
- A new gate section cannot be made RED by its mutation test — the check is
  vacuous; fix before shipping.
- Phase 1's NOTES/`skippedKinds` output differs from baseline for ANY probed
  input — Phase 1 must be behavior-neutral.
- Reconciliation with 005 would require reverting or weakening a check 005
  added — escalate to a human (maintainer) instead of resolving unilaterally.

## Maintenance notes

- Adding a gated feature is now one registry row + one gate site + the
  generator; the content anti-drift check fails on any partial wiring,
  including forgotten secondary Kinds — the class of bug behind finding #2.
- The features define's literal-YAML shape is load-bearing for the gate's
  sed/grep parser; the template comment says so. If the shape must change,
  change the parser in the same commit and re-run all mutation tests.
- Follow-up bead (do NOT do here): fold representation 2 (`isStable` builtin
  group list) and representation 4 (cluster-scoped list) into per-Kind
  attributes of the Kind registry. Consumers to migrate: `_util.tpl:36,43,81`.
  Requires adding registry entries for Node and ComponentStatus, and belongs
  with the extraObjects/escape-hatch work (brainstorm P3), not here.
- Values force-assume remains bare group/version (documented consumer
  contract): a force-assumed group opens every Kind in that group. Real
  clusters negotiate per Kind. If Kind-aware force-assume is ever wanted,
  that is a values-contract change (minor bump, schema update) — separate
  plan.
