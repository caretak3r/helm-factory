# Architecture Spec — `platform` Helm Library v2.0.0

This document describes the engineering design of the `platform` library chart
(directory `platform-library/`). It is grounded in the actual template source:
`templates/_capabilities.tpl`, `templates/_util.tpl`, `templates/_app.yaml`,
`values.yaml`, and `Chart.yaml`.

## 1. Chart identity

```yaml
# platform-library/Chart.yaml
apiVersion: v2
name: platform
type: library
version: 2.0.0
appVersion: "2.0.0"
kubeVersion: ">=1.34.0-0 <1.37.0-0"   # Kubernetes 1.34 – 1.36
```

- Pure `type: library`: not installable, contains only `_`-prefixed templates.
- Targets Helm 4.0–4.2 (verified on Helm v4.2.0) and Kubernetes 1.34–1.36 (n-2 policy: the latest supported minor plus two behind).

## 2. Rendering model

### 2.1 The single entrypoint: `platform.render`

A consumer chart's only template file is `templates/app.yaml`:

```yaml
{{ include "platform.render" . }}
```

`platform.render` (in `_util.tpl`) composes three layers, in order:

```
platform.render
├── platform.app            # tier-1: opinionated "primary app" objects
├── platform.extraObjects   # tier-2: generic, declarative long tail
└── platform.extraManifests # raw escape hatch (verbatim / tpl)
```

### 2.2 Tier-1: `platform.app`

Defined in `_app.yaml`. It walks the enabled features in a fixed order and
includes the matching generator, each wrapped in `platform.emit`. The order and
gating (from the source):

| # | Object(s) | Gate |
|---|---|---|
| 1 | ConfigMap | `configMap.enabled` |
| 2 | Pre/post-install script ConfigMaps | `jobs.{preInstall,postInstall}.enabled` and a `script`/`scriptFile` present |
| 3 | Secret | `secret.enabled` |
| 4 | Certificate (cert-manager) | `certificate.enabled` **and** `apiVersionFor "Certificate"` non-empty |
| 5 | TLS secrets (provided certs) | `ingress.enabled` and `ingress.secrets` |
| 6 | Self-signed TLS | `tlsSelfSigned.enabled` |
| 7 | mTLS (Istio PeerAuthentication/AuthorizationPolicy) | `mtls.enabled` **and** `apiVersionFor "PeerAuthentication"` non-empty |
| 8 | PersistentVolumeClaim | `persistence.enabled` |
| 9 | Workload (Deployment/StatefulSet/DaemonSet) | always |
| 10 | HorizontalPodAutoscaler | `autoscaling.enabled` |
| 11 | Service | `service.enabled` |
| 12 | Ingress | `ingress.enabled` |
| 13 | Gateway API (HTTPRoute/GRPCRoute) | `gatewayApi.enabled` **and** `apiVersionFor "HTTPRoute"` non-empty |
| 14 | NetworkPolicy | `networkPolicy.enabled` |
| 15 | PodDisruptionBudget | `podDisruptionBudget.enabled` |
| 16 | ServiceAccount | `serviceAccount.create` or `serviceAccount.name` |
| 17 | ServiceMonitor | `serviceMonitor.enabled` **and** `apiVersionFor "ServiceMonitor"` non-empty |
| 18 | PodMonitor | `podMonitor.enabled` **and** `apiVersionFor "PodMonitor"` non-empty |
| 19 | CronJob | `cronJob.enabled` |
| 20 | Pre-install hook Job | `jobs.preInstall.enabled` |
| 21 | Post-install hook Job | `jobs.postInstall.enabled` |
| 22 | serviceEndpoints ConfigMap | `serviceEndpoints.enabled` |

Note the two-part gate on CRD-backed tier-1 objects (Certificate, mTLS, Gateway
routes, ServiceMonitor, PodMonitor): the feature flag **and** a successful
capability negotiation. This is what lets those objects skip cleanly when the CRD
is absent.

### 2.3 The separator invariant: `platform.emit`

Because everything in v2 renders from a *single* template file (unlike v1's
one-file-per-object layout), adjacent YAML documents would merge without an
explicit separator and cause duplicate-key errors. `platform.emit` prefixes a
`---` to each **non-empty** rendered document:

```gotemplate
{{- define "platform.emit" -}}
{{- $content := . | trim -}}
{{- if $content }}
---
{{ $content }}
{{- end }}
{{- end -}}
```

