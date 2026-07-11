# Entity: capabilities registry (_capabilities.tpl)

`platform.capabilities.registry` (`platform-library/templates/_capabilities.tpl:68-158`) is the canonical Kind → ordered apiVersion preference table: every built-in Kubernetes Kind creatable via manifest, plus four CRD families (Gateway API, cert-manager, Istio, Prometheus Operator). First entry per Kind = preferred/newest GA, and also the offline fallback for OrDefault mode ([[strict-vs-ordefault-negotiation]]).

Structural hazard: it is a **YAML document inside a `define`**, parsed with `fromYaml` at every call site (`_capabilities.tpl:168`). One malformed line breaks every render, with an error nowhere near the edit.

Companion helpers in the same file:
- `has` (`:27-42`) — cluster discovery OR force-assume list `.Values.capabilities.apiVersions`; entries match `group/version` or `group/version/Kind`. See [[template-vs-cluster-capabilities]].
- `apiVersionFor` (`:165-173`) strict / `apiVersionForOrDefault` (`:184-195`) fallback.
- `isStable` (`:204-215`) — hardcoded built-in group list; auto-selects the gate mode for extraObjects (`_util.tpl:52-56`).
- `clusterScoped` set (`:221-223`) — drives namespace stamping and the cluster-scope extras gate (`_util.tpl:98-99`).

A Kind missing from the registry: `apiVersionFor` returns `""` → the object silently never renders. This is the #1 silent failure when adding Kinds.

Sources: raw/capabilities-design-header.md; file read in full 2026-07-10, HEAD 4fb9386.
