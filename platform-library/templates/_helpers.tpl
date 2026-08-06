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
Name of the release-managed TLS Secret. Single source of truth shared by the
writers (_tls-selfsigned.yaml, _certificate.yaml's secretName default) and the
reader (_ingress.yaml's spec.tls default) so they can never disagree.
*/}}
{{- define "platform.tlsSecretName" -}}
{{- printf "%s-tls" (include "platform.fullname" .) -}}
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
platform.tplValue — opt-in per-value template expansion for a single
annotation/env string. Takes (dict "ctx" $top "value" <string|any>). A
string value with the literal prefix "tpl:" has the marker stripped and the
remainder passed through tpl against the given (must be ROOT) context;
every other value — including non-string kinds like an envVars map-form
valueFrom block — passes through byte-identical. tpl failures fail the
render natively; there is no named-error wrapping for them. A literal value
that must itself start with "tpl:" escapes the sentinel by writing
tpl:{{ "tpl:..." }}.
Usage: include "platform.tplValue" (dict "ctx" $ctx "value" $v)
*/}}
{{- define "platform.tplValue" -}}
{{- $value := .value -}}
{{- if not (kindIs "string" $value) -}}
{{- $value -}}
{{- else if hasPrefix "tpl:" $value -}}
{{- tpl (trimPrefix "tpl:" $value) .ctx -}}
{{- else -}}
{{- $value -}}
{{- end -}}
{{- end }}

