# Plan 005: Capability-gate the secondary Kinds (AuthorizationPolicy, GRPCRoute)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 583b401..HEAD -- platform-library/templates/_mtls.yaml platform-library/templates/_gateway-api.yaml platform-library/templates/_capabilities.tpl platform-library/templates/_app.yaml scripts/lint-library.sh`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug (correctness / design-invariant violation)
- **Planned at**: commit `583b401`, 2026-07-28

## Why this matters

Design invariant 2 of this library (repo `CLAUDE.md`): *never emit an
apiVersion the cluster doesn't serve; skipped Kinds are warned in NOTES.*
Two CRD-backed Kinds violate it today. `AuthorizationPolicy`
(`_mtls.yaml:25`) and `GRPCRoute` (`_gateway-api.yaml:119`) ride the
capability gates of their *sibling* Kinds (`PeerAuthentication`, `HTTPRoute`)
but resolve their own apiVersion with
`platform.capabilities.apiVersionForOrDefault`, whose doctrine
(`_capabilities.tpl:193-199`) reserves it for always-present built-ins. On a
cluster that serves PeerAuthentication but not AuthorizationPolicy (or
HTTPRoute but not GRPCRoute — separate CRDs, independently installable), the
library renders an object with an unserved apiVersion: `helm install` fails at
apply time, or worse, GitOps pipelines with validation disabled carry a dead
object. The Kind also never appears in the NOTES `SKIPPED KINDS` warning, so
the failure is undiagnosable from the chart's own output. The lint gate's
anti-drift check (`scripts/lint-library.sh:812-824`) counts gate sites instead
of comparing names, so it structurally cannot catch this class of bug.

This plan is deliberately surgical: fix the two secondary-Kind call sites,
give both Kinds skip-with-NOTES behavior, and upgrade the anti-drift check to
a name-set comparison. The larger registry unification (survey finding P2)
builds on this later as a separate plan; do not attempt it here.

## Current state

Files and roles:

- `platform-library/templates/_mtls.yaml` — renders PeerAuthentication +
  AuthorizationPolicy when `mtls.enabled`. 44 lines total.
- `platform-library/templates/_gateway-api.yaml` — renders HTTPRoute +
  GRPCRoute when `gatewayApi.enabled` (+ per-route `.enabled`).
- `platform-library/templates/_capabilities.tpl` — capability registry and
  helpers (`has`, `apiVersionFor`, `apiVersionForOrDefault`, `gatedKinds`,
  `gateOpen`, `skippedKinds`).
- `platform-library/templates/_app.yaml` — dispatcher; wraps whole feature
  templates in `gateOpen` gates (representative-Kind gating — stays as-is).
- `platform-library/templates/_notes.tpl` — turns
  `platform.capabilities.skippedKinds` into the operator-visible
  `SKIPPED KINDS` warning (with `(tried <group/versions>)` detail).
- `scripts/lint-library.sh` — the gate; anti-drift check at :812-824,
  negative render at :256-273, NOTES skipped-kinds checks at :767-810,
  Gateway API negotiation checks at :898-939.

### The two bugs

`_mtls.yaml:24-25` — AuthorizationPolicy renders unconditionally whenever
`mtls.enabled`, at a defaulted apiVersion:

```yaml
---
apiVersion: {{ include "platform.capabilities.apiVersionForOrDefault" (list . "AuthorizationPolicy") }}
kind: AuthorizationPolicy
```

`_gateway-api.yaml:119` — GRPCRoute (enabled via nested
`gatewayApi.grpcRoute.enabled`) defaults its apiVersion the same way:

```gotemplate
{{- $grpcApiVersion := coalesce $grpc.apiVersion $gw.apiVersion (include "platform.capabilities.apiVersionForOrDefault" (list . "GRPCRoute")) -}}
```

