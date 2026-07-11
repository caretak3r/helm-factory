# Concept: strict vs OrDefault apiVersion negotiation

The load-bearing distinction of the v2 rework. Two negotiation modes in [[capabilities-registry]]:

- **`apiVersionFor`** (strict, `_capabilities.tpl:183-191`): returns `""` when no listed API is served → the object is **skipped**. Contract: a rendered chart never conflicts on deploy. Used for CRD-backed / optional Kinds.
- **`apiVersionForOrDefault`** (`_capabilities.tpl:202-213`): falls back to the first registry preference → **never empty**. Contract: a bare `helm template` (minimal offline discovery set) never drops a core workload. Used for built-in Kinds.

The selector is `isStable` (`:222-233`): Kind's first-preference group ∈ hardcoded built-in group list → OrDefault, else strict. `platform.genericResource` applies exactly this rule automatically for extraObjects (`_util.tpl:52-56`).

No exceptions exist in the codebase. Both inversions are bugs:
- CRD on OrDefault → renders objects that fail admission on clusters without the CRD.
- Built-in on strict → silently vanishes from every offline render ([[template-vs-cluster-capabilities]]).

One sanctioned nuance: inside a CRD generator *body*, OrDefault is acceptable because the `_app.yaml` wrapper's strict gate already proved availability (`_mtls.yaml:11`, wrapper gate `_app.yaml:32`).

Proof command: `tests/render.sh full --set capabilities.apiVersions=null` — all 7 CRD-backed Kinds must be absent (run 2026-07-10: 0 matches; also a gate leg in [[lint-library-gate]]).

Sources: raw/capabilities-design-header.md; `_capabilities.tpl`, `_util.tpl`, `_app.yaml` read 2026-07-10, HEAD 4fb9386.
