# Vendored kubeconform schemas

Everything under this directory is fetched from upstream by
`scripts/vendor-schemas.sh` — the only script in this repo allowed to make
network requests for schema data. `scripts/lint-library.sh` validates
against these local copies only; it makes zero network requests.

Last refreshed: **2026-07-10** for Kubernetes 1.34 1.35 1.36
(see `scripts/lib/schema-manifest.sh` for the authoritative version/Kind
list this snapshot covers).

## Layout

- `native/v<X.Y.Z>-standalone-strict/<kind>.json` — core Kubernetes object
  schemas, mirroring the layout of
  [yannh/kubernetes-json-schema](https://github.com/yannh/kubernetes-json-schema)
  (`standalone-strict` variant, self-contained with no external `$ref`s).
  One directory per supported Kubernetes version.
- `crd/<group>/<kind>_<apiVersion>.json` — CRD schemas mirroring the layout
  of [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog).
  Not versioned per Kubernetes release, since CRDs are cluster-installed
  independently of core Kubernetes.

Both layouts intentionally match kubeconform's default `-schema-location`
templating so `scripts/lint-library.sh` only had to swap the remote base URL
for a local filesystem path — see that script's `NATIVE_SCHEMA_LOCATION` /
`CRD_SCHEMA_LOCATION` variables.

## Refreshing

```bash
scripts/vendor-schemas.sh
```

Re-run after editing `scripts/lib/schema-manifest.sh` (e.g. bumping
`KUBE_VERSIONS` for a new supported Kubernetes window, or adding a schema
stem/path for a new Kind a fixture renders), then commit the resulting diff
under `tests/schemas/`.

## Provenance

| Source | Upstream | Variant |
| --- | --- | --- |
| Core Kubernetes schemas | `https://cdn.jsdelivr.net/gh/yannh/kubernetes-json-schema@master` | `{version}-standalone-strict` |
| CRD schemas | `https://cdn.jsdelivr.net/gh/datreeio/CRDs-catalog@main` | n/a |

Only the schema stems/paths listed in `scripts/lib/schema-manifest.sh` are
vendored — the subset actually exercised by `tests/fixtures/*` across the
render matrix, not the full upstream catalogs (which run into the hundreds of
MB per Kubernetes version).
