---
title: Conventions & Tricks
description: The Helm natives, built-ins, primitives, idioms, and deliberate hacks the library leans on — with source citations.
---

# Conventions & Tricks

This is the template craft behind `platform` — the Helm primitives, Sprig
functions, and deliberate idioms that make ~30 lines of consumer values turn into
hardened, capability-negotiated manifests. Every item cites its source under
`platform-library/templates/`. If you author a Kind or debug a render, read this
first; the patterns here are load-bearing, and several encode fixes for real P0
bugs.

:::tip Design invariant
Most of these are not style preferences — they are the mechanics of the six
design invariants (fail closed, capability negotiation, specific-beats-common,
goldens-are-contract, guarded gates, default-on hardening). Violating one is a
bug, not a taste call.
:::

## Library purity: `_*.yaml` vs `_*.tpl`

The chart is `type: library` and must never gain a non-underscore template file.

- `_*.yaml` — **object generators**, one `define "platform.<thing>"` each.
- `_*.tpl` — **helper-only** files (`_capabilities.tpl`, `_util.tpl`,
  `_helpers.tpl`, `_notes.tpl`).

A renderable (non-underscore) template would break `type: library` purity and make
the chart self-render. The consumer's *only* template file is
`templates/app.yaml` containing `{{ include "platform.render" . }}`.

## The `platform.emit` separator trick

Because everything renders from a **single** consumer template file, adjacent YAML
documents would merge into one (duplicate-key errors) without an explicit `---`
between them. `platform.emit` (`_util.tpl:14-20`) prefixes `---` to each
**non-empty** document:

```gotemplate
{{- define "platform.emit" -}}
{{- $content := . | trim -}}
{{- if $content }}
---
{{ $content }}
{{- end }}
{{- end -}}
```

The non-empty guard is the whole point: a generator that renders nothing (gated
out) must **not** emit a bare `---` with no body. Generators therefore never start
with their own `---`; `emit` adds it. The exception is a *multi-document*
generator, which puts `---` only *between* its own docs (`_mtls.yaml:24`,
`_gateway-api.yaml`).

## Map precedence: `range` + `set`, never bare `merge`

**Specific beats common.** Resource-specific values/labels/annotations must win
over `common*`/`global` on a key collision. Sprig's `merge` keeps the
**destination's** keys, so `merge $specific $common` wrongly lets `$common` lose
*and* `merge $common $specific` wrongly lets `$common` win — either way the naive
call is wrong. Two correct idioms:

```gotemplate
{{/* range + set: iterate common, set each only where specific hasn't */}}
{{- range $k, $v := $common }}{{- if not (hasKey $specific $k) }}
  {{- $_ := set $specific $k $v }}{{- end }}{{- end }}

{{/* or mergeOverwrite with the SPECIFIC map LAST so it overrides */}}
{{- $merged := mergeOverwrite (deepCopy $default) $specific -}}
```

`mergeOverwrite` (last map wins) backs the securityContext merge
(`_helpers.tpl:161`) and Gateway `specOverrides` (`_gateway-api.yaml:78,151`).
Always `deepCopy` the base first — `mergeOverwrite` mutates in place.

## Fail closed: `required` and prescriptive `fail`

Invalid or ambiguous config must fail at **template time** with a named error —
never render a dangling object and let the API server (or production) discover it.

```gotemplate
{{- required "extraObjects.<Kind>[].name is required" $spec.name -}}
{{- if not $ok }}{{ fail "mtls.mode must be STRICT|PERMISSIVE|DISABLE" }}{{ end -}}
```

Fail messages are **prescriptive**: they name the offending values path and state
the fix (models at `_helpers.tpl:111`, `_mtls.yaml:8`, `_util.tpl:83`). Every
`fail` is coupled to a negative test in `scripts/lint-library.sh` that greps its
message substring — the message and its test change together, and the check must
be proven able to go RED by reverting the guard.

## Calling conventions: list-unpack and named-dict helpers

A helper that needs more than `.` takes either a **positional list** or a
**named dict** — never assume `.` is root inside a multi-arg helper.

```gotemplate
{{/* positional: unpack with index . N */}}
{{- define "platform.capabilities.apiVersionFor" -}}
{{- $top := index . 0 -}}{{- $kind := index . 1 -}}
{{- end -}}
{{- include "platform.capabilities.apiVersionFor" (list $top "Role") -}}

{{/* named: dict for readability (_app.yaml:8,13) */}}
{{- include "platform.genericResource" (dict "root" $top "kind" "Role" "resource" $spec) -}}
```

The most common template bug in this codebase: reading `.Values` inside a
list-args helper where `.` is the **args list**, not root.

## The holder-dict idiom for computed values

Go templates can't reassign a variable across scope boundaries (a `{{- $x = … }}`
inside a `range` doesn't escape it). The workaround is a one-key dict you `set`:

```gotemplate
{{- $out := dict "value" "" -}}
{{- range $candidate := $prefs }}
  {{- if include "platform.capabilities.has" (list $top $candidate) }}
    {{- $_ := set $out "value" $candidate }}{{- end }}{{- end }}
{{- $out.value -}}
```

Used for negotiated apiVersions and other loop-computed values
(`_helpers.tpl:204,404`). Build lists the same way — `append` into a variable,
then a single `toYaml | nindent`.

## Rendering blocks cleanly

- **Strip control keys before emitting.** Probe and securityContext blocks carry
  an `enabled` flag that is not valid Kubernetes; render them with
  `omit ... "enabled"` (`_cronjob.yaml:56,82`).
- **Quote user scalars.** Any consumer-supplied scalar in an annotation/label
  value is `{{ $v | quote }}` — unquoted `true`/`123`/`y` become the wrong YAML
  type and can fail admission.
