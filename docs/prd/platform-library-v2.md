# PRD — `platform` Helm Library Chart v2.0.0

- **Chart name:** `platform` (source directory: `platform-library/`)
- **Type:** `library` (Helm library chart — not installable on its own)
- **Version:** `2.0.0`
- **Status:** Shipped
- **Maintainer:** Rohit Gudi (<caret4k3r@gmail.com>)

## 1. Problem

The v1 library (`platform-library`) generated Kubernetes manifests from a single
opinionated configuration, but it carried three structural problems:

1. **It self-rendered.** The chart shipped ~25 non-underscore wrapper templates
   (`deployment.yaml`, `service.yaml`, `app.yaml`, …) alongside the `_`-prefixed
   implementations. A `library` chart that emits objects on its own is a
   category error: it cannot be installed, yet it behaves as if it could, and
   consumers had no clean, single entrypoint to compose against.
2. **API versions were hard-coded.** HPA, Ingress, PDB, CronJob, Certificate,
   mTLS, Gateway API, ServiceMonitor and PodMonitor all pinned a fixed
   `apiVersion`. Across a fleet spanning Kubernetes 1.31–1.36 (and clusters that
   may or may not have cert-manager, Istio, Gateway API, or the Prometheus
   Operator installed) this produces manifests that either fail admission or
   silently target a version the cluster no longer serves.
3. **It only modelled the opinionated "primary app" objects.** Anything outside
   that set (an RBAC `Role`, a `PriorityClass`, a `ResourceQuota`, a webhook
   config) had nowhere to live, forcing consumers to fork the library or drop
   raw YAML into their own charts and lose the standard labelling/namespacing.

v1 also did not lint cleanly: it contained committed git-conflict markers, a
missing `{{- end }}` in `_helpers.tpl`, and a malformed `cronJob.initContainers`
/`sidecars` default (a `{enabled, containers}` map where a list was expected).

## 2. Goals

- **G1 — Pure library.** Ship a `type: library` chart with exactly one public
  entrypoint, `platform.render`. `helm install` of the library itself must fail
  (correct behaviour for a library).
- **G2 — Capability negotiation.** Every generated object picks the best
  `apiVersion` the target cluster actually serves, from a canonical preference
  table (newest GA first, then betas). Built-in workloads are never dropped;
  CRD-backed objects skip themselves when their API is absent so a deploy never
  conflicts.
- **G3 — Long-tail coverage.** Provide a generic, capability-gated renderer that
  can emit *any* Kubernetes Kind with standard labels and namespace handling,
  exposed to consumers as a declarative `extraObjects` map, plus a raw
  `extraManifests` escape hatch.
- **G4 — Clean toolchain.** `helm lint` clean; renders cleanly across the whole
  target Kubernetes matrix under bare `helm template` (no live cluster);
  `kubeconform` clean for objects with known schemas.
- **G5 — Low-friction consumption.** A consumer chart should need only a
  dependency declaration and a one-line `templates/app.yaml`, scaffolded by a
  generator that also wires up value-schema validation.

## 3. Non-goals

- **Not a Kubernetes schema validator.** The generic renderer passes spec fields
  through verbatim. It does not validate field names, types, or enum values
  against the OpenAPI schema of the target Kind — that is `kubeconform`/API-server
  admission's job.
- **Not per-field opinionated for the long tail.** Tier-1 objects
  (workload/service/ingress/…) remain opinionated with curated defaults.
  `extraObjects`/`extraManifests` are intentionally thin: they stamp identity
  (apiVersion, labels, namespace) and otherwise get out of the way.
- **Not a cluster bootstrapper.** The library does not install CRDs
  (cert-manager, Istio, Gateway API, Prometheus Operator); it negotiates against
  whatever the cluster already serves.
- **Not a policy engine.** No OPA/Kyverno-style enforcement; it renders manifests.

## 4. Users & workflows

| Persona | Owns | Workflow |
|---|---|---|
| **Platform team** | The `platform` library, the capability registry, tier-1 generators, the negotiation rules. | Maintains `platform-library/`, extends the registry when new API groups/versions ship, keeps the render/lint matrix green. |
| **Service teams** | A consumer product chart. | Scaffold a chart that depends on `platform`, then configure via values only: toggle tier-1 features (`service.enabled`, `ingress.enabled`, …), add long-tail objects under `extraObjects`, drop truly bespoke YAML under `extraManifests`. They never write templates beyond the one-line `templates/app.yaml`. |

Typical service-team loop:

```bash
# 1. Depend on the library (Chart.yaml), including the MANDATORY import-values.
# 2. templates/app.yaml is exactly:  {{ include "platform.render" . }}
# 3. Override in values.yaml only.
helm dependency update .
helm template my-service .            # renders locally, no cluster needed
helm install  my-service .            # negotiates against the live cluster
```

## 5. Requirements & acceptance criteria

### R1 — Pure library, single entrypoint
- The chart is `type: library`; it contains only `_`-prefixed templates.
- `platform.render` is the sole public entrypoint; it composes
  `platform.app` (tier-1) + `platform.extraObjects` (tier-2) + `platform.extraManifests` (raw).
