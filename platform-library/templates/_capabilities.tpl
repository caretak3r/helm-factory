{{/*
=============================================================================
platform.capabilities — API capability negotiation
=============================================================================
These helpers let every generator pick the best apiVersion that the target
cluster actually serves and silently skip an object when none is available,
so a rendered chart never conflicts on deploy.

Rendering without a cluster (helm template / lint) reports no CRDs and only a
subset of built-in groups. Consumers/CI can force-assume APIs by listing them
under `.Values.capabilities.apiVersions`, e.g:

  capabilities:
    apiVersions:
      - gateway.networking.k8s.io/v1
      - cert-manager.io/v1/Certificate

Entries may be "group/version" or "group/version/Kind"; both forms match.
=============================================================================
*/}}

{{/*
platform.capabilities.has — returns "true" (else "") when a "group/version" or
"group/version/Kind" is available, honoring the force-assume override list.
Usage: include "platform.capabilities.has" (list $top "autoscaling/v2/HorizontalPodAutoscaler")
*/}}
{{- define "platform.capabilities.has" -}}
{{- $top := index . 0 -}}
{{- $gvk := index . 1 -}}
{{- $found := $top.Capabilities.APIVersions.Has $gvk -}}
{{- if not $found -}}
  {{- $caps := (index $top.Values "capabilities") | default dict -}}
  {{- $forced := (index $caps "apiVersions") | default list -}}
  {{- $gvOnly := splitList "/" $gvk | initial | join "/" -}}
  {{- range $entry := $forced -}}
    {{- if or (eq $entry $gvk) (eq $entry $gvOnly) -}}
      {{- $found = true -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if $found -}}true{{- end -}}
{{- end -}}

{{/*
platform.capabilities.apiVersion — negotiate the first available apiVersion
from an ordered preference list of "group/version/Kind" strings.
Returns the winning "group/version" (e.g. "autoscaling/v2") or "" if none present.
Usage: include "platform.capabilities.apiVersion" (list $top (list "autoscaling/v2/HorizontalPodAutoscaler" "autoscaling/v2beta2/HorizontalPodAutoscaler"))
*/}}
{{- define "platform.capabilities.apiVersion" -}}
{{- $top := index . 0 -}}
{{- $prefs := index . 1 -}}
{{- $result := "" -}}
{{- range $pref := $prefs -}}
  {{- if and (eq $result "") (include "platform.capabilities.has" (list $top $pref)) -}}
    {{- $result = ($pref | splitList "/" | initial | join "/") -}}
  {{- end -}}
{{- end -}}
{{- $result -}}
{{- end -}}

