# Raw: CORE.md — Known Issues (Tracked)

Provenance: verbatim copy of `CORE.md` lines 95-106, taken 2026-07-10 at HEAD 4fb9386 (branch handover/2026-07-10). Not edited.

```markdown
## Known Issues (Tracked)
Lower-priority issues, verified still present at these locations:

| Issue | File:Line | Impact |
|-------|-----------|--------|
| Probe condition redundancy | `_helpers.tpl:244-251` | `omit` returns a dict (always truthy); `and enabled (omit ...)` reduces to `enabled` — works but misleading |
| Service selector includes mutable labels | `_service.yaml:51-55` | `commonLabels` are added to the Service selector; selectors are immutable, so changing `commonLabels` breaks the Service |
| Unknown workload type silently falls back to Deployment | `_helpers.tpl:440-448` | Mitigated: `values.schema.json` (fixtures/scaffold) rejects anything outside the `Deployment`/`StatefulSet`/`DaemonSet` enum at render time; only consumers without the schema hit the silent fallback |
| Duplicate imagePullSecrets possible | `_helpers.tpl:194-206` | The same secret listed in both `global.imagePullSecrets` and `image.pullSecrets` appears twice |

Fixed since the v1 review (no longer issues): DaemonSet+HPA (guarded in `_hpa.yaml:2`), silent hook-script skip (fails with a message in `_configmap-script.yaml:41`). Full history: [`CHANGELOG.md`](CHANGELOG.md) and `fable5-review.md`.

```
