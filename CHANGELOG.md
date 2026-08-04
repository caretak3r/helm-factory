# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions track the `platform-library` chart version (`platform-library/Chart.yaml`);
releases are tagged `vX.Y.Z` and published to `oci://ghcr.io/caretak3r/charts`.

## [Unreleased]

### Added — contributor toolchain (`Makefile`, `make tools`)

- New `Makefile` with the checks CI runs: `make lint` (every CI step, in CI's
  order), plus `shellcheck`, `helm-lint`, `schema-meta`, `gate`, `smoke`,
  `fast`, `render`, `golden`, `clean` and `help`.
  `.github/workflows/{ci,release}.yaml` now invoke these targets instead of
  carrying their own copies of the commands, so `make lint` is byte-identical
  to CI by construction rather than by discipline. `make gate` sets
  `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1` itself — the two knobs a
  local run used to omit.
- New `scripts/lib/tool-versions.sh` is the single source of truth for the
  toolchain: helm and kubeconform versions with their download checksums, the
  check-jsonschema pin, and the minimum-version floor and install hint for each
  required tool. Both workflows source it; the duplicated install blocks (kept
  in sync by a comment) are gone.
- New `scripts/check-tools.sh` verifies the local toolchain and is a
  prerequisite of every checking target, so a fresh clone with nothing
  installed fails on the first `make lint` with **all** missing tools named at
  once and an install line for each, rather than one per re-run. Silent when
  everything is fine. `make tools` (`--list`) prints the full table, flagging
  versions that differ from the CI pins.

### Fixed — CI/tooling

- `scripts/lint-library.sh`'s NOTES helper no longer discards stderr from
  `helm dependency update`. A failed dependency update left a stale `charts/`
  in place, so every NOTES assertion downstream silently tested the *previous*
  library build and reported OK; it now surfaces the error and fails the leg.

### Added — RBAC (`rbac.enabled`)

- New namespaced RBAC generator. `rbac.enabled: true` with a `rbac.rules` list
  renders a `Role` and a `RoleBinding` for the chart's own ServiceAccount. The
  binding subject resolves through `platform.serviceAccountName`, so it follows
  a `serviceAccount.name` override instead of drifting — previously every app
  that needed API access hand-rolled both objects through `extraObjects` and
  kept the subject in sync by hand. `rbac.name`, `rbac.annotations` and
  `rbac.labels` are supported; `commonLabels`/`commonAnnotations` apply, with
  the `rbac.*` maps winning on key collision.
- Fails closed on two shapes: `rbac.enabled: true` with empty `rbac.rules` (a
  Role that grants nothing, surfacing later as a runtime 403), and
  `rbac.enabled: true` with `serviceAccount.create: false` and no
  `serviceAccount.name` — which would bind the Role to the namespace's
  `default` ServiceAccount and grant the rules to every pod in the namespace
  that does not name its own identity.
- New NOTES warnings: RBAC enabled while
  `serviceAccount.automountServiceAccountToken` is false (the library default —
  the grant has no token to be used with), and `"*"` wildcards in
  `rbac.rules[].apiGroups`/`resources`/`verbs`, reported with their paths.
- `values.schema.reference.json` constrains the rule shape: `apiGroups`,
  `resources` and `verbs` are required per rule, and `nonResourceURLs` (a
  ClusterRole-only field the API server silently ignores in a namespaced Role)
  is rejected. Cluster-scoped RBAC is deliberately not generated here — it
  stays behind `extraObjects` + `allowClusterScopedExtras`.

### Fixed — image resolution

- `platform.imageRef` no longer double-prefixes the registry when
  `image.repository` (or a dict-form sidecar/init/hook repository) already
  starts with the resolved registry host — e.g. `docker.io/library/busybox`
  with the default `image.registry: docker.io` now renders
  `docker.io/library/busybox:<tag>`, not `docker.io/docker.io/...`. The hook
  Job path had a prefix guard with inverted `hasPrefix` arguments; both paths
  now share the same (correct) semantics. Unqualified repositories are
  prefixed exactly as before.

### Fixed — hook Jobs

- A hook Job enabled with no `script`, `scriptFile`, or `command` now fails at
  template time with a named error pointing at `jobs.preInstall`/`jobs.postInstall`
  (previously: a Go `reflect` crash from the template engine). A hook Job with
  `command` set and `args` empty also no longer crashes. To run the image's own
  ENTRYPOINT, set it explicitly via `command`.

### Added — NOTES warnings for weakened posture and escape hatches

- `platform.notes` now warns when `containerSecurityContext` weakens the
  hardened defaults (`privileged`, `allowPrivilegeEscalation`,
  `runAsNonRoot=false`, `runAsUser=0`, non-NET_BIND_SERVICE `capabilities.add`,
  `seccompProfile.type=Unconfined`), when `containerSecurityContext.enabled=false`
  or `podSecurityContext.enabled=false` disables hardening outright, and when
  the `mtls.allowAllPrincipals` or `allowClusterScopedExtras` escape hatches
  are active. Warnings appear on `helm install`/`upgrade` (including
  `--dry-run`); rendered manifests are unchanged.

### Fixed — capability negotiation

- `AuthorizationPolicy` and `GRPCRoute` are now capability-negotiated
  individually instead of riding the `PeerAuthentication`/`HTTPRoute` gates.
  **Behavior change:** on clusters that serve the sibling API but not these
  CRDs, the objects are now skipped (and named in the NOTES `SKIPPED KINDS`
  warning) instead of rendering an apiVersion the cluster does not serve and
  failing at apply time. Explicit `gatewayApi.apiVersion` /
  `gatewayApi.grpcRoute.apiVersion` overrides still force emission.