The `---` separators live at `_mtls.yaml:24` and `_gateway-api.yaml:153`; any
new guard must enclose them, or a skipped object leaves a dangling empty
document (the gate's negative-render section asserts no `{}`/empty docs).

### What is NOT a bug (do not "fix")

`_mtls.yaml:11` (PeerAuthentication) and `_gateway-api.yaml:18` (HTTPRoute)
also use `apiVersionForOrDefault`, but both are safe: the wrapper gates in
`_app.yaml` already proved availability before these templates run.
`_gateway-api.yaml:15-17` documents this:

```gotemplate
{{- /* gatewayApi.apiVersion is an explicit override only; when empty each route
       negotiates its own Kind (OrDefault is safe here: the wrapper gate in
       _app.yaml already proved HTTPRoute availability). */ -}}
```

`_mtls.yaml:11` lacks the equivalent comment — this plan adds one (comment
only, no behavior change).

### The doctrine (`_capabilities.tpl:193-199`)

> Use this [`apiVersionForOrDefault`] for always-present built-in Kinds…
> Use plain `apiVersionFor` (skip-if-absent) for CRDs and optional objects
> where a missing API must mean "do not render".

### Gate helpers as they exist today (`_capabilities.tpl:259-298`)

```gotemplate
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

Note both helpers look up the enabling block with a **single-key**
`index $top.Values <key>` — a dotted path like `gatewayApi.grpcRoute` cannot
work without a path-walking helper (Step 3).

The registry (`platform.capabilities.registry`, earlier in the same file)
already has both Kinds:

```yaml
GRPCRoute: ["gateway.networking.k8s.io/v1/GRPCRoute", "gateway.networking.k8s.io/v1alpha2/GRPCRoute"]
AuthorizationPolicy: ["security.istio.io/v1/AuthorizationPolicy", "security.istio.io/v1beta1/AuthorizationPolicy"]
```

Also relevant: `platform.capabilities.has` honors the force-assume list
`.Values.capabilities.apiVersions`, and a **bare** `group/version` entry there
matches ALL Kinds in that group (gvOnly logic, `_capabilities.tpl:34-38`).
This is why goldens will not change (see "Expected golden impact").

### `_app.yaml` gate sites (representative-Kind gating — unchanged by this plan)

```
24:{{- if include "platform.capabilities.gateOpen" (list . "Certificate") }}
36:{{- if include "platform.capabilities.gateOpen" (list . "PeerAuthentication") }}
66:{{- if include "platform.capabilities.gateOpen" (list . "HTTPRoute") }}
86:{{- if include "platform.capabilities.gateOpen" (list . "ServiceMonitor") }}
90:{{- if include "platform.capabilities.gateOpen" (list . "PodMonitor") }}
```

### The anti-drift check being upgraded (`scripts/lint-library.sh:812-824`)

```bash
gate_sites=$(grep -c 'platform.capabilities.gateOpen' "$LIB/templates/_app.yaml" || true)
gated_rows=$(sed -n '/define "platform.capabilities.gatedKinds"/,/^{{- end -}}/p' \
  "$LIB/templates/_capabilities.tpl" | grep -cE '^[A-Za-z]+: [A-Za-z]+' || true)
raw_gates=$(grep -c 'platform.capabilities.apiVersionFor' "$LIB/templates/_app.yaml" || true)
```

…passing iff `gate_sites>0 && gate_sites==gated_rows && raw_gates==0`. Two
problems: (a) counts, not names — a renamed/mismatched row passes; (b) after
this plan adds two registry rows with no matching `_app.yaml` gate (by
design), the count equality breaks. Note the row-matching regex
`^[A-Za-z]+: [A-Za-z]+` would also fail to match a dotted value
(`gatewayApi.grpcRoute`).

### Existing gate sections this plan must not break

- `:256-273` negative render: `full` fixture with
  `--set capabilities.apiVersions=null`, asserts NO line matches
  `^kind: (Certificate|HTTPRoute|GRPCRoute|PeerAuthentication|AuthorizationPolicy|ServiceMonitor|PodMonitor)$`
  and no empty `{}` documents. Passes today only because wrapper gates close
  the whole template; still passes after this plan (secondary Kinds now have
  their own guards too).
- `:767-810` NOTES SKIPPED KINDS checks; the comment near `:800-802` says the
  full fixture "enables all five gated features AND force-assumes every one of
  their APIs, so it must stay silent" — the "five" wording needs updating
  (Step 5), and the assertion itself stays green (see golden-impact analysis).
- `:898-939` Gateway API negotiation checks (pass full-GVK
  `--api-versions gateway.networking.k8s.io/v1beta1/HTTPRoute` and
  `.../v1alpha2/GRPCRoute` forms). These serve the GVK they test, so the new
  guards keep them green.
- Gate house rules (invariant 5): every assertion uses the guarded
  `if out=$(...)` idiom — a bare `var=$(...)` under `set -e` silently aborts
  the gate — and every new check must be proven able to go RED (mutation
  tests, Step 7).

### Fixture facts that determine golden impact

`tests/fixtures/full/values.yaml:82-87` force-assumes **bare** group/versions:

```yaml
capabilities:
  apiVersions:
    - gateway.networking.k8s.io/v1
    - cert-manager.io/v1
    - security.istio.io/v1beta1
    - monitoring.coreos.com/v1
```

Because bare entries match all Kinds in the group, plain `apiVersionFor` for
AuthorizationPolicy resolves to `security.istio.io/v1beta1` — exactly what the
golden contains today (`tests/golden/full.yaml:428`). The full fixture does
NOT enable `gatewayApi.grpcRoute` (only `httpRoute`), and no golden contains a
GRPCRoute. `mtls.enabled: true` with `allowedPrincipals` set. Therefore: **no
golden changes**.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| THE gate (definition of done) | `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` | ends `==> PASS`, exit 0 (~4 min) |
| Fast subset loop | `FIXTURES=minimal scripts/lint-library.sh` | ends `==> PASS (subset)` (~14s; never sufficient to claim done) |
| Render one fixture | `tests/render.sh full [--set k=v ...] [--api-versions g/v/K]` | manifests on stdout |
| Helm lint | `helm lint platform-library/` | 0 chart(s) failed |
| Shellcheck | `shellcheck -x scripts/*.sh tests/render.sh` | exit 0, no output |
| Golden diff check | `git diff --exit-code tests/golden/` | exit 0 (no diffs) |

Note: `tests/render.sh` and the `--api-versions` flag need the FULL
`group/version/Kind` form; a bare `group/version` on the CLI silently skips
objects. Only the `capabilities.apiVersions` values list accepts bare
group/version.

## Suggested executor toolkit

If these project skills exist in your environment, use them:
- `.claude/skills/capability-gates` — read before touching
  `_capabilities.tpl` or apiVersion negotiation.
- `.claude/skills/template-house-style` — house rules for `_*.yaml`/`_*.tpl`
  edits.
- `.claude/skills/validate-factory` — how to decide the work is done.

## Scope

**In scope** (the only files you should modify):
- `platform-library/templates/_mtls.yaml`
- `platform-library/templates/_gateway-api.yaml`
- `platform-library/templates/_capabilities.tpl`
- `scripts/lint-library.sh`
- `CHANGELOG.md` (`[Unreleased]` entry)

**Out of scope** (do NOT touch, even though they look related):
- `platform-library/templates/_app.yaml` — representative-Kind wrapper gating
  stays exactly as-is; a future registry-unification plan owns any redesign.
- `platform-library/values.schema.reference.json` — this plan adds NO new
  values keys, so no schema change (and no `values-contract-change` flow).
- `tests/golden/*.yaml` — must not change; never run `UPDATE_GOLDEN=1` for
  this plan.
- `platform-library/templates/_notes.tpl` — the SKIPPED KINDS warning already
  reads `skippedKinds`; it needs no edit.
- Escape-hatch NOTES warnings, extraObjects gating (separate findings/plans).

## Git workflow

- Branch: `advisor/005-capability-gate-secondary-kinds` off `main`.
- Conventional Commits, e.g.
  `fix(library): capability-gate AuthorizationPolicy and GRPCRoute individually`.
- Repo rule is PR-only main with squash-merge; do NOT push or open a PR
  unless the operator instructed it.

## Steps

### Step 1: Guard AuthorizationPolicy in `_mtls.yaml`

Replace lines 24-25 area so the AuthorizationPolicy document (INCLUDING the
`---` at line 24) only renders when its own API is served, and add the
justifying comment for PeerAuthentication at line 11. Target shape:

```gotemplate
{{- /* OrDefault is safe for PeerAuthentication: the wrapper gate in _app.yaml
       already proved its availability before this template runs. */}}
