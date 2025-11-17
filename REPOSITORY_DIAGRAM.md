# Repository Structure Diagram

## Visual Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GitHub Organization                                  │
│                      companyinfo/* repositories                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  Repository: platform-library                                               │
│  URL: https://github.com/companyinfo/platform-library                      │
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
│      └── ...                                                                │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Used by
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
│  └── Jenkinsfile  ← Service pipeline                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Updates
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Repository: backend-service                                                │
│  URL: https://github.com/companyinfo/backend-service                       │
│  Maintained by: Backend Team                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│  Files:                                                                     │
│  ├── configuration.yml  ← Webhook triggers on change                       │
│  ├── Dockerfile                                                             │
│  ├── main.py                                                                │
│  ├── requirements.txt                                                       │
│  └── Jenkinsfile                                                            │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Updates
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
│  └── Jenkinsfile                                                            │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Updates
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Repository: umbrella-chart                                                 │
│  URL: https://github.com/companyinfo/umbrella-chart                         │
│  Maintained by: Platform Team (auto-updated by pipelines)                   │
├─────────────────────────────────────────────────────────────────────────────┤
│  Files:                                                                     │
│  ├── Chart.yaml                                                             │
│  ├── values.yaml                                                            │
│  ├── services/                                                              │
│  │   ├── frontend/                                                          │
│  │   │   └── configuration.yml  ← Copied from frontend-service repo        │
│  │   ├── backend/                                                           │
│  │   │   └── configuration.yml  ← Copied from backend-service repo         │
│  │   └── database/                                                          │
│  │       └── configuration.yml ← Copied from database-service repo       │
│  ├── charts/  ← Generated (gitignored)                                     │
│  ├── values-*.yaml  ← Generated (gitignored)                               │
│  └── Jenkinsfile  ← Umbrella pipeline                                       │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              │ Deploys to
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Repository: helm-chart-factory (This Repo)                                 │
│  URL: https://github.com/companyinfo/helm-chart-factory                    │
│  Maintained by: Platform Team                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│  Files:                                                                     │
│  ├── factory/                                                               │
│  │   ├── chart-generator/  ← Tools (checked out by Jenkins)                │
│  │   ├── umbrella-sync/    ← Tools (checked out by Jenkins)                 │
│  │   ├── scripts/          ← Setup scripts                                 │
│  │   ├── cert-manager/     ← Cert-manager configs                          │
│  │   ├── jenkins/          ← Jenkins manifests                             │
│  │   ├── Jenkinsfile.service  ← Template for services                      │
│  │   └── Jenkinsfile.umbrella ← Template for umbrella                      │
│  └── Documentation                                                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

## File Location Reference

### platform-library Repository
```
platform-library/
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
    ├── workload.yaml
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── certificate.yaml
    ├── mtls.yaml
    ├── serviceaccount.yaml
    └── hpa.yaml
```

### Service Repository (e.g., frontend-service)
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
├── Jenkinsfile                ← Copied from Jenkinsfile.service
├── .gitignore
└── .dockerignore
```

### umbrella-chart Repository
```
umbrella-chart/
├── Chart.yaml
├── values.yaml
├── services/                  ← Service configurations (copied)
│   ├── frontend/
│   │   └── configuration.yml
│   ├── backend/
│   │   └── configuration.yml
│   └── database/
│       └── configuration.yml
├── charts/                    ← Generated charts (gitignored)
│   ├── frontend/
│   ├── backend/
│   └── database/
├── values-*.yaml              ← Generated values (gitignored)
├── Chart.lock                 ← Generated (gitignored)
├── Jenkinsfile                ← Copied from Jenkinsfile.umbrella
└── .gitignore
```

### helm-chart-factory Repository (Tools)
```
helm-chart-factory/
├── factory/
│   ├── chart-generator/       ← Used by Jenkins
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── umbrella-sync/         ← Used by Jenkins
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── scripts/               ← Utility scripts
│   ├── cert-manager/          ← Cert-manager configs
│   ├── jenkins/               ← Jenkins manifests
│   ├── Jenkinsfile.service    ← Template
│   └── Jenkinsfile.umbrella   ← Template
└── Documentation files
```

## CI/CD Flow

```
Developer edits configuration.yml in service repo
         │
         ▼
    Git Push
         │
         ▼
    GitHub Webhook
         │
         ▼
┌────────────────────────┐
│  Jenkins Pipeline       │
│  (Service-specific)     │
├────────────────────────┤
│  1. Checkout service   │
│  2. Checkout platform  │
│  3. Checkout tools      │
│  4. Build image         │
│  5. Generate chart       │
│  6. Update umbrella     │
└────────────────────────┘
         │
         ▼
    Push to umbrella-chart repo
         │
         ▼
    GitHub Webhook
         │
         ▼
┌────────────────────────┐
│  Jenkins Pipeline       │
│  (Umbrella)             │
├────────────────────────┤
│  1. Checkout umbrella  │
│  2. Checkout platform   │
│  3. Checkout tools      │
│  4. Sync all services   │
│  5. Deploy to k3s       │
└────────────────────────┘
         │
         ▼
    k3s Cluster
```

## Quick Reference

| What | Where | Repository |
|------|-------|------------|
| Platform templates | `platform-library/` | `platform-library` |
| Service config | `configuration.yml` | `*-service` |
| Service code | `src/`, `Dockerfile` | `*-service` |
| Service pipeline | `Jenkinsfile` | `*-service` |
| Umbrella chart | `Chart.yaml`, `values.yaml` | `umbrella-chart` |
| Service configs (copied) | `services/*/configuration.yml` | `umbrella-chart` |
| Umbrella pipeline | `Jenkinsfile` | `umbrella-chart` |
| Chart generator | `chart-generator/` | `helm-chart-factory` |
| Umbrella sync | `umbrella-sync/` | `helm-chart-factory` |
| Setup scripts | `scripts/` | `helm-chart-factory` |