{{/*
platform.workloadMetadata — shared top-level metadata labels/annotations for
the three primary workload generators (Deployment/StatefulSet/DaemonSet).
Verbatim move of the block each generator previously inlined; emission order
carries the specific-beats-common precedence. No right-trim on the define:
the body starts with a newline so the call site reproduces the original
bytes exactly. CronJob metadata is intentionally NOT unified here.
Usage (immediately after the namespace: line):
  {{- include "platform.workloadMetadata" . }}
*/}}
{{- define "platform.workloadMetadata" }}
  labels:
    {{- include "platform.labels" . | nindent 4 }}
    {{- range $k, $v := .Values.commonLabels }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
    {{- range $k, $v := .Values.labels }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
  {{- $ctx := . -}}
  {{- if or .Values.commonAnnotations .Values.annotations }}
  annotations:
    {{- /* Merge on RAW strings first (specific beats common); only the
           WINNING value is tpl-expanded, at emission below. */ -}}
    {{- $annotations := dict -}}
    {{- range $k, $v := .Values.commonAnnotations }}
    {{- $_ := set $annotations $k $v -}}
    {{- end }}
    {{- range $k, $v := .Values.annotations }}
    {{- $_ := set $annotations $k $v -}}
    {{- end }}
    {{- range $k, $v := $annotations }}
    {{ $k }}: {{ include "platform.tplValue" (dict "ctx" $ctx "value" $v) | quote }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Resolve an image dict (registry/repository/tag/digest) to a full reference,
honoring global.imageRegistry. Requires digest (preferred) or tag; there is no
`latest` fallback. digest wins when both are set.
Takes (dict "ctx" $ "image" <dict> "path" "<values path, for fail messages>").
*/}}
{{- define "platform.imageRef" -}}
{{- $img := .image -}}
{{- $path := .path -}}
{{- $repository := trimPrefix "/" ($img.repository | default "") -}}
{{- if not $repository }}
{{- fail (printf "platform-library: %s.repository is empty. Set it to the image repository (e.g. \"org/app\")." $path) }}
{{- end }}
{{- $global := .ctx.Values.global.imageRegistry | default "" -}}
{{- $registry := ternary $global ($img.registry | default "") (ne $global "") -}}
{{- if and $registry (not (hasPrefix (printf "%s/" $registry) $repository)) }}
  {{- $repository = printf "%s/%s" $registry $repository -}}
{{- end }}
{{- if $img.digest }}
{{- printf "%s@%s" $repository $img.digest }}
{{- else if $img.tag }}
{{- printf "%s:%v" $repository $img.tag }}
{{- else }}
{{- fail (printf "platform-library: %s.tag and %s.digest are both empty. Pin the image with %s.digest (preferred, immutable, e.g. \"sha256:<64-hex>\") or %s.tag (e.g. \"1.2.3\"). Floating \"latest\" is no longer defaulted." $path $path $path $path) }}
{{- end }}
{{- end }}

{{/*
Resolve the main container's full image reference, honoring global overrides.
Used by the main workload pod template and the CronJob default container.
*/}}
{{- define "platform.image" -}}
{{- include "platform.imageRef" (dict "ctx" . "image" .Values.image "path" "image") -}}
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
Render a list of containers with the library's containerSecurityContext merged in
as a DEFAULT. PSS is evaluated per container, so a user-supplied sidecar,
initContainer or CronJob container carrying no securityContext would run
unhardened and sink the whole pod's restricted posture. The container's own
securityContext keys win on conflict: mergeOverwrite lets the LAST map override,
whereas sprig's `merge` prefers the destination and would silently discard the
user's override.

Image handling: an `image` given as a dict (registry/repository/tag/digest,
optional pullPolicy) is resolved through platform.imageRef, so it honors
global.imageRegistry and the no-latest pin rule exactly like the main
container. A plain-string `image` is rendered verbatim — it bypasses
global.imageRegistry by design (a consumer who wrote a fully-qualified
reference must not get double-prefixed). Containers without an explicit
imagePullPolicy get the resolved library default (global.imagePullPolicy,
else the dict's pullPolicy, else image.pullPolicy, else IfNotPresent).

An optional 3rd list element is a slice of extra volumeMounts appended to
EVERY container in $containers (after any mounts the container already
declares) — used by the mTLS mount wiring so init/sidecar containers get the
same tls-selfsigned mounts as the main container. Omitting it (the 2-arg
form) is fully backward compatible: no volumeMounts key is touched.
Usage: include "platform.hardenContainers" (list $ctx $containers)
       include "platform.hardenContainers" (list $ctx $containers $extraMounts)
*/}}
{{- define "platform.hardenContainers" -}}
{{- $ctx := index . 0 -}}
{{- $containers := index . 1 -}}
{{- $extraMounts := list -}}
{{- if gt (len .) 2 -}}
  {{- $extraMounts = index . 2 -}}
{{- end -}}
{{- $hardened := list -}}
{{- range $containers }}
  {{- $container := deepCopy . -}}
  {{- if $ctx.Values.containerSecurityContext.enabled }}
    {{- $default := deepCopy (omit $ctx.Values.containerSecurityContext "enabled") -}}
    {{- $_ := set $container "securityContext" (mergeOverwrite $default (default (dict) $container.securityContext)) -}}
  {{- end }}
  {{- if kindIs "map" $container.image }}
    {{- $path := printf "container %q image" ($container.name | default "<unnamed>") -}}
    {{- if not $container.imagePullPolicy }}
      {{- $policy := include "platform.imagePullPolicy" $ctx -}}
      {{- if and $container.image.pullPolicy (not $ctx.Values.global.imagePullPolicy) }}
        {{- $policy = $container.image.pullPolicy -}}
      {{- end }}
      {{- $_ := set $container "imagePullPolicy" $policy -}}
    {{- end }}
    {{- $_ := set $container "image" (include "platform.imageRef" (dict "ctx" $ctx "image" $container.image "path" $path)) -}}
  {{- else if not $container.imagePullPolicy }}
    {{- $_ := set $container "imagePullPolicy" (include "platform.imagePullPolicy" $ctx) -}}
  {{- end }}
  {{- if gt (len $extraMounts) 0 }}
    {{- $existingMounts := $container.volumeMounts | default list -}}
    {{- $_ := set $container "volumeMounts" (concat $existingMounts $extraMounts) -}}
  {{- end }}
  {{- $hardened = append $hardened $container -}}
{{- end }}
{{- toYaml $hardened -}}
{{- end }}

{{/*
platform.podPolicy.identity — pod-level SA-token and service-link policy
shared by every pod-bearing generator. serviceAccountName intentionally
stays at each call site: hook Jobs use the distinct hook ServiceAccount
(platform.hookServiceAccountName) and must never share the release SA name.
Never empty, so call sites pipe through nindent.
Usage: {{- include "platform.podPolicy.identity" $ctx | nindent 2 }}
*/}}
{{- define "platform.podPolicy.identity" -}}
automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken | default false }}
enableServiceLinks: {{ .Values.enableServiceLinks | default false }}
{{- end -}}

