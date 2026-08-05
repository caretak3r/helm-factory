{{/*
platform.notes.hasResources — "true" (else "") when a container's resources
map (main container's .Values.resources, or a sidecar/initContainer entry's
own .resources) declares at least one request or limit.
Usage: include "platform.notes.hasResources" $container.resources
*/}}
{{- define "platform.notes.hasResources" -}}
{{- $resources := . | default dict -}}
{{- if or (and $resources.requests (not (empty $resources.requests))) (and $resources.limits (not (empty $resources.limits))) -}}true{{- end -}}
{{- end -}}

{{/*
platform.notes.emptyResourceContainers — comma-separated names of every
container that will actually render (main container, plus each enabled entry
under sidecars.containers / initContainers.containers) whose effective
resources map has neither requests nor limits, so it runs BestEffort QoS
(first evicted under node pressure). The library keeps `resources: {}` as the
default on purpose (no values-contract break); platform.notes turns a
non-empty result here into an operator-visible WARNING instead of shipping
default requests/limits — see CHANGELOG hf-uup.
Usage: include "platform.notes.emptyResourceContainers" $top
*/}}
{{- define "platform.notes.emptyResourceContainers" -}}
{{- $top := . -}}
{{- $empty := list -}}
{{- if not (include "platform.notes.hasResources" $top.Values.resources) -}}
  {{- $empty = append $empty $top.Chart.Name -}}
{{- end -}}
{{- if and $top.Values.initContainers $top.Values.initContainers.enabled $top.Values.initContainers.containers -}}
  {{- range $c := $top.Values.initContainers.containers -}}
    {{- if not (include "platform.notes.hasResources" $c.resources) -}}
      {{- $empty = append $empty (printf "%s (initContainer)" (default "<unnamed>" $c.name)) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if and $top.Values.sidecars $top.Values.sidecars.enabled $top.Values.sidecars.containers -}}
  {{- range $c := $top.Values.sidecars.containers -}}
    {{- if not (include "platform.notes.hasResources" $c.resources) -}}
      {{- $empty = append $empty (printf "%s (sidecar)" (default "<unnamed>" $c.name)) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- join ", " $empty -}}
{{- end -}}