The non-empty check matters: a generator that renders nothing (e.g. gated out)
must not emit a bare `---` with no body. `platform.extraObjects` and
`platform.extraManifests` apply the same "separator only when non-empty" rule
inline.

## 3. Capability negotiation (`_capabilities.tpl`)

### 3.1 `platform.capabilities.has (list $top "group/version[/Kind]")`

Returns `"true"` (else `""`) when the cluster serves the given API. It unions two
sources:

1. Live discovery: `$top.Capabilities.APIVersions.Has $gvk`.
2. A force-assume override list at `.Values.capabilities.apiVersions`.

Entries in the override list may be `group/version` **or** `group/version/Kind`;
both forms match (the helper compares the full GVK and the group/version prefix).

### 3.2 `platform.capabilities.apiVersion (list $top $prefList)`

Walks an ordered preference list of `group/version/Kind` strings and returns the
first available `group/version` (e.g. `autoscaling/v2`), or `""` if none is
served.

### 3.3 `platform.capabilities.registry`

The canonical `Kind -> ordered preference list` table (a YAML block parsed with
`fromYaml`). The **first** entry per Kind is the preferred (newest GA) version;
betas/older versions follow. Full contents:

**core/v1** (all `["v1/<Kind>"]`): Pod, Service, ConfigMap, Secret,
PersistentVolumeClaim, PersistentVolume, ServiceAccount, Namespace, ResourceQuota,
LimitRange, Endpoints, Event, ReplicationController, PodTemplate.

**apps/v1**: Deployment, StatefulSet, DaemonSet, ReplicaSet, ControllerRevision.

**batch**: Job `["batch/v1"]`; CronJob `["batch/v1"]`.

The registry's floor is Kubernetes 1.34 (`Chart.yaml` `kubeVersion`). Fallback
entries are only kept for `apiVersion`s still served somewhere in the 1.34–1.36
support window; versions removed before 1.34 (`batch/v1beta1`,
`policy/v1beta1`, `autoscaling/v2beta1`, `autoscaling/v2beta2`,
`networking.k8s.io/v1beta1`, `extensions/v1beta1`,
`flowcontrol.apiserver.k8s.io/v1beta3`) are pruned rather than
carried as dead weight. `autoscaling/v1` is kept as the HPA fallback because
that version was never removed upstream.

| Kind | Group | Preference order |
|---|---|---|
| HorizontalPodAutoscaler | autoscaling | `v2`, `v1` |
| PodDisruptionBudget | policy | `v1` |
| Ingress | networking.k8s.io | `v1` |
| IngressClass, NetworkPolicy | networking.k8s.io | `v1` |
| Role, RoleBinding, ClusterRole, ClusterRoleBinding | rbac.authorization.k8s.io | `v1` |
| StorageClass, VolumeAttachment, CSIDriver, CSINode, CSIStorageCapacity | storage.k8s.io | `v1` |
| PriorityClass | scheduling.k8s.io | `v1` |
| RuntimeClass | node.k8s.io | `v1` |
| Lease | coordination.k8s.io | `v1` |
| EndpointSlice | discovery.k8s.io | `v1` |
| ValidatingWebhookConfiguration, MutatingWebhookConfiguration | admissionregistration.k8s.io | `v1` |
| ValidatingAdmissionPolicy, ValidatingAdmissionPolicyBinding | admissionregistration.k8s.io | `v1`, `v1beta1` |
| MutatingAdmissionPolicy, MutatingAdmissionPolicyBinding | admissionregistration.k8s.io | `v1`, `v1beta1` |
| CustomResourceDefinition | apiextensions.k8s.io | `v1` |
| CertificateSigningRequest | certificates.k8s.io | `v1` |
| APIService | apiregistration.k8s.io | `v1` |
| FlowSchema, PriorityLevelConfiguration | flowcontrol.apiserver.k8s.io | `v1` |
| GatewayClass, Gateway, HTTPRoute | gateway.networking.k8s.io | `v1`, `v1beta1` |
| GRPCRoute | gateway.networking.k8s.io | `v1`, `v1alpha2` |
| ReferenceGrant | gateway.networking.k8s.io | `v1beta1`, `v1alpha2` |
| Certificate, Issuer, ClusterIssuer, CertificateRequest | cert-manager.io | `v1` |
| PeerAuthentication, AuthorizationPolicy, RequestAuthentication | security.istio.io | `v1`, `v1beta1` |
| VirtualService | networking.istio.io | `v1`, `v1beta1`, `v1alpha3` |
| DestinationRule, ServiceEntry, Sidecar | networking.istio.io | `v1`, `v1beta1` |
| ServiceMonitor, PodMonitor, PrometheusRule, Probe | monitoring.coreos.com | `v1` |
| VolumeSnapshot, VolumeSnapshotClass, VolumeSnapshotContent | snapshot.storage.k8s.io | `v1` |
| ResourceClaim, ResourceClaimTemplate, DeviceClass | resource.k8s.io | `v1` |

