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
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
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
Common labels for the main workload and everything that belongs to it.
*/}}
{{- define "platform.labels" -}}
{{- include "platform.labelsFor" (dict "ctx" . "component" "app") -}}
{{- end }}

{{/*
Common labels for a named component. Takes (dict "ctx" $ "component" "<name>").
CronJob and hook-Job objects use their own component so they are not mislabeled
as part of the main workload.
*/}}
{{- define "platform.labelsFor" -}}
{{- $ctx := .ctx -}}
helm.sh/chart: {{ include "platform.chart" $ctx }}
{{ include "platform.selectorLabelsFor" (dict "ctx" $ctx "component" .component) }}
{{- if $ctx.Chart.AppVersion }}
app.kubernetes.io/version: {{ $ctx.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ $ctx.Release.Service }}
{{- end }}

{{/*
Selector labels for the main workload's pods.

These land in immutable selectors (Deployment/StatefulSet/DaemonSet
spec.selector.matchLabels) and in the Service/PDB/PodMonitor selectors, so they
must be STABLE: never add a user-controlled value such as commonLabels here.
Changing a selector orphans the running pods (and, on workloads, is rejected
outright by the API server as an immutable-field update).

app.kubernetes.io/component is what keeps the Service and the PDB from matching
CronJob and hook-Job pods, which otherwise carry an identical name+instance pair.
*/}}
{{- define "platform.selectorLabels" -}}
{{- include "platform.selectorLabelsFor" (dict "ctx" . "component" "app") -}}
{{- end }}

{{/*
Selector labels for a named component. Takes (dict "ctx" $ "component" "<name>").
*/}}
{{- define "platform.selectorLabelsFor" -}}
{{- $ctx := .ctx -}}
app.kubernetes.io/name: {{ include "platform.name" $ctx }}
app.kubernetes.io/instance: {{ $ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Resolve the full image reference, honoring global overrides.
Requires image.digest (preferred) or image.tag; there is no `latest` fallback.
digest wins when both are set. Used by the main workload pod template and the
CronJob default container.
*/}}
{{- define "platform.image" -}}
{{- $repository := trimPrefix "/" (.Values.image.repository | default "") -}}
{{- $registry := ternary .Values.global.imageRegistry .Values.image.registry (ne .Values.global.imageRegistry "") -}}
{{- if $registry }}
  {{- $repository = printf "%s/%s" $registry $repository -}}
{{- end }}
{{- if .Values.image.digest }}
{{- printf "%s@%s" $repository .Values.image.digest }}
{{- else if .Values.image.tag }}
{{- printf "%s:%v" $repository .Values.image.tag }}
{{- else }}
{{- fail "platform-library: image.tag and image.digest are both empty. Pin the image with image.digest (preferred, immutable, e.g. \"sha256:<64-hex>\") or image.tag (e.g. \"1.2.3\"). Floating \"latest\" is no longer defaulted." }}
{{- end }}
{{- end }}

{{/*
Resolve pull policy with global override support
*/}}
{{- define "platform.imagePullPolicy" -}}
{{- $policy := .Values.image.pullPolicy | default "" -}}
{{- if .Values.global.imagePullPolicy }}
  {{- $policy = .Values.global.imagePullPolicy -}}
{{- end -}}
{{- default "IfNotPresent" $policy }}
{{- end }}

{{/*
Render environment variables from map or slice inputs
*/}}
{{- define "platform.envVars" -}}
{{- $env := .Values.envVars -}}
{{- if kindIs "map" $env }}
  {{- range $k, $v := $env }}
- name: {{ $k }}
  {{- if kindIs "map" $v }}
  {{- toYaml $v | nindent 2 }}
  {{- else }}
  value: {{ $v | quote }}
  {{- end }}
  {{- end }}
{{- else if kindIs "slice" $env }}
{{ toYaml $env }}
{{- end }}
{{- end }}

{{/*
Return the primary service port definition
*/}}
{{- define "platform.primaryServicePort" -}}
{{- $holder := dict "value" (dict "port" 80 "targetPort" "http" "name" "http" "protocol" "TCP") -}}
{{- if and .Values.service .Values.service.ports }}
  {{- $_ := set $holder "value" (index .Values.service.ports 0) -}}
{{- end }}
{{ toYaml (index $holder "value") }}
{{- end }}