{{/*
platform.capabilities.registry — the canonical Kind -> ordered apiVersion
preference table. Covers every built-in Kubernetes Kind creatable via a
manifest plus the CRD families this library ships opinionated generators for.
The first entry per Kind is the preferred (newest GA) version.
*/}}
{{- define "platform.capabilities.registry" -}}
# ---- core/v1 (always GA) ----
Pod: ["v1/Pod"]
Service: ["v1/Service"]
ConfigMap: ["v1/ConfigMap"]
Secret: ["v1/Secret"]
PersistentVolumeClaim: ["v1/PersistentVolumeClaim"]
PersistentVolume: ["v1/PersistentVolume"]
ServiceAccount: ["v1/ServiceAccount"]
Namespace: ["v1/Namespace"]
ResourceQuota: ["v1/ResourceQuota"]
LimitRange: ["v1/LimitRange"]
Endpoints: ["v1/Endpoints"]
Event: ["v1/Event"]
ReplicationController: ["v1/ReplicationController"]
PodTemplate: ["v1/PodTemplate"]
# ---- apps/v1 (always GA) ----
Deployment: ["apps/v1/Deployment"]
StatefulSet: ["apps/v1/StatefulSet"]
DaemonSet: ["apps/v1/DaemonSet"]
ReplicaSet: ["apps/v1/ReplicaSet"]
ControllerRevision: ["apps/v1/ControllerRevision"]
# ---- batch/v1 (always GA) ----
Job: ["batch/v1/Job"]
CronJob: ["batch/v1/CronJob", "batch/v1beta1/CronJob"]
# ---- autoscaling (negotiated) ----
HorizontalPodAutoscaler: ["autoscaling/v2/HorizontalPodAutoscaler", "autoscaling/v2beta2/HorizontalPodAutoscaler", "autoscaling/v2beta1/HorizontalPodAutoscaler", "autoscaling/v1/HorizontalPodAutoscaler"]
# ---- policy/v1 ----
PodDisruptionBudget: ["policy/v1/PodDisruptionBudget", "policy/v1beta1/PodDisruptionBudget"]
# ---- networking.k8s.io/v1 ----
Ingress: ["networking.k8s.io/v1/Ingress", "networking.k8s.io/v1beta1/Ingress", "extensions/v1beta1/Ingress"]
IngressClass: ["networking.k8s.io/v1/IngressClass"]
NetworkPolicy: ["networking.k8s.io/v1/NetworkPolicy"]
# ---- rbac.authorization.k8s.io/v1 ----
Role: ["rbac.authorization.k8s.io/v1/Role"]
RoleBinding: ["rbac.authorization.k8s.io/v1/RoleBinding"]
ClusterRole: ["rbac.authorization.k8s.io/v1/ClusterRole"]
ClusterRoleBinding: ["rbac.authorization.k8s.io/v1/ClusterRoleBinding"]
# ---- storage.k8s.io/v1 ----
StorageClass: ["storage.k8s.io/v1/StorageClass"]
VolumeAttachment: ["storage.k8s.io/v1/VolumeAttachment"]
CSIDriver: ["storage.k8s.io/v1/CSIDriver"]
CSINode: ["storage.k8s.io/v1/CSINode"]
CSIStorageCapacity: ["storage.k8s.io/v1/CSIStorageCapacity"]
# ---- scheduling.k8s.io/v1 ----
PriorityClass: ["scheduling.k8s.io/v1/PriorityClass"]
# ---- node.k8s.io/v1 ----
RuntimeClass: ["node.k8s.io/v1/RuntimeClass"]
# ---- coordination.k8s.io/v1 ----
Lease: ["coordination.k8s.io/v1/Lease"]
# ---- discovery.k8s.io/v1 ----
EndpointSlice: ["discovery.k8s.io/v1/EndpointSlice"]
# ---- admissionregistration.k8s.io ----
ValidatingWebhookConfiguration: ["admissionregistration.k8s.io/v1/ValidatingWebhookConfiguration"]
MutatingWebhookConfiguration: ["admissionregistration.k8s.io/v1/MutatingWebhookConfiguration"]
ValidatingAdmissionPolicy: ["admissionregistration.k8s.io/v1/ValidatingAdmissionPolicy", "admissionregistration.k8s.io/v1beta1/ValidatingAdmissionPolicy"]
ValidatingAdmissionPolicyBinding: ["admissionregistration.k8s.io/v1/ValidatingAdmissionPolicyBinding", "admissionregistration.k8s.io/v1beta1/ValidatingAdmissionPolicyBinding"]
# ---- apiextensions.k8s.io ----
CustomResourceDefinition: ["apiextensions.k8s.io/v1/CustomResourceDefinition"]
# ---- certificates.k8s.io/v1 ----
CertificateSigningRequest: ["certificates.k8s.io/v1/CertificateSigningRequest"]
# ---- apiregistration.k8s.io/v1 ----
APIService: ["apiregistration.k8s.io/v1/APIService"]
# ---- flowcontrol.apiserver.k8s.io ----
FlowSchema: ["flowcontrol.apiserver.k8s.io/v1/FlowSchema", "flowcontrol.apiserver.k8s.io/v1beta3/FlowSchema"]
PriorityLevelConfiguration: ["flowcontrol.apiserver.k8s.io/v1/PriorityLevelConfiguration", "flowcontrol.apiserver.k8s.io/v1beta3/PriorityLevelConfiguration"]
# ---- Gateway API CRDs ----
GatewayClass: ["gateway.networking.k8s.io/v1/GatewayClass", "gateway.networking.k8s.io/v1beta1/GatewayClass"]
Gateway: ["gateway.networking.k8s.io/v1/Gateway", "gateway.networking.k8s.io/v1beta1/Gateway"]
HTTPRoute: ["gateway.networking.k8s.io/v1/HTTPRoute", "gateway.networking.k8s.io/v1beta1/HTTPRoute"]
GRPCRoute: ["gateway.networking.k8s.io/v1/GRPCRoute", "gateway.networking.k8s.io/v1alpha2/GRPCRoute"]
ReferenceGrant: ["gateway.networking.k8s.io/v1beta1/ReferenceGrant", "gateway.networking.k8s.io/v1alpha2/ReferenceGrant"]
# ---- cert-manager CRDs ----
Certificate: ["cert-manager.io/v1/Certificate"]
Issuer: ["cert-manager.io/v1/Issuer"]
ClusterIssuer: ["cert-manager.io/v1/ClusterIssuer"]
CertificateRequest: ["cert-manager.io/v1/CertificateRequest"]
# ---- Istio CRDs ----
PeerAuthentication: ["security.istio.io/v1/PeerAuthentication", "security.istio.io/v1beta1/PeerAuthentication"]
AuthorizationPolicy: ["security.istio.io/v1/AuthorizationPolicy", "security.istio.io/v1beta1/AuthorizationPolicy"]
RequestAuthentication: ["security.istio.io/v1/RequestAuthentication", "security.istio.io/v1beta1/RequestAuthentication"]
VirtualService: ["networking.istio.io/v1/VirtualService", "networking.istio.io/v1beta1/VirtualService", "networking.istio.io/v1alpha3/VirtualService"]
DestinationRule: ["networking.istio.io/v1/DestinationRule", "networking.istio.io/v1beta1/DestinationRule"]
ServiceEntry: ["networking.istio.io/v1/ServiceEntry", "networking.istio.io/v1beta1/ServiceEntry"]
Sidecar: ["networking.istio.io/v1/Sidecar", "networking.istio.io/v1beta1/Sidecar"]
# ---- Prometheus Operator CRDs ----
ServiceMonitor: ["monitoring.coreos.com/v1/ServiceMonitor"]
PodMonitor: ["monitoring.coreos.com/v1/PodMonitor"]
PrometheusRule: ["monitoring.coreos.com/v1/PrometheusRule"]
Probe: ["monitoring.coreos.com/v1/Probe"]
{{- end -}}