### Changed — capability gating

- Capability gating is now driven by a single structured feature registry
  (`platform.capabilities.features`) declaring each feature's full emitted
  Kind set and a composition policy. `mtls` is atomic: on clusters that serve
  `PeerAuthentication` but not `AuthorizationPolicy`, the whole mTLS pair is
  now skipped (fail closed) instead of rendering a `PeerAuthentication`
  without its principal-restricting `AuthorizationPolicy`. `gatewayApi` routes
  negotiate per Kind. The NOTES `SKIPPED KINDS` warning now covers secondary
  Kinds (`AuthorizationPolicy`, `GRPCRoute`), including atomic Kinds held back
  by a missing partner API. The lint gate's capability anti-drift check now
  compares registry, gate sites and emitters by CONTENT in both directions
  (superseding the earlier count and name-set comparisons), so a Kind added to
  a generator but not to its feature's row is structurally detectable.
  (plans/010, follows plans/005.)

### Changed — release engineering

- CI/release/docs workflows now checksum-pin the helm and kubeconform
  downloads, pin all GitHub Actions to commit SHAs, and pin
  `check-jsonschema`; schema vendoring sources are pinned to commit SHAs.
  Docs workflow permissions are scoped per job. New
  `scripts/preflight-release.sh` validates tag readiness before tagging.

### Fixed — extraObjects fail-closed and skip visibility

- **Behavior change:** an `extraObjects` entry whose Kind is not in the
  platform capability registry now FAILS at template time with a named error
  (previously the object was silently dropped from the render). Set
  `apiVersion` explicitly on the entry to render it verbatim, or use
  `extraManifests`.
- Registry-known `extraObjects` entries whose API the cluster does not serve
  are still skipped (never emit an unserved apiVersion), but are now reported
  in a `SKIPPED EXTRA OBJECTS` NOTES warning naming each `Kind/name` and the
  apiVersions tried — the same contract tier-1 gated Kinds already have.

### Fixed — ServiceMonitor double-match

- The default ServiceMonitor selector no longer double-matches a StatefulSet's
  managed headless Service. Both Services carried identical label sets, so
  `matchLabels: platform.selectorLabels` selected the primary *and* the
  headless Service and Prometheus Operator generated two scrape targets for
  the same pods (duplicate series, doubled `up` counts). The managed headless
  Service now carries `platform/service-role: headless`, and the default
  selector adds a `matchExpressions` entry excluding it. An explicit
  `serviceMonitor.selector` is still used verbatim — it replaces the default
  selector, exclusion included. `PodMonitor` was never affected (it selects
  pods, not Services). The stateful fixture now enables `serviceMonitor`, and
  `scripts/lint-library.sh` gained a guarded, mutation-tested
  `ServiceMonitor does not double-match` gate section (helm-factory-75c).
  **Behavior change:** the headless Service gains one label; consumers that
  wrote their own selector matching *every* Service of the release should
  confirm they still want both targets.
### Added — PodDisruptionBudget eviction policy

- `podDisruptionBudget.unhealthyPodEvictionPolicy` — optional passthrough for
  the PDB's `unhealthyPodEvictionPolicy` field (GA since Kubernetes 1.31).
  Set to `AlwaysAllow` to let node drains evict permanently-unhealthy pods
  instead of deadlocking under the default `IfHealthyBudget` behavior.
  Empty string (default) omits the field, preserving current behavior. Any
  other value fails at template time with a named error (guarded,
  mutation-tested gate section included).

### Added — container resizePolicy

- Container `resizePolicy` passthrough for in-place pod vertical scaling
  (`InPlacePodVerticalScaling`, GA in the 1.34-1.36 supported window). New
  additive `resizePolicy` values key (list of `{resourceName, restartPolicy}`,
  same shape as the native Kubernetes container field) on the main workload
  container, threaded through to the CronJob fallback container and the
  pre/post-install hook Job main container via the shared `jobs.resizePolicy`
  default. `sidecars.containers` and `initContainers.containers` entries
  accept the same key directly since they are already verbatim per-container
  passthrough lists (helm-factory-7dm).

### Added — pod-spec long-tail fields

- Four pod-spec long-tail fields — `runtimeClassName`, `dnsPolicy`/`dnsConfig`,
  `shareProcessNamespace`, and pod-level `os` — as new top-level values keys,
  rendered verbatim (and omitted unless explicitly set, matching the existing
  `priorityClassName`/`schedulerName` convention) across all three pod-spec
  render sites: the main workload, the CronJob, and the pre/post-install hook
  Jobs (helm-factory-4qe).

### Added — Service long-tail fields

- Service long-tail fields: dual-stack `service.ipFamilies` /
  `service.ipFamilyPolicy`, `service.internalTrafficPolicy`,
  `service.trafficDistribution` (topology-aware routing), and
  `service.publishNotReadyAddresses`. All five are unset by default and
  render only when the consumer sets them. `publishNotReadyAddresses` is
  also threaded through the library-managed headless Service, which matters
  for StatefulSet peer discovery during initial bootstrap (helm-factory-utm).

### Added — ResourceQuota and LimitRange generators

