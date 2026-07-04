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
platform.util.merge — merge a consumer-supplied override template over a base
template (bitnami/common style) and emit the result. Takes a list:
  0: the top context ($)
  1: template name of the overrides (destination)
  2: template name of the base (source)
IMPORTANT: capability/enable gating must happen in the *wrapper* before calling
this, never here — fromYaml "" yields {} which would emit a bogus empty doc.
*/}}
{{- define "platform.util.merge" -}}
{{- $top := first . -}}
{{- $overrides := fromYaml (include (index . 1) $top) | default (dict) -}}
{{- $tpl := fromYaml (include (index . 2) $top) | default (dict) -}}
{{- toYaml (mergeOverwrite $tpl $overrides) -}}
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
  name: {{ required (printf "extraObjects.%s[].name is required" $kind) $res.name }}
  {{- if not $clusterScoped }}
  namespace: {{ $res.namespace | default $top.Release.Namespace }}
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
{{- range $k, $v := (omit $res "name" "namespace" "labels" "annotations" "apiVersion" "kind" "clusterScoped" "metadata") }}
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
*/}}
{{- define "platform.extraObjects" -}}
{{- $top := . -}}
{{- range $kind, $list := (.Values.extraObjects | default dict) }}
{{- range $res := $list }}
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
through tpl so they may contain template expressions.
*/}}
{{- define "platform.extraManifests" -}}
{{- $top := . -}}
{{- range $manifest := (.Values.extraManifests | default list) }}
---
{{- if kindIs "string" $manifest }}
{{ tpl $manifest $top }}
{{- else }}
{{ toYaml $manifest }}
{{- end }}
{{- end }}
{{- end -}}
