# Entity: capabilities registry (_capabilities.tpl)

`platform.capabilities.registry` (`platform-library/templates/_capabilities.tpl:76-176`) is the canonical Kind → ordered apiVersion preference table: every built-in Kubernetes Kind creatable via manifest, plus four CRD families (Gateway API, cert-manager, Istio, Prometheus Operator). First entry per Kind = preferred/newest GA, and also the offline fallback for OrDefault mode ([[strict-vs-ordefault-negotiation]]).

Structural hazard: it is a **YAML document inside a `define`**, parsed with `fromYaml` at every call site (`_capabilities.tpl:186,205,226,244`; the `gatedKinds` table is parsed the same way at `:276,291`). One malformed line breaks every render, with an error nowhere near the edit.

Companion helpers in the same file:
- `has` (`:27-45`) — cluster discovery OR force-assume list `.Values.capabilities.apiVersions`; entries match `group/version` or `group/version/Kind`. See [[template-vs-cluster-capabilities]].
- `apiVersionFor` (`:183-191`) strict / `apiVersionForOrDefault` (`:202-213`) fallback.
- `isStable` (`:222-233`) — hardcoded built-in group list; auto-selects the gate mode inside `platform.genericResource` for extraObjects (`_util.tpl:36-41`).
- `gatedKinds` (`:259`) / `gateOpen` (`:273`) / `skippedKinds` (`:288`) — added post-discovery: the shared Kind→values-block table that drives tier-1 CRD emitter gates (`gateOpen` folds `.enabled` + `apiVersionFor`) AND the NOTES.txt warning that names capability-skipped Kinds. A new gated Kind must be added here too, or it gates but never warns.
- `clusterScoped` set (`:304-306`, membership helper `isClusterScoped` `:312`) — drives namespace stamping and the cluster-scope extras gate (`_util.tpl:78-83`).

A Kind missing from the registry: `apiVersionFor` returns `""` → the object silently never renders. This is the #1 silent failure when adding Kinds.

Sources: raw/capabilities-design-header.md; file read in full 2026-07-10, HEAD 4fb9386; anchors re-verified 2026-07-19, HEAD 8d09841.
