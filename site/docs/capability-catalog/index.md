---
title: Capability Catalog
description: The full Kind → apiVersion registry that drives capability-gated rendering.
---

# Capability Catalog

The library never emits an `apiVersion` the target cluster doesn't serve. Every
generator negotiates the best available version from the
`platform.capabilities.registry` table
([`_capabilities.tpl`](https://github.com/caretak3r/helm-factory/blob/main/platform-library/templates/_capabilities.tpl)).
The first entry per Kind is the preferred (newest GA) version, and fallbacks
follow.

The registry's floor is Kubernetes 1.34 (`Chart.yaml` `kubeVersion`). apiVersions
removed before 1.34 (`batch/v1beta1`, `policy/v1beta1`, `autoscaling/v2beta1|v2beta2`,
`networking.k8s.io/v1beta1`, `extensions/v1beta1`,
`flowcontrol.apiserver.k8s.io/v1beta3`) are left out on purpose. They can't
negotiate on any supported cluster, so carrying them is dead weight.

## How capability gating works

Built-in Kinds always render (best served version, GA fallback via
`apiVersionForOrDefault`). CRD and optional Kinds skip when their API is absent
(strict `apiVersionFor`). See
[How It Works → Capability negotiation](/docs/how-it-works/#capability-negotiation)
for the decision flow and why the split exists.

## Built-in Kinds: always GA (`["v1/<Kind>"]` unless noted)

These render at their single GA version. As built-ins they use `OrDefault`, so a
plain `helm template` with no cluster still emits them.

| Group | Kinds | Version |
|---|---|---|
| core | Pod, Service, ConfigMap, Secret, PersistentVolumeClaim, PersistentVolume, ServiceAccount, Namespace, ResourceQuota, LimitRange, Endpoints, Event, ReplicationController, PodTemplate | `v1` |
| apps | Deployment, StatefulSet, DaemonSet, ReplicaSet, ControllerRevision | `apps/v1` |
| batch | Job, CronJob | `batch/v1` |
| policy | PodDisruptionBudget | `policy/v1` |
| networking.k8s.io | Ingress, IngressClass, NetworkPolicy | `v1` |
| rbac.authorization.k8s.io | Role, RoleBinding, ClusterRole, ClusterRoleBinding | `v1` |
| storage.k8s.io | StorageClass, VolumeAttachment, CSIDriver, CSINode, CSIStorageCapacity | `v1` |
| scheduling.k8s.io | PriorityClass | `v1` |
| node.k8s.io | RuntimeClass | `v1` |
| coordination.k8s.io | Lease | `v1` |
| discovery.k8s.io | EndpointSlice | `v1` |
| apiextensions.k8s.io | CustomResourceDefinition | `v1` |
| certificates.k8s.io | CertificateSigningRequest | `v1` |
| apiregistration.k8s.io | APIService | `v1` |
| flowcontrol.apiserver.k8s.io | FlowSchema, PriorityLevelConfiguration | `v1` |

## Negotiated built-ins: multiple preferences

Newest GA is preferred. An older version stays in the list only when it is still
served somewhere in the 1.34–1.36 window.

| Kind | Group | Preference order |
|---|---|---|
| HorizontalPodAutoscaler | autoscaling | `v2`, `v1` |
| ValidatingWebhookConfiguration, MutatingWebhookConfiguration | admissionregistration.k8s.io | `v1` |
| ValidatingAdmissionPolicy, ValidatingAdmissionPolicyBinding | admissionregistration.k8s.io | `v1`, `v1beta1` |
| MutatingAdmissionPolicy, MutatingAdmissionPolicyBinding | admissionregistration.k8s.io | `v1`, `v1beta1` |

## Optional built-ins: feature-gated groups (strict)

GA in the API but dependent on cluster feature support, so the library treats them
as CRD-class (`isStable` returns false). They skip when the group isn't served.

| Kind | Group | Version |
|---|---|---|
| VolumeSnapshot, VolumeSnapshotClass, VolumeSnapshotContent | snapshot.storage.k8s.io | `v1` |
| ResourceClaim, ResourceClaimTemplate, DeviceClass | resource.k8s.io | `v1` (GA 1.34) |

## CRD families: strict gate (skip when API absent)

Rendered only when the CRD's API is served or force-assumed.

| Kind | Group | Preference order |
|---|---|---|
| GatewayClass, Gateway, HTTPRoute | gateway.networking.k8s.io | `v1`, `v1beta1` |
| GRPCRoute | gateway.networking.k8s.io | `v1`, `v1alpha2` |
| ReferenceGrant | gateway.networking.k8s.io | `v1beta1`, `v1alpha2` |
| Certificate, Issuer, ClusterIssuer, CertificateRequest | cert-manager.io | `v1` |
| PeerAuthentication, AuthorizationPolicy, RequestAuthentication | security.istio.io | `v1`, `v1beta1` |
| VirtualService | networking.istio.io | `v1`, `v1beta1`, `v1alpha3` |
| DestinationRule, ServiceEntry, Sidecar | networking.istio.io | `v1`, `v1beta1` |
| ServiceMonitor, PodMonitor, PrometheusRule, Probe | monitoring.coreos.com | `v1` |

## Tier-1 gated Kinds → values block

Five CRD-backed Kinds are wired into `platform.app` behind a two-part gate (feature
flag plus capability). One registry, `platform.capabilities.features`, is the single
source of truth for both the emitter gate and the NOTES warning, so a gated feature
can't be enabled in one and forgotten in the other. When it's enabled but the API
is absent, `platform.app` renders nothing and `platform.notes` prints a visible
WARNING.

Each row also declares every Kind the feature's generator can emit and a
composition policy. `atomic` means all-or-nothing: `mtls` renders only when BOTH
`PeerAuthentication` and `AuthorizationPolicy` are available, because a
`PeerAuthentication` without its principal-restricting `AuthorizationPolicy` is
more permissive than neither. `independent` means per-Kind: a `gatewayApi`
cluster serving `HTTPRoute` but not `GRPCRoute` gets the route it can serve.
Secondary Kinds gate inside their own generator rather than at the
`platform.app` call site, but they are registry members, so their skips reach the
NOTES warning too.

| Kind | Enabling values block | Composition |
|---|---|---|
| Certificate | `certificate` | atomic |
| PeerAuthentication, AuthorizationPolicy | `mtls` | atomic |
| HTTPRoute, GRPCRoute | `gatewayApi` (`gatewayApi.grpcRoute` for GRPCRoute) | independent |
| ServiceMonitor | `serviceMonitor` | atomic |
| PodMonitor | `podMonitor` | atomic |

## Cluster-scoped Kinds

The generic renderer omits `metadata.namespace` for these (or when a spec sets
`clusterScoped: true`):

> Namespace, Node, PersistentVolume, ClusterRole, ClusterRoleBinding, StorageClass,
> VolumeAttachment, CSIDriver, CSINode, PriorityClass, RuntimeClass, IngressClass,
> CustomResourceDefinition, APIService, CertificateSigningRequest,
> ValidatingWebhookConfiguration, MutatingWebhookConfiguration,
> ValidatingAdmissionPolicy, ValidatingAdmissionPolicyBinding,
> MutatingAdmissionPolicy, MutatingAdmissionPolicyBinding, FlowSchema,
> PriorityLevelConfiguration, GatewayClass, ClusterIssuer, ComponentStatus,
> VolumeSnapshotClass, VolumeSnapshotContent, DeviceClass.

Emitting a cluster-scoped Kind through `extraObjects` requires the opt-in
`allowClusterScopedExtras: true` (warned in NOTES).

## Rendering without a cluster (CI / `helm template`)

Without a cluster, Helm's API discovery is minimal, so CRD-backed objects get
skipped by default. Force-assume the groups you use:

```yaml
capabilities:
  apiVersions:
    - gateway.networking.k8s.io/v1
    - cert-manager.io/v1
    - monitoring.coreos.com/v1
    - security.istio.io/v1beta1
```

The CLI flag works too, but only in the full `group/version/Kind` form:
`helm template --api-versions cert-manager.io/v1/Certificate` (and
`--kube-version <x.y>` to set `.Capabilities.KubeVersion`). A bare
`--api-versions group/version` flag does not satisfy the gate. The library checks
`.Capabilities.APIVersions.Has` with the full `group/version/Kind` string, and
Helm's `Has` is an exact-string membership test: a set containing only
`cert-manager.io/v1` never answers `true` for `cert-manager.io/v1/Certificate`.
You get the nastiest kind of failure, a clean exit 0 with the object silently
missing. Only the `capabilities.apiVersions` values list above accepts the bare
`group/version` form, because the library also matches each entry against the
queried Kind's `group/version`.

## Source of truth

The registry is generated from the `platform.capabilities.registry` YAML block in
[`platform-library/templates/_capabilities.tpl`](https://github.com/caretak3r/helm-factory/blob/main/platform-library/templates/_capabilities.tpl).
Deeper design rationale lives in the
[architecture spec](https://github.com/caretak3r/helm-factory/blob/main/docs/specs/platform-library-v2-architecture.md).
