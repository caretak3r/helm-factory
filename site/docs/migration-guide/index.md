---
title: Migration Guide
description: Upgrading a consumer chart from platform-library v1 to v2.
---

:::note[Source]
Ported from [`docs/migration/v1-to-v2.md`](https://github.com/caretak3r/helm-factory/blob/main/docs/migration/v1-to-v2.md)
in the repository. The Helm 3 → Helm 4 / server-side-apply section referenced in the
productionization plan (**DOC-7**) will be added here once that work lands.
:::

# Migration Guide — `platform` Library v1 → v2

This is a task-oriented upgrade for a **consumer** chart moving from the v1
`platform-library` to the v2 `platform` library. v2 is a **pure library chart**
with a single render entrypoint and capability-negotiated API versions.

## What broke (and why)

1. **The library no longer self-renders.** In v1 the chart shipped ~25
   non-underscore wrapper templates (`deployment.yaml`, `service.yaml`,
   `app.yaml`, …) that emitted objects on their own. These were **deleted**. The
   chart is now purely `type: library`, so `helm install platform-library …`
   correctly **fails** — a library cannot be installed. All templates are now
   `_`-prefixed implementations.

2. **Consumers must render explicitly.** Instead of relying on the library to
   self-render, your chart calls the single public entrypoint from its own
   `templates/app.yaml`:

   ```yaml
   {{ include "platform.render" . }}
   ```

   `platform.render` composes the opinionated tier-1 objects, the tier-2
   `extraObjects`, and the raw `extraManifests`.

3. **The chart was renamed and re-versioned.** The dependency name is now
   `platform` (directory `platform-library/`), `version: 2.0.0`,
   `kubeVersion: ">=1.31.0-0 <1.37.0-0"`.

4. **API versions are now negotiated, not hard-coded.** HPA, Ingress, PDB,
   CronJob, Certificate, mTLS, Gateway API, ServiceMonitor and PodMonitor now
   pick the best `apiVersion` the target cluster serves. CRD-backed objects
   **skip themselves** when their API is absent instead of rendering a manifest
   that would fail admission.

5. **Correctness fixes.** v1 did not lint: committed git-conflict markers and a
   missing `{{- end }}` in `_helpers.tpl` were fixed, and the malformed
   `cronJob.initContainers`/`sidecars` default (a `{enabled, containers}` map) is
   now a plain list (`[]`).

6. **New values keys:** `capabilities.apiVersions`, `extraObjects`,
   `extraManifests`.

## Fast path — scaffold a fresh consumer chart

If you'd rather start clean than hand-edit, generate a pre-wired consumer chart
and move your overrides into it:

```bash
scripts/new-app-chart.sh my-service
# options: --dir <path> --repo <url, default file://../platform-library>
#          --version <range, default ">=2.0.0-0"> --app-version <v>
```

This emits a `Chart.yaml` with the `platform` dependency (including
`import-values: [defaults]`), `templates/app.yaml` = `{{ include "platform.render" . }}`,
an overrides-only `values.yaml`, a `.helmignore`, and a `values.schema.json`
(copied from the library's reference schema) so your root values are validated on
every `helm` invocation. The manual steps below describe the same result if you
prefer to upgrade an existing chart in place.

## Step 1 — Update `Chart.yaml`

```yaml
apiVersion: v2
name: my-service
version: 1.0.0
dependencies:
  - name: platform
    version: ">=2.0.0-0"
    # OCI registry in normal use:
    repository: oci://<registry>/charts
    # ...or a local path for development:
    # repository: file://../platform-library
    import-values: [defaults]   # MANDATORY — see the footgun below
```

## Step 2 — Add the render entrypoint

Create (or replace) `templates/app.yaml` with exactly one line:

```yaml
{{ include "platform.render" . }}
```

Delete any per-object wrapper templates you were carrying to work around v1 —
they are unnecessary and will produce duplicate output.

## Step 3 — Keep your tier-1 overrides as-is

The opinionated tier-1 blocks are unchanged in shape (`service`, `ingress`,
`autoscaling`, `certificate`, `mtls`, `gatewayApi`, `serviceMonitor`, …). Your
existing overrides continue to apply. No hard-coded `apiVersion` is needed for
these anymore — negotiation handles it.

## The `import-values: [defaults]` footgun (read this)

This is the **#1 integration failure**. The library ships all defaults under
`exports.defaults`. Without `import-values: [defaults]` on the dependency, those
defaults **never reach your root scope** and every value renders empty — you get
either an empty/near-empty render or `nil` errors, with no obvious cause.

```yaml
dependencies:
  - name: platform
    version: ">=2.0.0-0"
    repository: oci://<registry>/charts
    import-values: [defaults]   # <-- without this, all values are empty
```

## Step 4 — Move custom resources into `extraObjects`

Anything you previously dropped as raw YAML in your own chart (RBAC, quotas,
priority classes, etc.) should move into the tier-2 `extraObjects` map so it gets
standard labels, namespace stamping, and API negotiation for free.

`extraObjects` is a **map of `Kind -> list of specs`**. Reserved keys per spec are
`name`, `namespace`, `labels`, `annotations`, `apiVersion`, `kind`,
`clusterScoped`; every other top-level key passes through verbatim.

```yaml
extraObjects:
  Role:
    - name: app-reader
      rules:
        - apiGroups: [""]
          resources: ["configmaps", "secrets"]
          verbs: ["get", "list", "watch"]
  RoleBinding:
    - name: app-reader-binding
      roleRef:
        apiGroup: rbac.authorization.k8s.io
        kind: Role
        name: app-reader
      subjects:
        - kind: ServiceAccount
          name: my-service
  PriorityClass:                 # cluster-scoped: no namespace is stamped
    - name: my-high
      value: 1000000
      globalDefault: false
      description: "High priority"
  ResourceQuota:
    - name: my-quota
      spec:
        hard:
          pods: "10"
```

- **Built-in Kinds** (RBAC, quotas, priority classes, …) always render at their
  best available version.
- **CRD Kinds** placed here skip when their API is absent.
- `metadata.name` is required; a missing name fails with
  `extraObjects.<Kind>[].name is required`.
- Set `clusterScoped: true` on a spec to force-suppress the namespace for a Kind
  the library doesn't already know is cluster-scoped.

## Step 5 — Use `extraManifests` only for the truly bespoke

For anything the library does not model and that you do not want normalized, use
the raw escape hatch. It is a **list**; you supply the full manifest. Strings are
run through `tpl` (so they can contain template expressions); maps are emitted
verbatim. No labels, namespace, or negotiation are added.

```yaml
extraManifests:
  - apiVersion: v1
    kind: ConfigMap
    metadata:
      name: raw-config
    data:
      raw: "true"
  # A template string is also allowed:
  - |
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: {{ .Release.Name }}-templated
    data:
      ns: {{ .Release.Namespace }}
```

## Step 6 — Rendering without a cluster (CI / `helm template`)

Under bare `helm template` (no cluster) Helm's API discovery is minimal and
reports **no CRDs**. Built-in objects still render (they use negotiate-or-default),
but CRD-backed objects (Certificate, mTLS, Gateway routes, ServiceMonitor,
PodMonitor, and any CRD in `extraObjects`) will **skip** unless you force-assume
their groups:

```yaml
capabilities:
  apiVersions:
    - gateway.networking.k8s.io/v1
    - cert-manager.io/v1
    - security.istio.io/v1beta1
    - monitoring.coreos.com/v1
```

Entries may be `group/version` or `group/version/Kind`. On a real cluster that
serves these APIs you don't need the override — it's for local/CI rendering.

Render locally with the test harness or directly:

```bash
helm dependency update .
helm template my-service . --kube-version 1.34
```

## Upgrade-churn & immutability warnings

- **Objects appear/disappear with CRDs.** Because CRD-backed objects skip when
  their API is absent, installing or removing a CRD (e.g. cert-manager) changes
  what renders. On the next `helm upgrade` those objects will be **created or
  pruned** accordingly. This is expected — plan the CRD install/removal around
  your release windows.
- **beta → GA can force a replace.** If negotiation moves an existing object from
  a beta to a GA `apiVersion` (e.g. `policy/v1beta1` → `policy/v1`), Helm/the API
  server may need to **replace** rather than update the resource. Expect a brief
  churn for those objects on the first v2 upgrade.
- **Immutable fields.** Do not override immutable fields on live objects — most
  importantly `spec.selector`. As in v1, avoid putting mutable labels into a
  Service selector: selectors are immutable, and changing them breaks matching to
  existing Pods (delete/recreate is then required).

## Quick checklist

- [ ] Dependency renamed to `platform`, `version: ">=2.0.0-0"`.
- [ ] `import-values: [defaults]` present on the dependency.
- [ ] `templates/app.yaml` = `{{ include "platform.render" . }}`.
- [ ] Removed old per-object wrapper templates.
- [ ] Custom resources moved to `extraObjects` (or `extraManifests` for the bespoke).
- [ ] `capabilities.apiVersions` set for CI/local renders that need CRD objects.
- [ ] Verified `helm dependency update && helm template` renders as expected.
