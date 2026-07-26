---
title: How It Works
description: The user journey from sourcing the library to rendered manifests, and the render pipeline that produces them.
---

# How It Works

`platform` is a **pure library chart**. It ships no installable templates — a
consumer chart declares it as a dependency and renders *everything* through one
entrypoint, `{{ include "platform.render" . }}`. This page traces the whole path
twice: first the **user journey** (what a service team does), then the **render
pipeline** (what the library does when Helm calls it).

## The user journey

A service team never writes a manifest. They describe intent in ~30 lines of
values, and the library generates hardened, capability-negotiated objects.

```mermaid
flowchart TD
    A["Service team writes ~30 lines<br/>of values.yaml — intent only"] --> B["Chart.yaml declares the platform<br/>dependency from GHCR, with<br/>import-values defaults"]
    B --> C["helm dependency update<br/>pulls the library from GHCR"]
    C --> D["import-values defaults merges<br/>exports.defaults into the<br/>consumer ROOT values scope"]
    D --> E["templates/app.yaml renders the<br/>platform.render entrypoint"]
    E --> F["helm template / helm install<br/>invokes the render pipeline"]
    F --> G["Hardened, PSS-restricted,<br/>capability-negotiated manifests"]
    G --> H["Objects the cluster actually serves —<br/>absent CRDs skip cleanly, warned in NOTES"]

    style A fill:#e8f0fe,stroke:#1a73e8,color:#000
    style G fill:#e6f4ea,stroke:#188038,color:#000
    style H fill:#e6f4ea,stroke:#188038,color:#000
```

The load-bearing step is `import-values: [defaults]`. Without it, the library's
defaults never reach your root values and nothing renders correctly — see
[Getting Started](/docs/getting-started/) for the exact dependency block.

## The render pipeline

`platform.render` (in `_util.tpl`) composes three layers in a fixed order. Tier-1
is the opinionated primary app; tier-2 and the raw layer are escape hatches for
the long tail.

```mermaid
flowchart TD
    R["platform.render"] --> A["platform.app<br/>tier-1: opinionated primary app"]
    R --> EO["platform.extraObjects<br/>tier-2: generic declarative long tail"]
    R --> EM["platform.extraManifests<br/>raw escape hatch (verbatim / tpl)"]

    A --> DISP["_app.yaml dispatches per Kind<br/>in a fixed order (21 slots)"]
    DISP --> GATE{"Enabled in values<br/>AND capability available?"}
    GATE -->|no| SKIP["Emit nothing<br/>(CRD-backed Kinds warned in NOTES)"]
    GATE -->|yes| GEN["Generator template _*.yaml<br/>one define per object"]
    GEN --> HELP["Shared helpers:<br/>naming, labels, image resolution,<br/>hardenContainers (_helpers.tpl / _util.tpl)"]
    HELP --> EMIT["platform.emit<br/>prefixes '---' only when non-empty"]
    EMIT --> OBJ["Rendered object"]

    EO --> GR["platform.genericResource<br/>(one renderer, all Kinds)"]
    EM --> TPL["tpl for string entries,<br/>toYaml for map entries"]
    GR --> OBJ
    TPL --> OBJ

    style R fill:#e8f0fe,stroke:#1a73e8,color:#000
    style GATE fill:#fef7e0,stroke:#f9ab00,color:#000
    style SKIP fill:#fce8e6,stroke:#d93025,color:#000
    style OBJ fill:#e6f4ea,stroke:#188038,color:#000
```

### Tier-1 dispatch order

`platform.app` walks enabled features in a fixed order and includes the matching
generator, each wrapped in `platform.emit`. Order matters — TLS secrets exist
before the workload that mounts them, and hook Jobs land last.