- **Numeric-capable fields via `printf "%v"`.** An image tag may be `1.24` (float)
  or `"1.24.0"` (string); `platform.image` uses `printf "%v"` so a bare-number tag
  doesn't render as `1.24` and pull the wrong image (`_helpers.tpl:119`).

## Capability negotiation as a primitive

The library never emits an apiVersion the cluster doesn't serve. Two helpers on
top of the `platform.capabilities.registry` table do the work:

- `platform.capabilities.has (list $top "group/version[/Kind]")` — unions live
  discovery (`.Capabilities.APIVersions.Has`) with the force-assume list at
  `.Values.capabilities.apiVersions`.
- `platform.capabilities.apiVersion (list $top $prefList)` — walks an ordered
  preference list, returns the first served `group/version` or `""`.

Built-ins use `apiVersionForOrDefault` (never empty — falls back to preferred GA);
CRDs use strict `apiVersionFor` (empty ⇒ skip). See
[How It Works](/docs/how-it-works/#capability-negotiation) for the decision flow
and [Capability Catalog](/docs/capability-catalog/) for the full registry.

:::danger The `--api-versions` exact-string trap
`helm template --api-versions` only satisfies the gate in the **full
`group/version/Kind`** form (`cert-manager.io/v1/Certificate`). Helm's
`.Capabilities.APIVersions.Has` is an exact-string membership test — a set
containing only `cert-manager.io/v1` never answers true for
`cert-manager.io/v1/Certificate`. The bare `group/version` flag produces the worst
failure mode: **clean exit 0, object silently missing.** Only the
`capabilities.apiVersions` *values* list accepts the bare form, because the library
also matches each entry against the queried Kind's `group/version`.
:::

## Hardening is default-on and per-container

PSS-restricted is evaluated **per container** — one unhardened sidecar fails
admission for the whole pod. So passthrough containers (init containers, sidecars)
get the same hardening pass as the main container:

```gotemplate
{{- include "platform.hardenContainers" (list $ctx $ctx.Values.initContainers.containers) -}}
```

`platform.hardenContainers` (`_helpers.tpl:153`) applies the restricted
securityContext to every container in the list, with **user-supplied keys winning**
via `mergeOverwrite $default $userSecurityContext` (user map last —
`_helpers.tpl:161`). It's applied at every container site: main workload, CronJob
containers (`_cronjob.yaml:74,77`), and init/sidecar passthrough (`_helpers.tpl:309`).

## Hook ordering and the distinct hook ServiceAccount

Pre-install hook Jobs depend on a script ConfigMap and a **distinctly named** hook
ServiceAccount (`<fullname>-preinstall`), weight-ordered below the Job
(`_configmap-script.yaml:32-34`, `_job-preinstall.yaml`, `platform.renderHookJob`).

The distinct name is not cosmetic. A **same-named** hook copy of the release SA
would let `helm.sh/hook-delete-policy: before-hook-creation` delete the **live** SA
at the start of every upgrade's hook phase, invalidating the bound tokens of
running pods. Two more hook facts that look like races but aren't:

- The ServiceAccount admission controller **always** looks up a pod's SA, even with
  `automountServiceAccountToken: false` — a missing SA is a hard admission failure,
  so "just omit the SA since automount is off" is invalid.
- `hook-succeeded` deletions run only **after every hook in the phase completes**
  (Helm loops hooks, then loops again to delete), so a ConfigMap at weight `-6`
  safely survives until a Job at `-5` finishes.

## Selector labels are immutable — `commonLabels` must never leak

`platform.selectorLabels` (`_helpers.tpl:74`; rationale at `:62-72`) is the
immutable subset — name + instance only. A Service/workload selector is immutable
on a live object, so a *mutable* label there (like `commonLabels`, which a consumer
can change) orphans the workload on the next `helm upgrade`.

```gotemplate
selector:
  {{- include "platform.selectorLabels" . | nindent 4 }}   # name + instance ONLY
```

Leaking `commonLabels` into a selector was a **P0 bug** (hf-7a1, fixed
2026-07-13): `_service.yaml:57-58` and `_service-headless.yaml:27-28` now use
`platform.selectorLabels` only. Every non-selector object still gets the full
`platform.labels` + a `range` over `commonLabels` (quoted values) + block-specific
labels.

## Gate outside `fromYaml`

Capability/enable gating must happen in the **wrapper** (`_app.yaml`) *before*
invoking a generator at all — and outside any `fromYaml` round-trip. `fromYaml ""`
yields `{}`, which serializes to a bogus empty document; the gate has a negative
test that asserts no `{}` doc is ever emitted. Generators also repeat the
`.enabled` guard defensively inside their own define (`_mtls.yaml:2`,
`_secret.yaml:5`) — both layers.

## The two escape hatches

When the opinionated tier-1 doesn't model your Kind:

- **`extraObjects`** — a *map* of `Kind: [ {name, …passthrough} ]`, rendered by the
  single `platform.genericResource`. Every key except the reserved set
  (`name`, `namespace`, `labels`, `annotations`, `apiVersion`, `kind`,
  `clusterScoped`) passes through verbatim. Capability-negotiated and namespaced
  like tier-1. Cluster-scoped Kinds need `allowClusterScopedExtras: true` (opt-in,
  warned).
- **`extraManifests`** — a *list* of full manifest maps or template strings. String
  entries render through `tpl` (so they may contain template expressions); the
  consumer supplies the full `apiVersion`/`kind`. This layer does **no**
  negotiation, labelling, or namespacing — it's the raw escape hatch.

See [Examples & Recipes](/docs/examples-recipes/) for worked `extraObjects` usage.