### 3.4 The two negotiation modes — and why

Two Kind-name helpers sit on top of the registry:

- **`platform.capabilities.apiVersionFor (list $top "Kind")`** — *strict*.
  Negotiates from the registry; returns `""` when nothing is served.
  **Skip-if-absent.** Used for CRDs and optional objects: a missing API must mean
  "do not render", so a deploy never conflicts.

- **`platform.capabilities.apiVersionForOrDefault (list $top "Kind")`** —
  negotiate, else fall back to the **first (preferred GA)** registry entry.
  **Never empty.** Used for always-present built-in Kinds so a core workload is
  never silently dropped.

The selector between them is:

- **`platform.capabilities.isStable (list $top "Kind")`** — returns `"true"` when
  the Kind's group (derived from the group of its first registry preference) is in
  the built-in Kubernetes group set (core, apps, batch, autoscaling, policy,
  extensions, networking.k8s.io, rbac.*, storage.k8s.io, scheduling.k8s.io,
  node.k8s.io, coordination.k8s.io, discovery.k8s.io, admissionregistration.k8s.io,
  apiextensions.k8s.io, certificates.k8s.io, apiregistration.k8s.io,
  flowcontrol.apiserver.k8s.io, authentication.k8s.io, authorization.k8s.io,
  events.k8s.io). CRD families (gateway/cert-manager/istio/monitoring) and
  optional built-in groups that require cluster feature support
  (snapshot.storage.k8s.io, resource.k8s.io) return `""`.

**Why the split (the core rationale to preserve):** under bare `helm template`
with no cluster, Helm's default API discovery set is *minimal* — it does not
report the full built-in group set, and reports no CRDs at all. If GA built-ins
were gated *strictly*, negotiation would wrongly return `""` and a core workload
(Deployment, Service, …) would be dropped from a plain `helm template`. So:

- **Built-ins → `OrDefault`**: always render, at the best available version,
  falling back to preferred GA when discovery is silent.
- **CRDs/optional → strict `apiVersionFor`**: never render when absent, so they
  never conflict on a real deploy.

CI and local dev bridge the gap for CRDs by **force-assuming** their groups via
`.Values.capabilities.apiVersions` (see the `full` fixture, which lists
`gateway.networking.k8s.io/v1`, `cert-manager.io/v1`, `security.istio.io/v1beta1`,
`monitoring.coreos.com/v1`).

### 3.5 Cluster-scope handling

`platform.capabilities.isClusterScoped "Kind"` returns `"true"` for the
cluster-scoped set (Namespace, Node, PersistentVolume, ClusterRole,
ClusterRoleBinding, StorageClass, VolumeAttachment, CSIDriver, CSINode,
PriorityClass, RuntimeClass, IngressClass, CustomResourceDefinition, APIService,
CertificateSigningRequest, ValidatingWebhookConfiguration,
MutatingWebhookConfiguration, ValidatingAdmissionPolicy,
ValidatingAdmissionPolicyBinding, MutatingAdmissionPolicy,
MutatingAdmissionPolicyBinding, FlowSchema, PriorityLevelConfiguration,
GatewayClass, ClusterIssuer, ComponentStatus, VolumeSnapshotClass,
VolumeSnapshotContent, DeviceClass). The generic renderer uses it to decide
whether to stamp a `metadata.namespace`.

## 4. The generic renderer (`platform.genericResource`)

`_util.tpl` defines the one renderer that backs the entire long tail:

```gotemplate
include "platform.genericResource" (dict "root" $top "kind" "Role" "resource" $spec)
```

Contract:

1. **apiVersion resolution.** If the spec carries an explicit `apiVersion`, use it.
   Otherwise negotiate: `OrDefault` when `isStable` is true (built-in), strict
   `apiVersionFor` otherwise (CRD). **If no apiVersion is available, emit
   nothing** (skip-if-absent).
