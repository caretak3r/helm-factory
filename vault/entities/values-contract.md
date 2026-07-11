# Entity: values contract (values.yaml + values.schema.reference.json)

The consumer-facing surface, merge bar #3 (stability: rename/move = breaking = major bump).

**Defaults**: all library defaults live under `exports.defaults` in `platform-library/values.yaml` (629 lines; file opens `exports:\n  defaults:`). Keys outside that wrapper are never exported to consumers. Mechanics: [[exports-defaults-import-mechanics]].

**Schema**: `platform-library/values.schema.reference.json` — draft 2020-12, root `additionalProperties: true`. Verified constraints (parsed 2026-07-10): `workload.type` enum `Deployment|StatefulSet|DaemonSet`; `image.pullPolicy` enum `Always|IfNotPresent|Never|""`; `service.type` enum `ClusterIP|NodePort|LoadBalancer|ExternalName`; `mtls.policy` enum `STRICT|PERMISSIVE|DISABLE|UNSET`; `image.tag` type string|number with `not: {const: latest}`.

Deliberately NOT named `values.schema.json` at the library root: the library's own values are wrapped under `exports.defaults` and would fail the post-import-shaped schema. It is copied into consumers as `values.schema.json` — by the scaffold at generation time and by `tests/render.sh:13` on every fixture render — so Helm validates coalesced post-import values.

Security defaults within the contract (never weakened, merge bar #2): raw/values-security-defaults.md and [[fail-closed-guardrail-pattern]]. Tier-2 key is named `extraObjects` (not `resources`) to avoid colliding with container `resources:`.

Sources: raw/values-security-defaults.md; schema parsed with python-json; `values.yaml` head + `tests/render.sh` read 2026-07-10, HEAD 4fb9386.