{{/*
platform.capabilities.apiVersionFor — negotiate the apiVersion for a Kind by
name using the registry above. Returns "group/version" or "".
Usage: include "platform.capabilities.apiVersionFor" (list $top "Role")
*/}}
{{- define "platform.capabilities.apiVersionFor" -}}
{{- $top := index . 0 -}}
{{- $kind := index . 1 -}}
{{- $registry := fromYaml (include "platform.capabilities.registry" $top) -}}
{{- $prefs := index $registry $kind -}}
{{- if $prefs -}}
  {{- include "platform.capabilities.apiVersion" (list $top $prefs) -}}
{{- end -}}
{{- end -}}

{{/*
platform.capabilities.apiVersionForOrDefault — like apiVersionFor but never
returns empty: when the cluster reports none of the preferences (e.g. bare
`helm template` with a minimal default capability set), fall back to the first
(preferred GA) preference. Use this for always-present built-in Kinds so a core
workload is never silently dropped. Use plain apiVersionFor (skip-if-absent)
for CRDs and optional objects where a missing API must mean "do not render".
Usage: include "platform.capabilities.apiVersionForOrDefault" (list $top "HorizontalPodAutoscaler")
*/}}
{{- define "platform.capabilities.apiVersionForOrDefault" -}}
{{- $top := index . 0 -}}
{{- $kind := index . 1 -}}
{{- $registry := fromYaml (include "platform.capabilities.registry" $top) -}}
{{- $prefs := index $registry $kind -}}
{{- $negotiated := include "platform.capabilities.apiVersion" (list $top $prefs) -}}
{{- if $negotiated -}}
  {{- $negotiated -}}
{{- else if $prefs -}}
  {{- first $prefs | splitList "/" | initial | join "/" -}}
{{- end -}}
{{- end -}}

{{/*
platform.capabilities.isStable — returns "true" (else "") when a Kind belongs
to a built-in Kubernetes API group (always present on a real cluster >=1.31).
Derived from the group of the Kind's first registry preference, so CRD families
(gateway/cert-manager/istio/monitoring) return "" and must skip-if-absent.
Usage: include "platform.capabilities.isStable" (list $top "Role")
*/}}
{{- define "platform.capabilities.isStable" -}}
{{- $top := index . 0 -}}
{{- $kind := index . 1 -}}
{{- $builtin := list "core" "apps" "batch" "autoscaling" "policy" "extensions" "networking.k8s.io" "rbac.authorization.k8s.io" "storage.k8s.io" "scheduling.k8s.io" "node.k8s.io" "coordination.k8s.io" "discovery.k8s.io" "admissionregistration.k8s.io" "apiextensions.k8s.io" "certificates.k8s.io" "apiregistration.k8s.io" "flowcontrol.apiserver.k8s.io" "authentication.k8s.io" "authorization.k8s.io" "events.k8s.io" -}}
{{- $registry := fromYaml (include "platform.capabilities.registry" $top) -}}
{{- $prefs := index $registry $kind -}}
{{- if $prefs -}}
  {{- $parts := splitList "/" (first $prefs) -}}
  {{- $group := ternary "core" (first $parts) (eq (len $parts) 2) -}}
  {{- if has $group $builtin -}}true{{- end -}}
{{- end -}}
{{- end -}}

{{/*
platform.capabilities.clusterScoped — space-delimited set of cluster-scoped
Kinds, used by the generic renderer to decide whether to stamp a namespace.
*/}}
{{- define "platform.capabilities.clusterScoped" -}}
Namespace Node PersistentVolume ClusterRole ClusterRoleBinding StorageClass VolumeAttachment CSIDriver CSINode PriorityClass RuntimeClass IngressClass CustomResourceDefinition APIService CertificateSigningRequest ValidatingWebhookConfiguration MutatingWebhookConfiguration ValidatingAdmissionPolicy ValidatingAdmissionPolicyBinding FlowSchema PriorityLevelConfiguration GatewayClass ClusterIssuer ComponentStatus
{{- end -}}

{{/*
platform.capabilities.isClusterScoped — returns "true" (else "") for a Kind.
Usage: include "platform.capabilities.isClusterScoped" "ClusterRole"
*/}}
{{- define "platform.capabilities.isClusterScoped" -}}
{{- $kind := . -}}
{{- if has $kind (include "platform.capabilities.clusterScoped" $ | trim | splitList " ") -}}true{{- end -}}
{{- end -}}