{{/*
=============================================================================
platform.notes — post-install warnings for the consumer's NOTES.txt: security
footguns, plus Kinds that were enabled in values and silently skipped because
the cluster does not serve their API (platform.capabilities.skippedKinds).
=============================================================================
Renders nothing when there is nothing to warn about. NOTES.txt content never
appears in `helm template` manifest output (verified with Helm 4.2.0), so
golden snapshots, kind counts, and kubeconform are unaffected; warnings show
on `helm install`/`helm upgrade` (including --dry-run).
Usage (consumer chart templates/NOTES.txt):
  {{ include "platform.notes" . }}
*/}}
{{- define "platform.notes" -}}
{{- $top := . -}}
{{- $warnings := list -}}
{{- $skipped := include "platform.capabilities.skippedKinds" $top | trim -}}
{{- if $skipped -}}
{{- $details := list -}}
{{- range $kind := splitList " " $skipped -}}
{{- $details = append $details (printf "%s (tried %s)" $kind (include "platform.capabilities.apiVersionsFor" (list $top $kind))) -}}
{{- end -}}
{{- $warnings = append $warnings (printf "SKIPPED KINDS: enabled in values but NOT rendered, because the target cluster does not serve their API: %s. NOTHING was deployed for them. Install the CRDs, or — if the CRDs exist but are invisible at render time (e.g. `helm template` without a cluster) — force-assume the API via capabilities.apiVersions or `--api-versions`." (join "; " $details)) -}}
{{- end -}}
{{- $skippedExtras := include "platform.capabilities.skippedExtraObjects" $top | trim -}}
{{- if $skippedExtras -}}
{{- $details := list -}}
{{- range $entry := splitList " " $skippedExtras -}}
{{- $kind := index (splitList "/" $entry) 0 -}}
{{- $details = append $details (printf "%s (tried %s)" $entry (include "platform.capabilities.apiVersionsFor" (list $top $kind))) -}}
{{- end -}}
{{- $warnings = append $warnings (printf "SKIPPED EXTRA OBJECTS: listed in extraObjects but NOT rendered, because the target cluster does not serve their API: %s. NOTHING was deployed for them. Install the CRDs, force-assume the API via capabilities.apiVersions or `--api-versions`, or set apiVersion explicitly on the entry." (join "; " $details)) -}}
{{- end -}}
{{- if and .Values.ingress.enabled .Values.ingress.hostname (not .Values.ingress.tls) -}}
{{- $warnings = append $warnings (printf "Ingress host %q is served over PLAIN HTTP (ingress.tls=false). Set ingress.tls=true with ingress.existingSecret, or use cert-manager via the certificate block / an ingress annotation." .Values.ingress.hostname) -}}
{{- end -}}
{{- if and .Values.networkPolicy.enabled (empty .Values.networkPolicy.ingress) (empty .Values.networkPolicy.egress) -}}
{{- $warnings = append $warnings "networkPolicy.enabled=true with EMPTY ingress and egress rules is a DEFAULT-DENY policy: it blocks all traffic to and from the pods (including DNS). If that is not intentional, add allow rules under networkPolicy.ingress/egress." -}}
{{- end -}}
{{- if and .Values.secret.enabled (not .Values.secret.existingSecret) (or .Values.secret.stringData .Values.secret.data) -}}
{{- $warnings = append $warnings "secret.stringData/secret.data contain plaintext secret material in values (DISCOURAGED): it ends up in git and in Helm release manifests. Prefer secret.existingSecret (External Secrets / Sealed Secrets / kubectl)." -}}
{{- end -}}
{{- if not (empty .Values.generatedSecrets) -}}
{{- $warnings = append $warnings "generatedSecrets is set: the generated credential material lives in cluster Secrets AND in Helm release state (it is not re-derived from anything). Rotate a key by deleting it from values (or the whole Secret from the cluster) and running helm upgrade." -}}
{{- end -}}
{{- if .Values.tlsSelfSigned.mtls.enabled -}}
{{- $warnings = append $warnings "tlsSelfSigned.mtls.enabled=true: self-signed mTLS is DEV-ONLY, not for production. A CA Secret and per-client certificates are generated and persisted alongside the server cert. If the server cert already existed from a prior release without mtls, THIS UPGRADE ROTATES IT ONCE so it chains to the new CA — anything holding the old server cert/CA pair must be updated." -}}
{{- end -}}
{{- if not (empty .Values.ingress.secrets) -}}
{{- $warnings = append $warnings "ingress.secrets contains inline TLS cert/key material in values (DISCOURAGED). Prefer cert-manager (certificate block) or a pre-created Secret via ingress.existingSecret." -}}
{{- end -}}
{{- $csc := .Values.containerSecurityContext | default dict -}}
{{- if not $csc.enabled -}}
{{- $warnings = append $warnings "containerSecurityContext.enabled=false disables the per-container hardening defaults (runAsNonRoot, readOnlyRootFilesystem, allowPrivilegeEscalation=false, capabilities drop ALL, seccompProfile RuntimeDefault) for EVERY container in the release. The pod no longer meets the PSS restricted profile. Re-enable it and override individual keys instead." -}}
{{- else -}}
{{- $weakened := list -}}
{{- if $csc.privileged -}}
{{- $weakened = append $weakened "privileged=true (disables all container isolation)" -}}
{{- end -}}
{{- if $csc.allowPrivilegeEscalation -}}
{{- $weakened = append $weakened "allowPrivilegeEscalation=true" -}}
{{- end -}}
{{- if and (hasKey $csc "runAsNonRoot") (not $csc.runAsNonRoot) -}}
{{- $weakened = append $weakened "runAsNonRoot=false" -}}
{{- end -}}
{{- if and (hasKey $csc "runAsUser") (eq (int $csc.runAsUser) 0) -}}
{{- $weakened = append $weakened "runAsUser=0 (root)" -}}
{{- end -}}
{{- if and $csc.seccompProfile (eq ($csc.seccompProfile.type | default "") "Unconfined") -}}
{{- $weakened = append $weakened "seccompProfile.type=Unconfined" -}}
{{- end -}}
{{- $badCaps := list -}}
{{- if $csc.capabilities -}}
{{- range $cap := ($csc.capabilities.add | default list) -}}
{{- if ne (printf "%v" $cap) "NET_BIND_SERVICE" -}}
{{- $badCaps = append $badCaps (printf "%v" $cap) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if $badCaps -}}
{{- $weakened = append $weakened (printf "capabilities.add grants %s (PSS restricted allows only NET_BIND_SERVICE)" (join ", " $badCaps)) -}}
{{- end -}}
{{- if $weakened -}}
{{- $warnings = append $warnings (printf "containerSecurityContext WEAKENS the default hardened posture: %s. The pod may fail PSS-restricted admission or run with elevated privilege — make sure this is intentional and reviewed." (join "; " $weakened)) -}}
{{- end -}}
{{- end -}}
{{- if not .Values.podSecurityContext.enabled -}}
{{- $warnings = append $warnings "podSecurityContext.enabled=false removes the pod-level hardening defaults (fsGroup, runAsNonRoot, seccompProfile RuntimeDefault). The pod no longer meets the PSS restricted profile." -}}
{{- end -}}
{{- if and .Values.mtls.enabled .Values.mtls.allowAllPrincipals (empty (.Values.mtls.allowedPrincipals | default list)) -}}
{{- $warnings = append $warnings "mtls.allowAllPrincipals=true authorizes the wildcard principal cluster.local/ns/*/sa/*: any workload in the mesh may call this service (mTLS identity without meaningful authorization). List explicit principals under mtls.allowedPrincipals when possible." -}}
{{- end -}}
{{- if .Values.allowClusterScopedExtras -}}
{{- $warnings = append $warnings "allowClusterScopedExtras=true: extraObjects may render cluster-scoped Kinds (ClusterRole, PriorityClass, StorageClass, webhooks, ...). Cluster-scoped objects outlive the namespace and affect the whole cluster — keep them least-privilege and reviewed." -}}
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
{{- if .Values.rbac.enabled -}}
{{- if not .Values.serviceAccount.automountServiceAccountToken -}}
{{- $warnings = append $warnings "rbac.enabled=true but serviceAccount.automountServiceAccountToken is false (the library default): the pods get no API token, so the Role grants them nothing and every API call fails unauthenticated. Set serviceAccount.automountServiceAccountToken: true, or drop the RBAC block." -}}
{{- end -}}
{{- $wildcards := list -}}
{{- range $i, $rule := (.Values.rbac.rules | default list) -}}
{{- range $field := (list "apiGroups" "resources" "verbs") -}}
{{- if has "*" (get $rule $field | default list) -}}
{{- $wildcards = append $wildcards (printf "rules[%d].%s" $i $field) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if $wildcards -}}
{{- $warnings = append $warnings (printf "rbac.rules use the \"*\" wildcard at %s. A wildcard grant is not least-privilege — it silently widens as CRDs are installed in the namespace. List the apiGroups/resources/verbs the app actually needs." (join ", " $wildcards)) -}}
{{- end -}}
{{- end -}}
{{- $emptyResources := include "platform.notes.emptyResourceContainers" $top | trim -}}
{{- if $emptyResources -}}
{{- $warnings = append $warnings (printf "NO RESOURCES CONFIGURED: container(s) %s have no CPU/memory requests or limits and will run at BestEffort QoS — the first killed under node memory pressure and unbounded on CPU/memory otherwise. Set resources.requests/resources.limits for the main container, or a resources block per entry under sidecars.containers / initContainers.containers." $emptyResources) -}}
{{- end -}}
{{- range $w := $warnings }}
WARNING: {{ $w }}
{{ end -}}
{{- end -}}
