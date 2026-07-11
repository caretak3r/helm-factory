# Concept: fail-closed guardrail pattern

The v2 hardening posture (merge bar #2, never weakened) is enforced by render-time `fail` calls, each with three coupled parts: **prescriptive message** (names the offending values path AND states the fix) + **negative test** in [[lint-library-gate]] that asserts both the failure and the message substring + **documented opt-out** where legitimate.

Verified guardrail table (all anchors + gate legs confirmed 2026-07-10, HEAD 4fb9386):

| Guardrail | Source | Gate leg |
|---|---|---|
| Unpinned image (no tag, no digest) | `_helpers.tpl:68` | `lint-library.sh:178-185` |
| Hook Job resolves to no pin (digest inherited only when repos match) | `_helpers.tpl:640` | `:195-201` |
| mTLS enabled + empty `allowedPrincipals` (opt-out: `allowAllPrincipals: true`) | `_mtls.yaml:8` | `:223-237` |
| Cluster-scoped extraObjects (opt-out: `allowClusterScopedExtras: true`) | `_util.tpl:99` | `:240-246` |
| `existingSecret` + inline `data`/`stringData` | `_secret.yaml:3` | `:249-255` |
| Missing hook `scriptFile` | `_configmap-script.yaml:41` | — |
| `tag: latest`, lowercase workload type | values.schema (helm-side) | `:203-218` |

Consequences: changing a `fail` message breaks the gate by design — message and grep move together. Hazards that would break legitimate use warn instead, via `platform.notes` (`_notes.tpl`) into install-time NOTES.txt, which never appears in `helm template` output (goldens unaffected).

The defaults side of the posture (PSS-restricted contexts, `automountServiceAccountToken: false`, `enableServiceLinks: false`) lives in [[values-contract]] / raw/values-security-defaults.md. The rule: relaxation is a per-field consumer override, never a library-default change.

Sources: raw/values-security-defaults.md, raw/lint-library-header.md; all `fail` sites read 2026-07-10.
