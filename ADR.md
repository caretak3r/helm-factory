# Architecture Decision Records (ADR)

This document contains Architecture Decision Records (ADRs) for the Helm Chart Factory project.

## ADR-001: Library Chart Pattern

**Status**: Accepted  
**Date**: 2024-11-14  
**Deciders**: Platform Team

### Context

Service teams need to deploy applications to Kubernetes using Helm charts, but maintaining individual Helm charts with platform best practices is time-consuming and error-prone. Each service team would need to:
- Learn Helm templating
- Implement security best practices
- Configure resource limits, health probes, and security contexts
- Maintain consistency across services

### Decision

We will use a Helm library chart pattern where:
- Platform team maintains a reusable library chart (`platform-library`) with best practices
- Service teams provide a simple `configuration.yml` file (similar to `values.yaml`)
- A chart generator tool merges the service configuration with the library chart to create a complete Helm chart
- Generated charts reference the library chart as a dependency

### Consequences

**Positive:**
- Service teams only need to provide configuration, not Helm templates
- Platform best practices are enforced automatically
- Changes to best practices propagate to all services via library chart updates
- Reduced cognitive load for service teams

**Negative:**
- Service teams have less flexibility to customize templates
- Library chart changes affect all services (mitigated by versioning)
- Additional tooling required for chart generation

---

## ADR-002: Multi-Repository Architecture

**Status**: Accepted  
**Date**: 2024-11-14  
**Deciders**: Platform Team

### Context

We need to organize code across multiple repositories:
- Platform library chart
- Individual service repositories
- Umbrella chart repository
- Chart generation tools

### Decision

We will use a multi-repository architecture:
- `platform-library`: Library chart repository
- `{service-name}-service`: Individual service repositories (one per service)
- `umbrella-chart`: Umbrella chart repository managing all services
- `helm-chart-factory`: Tools repository containing chart-generator and umbrella-sync

### Consequences

**Positive:**
- Clear separation of concerns
- Independent versioning and release cycles
- Service teams own their repositories
- Platform team owns library and tools

**Negative:**
- More repositories to manage
- Requires coordination across repositories
- CI/CD setup more complex

---

## ADR-003: Configuration-Driven Chart Generation

**Status**: Accepted  
**Date**: 2024-11-14  
**Deciders**: Platform Team

### Context

Service teams need a simple way to configure their Helm charts without writing templates.

### Decision

Service teams will provide a `configuration.yml` file that:
- Acts like `values.yaml` but with service-specific structure
- Gets merged with library chart defaults
- Is used by chart-generator to create complete Helm charts
- Supports features like `ingress: enable`, `mtls: enable`, `certificate: enable`

### Consequences

**Positive:**
- Simple YAML configuration for service teams
- No Helm template knowledge required
- Configuration validation possible
- Easy to understand and modify

**Negative:**
- Less flexible than writing custom templates
- Configuration format must be documented
- Changes to configuration format require updates across services

---

## ADR-004: Pull Request-Based Workflow

**Status**: Accepted  
**Date**: 2024-11-14  
**Deciders**: Platform Team

### Context

When service configurations change, the umbrella chart needs to be updated. We need a workflow that:
- Triggers on service configuration changes
- Updates umbrella chart dependencies
- Allows for review and approval

### Decision

We will use a Pull Request-based workflow:
- Service pipeline triggers on PRs and merges to main
- When `configuration.yml` changes and merges to main, service pipeline creates a PR to umbrella chart repository
- Umbrella chart pipeline validates PR changes (lint, template)
- On merge to main, umbrella chart pipeline deploys to k3s

### Consequences

**Positive:**
- Changes are reviewed before deployment
- Clear audit trail
- Can validate changes before merging
- Follows GitOps best practices

**Negative:**
- Additional PR step adds latency
- Requires GitHub API access
- More complex CI/CD setup

---

## ADR-005: Multiple Workload Types Support

**Status**: Accepted  
**Date**: 2024-11-14  
**Deciders**: Platform Team

### Context

Different services may need different Kubernetes workload types:
- Stateless services: Deployment
- Stateful services: StatefulSet
- Node-level services: DaemonSet

### Decision

We will support multiple workload types in the library chart:
- Developers specify `workload.type` in `configuration.yml` (default: `Deployment`)
- Library chart includes templates for Deployment, StatefulSet, and DaemonSet
- Chart generator creates appropriate templates based on workload type
- HPA only supported for Deployment and StatefulSet

### Consequences

**Positive:**
- Supports diverse service requirements
- Single library chart handles all workload types
- Consistent configuration across workload types

**Negative:**
- More complex library chart templates
- Need to maintain multiple workload templates
- Some features (like HPA) don't apply to all workload types

---

## ADR-006: Stage Toggles for Jenkins Pipelines

**Status**: Accepted  
**Date**: 2024-11-14  
**Deciders**: Platform Team

### Context

Jenkins pipelines need flexibility to enable/disable stages for different use cases:
- POC: Skip deployment and verification stages
- Testing: Enable all stages
- Production: Enable all stages with additional checks

### Decision

We will use Jenkins pipeline parameters (boolean parameters) to toggle stages:
- Each stage has a corresponding `ENABLE_*` parameter
- Parameters have sensible defaults (deployment/verification disabled for POC)
- Parameters are visible in Jenkins UI for easy toggling
- Stages use `when { expression { params.ENABLE_* } }` conditions

### Consequences