{{/*
Build affinity block honoring HA presets when explicit affinity not provided
*/}}
{{- define "platform.buildAffinity" -}}
{{- if .Values.affinity }}
{{ toYaml .Values.affinity }}
{{- else if and .Values.highAvailability .Values.highAvailability.enabled }}
  {{- $ha := .Values.highAvailability -}}
  {{- $aff := dict -}}
  {{- $selector := include "platform.selectorLabels" . | fromYaml -}}
  {{- $matchLabels := dict -}}
  {{- range $k, $v := $selector }}
    {{- $_ := set $matchLabels $k $v -}}
  {{- end }}
  {{- /* Pod Anti-Affinity */}}
  {{- if eq $ha.podAntiAffinityPreset "hard" }}
    {{- $_ := set $aff "podAntiAffinity" (dict "requiredDuringSchedulingIgnoredDuringExecution" (list (dict "labelSelector" (dict "matchLabels" $matchLabels) "topologyKey" "kubernetes.io/hostname"))) }}
  {{- else if eq $ha.podAntiAffinityPreset "soft" }}
    {{- $_ := set $aff "podAntiAffinity" (dict "preferredDuringSchedulingIgnoredDuringExecution" (list (dict "weight" 100 "podAffinityTerm" (dict "labelSelector" (dict "matchLabels" $matchLabels) "topologyKey" "kubernetes.io/hostname")))) }}
  {{- end }}
  {{- /* Pod Affinity */}}
  {{- if eq $ha.podAffinityPreset "hard" }}
    {{- $_ := set $aff "podAffinity" (dict "requiredDuringSchedulingIgnoredDuringExecution" (list (dict "labelSelector" (dict "matchLabels" $matchLabels) "topologyKey" "kubernetes.io/hostname"))) }}
  {{- else if eq $ha.podAffinityPreset "soft" }}
    {{- $_ := set $aff "podAffinity" (dict "preferredDuringSchedulingIgnoredDuringExecution" (list (dict "weight" 100 "podAffinityTerm" (dict "labelSelector" (dict "matchLabels" $matchLabels) "topologyKey" "kubernetes.io/hostname")))) }}
  {{- end }}
  {{- /* Node affinity */}}
  {{- if and $ha.nodeAffinityPreset.type (gt (len ($ha.nodeAffinityPreset.values | default (list))) 0) }}
    {{- $nodeTerm := dict "matchExpressions" (list (dict "key" ($ha.nodeAffinityPreset.key | default "kubernetes.io/hostname") "operator" "In" "values" $ha.nodeAffinityPreset.values)) }}
    {{- if eq $ha.nodeAffinityPreset.type "hard" }}
      {{- $_ := set $aff "nodeAffinity" (dict "requiredDuringSchedulingIgnoredDuringExecution" (dict "nodeSelectorTerms" (list $nodeTerm))) }}
    {{- else if eq $ha.nodeAffinityPreset.type "soft" }}
      {{- $_ := set $aff "nodeAffinity" (dict "preferredDuringSchedulingIgnoredDuringExecution" (list (dict "weight" 100 "preference" $nodeTerm))) }}
    {{- end }}
  {{- end }}
  {{- if gt (len $aff) 0 }}
{{ toYaml $aff }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Render the full Pod template spec shared across workloads
*/}}
{{- define "platform.podTemplateSpec" -}}
{{- $ctx := . -}}
metadata:
  labels:
    {{- include "platform.selectorLabels" $ctx | nindent 4 }}
    {{- range $k, $v := $ctx.Values.commonLabels }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
    {{- range $k, $v := $ctx.Values.podLabels }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
  {{- $podAnnotations := dict -}}
  {{- range $k, $v := $ctx.Values.commonAnnotations }}
    {{- $_ := set $podAnnotations $k $v -}}
  {{- end }}
  {{- range $k, $v := $ctx.Values.podAnnotations }}
    {{- $_ := set $podAnnotations $k $v -}}
  {{- end }}
  {{- if eq $ctx.Values.workload.type "Deployment" }}
    {{- $rollout := (include "platform.deployment.rolloutAnnotations" $ctx | trim) -}}
    {{- if $rollout }}
      {{- $rolloutMap := fromYaml $rollout -}}
      {{- range $k, $v := $rolloutMap }}
        {{- $_ := set $podAnnotations $k $v -}}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if gt (len $podAnnotations) 0 }}
  annotations:
    {{- range $k, $v := $podAnnotations }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
  {{- end }}
spec:
  serviceAccountName: {{ include "platform.serviceAccountName" $ctx }}
  automountServiceAccountToken: {{ $ctx.Values.serviceAccount.automountServiceAccountToken | default false }}
  enableServiceLinks: {{ $ctx.Values.enableServiceLinks | default false }}
  {{- $pullSecrets := list -}}
  {{- range $ctx.Values.global.imagePullSecrets }}
    {{- $pullSecrets = append $pullSecrets . -}}
  {{- end }}
  {{- range $ctx.Values.image.pullSecrets }}
    {{- $pullSecrets = append $pullSecrets . -}}
  {{- end }}
  {{- if gt (len $pullSecrets) 0 }}
  imagePullSecrets:
    {{- range $name := $pullSecrets }}
    - name: {{ $name }}
    {{- end }}
  {{- end }}
  {{- if $ctx.Values.podSecurityContext.enabled }}
  securityContext: {{- omit $ctx.Values.podSecurityContext "enabled" | toYaml | nindent 4 }}
  {{- end }}
  {{- if and $ctx.Values.initContainers.enabled $ctx.Values.initContainers.containers }}
  initContainers: {{- toYaml $ctx.Values.initContainers.containers | nindent 4 }}
  {{- end }}
  containers:
    - name: {{ $ctx.Chart.Name }}
      {{- if $ctx.Values.containerSecurityContext.enabled }}
      securityContext: {{- omit $ctx.Values.containerSecurityContext "enabled" | toYaml | nindent 8 }}
      {{- end }}
      image: {{ include "platform.image" $ctx }}
      imagePullPolicy: {{ include "platform.imagePullPolicy" $ctx }}
      {{- if $ctx.Values.command }}
      command: {{- toYaml $ctx.Values.command | nindent 8 }}
      {{- end }}
      {{- if $ctx.Values.args }}
      args: {{- toYaml $ctx.Values.args | nindent 8 }}
      {{- end }}
      {{- if $ctx.Values.envVars }}
      env:
        {{- include "platform.envVars" $ctx | nindent 8 }}
      {{- end }}
      {{- if or $ctx.Values.envVarsConfigMap $ctx.Values.envVarsSecret }}
      envFrom:
        {{- if $ctx.Values.envVarsConfigMap }}
        - configMapRef:
            name: {{ $ctx.Values.envVarsConfigMap }}
        {{- end }}
        {{- if $ctx.Values.envVarsSecret }}
        - secretRef:
            name: {{ $ctx.Values.envVarsSecret }}
        {{- end }}
      {{- end }}
      {{- if $ctx.Values.ports }}
      ports: {{- toYaml $ctx.Values.ports | nindent 8 }}
      {{- end }}
      {{- if and $ctx.Values.livenessProbe.enabled (omit $ctx.Values.livenessProbe "enabled") }}
      livenessProbe: {{- toYaml (omit $ctx.Values.livenessProbe "enabled") | nindent 8 }}
      {{- end }}
      {{- if and $ctx.Values.readinessProbe.enabled (omit $ctx.Values.readinessProbe "enabled") }}
      readinessProbe: {{- toYaml (omit $ctx.Values.readinessProbe "enabled") | nindent 8 }}
      {{- end }}
      {{- if and $ctx.Values.startupProbe.enabled (omit $ctx.Values.startupProbe "enabled") }}
      startupProbe: {{- toYaml (omit $ctx.Values.startupProbe "enabled") | nindent 8 }}
      {{- end }}
      {{- if $ctx.Values.lifecycleHooks }}
      lifecycle: {{- toYaml $ctx.Values.lifecycleHooks | nindent 8 }}
      {{- end }}
      {{- if or (and $ctx.Values.resources.requests (not (empty $ctx.Values.resources.requests))) (and $ctx.Values.resources.limits (not (empty $ctx.Values.resources.limits))) }}
      resources: {{- toYaml $ctx.Values.resources | nindent 8 }}
      {{- end }}
      {{- $mounts := list -}}
      {{- if and $ctx.Values.configMap.enabled $ctx.Values.configMap.mounted }}
        {{- $configMount := dict "name" "config" "mountPath" $ctx.Values.configMap.mountPath -}}
        {{- if $ctx.Values.configMap.subPath }}
          {{- $_ := set $configMount "subPath" $ctx.Values.configMap.subPath -}}
        {{- end }}
        {{- $mounts = append $mounts $configMount -}}
      {{- end }}
      {{- if $ctx.Values.persistence.enabled }}
        {{- $dataMount := dict "name" "data" "mountPath" $ctx.Values.persistence.mountPath -}}
        {{- if $ctx.Values.persistence.subPath }}
          {{- $_ := set $dataMount "subPath" $ctx.Values.persistence.subPath -}}
        {{- end }}
        {{- $mounts = append $mounts $dataMount -}}
      {{- end }}
      {{- if $ctx.Values.extraVolumeMounts }}
        {{- range $ctx.Values.extraVolumeMounts }}
          {{- $mounts = append $mounts . -}}
        {{- end }}
      {{- end }}
      {{- if gt (len $mounts) 0 }}
      volumeMounts: {{- toYaml $mounts | nindent 8 }}
      {{- end }}
    {{- if and $ctx.Values.sidecars.enabled $ctx.Values.sidecars.containers }}
    {{- toYaml $ctx.Values.sidecars.containers | nindent 4 }}
    {{- end }}
  {{- $volumes := list -}}
  {{- if $ctx.Values.configMap.enabled }}
    {{- $volumes = append $volumes (dict "name" "config" "configMap" (dict "name" (printf "%s-config" (include "platform.fullname" $ctx)))) -}}
  {{- end }}
  {{- if $ctx.Values.persistence.enabled }}
    {{- $claimName := default (printf "%s-data" (include "platform.fullname" $ctx)) $ctx.Values.persistence.existingClaim -}}
    {{- $volumes = append $volumes (dict "name" "data" "persistentVolumeClaim" (dict "claimName" $claimName)) -}}
  {{- end }}
  {{- if $ctx.Values.extraVolumes }}
    {{- range $ctx.Values.extraVolumes }}
      {{- $volumes = append $volumes . -}}
    {{- end }}
  {{- end }}
  {{- if gt (len $volumes) 0 }}
  volumes: {{- toYaml $volumes | nindent 4 }}
  {{- end }}
  {{- $affinity := include "platform.buildAffinity" $ctx | trim }}
  {{- if $affinity }}
  affinity:
{{ $affinity | nindent 4 }}
  {{- end }}
  {{- $topologyHolder := dict "value" $ctx.Values.topologySpreadConstraints -}}
  {{- if and (not (index $topologyHolder "value")) (and $ctx.Values.highAvailability $ctx.Values.highAvailability.enabled) $ctx.Values.highAvailability.topologySpreadConstraints }}
    {{- $_ := set $topologyHolder "value" $ctx.Values.highAvailability.topologySpreadConstraints -}}
  {{- end }}
  {{- if index $topologyHolder "value" }}
  topologySpreadConstraints: {{- toYaml (index $topologyHolder "value") | nindent 4 }}
  {{- end }}
  {{- $nodeSelector := dict -}}
  {{- range $k, $v := $ctx.Values.nodeSelector }}
    {{- $_ := set $nodeSelector $k $v -}}
  {{- end }}
  {{- if and (eq $ctx.Values.workload.type "DaemonSet") $ctx.Values.daemonSet.nodeSelector }}
    {{- range $k, $v := $ctx.Values.daemonSet.nodeSelector }}
      {{- $_ := set $nodeSelector $k $v -}}
    {{- end }}
  {{- end }}
  {{- if gt (len $nodeSelector) 0 }}
  nodeSelector:
    {{- range $k, $v := $nodeSelector }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
  {{- end }}
  {{- $tolerations := list -}}
  {{- if $ctx.Values.tolerations }}
    {{- range $ctx.Values.tolerations }}
      {{- $tolerations = append $tolerations . -}}
    {{- end }}
  {{- end }}
  {{- if and (eq $ctx.Values.workload.type "DaemonSet") $ctx.Values.daemonSet.tolerations }}
    {{- range $ctx.Values.daemonSet.tolerations }}
      {{- $tolerations = append $tolerations . -}}
    {{- end }}
  {{- end }}
  {{- if gt (len $tolerations) 0 }}
  tolerations: {{- toYaml $tolerations | nindent 4 }}
  {{- end }}
  {{- if $ctx.Values.priorityClassName }}
  priorityClassName: {{ $ctx.Values.priorityClassName | quote }}
  {{- end }}
  {{- if $ctx.Values.schedulerName }}
  schedulerName: {{ $ctx.Values.schedulerName | quote }}
  {{- end }}
  {{- if $ctx.Values.terminationGracePeriodSeconds }}
  terminationGracePeriodSeconds: {{ $ctx.Values.terminationGracePeriodSeconds }}
  {{- end }}
  {{- if $ctx.Values.podRestartPolicy }}
  restartPolicy: {{ $ctx.Values.podRestartPolicy }}
  {{- end }}
  {{- if $ctx.Values.hostAliases }}
  hostAliases: {{- toYaml $ctx.Values.hostAliases | nindent 4 }}
  {{- end }}
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
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "platform.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken | default false }}
{{- end }}
{{- end }}

{{/*
Create HorizontalPodAutoscaler
*/}}
{{- define "platform.autoscaling" -}}
{{- if .Values.autoscaling.enabled }}
apiVersion: {{ include "platform.capabilities.apiVersionForOrDefault" (list . "HorizontalPodAutoscaler") }}
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "platform.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "platform.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: {{ .Values.workload.type }}
    name: {{ include "platform.fullname" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  {{- if .Values.autoscaling.behavior }}
  behavior: {{- toYaml .Values.autoscaling.behavior | nindent 4 }}
  {{- end }}
  {{- if or .Values.autoscaling.targetCPU .Values.autoscaling.targetMemory .Values.autoscaling.metrics }}
  metrics:
  {{- if .Values.autoscaling.targetCPU }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPU }}
  {{- end }}
  {{- if .Values.autoscaling.targetMemory }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetMemory }}
  {{- end }}
  {{- range .Values.autoscaling.metrics }}
    {{- toYaml (list .) | nindent 4 }}
  {{- end }}
  {{- end }}
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
Build deterministic checksum annotations to trigger Deployment rollouts when
ConfigMaps or Secrets change.
*/}}
{{- define "platform.deployment.rolloutAnnotations" -}}
{{- $ctx := . -}}
{{- $annotations := dict -}}
{{- if $ctx.Values.configMap.enabled }}
  {{- $_ := set $annotations "checksum/config" (include "platform.configmap" $ctx | sha256sum) -}}
{{- end }}
{{- if and $ctx.Values.secret.enabled (not $ctx.Values.secret.existingSecret) }}
  {{- $_ := set $annotations "checksum/secret" (include "platform.secret" $ctx | sha256sum) -}}
{{- end }}
{{- if gt (len $annotations) 0 }}
{{ toYaml $annotations }}
{{- end }}
{{- end }}


