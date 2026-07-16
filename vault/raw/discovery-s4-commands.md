# Raw: Discovery report §4 — commands that prove work

Provenance: verbatim copy of `.claude/operating/discovery.md` lines 124-143, taken 2026-07-10 at HEAD 4fb9386 (branch handover/2026-07-10). Not edited.

```markdown
## 4. The COMMANDS that prove work is done

All run on 2026-07-10 from repo root `/Users/rohit/Documents/helm-factory`; every one passed. Fixture renders regenerate only gitignored artifacts — `git status` confirmed clean after the full gate.

| # | Command | Proves | Success signal |
|---|---|---|---|
| 1 | `helm lint platform-library/` | Chart.yaml + template parse sanity (weak — see §3.2) | `1 chart(s) linted, 0 chart(s) failed` (the `icon is recommended` INFO is expected) |
| 2 | `tests/render.sh <fixture>` (minimal\|full\|stateful\|daemon) | A consumer render end-to-end with schema enforced; accepts extra helm args (`--kube-version 1.31`, `--api-versions g/v/Kind`, `--set k=v`) | Manifests on stdout, exit 0. Kind counts: minimal 3, full 24, stateful 6, daemon 3 (`tests/render.sh full \| grep -c '^kind:'`) |
| 3 | `scripts/lint-library.sh` | THE gate: lint, schema metaschema + fixture values, render matrix k8s 1.31–1.36 with count assertions, golden diffs, kubeconform matrix, negative CRD-drop render, image-pin + helm-side schema + posture guardrail negative tests | Last line `==> PASS`, exit 0. Any `FAIL:` line = broken. |
| 4 | `REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh` | Same, in CI-strict mode (missing tools fail instead of warn). This is exactly what CI and release run. | `==> PASS`, exit 0 |
| 5 | `UPDATE_GOLDEN=1 scripts/lint-library.sh` | Accepts an *intentional* render change into `tests/golden/*.yaml`. NOT run this session (mutating). Must be followed by reviewing `git diff tests/golden/` and re-running #4 clean. | `updated tests/golden/<fx>.yaml` lines, then `==> PASS` |
| 6 | `shellcheck scripts/*.sh tests/render.sh` | Script hygiene (CI step) | No output, exit 0 |
| 7 | `check-jsonschema --check-metaschema platform-library/values.schema.reference.json` | Reference schema is valid JSON Schema (CI step) | `ok -- validation done` |
| 8 | `scripts/new-app-chart.sh <name> --dir <path>` then `helm dependency update <path> && helm template <name> <path>` | Scaffold + consumer pipeline works. Verified in scratchpad; when the chart lives outside the repo, rewrite the `file://../platform-library` repo path in Chart.yaml to an absolute `file:///Users/rohit/Documents/helm-factory/platform-library` (or use `--repo`). | 3 kinds rendered (ServiceAccount, Service, Deployment) |
| 9 | `tests/render.sh full --set capabilities.apiVersions=null` | Negative render: all 7 CRD-backed Kinds absent from output (subset of #3, useful standalone when touching gates) | No `kind: Certificate\|HTTPRoute\|GRPCRoute\|PeerAuthentication\|AuthorizationPolicy\|ServiceMonitor\|PodMonitor` lines |

Timing: the full gate (#4) takes ~1–2 min warm (kubeconform schema cache in `${TMPDIR}/kubeconform-schema-cache`); first run downloads CRD schemas from the datreeio catalog (network required).

Definition of done for any library change = #4 exits 0 **and** any golden/count change was intentional and reviewed. For consumer-chart work = #2/#8 renders clean with the CRD groups the chart uses force-assumed.

```