2. **Identity.** Sets `apiVersion`, `kind`, `metadata.name`
   (`required` — errors with `extraObjects.<Kind>[].name is required` if missing).
3. **Namespace.** Adds `metadata.namespace` (defaulting to `.Release.Namespace`)
   **unless** the Kind is cluster-scoped or the spec sets `clusterScoped: true`.
4. **Labels/annotations.** Stamps `platform.labels` (standard chart labels),
   merges any `labels`/`annotations` from the spec.
5. **Passthrough.** Every top-level key except the reserved set
   (`name`, `namespace`, `labels`, `annotations`, `apiVersion`, `kind`,
   `clusterScoped`) is emitted verbatim — maps/slices via `toYaml`, scalars
   inline. This is what makes `rules`, `subjects`, `roleRef`, `spec`, `data`,
   `webhooks`, `value`, etc. all work through one renderer with no per-Kind code.

### 4.1 `platform.extraObjects`

Iterates `.Values.extraObjects` (a map of `Kind -> [specs]`), calling
`genericResource` per entry and prefixing `---` only when the render is non-empty
(so absent-API objects leave no stray separator).

### 4.2 `platform.extraManifests`

Iterates `.Values.extraManifests` (a list). String entries are rendered through
`tpl $manifest $top` (so they may contain template expressions); map entries are
emitted with `toYaml`. The consumer supplies the full `apiVersion`/`kind` — this
layer does **no** negotiation, labelling, or namespacing.

## 5. The merge overlay and the "gate outside `fromYaml`" invariant

`platform.util.merge (list $top "overridesTpl" "baseTpl")` is a bitnami-common
style overlay: it `fromYaml`s an overrides template over a base template with
`mergeOverwrite` and re-emits via `toYaml`. It is available for advanced
consumers who want to override a base tier-1 template.

**Invariant — gate outside `fromYaml`:** capability/enable gating must happen in
the *wrapper* **before** calling `platform.util.merge` (or before invoking a
generator at all). `fromYaml ""` yields `{}`, which would serialize to a bogus
empty document. The wrapper must decide "render or not" first; the merge helper
assumes it is only ever called when a document is actually wanted. This is the
same reasoning behind `platform.emit`'s non-empty guard.

## 6. Values contract (`exports.defaults` + `import-values: [defaults]`)

All defaults live under `exports.defaults` in the library's `values.yaml`. A
consumer's `import-values: [defaults]` merges them into the consumer's **root**
scope. The contract has three tiers:

- **Tier-1 (opinionated blocks):** `workload`, `image`, `ports`, `service`,
  `ingress`, `gatewayApi`, `autoscaling`, `podDisruptionBudget`, `persistence`,
  `configMap`, `secret`, `certificate`, `mtls`, `tlsSelfSigned`, `jobs`,
  `cronJob`, `serviceAccount`, `serviceMonitor`, `podMonitor`, `networkPolicy`,
  `serviceEndpoints`, `highAvailability`, security contexts, scheduling, labels,
  etc. Each has an `enabled` flag where applicable.
- **Tier-2 — `extraObjects`:** a **map** of
  `Kind: [ {name, namespace?, labels?, annotations?, clusterScoped?, …passthrough} ]`.
  Default `{}`.
- **Raw — `extraManifests`:** a **list** of full manifest maps or template
  strings. Default `[]`.
- **`capabilities.apiVersions`:** the force-assume list. Default `[]`.

### 6.1 Value-schema validation (`values.schema.reference.json`)