{{/*
platform.podPolicy.securityContext — pod securityContext from
.Values.podSecurityContext (minus the enabled flag). Emits NOTHING when
disabled. Because of that, call sites must NOT pipe through nindent (an
empty string through nindent leaves a whitespace-only line); the field
indentation is passed as the second list element instead, and keys render
two columns deeper.
Usage: {{- include "platform.podPolicy.securityContext" (list $ctx 2) }}
*/}}
{{- define "platform.podPolicy.securityContext" -}}
{{- $ctx := index . 0 -}}
{{- $indent := index . 1 -}}
{{- if $ctx.Values.podSecurityContext.enabled -}}
{{- printf "securityContext:" | nindent $indent -}}
{{- omit $ctx.Values.podSecurityContext "enabled" | toYaml | nindent (add $indent 2 | int) -}}
{{- end -}}
{{- end -}}

{{/*
platform.podPolicy.imagePullSecrets — merged pull secrets:
global.imagePullSecrets first, then image.pullSecrets, uniq keeping the
first occurrence so global entries stay ahead of image ones. Emits NOTHING
when the merged list is empty — same call convention as
podPolicy.securityContext (indent argument, no nindent at the call site).
Usage: {{- include "platform.podPolicy.imagePullSecrets" (list $ctx 2) }}
*/}}
{{- define "platform.podPolicy.imagePullSecrets" -}}
{{- $ctx := index . 0 -}}
{{- $indent := index . 1 -}}
{{- $pullSecrets := list -}}
{{- range $ctx.Values.global.imagePullSecrets -}}
{{- $pullSecrets = append $pullSecrets . -}}
{{- end -}}
{{- range $ctx.Values.image.pullSecrets -}}
{{- $pullSecrets = append $pullSecrets . -}}
{{- end -}}
{{- /* uniq keeps the first occurrence: global entries stay ahead of image ones */ -}}
{{- $pullSecrets = $pullSecrets | uniq -}}
{{- if gt (len $pullSecrets) 0 -}}
{{- printf "imagePullSecrets:" | nindent $indent -}}
{{- range $pullSecrets -}}
{{- printf "- name: %v" . | nindent (add $indent 2 | int) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Render environment variables from map or slice inputs. Map-form scalar
values route through platform.tplValue (opt-in "tpl:" prefix expansion);
slice form is raw passthrough — never sentinel-checked, since a slice
entry is a structured {name, value/valueFrom} object, not a flat string.
*/}}
{{- define "platform.envVars" -}}
{{- $ctx := . -}}
{{- $env := .Values.envVars -}}
{{- if kindIs "map" $env }}
  {{- range $k, $v := $env }}