apiVersion: {{ include "platform.capabilities.apiVersionForOrDefault" (list . "PeerAuthentication") }}
kind: PeerAuthentication
...
      {{- include "platform.selectorLabels" . | nindent 6 }}
{{- /* AuthorizationPolicy is a SEPARATE CRD from PeerAuthentication; the
       wrapper gate proved only the latter. Skip-if-absent per the
       apiVersionFor doctrine — a skipped Kind surfaces in NOTES via the
       gatedKinds row added alongside this guard. */}}
{{- $authzApi := include "platform.capabilities.apiVersionFor" (list . "AuthorizationPolicy") -}}
{{- if $authzApi }}
---
apiVersion: {{ $authzApi }}
kind: AuthorizationPolicy
...
        {{- toYaml $principals | nindent 8 }}
{{- end }}
{{- end }}
{{- end }}
```

Keep the principals validation (`_mtls.yaml:3-10`) OUTSIDE the new guard:
misconfiguration must still fail closed even when the object would be skipped.

**Verify**:
`tests/render.sh full --set capabilities.apiVersions=null --api-versions security.istio.io/v1beta1/PeerAuthentication | grep '^kind: '`
→ output contains `kind: PeerAuthentication`, does NOT contain
`kind: AuthorizationPolicy`. Then
`tests/render.sh full | grep -c 'kind: AuthorizationPolicy'` → `1`
(fixture force-assume still renders it).

### Step 2: Guard GRPCRoute in `_gateway-api.yaml`

Change line 119 from `apiVersionForOrDefault` to `apiVersionFor`, and wrap the
GRPCRoute document (INCLUDING the `---` at line 153) in a guard on the
resolved version. Explicit consumer overrides (`grpcRoute.apiVersion`,
`gatewayApi.apiVersion`) still force emission — that is the documented escape
hatch, keep it. Target shape:

```gotemplate
{{- /* Explicit apiVersion overrides force emission; otherwise negotiate
       GRPCRoute's own API (HTTPRoute availability does not prove GRPCRoute —
       they are separate CRDs). Empty means skip; NOTES warns via gatedKinds. */ -}}
{{- $grpcApiVersion := coalesce $grpc.apiVersion $gw.apiVersion (include "platform.capabilities.apiVersionFor" (list . "GRPCRoute")) -}}
```

then, keeping all the existing validation (`fail` on missing parentRefs etc.)
OUTSIDE the guard, wrap only the emission:

```gotemplate
{{- if $grpcApiVersion }}
---
apiVersion: {{ $grpcApiVersion }}
kind: GRPCRoute
...
{{ toYaml $spec | nindent 2 }}
{{- end }}
{{- end }}
```

(`coalesce` returns empty when all arguments are empty, so the `if` works.)

**Verify**:
`tests/render.sh full --set capabilities.apiVersions=null --set gatewayApi.grpcRoute.enabled=true --api-versions gateway.networking.k8s.io/v1/HTTPRoute | grep '^kind: '`
→ contains `kind: HTTPRoute`, does NOT contain `kind: GRPCRoute`. And the
override escape:
`tests/render.sh full --set capabilities.apiVersions=null --set gatewayApi.grpcRoute.enabled=true --set gatewayApi.grpcRoute.apiVersion=gateway.networking.k8s.io/v1 --api-versions gateway.networking.k8s.io/v1/HTTPRoute | grep -c '^kind: GRPCRoute'`
→ `1`.

### Step 3: Register both Kinds in `gatedKinds` + add a dotted-path enablement helper

3a. Add two rows to `platform.capabilities.gatedKinds`
(`_capabilities.tpl:259-265`):

```gotemplate
{{- define "platform.capabilities.gatedKinds" -}}
Certificate: certificate
PeerAuthentication: mtls
AuthorizationPolicy: mtls
HTTPRoute: gatewayApi
GRPCRoute: gatewayApi.grpcRoute
ServiceMonitor: serviceMonitor
PodMonitor: podMonitor
{{- end -}}
```

3b. The dotted value breaks the single-key `index $top.Values <key>` lookup in
`gateOpen` and `skippedKinds`. Add a helper next to them that walks a dotted
path and requires `.enabled` truthy at EVERY segment (so
`gatewayApi.grpcRoute` means `gatewayApi.enabled AND grpcRoute.enabled`,
matching the template's actual nesting; single-segment behavior is identical
to today). Target shape:

```gotemplate
{{/*
platform.capabilities.featureEnabled — "true" (else "") when the values block
at a (possibly dotted) path is enabled. Every segment must be a map with a
truthy .enabled: "gatewayApi.grpcRoute" requires gatewayApi.enabled AND
gatewayApi.grpcRoute.enabled, mirroring the template nesting.
Usage: include "platform.capabilities.featureEnabled" (list . "gatewayApi.grpcRoute")
*/}}
{{- define "platform.capabilities.featureEnabled" -}}
{{- $top := index . 0 -}}
{{- $node := $top.Values -}}
{{- $on := true -}}
{{- range $seg := splitList "." (index . 1) -}}
  {{- if $on -}}
    {{- if kindIs "map" $node -}}
      {{- $node = (index $node $seg) | default dict -}}
      {{- if not $node.enabled -}}{{- $on = false -}}{{- end -}}
    {{- else -}}
      {{- $on = false -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if $on -}}true{{- end -}}
{{- end -}}
```

3c. Rewire BOTH `gateOpen` and `skippedKinds` to use it (replacing their
`$block := index ... | default dict` + `$block.enabled` lines with
`include "platform.capabilities.featureEnabled" (list $top $valuesKey)`).
Update the `gatedKinds` doc comment to note values may be dotted paths.

**Verify**:
`tests/render.sh full | grep -c '^kind:'` → same object count as before Step 3
(run it before and after; the count must not change). Then NOTES behavior —
render NOTES the way the gate does (helm template has no --notes flag in
Helm 4):
`helm install t tests/fixtures/full --dry-run=client --set 'capabilities.apiVersions={security.istio.io/v1beta1/PeerAuthentication}' 2>/dev/null | grep -A6 'SKIPPED KINDS'`
→ lists `AuthorizationPolicy` (PeerAuthentication served, AuthorizationPolicy
not). If `helm install --dry-run` needs the deps built, run
`tests/render.sh full >/dev/null` first to populate `tests/fixtures/full/charts/`.

### Step 4: Upgrade the anti-drift check to a name-set comparison

Replace `scripts/lint-library.sh:812-824` with a name-set check. Semantics:

- Kinds gated in `_app.yaml` (extracted from `gateOpen` call sites) must be a
  **subset** of `gatedKinds` keys.
- The complement (`gatedKinds` keys minus `_app.yaml` gate kinds) must equal
  EXACTLY the documented secondary-Kind set: `AuthorizationPolicy GRPCRoute`
  (these are gated inside their feature templates, not in `_app.yaml`).
- Keep the existing `raw_gates==0` assertion (no bare `apiVersionFor` calls in
  `_app.yaml`).

Target shape (guarded idiom — no bare `var=$(cmd)` that can abort under
`set -e`; captures use `|| true`, decisions use `if`):

```bash
echo "==> capability gates: _app.yaml gate set vs gatedKinds registry (name-set, hf-XXX)"
# Kind names are the only "Quoted" capitalized tokens on gateOpen lines
# ("platform.capabilities.gateOpen" itself starts lowercase).
gate_kinds=$(grep 'platform.capabilities.gateOpen' "$LIB/templates/_app.yaml" \
  | grep -oE '"[A-Z][A-Za-z]+"' | tr -d '"' | LC_ALL=C sort -u || true)
