# Plan 003 — extraObjects: fail closed on unknown Kinds, NOTES visibility for unserved ones

Planned at: 583b401

## Executor instructions

Read this plan top to bottom before touching anything. Every excerpt was read
from the repo at commit `583b401` and is quoted verbatim. Drift check first:

```bash
git diff --stat 583b401..HEAD -- \
  platform-library/templates/_util.tpl \
  platform-library/templates/_capabilities.tpl \
  platform-library/templates/_notes.tpl \
  platform-library/values.yaml \
  scripts/lint-library.sh \
  CHANGELOG.md
```

If non-empty, re-anchor edits by CONTENT, not line number. If an excerpt no
longer exists, STOP and report. If plan 001 has already merged, `_notes.tpl`
will have new posture branches — that is expected drift; your NOTES branch goes
in a different location (see Step 3) and does not interact with plan 001's.

## Status

| Field | Value |
|---|---|
| Priority | P1 |
| Effort | M |
| Risk | MEDIUM (deliberate behavior change: silent drop → template-time fail for unknown Kinds) |
| Depends on | none |
| Category | correctness / fail-closed (design invariants 1 + 2) |
| Planned at | 583b401 |
| Finding | .uplift/survey-findings.md #5 (subset of structural problem P3) |

## Why this matters

`extraObjects` is the tier-2 escape hatch: a map of Kind → list of specs. Today
an entry can vanish from the render with **no error and no warning**, two ways:

1. **Unknown Kind** (typo, or a Kind the registry has never heard of):
   `platform.genericResource` finds no apiVersion and emits nothing. A consumer
   who writes `PodDisruptionBudgett` (typo) or `MyCompanyWidget` ships a chart
   that silently deploys less than their values say. Invariant 1 says ambiguous
   config fails at template time with a named error.
2. **Known CRD-backed Kind whose API the cluster does not serve** (e.g. a
   `VirtualService` on a cluster without Istio): skipping is CORRECT (invariant
   2 — never emit an unserved apiVersion), but it must be *visible*. The
   tier-1 gated Kinds already get exactly this treatment via the
   `SKIPPED KINDS` NOTES warning; extraObjects entries get nothing.

The fix keeps the two cases distinct: unknown = fail (nobody can negotiate an
apiVersion for a Kind that does not exist in the registry — the consumer must
pin one or use `extraManifests`); known-but-unserved = skip + warn (same
contract as tier-1).

## Current state (verbatim excerpts @ 583b401)

`platform-library/templates/_util.tpl:30-69`, `platform.genericResource` — the
silent-drop mechanism. Note: `platform.extraObjects` (line 85) is its ONLY
caller in the library (verified by grep at 583b401), so changes scoped to the
extraObjects loop cannot affect tier-1 generators.

```
{{- define "platform.genericResource" -}}
{{- $top := .root -}}
{{- $kind := .kind -}}
{{- $res := .resource -}}
{{- $api := $res.apiVersion -}}
{{- if not $api -}}
  {{- if include "platform.capabilities.isStable" (list $top $kind) -}}
    {{- $api = include "platform.capabilities.apiVersionForOrDefault" (list $top $kind) -}}
  {{- else -}}
    {{- $api = include "platform.capabilities.apiVersionFor" (list $top $kind) -}}
  {{- end -}}
{{- end -}}
{{- if $api -}}
...
{{- end -}}
{{- end -}}
```

The `{{- if $api -}}` guard is where both an unknown Kind and an unserved CRD
Kind become empty output. Semantics of the helpers it calls
(`_capabilities.tpl`): `isStable` returns truthy for built-in API groups;
`apiVersionForOrDefault` always returns something for registry Kinds (falls
back to first preference — safe for stable built-ins only); `apiVersionFor`
returns "" when the API is neither served nor force-assumed. For a Kind absent
from the registry BOTH return "" — that is the unknown-Kind path.