- name: {{ $k }}
  {{- if kindIs "map" $v }}
  {{- toYaml $v | nindent 2 }}
  {{- else }}
  value: {{ include "platform.tplValue" (dict "ctx" $ctx "value" $v) | quote }}
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
{{- /*
mTLS mount wiring (tlsSelfSigned.mtls.mount.enabled): server cert pair,
each client cert pair, and the CA trust bundle mounted read-only into
EVERY container (main + init + sidecars) — the same per-container coverage
as the hardening pass above, since one unmounted sidecar that still needs to
present a client cert is as broken as one unhardened one. Computed once here
so it can feed both the main container's $mounts below and the
hardenContainers calls for initContainers/sidecars. Empty lists when
disabled, so this is a no-op on the byte-identical non-mtls path.

The webhook serving cert (webhooks.enabled) rides this SAME $mtlsMounts/
$mtlsVolumes mechanism below, for the same per-container coverage reason —
an admission webhook server running as a sidecar needs its serving cert as
much as the main container does.
*/ -}}
{{- $mtlsMounts := list -}}
{{- $mtlsVolumes := list -}}
{{- if and $ctx.Values.tlsSelfSigned.mtls.enabled $ctx.Values.tlsSelfSigned.mtls.mount.enabled }}
  {{- $basePath := $ctx.Values.tlsSelfSigned.mtls.mount.basePath -}}
  {{- $mtlsMounts = append $mtlsMounts (dict "name" "mtls-server" "mountPath" (printf "%s/server" $basePath) "readOnly" true) -}}
  {{- /* defaultMode is a leading-zero Go template numeric literal (octal) —
         0400/0444 evaluate to the decimal 256/292 K8s stores, matching the
         conventional octal notation used for Secret/ConfigMap file modes. */ -}}
  {{- $mtlsVolumes = append $mtlsVolumes (dict "name" "mtls-server" "secret" (dict "secretName" (include "platform.tlsSecretName" $ctx) "defaultMode" 0400)) -}}
  {{- range $ctx.Values.tlsSelfSigned.mtls.clients }}
    {{- $clientName := .name -}}
    {{- $mtlsMounts = append $mtlsMounts (dict "name" (printf "mtls-client-%s" $clientName) "mountPath" (printf "%s/client-%s" $basePath $clientName) "readOnly" true) -}}
    {{- $mtlsVolumes = append $mtlsVolumes (dict "name" (printf "mtls-client-%s" $clientName) "secret" (dict "secretName" (printf "%s-mtls-client-%s" (include "platform.fullname" $ctx) $clientName) "defaultMode" 0400)) -}}
  {{- end }}
  {{- if $ctx.Values.tlsSelfSigned.mtls.trustBundle.enabled }}
    {{- $mtlsMounts = append $mtlsMounts (dict "name" "mtls-ca-bundle" "mountPath" (printf "%s/ca" $basePath) "readOnly" true) -}}
    {{- $mtlsVolumes = append $mtlsVolumes (dict "name" "mtls-ca-bundle" "configMap" (dict "name" (printf "%s-ca-bundle" (include "platform.fullname" $ctx)) "defaultMode" 0444)) -}}
  {{- end }}
{{- end -}}
{{- if $ctx.Values.webhooks.enabled }}
  {{- $mtlsMounts = append $mtlsMounts (dict "name" "webhook-tls" "mountPath" $ctx.Values.webhooks.certMountPath "readOnly" true) -}}
  {{- $mtlsVolumes = append $mtlsVolumes (dict "name" "webhook-tls" "secret" (dict "secretName" (printf "%s-webhook-cert" (include "platform.fullname" $ctx)) "defaultMode" 0400)) -}}
{{- end -}}
metadata:
  labels:
    {{- include "platform.selectorLabels" $ctx | nindent 4 }}
    {{- range $k, $v := $ctx.Values.commonLabels }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
    {{- range $k, $v := $ctx.Values.podLabels }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
  {{- /* Merge on RAW strings first (specific beats common); only the WINNING
         value is tpl-expanded, at emission below — a shadowed commonAnnotations
         sentinel must never fail the render just because it lost the merge. */ -}}
  {{- $podAnnotations := dict -}}
  {{- range $k, $v := $ctx.Values.commonAnnotations }}
    {{- $_ := set $podAnnotations $k $v -}}
  {{- end }}
  {{- range $k, $v := $ctx.Values.podAnnotations }}
    {{- $_ := set $podAnnotations $k $v -}}
  {{- end }}
  {{- $rollout := (include "platform.rolloutAnnotations" $ctx | trim) -}}
  {{- $rolloutKeys := dict -}}
  {{- if $rollout }}
    {{- $rolloutMap := fromYaml $rollout -}}
    {{- range $k, $v := $rolloutMap }}
      {{- $_ := set $podAnnotations $k $v -}}
      {{- $_ := set $rolloutKeys $k true -}}
    {{- end }}
  {{- end }}
  {{- if gt (len $podAnnotations) 0 }}
  annotations:
    {{- range $k, $v := $podAnnotations }}
    {{- if hasKey $rolloutKeys $k }}
    {{ $k }}: {{ $v | quote }}
    {{- else }}
    {{ $k }}: {{ include "platform.tplValue" (dict "ctx" $ctx "value" $v) | quote }}
    {{- end }}
    {{- end }}
  {{- end }}
spec:
  serviceAccountName: {{ include "platform.serviceAccountName" $ctx }}
  {{- include "platform.podPolicy.identity" $ctx | nindent 2 }}
  {{- include "platform.podPolicy.imagePullSecrets" (list $ctx 2) }}
  {{- include "platform.podPolicy.securityContext" (list $ctx 2) }}
  {{- if and $ctx.Values.initContainers.enabled $ctx.Values.initContainers.containers }}
  initContainers: {{- include "platform.hardenContainers" (list $ctx $ctx.Values.initContainers.containers $mtlsMounts) | nindent 4 }}
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
      {{- /* the omit guard skips rendering when enabled:true is set with no other probe fields (omit yields an empty, falsy dict) */}}
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
      {{- if $ctx.Values.resizePolicy }}
      resizePolicy: {{- toYaml $ctx.Values.resizePolicy | nindent 8 }}
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
      {{- range $mtlsMounts }}
        {{- $mounts = append $mounts . -}}
      {{- end }}
      {{- if gt (len $mounts) 0 }}
      volumeMounts: {{- toYaml $mounts | nindent 8 }}
      {{- end }}
    {{- if and $ctx.Values.sidecars.enabled $ctx.Values.sidecars.containers }}
    {{- include "platform.hardenContainers" (list $ctx $ctx.Values.sidecars.containers $mtlsMounts) | nindent 4 }}
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
  {{- range $mtlsVolumes }}
    {{- $volumes = append $volumes . -}}
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
  {{- if $ctx.Values.runtimeClassName }}
  runtimeClassName: {{ $ctx.Values.runtimeClassName | quote }}
  {{- end }}
  {{- if $ctx.Values.dnsPolicy }}
  dnsPolicy: {{ $ctx.Values.dnsPolicy | quote }}
  {{- end }}
  {{- if $ctx.Values.dnsConfig }}
  dnsConfig: {{- toYaml $ctx.Values.dnsConfig | nindent 4 }}
  {{- end }}
  {{- if $ctx.Values.shareProcessNamespace }}
  shareProcessNamespace: {{ $ctx.Values.shareProcessNamespace }}
  {{- end }}
  {{- if $ctx.Values.os }}
  os: {{- toYaml $ctx.Values.os | nindent 4 }}
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
{{- $ctx := . -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "platform.serviceAccountName" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "platform.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  {{- $expanded := dict -}}
  {{- range $k, $v := . }}
    {{- $_ := set $expanded $k (include "platform.tplValue" (dict "ctx" $ctx "value" $v)) -}}
  {{- end }}
  annotations:
    {{- toYaml $expanded | nindent 4 }}
  {{- end }}
automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken | default false }}
{{- end }}
{{- end }}

{{/*
Effective helm.sh/hook-weight of a hook Job. Shared so that anything a hook Job
depends on (the script ConfigMap, the hook ServiceAccount) can order itself
strictly ahead of the Job without hard-coding a weight that could drift from it.
Usage: include "platform.job.hookWeight" (dict "job" $job "type" "preinstall")
*/}}
{{- define "platform.job.hookWeight" -}}
{{- $job := .job -}}
{{- int (default (ternary -5 5 (eq .type "preinstall")) $job.hookWeight) -}}
{{- end }}

{{/*
ServiceAccount name for a hook Job.

Helm runs pre-install hooks BEFORE it creates the release's normal resources, so
a release-managed ServiceAccount does not exist yet when the hook pod is
admitted — and the ServiceAccount admission controller rejects a pod whose
ServiceAccount is missing, regardless of automountServiceAccountToken. When the
library creates the ServiceAccount, pre-install hooks therefore reference their
own hook-scoped copy (platform.serviceAccount.hook), which is created in the
same hook phase at a lower weight. A user-supplied ServiceAccount (or the
namespace default) already exists, so it is referenced as-is.
Usage: include "platform.hookServiceAccountName" (list $ctx "preinstall")
*/}}
{{- define "platform.hookServiceAccountName" -}}
{{- $ctx := index . 0 -}}
{{- $type := index . 1 -}}
{{- if and (eq $type "preinstall") $ctx.Values.serviceAccount.create -}}
{{- printf "%s-preinstall" (include "platform.fullname" $ctx) | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "platform.serviceAccountName" $ctx -}}
{{- end -}}
{{- end }}

{{/*
Hook-scoped copy of the release ServiceAccount for the pre-install hook Job.

It carries a distinct name rather than shadowing the release ServiceAccount:
a same-named hook copy would make helm.sh/hook-delete-policy delete the LIVE
ServiceAccount on every helm upgrade, invalidating the bound tokens of the pods
still running. hook-succeeded reaps it once the hook phase is done; a failed
hook leaves it behind for debugging and before-hook-creation clears it on the
next attempt. serviceAccount.annotations (IRSA / Workload Identity) are copied
so the hook keeps the same cloud identity as the workload.
*/}}
{{- define "platform.serviceAccount.hook" -}}
{{- if and .Values.serviceAccount.create .Values.jobs.preInstall.enabled }}
{{- $ctx := . -}}
{{- $weight := include "platform.job.hookWeight" (dict "job" .Values.jobs.preInstall "type" "preinstall") -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "platform.hookServiceAccountName" (list . "preinstall") }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "platform.labelsFor" (dict "ctx" . "component" "preinstall") | nindent 4 }}
    {{- range $k, $v := .Values.commonLabels }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-weight: "{{ sub $weight 1 }}"
    helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
    {{- with .Values.serviceAccount.annotations }}
    {{- $expanded := dict -}}
    {{- range $k, $v := . }}
      {{- $_ := set $expanded $k (include "platform.tplValue" (dict "ctx" $ctx "value" $v)) -}}
    {{- end }}
    {{- toYaml $expanded | nindent 4 }}
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
Name of the library-managed headless Service that governs a StatefulSet.
*/}}
{{- define "platform.headlessServiceName" -}}
{{- printf "%s-headless" (include "platform.fullname" .) -}}
{{- end }}