gated_keys=$(sed -n '/define "platform.capabilities.gatedKinds"/,/^{{- end -}}/p' \
  "$LIB/templates/_capabilities.tpl" | grep -oE '^[A-Za-z]+:' | tr -d ':' \
  | LC_ALL=C sort -u || true)
raw_gates=$(grep -c 'platform.capabilities.apiVersionFor' "$LIB/templates/_app.yaml" || true)
secondary_expected=$(printf 'AuthorizationPolicy\nGRPCRoute\n')
if [[ -z "$gate_kinds" ]]; then
  echo "  FAIL: no gateOpen call sites found in _app.yaml"; fail=1
fi
unregistered=$(comm -23 <(printf '%s\n' "$gate_kinds") <(printf '%s\n' "$gated_keys") || true)
if [[ -n "$unregistered" ]]; then
  echo "  FAIL: gated in _app.yaml but missing from gatedKinds: $unregistered"; fail=1
else
  echo "  OK: every _app.yaml gate has a gatedKinds row"
fi
secondary=$(comm -13 <(printf '%s\n' "$gate_kinds") <(printf '%s\n' "$gated_keys") || true)
if [[ "$secondary" == "$secondary_expected" ]]; then
  echo "  OK: template-internal gates are exactly: AuthorizationPolicy GRPCRoute"
