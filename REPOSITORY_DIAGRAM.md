# Repository Structure Diagram

## Visual Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GitHub Organization                                  │
│                      companyinfo/* repositories                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  Repository: common-library                                                 │
│  URL: https://github.com/companyinfo/common-library                         │
│  Maintained by: Platform Team                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  Files:                                                                     │
│  ├── Chart.yaml                                                             │
│  ├── values.yaml                                                            │
│  └── templates/                                                              │
│      ├── _helpers.tpl                                                       │
│      ├── _deployment.yaml                                                   │
│      ├── _statefulset.yaml                                                  │
│      ├── _daemonset.yaml                                                    │
│      ├── _service.yaml                                                      │
│      ├── _ingress.yaml                                                      │
│      ├── _certificate.yaml                                                  │
│      ├── _mtls.yaml                                                         │
│      ├── _hpa.yaml                                                          │
│      ├── _job.yaml                                                          │
│      └── ...                                                                │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Static dependency
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Repository: frontend-service                                               │
│  URL: https://github.com/companyinfo/frontend-service                       │
│  Maintained by: Frontend Team                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  Files:                                                                     │
│  ├── configuration.yml  ← Webhook triggers on change                       │
│  ├── Dockerfile                                                             │
│  ├── nginx.conf                                                             │
│  ├── package.json                                                           │
│  ├── src/                                                                   │
│  │   ├── App.js                                                             │
│  │   └── ...                                                                │
│  ├── public/                                                                │
│  ├── Jenkinsfile  ← Service pipeline (from Jenkinsfile.service.new)        │
│  ├── .gitignore                                                             │
│  └── .dockerignore                                                          │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Creates PR with config.yml
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Repository: backend-service                                                │
│  URL: https://github.com/companyinfo/backend-service                        │
│  Maintained by: Backend Team                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│  Files:                                                                     │
│  ├── configuration.yml  ← Webhook triggers on change                       │
│  ├── Dockerfile                                                             │
│  ├── main.py                                                                │
│  ├── requirements.txt                                                       │
│  ├── Jenkinsfile                                                            │
│  ├── .gitignore                                                             │
│  └── .dockerignore                                                          │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Creates PR with config.yml
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Repository: database-service                                               │
│  URL: https://github.com/companyinfo/database-service                       │
│  Maintained by: Database Team                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  Files:                                                                     │
│  ├── configuration.yml  ← Webhook triggers on change                       │
│  ├── Dockerfile                                                             │
│  ├── init.sql                                                               │
│  ├── Jenkinsfile                                                            │
│  ├── .gitignore                                                             │
│  └── .dockerignore                                                          │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Creates PR with config.yml
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Repository: umbrella-chart                                                 │
│  URL: https://github.com/companyinfo/umbrella-chart                         │
│  Maintained by: Platform Team (auto-updated by pipelines)                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  Files:                                                                     │
│  ├── Chart.yaml  ← Static dependency on common-library                    │
│  ├── values.yaml                                                            │
│  ├── services/                                                              │
│  │   ├── frontend/                                                          │
│  │   │   └── configuration.yml  ← Copied from frontend-service repo        │
│  │   ├── backend/                                                           │
│  │   │   └── configuration.yml  ← Copied from backend-service repo         │
│  │   └── database/                                                          │
│  │       └── configuration.yml ← Copied from database-service repo       │
│  ├── src/  ← Chart generation and validation tools                         │
│  │   └── chart-generator/                                                   │
│  │       ├── main.py                                                        │
│  │       └── requirements.txt                                              │
│  ├── charts/  ← Generated (gitignored)                                     │
│  │   ├── frontend/                                                          │
│  │   ├── backend/                                                           │
│  │   └── database/                                                          │
│  ├── Jenkinsfile  ← Umbrella pipeline (from Jenkinsfile.umbrella.new)      │
│  └── .gitignore                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Deploys to
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Kubernetes Clusters (QA & Production)                                     │
│  ECR Registries (QA & Production)                                           │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  Repository: helm-chart-factory (This Repo)                                 │
│  URL: https://github.com/companyinfo/helm-chart-factory                    │
│  Maintained by: Platform Team                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│  Files:                                                                     │
│  ├── factory/                                                               │
│  │   ├── chart-generator/  ← Source code (copied to umbrella-chart/src/)  │
│  │   ├── common-library/   ← Source code (copied to common-library repo)   │
│  │   ├── services/         ← Example service configs                        │
│  │   ├── scripts/          ← Setup scripts                                 │
│  │   ├── Jenkinsfile.service.new  ← Template for services                  │
│  │   ├── Jenkinsfile.umbrella.new ← Template for umbrella                  │
│  │   └── Documentation                                                     │
│  └── README.md                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## File Location Reference

### common-library Repository
**Copy from:** `factory/common-library/` (if exists) or create from templates

```
common-library/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── _deployment.yaml
    ├── _statefulset.yaml
    ├── _daemonset.yaml
    ├── _service.yaml
    ├── _ingress.yaml
    ├── _certificate.yaml
    ├── _mtls.yaml
    ├── _hpa.yaml
    ├── _serviceaccount.yaml
    ├── _job.yaml
    └── ...
```

### Service Repository (e.g., frontend-service)
**Copy from:** `factory/services/frontend/` and `factory/Jenkinsfile.service.new`

```
frontend-service/
├── configuration.yml          ← Main config file
├── Dockerfile
├── nginx.conf
├── package.json
├── src/
│   ├── App.js
│   ├── index.js
│   └── index.css
├── public/
│   └── index.html
├── Jenkinsfile                ← Copy from Jenkinsfile.service.new
├── .gitignore
└── .dockerignore
```

### umbrella-chart Repository
**Copy from:** `factory/chart-generator/` → `umbrella-chart/src/chart-generator/`
**Copy from:** `factory/Jenkinsfile.umbrella.new` → `umbrella-chart/Jenkinsfile`

```
umbrella-chart/
├── Chart.yaml                 ← Static dependency on common-library
├── values.yaml
├── services/                  ← Service configurations (copied from service repos)
│   ├── frontend/
│   │   └── configuration.yml
│   ├── backend/
│   │   └── configuration.yml
│   └── database/
│       └── configuration.yml
├── src/                       ← Chart generation and validation tools
│   └── chart-generator/
│       ├── main.py            ← Copy from factory/chart-generator/main.py
│       ├── requirements.txt   ← Copy from factory/chart-generator/requirements.txt
│       └── ...
├── charts/                    ← Generated charts (gitignored)
│   ├── frontend/
│   ├── backend/
│   └── database/
├── Jenkinsfile                ← Copy from Jenkinsfile.umbrella.new
└── .gitignore                 ← Should ignore charts/, *.tgz, Chart.lock
```

### helm-chart-factory Repository (This Repository)
**Contains:** Source code, templates, and documentation

```
helm-chart-factory/
├── factory/
│   ├── chart-generator/       ← Source code (copy to umbrella-chart/src/)
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── common-library/        ← Source code (copy to common-library repo)
│   ├── services/              ← Example service configs
│   ├── scripts/               ← Utility scripts
│   ├── Jenkinsfile.service.new    ← Template for service repos
│   ├── Jenkinsfile.umbrella.new   ← Template for umbrella repo
│   └── Documentation files
└── README.md
```

## CI/CD Flow

```
Developer edits configuration.yml in service repo
         │
         ▼
    Git Push to main
         │
         ▼
    GitHub Webhook
         │
         ▼
┌────────────────────────┐
│  Jenkins Pipeline       │
│  (Service-specific)    │
├────────────────────────┤
│  1. Checkout service   │
│  2. Install tools      │
│  3. Build image        │
│  4. Push to QA ECR     │
│  5. Generate chart     │
│  6. Validate chart     │
│  7. Push chart to QA   │
│  8. Push to PROD ECR   │
│     (if approved)      │
│  9. Create PR to       │
│     umbrella-chart     │
└────────────────────────┘
         │
         ▼
    PR to umbrella-chart repo
         │
         ▼
    GitHub Webhook
         │
         ▼
┌────────────────────────┐
│  Jenkins Pipeline       │
│  (Umbrella - PR)       │
├────────────────────────┤
│  1. Checkout umbrella  │
│  2. Checkout common    │
│  3. Install tools       │
│  4. Generate charts     │
│  5. Update dependencies│
│  6. Lint charts         │
│  7. Template charts     │
└────────────────────────┘
         │
         ▼
    PR Merged to main
         │
         ▼
┌────────────────────────┐
│  Jenkins Pipeline       │
│  (Umbrella - Main)     │
├────────────────────────┤
│  1. Checkout umbrella  │
│  2. Checkout common    │
│  3. Generate charts     │
│  4. Update dependencies│
│  5. Deploy to K8s      │
│  6. Verify deployment  │
└────────────────────────┘
         │
         ▼
    Kubernetes Cluster
```

## Quick Reference

| What | Where | Repository | Copy From |
|------|-------|------------|-----------|
| Common library templates | `common-library/` | `common-library` | `factory/common-library/` |
| Service config | `configuration.yml` | `*-service` | `factory/services/*/configuration.yml` |
| Service code | `src/`, `Dockerfile` | `*-service` | `factory/services/*/` |
| Service pipeline | `Jenkinsfile` | `*-service` | `factory/Jenkinsfile.service.new` |
| Umbrella chart | `Chart.yaml`, `values.yaml` | `umbrella-chart` | Create manually |
| Service configs (copied) | `services/*/configuration.yml` | `umbrella-chart` | Copied by service pipelines |
| Chart generator | `src/chart-generator/` | `umbrella-chart` | `factory/chart-generator/` |
| Umbrella pipeline | `Jenkinsfile` | `umbrella-chart` | `factory/Jenkinsfile.umbrella.new` |

## Files to Copy to Each Repository

### common-library Repository
```bash
# Copy from factory/common-library/ to common-library repo
cp -r factory/common-library/* <common-library-repo>/
```

### Service Repository (e.g., frontend-service)
```bash
# Copy service files
cp factory/services/frontend/configuration.yml <service-repo>/
cp factory/services/frontend/Dockerfile <service-repo>/
cp -r factory/services/frontend/src <service-repo>/
cp -r factory/services/frontend/public <service-repo>/
cp factory/services/frontend/package.json <service-repo>/
cp factory/services/frontend/nginx.conf <service-repo>/

# Copy Jenkinsfile
cp factory/Jenkinsfile.service.new <service-repo>/Jenkinsfile

# Copy ignore files
cp factory/services/frontend/.gitignore <service-repo>/
cp factory/services/frontend/.dockerignore <service-repo>/
```

### umbrella-chart Repository
```bash
# Copy chart generator to src/
mkdir -p <umbrella-repo>/src
cp -r factory/chart-generator <umbrella-repo>/src/

# Copy Jenkinsfile
cp factory/Jenkinsfile.umbrella.new <umbrella-repo>/Jenkinsfile

# Create initial structure
mkdir -p <umbrella-repo>/services/{frontend,backend,database}
mkdir -p <umbrella-repo>/charts

# Copy initial service configs (optional)
cp factory/services/frontend/configuration.yml <umbrella-repo>/services/frontend/
cp factory/services/backend/configuration.yml <umbrella-repo>/services/backend/
cp factory/services/database/configuration.yml <umbrella-repo>/services/database/

# Create Chart.yaml with common-library dependency
# Create values.yaml
# Create .gitignore
```
