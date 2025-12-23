{{/*
Expand the name of the chart.
*/}}
{{- define "platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "platform.fullname" -}}
{{- if .Values.nameOverride }}
{{- .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "platform.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "platform.labels" -}}
helm.sh/chart: {{ include "platform.chart" . }}
{{ include "platform.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "platform.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "platform.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account
*/}}
{{- define "platform.serviceAccount" -}}
{{- if .Values.serviceAccount.create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "platform.serviceAccountName" . }}
  namespace: {{ .Values.global.namespace }}
  labels:
    {{- include "platform.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Create HorizontalPodAutoscaler
*/}}
{{- define "platform.autoscaling" -}}
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "platform.fullname" . }}
  namespace: {{ .Values.global.namespace }}
  labels:
    {{- include "platform.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: {{ .Values.workload.type }}
    name: {{ include "platform.fullname" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
{{- end }}
{{- end }}

{{/*
Workload template selector
*/}}
{{- define "platform.workload" -}}
{{- if eq .Values.workload.type "StatefulSet" }}
{{- include "platform.statefulset" . }}
{{- else if eq .Values.workload.type "DaemonSet" }}
{{- include "platform.daemonset" . }}
{{- else }}
{{- include "platform.deployment" . }}
{{- end }}
{{- end }}

{{/*
Pre-install job template
*/}}
{{- define "platform.job.preinstall" -}}
{{- if .Values.job.preInstall.enabled }}
{{- $jobValues := .Values }}
{{- $_ := set $jobValues.job "type" "preinstall" }}
{{- $_ := set $jobValues.job "hookAnnotations" (dict "helm.sh/hook" "pre-install,pre-upgrade" "helm.sh/hook-weight" (toString (.Values.job.preInstall.hookWeight | default "-5")) "helm.sh/hook-delete-policy" "before-hook-creation,hook-succeeded") }}
{{- if .Values.job.preInstall.image }}
{{- $_ := set $jobValues.job "image" .Values.job.preInstall.image }}
{{- end }}
{{- if .Values.job.preInstall.command }}
{{- $_ := set $jobValues.job "command" .Values.job.preInstall.command }}
{{- end }}
{{- if .Values.job.preInstall.args }}
{{- $_ := set $jobValues.job "args" .Values.job.preInstall.args }}
{{- end }}
{{- if .Values.job.preInstall.env }}
{{- $_ := set $jobValues.job "env" .Values.job.preInstall.env }}
{{- end }}
{{- if .Values.job.preInstall.resources }}
{{- $_ := set $jobValues.job "resources" .Values.job.preInstall.resources }}
{{- end }}
{{- if .Values.job.preInstall.backoffLimit }}
{{- $_ := set $jobValues.job "backoffLimit" .Values.job.preInstall.backoffLimit }}
{{- end }}
{{- if .Values.job.preInstall.completions }}
{{- $_ := set $jobValues.job "completions" .Values.job.preInstall.completions }}
{{- end }}
{{- if .Values.job.preInstall.parallelism }}
{{- $_ := set $jobValues.job "parallelism" .Values.job.preInstall.parallelism }}
{{- end }}
{{- if .Values.job.preInstall.restartPolicy }}
{{- $_ := set $jobValues.job "restartPolicy" .Values.job.preInstall.restartPolicy }}
{{- end }}
{{- if .Values.job.preInstall.activeDeadlineSeconds }}
{{- $_ := set $jobValues.job "activeDeadlineSeconds" .Values.job.preInstall.activeDeadlineSeconds }}
{{- end }}
{{- if .Values.job.preInstall.volumeMounts }}
{{- $_ := set $jobValues.job "volumeMounts" .Values.job.preInstall.volumeMounts }}
{{- end }}
{{- if .Values.job.preInstall.volumes }}
{{- $_ := set $jobValues.job "volumes" .Values.job.preInstall.volumes }}
{{- end }}
{{- include "platform.job" $jobValues }}
{{- end }}
{{- end }}

{{/*
Post-install job template
*/}}
{{- define "platform.job.postinstall" -}}
{{- if .Values.job.postInstall.enabled }}
{{- $jobValues := .Values }}
{{- $_ := set $jobValues.job "type" "postinstall" }}
{{- $_ := set $jobValues.job "hookAnnotations" (dict "helm.sh/hook" "post-install,post-upgrade" "helm.sh/hook-weight" (toString (.Values.job.postInstall.hookWeight | default "5")) "helm.sh/hook-delete-policy" "before-hook-creation,hook-succeeded") }}
{{- if .Values.job.postInstall.image }}
{{- $_ := set $jobValues.job "image" .Values.job.postInstall.image }}
{{- end }}
{{- if .Values.job.postInstall.command }}
{{- $_ := set $jobValues.job "command" .Values.job.postInstall.command }}
{{- end }}
{{- if .Values.job.postInstall.args }}
{{- $_ := set $jobValues.job "args" .Values.job.postInstall.args }}
{{- end }}
{{- if .Values.job.postInstall.script }}
{{- $_ := set $jobValues.job "script" .Values.job.postInstall.script }}
{{- end }}
{{- if .Values.job.postInstall.scriptFile }}
{{- $_ := set $jobValues.job "scriptFile" .Values.job.postInstall.scriptFile }}
{{- end }}
{{- if .Values.job.postInstall.env }}
{{- $_ := set $jobValues.job "env" .Values.job.postInstall.env }}
{{- end }}
{{- if .Values.job.postInstall.resources }}
{{- $_ := set $jobValues.job "resources" .Values.job.postInstall.resources }}
{{- end }}
{{- if .Values.job.postInstall.backoffLimit }}
{{- $_ := set $jobValues.job "backoffLimit" .Values.job.postInstall.backoffLimit }}
{{- end }}
{{- if .Values.job.postInstall.completions }}
{{- $_ := set $jobValues.job "completions" .Values.job.postInstall.completions }}
{{- end }}
{{- if .Values.job.postInstall.parallelism }}
{{- $_ := set $jobValues.job "parallelism" .Values.job.postInstall.parallelism }}
{{- end }}
{{- if .Values.job.postInstall.restartPolicy }}
{{- $_ := set $jobValues.job "restartPolicy" .Values.job.postInstall.restartPolicy }}
{{- end }}
{{- if .Values.job.postInstall.activeDeadlineSeconds }}
{{- $_ := set $jobValues.job "activeDeadlineSeconds" .Values.job.postInstall.activeDeadlineSeconds }}
{{- end }}
{{- if .Values.job.postInstall.volumeMounts }}
{{- $_ := set $jobValues.job "volumeMounts" .Values.job.postInstall.volumeMounts }}
{{- end }}
{{- if .Values.job.postInstall.volumes }}
{{- $_ := set $jobValues.job "volumes" .Values.job.postInstall.volumes }}
{{- end }}
{{- include "platform.job" $jobValues }}
{{- end }}
{{- end }}

{{/*
Post-install script ConfigMap template
*/}}
{{- define "platform.configmap.postinstall-script" -}}
{{- if .Values.job.postInstall.enabled }}
{{- if or .Values.job.postInstall.script .Values.job.postInstall.scriptFile }}
{{- $jobValues := .Values }}
{{- $_ := set $jobValues.job "type" "postinstall" }}
{{- if .Values.job.postInstall.script }}
{{- $_ := set $jobValues.job "script" .Values.job.postInstall.script }}
{{- end }}
{{- if .Values.job.postInstall.scriptFile }}
{{- $_ := set $jobValues.job "scriptFile" .Values.job.postInstall.scriptFile }}
{{- end }}
{{- include "platform.configmap.script" $jobValues }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Get service endpoint for this service
*/}}
{{- define "platform.service.endpoint" -}}
{{- $serviceName := include "platform.fullname" . }}
{{- $servicePort := .Values.service.port | default 80 }}
{{- $namespace := .Values.global.namespace | default "default" }}
{{- printf "%s.%s.svc.cluster.local:%d" $serviceName $namespace $servicePort }}
{{- end }}

{{/*
Get service endpoint for a specific subchart (for umbrella charts)
*/}}
{{- define "global.subchartEndpoint" -}}
{{- $subchartName := .subchartName -}}
{{- $rootContext := .rootContext -}}
{{- if $subchartName -}}
  {{- $subchartContext := index $rootContext.Values $subchartName -}}
  {{- if $subchartContext -}}
    {{- $subserviceName := $subchartName -}}
    {{- if $subchartContext.service.name -}}
      {{- $subserviceName = $subchartContext.service.name -}}
    {{- end -}}
    {{- $subservicePort := $subchartContext.service.port | default 80 -}}
    {{- $namespace := $subchartContext.global.namespace | default $rootContext.Values.global.namespace | default "default" -}}
    {{- printf "%s.%s.svc.cluster.local:%d" $subserviceName $namespace $subservicePort -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Get all enabled subcharts dynamically
*/}}
{{- define "global.enabledSubcharts" -}}
{{- $enabled := list -}}
{{- range $chartName, $chartValues := .Values -}}
  {{- if and (not (eq $chartName "global")) (not (eq $chartName "nameOverride")) (not (eq $chartName "common")) }}
    {{- if or (hasKey $chartValues "enabled") (not (hasKey $chartValues "enabled")) }}
      {{- if or $chartValues.enabled (not (hasKey $chartValues "enabled")) }}
        {{- $enabled = append $enabled $chartName -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $enabled | join "," -}}
{{- end }}

{{/*
Get all service endpoints dynamically
*/}}
{{- define "global.allEndpointsDynamic" -}}
{{- $endpoints := dict -}}
{{- range $chartName, $chartValues := .Values -}}
  {{- if and (not (eq $chartName "global")) (not (eq $chartName "nameOverride")) (not (eq $chartName "common")) }}
    {{- if or (hasKey $chartValues "enabled") (not (hasKey $chartValues "enabled")) }}
      {{- if or $chartValues.enabled (not (hasKey $chartValues "enabled")) }}
        {{- $subserviceName := $chartName -}}
        {{- if $chartValues.service.name -}}
          {{- $subserviceName = $chartValues.service.name -}}
        {{- end -}}
        {{- $subservicePort := $chartValues.service.port | default 80 -}}
        {{- if $subservicePort -}}
          {{- $namespace := $chartValues.global.namespace | default $.Values.global.namespace | default "default" -}}
          {{- $endpoint := printf "%s.%s.svc.cluster.local:%d" $subserviceName $namespace $subservicePort -}}
          {{- $endpoints = set $endpoints $subserviceName $endpoint -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $endpoints | toYaml -}}
{{- end }}

{{/*
All service endpoints as a dynamic single variable (backward compatibility)
*/}}
{{- define "global.allEndpoints" -}}
{{- include "global.allEndpointsDynamic" . -}}
{{- end }}

{{/*
Create ConfigMap with all service endpoints
*/}}
{{- define "platform.serviceEndpoints.configmap" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "platform.fullname" . }}-service-endpoints
  namespace: {{ .Values.global.namespace | default "default" }}
  labels:
    {{- include "platform.labels" . | nindent 4 }}
data:
  # List of enabled subcharts
  enabled-subcharts: |
    {{- include "global.enabledSubcharts" . | nindent 4 }}

  # Dynamically generate all enabled service endpoints
  {{- $allEndpoints := include "global.allEndpointsDynamic" . | fromYaml }}
  {{- range $service, $endpoint := $allEndpoints }}
  {{- if $endpoint }}
  {{ $service }}-endpoint: {{ $endpoint | quote }}
  {{- end }}
  {{- end }}

  # All endpoints as structured data
  service-endpoints.yaml: |
    {{- include "global.allEndpointsDynamic" . | nindent 4 }}
{{- end -}}