The root-contract JSON Schema ships as
`platform-library/values.schema.reference.json` — deliberately **not** as a magic
`values.schema.json` at the library root. Helm auto-validates a chart's values
against a `values.schema.json` in that chart's directory; the library's own
values are wrapped under `exports.defaults`, so a root schema describing the
*post-import* (unwrapped) contract would validate against the wrapped structure
and fail. The reference file (`$schema` draft-07 — Helm's built-in `gojsonschema`
validator only implements draft-04 through draft-07, so the declared dialect
must match what Helm actually enforces (helm/helm#13069) — `title:
"platform-library consumer values"`, `additionalProperties: true`) instead
documents the contract for **consumers**: the scaffold generator copies it into
each consumer chart as `values.schema.json`, where the post-import root values
do match it (e.g. it requires `image.repository`, constrains `workload.type` to
the three workload Kinds, `image.pullPolicy` to the pull-policy enum, and
`podSecurityContext`/`containerSecurityContext`/`networkPolicy.policyTypes`/
`serviceAccount.name`/`ingress.hostname` to typed, pattern-constrained shapes,
etc.). `scripts/lint-library.sh`
validates the reference file against its metaschema and every fixture's values
against it (`check-jsonschema`), and `tests/render.sh` copies it into each
fixture as `values.schema.json` so Helm itself enforces the contract on every
rendered fixture.

**Naming note (collision avoidance):** container resource requests/limits stay
under `resources:` (a tier-1 block). The tier-2 long tail is deliberately named
`extraObjects`, **not** `resources`, so the two never collide.

## 7. Scaffold generator (`scripts/new-app-chart.sh`)

`scripts/new-app-chart.sh <name>` scaffolds a ready-to-render consumer chart.

```
scripts/new-app-chart.sh <name> \
  [--dir <path>] \
  [--repo <url, default file://../platform-library>] \
  [--version <range, default ">=2.0.0-0">] \
  [--app-version <v>]
```

It produces a consumer chart wired with:

- a `Chart.yaml` declaring the `platform` dependency **with** `import-values: [defaults]`
  (using the `--repo`/`--version`/`--app-version` values),
- `templates/app.yaml` = `{{ include "platform.render" . }}`,
- an overrides-only `values.yaml`,
- a `.helmignore`,
- a `values.schema.json` copied from `platform-library/values.schema.reference.json`
  (see §6.1) so the consumer's post-import root values are schema-validated.

## 7a. Library validation gate (`scripts/lint-library.sh`)

`scripts/lint-library.sh` is the single validation gate for the pure library
(which, being uninstallable, is validated through the fixture consumers). It runs:

1. `helm lint` on `platform-library/`.
2. Values-contract validation: metaschema check plus per-fixture
   `check-jsonschema` validation, and helm-side enforcement via the schema
   copied into each fixture (negative legs prove e.g. `workload.type=deployment`,
   `image.tag=latest`, `networkPolicy.policyTypes[0]=Bogus`, a negative
   `podSecurityContext.fsGroup`, a lowercase
   `containerSecurityContext.capabilities.drop` entry, and a non-RFC1123
   `serviceAccount.name`/`ingress.hostname` are all rejected).
3. The render matrix — `tests/render.sh <fixture> --kube-version <kv>` for both
   `minimal` and `full` across `--kube-version 1.34 … 1.36`.
4. `kubeconform -strict -ignore-missing-schemas` on each fixture render (when
   `kubeconform` is on `PATH`).
5. A **negative render** — `tests/render.sh full --set capabilities.apiVersions=null`
   — asserting that no CRD-backed Kind (Certificate, HTTPRoute, GRPCRoute,
   PeerAuthentication, AuthorizationPolicy, ServiceMonitor, PodMonitor) rendered,
   and that no empty `{}` document was emitted.
6. Posture guardrails and `platform.notes` (`NOTES.txt`) warning checks — via
   `helm install --dry-run=client` (NOTES only renders on install/upgrade, never
   `helm template`) — asserting the `secret.stringData`/`secret.data` and
   `ingress.secrets` warnings fire when set and stay silent otherwise, and that
   `helm template` output never includes NOTES content.

## 8. Test strategy

A pure library is not installable and renders only through a consumer, so tests
use fixture consumer charts under `tests/fixtures/`:

- **`minimal`** — workload + service only.
- **`full`** — exercises every tier-1 generator, all four CRD families
  (force-assumed via `capabilities.apiVersions`), a broad `extraObjects` map, and
  an `extraManifests` entry.

`tests/render.sh <fixture> [helm args…]` removes any cached `charts/`/`Chart.lock`,
runs `helm dependency update`, then `helm template`. Verified checks:

- `helm lint` clean.
- Render matrix across `--kube-version 1.34 … 1.36`.
- **Negative render:** `--set capabilities.apiVersions=null` proves CRD-backed
  objects drop while built-ins remain (validates the OrDefault-vs-strict split)
  and that no empty `{}` document is emitted.
- `kubeconform -ignore-missing-schemas` clean (CRD objects are skipped locally for
  lack of installed schemas).

Both fixture `Chart.yaml` files declare the `platform` dependency at
`version: ">=2.0.0-0"` with `repository: file://../../../platform-library` and
`import-values: [defaults]`. `scripts/lint-library.sh` wraps all of the above.
