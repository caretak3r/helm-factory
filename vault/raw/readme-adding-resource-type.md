# Raw: README — Adding a new resource type + Validation

Provenance: verbatim copy of `README.md` lines 970-989, taken 2026-07-10 at HEAD 4fb9386 (branch handover/2026-07-10). Not edited.

```markdown
## Contributing

See [CORE.md](CORE.md) for architecture details, known issues, and maintenance guidelines.

### Adding a new resource type

1. Create `platform-library/templates/_<resource>.yaml` with a `define "platform.<resource>"` block
2. If the Kind is CRD-backed or version-negotiated, register it in the Kind→apiVersion registry in `_capabilities.tpl`
3. Add the `include` call to `_app.yaml` guarded by `.Values.<resource>.enabled` (and a capability gate for CRD-backed Kinds)
4. Add defaults to `values.yaml` under `exports.defaults` and extend `values.schema.reference.json`
5. Cover it in a fixture under `tests/fixtures/`, bump `expected_kinds` in `scripts/lint-library.sh`, and regenerate goldens: `UPDATE_GOLDEN=1 scripts/lint-library.sh`
6. Update `CORE.md` rendering order and directory listing

### Validation

```bash
helm lint platform-library/
scripts/lint-library.sh              # render matrix, goldens, kubeconform, guardrails
UPDATE_GOLDEN=1 scripts/lint-library.sh   # accept intentional render changes
```
```