{{/*
Whether the library must render its managed headless Service (returns "true"
or ""). Stable per-pod DNS (<pod>.<svc>.<ns>) only works when the StatefulSet's
spec.serviceName points at a headless Service that exists, so the library
renders one unless the consumer already provides the wiring: an explicit
statefulSet.serviceName, or a primary Service that is itself headless
(service.enabled with clusterIP: None).
*/}}
{{- define "platform.statefulset.needsManagedHeadless" -}}
{{- if and (eq (.Values.workload.type | default "Deployment") "StatefulSet") (not .Values.statefulSet.serviceName) -}}
{{- if not (and .Values.service.enabled (eq .Values.service.type "ClusterIP") (eq (printf "%v" .Values.service.clusterIP) "None")) -}}
true
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Governing Service name for the StatefulSet: statefulSet.serviceName verbatim
when set, the primary Service when it is already headless, otherwise the
library-managed headless Service.
*/}}
{{- define "platform.statefulset.serviceName" -}}
{{- if .Values.statefulSet.serviceName -}}
{{- .Values.statefulSet.serviceName -}}
{{- else if include "platform.statefulset.needsManagedHeadless" . -}}
{{- include "platform.headlessServiceName" . -}}
{{- else -}}
{{- include "platform.fullname" . -}}
{{- end -}}
{{- end }}