{{/*
Render hook jobs (pre/post install)
*/}}
{{- define "platform.renderHookJob" -}}
{{- $ctx := .ctx -}}
{{- $job := .job -}}
{{- $type := .type -}}
{{- $defaults := $ctx.Values.jobs -}}
{{- $imageCfg := dict "repository" ($defaults.image.repository | default "") "tag" ($defaults.image.tag | default "") "digest" ($defaults.image.digest | default "") "pullPolicy" ($defaults.image.pullPolicy | default "IfNotPresent") -}}
{{- if $job.image }}
  {{- range $k, $v := $job.image }}
    {{- $_ := set $imageCfg $k $v -}}
  {{- end }}
{{- end }}
{{- if not $imageCfg.repository }}
  {{- $_ := set $imageCfg "repository" $ctx.Values.image.repository -}}
{{- end }}
{{- /*
Inherit the pin from the main image when the hook image sets neither tag nor
digest. Digests are repository-specific, so the main digest is inherited only
when the hook resolves to the same repository; a different hook repository
inherits the main tag only.
*/}}
{{- if and (not $imageCfg.tag) (not $imageCfg.digest) }}
  {{- if and $ctx.Values.image.digest (eq $imageCfg.repository ($ctx.Values.image.repository | default "")) }}
    {{- $_ := set $imageCfg "digest" $ctx.Values.image.digest -}}
  {{- else if $ctx.Values.image.tag }}
    {{- $_ := set $imageCfg "tag" $ctx.Values.image.tag -}}
  {{- end }}
{{- end }}
{{- $registry := $imageCfg.registry | default "" -}}
{{- if not $registry }}
  {{- if $ctx.Values.global.imageRegistry }}
    {{- $registry = $ctx.Values.global.imageRegistry -}}
  {{- else if $ctx.Values.image.registry }}
    {{- $registry = $ctx.Values.image.registry -}}
  {{- end }}
{{- end }}
{{- if and $registry $imageCfg.repository (not (hasPrefix $imageCfg.repository (printf "%s/" $registry))) }}
  {{- $_ := set $imageCfg "repository" (printf "%s/%s" $registry (trimPrefix "/" $imageCfg.repository)) -}}
{{- end }}
{{- $image := "" -}}
{{- if $imageCfg.digest }}
  {{- $image = printf "%s@%s" $imageCfg.repository $imageCfg.digest -}}
{{- else if $imageCfg.tag }}
  {{- $image = printf "%s:%v" $imageCfg.repository $imageCfg.tag -}}
{{- else }}
  {{- fail (printf "platform-library: hook Job %q resolves to an image with no tag and no digest. Set jobs.image.tag/digest (or the per-job image.tag/digest), or pin the main image via image.tag/image.digest to inherit. Floating \"latest\" is no longer defaulted." $type) -}}
{{- end }}
{{- $pullPolicy := $imageCfg.pullPolicy | default "IfNotPresent" -}}
{{- $command := coalesce $job.command nil -}}
{{- $args := coalesce $job.args nil -}}
{{- $env := default (list) $job.env -}}
{{- $volumeMounts := default (list) $job.volumeMounts -}}
{{- $volumes := default (list) $job.volumes -}}
{{- $resources := coalesce $job.resources $defaults.resources -}}
{{- $backoffLimit := default $defaults.backoffLimit $job.backoffLimit -}}
{{- $completions := default $defaults.completions $job.completions -}}
{{- $parallelism := default $defaults.parallelism $job.parallelism -}}
{{- $restartPolicy := default $defaults.restartPolicy $job.restartPolicy -}}
{{- $activeDeadlineSeconds := default $defaults.activeDeadlineSeconds $job.activeDeadlineSeconds -}}
{{- $useScript := or $job.script $job.scriptFile -}}
{{- if and $useScript (not $command) }}
  {{- $command = list "/bin/sh" "/scripts/script.sh" -}}
{{- end }}
{{- if and $useScript (not $job.command) }}
  {{- $args = list -}}
{{- end }}
{{- if $useScript }}
  {{- $volumeMounts = append $volumeMounts (dict "name" "job-script" "mountPath" "/scripts" "readOnly" true) -}}
  {{- $volumes = append $volumes (dict "name" "job-script" "configMap" (dict "name" (printf "%s-%s-script" (include "platform.fullname" $ctx) $type) "defaultMode" 0555)) -}}
{{- end }}
{{- $initContainers := list -}}
{{- if and $defaults.initContainers $defaults.initContainers.enabled $defaults.initContainers.containers }}
  {{- range $defaults.initContainers.containers }}
    {{- $initContainers = append $initContainers . -}}
  {{- end }}
{{- end }}
{{- if and $job.initContainers $job.initContainers.enabled $job.initContainers.containers }}
  {{- range $job.initContainers.containers }}
    {{- $initContainers = append $initContainers . -}}
  {{- end }}
{{- end }}
{{- $sidecars := list -}}
{{- if and $defaults.sidecars $defaults.sidecars.enabled $defaults.sidecars.containers }}
  {{- range $defaults.sidecars.containers }}
    {{- $sidecars = append $sidecars . -}}
  {{- end }}
{{- end }}
{{- if and $job.sidecars $job.sidecars.enabled $job.sidecars.containers }}
  {{- range $job.sidecars.containers }}
    {{- $sidecars = append $sidecars . -}}
  {{- end }}
{{- end }}
{{- $mainJobContainer := dict "name" (printf "%s-%s" (include "platform.name" $ctx) $type) "image" $image "imagePullPolicy" $pullPolicy -}}
{{- if $ctx.Values.containerSecurityContext.enabled }}
  {{- $_ := set $mainJobContainer "securityContext" (omit $ctx.Values.containerSecurityContext "enabled") -}}
{{- end }}
{{- if gt (len $command) 0 }}
  {{- $_ := set $mainJobContainer "command" $command -}}
{{- end }}
{{- if gt (len $args) 0 }}
  {{- $_ := set $mainJobContainer "args" $args -}}
{{- end }}
{{- if gt (len $env) 0 }}
  {{- $_ := set $mainJobContainer "env" $env -}}
{{- end }}
{{- if gt (len $volumeMounts) 0 }}
  {{- $_ := set $mainJobContainer "volumeMounts" $volumeMounts -}}
{{- end }}
{{- if $resources }}
  {{- $_ := set $mainJobContainer "resources" $resources -}}
{{- end }}
{{- $jobContainers := list $mainJobContainer -}}
{{- range $sidecars }}
  {{- $jobContainers = append $jobContainers . -}}
{{- end }}
{{- $defaultWeight := ternary -5 5 (eq $type "preinstall") -}}
{{- $hookWeight := default $defaultWeight $job.hookWeight -}}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ printf "%s-%s" (include "platform.fullname" $ctx) $type }}
  namespace: {{ $ctx.Release.Namespace }}
  labels:
    {{- include "platform.labelsFor" (dict "ctx" $ctx "component" $type) | nindent 4 }}
    {{- range $k, $v := $ctx.Values.commonLabels }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
  annotations:
    helm.sh/hook: {{ if eq $type "preinstall" }}pre-install,pre-upgrade{{ else }}post-install,post-upgrade{{ end }}
    helm.sh/hook-weight: "{{ $hookWeight }}"
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
spec:
  backoffLimit: {{ $backoffLimit }}
  completions: {{ $completions }}
  parallelism: {{ $parallelism }}
  activeDeadlineSeconds: {{ $activeDeadlineSeconds }}
  template:
    metadata:
      labels:
        {{- include "platform.selectorLabelsFor" (dict "ctx" $ctx "component" $type) | nindent 8 }}
    spec:
      restartPolicy: {{ $restartPolicy }}
      serviceAccountName: {{ include "platform.serviceAccountName" $ctx }}
      automountServiceAccountToken: {{ $ctx.Values.serviceAccount.automountServiceAccountToken | default false }}
      enableServiceLinks: {{ $ctx.Values.enableServiceLinks | default false }}
      {{- if $ctx.Values.podSecurityContext.enabled }}
      securityContext: {{- omit $ctx.Values.podSecurityContext "enabled" | toYaml | nindent 8 }}
      {{- end }}
      {{- $hookPullSecrets := list -}}
      {{- range $ctx.Values.global.imagePullSecrets }}
        {{- $hookPullSecrets = append $hookPullSecrets . -}}
      {{- end }}
      {{- range $ctx.Values.image.pullSecrets }}
        {{- $hookPullSecrets = append $hookPullSecrets . -}}
      {{- end }}
      {{- if gt (len $hookPullSecrets) 0 }}
      imagePullSecrets:
        {{- range $hookPullSecrets }}
        - name: {{ . }}
        {{- end }}
      {{- end }}
      {{- if gt (len $initContainers) 0 }}
      initContainers: {{- toYaml $initContainers | nindent 8 }}
      {{- end }}
      containers: {{- toYaml $jobContainers | nindent 8 }}
      {{- if $volumes }}
      volumes: {{- toYaml $volumes | nindent 8 }}
      {{- end }}
{{- end }}
