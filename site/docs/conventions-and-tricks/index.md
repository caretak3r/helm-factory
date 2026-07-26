---
title: Conventions & Tricks
description: The Helm idioms, primitives, and deliberate hacks the library uses, with source citations.
---

# Conventions & Tricks

These are the Helm primitives and idioms that turn ~30 lines of consumer values
into hardened manifests. Every item cites its source under
`platform-library/templates/`. Read this before you author a Kind or debug a
render. Several of the patterns encode fixes for real P0 bugs, so they are not
optional.

:::note
These are not style preferences. Most of them are the mechanics of the six design
invariants (fail closed, capability negotiation, specific-beats-common,
goldens-are-contract, guarded gates, default-on hardening). Break one and you have
written a bug.
:::

## Library purity: `_*.yaml` vs `_*.tpl`

The chart is `type: library` and must never gain a non-underscore template file.
Two kinds of file:

- `_*.yaml`: object generators, one `define "platform.<thing>"` each.
- `_*.tpl`: helper-only files (`_capabilities.tpl`, `_util.tpl`, `_helpers.tpl`,
  `_notes.tpl`).

A renderable (non-underscore) template would break `type: library` purity and let
the chart render itself. The consumer's one template file is `templates/app.yaml`,
holding `{{ include "platform.render" . }}`.

## The `platform.emit` separator trick

Everything renders from a single consumer template file, so without an explicit
`---` between them, adjacent YAML documents merge into one and you get
duplicate-key errors. `platform.emit` (`_util.tpl:14-20`) puts a `---` in front of
each non-empty document:

```gotemplate
{{- define "platform.emit" -}}
{{- $content := . | trim -}}
{{- if $content }}
---
{{ $content }}
{{- end }}
{{- end -}}
```

The non-empty check is why it exists: a generator that renders nothing (because it
is gated out) must not emit a bare `---` with no body under it. So generators
never write their own leading `---`; emit adds it. Multi-document generators are
the exception, and put `---` only between their own docs (`_mtls.yaml:24`,
`_gateway-api.yaml`).

## Map precedence: `range` + `set`, never bare `merge`

Specific beats common. Resource-specific values, labels, and annotations win over
`common*`/`global` when keys collide. Sprig's `merge` keeps the destination map's
keys, so both `merge $specific $common` and `merge $common $specific` get it wrong,
in opposite directions. Two idioms that don't:

```gotemplate
{{/* range + set: iterate common, set each only where specific hasn't */}}
{{- range $k, $v := $common }}{{- if not (hasKey $specific $k) }}
  {{- $_ := set $specific $k $v }}{{- end }}{{- end }}

{{/* or mergeOverwrite with the SPECIFIC map LAST so it overrides */}}
{{- $merged := mergeOverwrite (deepCopy $default) $specific -}}
```

`mergeOverwrite` (last map wins) backs the securityContext merge
(`_helpers.tpl:161`) and Gateway `specOverrides` (`_gateway-api.yaml:78,151`).
`deepCopy` the base first, since `mergeOverwrite` mutates in place.

## Fail closed: `required` and prescriptive `fail`

Invalid or ambiguous config fails at template time with a named error. The library
never renders a dangling object and leaves the API server (or production) to find
it later.

```gotemplate
{{- required "extraObjects.<Kind>[].name is required" $spec.name -}}
{{- if not $ok }}{{ fail "mtls.mode must be STRICT|PERMISSIVE|DISABLE" }}{{ end -}}
```

Fail messages are prescriptive: they name the values path at fault and say how to
fix it (models at `_helpers.tpl:111`, `_mtls.yaml:8`, `_util.tpl:83`). Every `fail`
has a matching negative test in `scripts/lint-library.sh` that greps its message.
The message and the test change together, and you have to prove the check can go
red by reverting the guard it protects.

## Calling conventions: list-unpack and named-dict helpers

A helper that needs more than `.` takes either a positional list or a named dict.
Never assume `.` is the root inside a multi-arg helper.

```gotemplate
{{/* positional: unpack with index . N */}}
{{- define "platform.capabilities.apiVersionFor" -}}
{{- $top := index . 0 -}}{{- $kind := index . 1 -}}
{{- end -}}
{{- include "platform.capabilities.apiVersionFor" (list $top "Role") -}}

{{/* named: dict for readability (_app.yaml:8,13) */}}
{{- include "platform.genericResource" (dict "root" $top "kind" "Role" "resource" $spec) -}}
```

The most common template bug in this repo is reading `.Values` inside a list-args
helper, where `.` is the args list, not the root.

## The holder-dict idiom for computed values

Go templates can't reassign a variable across a scope boundary: a `{{- $x = … }}`
inside a `range` doesn't survive the loop. The fix is a one-key dict you `set`
into:

```gotemplate
{{- $out := dict "value" "" -}}
{{- range $candidate := $prefs }}
  {{- if include "platform.capabilities.has" (list $top $candidate) }}
    {{- $_ := set $out "value" $candidate }}{{- end }}{{- end }}
{{- $out.value -}}
```

Used for negotiated apiVersions and other values computed in a loop
(`_helpers.tpl:204,404`). Build lists the same way: `append` into a variable, then
one `toYaml | nindent` at the end.

## Rendering blocks cleanly

- Strip control keys before you emit. Probe and securityContext blocks carry an
  `enabled` flag that isn't valid Kubernetes; render them with
  `omit ... "enabled"` (`_cronjob.yaml:56,82`).
- Quote user scalars. A consumer-supplied scalar in an annotation or label value
  goes through `{{ $v | quote }}`. Left unquoted, `true`/`123`/`y` land as the
  wrong YAML type and can fail admission.