{{/*
Workload template selector
*/}}
{{- define "platform.workload" -}}
{{- $type := .Values.workload.type | default "Deployment" }}
{{- if eq $type "StatefulSet" }}
{{- include "platform.statefulset" . }}
{{- else if eq $type "DaemonSet" }}
{{- include "platform.daemonset" . }}
{{- else if eq $type "Deployment" }}
{{- include "platform.deployment" . }}
{{- else }}
{{- fail (printf "platform-library: unknown workload.type %q. Set workload.type to Deployment, StatefulSet or DaemonSet (case-sensitive); leaving it unset defaults to Deployment." $type) }}
{{- end }}
{{- end }}

{{/*
Render a workload update strategy. The API server rejects rollingUpdate on any
type other than RollingUpdate (Deployment Recreate, StatefulSet/DaemonSet
OnDelete), so drop the sub-key rather than pass the values map through verbatim.
An unset type means the Kubernetes default, RollingUpdate, so rollingUpdate stays.
*/}}
{{- define "platform.updateStrategy" -}}
{{- if and .type (ne (toString .type) "RollingUpdate") -}}
{{- toYaml (omit . "rollingUpdate") -}}
{{- else -}}
{{- toYaml . -}}
{{- end -}}
{{- end }}

{{/*
Build deterministic checksum annotations to trigger pod rollouts when
ConfigMaps or Secrets change. Applies to every workload type: StatefulSet and
DaemonSet pods mount config at least as often as Deployments do.
*/}}
{{- define "platform.rolloutAnnotations" -}}
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
Deprecated alias, kept for consumers that include the old Deployment-scoped
name directly. Use platform.rolloutAnnotations instead.
*/}}
{{- define "platform.deployment.rolloutAnnotations" -}}
{{- include "platform.rolloutAnnotations" . -}}
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
{{- if and $registry $imageCfg.repository (not (hasPrefix (printf "%s/" $registry) $imageCfg.repository)) }}
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
{{- $command := default (list) $job.command -}}
{{- $args := default (list) $job.args -}}
{{- $env := default (list) $job.env -}}
{{- $volumeMounts := default (list) $job.volumeMounts -}}
{{- $volumes := default (list) $job.volumes -}}
{{- $resources := coalesce $job.resources $defaults.resources -}}
{{- $resizePolicy := coalesce $job.resizePolicy $defaults.resizePolicy -}}
{{- $backoffLimit := default $defaults.backoffLimit $job.backoffLimit -}}
{{- $completions := default $defaults.completions $job.completions -}}
{{- $parallelism := default $defaults.parallelism $job.parallelism -}}
{{- $restartPolicy := default $defaults.restartPolicy $job.restartPolicy -}}
{{- $activeDeadlineSeconds := default $defaults.activeDeadlineSeconds $job.activeDeadlineSeconds -}}
{{- $useScript := or $job.script $job.scriptFile -}}
{{- if and (not $useScript) (not $command) }}
  {{- $jobsKey := ternary "preInstall" "postInstall" (eq $type "preinstall") -}}
  {{- fail (printf "platform-library: jobs.%s is enabled but defines no work to run: script, scriptFile, and command are all empty. Set jobs.%s.script (inline script), jobs.%s.scriptFile (script file in the consumer chart), or jobs.%s.command. To run the image's own ENTRYPOINT, state it explicitly via jobs.%s.command." $jobsKey $jobsKey $jobsKey $jobsKey $jobsKey) -}}
{{- end }}
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
{{/* securityContext is injected for every container below by platform.hardenContainers. */}}
{{- $mainJobContainer := dict "name" (printf "%s-%s" (include "platform.name" $ctx) $type) "image" $image "imagePullPolicy" $pullPolicy -}}
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
{{- if $resizePolicy }}
  {{- $_ := set $mainJobContainer "resizePolicy" $resizePolicy -}}
{{- end }}
{{- $jobContainers := list $mainJobContainer -}}
{{- range $sidecars }}
  {{- $jobContainers = append $jobContainers . -}}
{{- end }}
{{- $hookWeight := include "platform.job.hookWeight" (dict "job" $job "type" $type) -}}
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
      serviceAccountName: {{ include "platform.hookServiceAccountName" (list $ctx $type) }}
      {{- include "platform.podPolicy.identity" $ctx | nindent 6 }}
      {{- if $ctx.Values.runtimeClassName }}
      runtimeClassName: {{ $ctx.Values.runtimeClassName | quote }}
      {{- end }}
      {{- if $ctx.Values.dnsPolicy }}
      dnsPolicy: {{ $ctx.Values.dnsPolicy | quote }}
      {{- end }}
      {{- if $ctx.Values.dnsConfig }}
      dnsConfig: {{- toYaml $ctx.Values.dnsConfig | nindent 8 }}
      {{- end }}
      {{- if $ctx.Values.shareProcessNamespace }}
      shareProcessNamespace: {{ $ctx.Values.shareProcessNamespace }}
      {{- end }}
      {{- if $ctx.Values.os }}
      os: {{- toYaml $ctx.Values.os | nindent 8 }}
      {{- end }}
      {{- include "platform.podPolicy.securityContext" (list $ctx 6) }}
      {{- include "platform.podPolicy.imagePullSecrets" (list $ctx 6) }}
      {{- if gt (len $initContainers) 0 }}
      initContainers: {{- include "platform.hardenContainers" (list $ctx $initContainers) | nindent 8 }}
      {{- end }}
      containers: {{- include "platform.hardenContainers" (list $ctx $jobContainers) | nindent 8 }}
      {{- if $volumes }}
      volumes: {{- toYaml $volumes | nindent 8 }}
      {{- end }}
{{- end }}
