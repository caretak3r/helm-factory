---
title: Getting Started
description: Scaffold a chart, add the platform dependency, and render your first release.
---

# Getting Started

`platform-library` (chart name `platform`, `type: library`, **v2**) is a **pure** Helm
library chart: it ships no installable templates of its own. Product charts depend on
it and render everything through a single entrypoint, `platform.render`. Service teams
never write manifests — they set values and the library generates the resources.

Targets **Kubernetes 1.31–1.36** and **Helm 4.0+**. Migrating from v1? See the
[Migration Guide](/docs/migration-guide/).

## Fastest: scaffold a new chart

```bash
scripts/new-app-chart.sh my-service --repo oci://ghcr.io/caretak3r/charts --version "^2.0.0"
helm dependency update my-service
helm template my-service my-service
```

This generates a chart already wired to the library (dependency + `import-values`, an
entrypoint template, an overrides-only `values.yaml`, and a `values.schema.json`). Or do
it by hand:

### 1. Add the dependency

```yaml
# Chart.yaml
apiVersion: v2
name: my-service
version: 1.0.0
dependencies:
  - name: platform                     # the chart name, not "platform-library"
    version: "^2.0.0"
    repository: "oci://ghcr.io/caretak3r/charts"
    import-values:                     # REQUIRED — without this the library
      - defaults                       # defaults never reach your root values
```

### 2. Add the entrypoint template

The library is pure; your chart renders it. Create exactly one template:

```yaml
# templates/app.yaml
{{ include "platform.render" . }}
```

### 3. Configure your service

```yaml
# values.yaml  (values land at the root because of import-values: [defaults])
image:
  repository: gcr.io/my-project/my-service
  tag: v1.0.0

service:
  enabled: true
  ports:
    - name: http
      port: 80
      targetPort: http

ingress:
  enabled: true
  hostname: my-service.example.com

# When rendering in CI (no cluster), force-assume CRD groups you use so their
# objects are not skipped:
# capabilities:
#   apiVersions: [cert-manager.io/v1, monitoring.coreos.com/v1]
```

### 4. Render and deploy

```bash
helm dependency update .
helm template my-service .
helm install my-service .
```

## Installation

The chart is a **library chart** (`type: library`). It cannot be installed directly.
Add it as a dependency to your service chart as shown above.

The library uses the `exports.defaults` pattern — all values are merged into the
parent chart's root scope automatically.

## Where to go next

- [Values Reference](/docs/values-reference/) — every configurable key.
- [Capability Catalog](/docs/capability-catalog/) — which Kinds render and how apiVersion
  negotiation works.
- [Security Model](/docs/security-model/) — trust boundaries and secrets handling.
- [Examples & Recipes](/docs/examples-recipes/) — worked examples per workload type.