- **Accept:** a consumer whose only template is `{{ include "platform.render" . }}`
  renders all enabled objects; `helm install` of the library alone fails.

### R2 — Capability negotiation for every object
- A canonical registry maps every built-in creatable Kind plus the shipped CRD
  families to an ordered `group/version/Kind` preference list.
- Built-in Kinds use *negotiate-or-default* (never empty); CRD/optional Kinds use
  *strict negotiate* (skip when absent).
- Consumers/CI can force-assume APIs via `.Values.capabilities.apiVersions`.
- **Accept:** under bare `helm template` (minimal discovery set) all built-in
  workloads still render at their preferred GA version; with
  `capabilities.apiVersions` cleared, CRD-backed objects (Certificate, mTLS,
  Gateway routes, ServiceMonitor/PodMonitor) drop while the Deployment/Service/etc.
  remain.

### R3 — Long-tail (`extraObjects`) and raw (`extraManifests`)
- `extraObjects` is a map of `Kind -> [ {name, namespace?, labels?, annotations?, clusterScoped?, …passthrough} ]`.
- Each entry is capability-negotiated, standard-labelled, and namespace-stamped
  unless the Kind is cluster-scoped; every non-reserved top-level key passes
  through verbatim.
- `extraManifests` is a list of full manifest maps or template strings (strings
  rendered through `tpl`).
- **Accept:** the `full` fixture renders `Role`, `RoleBinding`, `ServiceAccount`,
  `ClusterRole`, `PriorityClass`, `ResourceQuota`, `ConfigMap` via `extraObjects`
  and a raw `ConfigMap` via `extraManifests`, each carrying standard labels and
  correct namespace scoping.

### R4 — Clean toolchain across the matrix
- **Accept:** `scripts/lint-library.sh` passes — `helm lint` clean; the reference
  schema parses; `tests/render.sh full` and `tests/render.sh minimal` render
  without error across `--kube-version 1.31 … 1.36`; a negative render with
  `--set capabilities.apiVersions=null` proves CRD objects drop, built-ins remain,
  and no empty `{}` documents are emitted; `kubeconform -ignore-missing-schemas` clean.

### R6 — Low-friction scaffolding
- `scripts/new-app-chart.sh <name>` scaffolds a ready-to-render consumer chart
  pre-wired with the `platform` dependency (including `import-values: [defaults]`),
  a one-line `templates/app.yaml`, an overrides-only `values.yaml`, `.helmignore`,
  and a `values.schema.json` copied from the library's reference schema.
- **Accept:** a chart produced by the generator renders via `helm dependency update && helm template`
  with no further edits beyond filling in overrides.

### R5 — Correct metadata
- **Accept:** `Chart.yaml` carries `type: library`, `version: 2.0.0`,
  `kubeVersion: ">=1.31.0-0 <1.37.0-0"`.

## 6. Version & support matrix

| Dimension | Supported |
|---|---|
| Helm | 4.0 – 4.2 (developed/verified against Helm **v4.2.0**) |
| Kubernetes | 1.31 – 1.36 (`kubeVersion: ">=1.31.0-0 <1.37.0-0"`) |
| Built-in API groups | core, apps, batch, autoscaling, policy, networking.k8s.io, rbac, storage.k8s.io, scheduling.k8s.io, node.k8s.io, coordination.k8s.io, discovery.k8s.io, admissionregistration.k8s.io, apiextensions.k8s.io, certificates.k8s.io, apiregistration.k8s.io, flowcontrol.apiserver.k8s.io |
| CRD families (negotiated, skip-if-absent) | Gateway API (`gateway.networking.k8s.io`), cert-manager (`cert-manager.io`), Istio (`security.istio.io`, `networking.istio.io`), Prometheus Operator (`monitoring.coreos.com`) |

## 7. Success metrics

- `helm lint platform-library/` reports 0 errors.
- Render matrix (`minimal` + `full` × K8s 1.31–1.36) renders with 0 errors.
- **Zero `apiVersion` conflicts** on target clusters at deploy time (no object
  submitted at a version the API server does not serve).
- CRD-backed objects **skip** cleanly when their API is absent (verified by the
  negative render) — never a hard failure, never a conflicting apply.
- `kubeconform -ignore-missing-schemas` clean.

## 8. Risks & open questions

**Risks**

- **Upgrade churn from capability drift.** An object that appears/disappears as a
  CRD is installed/removed will be created or pruned on the next `helm upgrade`.
  A beta→GA `apiVersion` shift for an existing object can force a resource
  *replace* rather than an in-place update.
- **Immutable fields.** `spec.selector` (and similar immutable fields) must not be
  changed via overrides on live objects; the pre-existing note about mutable
  labels leaking into the Service selector still applies.
- **`import-values: [defaults]` omission** is the #1 integration footgun — without
  it the library's `exports.defaults` never reach the consumer's root scope and
  every value renders empty. See the migration guide.
- **Registry completeness.** The negotiation is only as good as the registry; a
  Kind or API group not listed cannot be negotiated (built-ins fall through the
  generic renderer only if present in the registry).

**Open questions**

- Should `extraObjects` grow light validation (e.g. reject a Kind absent from the
  registry with a helpful `fail`) or stay fully permissive?