- First-class `resourceQuota` and `limitRange` generators for namespace QoS
  governance, following the dedicated-namespace-per-app model: `resourceQuota`
  renders a `v1/ResourceQuota` from a verbatim `hard` passthrough plus optional
  `scopes`/`scopeSelector`; `limitRange` renders a `v1/LimitRange` with a
  single `Container`-type item (`default`/`defaultRequest`/`max`/`min`, opt-in
  `type` override for `Pod`/`PersistentVolumeClaim`). Both are opt-in
  (`enabled: false` by default), always-GA built-ins (no capability gate), and
  fail closed when enabled with nothing to enforce (empty `hard`, or none of
  `default`/`defaultRequest`/`max`/`min` set). `limitRange.default`/
  `defaultRequest` is the namespace-level backstop for a workload that renders
  with no `resources:` set (BestEffort QoS).

### Added — PrometheusRule generator

- First-class `prometheusRule:` values block and `_prometheusrule.yaml`
  generator for Prometheus Operator `PrometheusRule` objects (alerts and
  recording rules), the missing third leg of the observability story
  alongside `serviceMonitor`/`podMonitor`. `PrometheusRule` is registered in
  the `platform.capabilities.features` registry, so it negotiates its
  apiVersion and skips (with a NOTES warning) like the other Prometheus
  Operator CRDs when the `monitoring.coreos.com` API isn't served or
  force-assumed. `groups` is a verbatim passthrough of Prometheus rule
  groups — the same free-form treatment as `serviceMonitor.relabelings`.
  Fails closed when enabled with empty `prometheusRule.groups`: a rule
  object with no groups enforces nothing.

### Added — VerticalPodAutoscaler generator

- `VerticalPodAutoscaler` (`autoscaling.k8s.io/v1`) support: a new registry
  entry (unblocks `extraObjects` for VPA) plus a first-class
  `verticalAutoscaling` values block (`enabled`, `updateMode`, generator-gated
  and capability-gated the same way as Certificate/ServiceMonitor/PodMonitor).
  `updateMode` is validated against `Off`/`Initial`/`Recreate`/`Auto` and
  `resourcePolicy` is a verbatim passthrough to `spec.resourcePolicy`;
  `targetRef` auto-wires to the chart's own workload. Enabling
  `verticalAutoscaling` alongside `autoscaling` (HPA) while HPA scales on
  CPU/memory now fails closed at render time unless `updateMode: Off`
  (recommend-only) — the two would otherwise fight over the same resource
  (`helm-factory-ocx`).

### Added — NOTES warning for BestEffort QoS containers

- `NOTES.txt` now warns when a container that will actually render — the main
  container, or an enabled entry under `sidecars.containers` /
  `initContainers.containers` — has no `resources.requests` or
  `resources.limits` configured, so it runs at BestEffort QoS (first evicted
  under node memory pressure, unbounded otherwise). The library's default stays
  `resources: {}` — this is a NOTES-only warning, not a values-contract change,
  and it has zero effect on rendered manifests: shipping default
  requests/limits remains a possible future follow-up, reserved for a separate
  decision. The warning names every offending container; `scripts/lint-library.sh`
  gained a mutation-tested `NOTES: containers with no resources configured`
  section covering the zero-config case, setting resources on the main
  container, and setting/omitting resources on sidecars and initContainers
  independently (hf-uup).

### Added — consumer schema sync script

- `scripts/sync-consumer-schema.sh <consumer-chart-dir>` refreshes a consumer
  chart's `values.schema.json` from `platform-library/values.schema.reference.json`.
  `scripts/new-app-chart.sh` only copies that schema once, at scaffold time, so
  a consumer that later bumped its `platform` dependency kept validating against
  the old contract with no warning. The script reads the chart's declared
  `platform` dependency version, reports the top-level values keys added or
  removed plus a truncated unified diff, and supports `--dry-run` for a
  report-only pass. It exits 0 without writing when the copy is already in sync.
  Documented in README.md and printed in the scaffold's onboarding output
  (hf-th2).

### Added — schema sync `--check` mode

- `scripts/sync-consumer-schema.sh` gained a `--check` mode: it reports drift
  exactly like `--dry-run` (writing nothing) but exits 1 when the consumer's
  `values.schema.json` is DRIFTED or MISSING and 0 when it is already in sync.
  A consumer chart can now gate its own CI on schema drift after bumping its
  `platform` dependency, instead of relying on someone reading `--dry-run`
  output (helm-factory-cuk).

## [2.1.0] - 2026-07-20

Correctness batch: thirteen library defects fixed since 2.0.0, all with new
guarded, mutation-tested `scripts/lint-library.sh` sections. Minor bump — the
only new values key is the additive `service.externalName`; the remaining
behavior shifts are corrections toward documented intent, each flagged
**Behavior change:** inline below. Upgraders should skim these before a
`helm upgrade`: StatefulSet/DaemonSet pods now roll on config/secret changes,
Ingress/Gateway API resource-specific annotations now beat `commonAnnotations`,
`gatewayApi.apiVersion` now negotiates per route, `service.type: ExternalName`
and empty `certificate.issuer`/`ingress`-without-`service` now fail closed, and
StatefulSets get an auto governing headless Service.

### Fixed — workload templates

- Config/Secret checksum rollout annotations (`checksum/config`,
  `checksum/secret`) now apply to StatefulSet and DaemonSet pod templates, not
  just Deployments — previously a `helm upgrade` changing `configMap.data` or
  `secret.stringData` left StatefulSet/DaemonSet pods running stale config
  until manually rolled. The helper is renamed
  `platform.rolloutAnnotations`; `platform.deployment.rolloutAnnotations`
  remains as a deprecated alias. The full fixture now enables `configMap` to
  snapshot the Deployment path, and `scripts/lint-library.sh` gained a
  `rollout checksum` gate asserting the annotations reach the full and
  stateful pod templates (hf-bk0).
