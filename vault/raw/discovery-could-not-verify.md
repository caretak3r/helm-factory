# Raw: Discovery report — could not verify / open items

Provenance: verbatim copy of `.claude/operating/discovery.md` lines 166-174, taken 2026-07-10 at HEAD 4fb9386 (branch handover/2026-07-10). Not edited.

```markdown
## Could not verify / open items

- **`UPDATE_GOLDEN=1` leg** not executed (mutates committed goldens; forbidden this phase). Mechanism read from source (`lint-library.sh:136-139`) and is CI-exercised.
- **Release workflow end-to-end** (tag → GHCR push) not executable locally; verified by reading `release.yaml` only. Whether `oci://ghcr.io/caretak3r/charts` currently hosts a published 2.0.0 is unverified (no network push allowed; consumers in-repo use `file://`).
- **Real-cluster behavior** (live `.Capabilities` discovery, `lookup`-based tlsSelfSigned reuse, `helm upgrade --dry-run=server`) — no cluster in this environment. Claims come from source comments and the spec, which were accurate everywhere else I could check.
- **`global.*` umbrella helpers / `serviceEndpoints`** have zero fixture coverage; their output shape (`_helpers.tpl:512-591`) is untested by the gate. Any skill touching them should render-verify first.
- **`platform.util.merge`** is defined but has no call sites in the library — it's public API for advanced consumers per the spec (§5). Dead-ish code; do not remove without a deprecation pass.
- Beads issue helm-factory-uaw confirms a known gate gap: kubeconform validates the *single* canonical render against each matrix version, not per-version renders (`raw` captured once at line 129, reused at 158). Skills referencing the gate should not overstate matrix coverage.
```
