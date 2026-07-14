# Raw: _capabilities.tpl — design header comment

Provenance: verbatim copy of `platform-library/templates/_capabilities.tpl` lines 1-20, taken 2026-07-10 at HEAD 4fb9386 (branch handover/2026-07-10). Not edited.

```text
{{/*
=============================================================================
platform.capabilities — API capability negotiation
=============================================================================
These helpers let every generator pick the best apiVersion that the target
cluster actually serves and silently skip an object when none is available,
so a rendered chart never conflicts on deploy.

Rendering without a cluster (helm template / lint) reports no CRDs and only a
subset of built-in groups. Consumers/CI can force-assume APIs by listing them
under `.Values.capabilities.apiVersions`, e.g:

  capabilities:
    apiVersions:
      - gateway.networking.k8s.io/v1
      - cert-manager.io/v1/Certificate

Entries may be "group/version" or "group/version/Kind"; both forms match.
=============================================================================
*/}}
```
