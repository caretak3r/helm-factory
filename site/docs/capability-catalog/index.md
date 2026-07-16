---
title: Capability Catalog
description: The Kind → apiVersion registry that drives capability-gated rendering.
---

# Capability Catalog

:::info[Stub — pending generated table]
This page is a placeholder. The full catalog will be generated from the
`platform.capabilities.registry` YAML block embedded in
`platform-library/templates/_capabilities.tpl` and rendered as a sortable/searchable
table: Kind, preferred `apiVersion`, fallback chain, and cluster-scoped status
(cross-referenced with `platform.capabilities.clusterScoped`). This page is a
placeholder pending a future generation/write-up pass, best done once the in-flight
capability additions land so the first published table doesn't need an immediate
follow-up edit.
:::

## How capability gating works today

Every generator picks the best `apiVersion` the target cluster serves and skips
CRD-backed objects whose API is absent — charts never conflict on deploy. Built-in
Kinds always render (best version, GA fallback); CRD/optional Kinds skip when their
API is missing.

When rendering **without a cluster** (`helm template`, CI), Helm's API discovery is
minimal, so CRD-backed objects would be skipped by default. Force-assume the groups
you use:

```yaml
capabilities:
  apiVersions:
    - gateway.networking.k8s.io/v1
    - cert-manager.io/v1
    - monitoring.coreos.com/v1
    - security.istio.io/v1beta1
```

The CLI flag works too, but **only in the full `group/version/Kind` form** —
`helm template --api-versions cert-manager.io/v1/Certificate` (and
`--kube-version <x.y>` to set `.Capabilities.KubeVersion`). A bare
`--api-versions group/version` flag does **not** satisfy the gate: the library
checks `.Capabilities.APIVersions.Has` with the full `group/version/Kind`
string, and Helm's `Has` is an exact-string membership test — a set containing
only `cert-manager.io/v1` never answers `true` for
`cert-manager.io/v1/Certificate`. The result is the worst failure mode: a
clean exit 0 with the object silently missing. Only the
`capabilities.apiVersions` values list above accepts the bare `group/version`
form, because the library itself also matches each entry against the queried
Kind's `group/version`.

Until the generated table lands, the authoritative source is
[`platform-library/templates/_capabilities.tpl`](https://github.com/caretak3r/helm-factory/blob/main/platform-library/templates/_capabilities.tpl)
and the architecture spec at
[`docs/specs/platform-library-v2-architecture.md`](https://github.com/caretak3r/helm-factory/blob/main/docs/specs/platform-library-v2-architecture.md).