else
  echo "  FAIL: gatedKinds rows without an _app.yaml gate changed."
  echo "        expected exactly {AuthorizationPolicy, GRPCRoute}, got: $(echo "$secondary" | tr '\n' ' ')"
  echo "        New secondary Kinds must gate inside their template AND be added to this list."
  fail=1
fi
if [[ "$raw_gates" -eq 0 ]]; then
  echo "  OK: no raw apiVersionFor calls in _app.yaml"
else
  echo "  FAIL: _app.yaml must gate via gateOpen, found $raw_gates raw apiVersionFor call(s)"; fail=1
fi
```

Also update the "five gated features" comment near `:800-802` to describe the
new reality: 7 registry rows, 5 `_app.yaml` wrapper gates + 2
template-internal secondary gates.

**Verify**: `bash -n scripts/lint-library.sh` → exit 0, then
`FIXTURES=minimal scripts/lint-library.sh` → `==> PASS (subset)` (the subset
run exits before this section — it only proves nothing earlier broke; full
proof is Step 8).

### Step 5: Add negative renders + NOTES assertion for partial serving

Add a new gate section (model its structure and guarded idiom on the existing
negative render at `scripts/lint-library.sh:256-273`; place it nearby) with
these legs:

1. **AuthorizationPolicy absent when unserved** — render `full` with
   `--set capabilities.apiVersions=null --api-versions security.istio.io/v1beta1/PeerAuthentication`;
   assert `kind: PeerAuthentication` present AND `kind: AuthorizationPolicy`
   absent AND no `^\{\}\s*$` empty documents.
2. **GRPCRoute absent when unserved** — render `full` with
   `--set capabilities.apiVersions=null --set gatewayApi.grpcRoute.enabled=true --api-versions gateway.networking.k8s.io/v1/HTTPRoute`;
   assert `kind: HTTPRoute` present AND `kind: GRPCRoute` absent.
3. **Positive control (no over-skip)** — render `full` with
   `--set capabilities.apiVersions=null --api-versions security.istio.io/v1beta1/PeerAuthentication --api-versions security.istio.io/v1beta1/AuthorizationPolicy`;
   assert `kind: AuthorizationPolicy` present with
   `apiVersion: security.istio.io/v1beta1`.
4. **NOTES lists the skipped secondary Kind** — using the same
   `helm install --dry-run=client` technique as the existing NOTES sections at
   `:767-810` (reuse their helper if one exists), with force-assume
   `--set 'capabilities.apiVersions={security.istio.io/v1beta1/PeerAuthentication}'`,
   assert the NOTES output's SKIPPED KINDS block names `AuthorizationPolicy`.

Every leg: guarded `if out=$(...)` idiom, `fail=1` + descriptive `FAIL:` line
on the failing branch, `OK:` line on success.

**Verify**: `bash -n scripts/lint-library.sh` → exit 0;
`shellcheck -x scripts/lint-library.sh` → clean.

### Step 6: CHANGELOG entry

Under `## [Unreleased]` in `CHANGELOG.md` (replace "Nothing yet." if it is
still the only content), following the 2.1.0 section's style:

