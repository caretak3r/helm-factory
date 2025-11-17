# Architecture Decision Records (ADR)

This document contains Architecture Decision Records (ADRs) for the Helm Chart Factory system. ADRs capture important architectural decisions along with their context, consequences, and alternatives considered.

## Table of Contents

1. [ADR-001: Library Chart Pattern for Platform Standardization](#adr-001-library-chart-pattern-for-platform-standardization)
2. [ADR-002: Multi-Repository Architecture](#adr-002-multi-repository-architecture)
3. [ADR-003: Configuration-Driven Chart Generation](#adr-003-configuration-driven-chart-generation)
4. [ADR-004: Pull Request-Based Workflow](#adr-004-pull-request-based-workflow)
5. [ADR-005: Support for Multiple Workload Types](#adr-005-support-for-multiple-workload-types)
6. [ADR-006: Stage Toggles for Pipeline Flexibility](#adr-006-stage-toggles-for-pipeline-flexibility)
7. [ADR-007: Umbrella Chart for Service Orchestration](#adr-007-umbrella-chart-for-service-orchestration)
8. [ADR-008: Local Development Environment with k3s](#adr-008-local-development-environment-with-k3s)

---

## ADR-001: Library Chart Pattern for Platform Standardization

**Status:** Accepted  
**Date:** 2024-11-14  
**Deciders:** Platform Team  
**Tags:** helm, charts, standardization

### Context

Service teams need to deploy applications to Kubernetes using Helm charts, but each team creating their own charts leads to:
- Inconsistent security practices
- Duplication of best practices code
- Difficulty maintaining standards across teams
- Risk of misconfiguration

### Decision

We will use Helm's **library chart pattern** to create a centralized `platform-library` chart that contains reusable templates and best practices. Service teams submit a `configuration.yml` file (similar to `values.yaml`), and a chart generator tool automatically creates service-specific Helm charts that depend on the platform library.

### Architecture

```mermaid
graph TB
    subgraph "Platform Library"
        LC[platform-library/<br/>Chart.yaml<br/>type: library]
        LC --> TEMPLATES[templates/<br/>_deployment.yaml<br/>_service.yaml<br/>_ingress.yaml<br/>etc.]
        LC --> VALUES[values.yaml<br/>Default values]
    end
    
    subgraph "Service Configuration"
        CFG[configuration.yml<br/>Service-specific values]
    end
    
    subgraph "Chart Generator"
        CG[chart-generator/<br/>main.py]
    end
    
    subgraph "Generated Service Chart"
        SCHART[service-name/<br/>Chart.yaml<br/>dependency: platform]
        SCHART --> SVALS[values.yaml<br/>Merged config]
        SCHART --> STEMPLATES[templates/<br/>deployment.yaml<br/>service.yaml<br/>etc.]
    end
    
    CFG --> CG
    LC --> CG
    CG --> SCHART
    
    TEMPLATES -.->|Referenced by| STEMPLATES
    
    style LC fill:#e1f5ff
    style CFG fill:#ffcccc
    style CG fill:#fff4e1
    style SCHART fill:#e1ffe1
```

### Consequences

**Positive:**
- ✅ Centralized best practices enforcement
- ✅ Consistent security contexts, resource limits, and probes
- ✅ Easy to update standards across all services
- ✅ Service teams focus on application config, not Kubernetes manifests
- ✅ Reduced risk of misconfiguration

**Negative:**
- ⚠️ Platform team must maintain library chart
- ⚠️ Changes to library chart affect all services
- ⚠️ Service teams have less flexibility (by design)

**Neutral:**
- Service charts are generated, not manually maintained
- Requires chart generator tool

### Alternatives Considered

1. **Shared Templates Repository**: Teams copy templates manually
   - ❌ Rejected: No enforcement, templates get out of sync

2. **Helm Plugin**: Create a Helm plugin for standardization
   - ❌ Rejected: More complex, harder to maintain

3. **Kustomize Overlays**: Use Kustomize for standardization
   - ❌ Rejected: Less mature ecosystem, fewer features

---

## ADR-002: Multi-Repository Architecture

**Status:** Accepted  
**Date:** 2024-11-14  
**Deciders:** Platform Team, DevOps Team  
**Tags:** git, repositories, ci-cd

### Context

The system needs to support:
- Platform team maintaining library chart independently
- Service teams owning their service code and configuration
- Centralized umbrella chart for deployment orchestration
- CI/CD pipelines that can trigger independently

### Decision

We will use a **multi-repository architecture** with separate GitHub repositories:
- `platform-library` - Platform team's library chart
- `*-service` repositories - Each service has its own repository
- `umbrella-chart` - Umbrella chart repository
- `helm-chart-factory` - Tools and documentation repository

### Architecture

```mermaid
graph TB
    subgraph "GitHub Organization"
        PLATFORM_REPO[platform-library<br/>Repository]
        FE_REPO[frontend-service<br/>Repository]
        BE_REPO[backend-service<br/>Repository]
        DB_REPO[database-service<br/>Repository]
        UMBRELLA_REPO[umbrella-chart<br/>Repository]
        TOOLS_REPO[helm-chart-factory<br/>Repository]
    end
    
    subgraph "Jenkins"
        FE_PIPELINE[frontend-service<br/>Pipeline]
        BE_PIPELINE[backend-service<br/>Pipeline]
        DB_PIPELINE[database-service<br/>Pipeline]
        UMBRELLA_PIPELINE[umbrella-chart<br/>Pipeline]
    end
    
    FE_REPO -->|Webhook| FE_PIPELINE
    BE_REPO -->|Webhook| BE_PIPELINE
    DB_REPO -->|Webhook| DB_PIPELINE
    UMBRELLA_REPO -->|Webhook| UMBRELLA_PIPELINE
    
    FE_PIPELINE -->|Checkout| PLATFORM_REPO
    FE_PIPELINE -->|Checkout| TOOLS_REPO
    FE_PIPELINE -->|Create PR| UMBRELLA_REPO
    
    BE_PIPELINE -->|Checkout| PLATFORM_REPO
    BE_PIPELINE -->|Checkout| TOOLS_REPO
    BE_PIPELINE -->|Create PR| UMBRELLA_REPO
    
    DB_PIPELINE -->|Checkout| PLATFORM_REPO
    DB_PIPELINE -->|Checkout| TOOLS_REPO
    DB_PIPELINE -->|Create PR| UMBRELLA_REPO
    
    UMBRELLA_PIPELINE -->|Checkout| PLATFORM_REPO
    UMBRELLA_PIPELINE -->|Checkout| TOOLS_REPO
    
    style PLATFORM_REPO fill:#fff4e1
    style FE_REPO fill:#e1f5ff
    style BE_REPO fill:#e1f5ff
    style DB_REPO fill:#e1f5ff
    style UMBRELLA_REPO fill:#ffe1f5
    style TOOLS_REPO fill:#e1ffe1
```

### Consequences

**Positive:**
- ✅ Clear ownership boundaries
- ✅ Independent versioning and releases
- ✅ Service teams can work independently
- ✅ Platform team controls library chart evolution
- ✅ Fine-grained access control per repository
- ✅ Independent CI/CD pipelines

**Negative:**
- ⚠️ More repositories to manage
- ⚠️ Requires coordination for cross-repo changes
- ⚠️ More complex webhook configuration

**Neutral:**
- Requires tooling to sync across repositories
- PR-based workflow adds review step

### Alternatives Considered

1. **Monorepo**: Single repository with all services
   - ❌ Rejected: Harder to manage permissions, all teams see all code

2. **Two Repositories**: Platform repo + Services repo
   - ❌ Rejected: Services repo becomes bottleneck, harder to scale

3. **Git Submodules**: Use submodules for library chart
   - ❌ Rejected: Submodules are complex and error-prone

---

## ADR-003: Configuration-Driven Chart Generation

**Status:** Accepted  
**Date:** 2024-11-14  
**Deciders:** Platform Team  
**Tags:** automation, code-generation, helm

### Context

Service teams need Helm charts but shouldn't need to:
- Write Helm templates
- Understand Kubernetes resource details
- Maintain chart structure
- Keep up with best practice changes

### Decision

We will use a **configuration-driven approach** where:
1. Service teams create a `configuration.yml` file (similar to `values.yaml`)
2. A Python tool (`chart-generator`) reads the configuration
3. The tool merges service config with platform library defaults
4. The tool generates a complete Helm chart structure
5. Generated charts reference platform library templates

### Process Flow

```mermaid
flowchart TD
    START([Service Team<br/>Creates configuration.yml]) --> VALIDATE{Validate<br/>Configuration}
    
    VALIDATE -->|Invalid| ERROR[Error:<br/>Show Issues]
    VALIDATE -->|Valid| LOAD[Load configuration.yml]
    
    LOAD --> LOADLIB[Load Platform Library<br/>values.yaml]
    
    LOADLIB --> MERGE[Deep Merge<br/>Service Config +<br/>Library Defaults]
    
    MERGE --> DETECT[Detect Service Name<br/>from service.name]
    
    DETECT --> CREATEDIR[Create Chart Directory<br/>charts/service-name/]
    
    CREATEDIR --> COPYTMPL[Copy Library Templates<br/>_helpers.tpl<br/>_*.yaml templates]
    
    COPYTMPL --> CHARTYAML[Create Chart.yaml<br/>with dependency on<br/>platform library]
    
    CHARTYAML --> VALUESYAML[Create values.yaml<br/>with merged values]
    
    VALUESYAML --> TEMPLATES[Create Template Files<br/>deployment.yaml<br/>service.yaml<br/>ingress.yaml<br/>etc.]
    
    TEMPLATES --> COMPLETE([Chart Generated<br/>Ready for Helm])
    
    ERROR --> END([End])
    COMPLETE --> END
    
    style START fill:#90EE90
    style COMPLETE fill:#90EE90
    style ERROR fill:#FFB6C1
    style END fill:#FFB6C1
```

### Consequences

**Positive:**
- ✅ Service teams only write YAML configuration
- ✅ No Helm template knowledge required
- ✅ Consistent chart structure across all services
- ✅ Easy to update generation logic
- ✅ Can add new features by updating generator

**Negative:**
- ⚠️ Less flexibility for edge cases
- ⚠️ Requires generator tool maintenance
- ⚠️ Generated charts may be harder to debug

**Neutral:**
- Charts are generated, not committed to git (usually)
- Generator can be extended for new features

### Alternatives Considered

1. **Helm Scaffold**: Use `helm create` and customize
   - ❌ Rejected: Teams would still need Helm knowledge

2. **Template Repository**: Copy templates and customize
   - ❌ Rejected: No enforcement, templates diverge

3. **Helmfile**: Use Helmfile for configuration
   - ❌ Rejected: Adds another tool, less standard

---

## ADR-004: Pull Request-Based Workflow

**Status:** Accepted  
**Date:** 2024-11-14  
**Deciders:** Platform Team, DevOps Team  
**Tags:** git, workflow, ci-cd

### Context

We need a workflow that:
- Allows review before changes are deployed
- Prevents direct pushes to production
- Provides audit trail
- Enables rollback
- Supports multiple environments

### Decision

We will use a **pull request-based workflow**:
1. Service teams create PRs in their service repositories
2. PRs are reviewed and merged to `main`
3. Merging to `main` triggers service pipeline
4. Service pipeline creates PR to umbrella-chart repository
5. Umbrella PR is reviewed and merged
6. Merging umbrella PR triggers deployment

### Workflow Diagram

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant ServiceRepo as Service Repository
    participant ServicePR as Service PR
    participant ServicePipeline as Service Pipeline
    participant UmbrellaRepo as Umbrella Repository
    participant UmbrellaPR as Umbrella PR
    participant UmbrellaPipeline as Umbrella Pipeline
    participant k3s as k3s Cluster
    
    Dev->>ServiceRepo: 1. Edit configuration.yml
    Dev->>ServiceRepo: 2. Create PR
    ServiceRepo->>ServicePR: 3. PR Created
    
    ServicePR->>ServicePR: 4. Review & Approve
    ServicePR->>ServiceRepo: 5. Merge to main
    
    ServiceRepo->>ServicePipeline: 6. Webhook triggers pipeline
    ServicePipeline->>ServicePipeline: 7. Build image
    ServicePipeline->>ServicePipeline: 8. Generate chart
    ServicePipeline->>UmbrellaRepo: 9. Create PR
    
    UmbrellaRepo->>UmbrellaPR: 10. PR Created
    UmbrellaPR->>UmbrellaPR: 11. Validate (no deploy)
    
    UmbrellaPR->>UmbrellaPR: 12. Review & Approve
    UmbrellaPR->>UmbrellaRepo: 13. Merge to main
    
    UmbrellaRepo->>UmbrellaPipeline: 14. Webhook triggers pipeline
    UmbrellaPipeline->>UmbrellaPipeline: 15. Sync charts
    UmbrellaPipeline->>k3s: 16. Deploy to k3s
    k3s->>UmbrellaPipeline: 17. Deployment complete
```

### Consequences

**Positive:**
- ✅ Review process before deployment
- ✅ No direct pushes to production
- ✅ Clear audit trail
- ✅ Easy rollback (revert PR)
- ✅ Validation before merge
- ✅ Can test PR changes without deploying

**Negative:**
- ⚠️ More steps in workflow
- ⚠️ Requires PR reviewers
- ⚠️ Slower deployment cycle

**Neutral:**
- PRs can be auto-merged with proper checks
- Can add status checks for automation

### Alternatives Considered

1. **Direct Push to Main**: Merge directly, deploy automatically
   - ❌ Rejected: No review, higher risk

2. **Feature Branches**: Use feature branches with auto-merge
   - ❌ Rejected: Less control, harder to review

3. **GitOps with ArgoCD**: Use ArgoCD for GitOps
   - ⚠️ Considered: May adopt later, but PR workflow provides better control for POC

---

## ADR-005: Support for Multiple Workload Types

**Status:** Accepted  
**Date:** 2024-11-14  
**Deciders:** Platform Team  
**Tags:** kubernetes, workloads, flexibility

### Context

Different services have different requirements:
- Stateless web apps → Deployment
- Databases → StatefulSet (persistent storage, stable identity)
- Node agents → DaemonSet (one per node)

Using only Deployment limits flexibility and forces workarounds.

### Decision

We will support **multiple Kubernetes workload types**:
- **Deployment** (default) - For stateless applications
- **StatefulSet** - For stateful applications with persistent storage
- **StatefulSet** - For stateful applications with persistent storage
- **DaemonSet** - For node-level agents

Service teams specify workload type in `configuration.yml`:

```yaml
workload:
  type: StatefulSet  # or Deployment, DaemonSet
```

### Architecture

```mermaid
graph TB
    subgraph "Platform Library Templates"
        HELPER[_helpers.tpl<br/>platform.workload function]
        DEP_TMPL[_deployment.yaml<br/>platform.deployment]
        STS_TMPL[_statefulset.yaml<br/>platform.statefulset]
        DS_TMPL[_daemonset.yaml<br/>platform.daemonset]
    end
    
    subgraph "Generated Service Chart"
        WORKLOAD_TMPL[workload.yaml<br/>or deployment.yaml]
    end
    
    subgraph "Workload Selection Logic"
        CHECK{workload.type?}
        CHECK -->|Deployment| DEP_TMPL
        CHECK -->|StatefulSet| STS_TMPL
        CHECK -->|DaemonSet| DS_TMPL
    end
    
    HELPER --> CHECK
    DEP_TMPL --> WORKLOAD_TMPL
    STS_TMPL --> WORKLOAD_TMPL
    DS_TMPL --> WORKLOAD_TMPL
    
    style HELPER fill:#ffe1f5
    style DEP_TMPL fill:#e1f5ff
    style STS_TMPL fill:#fff4e1
    style DS_TMPL fill:#e1ffe1
    style WORKLOAD_TMPL fill:#ffcccc
```

### Consequences

**Positive:**
- ✅ Supports diverse service requirements
- ✅ No workarounds needed
- ✅ Proper Kubernetes resource types
- ✅ StatefulSet gets persistent storage automatically
- ✅ DaemonSet schedules correctly

**Negative:**
- ⚠️ More templates to maintain
- ⚠️ HPA only works with Deployment/StatefulSet
- ⚠️ Some features workload-specific

**Neutral:**
- Default remains Deployment (backward compatible)
- Can add more workload types later

### Alternatives Considered

1. **Deployment Only**: Force all services to use Deployment
   - ❌ Rejected: Databases need StatefulSet, agents need DaemonSet

2. **Separate Generators**: Different generators per workload type
   - ❌ Rejected: Too much duplication, harder to maintain

3. **Custom Resources**: Create custom workload resources
   - ❌ Rejected: Adds complexity, not standard Kubernetes

---

## ADR-006: Stage Toggles for Pipeline Flexibility

**Status:** Accepted  
**Date:** 2024-11-14  
**Deciders:** Platform Team, DevOps Team  
**Tags:** jenkins, ci-cd, flexibility

### Context

During POC, we need to:
- Skip deployment stages (no k3s cluster available)
- Test chart generation without deployment
- Enable/disable features as needed
- Support different environments (dev, staging, prod)

### Decision

We will add **environment variable toggles** for all Jenkins pipeline stages. Each stage checks an `ENABLE_*` environment variable before executing. Defaults are set for POC (deployment disabled).

### Toggle Structure

```mermaid
graph LR
    subgraph "Pipeline Stages"
        S1[Checkout]
        S2[Setup]
        S3[Validate]
        S4[Build]
        S5[Generate]
        S6[Lint]
        S7[Deploy]
        S8[Verify]
    end
    
    subgraph "Environment Variables"
        E1[ENABLE_CHECKOUT]
        E2[ENABLE_SETUP]
        E3[ENABLE_VALIDATE]
        E4[ENABLE_BUILD]
        E5[ENABLE_GENERATE]
        E6[ENABLE_LINT]
        E7[ENABLE_DEPLOY]
        E8[ENABLE_VERIFY]
    end
    
    E1 -->|Controls| S1
    E2 -->|Controls| S2
    E3 -->|Controls| S3
    E4 -->|Controls| S4
    E5 -->|Controls| S5
    E6 -->|Controls| S6
    E7 -->|Controls| S7
    E8 -->|Controls| S8
    
    style E7 fill:#FFB6C1
    style E8 fill:#FFB6C1
    style S7 fill:#FFB6C1
    style S8 fill:#FFB6C1
```

### Consequences

**Positive:**
- ✅ Flexible pipeline configuration
- ✅ POC can skip deployment
- ✅ Easy to enable/disable features
- ✅ Supports multiple environments
- ✅ Can test individual stages

**Negative:**
- ⚠️ More environment variables to manage
- ⚠️ Must document all toggles
- ⚠️ Risk of misconfiguration

**Neutral:**
- Defaults set for POC
- Can override per job or globally

### Alternatives Considered

1. **Separate Pipelines**: Different pipelines for POC vs production
   - ❌ Rejected: Duplication, harder to maintain

2. **Pipeline Parameters**: Use Jenkins parameters
   - ⚠️ Considered: Good for interactive use, but env vars simpler for automation

3. **Feature Flags**: Use feature flag service
   - ❌ Rejected: Overkill for this use case

---

## ADR-007: Umbrella Chart for Service Orchestration

**Status:** Accepted  
**Date:** 2024-11-14  
**Deciders:** Platform Team  
**Tags:** helm, orchestration, deployment

### Context

We need to:
- Deploy multiple services together
- Manage dependencies between services
- Coordinate updates across services
- Provide single deployment point

### Decision

We will use an **umbrella chart** pattern where:
1. Umbrella chart depends on all service charts
2. Service configurations are stored in `services/` directory
3. Umbrella sync tool automatically updates dependencies
4. Single `helm install` deploys all services

### Architecture

```mermaid
graph TB
    subgraph "Umbrella Chart"
        UC[umbrella-chart/<br/>Chart.yaml]
        UC --> DEPS[Dependencies:<br/>- frontend<br/>- backend<br/>- database]
        UC --> VALUES[values.yaml<br/>Global values]
        UC --> SVALUES[values-*.yaml<br/>Service-specific]
    end
    
    subgraph "Service Charts"
        FE_CHART[frontend Chart]
        BE_CHART[backend Chart]
        DB_CHART[database Chart]
    end
    
    subgraph "Service Configs"
        FE_CFG[services/frontend/<br/>configuration.yml]
        BE_CFG[services/backend/<br/>configuration.yml]
        DB_CFG[services/database/<br/>configuration.yml]
    end
    
    subgraph "Umbrella Sync Tool"
        SYNC[umbrella-sync/<br/>main.py]
    end
    
    FE_CFG --> SYNC
    BE_CFG --> SYNC
    DB_CFG --> SYNC
    
    SYNC --> FE_CHART
    SYNC --> BE_CHART
    SYNC --> DB_CHART
    
    SYNC --> DEPS
    SYNC --> SVALUES
    
    DEPS --> FE_CHART
    DEPS --> BE_CHART
    DEPS --> DB_CHART
    
    style UC fill:#ffe1f5
    style SYNC fill:#fff4e1
    style FE_CHART fill:#e1f5ff
    style BE_CHART fill:#e1f5ff
    style DB_CHART fill:#e1f5ff
```

### Consequences

**Positive:**
- ✅ Single deployment command
- ✅ Coordinated updates
- ✅ Shared configuration
- ✅ Dependency management
- ✅ Atomic deployments

**Negative:**
- ⚠️ All services deploy together
- ⚠️ One failure affects all
- ⚠️ Requires sync tool

**Neutral:**
- Can deploy individual charts if needed
- Umbrella chart is auto-generated

### Alternatives Considered

1. **Individual Deployments**: Deploy each service separately
   - ❌ Rejected: No coordination, harder to manage

2. **Helmfile**: Use Helmfile for multi-chart deployment
   - ⚠️ Considered: Good alternative, but umbrella chart is more standard

3. **Kustomize**: Use Kustomize overlays
   - ❌ Rejected: Less mature, fewer features

---

## ADR-008: Local Development Environment with k3s

**Status:** Accepted  
**Date:** 2024-11-14  
**Deciders:** Platform Team, DevOps Team  
**Tags:** kubernetes, local-development, testing

### Context

We need a local Kubernetes environment for:
- Testing chart generation
- Validating deployments
- POC demonstrations
- Developer onboarding

Options include: minikube, kind, k3s, Docker Desktop Kubernetes.

### Decision

We will use **k3s** as the local Kubernetes environment because:
- Lightweight and fast startup
- Single binary, easy installation
- Full Kubernetes API compatibility
- Good for CI/CD pipelines
- Works well in containers

### Architecture

```mermaid
graph TB
    subgraph "Local Machine"
        DEV[Developer]
        JENKINS[Jenkins Pipeline]
        K3S[k3s Cluster]
        REGISTRY[Local Docker<br/>Registry :5000]
    end
    
    subgraph "k3s Cluster"
        API[k3s API Server]
        ETCD[etcd]
        KUBELET[kubelet]
        PODS[Pods]
        SVC[Services]
        ING[Ingress]
    end
    
    subgraph "External"
        GH[GitHub<br/>Repositories]
    end
    
    DEV -->|Push| GH
    GH -->|Webhook| JENKINS
    
    JENKINS -->|Build Images| REGISTRY
    JENKINS -->|Deploy Charts| K3S
    
    K3S --> API
    API --> ETCD
    API --> KUBELET
    KUBELET --> PODS
    
    PODS -->|Pull Images| REGISTRY
    PODS --> SVC
    SVC --> ING
    
    style K3S fill:#e1ffe1
    style REGISTRY fill:#fff4e1
    style JENKINS fill:#ffe1f5
```

### Consequences

**Positive:**
- ✅ Fast startup (< 30 seconds)
- ✅ Low resource usage
- ✅ Full Kubernetes API
- ✅ Good for CI/CD
- ✅ Easy to reset/cleanup

**Negative:**
- ⚠️ Some differences from production clusters
- ⚠️ Single node (no HA testing)
- ⚠️ Limited storage options

**Neutral:**
- Can switch to other solutions later
- Production can use different distribution

### Alternatives Considered

1. **minikube**: Local Kubernetes
   - ⚠️ Considered: Heavier, slower startup

2. **kind**: Kubernetes in Docker
   - ⚠️ Considered: Good for CI, but more complex setup

3. **Docker Desktop Kubernetes**: Built-in K8s
   - ❌ Rejected: Platform-specific, licensing issues

4. **Production-like Cluster**: Use cloud cluster
   - ❌ Rejected: Cost, complexity, not local

---

## Summary

These ADRs document the key architectural decisions for the Helm Chart Factory system:

1. **Library Chart Pattern** - Centralized best practices
2. **Multi-Repository Architecture** - Clear ownership boundaries
3. **Configuration-Driven Generation** - Simplified developer experience
4. **Pull Request Workflow** - Review and audit trail
5. **Multiple Workload Types** - Flexibility for different services
6. **Stage Toggles** - Pipeline flexibility for POC and production
7. **Umbrella Chart** - Coordinated multi-service deployment
8. **k3s for Local Development** - Fast, lightweight testing environment

Each decision balances trade-offs between flexibility, maintainability, and ease of use, with a focus on enabling service teams while maintaining platform standards.

