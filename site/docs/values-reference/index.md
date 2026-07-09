---
title: Values Reference
description: Every configurable key in values.yaml, generated from source.
---

# Values Reference

:::info[Stub — pending generation pipeline]
This page is a placeholder. The full reference will be generated from
`platform-library/values.yaml` (inline `#` section comments) and
`platform-library/values.schema.reference.json` (types, `enum`s, descriptions) by a
values-doc generation pipeline (tracked as **DOC-2** in the productionization plan), not
hand-written here — a hand-maintained reference drifts from source the moment either
file changes.

**Known complication for the generator:** this library's defaults live under the
`exports.defaults:` key rather than at the file root, so the generator needs either a
pre-processing unwrap step or configurable root-key support.
:::

Until the generator lands, the authoritative source for configurable keys is:

- [`platform-library/values.yaml`](https://github.com/caretak3r/helm-factory/blob/main/platform-library/values.yaml) —
  inline comments document every section.
- [`platform-library/values.schema.reference.json`](https://github.com/caretak3r/helm-factory/blob/main/platform-library/values.schema.reference.json) —
  the JSON Schema used to validate consumer values.
- The [Getting Started](/docs/getting-started/) guide, which walks through the
  most commonly configured keys (image, service, ingress).