```markdown
### Fixed — capability negotiation

- `AuthorizationPolicy` and `GRPCRoute` are now capability-negotiated
  individually instead of riding the `PeerAuthentication`/`HTTPRoute` gates.
  **Behavior change:** on clusters that serve the sibling API but not these
  CRDs, the objects are now skipped (and named in the NOTES `SKIPPED KINDS`
  warning) instead of rendering an apiVersion the cluster does not serve and
  failing at apply time. Explicit `gatewayApi.apiVersion` /
  `gatewayApi.grpcRoute.apiVersion` overrides still force emission. The lint
  gate's capability anti-drift check now compares gate/registry Kind
  name-sets instead of counts.
```

**Verify**: `grep -n 'AuthorizationPolicy' CHANGELOG.md | head -3` → shows the
new entry under Unreleased.

### Step 7: Mutation tests — prove every new check can go RED

Run each mutation, confirm the gate FAILS with the expected message, then
revert the mutation (`git checkout -- <file>` restores; your fix commits from
Steps 1-5 must already be staged/committed so checkout doesn't destroy them —
commit first). For speed you may run only the relevant section by temporarily
executing the full script and checking its output; the full run is ~4 min.

1. Revert `_mtls.yaml`'s guard (change `apiVersionFor` back to
   `apiVersionForOrDefault` on the AuthorizationPolicy line and remove the
   `{{- if $authzApi }}`/`{{- end }}` pair) → Step 5 leg 1 must print
   `FAIL` (note: the OLD negative render at :256-273 does NOT catch this —
   with zero APIs served the wrapper gate closes the whole template; that is
   exactly why the partial-serving legs exist). Revert.