`platform-library/templates/_util.tpl:76-92`, `platform.extraObjects` — where
the new fail guard goes:

```
{{- define "platform.extraObjects" -}}
{{- $top := . -}}
{{- $allowCluster := .Values.allowClusterScopedExtras | default false -}}
{{- range $kind, $list := (.Values.extraObjects | default dict) }}
{{- range $res := $list }}
{{- $clusterScoped := or (include "platform.capabilities.isClusterScoped" $kind) (and (hasKey $res "clusterScoped") $res.clusterScoped) -}}
{{- if and $clusterScoped (not $allowCluster) -}}
{{- fail (printf "extraObjects contains cluster-scoped Kind %q (name %q), which is refused by default. Set allowClusterScopedExtras=true to render cluster-scoped objects from extraObjects." $kind ($res.name | default "")) -}}
{{- end -}}
{{- $rendered := include "platform.genericResource" (dict "root" $top "kind" $kind "resource" $res) | trim }}
{{- if $rendered }}
---
{{ $rendered }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
```

The pattern for the new skipped-extras helper —
`platform.capabilities.skippedKinds` (`_capabilities.tpl:288-298`):

```
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

The NOTES branch pattern to mirror — `_notes.tpl:17-24`:

```
{{- $skipped := include "platform.capabilities.skippedKinds" $top | trim -}}
{{- if $skipped -}}
{{- $details := list -}}
{{- range $kind := splitList " " $skipped -}}
{{- $details = append $details (printf "%s (tried %s)" $kind (include "platform.capabilities.apiVersionsFor" (list $top $kind))) -}}
{{- end -}}
{{- $warnings = append $warnings (printf "SKIPPED KINDS: enabled in values but NOT rendered, because the target cluster does not serve their API: %s. NOTHING was deployed for them. Install the CRDs, or — if the CRDs exist but are invisible at render time (e.g. `helm template` without a cluster) — force-assume the API via capabilities.apiVersions or `--api-versions`." (join "; " $details)) -}}
{{- end -}}
```

Compatibility facts:
- `tests/fixtures/full/values.yaml` extraObjects are ALL stable built-in Kinds
  (Role, RoleBinding, ServiceAccount, ClusterRole, PriorityClass,
  ResourceQuota, ConfigMap) → all in-registry and stable → neither the new
  fail nor the new warning fires on any fixture → **zero golden impact**.
- An entry with an explicit per-entry `apiVersion` bypasses negotiation today
  (`$api := $res.apiVersion` short-circuits) and renders verbatim. This plan
  KEEPS that: explicit pin = consumer takes responsibility. It is also the
  documented escape for unknown Kinds after the fail lands.
- Schema: `values.schema.reference.json` models `extraObjects` as
  `additionalProperties` → array of objects requiring `name`, with `apiVersion`
  permitted per item; root of the entry map takes any Kind key. Every `--set-json`
  in the test plan passes helm-side schema validation.
- Registry fact used by the tests: `VirtualService` is a registry CRD Kind with
  three preferences (`networking.istio.io/v1`, `/v1beta1`, `/v1alpha3`), not
  force-assumed by the minimal fixture, so it is the canonical
  known-but-unserved probe. `platform.capabilities.apiVersionsFor` (quoted
  header at `_capabilities.tpl:236-239`) renders the comma-joined "tried" list.

## Commands

| Command | Purpose |
|---|---|
| `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` | THE gate; must end `==> PASS` |
| `tests/render.sh minimal --set-json 'extraObjects={"WidgetFrobber":[{"name":"w1"}]}'` | negative: must fail with the named unknown-Kind error |
| `tests/render.sh minimal --set-json 'extraObjects={"WidgetFrobber":[{"name":"w1","apiVersion":"widgets.example.io/v1"}]}'` | positive: explicit pin renders verbatim |
| `tests/render.sh minimal --set-json 'extraObjects={"VirtualService":[{"name":"vs1"}]}'` | known-but-unserved: renders successfully WITHOUT a VirtualService doc |
| `shellcheck -x scripts/lint-library.sh` | after gate edits |

## Suggested executor toolkit

Helm 4.x, kubeconform, check-jsonschema, shellcheck. No cluster. Skills:
`template-house-style`, `capability-gates` (you are touching
`_capabilities.tpl`), `extra-objects-runbook`, `validate-factory`.

## Scope

**In scope**
- `platform-library/templates/_util.tpl` — unknown-Kind fail in
  `platform.extraObjects` only.
- `platform-library/templates/_capabilities.tpl` — new helper
  `platform.capabilities.skippedExtraObjects` (additive; no existing define
  touched).
- `platform-library/templates/_notes.tpl` — one new warning branch.
- `platform-library/values.yaml` — comment on `extraObjects` documenting the
  new contract (comment only).
- `scripts/lint-library.sh` — new checks.
- `CHANGELOG.md` — `[Unreleased]` entry with a `**Behavior change:**` flag.

**Out of scope (do NOT touch)**
- `platform.genericResource` itself — the fail lives in the extraObjects loop
  so the generic renderer stays a pure function (and future callers decide
  their own policy).
- `extraManifests` (finding #7 / structural P3 handles its cluster-scope
  bypass; different plan).
- Warning on pinned-but-unserved apiVersions (P3 scope; explicitly deferred).
- The `gatedKinds`/`gateOpen` anti-drift machinery (`lint-library.sh:816-824`)
  — the new helper is not a gate and must NOT be added to that count check.
- `values.schema.reference.json` — no shape change (apiVersion per item is
  already permitted).

## Git workflow

Branch off `main` (e.g. `fix/extraobjects-fail-closed`). One commit:
`fix(extraObjects): fail closed on unknown Kinds; warn in NOTES for unserved ones`.
PR to `main`, CI green, squash-merge. Never push directly to `main`.

## Steps

### Step 1 — unknown-Kind fail in `platform.extraObjects`

In `_util.tpl`, inside `define "platform.extraObjects"`:

1. After the line
   `{{- $allowCluster := .Values.allowClusterScopedExtras | default false -}}`
   add (parse the registry ONCE, outside both ranges):

```
{{- $registryTable := fromYaml (include "platform.capabilities.registry" $top) -}}
```

2. Inside the inner `{{- range $res := $list }}`, immediately BEFORE the
   `$clusterScoped` line, add:

```
{{- if and (not (hasKey $registryTable $kind)) (not $res.apiVersion) -}}
{{- fail (printf "extraObjects contains unknown Kind %q (name %q): it is not in the platform capability registry, so its apiVersion cannot be negotiated and the object would be silently dropped. Set apiVersion explicitly on the entry to render it verbatim, or move it to extraManifests." $kind ($res.name | default "")) -}}
{{- end -}}
```

Design notes:
- Message follows house-style rule 7 (names the offending values path shape,
  states two concrete fixes) and mirrors the adjacent cluster-scope fail's
  voice.
- Ordering: unknown-Kind fires before the cluster-scope fail. They cannot
  collide for registry Kinds (ClusterRole etc. are in the registry), so the
  existing gate check that expects the ClusterRole message
  (`lint-library.sh:545-551`) is unaffected.
- `hasKey` on the parsed registry map is the same membership test the
  capability helpers use internally.

**Verify:** the negative and positive commands from the Commands table.

### Step 2 — `platform.capabilities.skippedExtraObjects` helper

In `_capabilities.tpl`, insert after the `skippedKinds` define (ends line 298)
and before the `clusterScoped` define (line 304):

```
{{/*
platform.capabilities.skippedExtraObjects — space-delimited "Kind/name" entries
from .Values.extraObjects that are in the capability registry but whose API is
neither served nor force-assumed and that carry no explicit apiVersion, so
platform.genericResource rendered NOTHING for them. The tier-2 mirror of
platform.capabilities.skippedKinds; platform.notes turns it into a WARNING.
Usage: include "platform.capabilities.skippedExtraObjects" $top
*/}}
{{- define "platform.capabilities.skippedExtraObjects" -}}
{{- $top := . -}}
{{- $registry := fromYaml (include "platform.capabilities.registry" $top) -}}
{{- $skipped := list -}}
{{- range $kind, $list := ($top.Values.extraObjects | default dict) -}}
{{- if and (hasKey $registry $kind) (not (include "platform.capabilities.isStable" (list $top $kind))) (not (include "platform.capabilities.apiVersionFor" (list $top $kind))) -}}
{{- range $res := $list -}}
{{- if not $res.apiVersion -}}
{{- $skipped = append $skipped (printf "%s/%s" $kind ($res.name | default "")) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- join " " $skipped -}}
{{- end -}}
```

Predicate rationale (must exactly complement what renders):
- in-registry — unknown Kinds now FAIL in Step 1, never reach here;
- not stable — stable built-ins resolve via `apiVersionForOrDefault`, which
  always returns a version, so they always render;
- `apiVersionFor` empty — the API is neither served nor force-assumed;
- no per-entry `apiVersion` — pinned entries render verbatim regardless.
`Kind/name` is safe to join/split on spaces and split on `/` because K8s
object names cannot contain either character.

### Step 3 — NOTES branch

In `_notes.tpl`, insert immediately AFTER the `SKIPPED KINDS` branch (the
`{{- end -}}` at line 24, directly before the
`{{- if and .Values.ingress.enabled ...` branch):

```
{{- $skippedExtras := include "platform.capabilities.skippedExtraObjects" $top | trim -}}
{{- if $skippedExtras -}}
{{- $details := list -}}
{{- range $entry := splitList " " $skippedExtras -}}
{{- $kind := index (splitList "/" $entry) 0 -}}
{{- $details = append $details (printf "%s (tried %s)" $entry (include "platform.capabilities.apiVersionsFor" (list $top $kind))) -}}
{{- end -}}
{{- $warnings = append $warnings (printf "SKIPPED EXTRA OBJECTS: listed in extraObjects but NOT rendered, because the target cluster does not serve their API: %s. NOTHING was deployed for them. Install the CRDs, force-assume the API via capabilities.apiVersions or `--api-versions`, or set apiVersion explicitly on the entry." (join "; " $details)) -}}
{{- end -}}
```

(The inner `$details`/`$kind` variables are block-scoped inside the `if`; the
earlier SKIPPED KINDS branch's identically named variables are in their own
block — no clash. This matches the file's existing style exactly.)

### Step 4 — gate assertions (guarded idiom, invariant 5)

Two locations.

**4a. Render-path checks** — in the "posture guardrails" section, insert AFTER
the cluster-scoped-extras check (block at `lint-library.sh:544-551` ending
`  FAIL: gate=false failed without the expected message"; ...` and its `fi`)
and BEFORE the `# secret.existingSecret conflicts...` comment:

```bash
# extraObjects with a Kind the registry does not know must fail closed, not
# silently drop the object.
if out=$("$RENDER" minimal --set-json 'extraObjects={"WidgetFrobber":[{"name":"w1"}]}' 2>&1); then
  echo "  FAIL: render succeeded with an unknown extraObjects Kind (silent drop)"; fail=1
elif grep -q 'unknown Kind "WidgetFrobber"' <<<"$out"; then
  echo "  OK: unknown extraObjects Kind fails closed with actionable message"
else
  echo "  FAIL: unknown extraObjects Kind failed without the expected message"; echo "$out" | tail -3; fail=1
fi

# An explicit per-entry apiVersion is the documented escape: renders verbatim.
if out=$("$RENDER" minimal --set-json 'extraObjects={"WidgetFrobber":[{"name":"w1","apiVersion":"widgets.example.io/v1","spec":{"size":1}}]}' 2>&1); then
  if grep -q "kind: WidgetFrobber" <<<"$out" && grep -q "apiVersion: widgets.example.io/v1" <<<"$out"; then
    echo "  OK: unknown Kind with explicit apiVersion renders verbatim"
  else
    echo "  FAIL: pinned unknown Kind did not render as specified"; fail=1
  fi
else
  echo "  FAIL: render failed for pinned unknown extraObjects Kind"; echo "$out" | tail -3; fail=1
fi

# Known CRD Kind whose API is unserved still SKIPS (invariant 2) — the render
# must succeed and must not contain the object.
if out=$("$RENDER" minimal --set-json 'extraObjects={"VirtualService":[{"name":"vs1"}]}' 2>&1); then
  if grep -q "kind: VirtualService" <<<"$out"; then
    echo "  FAIL: unserved VirtualService extraObject rendered anyway"; fail=1
  else
    echo "  OK: unserved registry Kind in extraObjects is skipped from manifests"
  fi
else
  echo "  FAIL: render failed for unserved extraObjects Kind"; echo "$out" | tail -3; fail=1
fi
```

**4b. NOTES checks** — in the NOTES section, insert AFTER the full-fixture
SKIPPED KINDS silence check (block at `lint-library.sh:800-810` ending
`  FAIL: helm install --dry-run=client failed for full fixture"; ...` and its
`fi`) and BEFORE the `# Anti-drift:` comment (line 812):

```bash
# The skip above must be VISIBLE: unserved extraObjects entries get their own
# NOTES warning naming Kind/name and the apiVersions tried.
if out=$(notes_of minimal --set-json 'extraObjects={"VirtualService":[{"name":"vs1"}]}' 2>&1); then
  if grep -q "SKIPPED EXTRA OBJECTS" <<<"$out" &&
     grep -qF "VirtualService/vs1 (tried networking.istio.io/v1, networking.istio.io/v1beta1, networking.istio.io/v1alpha3)" <<<"$out"; then
    echo "  OK: unserved extraObjects entry is named in a NOTES warning with the apiVersions tried"
  else
    echo "  FAIL: unserved extraObjects entry produced no naming NOTES warning"; echo "$out" | tail -5; fail=1
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal with unserved extraObject"; echo "$out" | tail -5; fail=1
fi

# Force-assuming the API closes the gap: the object renders, warning disappears.
if out=$(notes_of minimal --set-json 'extraObjects={"VirtualService":[{"name":"vs1"}]}' \
  --set 'capabilities.apiVersions[0]=networking.istio.io/v1' 2>&1); then
  if grep -q "SKIPPED EXTRA OBJECTS" <<<"$out"; then
    echo "  FAIL: force-assumed extraObjects API still reported as skipped"; echo "$out" | tail -5; fail=1
  else
    echo "  OK: force-assumed apiVersion suppresses the skipped-extras warning"
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for minimal with force-assumed extraObject API"; echo "$out" | tail -5; fail=1
fi

# No false positives: full's extraObjects are all stable built-ins.
if out=$(notes_of full 2>&1); then
  if grep -q "SKIPPED EXTRA OBJECTS" <<<"$out"; then
    echo "  FAIL: full fixture warns about skipped extraObjects it actually renders"; echo "$out" | tail -5; fail=1
  else
    echo "  OK: full fixture (stable extraObjects) emits no skipped-extras warning"
  fi
else
  echo "  FAIL: helm install --dry-run=client failed for full fixture"; echo "$out" | tail -5; fail=1
fi
```

(`"SKIPPED EXTRA OBJECTS"` and `"SKIPPED KINDS"` are disjoint substrings —
neither contains the other — so none of the existing SKIPPED KINDS greps at
lines 771-810 interact with the new checks.)

**Verify:** `shellcheck -x scripts/lint-library.sh` clean, then the full gate.

### Step 5 — mutation tests (prove RED)

One at a time, full gate each, restore between:

1. Delete the Step 1 fail guard → 4a check 1 must go RED.
2. In Step 2's helper, invert `not $res.apiVersion` → 4b check 1 must go RED
   (entry no longer reported).
3. Delete the Step 3 NOTES branch → 4b check 1 must go RED.
4. In Step 1's guard, drop the `(not $res.apiVersion)` clause → 4a check 2
   (pinned escape) must go RED.

Record all RED runs in the PR description.

### Step 6 — values.yaml comment + CHANGELOG

On the `extraObjects:` key in `platform-library/values.yaml` (~line 656),
extend the comment (comment only, no shape change):

```yaml
# Kinds must exist in the platform capability registry; unknown Kinds fail at
# template time unless the entry sets apiVersion explicitly (rendered verbatim).
# Registry Kinds whose API the cluster does not serve are skipped with a NOTES warning.
```

Under `## [Unreleased]` in `CHANGELOG.md`:

```markdown
### Fixed — extraObjects fail-closed and skip visibility

- **Behavior change:** an `extraObjects` entry whose Kind is not in the
  platform capability registry now FAILS at template time with a named error
  (previously the object was silently dropped from the render). Set
  `apiVersion` explicitly on the entry to render it verbatim, or use
  `extraManifests`.
- Registry-known `extraObjects` entries whose API the cluster does not serve
  are still skipped (never emit an unserved apiVersion), but are now reported
  in a `SKIPPED EXTRA OBJECTS` NOTES warning naming each `Kind/name` and the
  apiVersions tried — the same contract tier-1 gated Kinds already have.
```

## Golden-file impact

**Zero.** All fixture extraObjects are stable built-in registry Kinds: the fail
cannot fire, the skip predicate cannot match, and NOTES never appears in
`helm template` output (`_notes.tpl:7-10`; gate invariant at
`lint-library.sh:756-765`). Done criterion: `git status tests/golden/` clean,
golden comparison passes without `UPDATE_GOLDEN`. Any golden diff = STOP.

## Test plan / verification

1. `shellcheck -x scripts/*.sh tests/render.sh` — clean.
2. `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh`
   ends `==> PASS` (exit 0); paste the tail in the PR. Subset runs skip the
   guardrail suite and are not sufficient.
3. All four Step 5 mutations demonstrated RED, restored, gate green.
4. Existing checks that must stay green (they share this code path): the
   cluster-scoped refusal (`lint-library.sh:545-551`), full-fixture render, and
   the whole SKIPPED KINDS block (771-810).
5. `git status`: only the six in-scope files modified.

Do not run the gate or `tests/render.sh` concurrently with sibling
agents/sessions (fixture-artifact race).

## STOP conditions

- Any golden diff.
- The full fixture fails to render after Step 1 — a fixture Kind is not in the
  registry after all; your registry-membership assumption broke. Report, do not
  "fix" by weakening the guard.
- The anti-drift gate count check (`lint-library.sh:816-824`) goes RED — you
  wired the new helper into `gateOpen`/`gatedKinds` machinery; it must stay
  separate.
- A consumer-visible key shape change starts to look necessary — that is the
  `values-contract-change` skill's territory; escalate.
- A mutation does not turn its check RED.
- Drift check shows the quoted regions changed since 583b401 (plan-001 NOTES
  additions excepted).

## Maintenance notes

- Deferred to structural problem P3 (do not scope-creep into this PR): warn on
  per-entry PINNED apiVersions that the cluster does not serve; structural
  `fromYaml` pass on `extraManifests`; extraManifests cluster-scope refusal
  (finding #7).
- When new Kinds are added to the capability registry, no change is needed
  here — both the fail predicate and the skip predicate read the registry.
- The `Kind/name` wire format between the helper and NOTES relies on K8s name
  charset (no spaces, no slashes). If a future caller needs namespaces in the
  details, switch to a YAML payload, not delimiter stacking.