**Positive:**
- Easy to configure pipeline behavior without code changes
- Clear visibility of enabled/disabled stages in Jenkins UI
- Supports different use cases (POC, testing, production)
- No need to modify Jenkinsfile for different environments

**Negative:**
- More parameters to manage
- Need to document parameter usage
- Parameters must be set correctly for each use case

---

## ADR-007: Umbrella Chart Orchestration

**Status**: Accepted  
**Date**: 2024-11-14  
**Deciders**: Platform Team

### Context

Multiple services need to be deployed together. We need a way to:
- Manage dependencies between services
- Deploy all services atomically
- Update service configurations centrally

### Decision

We will use an umbrella chart that:
- Contains dependencies for all service charts
- Stores service configurations in `services/{service-name}/configuration.yml`
- Uses `umbrella-sync` tool to update dependencies automatically
- Deploys all services together

### Consequences

**Positive:**
- Single deployment point for all services
- Centralized configuration management
- Atomic updates across services
- Easier dependency management

**Negative:**
- All services deployed together (no independent deployments)
- Umbrella chart becomes single point of failure
- More complex dependency resolution

---

## ADR-008: Local Development with k3s

**Status**: Accepted  
**Date**: 2024-11-14  
**Deciders**: Platform Team

### Context

We need a local development environment to test the entire system without cloud infrastructure.

### Decision

We will use k3s for local development:
- Lightweight Kubernetes distribution
- Runs on single machine
- Includes local Docker registry
- Uses cert-manager with self-signed certificates
- Jenkins pipelines can deploy to k3s cluster

### Consequences

**Positive:**
- Fast local development cycle
- No cloud costs for testing
- Easy to reset and start fresh
- Tests entire deployment flow

**Negative:**
- k3s may behave differently than production Kubernetes
- Local registry requires setup
- Self-signed certificates need browser acceptance
- Limited scalability testing

---

## ADR-009: Centralized Chart Generation in Umbrella Repository

**Status**: Accepted  
**Date**: 2024-11-14  
**Deciders**: Platform Team

### Context

The original architecture had chart generation happening in service repositories. This led to:
- Duplication of chart generation logic across services
- Service repositories containing chart generation tools
- More complex service pipelines
- Difficulty maintaining consistency

### Decision

We will move all chart generation to the umbrella-chart repository:
- Service repositories only contain `configuration.yml` and application code
- Service pipelines create PRs to umbrella chart with configuration changes
- Umbrella chart pipeline generates all service charts centrally
- Chart generator tools live in umbrella repository or are cloned during pipeline
- Common-library is a static dependency in umbrella Chart.yaml

### Consequences

**Positive:**
- Single source of truth for chart generation
- Simplified service repositories
- Easier to maintain chart generation logic
- Consistent chart generation across all services
- Centralized visibility of all service configurations
- Easier dependency management

**Negative:**
- Service teams lose ability to generate charts locally (can be mitigated with local tools)
- Umbrella repository becomes more critical
- All chart generation happens in one place (single point of failure, mitigated by PR workflow)

### Implementation Details

- Service repositories: Only `configuration.yml`, Dockerfile, application code, and `Jenkinsfile.service`
- Umbrella repository: Contains `services/` directory with all service configs, `charts/` directory with generated charts, `Jenkinsfile.umbrella` for chart generation
- Common-library: Static dependency, not dynamically fetched
- Chart generator: Cloned or included in umbrella repository tools directory

---

## ADR-010: Jenkins Pipeline Parameters for Stage Control

**Status**: Accepted  
**Date**: 2024-11-14  
**Deciders**: Platform Team

### Context

Previously, stage toggles were implemented as environment variables with string comparisons (`env.ENABLE_STAGE == 'true'`). This approach:
- Required string comparisons in `when` conditions
- Was less intuitive in Jenkins UI
- Didn't provide clear boolean semantics

### Decision

We will use Jenkins pipeline parameters (boolean parameters) for stage toggles:
- Each stage has a corresponding `ENABLE_*` boolean parameter
- Parameters are defined in `parameters {}` block
- Stages use `when { expression { params.ENABLE_* } }` conditions
- Parameters have sensible defaults (deployment/verification disabled for POC)
- Parameters are visible and toggleable in Jenkins UI

### Consequences

**Positive:**
- Native boolean semantics (no string comparison needed)
- Clear UI in Jenkins for toggling stages
- Better type safety
- Easier to understand and use
- Parameters persist across builds (can be configured per job)

**Negative:**
- Requires Jenkins job to be configured with parameters (first build)
- Parameters must be set correctly for each use case
- More parameters to document

### Implementation

**Service Pipeline Parameters:**
- `ENABLE_CHECKOUT` (default: true)
- `ENABLE_INSTALL_TOOLS` (default: true)
- `ENABLE_VALIDATE_CONFIG` (default: true)
- `ENABLE_BUILD_IMAGE` (default: true)
- `ENABLE_CREATE_PR` (default: true)

**Umbrella Pipeline Parameters:**
- `ENABLE_CHECKOUT` (default: true)
- `ENABLE_INSTALL_TOOLS` (default: true)
- `ENABLE_GENERATE_CHARTS` (default: true)
- `ENABLE_UPDATE_DEPENDENCIES` (default: true)
- `ENABLE_LINT_CHARTS` (default: true)
- `ENABLE_TEMPLATE_CHARTS` (default: true)
- `ENABLE_DEPLOY` (default: false)
- `ENABLE_VERIFY_DEPLOYMENT` (default: false)
