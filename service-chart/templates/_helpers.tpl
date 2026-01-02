{{/*
Helper functions extending the platform library helpers for chart specific
concerns such as generating a deterministic frontend component name.
*/}}

{{- define "aurora.frontend.fullname" -}}
{{- $base := include "platform.fullname" . -}}
{{- printf "%s-frontend" $base | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "aurora.frontend.labels" -}}
{{- $selector := include "platform.selectorLabels" . | fromYaml -}}
{{- $labels := dict -}}
{{- range $k, $v := $selector }}
  {{- $_ := set $labels $k $v -}}
{{- end -}}
{{- $_ := set $labels "app.kubernetes.io/component" "frontend" -}}
{{- $_ := set $labels "app.kubernetes.io/part-of" (include "platform.fullname" .) -}}
{{- $_ := set $labels "app.kubernetes.io/name" (printf "%s-frontend" (include "platform.name" .)) -}}
{{- toYaml $labels -}}
{{- end -}}

{{- define "aurora.frontend.selectorLabels" -}}
{{- $labels := dict -}}
{{- $_ := set $labels "app.kubernetes.io/name" (printf "%s-frontend" (include "platform.name" .)) -}}
{{- $_ := set $labels "app.kubernetes.io/instance" .Release.Name -}}
{{- $_ := set $labels "app.kubernetes.io/component" "frontend" -}}
{{- toYaml $labels -}}
{{- end -}}

{{- define "aurora.frontend.image" -}}
{{- $img := .Values.frontend.image -}}
{{- $repo := $img.repository | default "" -}}
{{- if not $repo }}
  {{- fail "frontend.image.repository must be specified when frontend is enabled" -}}
{{- end -}}
{{- if $img.digest }}
{{ printf "%s@%s" $repo $img.digest }}
{{- else }}
{{ printf "%s:%s" $repo ($img.tag | default "latest") }}
{{- end -}}
{{- end -}}
