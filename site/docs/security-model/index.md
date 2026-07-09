---
title: Security Model
description: Trust boundaries, secrets handling, and the secure-by-default posture.
---

# Security Model

:::info[Stub — consolidation pending]
This page is a placeholder. A full write-up consolidating the PSS-restricted target
and rationale, the escape-hatch trust model, the secrets-in-values warning, the mTLS
fail-closed design, and the SSA/`extraObjects`-conflict behavior into one authoritative
page is tracked as **DOC-6** in the productionization plan. Until then, the source
material is linked below.
:::

## Trust model — values are code

`extraObjects`, `extraManifests`, `sidecars`, `initContainers`, and `extraVolumes` are
verbatim escape hatches: whoever writes those values authors arbitrary Kubernetes
objects (and, for `extraManifests` strings, arbitrary template code executed with the
full chart context). Review values changes like code changes.

Two guardrails apply today:

- Cluster-scoped Kinds in `extraObjects` **fail rendering** unless you set
  `allowClusterScopedExtras: true` (the failure names the offending Kind).
- Install-time `WARNING:` notes are printed (via `NOTES.txt`) when extras contain
  `hostPath` volumes, `privileged: true` containers, or cluster-scoped RBAC.

## Secrets in values are plaintext

Anything under `secret.data`/`secret.stringData` (and raw cert/key material under
`ingress.secrets`) ends up in your values files (git) and in the Helm release manifest
(a Secret in the release namespace). For production, create the Secret out-of-band —
[External Secrets Operator](https://external-secrets.io/),
[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets), or SOPS — and point
the chart at it with `secret.existingSecret`. The chart then renders **no** Secret.

## mTLS is fail-closed

When `mtls.enabled: true`, `allowedPrincipals` must list the SPIFFE principals
allowed to call the workload — rendering fails otherwise. There is no
implicit-allow default.

## Further reading

- [`README.md`](https://github.com/caretak3r/helm-factory/blob/main/README.md) —
  secrets warning, mTLS section, and the "Extending: any Kubernetes object" trust
  model section.
- [`platform-library/values.yaml`](https://github.com/caretak3r/helm-factory/blob/main/platform-library/values.yaml) —
  PSS-restricted defaults and inline rationale comments.