- Use `printf "%v"` for numeric-capable fields. An image tag might be `1.24` (a
  float) or `"1.24.0"` (a string). `platform.image` runs it through
  `printf "%v"` so a bare-number tag doesn't render as `1.24` and pull the wrong
  image (`_helpers.tpl:119`).

## Capability negotiation as a primitive

The library never emits an apiVersion the cluster doesn't serve. Two helpers over
the `platform.capabilities.registry` table do the work:

- `platform.capabilities.has (list $top "group/version[/Kind]")`: unions live
  discovery (`.Capabilities.APIVersions.Has`) with the force-assume list at
  `.Values.capabilities.apiVersions`.
- `platform.capabilities.apiVersion (list $top $prefList)`: walks an ordered
  preference list and returns the first served `group/version`, or `""`.

Built-ins use `apiVersionForOrDefault`, which never returns empty (it falls back to
preferred GA). CRDs use strict `apiVersionFor`, where empty means skip. See
[How It Works](/docs/how-it-works/#capability-negotiation) for the decision flow
and [Capability Catalog](/docs/capability-catalog/) for the full registry.

:::warning The `--api-versions` exact-string trap
`helm template --api-versions` only satisfies the gate in the full
`group/version/Kind` form (`cert-manager.io/v1/Certificate`). Helm's
`.Capabilities.APIVersions.Has` is an exact-string test: a set holding only
`cert-manager.io/v1` never answers true for `cert-manager.io/v1/Certificate`. Pass
the bare `group/version` and you get the nastiest kind of failure, a clean exit 0
with the object silently missing. Only the `capabilities.apiVersions` values list
accepts the bare form, because the library also matches each entry against the
queried Kind's `group/version`.
:::

## Hardening is default-on and per-container

PSS-restricted is checked per container, so one unhardened sidecar fails admission
for the whole pod. Passthrough containers (init containers, sidecars) get the same
hardening pass as the main one:

```gotemplate
{{- include "platform.hardenContainers" (list $ctx $ctx.Values.initContainers.containers) -}}
```

`platform.hardenContainers` (`_helpers.tpl:153`) applies the restricted
securityContext to every container in the list. User-supplied keys win, via
`mergeOverwrite $default $userSecurityContext` with the user map last
(`_helpers.tpl:161`). It runs at every container site: the main workload, CronJob
containers (`_cronjob.yaml:74,77`), and init/sidecar passthrough
(`_helpers.tpl:309`).

## Hook ordering and the distinct hook ServiceAccount

Pre-install hook Jobs depend on a script ConfigMap and a hook ServiceAccount with
a distinct name (`<fullname>-preinstall`), weight-ordered below the Job
(`_configmap-script.yaml:32-34`, `_job-preinstall.yaml`, `platform.renderHookJob`).

The distinct name earns its keep. A same-named hook copy of the release SA would
let `helm.sh/hook-delete-policy: before-hook-creation` delete the live SA at the
start of every upgrade's hook phase, which invalidates the bound tokens of running
pods. Two more hook facts that look like races but aren't:

- The ServiceAccount admission controller always looks up a pod's SA, even with
  `automountServiceAccountToken: false`. A missing SA is a hard admission failure,
  so "just omit the SA since automount is off" doesn't work.
- `hook-succeeded` deletions run only after every hook in the phase finishes (Helm
  loops the hooks, then loops again to delete). A ConfigMap at weight `-6` survives
  until a Job at `-5` is done.

## Selector labels are immutable: keep `commonLabels` out

`platform.selectorLabels` (`_helpers.tpl:74`, rationale at `:62-72`) is the
immutable subset: name and instance only. A Service or workload selector can't
change on a live object, so a mutable label there (like `commonLabels`, which a
consumer can edit) orphans the workload on the next `helm upgrade`.

```gotemplate
selector:
  {{- include "platform.selectorLabels" . | nindent 4 }}   # name + instance ONLY
```

Leaking `commonLabels` into a selector was a P0 bug (hf-7a1, fixed 2026-07-13).
`_service.yaml:57-58` and `_service-headless.yaml:27-28` now use
`platform.selectorLabels` only. Every non-selector object still gets the full
`platform.labels`, plus a `range` over `commonLabels` (quoted values), plus
block-specific labels.

## Gate outside `fromYaml`

Enable and capability gating happens in the wrapper (`_app.yaml`), before a
generator runs at all, and outside any `fromYaml` round-trip. `fromYaml ""`
returns `{}`, which serializes to a bogus empty document, and the gate has a
negative test that no `{}` doc is ever emitted. Generators also repeat the
`.enabled` guard defensively inside their own define (`_mtls.yaml:2`,
`_secret.yaml:5`), so both layers hold.

## The two escape hatches

When the opinionated tier-1 doesn't model your Kind:

- `extraObjects`: a map of `Kind: [ {name, …passthrough} ]`, rendered by the single
  `platform.genericResource`. Every key outside the reserved set (`name`,
  `namespace`, `labels`, `annotations`, `apiVersion`, `kind`, `clusterScoped`)
  passes through verbatim. It's capability-negotiated and namespaced like tier-1.
  Cluster-scoped Kinds need `allowClusterScopedExtras: true` (opt-in, and warned).
- `extraManifests`: a list of full manifest maps or template strings. String
  entries render through `tpl`, so they can hold template expressions, and you
  supply the full `apiVersion`/`kind`. This layer does no negotiation, labelling,
  or namespacing. It's the raw escape hatch.

See [Examples & Recipes](/docs/examples-recipes/) for worked `extraObjects` usage.