| # | Object(s) | Gate |
|---|---|---|
| 1 | ConfigMap | `configMap.enabled` |
| 2 | Pre/post-install script ConfigMaps | `jobs.{preInstall,postInstall}.enabled` + a `script`/`scriptFile` |
| 3 | Secret | `secret.enabled` |
| 4 | Certificate (cert-manager) | `certificate.enabled` **and** `apiVersionFor "Certificate"` |
| 5 | TLS secrets (provided certs) | `ingress.enabled` + `ingress.secrets` |
| 6 | Self-signed TLS | `tlsSelfSigned.enabled` |
| 7 | mTLS (Istio PeerAuthentication/AuthorizationPolicy) | `mtls.enabled` **and** `apiVersionFor "PeerAuthentication"` |
| 8 | PersistentVolumeClaim | `persistence.enabled` |
| 9 | Workload (Deployment/StatefulSet/DaemonSet) | always |
| 10 | HorizontalPodAutoscaler | `autoscaling.enabled` |
| 11 | Service | `service.enabled` |
| 12 | Ingress | `ingress.enabled` |
| 13 | Gateway API (HTTPRoute/GRPCRoute) | `gatewayApi.enabled` **and** `apiVersionFor "HTTPRoute"` |
| 14 | NetworkPolicy | `networkPolicy.enabled` |
| 15 | PodDisruptionBudget | `podDisruptionBudget.enabled` |
| 16 | ServiceAccount | `serviceAccount.create` or `serviceAccount.name` |
| 17 | ServiceMonitor | `serviceMonitor.enabled` **and** `apiVersionFor "ServiceMonitor"` |
| 18 | PodMonitor | `podMonitor.enabled` **and** `apiVersionFor "PodMonitor"` |
| 19 | CronJob | `cronJob.enabled` |
| 20 | Pre-install hook Job | `jobs.preInstall.enabled` |
| 21 | Post-install hook Job | `jobs.postInstall.enabled` |

The two-part gate on CRD-backed objects (Certificate, mTLS, Gateway routes,
ServiceMonitor, PodMonitor) — the feature flag **and** a successful capability
negotiation — is what lets those objects skip cleanly when the CRD is absent.

## Capability negotiation

For each Kind, the library decides *which* `apiVersion` to emit — or whether to
emit at all — by class. Built-ins must always render (a plain `helm template`
with no cluster still needs a Deployment); CRDs must never render when their API
is absent (a deploy must not conflict).

```mermaid
flowchart TD
    K["Kind to render"] --> S{"isStable?<br/>(built-in K8s group)"}
    S -->|yes: built-in| OD["apiVersionForOrDefault<br/>negotiate, else fall back to<br/>preferred GA registry entry"]
    OD --> ALWAYS["Always renders<br/>(never silently dropped)"]
    S -->|no: CRD / optional| STRICT["apiVersionFor (strict)"]
    STRICT --> AVAIL{"Served by cluster<br/>OR force-assumed via<br/>capabilities.apiVersions?"}
    AVAIL -->|yes| RENDER["Render at negotiated version"]
    AVAIL -->|no| DROP["Emit nothing<br/>+ NOTES warning (skippedKinds)"]

    style K fill:#e8f0fe,stroke:#1a73e8,color:#000
    style S fill:#fef7e0,stroke:#f9ab00,color:#000
    style AVAIL fill:#fef7e0,stroke:#f9ab00,color:#000
    style ALWAYS fill:#e6f4ea,stroke:#188038,color:#000
    style RENDER fill:#e6f4ea,stroke:#188038,color:#000
    style DROP fill:#fce8e6,stroke:#d93025,color:#000
```

Under bare `helm template` (no cluster), Helm's API discovery is minimal — it
reports neither the full built-in group set nor any CRD. That is exactly why
built-ins use `OrDefault` (fall back to preferred GA) and CRDs use strict
`apiVersionFor` (skip when absent). To render CRD-backed objects offline, in CI,
**force-assume** their groups via `capabilities.apiVersions` — full detail and
the exact-string `--api-versions` gotcha live in the
[Capability Catalog](/docs/capability-catalog/).

## Where to go next

- [Capability Catalog](/docs/capability-catalog/) — the full Kind → apiVersion registry.
- [Conventions & Tricks](/docs/conventions-and-tricks/) — the Helm idioms, primitives, and hacks the library leans on.
- [Values Reference](/docs/values-reference/) — every configurable key.
- [Security Model](/docs/security-model/) — hardening defaults and trust boundaries.