2. Same for `_gateway-api.yaml:119` (back to `apiVersionForOrDefault` inside
   the coalesce) → Step 5 leg 2 must print `FAIL`. Revert.
3. Delete the `AuthorizationPolicy: mtls` row from `gatedKinds` → Step 4's
   secondary-set check must print `FAIL` (got only GRPCRoute). Revert.
4. Add a bogus row `FooBar: fooBar` to `gatedKinds` → Step 4 must print
   `FAIL` (unexpected secondary). Revert.

**Verify**: after all reverts, `git status --short` shows only the intended
plan changes; `git diff` matches your committed fix.

### Step 8: Full gate + golden check

**Verify**:
`REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh`
→ ends `==> PASS`, exit 0. Then `git diff --exit-code tests/golden/` → exit 0
(zero golden diffs). Then `helm lint platform-library/` → passes, and
`shellcheck -x scripts/*.sh tests/render.sh` → clean.

## Test plan

All new tests are lint-gate sections (this repo's test idiom — there is no
unit-test framework for templates):

- Partial-serving negative renders for both secondary Kinds (Step 5, legs
  1-2) — the regression tests for this exact bug class.
- Positive control against over-skipping (leg 3).
- NOTES SKIPPED KINDS coverage for a secondary Kind (leg 4).
- Name-set anti-drift with subset + exact-complement semantics (Step 4).
- Mutation-proofs for each (Step 7) — required by design invariant 5.
- Structural pattern to model on: the guarded negative render at
  `scripts/lint-library.sh:256-273`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` ends `==> PASS`, exit 0
- [ ] `git diff --exit-code tests/golden/` exits 0 (no golden changes)
- [ ] `grep -c 'apiVersionForOrDefault' platform-library/templates/_mtls.yaml` → `1` (PeerAuthentication only)
- [ ] `grep -c 'apiVersionForOrDefault' platform-library/templates/_gateway-api.yaml` → `1` (HTTPRoute only)
- [ ] `grep -c ':' <(sed -n '/define "platform.capabilities.gatedKinds"/,/^{{- end -}}/p' platform-library/templates/_capabilities.tpl | grep -E '^[A-Za-z]+:')` → `7`
- [ ] `shellcheck -x scripts/*.sh tests/render.sh` exits 0
- [ ] `helm lint platform-library/` passes
- [ ] CHANGELOG `[Unreleased]` contains the AuthorizationPolicy/GRPCRoute entry
- [ ] All four Step 7 mutations were demonstrated RED and reverted
- [ ] No files outside the in-scope list modified (`git status`)

## STOP conditions

Stop and report back (do not improvise) if:

- Any file in `tests/golden/` shows a diff at any point — the analysis above
  says there must be none; a diff means an assumption
  (fixture force-assume matching, grpcRoute disabled in fixtures) is wrong.
- The live `gateOpen`/`skippedKinds`/`gatedKinds` definitions differ from the
  "Current state" excerpts (drift since `583b401`).
- The existing Gateway API negotiation sections (`lint-library.sh:898-939`)
  or NOTES sections (`:767-810`) fail after your change.
- A Step 7 mutation does NOT turn the gate RED — the new check is decorative;
  do not ship it.
- `helm install --dry-run=client` cannot render NOTES for leg 4 after
  reasonable dependency setup — report the exact error.
- You find yourself wanting to edit `_app.yaml` or the registry structure —
  that is the out-of-scope unification work.

## Maintenance notes

- Future secondary Kinds (gated inside a feature template rather than in
  `_app.yaml`) must be added BOTH to `gatedKinds` and to the
  `secondary_expected` list in the anti-drift check — the check's FAIL
  message says so.
- The planned registry unification (survey P2, future plans/010) subsumes
  this fix's structure; when it lands, the `featureEnabled` helper and the
  hardcoded secondary set are the first things it should absorb.
- Reviewer scrutiny: confirm the `---` separators moved INSIDE the guards
  (dangling separators create empty documents), and that validation `fail`
  calls stayed OUTSIDE (fail-closed on misconfig even when skipped).
- Explicitly deferred: warning in NOTES when an explicit `apiVersion`
  override forces emission of an unserved API (escape-hatch warning work,
  survey finding #3's family).
