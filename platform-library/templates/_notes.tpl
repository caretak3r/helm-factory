{{/*
=============================================================================
platform.notes — post-install security warnings for the consumer's NOTES.txt
=============================================================================
Renders nothing when there is nothing to warn about. NOTES.txt content never
appears in `helm template` manifest output (verified with Helm 4.2.0), so
golden snapshots, kind counts, and kubeconform are unaffected; warnings show
on `helm install`/`helm upgrade` (including --dry-run).
Usage (consumer chart templates/NOTES.txt):
  {{ include "platform.notes" . }}
*/}}
{{- define "platform.notes" -}}
{{- $warnings := list -}}
{{- if and .Values.ingress.enabled .Values.ingress.hostname (not .Values.ingress.tls) -}}
{{- $warnings = append $warnings (printf "Ingress host %q is served over PLAIN HTTP (ingress.tls=false). Set ingress.tls=true with ingress.existingSecret, or use cert-manager via the certificate block / an ingress annotation." .Values.ingress.hostname) -}}
{{- end -}}
{{- if and .Values.networkPolicy.enabled (empty .Values.networkPolicy.ingress) (empty .Values.networkPolicy.egress) -}}
{{- $warnings = append $warnings "networkPolicy.enabled=true with EMPTY ingress and egress rules is a DEFAULT-DENY policy: it blocks all traffic to and from the pods (including DNS). If that is not intentional, add allow rules under networkPolicy.ingress/egress." -}}
{{- end -}}
{{- if and .Values.secret.enabled (not .Values.secret.existingSecret) (or .Values.secret.stringData .Values.secret.data) -}}
{{- $warnings = append $warnings "secret.stringData/secret.data contain plaintext secret material in values (DISCOURAGED): it ends up in git and in Helm release manifests. Prefer secret.existingSecret (External Secrets / Sealed Secrets / kubectl)." -}}
{{- end -}}
{{- if not (empty .Values.ingress.secrets) -}}
{{- $warnings = append $warnings "ingress.secrets contains inline TLS cert/key material in values (DISCOURAGED). Prefer cert-manager (certificate block) or a pre-created Secret via ingress.existingSecret." -}}
{{- end -}}
{{- $extrasYaml := printf "%s\n%s\n%s\n%s\n%s" (toYaml (.Values.extraObjects | default dict)) (toYaml (.Values.extraManifests | default list)) (toYaml (.Values.extraVolumes | default list)) (toYaml (.Values.sidecars | default dict)) (toYaml (.Values.initContainers | default dict)) -}}
{{- if contains "hostPath:" $extrasYaml -}}
{{- $warnings = append $warnings "extraObjects/extraManifests/extraVolumes/sidecars contain a hostPath volume. hostPath breaks pod isolation and violates the PSS restricted profile — make sure this is intentional and reviewed." -}}
{{- end -}}
{{- if contains "privileged: true" $extrasYaml -}}
{{- $warnings = append $warnings "extraObjects/extraManifests/sidecars contain privileged: true. Privileged containers disable all isolation — make sure this is intentional and reviewed." -}}
{{- end -}}
{{- $extras := .Values.extraObjects | default dict -}}
{{- if or (hasKey $extras "ClusterRole") (hasKey $extras "ClusterRoleBinding") (contains "kind: ClusterRole" $extrasYaml) -}}
{{- $warnings = append $warnings "extraObjects/extraManifests grant cluster-scoped RBAC (ClusterRole/ClusterRoleBinding). Cluster-wide permissions outlive the namespace — keep the rules least-privilege." -}}
{{- end -}}
{{- range $w := $warnings }}
WARNING: {{ $w }}
{{ end -}}
{{- end -}}
