# platform-library docs site

This is the [Docusaurus](https://docusaurus.io/) documentation site for the
`platform-library` Helm chart.

## Installation

```bash
npm ci
```

## Local Development

```bash
npm start
```

This command starts a local development server and opens up a browser window. Most
changes are reflected live without having to restart the server.

## Build

```bash
npm run build
```

This command generates static content into the `build` directory and can be served
using any static contents hosting service.

## Deployment

Deployment is handled by `.github/workflows/docs.yaml` on push to `main` (path-filtered
to docs-affecting changes) via `actions/deploy-pages`, not the `docusaurus deploy`
command. GitHub Pages must be enabled in repo settings (Pages → Source: GitHub Actions)
for the workflow's deploy step to publish.
