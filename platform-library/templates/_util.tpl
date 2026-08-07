{{/*
=============================================================================
platform.util — merge overlay + generic capability-gated resource renderer
=============================================================================
*/}}

{{/*
platform.emit — prefix a rendered manifest string with a document separator,
but only when it is non-empty (after trimming). Because platform.render
concatenates many generators into a single template file, every top-level
object must carry its own leading "---" or adjacent docs merge into one.
Usage: include "platform.emit" (include "platform.service" .)
*/}}
{{- define "platform.emit" -}}
{{- $content := . | trim -}}
{{- if $content }}
---
{{ $content }}
{{- end }}
{{- end -}}

{{/*
platform.genericResource — render an arbitrary Kubernetes object with the
negotiated apiVersion, standard labels, and namespace handling. Any top-level
key on the spec other than the reserved metadata keys is passed through, so
this one renderer supports every Kind (rules/subjects/roleRef/spec/data/
webhooks/…). Emits nothing when no supported apiVersion is present.
Usage: include "platform.genericResource" (dict "root" $top "kind" "Role" "resource" $spec)
*/}}
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
{{- $clusterScoped := or (include "platform.capabilities.isClusterScoped" $kind) (and (hasKey $res "clusterScoped") $res.clusterScoped) -}}
apiVersion: {{ $api }}
kind: {{ $kind }}
metadata:
  name: {{ required (printf "extraObjects.%s[].name is required" $kind) $res.name | quote }}
  {{- if not $clusterScoped }}
  namespace: {{ $res.namespace | default $top.Release.Namespace | quote }}
  {{- end }}
  labels:
    {{- include "platform.labels" $top | nindent 4 }}
    {{- with $res.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with $res.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- range $k, $v := (omit $res "name" "namespace" "labels" "annotations" "apiVersion" "kind" "clusterScoped" "metadata" "template") }}
{{- if or (kindIs "map" $v) (kindIs "slice" $v) }}
{{ $k }}:
{{ toYaml $v | indent 2 }}
{{- else }}
{{ $k }}: {{ toYaml $v | trim }}
{{- end }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
platform.extraObjects — render the tier-2 long tail: a map of Kind -> list of
specs under .Values.extraObjects. Each object is capability-negotiated and
skipped when its API is absent.

Opt-in per-entry tpl expansion: an entry carrying the reserved control key
`template: true` has its whole body (toYaml -> tpl -> fromYaml) expanded
against the root context BEFORE any validation below, so a templated
apiVersion/clusterScoped is resolved before it is checked. Expansion is
opt-in (not unconditional) because existing consumers legitimately carry
literal "{{ }}" — e.g. PrometheusRule alert annotations like
"{{ $labels.pod }}" — which `tpl` would otherwise try to execute and fail.
The Kind map KEY (the range's $kind) is never templated, only entry
contents; the control key itself is stripped and never reaches rendered
output (see the `omit` list in platform.genericResource above).
*/}}
{{- define "platform.extraObjects" -}}
{{- $top := . -}}
{{- $allowCluster := .Values.allowClusterScopedExtras | default false -}}
{{- $registryTable := fromYaml (include "platform.capabilities.registry" $top) -}}
{{- range $kind, $list := (.Values.extraObjects | default dict) }}
{{- range $res := $list }}
{{- if $res.template -}}
{{- $expanded := tpl (toYaml (omit $res "template")) $top -}}
{{- $parsed := fromYaml $expanded -}}
{{- if hasKey $parsed "Error" -}}
{{- fail (printf "extraObjects.%s (name %q): template expansion produced invalid YAML: %s" $kind ($res.name | default "") $parsed.Error) -}}
{{- end -}}
{{- if or (not (kindIs "map" $parsed)) (eq (len $parsed) 0) -}}
{{- fail (printf "extraObjects.%s (name %q): template expansion produced an empty result" $kind ($res.name | default "")) -}}
{{- end -}}
{{- $res = $parsed -}}
{{- end -}}
{{- if and (not (hasKey $registryTable $kind)) (not $res.apiVersion) -}}
{{- fail (printf "extraObjects contains unknown Kind %q (name %q): it is not in the platform capability registry, so its apiVersion cannot be negotiated and the object would be silently dropped. Set apiVersion explicitly on the entry to render it verbatim, or move it to extraManifests." $kind ($res.name | default "")) -}}
{{- end -}}
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

{{/*
platform.extraManifests — ultimate escape hatch. A list of raw manifest maps
rendered verbatim (consumer supplies full apiVersion/kind). Strings are passed
through tpl so they may contain template expressions. Entries that render to
nothing (a string whose template collapses to empty, or an empty map) are
skipped so no separator-only or bare {} document is emitted.
*/}}
{{- define "platform.extraManifests" -}}
{{- $top := . -}}
{{- range $manifest := (.Values.extraManifests | default list) }}
{{- $rendered := "" -}}
{{- if kindIs "string" $manifest }}
{{- $rendered = tpl $manifest $top | trim }}
{{- else }}
{{- $rendered = toYaml $manifest | trim }}
{{- end }}
{{- if and $rendered (ne $rendered "{}") }}
---
{{ $rendered }}
{{- end }}
{{- end }}
{{- end -}}
