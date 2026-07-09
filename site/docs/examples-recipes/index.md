---
title: Examples & Recipes
description: Worked examples per workload type and common integration patterns.
---

# Examples & Recipes

:::info Stub — worked examples pending
This page is a placeholder for a set of worked examples: one per workload type
(Deployment / StatefulSet / DaemonSet), one for Gateway API, one for the mTLS +
NetworkPolicy combination, and one for `extraObjects` (RBAC + PriorityClass).
:::

## A quick taste: `extraObjects` for RBAC + PriorityClass

```yaml
allowClusterScopedExtras: true   # PriorityClass below is cluster-scoped
extraObjects:
  Role:
    - name: app-reader
      rules:
        - apiGroups: [""]
          resources: [configmaps, secrets]
          verbs: [get, list, watch]
  PriorityClass:
    - name: app-high            # cluster-scoped Kinds skip the namespace automatically
      value: 1000000
      globalDefault: false
```

See [Getting Started](/docs/getting-started/) for the base scaffold this builds on.