- `imagePullSecrets` are now deduped by name across `global.imagePullSecrets`
  and `image.pullSecrets` (global entries first) in all three pod specs that
  aggregate them — workload pod template, CronJob, and hook Job. A secret
  named in both values paths previously rendered twice.
  `scripts/lint-library.sh` gained a dedupe/ordering gate covering all three
  sites (hf-k9c).
- An unknown `workload.type` now fails the render in-template with the allowed
  values listed (`Deployment`, `StatefulSet`, `DaemonSet`), instead of silently
  rendering a Deployment for consumers who don't copy `values.schema.json`.
  Unset/empty `workload.type` still defaults to Deployment.
  `scripts/lint-library.sh` gained a schema-less negative render asserting the
  in-template failure (hf-klw).
- Passthrough containers (`sidecars`, `initContainers`, `cronJob.containers`/
  `initContainers`, hook-Job sidecars) now get image resolution and a pull
  policy default via `platform.hardenContainers`. A container `image` written
  as a dict (`registry`/`repository`/`tag`/`digest`, optional `pullPolicy`)
  resolves exactly like the main `image` block — `global.imageRegistry`
  applies and rendering fails without a `tag` or `digest` pin — so mirrored/
  air-gapped installs no longer silently pull sidecars from docker.io.
  Plain-string images still render verbatim (never registry-prefixed, so
  fully-qualified references can't be double-prefixed). Containers without an
  explicit `imagePullPolicy` now render the resolved library default
  (`global.imagePullPolicy`, else the dict's `pullPolicy`, else
  `image.pullPolicy`, else `IfNotPresent`) — previously sidecars ignored
  `global.imagePullPolicy` entirely. `scripts/lint-library.sh` gained a
  `passthrough container image resolution` gate (dict resolution, string
  passthrough, and two negative pins) (helm-factory-4lc).

### Fixed — networking and TLS

- The Ingress `spec.tls` secretName now converges with the release-managed TLS
  Secret: with `ingress.tls` enabled and no `ingress.existingSecret`, the
  Ingress references the Secret `tlsSelfSigned` actually writes (or the
  `certificate` block's `spec.secretName`) instead of the conventional
  `<hostname>-tls` that nothing creates unless the hostname happens to equal
  the fullname. The name comes from a new shared helper
  `platform.tlsSecretName` (`<fullname>-tls`) used by `_tls-selfsigned.yaml`,
  `_certificate.yaml`, and `_ingress.yaml` so writer and reader can never
  disagree. `ingress.existingSecret` still wins, and without any managed cert
  source the `<hostname>-tls` fallback is preserved. `scripts/lint-library.sh`
  gained a four-leg `TLS secret name convergence` gate (hf-bly).
- Removed the dead value `ingress.selfSigned` from `platform-library/values.yaml`
  — it was read by no template (the real knob is `tlsSelfSigned.enabled`) and
  misled consumers. It was never in the reference schema. (`global.storageClass`,
  the other dead knob named by hf-bly, was already removed in #25.) (hf-bly)
- StatefulSets now get a resolvable governing headless Service by default.
  `spec.serviceName` previously defaulted to `<fullname>` — a Service that
  doesn't exist unless `service.enabled: true`, and is a ClusterIP VIP when it
  does — so stable per-pod DNS (`<pod>.<svc>.<ns>`) never resolved. When
  `workload.type: StatefulSet` and `statefulSet.serviceName` is unset, the
  library now renders a headless Service `<fullname>-headless` (`clusterIP:
  None`, same selector/ports as the primary Service) and points
  `spec.serviceName` at it. An explicit `statefulSet.serviceName` is used
  verbatim, and a primary Service that is already headless
  (`service.clusterIP: None`) governs directly with no extra Service. The
  stateful golden gained the new Service, and `scripts/lint-library.sh` gained
  a four-leg `StatefulSet governing headless Service` gate (hf-dtq).
- `gatewayApi.apiVersion` now defaults to `""` so capability negotiation
  actually runs, matching every other CRD-backed generator. The shipped
  literal `gateway.networking.k8s.io/v1` always won over the negotiated
  value, so on a cluster serving only `v1beta1` the capability gate passed
  (it negotiated `v1beta1`) and the HTTPRoute then rendered as `v1` — an
  apiVersion the cluster does not serve. Each route now negotiates its own
  Kind (HTTPRoute `v1` → `v1beta1`, GRPCRoute `v1` → `v1alpha2`, so GRPCRoute
  no longer inherits HTTPRoute's negotiated version); a non-empty
  `gatewayApi.apiVersion` or per-route `apiVersion` is still used verbatim.
  **Behavior change:** consumers on pre-1.0 Gateway API installs go from a
  hard apiVersion mismatch to a correct `v1beta1`/`v1alpha2` render; `v1`
  clusters and offline `helm template` output are unchanged.
  `scripts/lint-library.sh` gained a three-leg
  `Gateway API apiVersion negotiation` gate (helm-factory-5ar).
- Three cross-field combinations that silently rendered invalid or dangling
  objects now fail at template time with prescriptive messages:
  `service.type: ExternalName` is now supported properly — the Service renders
  `spec.externalName` from the new `service.externalName` value (required;
  rendering fails when empty) and omits ports/selector, where it previously
  rendered ports+selector with no `externalName` and was rejected by the API
  server; `certificate.enabled` with an empty `certificate.issuer` fails
  instead of rendering a null `issuerRef.name` cert-manager can never issue;
  and `ingress.enabled` without `service.enabled` fails instead of rendering
  an Ingress whose backends dangle against a Service that does not exist
  (same guard for Gateway API routes whose `backendRefs` default to the
  release Service — explicit `backendRefs` remain allowed without it).
  `service.externalName` is an additive values key with schema validation
  (`externalName` required when `type` is `ExternalName`).
  `scripts/lint-library.sh` gained a six-leg `Cross-field guards` gate
  (helm-factory-h8q).

### Fixed — annotation precedence (Ingress, Gateway API)

- Resource-specific annotations now override `commonAnnotations` on Ingress,
  HTTPRoute, and GRPCRoute (and `gatewayApi.annotations` now overrides
  `commonAnnotations` in the shared Gateway API map), matching every other
  object in the library (Service, Secret, ConfigMap, PVC, ...). These four
  sites used Sprig `merge`, which keeps existing keys, so `commonAnnotations`
  silently won any collision. **Behavior change:** only consumers setting the
  same annotation key in both `commonAnnotations` and the resource-specific
  block are affected — previously the common value rendered (the bug), now the
  specific value wins. `scripts/lint-library.sh` gained an
  `annotation precedence` gate asserting the specific value renders (hf-tyw).

### Fixed — CI/tooling

- `scripts/lint-library.sh`: per-document assertions no longer key on
  `metadata.name` (or field/indent position) alone — ambiguous since the
  pre-install hook ServiceAccount and hook Job legitimately share a name, so a
  name-keyed extractor silently read whichever same-named document rendered
  first. A shared `doc_of <kind> <name>` extractor now defines the kind+name
  key once, and every single-document extractor (hook-Job serviceAccountName,
  imagePullSecrets order, Ingress/Certificate TLS secretName convergence,
  ExternalName Service shape, StatefulSet serviceName) was swept onto it
  (helm-factory-4b1).
- `scripts/lint-library.sh`: `FIXTURES` and `KUBE_VERSIONS` are now
  env-overridable with space-separated subsets for a fast local feedback loop
  (e.g. `FIXTURES=minimal scripts/lint-library.sh` runs in seconds instead of
  minutes). A subset run covers only the per-fixture legs, skips the guardrail
  suite, and ends `==> PASS (subset)` so it can't masquerade as full-gate
  evidence; unknown fixtures or versions outside the vendored schema window
  fail fast with a prescriptive message. Bare invocation (and CI) is unchanged
  (hf-3p0).
- `scripts/lint-library.sh`: the negative-render check was a bare
  command-substitution assignment under `set -euo pipefail`, so a render failure
  there aborted the whole script at that line — silently skipping every later
  check (image-pin enforcement, schema enforcement, posture/hardening guardrails,
  hook ordering) with stderr discarded. Wrapped it in the script's guarded
  `if ! neg=$(...)` idiom and kept stderr, so a broken negative render now reports
  `FAIL`, the rest of the gate still runs, and the script exits 1 (hf-tgh).

### Fixed — docs

- Docs no longer teach the bare `--api-versions group/version` CLI form, which
  does NOT satisfy the capability gate (the gate checks
  `.Capabilities.APIVersions.Has` with the full `group/version/Kind` string, so
  the object is skipped silently with a clean exit 0). The published
  capability-catalog page (`site/docs/capability-catalog/index.md`) — which
  directly contradicted the README — now shows the full form and explains why
  the bare form fails; `CORE.md` debug commands/pitfalls and the
  `tests/render.sh` usage comment use the full form and carry the warning;
  the `g/v` shorthand in the discovery command tables became `g/v/Kind`. Only
  the `capabilities.apiVersions` values list accepts bare `group/version`
  (helm-factory-o5d).
- Docs accuracy pass (hf-8k3): the architecture spec's validation-gate and
  test-strategy sections now describe all four fixtures (`minimal`, `full`,
  `stateful`, `daemon`), their expected-count assertions, and the four
  committed goldens — the old text said `minimal`/`full` only, so a
  contributor could miss regenerating the `stateful`/`daemon` goldens. The
  README documents the previously rendered-but-undocumented values
  (`updateStrategy` / `statefulSet.updateStrategy` / `daemonSet.updateStrategy`
  with the automatic `rollingUpdate` drop on non-RollingUpdate types,
  `schedulerName`, `podRestartPolicy`, `hostAliases`), replaces the open-ended
  "Helm 4.0+" claim with the spec/PRD-scoped Helm 4.0–4.2 (verified v4.2.0),
  and adds a chart-version ↔ Kubernetes/Helm compatibility table for OCI
  consumers. `extraManifests` now honors the spec's "separator only when
  non-empty" contract in code: entries that render to nothing (a string whose
  template collapses to empty, or an empty map) are skipped instead of
  emitting a stray empty document, with a lint-gate leg asserting the skip
  and that non-empty entries still render.

## [2.0.0] - 2026-07-14

The v2 rewrite — the first published release of this chart. Everything below
ships together.

### Changed (breaking) — pod selectors

- Every pod selector now carries `app.kubernetes.io/component`, and
  `commonLabels` no longer appear in any selector. This fixes two defects that
  were live on the library's default values:
  - **The Service routed traffic to the wrong pods.** `platform.selectorLabels`
    emitted only `name` + `instance`, and the same pair was stamped on CronJob
    pods and pre/post-install hook-Job pods. With `commonLabels` unset (the
    default) the Service selector matched them, so a scheduled job or an
    install hook could receive live traffic. The PodDisruptionBudget counted
    them too, skewing node-drain math. CronJob pods are now
    `component: cronjob`, hook-Job pods `component: preinstall`/`postinstall`,
    and the main workload `component: app`.
  - **Changing a `commonLabel` orphaned the Service.** The Service selector
    included `commonLabels` (the workload selectors correctly did not), so
    editing one instantly de-selected every running pod and dropped the Service
    to zero endpoints until the rollout completed. Selectors are now built only
    from stable, chart-derived labels. `commonLabels` still apply to object and
    pod *metadata*, which is what they are for.

  **Upgrade impact:** `spec.selector.matchLabels` is immutable on Deployment,
  StatefulSet, and DaemonSet, so this cannot be applied by `helm upgrade` to a
  release created before this change — the API server rejects it. Any such
  release must be uninstalled and reinstalled. This is why the change lands in
  2.0.0, before the chart has ever been published: there are no existing
  installs to migrate.

  `scripts/lint-library.sh` gained a `selector stability` gate asserting that no
  user-settable label can reach a selector and that job pods stay distinguishable
  from workload pods.

### Removed (breaking)

- Removed the `serviceEndpoints` feature (`serviceEndpoints.enabled`, the
  `<fullname>-service-endpoints` ConfigMap, and `platform.serviceEndpoints.configmap`).
  It inferred "subcharts" by ranging over every map-valued key in `.Values`, a
  heuristic that was coherent under v1's nested-subchart model but is meaningless
  under v2's flattened `import-values: [defaults]` contract — every defaults block
  looks like a subchart. Enabling it emitted entries like
  `podSecurityContext-endpoint: podSecurityContext.default.svc.cluster.local:80`.
  It had zero test coverage. Repairing it would require a real subchart registry
  that v2 does not have, so it was removed rather than patched.
- Removed the umbrella helpers it depended on, all of which had zero call sites:
  `global.enabledSubcharts`, `global.allEndpointsDynamic`, `global.allEndpoints`,
  `global.subchartEndpoint`, `platform.service.endpoint`.
- Removed `platform.util.merge` (`_util.tpl`), a bitnami-common style overlay
  helper documented as public API for advanced consumers. It had no call sites
  anywhere in the library. The "gate outside `fromYaml`" invariant it was
  documented alongside still holds and is unchanged.
- Removed dead values keys that no template ever read: `global.storageClass`,
  `serviceAccount.labels`, `cronJob.sidecars`. (`persistence.storageClass` is
  unaffected and still works.)

Golden snapshots were byte-identical across all four fixtures after these
removals, confirming the code was genuinely unreachable.

### Fixed

- `podDisruptionBudget.maxUnavailable` is now selectable. It was previously
  unreachable: `minAvailable` defaulted to `1`, and the template's
  `if minAvailable / else if maxUnavailable` chain meant the `maxUnavailable`
  branch could never be taken. `minAvailable` and `maxUnavailable` now both
  default to empty, are declared in `values.yaml`, fail closed if both are set,
  and fall back to `minAvailable: 1` when neither is — preserving the previous
  default output.

- `updateStrategy.type: Recreate` (Deployment) and `OnDelete`
  (StatefulSet/DaemonSet) no longer emit a `rollingUpdate` block. The templates
  passed the whole values map through `toYaml`, and the library ships
  `rollingUpdate` defaults, so flipping only `.type` produced an object the API
  server rejects with "may not be specified when strategy type is ..." —
  `helm template` passed, `helm install` failed. The `rollingUpdate` sub-key is
  now dropped whenever `.type` is anything other than `RollingUpdate`; consumers
  no longer have to null it out themselves. `scripts/lint-library.sh` gained an
  `updateStrategy compatibility` gate covering all three workload kinds.

- User-supplied containers are now hardened by default. `sidecars.containers`,
  `initContainers.containers`, `cronJob.containers`/`cronJob.initContainers`, and
  hook-Job sidecars/initContainers were passed straight through with `toYaml` and
  received no `containerSecurityContext`, so they ran as root with
  `allowPrivilegeEscalation` unset while the library's own container was
  hardened. Pod Security Standards are evaluated *per container*, so a single
  bare sidecar sank the whole pod's `restricted` posture — the library's
  headline "PSS-restricted by default" claim was false for every container a
  consumer supplied. The library's `containerSecurityContext` is now merged into
  each of them as a **default**, with the container's own `securityContext` keys
  winning on conflict, so an intentional relaxation (say a sidecar that needs its
  own `runAsUser`) still works and the escape hatch
  (`containerSecurityContext.enabled: false`) is unchanged.

  **Upgrade impact:** a sidecar/initContainer that silently relied on running as
  root, or on a writable root filesystem, will now start with the restricted
  context and may fail. The fix is a per-container `securityContext` override in
  that container's spec — not disabling the library default. `scripts/lint-library.sh`
  gained a `container hardening posture` gate proving a bare container of each of
  the four kinds cannot render unhardened, that an explicit override survives the
  merge, and that `containerSecurityContext.enabled: false` still injects nothing.

- A pre-install hook Job no longer deadlocks a fresh `helm install`. The Job is a
  `pre-install` hook, but the script ConfigMap it mounts and the ServiceAccount it
  referenced were plain resources — and Helm creates a release's normal resources
  only *after* the pre-install hooks have run. On a fresh install the hook pod had
  no ConfigMap to mount, and the ServiceAccount admission controller rejected it
  for a missing ServiceAccount (which it does regardless of
  `automountServiceAccountToken`), so the install hung until the hook timed out and
  then failed. The script ConfigMap now joins the same hook phase one weight ahead
  of the Job, and when the library creates the ServiceAccount, the pre-install Job
  gets a hook-scoped copy of it (`<fullname>-preinstall`, carrying
  `serviceAccount.annotations` so IRSA/Workload Identity still work). Both are
  reaped by `hook-delete-policy: before-hook-creation,hook-succeeded`. The hook copy
  is deliberately *not* named after the release ServiceAccount: a same-named copy
  would make `before-hook-creation` delete the live ServiceAccount on every
  `helm upgrade`, invalidating the bound tokens of the pods still running.
  `post-install` hooks were never affected (they run after the normal resources) and
  their script ConfigMap stays a release-tracked normal resource.

  `helm template` executes no hooks, so no golden or render test could ever have
  caught this; `scripts/lint-library.sh` gained a `hook Job dependency ordering`
  gate asserting the hook annotations and the weight ordering directly, including
  when a consumer overrides `jobs.preInstall.hookWeight`.

### Added

- `NOTES.txt` now warns when a Kind is enabled in values but was **not rendered**
  because the target cluster does not serve its API. Capability gating skips
  `Certificate`, `PeerAuthentication`, `HTTPRoute`, `ServiceMonitor` and
  `PodMonitor` when their CRDs are absent, and until now it did so in complete
  silence: an operator could set `certificate.enabled=true`, see a successful
  install, and believe cert-manager was issuing a certificate that does not exist.
  The warning names each skipped Kind, the apiVersions that were tried, and the
  `capabilities.apiVersions` / `--api-versions` escape hatch. The gate conditions
  in `platform.app` and the warning now read one shared table
  (`platform.capabilities.gatedKinds`), so a future gated feature cannot be wired
  into the emitter and forgotten in the warning — `scripts/lint-library.sh`
  asserts the two stay in sync. Manifest output is unchanged.

- Declared three values keys that templates already read but `values.yaml` and
  the schema never documented, so consumers could not discover them:
  root-level `topologySpreadConstraints` (takes precedence over
  `highAvailability.topologySpreadConstraints`), `daemonSet.tolerations`, and
  `podDisruptionBudget.maxUnavailable`. All three are now typed in
  `values.schema.reference.json` (and therefore in the `values.schema.json`
  copied into consumers), so a malformed value is rejected at render time
  instead of being silently ignored. `podDisruptionBudget.minAvailable` is
  typed alongside its mutually exclusive sibling.

### Changed (breaking)

- Tightened the supported Kubernetes window to an n-2 policy — the latest
  supported minor plus two behind it, currently **1.34–1.36**. `Chart.yaml`
  now enforces `kubeVersion: ">=1.34.0-0 <1.37.0-0"`, so consumers on
  Kubernetes 1.33 or older can no longer install charts built on this library
  and must stay on a pre-tightening release or upgrade their clusters. The CI
  render/kubeconform matrix, golden snapshots (now rendered at 1.34), and docs
  were narrowed to match, and the dead `flowcontrol.apiserver.k8s.io/v1beta3`
  fallbacks (removed upstream in 1.32) were pruned from the capability registry.
- Rewrote `platform-library` as a pure, capability-gated common library (chart
  `platform`, v2): no self-rendering stub templates. Consumers depend on it with
  `import-values: [defaults]` and render everything through the single public
  entrypoint `{{ include "platform.render" . }}`.
- Every generator negotiates the best available `apiVersion` through the
  Kind→apiVersion registry in `_capabilities.tpl` and skips CRD-backed objects
  whose API is absent. Targets Kubernetes 1.34–1.36 and Helm 4.
- Security defaults pass the Pod Security Standards "restricted" profile out of
  the box: `podSecurityContext`/`containerSecurityContext` enabled by default
  (runAsNonRoot, seccompProfile RuntimeDefault, readOnlyRootFilesystem).
- Hook Jobs and CronJobs are hardened the same way: pod + container security
  contexts, merged image pull secrets, and `jobs.resources` on the fallback
  container.
- ServiceAccount defaults: `serviceAccount.create: true` with
  `automountServiceAccountToken: false` rendered on the ServiceAccount and every
  pod spec; `enableServiceLinks: false`.
- Image pinning is enforced: rendering fails when `image.tag` and `image.digest`
  are both empty, and the values schema rejects the floating tag `latest`.
- mTLS fails closed: `mtls.allowedPrincipals` is required when `mtls.enabled=true`;
  `mtls.allowAllPrincipals: true` is the explicit wildcard opt-in.
- Cluster-scoped Kinds in `extraObjects` are refused unless
  `allowClusterScopedExtras: true` (the failure names the offending Kind).

### Added

- `extraObjects` — render any Kubernetes Kind through one capability-gated
  generic renderer — and `extraManifests` — raw (optionally templated) manifests.
- `scripts/new-app-chart.sh` scaffold: generates a consumer chart (dependency +
  `import-values`, `templates/app.yaml`, `templates/NOTES.txt`, overrides-only
  `values.yaml`, `values.schema.json`) with validated inputs (semver charsets,
  repo scheme allowlist, control-character/newline rejection).
- Values contract: `platform-library/values.schema.reference.json` (enums for
  `workload.type`, `image.pullPolicy`, `service.type`, `mtls.policy`,
  `networkPolicy.policyTypes`; conditional Gateway API `parentRefs`; typed,
  pattern-constrained shapes for `podSecurityContext`, `containerSecurityContext`,
  `serviceAccount.name`, and `ingress.hostname`), copied into fixtures and
  scaffolded charts as `values.schema.json` so Helm enforces the coalesced
  post-import values. Declared as draft-07 (`$schema`), matching the dialect
  Helm's built-in `gojsonschema` validator actually implements (helm/helm#13069).
- `secret.existingSecret` to reference a pre-created Secret; mutually exclusive
  with inline `data`/`stringData`; suppresses the chart-managed Secret and its
  rollout checksum.
- Self-signed TLS Secret reuse across upgrades via `lookup` — no certificate
  churn on `helm upgrade`.
- Install-time `NOTES.txt` warnings (`platform.notes`): plain-HTTP ingress,
  default-deny NetworkPolicy, hostPath / privileged / cluster-scoped RBAC
  content in the extras escape hatches, and plaintext secret material under
  `secret.stringData`/`secret.data` or inline TLS material under
  `ingress.secrets`.
- CI (`.github/workflows/ci.yaml`): shellcheck, `helm lint`, metaschema check,
  and `scripts/lint-library.sh` — fixture render matrix across k8s 1.34–1.36
  with expected-object-count assertions, committed golden snapshots,
  kubeconform (native + datreeio CRD schemas) across the matrix, a negative
  render proving CRD-backed objects drop when their API is absent, image-pin
  enforcement, and posture guardrail checks.
- Vendored kubeconform schemas (`tests/schemas/`): the exact core Kubernetes
  (1.34–1.36) and CRD schemas the render matrix and fixtures exercise, with
  provenance recorded in `tests/schemas/README.md` and refreshed by
  `scripts/vendor-schemas.sh`. `scripts/lint-library.sh` validates against
  these local copies only — see Fixed below.
- Test fixtures (`tests/fixtures/`): `minimal`, `full`, `stateful`, `daemon`
  consumer charts with golden snapshots under `tests/golden/`.
- Release automation (`.github/workflows/release.yaml`): semver-tag-triggered;
  verifies the tag against `Chart.yaml`, reruns the full CI gate, then
  `helm package` + `helm push` to `oci://ghcr.io/<owner>/charts`. This CHANGELOG.
- `statefulSet.persistentVolumeClaimRetentionPolicy.whenDeleted` /
  `.whenScaled` — reclaim `volumeClaimTemplates` PVCs on scale-down or
  StatefulSet deletion; unset (default) preserves Kubernetes' implicit
  `Retain`/`Retain` behavior.
- `certificate.issuerKind` — defaults to `ClusterIssuer`; set to `Issuer` to
  reference a namespaced cert-manager Issuer in multi-tenant clusters.
- Root-level `minReadySeconds` (default `0`, omitted from the manifest) for
  Deployment, StatefulSet, and DaemonSet.
- `serviceMonitor`/`podMonitor` `scheme`, `tlsConfig` (mTLS-scraped targets),
  and `sampleLimit` (per-target series cap).
- Documentation site (`site/`): a Docusaurus site with Getting Started and
  Migration Guide ported from the README/`docs/migration/v1-to-v2.md`, plus
  stubs for Values Reference, Capability Catalog, Security Model, and Examples
  & Recipes pending their own follow-up work. Deployed to GitHub Pages by
  `.github/workflows/docs.yaml`, kept separate from `ci.yaml`/`release.yaml` so
  a docs build failure never blocks a chart release.

### Fixed

- Gateway API HTTPRoute path match type is `PathPrefix` (was the invalid
  `ImplementationSpecific`).
- `full` fixture `mtls.mode` → `mtls.policy` typo.
- `tests/render.sh` no longer swallows `helm dependency update` errors.
- `scripts/lint-library.sh` kubeconform legs validate each matrix version's own
  render (previously the canonical 1.31 render was re-validated against every
  version's schemas, under-validating version-specific negotiation).
- Hook script ConfigMaps fail with an actionable message when the referenced
  script file is missing (previously silently skipped).
- Recurring kubeconform CI flake: schema validation fetched schemas from the
  jsdelivr CDN mirror at test time, which intermittently returned hard HTTP
  403s that survived retries. Schemas are now vendored into `tests/schemas/`
  and `scripts/lint-library.sh` makes zero network requests; the retry/backoff
  loop that papered over the CDN flakiness has been removed.
- `certificate.enabled` and `tlsSelfSigned.enabled` fail closed when both are
  `true` (previously both silently targeted the same Secret `<fullname>-tls`
  and collided).
- Self-signed TLS Secret reuse now rotates near expiry instead of reusing the
  cert forever: generation stamps the annotation `platform/tls-not-after`
  (RFC3339, since Helm/sprig cannot parse x509 NotAfter from the looked-up
  cert), and reuse is skipped once within the new `tlsSelfSigned.renewBeforeDays`
  (default `30`) of that recorded expiry. A legacy Secret with no
  `platform/tls-not-after` annotation regenerates once, acquiring rotation
  metadata for subsequent upgrades.

### Removed

- The v1 root-level chart layout and the root `configuration.yaml` v1 artifact.
  Consumer configuration lives in the consumer chart's `values.yaml` (see the
  README Quick Start or `scripts/new-app-chart.sh`).

### Future work

- Sign pushed charts (cosign, keyless OIDC) and attach provenance to OCI
  releases.
