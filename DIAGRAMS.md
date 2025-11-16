# Helm Chart Factory - Comprehensive System Diagrams

This document contains detailed mermaid diagrams explaining how the Helm Chart Factory system works, including all workflows and component interactions.

## Table of Contents

1. [System Architecture Overview](#system-architecture-overview)
2. [Component Relationships](#component-relationships)
3. [Developer Workflow](#developer-workflow)
4. [Chart Generation Process](#chart-generation-process)
5. [Umbrella Chart Sync Flow](#umbrella-chart-sync-flow)
6. [Jenkins Pipeline Flow](#jenkins-pipeline-flow)
7. [Deployment Flow](#deployment-flow)
8. [Library Chart Structure](#library-chart-structure)
9. [Service Lifecycle](#service-lifecycle)
10. [Complete End-to-End Flow](#complete-end-to-end-flow)

---

## System Architecture Overview

```mermaid
graph TB
    subgraph "Service Teams"
        FE[Frontend Team<br/>configuration.yml]
        BE[Backend Team<br/>configuration.yml]
        DB[Database Team<br/>configuration.yml]
    end
    
    subgraph "Platform Team"
        LC[Platform Library Chart<br/>Best Practices Templates]
        CG[Chart Generator<br/>Python Tool]
        US[Umbrella Sync<br/>Python Tool]
    end
    
    subgraph "CI/CD"
        GH[Git Repository]
        WH[Webhook]
        JN[Jenkins Pipeline<br/>on k3s]
    end
    
    subgraph "Generated Artifacts"
        SC1[Frontend Chart]
        SC2[Backend Chart]
        SC3[Database Chart]
        UC[Umbrella Chart]
    end
    
    subgraph "k3s Cluster"
        NS[platform namespace]
        DEP1[Frontend Deployment]
        DEP2[Backend Deployment]
        DEP3[Database Deployment]
        SVC[Services]
        ING[Ingress]
        CERT[Certificates]
    end
    
    FE -->|Submit| GH
    BE -->|Submit| GH
    DB -->|Submit| GH
    
    GH -->|Triggers| WH
    WH -->|Triggers| JN
    
    JN -->|Uses| CG
    JN -->|Uses| US
    CG -->|Uses| LC
    
    CG -->|Generates| SC1
    CG -->|Generates| SC2
    CG -->|Generates| SC3
    
    US -->|Creates| UC
    UC -->|Depends on| SC1
    UC -->|Depends on| SC2
    UC -->|Depends on| SC3
    
    JN -->|Deploys| UC
    UC -->|Creates| DEP1
    UC -->|Creates| DEP2
    UC -->|Creates| DEP3
    UC -->|Creates| SVC
    UC -->|Creates| ING
    UC -->|Creates| CERT
    
    DEP1 --> NS
    DEP2 --> NS
    DEP3 --> NS
    SVC --> NS
    ING --> NS
    CERT --> NS
    
    style LC fill:#e1f5ff
    style CG fill:#fff4e1
    style US fill:#fff4e1
    style JN fill:#ffe1f5
    style UC fill:#e1ffe1
```

---

## Component Relationships

```mermaid
graph LR
    subgraph "Input Layer"
        CFG[configuration.yml<br/>Service Config]
    end
    
    subgraph "Processing Layer"
        CG[Chart Generator<br/>main.py]
        LC[Library Chart<br/>platform-library/]
        US[Umbrella Sync<br/>main.py]
    end
    
    subgraph "Output Layer"
        SCH[Service Chart<br/>Chart.yaml + templates]
        UC[Umbrella Chart<br/>Chart.yaml + deps]
    end
    
    subgraph "Deployment Layer"
        HELM[Helm CLI]
        K8S[k3s Cluster]
    end
    
    CFG -->|Input| CG
    LC -->|Templates| CG
    CG -->|Generates| SCH
    
    CFG -->|Input| US
    SCH -->|Dependency| US
    US -->|Creates| UC
    
    UC -->|Installed via| HELM
    HELM -->|Deploys to| K8S
    
    style CFG fill:#ffcccc
    style CG fill:#ccffcc
    style LC fill:#ccccff
    style US fill:#ccffcc
    style SCH fill:#ffffcc
    style UC fill:#ffccff
```

---

## Developer Workflow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Git as Git Repository
    participant Webhook as Webhook
    participant Jenkins as Jenkins Pipeline
    participant Generator as Chart Generator
    participant Umbrella as Umbrella Sync
    participant k3s as k3s Cluster
    
    Dev->>Git: 1. Edit configuration.yml
    Dev->>Git: 2. Commit changes
    Dev->>Git: 3. Push to repository
    
    Git->>Webhook: 4. Push event
    Webhook->>Jenkins: 5. Trigger pipeline
    
    Jenkins->>Jenkins: 6. Checkout code
    Jenkins->>Jenkins: 7. Setup environment
    
    Jenkins->>Generator: 8. Validate configs
    Generator-->>Jenkins: 9. Validation OK
    
    Jenkins->>Generator: 10. Generate charts
    Generator->>Generator: 11. Load config.yml
    Generator->>Generator: 12. Merge with library values
    Generator->>Generator: 13. Copy library templates
    Generator->>Generator: 14. Create Chart.yaml
    Generator->>Generator: 15. Create values.yaml
    Generator->>Generator: 16. Create template files
    Generator-->>Jenkins: 17. Charts generated
    
    Jenkins->>Jenkins: 18. Lint charts
    Jenkins->>Jenkins: 19. Template charts
    
    Jenkins->>Umbrella: 20. Sync umbrella chart
    Umbrella->>Umbrella: 21. Find all configs
    Umbrella->>Umbrella: 22. Generate charts
    Umbrella->>Umbrella: 23. Update Chart.yaml
    Umbrella->>Umbrella: 24. Create values files
    Umbrella-->>Jenkins: 25. Umbrella synced
    
    Jenkins->>k3s: 26. Deploy umbrella chart
    k3s->>k3s: 27. Create resources
    k3s-->>Jenkins: 28. Deployment complete
    
    Jenkins->>k3s: 29. Verify deployment
    k3s-->>Jenkins: 30. All pods ready
    
    Jenkins->>k3s: 31. Run tests
    k3s-->>Jenkins: 32. Tests passed
    
    Jenkins-->>Dev: 33. Pipeline success notification
```

---

## Chart Generation Process

```mermaid
flowchart TD
    START([Start: configuration.yml]) --> VALIDATE{Validate<br/>Configuration}
    
    VALIDATE -->|Missing Fields| ERROR1[Error:<br/>Invalid Config]
    VALIDATE -->|Valid| LOAD[Load configuration.yml]
    
    LOAD --> LOADLIB[Load Library Chart<br/>values.yaml]
    LOADLIB --> MERGE[Deep Merge Config<br/>with Library Values]
    
    MERGE --> DETECT[Detect Chart Name<br/>from service.name]
    
    DETECT --> CREATEDIR[Create Output Directory<br/>charts/service-name/]
    
    CREATEDIR --> COPYTMPL[Copy Library Templates<br/>_*.yaml, _helpers.tpl]
    
    COPYTMPL --> CHARTYAML[Create Chart.yaml<br/>with dependency on platform]
    
    CHARTYAML --> VALUESYAML[Create values.yaml<br/>merged configuration]
    
    VALUESYAML --> TEMPLATES{Create Template<br/>Files}
    
    TEMPLATES --> DEPLOY_TMPL[deployment.yaml<br/>calls platform.deployment]
    TEMPLATES --> SVC_TMPL[service.yaml<br/>calls platform.service]
    
    TEMPLATES --> INGRESS_CHECK{Ingress<br/>Enabled?}
    INGRESS_CHECK -->|Yes| ING_TMPL[ingress.yaml<br/>calls platform.ingress]
    INGRESS_CHECK -->|No| CERT_CHECK
    
    ING_TMPL --> CERT_CHECK{Certificate<br/>Enabled?}
    CERT_CHECK -->|Yes| CERT_TMPL[certificate.yaml<br/>calls platform.certificate]
    CERT_CHECK -->|No| MTLS_CHECK
    
    CERT_TMPL --> MTLS_CHECK{mTLS<br/>Enabled?}
    MTLS_CHECK -->|Yes| MTLS_TMPL[mtls.yaml<br/>calls platform.mtls]
    MTLS_CHECK -->|No| HPA_CHECK
    
    MTLS_TMPL --> HPA_CHECK{Autoscaling<br/>Enabled?}
    HPA_CHECK -->|Yes| HPA_TMPL[hpa.yaml<br/>calls platform.hpa]
    HPA_CHECK -->|No| SA_TMPL
    
    HPA_TMPL --> SA_TMPL[serviceaccount.yaml<br/>calls platform.serviceAccount]
    
    SA_TMPL --> COMPLETE([Chart Generated<br/>Successfully])
    
    ERROR1 --> END([End])
    COMPLETE --> END
    
    style START fill:#90EE90
    style COMPLETE fill:#90EE90
    style ERROR1 fill:#FFB6C1
    style END fill:#FFB6C1
```

---

## Umbrella Chart Sync Flow

```mermaid
flowchart TD
    START([Start: Sync Umbrella]) --> SCAN[Scan services/<br/>for configuration.yml]
    
    SCAN --> FOUND{Configs<br/>Found?}
    FOUND -->|No| WARN[Warning:<br/>No configs]
    FOUND -->|Yes| LOOP[For Each Config]
    
    LOOP --> LOAD[Load configuration.yml]
    LOAD --> EXTRACT[Extract service.name]
    
    EXTRACT --> VALID{Valid<br/>service.name?}
    VALID -->|No| SKIP[Skip Config<br/>Log Warning]
    VALID -->|Yes| GEN[Generate Chart<br/>via Chart Generator]
    
    GEN --> CHARTDIR[Create charts/<br/>service-name/]
    CHARTDIR --> COPYVAL[Copy config as<br/>values.yaml]
    
    COPYVAL --> DEPEND[Add Dependency<br/>to Chart.yaml]
    
    DEPEND --> VALUESFILE[Create values-<br/>service-name.yaml]
    
    VALUESFILE --> NEXT{More<br/>Configs?}
    NEXT -->|Yes| LOOP
    NEXT -->|No| UPDATE[Update Umbrella<br/>Chart.yaml]
    
    UPDATE --> DEPS[Set dependencies[]<br/>with all services]
    
    DEPS --> HELMUPDATE[Run helm dependency<br/>update]
    
    HELMUPDATE --> SUMMARY[Display Summary<br/>Table]
    
    SUMMARY --> COMPLETE([Umbrella Synced])
    
    WARN --> END([End])
    SKIP --> NEXT
    COMPLETE --> END
    
    style START fill:#90EE90
    style COMPLETE fill:#90EE90
    style WARN fill:#FFD700
    style SKIP fill:#FFD700
    style END fill:#FFB6C1
```

---

## Jenkins Pipeline Flow

```mermaid
graph TD
    START([Pipeline Triggered]) --> CHECKOUT[Stage: Checkout<br/>Clone Repository]
    
    CHECKOUT --> SETUP[Stage: Setup Environment<br/>Install Python deps<br/>Setup Helm]
    
    SETUP --> VALIDATE[Stage: Validate Configurations<br/>Check all config.yml files<br/>Validate required fields]
    
    VALIDATE -->|Invalid| FAIL1[Pipeline Failed]
    VALIDATE -->|Valid| GENERATE[Stage: Generate Charts<br/>Run chart-generator<br/>for each service]
    
    GENERATE --> LINT[Stage: Lint Charts<br/>helm lint<br/>all charts]
    
    LINT -->|Errors| FAIL2[Pipeline Failed]
    LINT -->|OK| TEMPLATE[Stage: Template Charts<br/>helm template<br/>render manifests]
    
    TEMPLATE --> K3S_SETUP[Stage: Setup k3s Cluster<br/>Ensure k3s running<br/>Create namespace]
    
    K3S_SETUP --> DEPS[Stage: Install Dependencies<br/>cert-manager<br/>ingress-nginx]
    
    DEPS --> SYNC[Stage: Sync Umbrella Chart<br/>Update dependencies<br/>Generate charts]
    
    SYNC --> DEPLOY[Stage: Deploy to k3s<br/>helm upgrade --install<br/>Wait for ready]
    
    DEPLOY -->|Failed| FAIL3[Pipeline Failed<br/>Rollback]
    DEPLOY -->|Success| VERIFY[Stage: Verify Deployment<br/>Check pods<br/>Check services<br/>Check ingress]
    
    VERIFY -->|Not Ready| FAIL4[Pipeline Failed]
    VERIFY -->|Ready| TEST[Stage: Run Tests<br/>Smoke tests<br/>Health checks<br/>Endpoint checks]
    
    TEST -->|Failed| FAIL5[Pipeline Failed]
    TEST -->|Passed| SUCCESS[Pipeline Success<br/>Archive Artifacts]
    
    FAIL1 --> CLEANUP[Post: Cleanup]
    FAIL2 --> CLEANUP
    FAIL3 --> CLEANUP
    FAIL4 --> CLEANUP
    FAIL5 --> CLEANUP
    SUCCESS --> CLEANUP
    
    CLEANUP --> END([End])
    
    style START fill:#90EE90
    style SUCCESS fill:#90EE90
    style FAIL1 fill:#FFB6C1
    style FAIL2 fill:#FFB6C1
    style FAIL3 fill:#FFB6C1
    style FAIL4 fill:#FFB6C1
    style FAIL5 fill:#FFB6C1
    style END fill:#FFB6C1
```

---

## Deployment Flow

```mermaid
sequenceDiagram
    participant Helm as Helm CLI
    participant Umbrella as Umbrella Chart
    participant Dep1 as Frontend Chart
    participant Dep2 as Backend Chart
    participant Dep3 as Database Chart
    participant Library as Platform Library
    participant k3s as k3s API Server
    participant Pods as Pods/Resources
    
    Helm->>Umbrella: helm upgrade --install platform
    Umbrella->>Umbrella: Load Chart.yaml
    Umbrella->>Umbrella: Resolve dependencies
    
    Umbrella->>Dep1: Load Frontend Chart
    Umbrella->>Dep2: Load Backend Chart
    Umbrella->>Dep3: Load Database Chart
    
    Dep1->>Library: Include platform templates
    Dep2->>Library: Include platform templates
    Dep3->>Library: Include platform templates
    
    Library->>Library: Render templates<br/>with values
    
    Dep1->>k3s: Create Frontend Deployment
    Dep1->>k3s: Create Frontend Service
    Dep1->>k3s: Create Frontend Ingress
    Dep1->>k3s: Create Certificate (if enabled)
    Dep1->>k3s: Create mTLS Policy (if enabled)
    Dep1->>k3s: Create HPA (if enabled)
    
    Dep2->>k3s: Create Backend Deployment
    Dep2->>k3s: Create Backend Service
    Dep2->>k3s: Create Backend Ingress
    Dep2->>k3s: Create Certificate (if enabled)
    Dep2->>k3s: Create mTLS Policy (if enabled)
    Dep2->>k3s: Create HPA (if enabled)
    
    Dep3->>k3s: Create Database Deployment
    Dep3->>k3s: Create Database Service
    
    k3s->>Pods: Schedule Pods
    k3s->>Pods: Create Services
    k3s->>Pods: Create Ingress
    
    Pods->>k3s: Pod Status Updates
    k3s->>Helm: Deployment Status
    
    Helm->>Helm: Wait for Ready
    Helm-->>Helm: Deployment Complete
```

---

## Library Chart Structure

```mermaid
graph TB
    subgraph "Platform Library Chart"
        ROOT[platform-library/<br/>Chart.yaml<br/>type: library]
        
        ROOT --> VALUES[values.yaml<br/>Default Values]
        ROOT --> TEMPLATES[templates/]
        
        TEMPLATES --> HELPERS[_helpers.tpl<br/>Template Functions]
        TEMPLATES --> DEF_DEP[_deployment.yaml<br/>Define platform.deployment]
        TEMPLATES --> DEF_SVC[_service.yaml<br/>Define platform.service]
        TEMPLATES --> DEF_ING[_ingress.yaml<br/>Define platform.ingress]
        TEMPLATES --> DEF_CERT[_certificate.yaml<br/>Define platform.certificate]
        TEMPLATES --> DEF_MTLS[_mtls.yaml<br/>Define platform.mtls]
        TEMPLATES --> DEF_HPA[_hpa.yaml<br/>Define platform.autoscaling]
        TEMPLATES --> DEF_SA[_serviceaccount.yaml<br/>Define platform.serviceAccount]
        
        DEF_DEP --> DEP[deployment.yaml<br/>Include platform.deployment]
        DEF_SVC --> SVC[service.yaml<br/>Include platform.service]
        DEF_ING --> ING[ingress.yaml<br/>Include platform.ingress]
        DEF_CERT --> CERT[certificate.yaml<br/>Include platform.certificate]
        DEF_MTLS --> MTLS[mtls.yaml<br/>Include platform.mtls]
        DEF_HPA --> HPA[hpa.yaml<br/>Include platform.hpa]
        DEF_SA --> SA[serviceaccount.yaml<br/>Include platform.serviceAccount]
    end
    
    subgraph "Generated Service Chart"
        SCHART[service-name/<br/>Chart.yaml<br/>dependency: platform]
        SCHART --> SVALS[values.yaml<br/>Merged Config]
        SCHART --> STEMPLATES[templates/]
        
        STEMPLATES --> SHELPERS[_helpers.tpl<br/>Copied from Library]
        STEMPLATES --> SDEP[deployment.yaml<br/>include platform.deployment]
        STEMPLATES --> SSVC[service.yaml<br/>include platform.service]
        STEMPLATES --> SING[ingress.yaml<br/>include platform.ingress]
        STEMPLATES --> SCERT[certificate.yaml<br/>include platform.certificate]
        STEMPLATES --> SMTLS[mtls.yaml<br/>include platform.mtls]
        STEMPLATES --> SHPA[hpa.yaml<br/>include platform.hpa]
        STEMPLATES --> SSA[serviceaccount.yaml<br/>include platform.serviceAccount]
    end
    
    HELPERS -.->|Used by| SDEP
    DEF_DEP -.->|Called by| SDEP
    DEF_SVC -.->|Called by| SSVC
    DEF_ING -.->|Called by| SING
    DEF_CERT -.->|Called by| SCERT
    DEF_MTLS -.->|Called by| SMTLS
    DEF_HPA -.->|Called by| SHPA
    DEF_SA -.->|Called by| SSA
    
    style ROOT fill:#e1f5ff
    style SCHART fill:#fff4e1
    style HELPERS fill:#ffe1f5
    style SHELPERS fill:#ffe1f5
```

---

## Service Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Created: Developer creates<br/>configuration.yml
    
    Created --> Committed: git commit
    
    Committed --> Pushed: git push
    
    Pushed --> WebhookTriggered: Webhook fires
    
    WebhookTriggered --> PipelineRunning: Jenkins starts
    
    PipelineRunning --> Validating: Validate configs
    
    Validating --> Valid: Config valid
    Validating --> Invalid: Config invalid
    
    Invalid --> [*]: Pipeline fails
    
    Valid --> Generating: Generate charts
    
    Generating --> Generated: Charts created
    
    Generated --> Linting: Lint charts
    
    Linting --> LintPass: Lint OK
    Linting --> LintFail: Lint errors
    
    LintFail --> [*]: Pipeline fails
    
    LintPass --> Syncing: Sync umbrella
    
    Syncing --> Synced: Umbrella updated
    
    Synced --> Deploying: Deploy to k3s
    
    Deploying --> Deployed: Resources created
    
    Deployed --> Verifying: Verify deployment
    
    Verifying --> Verified: All pods ready
    Verifying --> Failed: Pods not ready
    
    Failed --> [*]: Pipeline fails
    
    Verified --> Testing: Run tests
    
    Testing --> TestsPassed: Tests OK
    Testing --> TestsFailed: Tests fail
    
    TestsFailed --> [*]: Pipeline fails
    
    TestsPassed --> Running: Service running
    
    Running --> Updated: Developer updates config
    
    Updated --> Committed
    
    Running --> [*]: Service removed
```

---

## Complete End-to-End Flow

```mermaid
graph TB
    subgraph "Phase 1: Development"
        DEV1[Developer edits<br/>services/my-service/<br/>configuration.yml]
        DEV2[Commit changes]
        DEV3[Push to repository]
    end
    
    subgraph "Phase 2: CI/CD Trigger"
        GH1[GitHub/GitLab<br/>receives push]
        WH1[Webhook triggered]
        JN1[Jenkins pipeline<br/>starts]
    end
    
    subgraph "Phase 3: Validation & Generation"
        VAL1[Validate all<br/>configurations]
        GEN1[Generate charts<br/>for each service]
        LINT1[Lint generated<br/>charts]
        TEMP1[Template charts<br/>render manifests]
    end
    
    subgraph "Phase 4: Cluster Setup"
        K3S1[Ensure k3s<br/>cluster running]
        DEPS1[Install cert-manager<br/>ingress-nginx]
        NS1[Create platform<br/>namespace]
    end
    
    subgraph "Phase 5: Umbrella Sync"
        SYNC1[Scan all service<br/>configurations]
        SYNC2[Generate charts<br/>for each]
        SYNC3[Update umbrella<br/>Chart.yaml]
        SYNC4[Create values-*.yaml<br/>files]
    end
    
    subgraph "Phase 6: Deployment"
        DEP1[helm upgrade<br/>--install platform]
        DEP2[Create Deployments]
        DEP3[Create Services]
        DEP4[Create Ingress]
        DEP5[Create Certificates]
        DEP6[Create mTLS Policies]
        DEP7[Create HPA]
    end
    
    subgraph "Phase 7: Verification"
        VER1[Wait for pods<br/>to be ready]
        VER2[Check service<br/>endpoints]
        VER3[Verify ingress<br/>configuration]
        VER4[Check certificate<br/>status]
    end
    
    subgraph "Phase 8: Testing"
        TEST1[Run smoke tests]
        TEST2[Check pod health]
        TEST3[Verify endpoints]
        TEST4[Test ingress<br/>connectivity]
    end
    
    subgraph "Phase 9: Completion"
        SUCC1[Pipeline success]
        SUCC2[Archive artifacts]
        SUCC3[Notify developer]
    end
    
    DEV1 --> DEV2
    DEV2 --> DEV3
    DEV3 --> GH1
    GH1 --> WH1
    WH1 --> JN1
    
    JN1 --> VAL1
    VAL1 --> GEN1
    GEN1 --> LINT1
    LINT1 --> TEMP1
    
    TEMP1 --> K3S1
    K3S1 --> DEPS1
    DEPS1 --> NS1
    
    NS1 --> SYNC1
    SYNC1 --> SYNC2
    SYNC2 --> SYNC3
    SYNC3 --> SYNC4
    
    SYNC4 --> DEP1
    DEP1 --> DEP2
    DEP2 --> DEP3
    DEP3 --> DEP4
    DEP4 --> DEP5
    DEP5 --> DEP6
    DEP6 --> DEP7
    
    DEP7 --> VER1
    VER1 --> VER2
    VER2 --> VER3
    VER3 --> VER4
    
    VER4 --> TEST1
    TEST1 --> TEST2
    TEST2 --> TEST3
    TEST3 --> TEST4
    
    TEST4 --> SUCC1
    SUCC1 --> SUCC2
    SUCC2 --> SUCC3
    
    style DEV1 fill:#e1f5ff
    style JN1 fill:#ffe1f5
    style GEN1 fill:#fff4e1
    style DEP1 fill:#e1ffe1
    style SUCC1 fill:#90EE90
```

---

## Data Flow Diagram

```mermaid
flowchart LR
    subgraph "Input"
        CFG[configuration.yml<br/>YAML Config]
    end
    
    subgraph "Processing"
        P1[Load & Parse<br/>YAML]
        P2[Merge with<br/>Library Values]
        P3[Copy Library<br/>Templates]
        P4[Generate Chart<br/>Structure]
        P5[Create Template<br/>Files]
    end
    
    subgraph "Output"
        O1[Chart.yaml<br/>Metadata]
        O2[values.yaml<br/>Merged Values]
        O3[templates/<br/>Template Files]
        O4[_helpers.tpl<br/>Helper Functions]
    end
    
    subgraph "Helm Processing"
        H1[helm template<br/>Render]
        H2[helm lint<br/>Validate]
        H3[helm install<br/>Deploy]
    end
    
    subgraph "Kubernetes"
        K1[Deployment]
        K2[Service]
        K3[Ingress]
        K4[Certificate]
        K5[mTLS Policy]
        K6[HPA]
    end
    
    CFG --> P1
    P1 --> P2
    P2 --> P3
    P3 --> P4
    P4 --> P5
    
    P5 --> O1
    P5 --> O2
    P5 --> O3
    P3 --> O4
    
    O1 --> H1
    O2 --> H1
    O3 --> H1
    O4 --> H1
    
    H1 --> H2
    H2 --> H3
    
    H3 --> K1
    H3 --> K2
    H3 --> K3
    H3 --> K4
    H3 --> K5
    H3 --> K6
    
    style CFG fill:#ffcccc
    style P2 fill:#ccffcc
    style O1 fill:#ffffcc
    style H3 fill:#ccccff
    style K1 fill:#ffccff
```

---

## Component Interaction Diagram

```mermaid
graph TB
    subgraph "External"
        DEV[Developer]
        GIT[Git Repository]
    end
    
    subgraph "Jenkins Pod"
        JN[Jenkins Controller]
        AG1[Jenkins Agent<br/>helm container]
        AG2[Jenkins Agent<br/>kubectl container]
        AG3[Jenkins Agent<br/>python container]
    end
    
    subgraph "Chart Tools"
        CG[chart-generator/<br/>main.py]
        US[umbrella-sync/<br/>main.py]
    end
    
    subgraph "Library"
        LC[platform-library/<br/>Templates & Values]
    end
    
    subgraph "Generated"
        SC[Service Charts<br/>generated-charts/]
        UC[Umbrella Chart<br/>umbrella-chart/]
    end
    
    subgraph "k3s Cluster"
        API[k3s API Server]
        ETCD[etcd]
        KUBELET[kubelet]
        PODS[Pods]
    end
    
    DEV -->|Push| GIT
    GIT -->|Webhook| JN
    
    JN -->|Spawn| AG1
    JN -->|Spawn| AG2
    JN -->|Spawn| AG3
    
    AG3 -->|Execute| CG
    AG3 -->|Execute| US
    AG1 -->|Execute| HELM[helm commands]
    AG2 -->|Execute| KUBECTL[kubectl commands]
    
    CG -->|Read| LC
    CG -->|Write| SC
    US -->|Read| SC
    US -->|Write| UC
    
    HELM -->|Install| UC
    HELM -->|Query| API
    
    KUBECTL -->|Apply| API
    KUBECTL -->|Get| API
    
    API -->|Store| ETCD
    API -->|Schedule| KUBELET
    KUBELET -->|Manage| PODS
    
    style DEV fill:#e1f5ff
    style JN fill:#ffe1f5
    style CG fill:#fff4e1
    style LC fill:#e1ffe1
    style API fill:#ffe1f5
```

---

## Error Handling Flow

```mermaid
flowchart TD
    START([Pipeline Start]) --> VALIDATE{Validate<br/>Config}
    
    VALIDATE -->|Invalid YAML| ERR1[Error: Invalid YAML<br/>Stop Pipeline<br/>Report to Developer]
    VALIDATE -->|Missing Fields| ERR2[Error: Missing Fields<br/>Stop Pipeline<br/>Report Missing Fields]
    VALIDATE -->|Valid| GENERATE
    
    GENERATE{Generate<br/>Charts} -->|Template Error| ERR3[Error: Template Error<br/>Stop Pipeline<br/>Show Template Error]
    GENERATE -->|Success| LINT
    
    LINT{Lint<br/>Charts} -->|Lint Errors| ERR4[Error: Lint Failed<br/>Stop Pipeline<br/>Show Lint Errors]
    LINT -->|Success| DEPLOY
    
    DEPLOY{Deploy to<br/>k3s} -->|Helm Error| ERR5[Error: Helm Failed<br/>Rollback<br/>Show Helm Error]
    DEPLOY -->|Timeout| ERR6[Error: Timeout<br/>Rollback<br/>Show Timeout]
    DEPLOY -->|Success| VERIFY
    
    VERIFY{Verify<br/>Deployment} -->|Pods Not Ready| ERR7[Error: Pods Not Ready<br/>Show Pod Status<br/>Show Pod Logs]
    VERIFY -->|Success| TEST
    
    TEST{Run<br/>Tests} -->|Tests Failed| ERR8[Error: Tests Failed<br/>Show Test Results<br/>Keep Deployment]
    TEST -->|Success| SUCCESS
    
    ERR1 --> CLEANUP[Cleanup<br/>Archive Logs]
    ERR2 --> CLEANUP
    ERR3 --> CLEANUP
    ERR4 --> CLEANUP
    ERR5 --> CLEANUP
    ERR6 --> CLEANUP
    ERR7 --> CLEANUP
    ERR8 --> CLEANUP
    SUCCESS --> CLEANUP
    
    CLEANUP --> NOTIFY[Notify Developer<br/>Email/Slack]
    NOTIFY --> END([End])
    
    style START fill:#90EE90
    style SUCCESS fill:#90EE90
    style ERR1 fill:#FFB6C1
    style ERR2 fill:#FFB6C1
    style ERR3 fill:#FFB6C1
    style ERR4 fill:#FFB6C1
    style ERR5 fill:#FFB6C1
    style ERR6 fill:#FFB6C1
    style ERR7 fill:#FFB6C1
    style ERR8 fill:#FFB6C1
    style END fill:#FFB6C1
```

---

## Resource Creation Flow

```mermaid
graph TD
    HELM[Helm Install] --> DEPLOY[Deployment]
    HELM --> SVC[Service]
    HELM --> ING[Ingress]
    HELM --> CERT[Certificate]
    HELM --> MTLS[PeerAuthentication]
    HELM --> AUTHZ[AuthorizationPolicy]
    HELM --> HPA[HorizontalPodAutoscaler]
    HELM --> SA[ServiceAccount]
    
    DEPLOY --> POD1[Pod 1]
    DEPLOY --> POD2[Pod 2]
    DEPLOY --> POD3[Pod N...]
    
    POD1 --> CONTAINER1[Container<br/>App Image]
    POD2 --> CONTAINER2[Container<br/>App Image]
    
    SVC --> ENDPOINTS1[Endpoints<br/>Pod IPs]
    ENDPOINTS1 --> POD1
    ENDPOINTS1 --> POD2
    
    ING --> INGCTRL[Ingress Controller]
    INGCTRL --> SVC
    
    CERT --> CERTMGR[Cert Manager]
    CERTMGR --> SECRET1[TLS Secret]
    SECRET1 --> ING
    
    MTLS --> ISTIO[Istio Control Plane]
    AUTHZ --> ISTIO
    ISTIO --> POD1
    ISTIO --> POD2
    
    HPA --> METRICS[Metrics Server]
    METRICS --> POD1
    METRICS --> POD2
    HPA --> DEPLOY
    
    SA --> POD1
    SA --> POD2
    
    style HELM fill:#e1f5ff
    style DEPLOY fill:#fff4e1
    style POD1 fill:#e1ffe1
    style POD2 fill:#e1ffe1
    style SVC fill:#ffe1f5
    style ING fill:#ffe1f5
```

---

These diagrams provide a comprehensive view of how the Helm Chart Factory system works, covering all workflows, components, and interactions. Each diagram focuses on a specific aspect of the system to provide detailed understanding.

