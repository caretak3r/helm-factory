# Pull Request Workflow

This document describes the pull request-based workflow for updating service configurations and the umbrella chart.

## Workflow Overview

```
Developer edits configuration.yml in service repo
         │
         ▼
    Create PR in service repo
         │
         ▼
    PR Merged to main
         │
         ▼
┌────────────────────────┐
│  Jenkins Pipeline       │
│  (Service-specific)     │
├────────────────────────┤
│  1. Build image         │
│  2. Generate chart       │
│  3. Create PR to        │
│     umbrella-chart repo │
└────────────────────────┘
         │
         ▼
    PR Created in umbrella-chart repo
         │
         ▼
┌────────────────────────┐
│  Jenkins Pipeline       │
│  (Umbrella)             │
├────────────────────────┤
│  1. Validate PR         │
│  2. Lint charts          │
│  3. Template charts      │
│  4. (On merge) Deploy   │
└────────────────────────┘
         │
         ▼
    PR Merged to main
         │
         ▼
    Deploy to k3s
```

## Service Repository Workflow

### 1. Developer Makes Changes

Developer edits `configuration.yml` in their service repository:

```bash
cd frontend-service
# Edit configuration.yml
git checkout -b update-config
git add configuration.yml
git commit -m "Update frontend configuration"
git push origin update-config
```

### 2. Create PR in Service Repository

Developer creates a PR in the service repository (e.g., `frontend-service`).

### 3. PR Merged to Main

When the PR is merged to `main`:
- GitHub webhook triggers Jenkins pipeline
- Pipeline runs on `main` branch

### 4. Service Pipeline Actions

The service pipeline (`Jenkinsfile.service`) performs:

1. **Checkout Service Repository** - Gets the latest code
2. **Checkout Platform Library** - Gets platform templates
3. **Checkout Tools** - Gets chart-generator and umbrella-sync tools
4. **Build Image** - Builds Docker image for the service
5. **Generate Chart** - Generates Helm chart using platform library
6. **Lint Chart** - Validates the generated chart
7. **Update Umbrella Chart** - Updates umbrella chart repository
8. **Create PR** - Creates a pull request to umbrella-chart repository

### 5. PR Created in Umbrella Chart Repository

The service pipeline creates a PR in the umbrella-chart repository with:
- Updated `services/<service-name>/configuration.yml`
- Updated `Chart.yaml` dependencies
- Updated `values-*.yaml` files
- Generated charts (if not gitignored)

## Umbrella Chart Repository Workflow

### 1. PR Created

When a PR is created in the umbrella-chart repository:
- GitHub webhook triggers Jenkins pipeline
- Pipeline runs on the PR branch

### 2. PR Pipeline Actions

The umbrella pipeline (`Jenkinsfile.umbrella`) performs:

1. **Checkout Umbrella Chart** - Gets PR branch
2. **Checkout Platform Library** - Gets platform templates
3. **Checkout Tools** - Gets umbrella-sync tool
4. **Sync Umbrella Chart** - Syncs all service configurations
5. **Lint Charts** - Validates all charts
6. **Template Charts** - Renders templates to check for errors
7. **Validate PR Changes** - Runs validation checks (PR only, not on main)

### 3. PR Merged to Main

When the PR is merged to `main`:
- GitHub webhook triggers Jenkins pipeline
- Pipeline runs on `main` branch

### 4. Main Branch Pipeline Actions

The umbrella pipeline performs all PR validation steps plus:

1. **Deploy to k3s** - Deploys the umbrella chart to k3s cluster
2. **Verify Deployment** - Verifies all resources are running
3. **Run Tests** - Runs integration tests

## Jenkins Configuration

### Service Repository Pipeline

**Trigger Configuration:**
- **GitHub Push**: Enabled
- **Branches**: `main`, `master`
- **Path Filter**: `configuration.yml`

**Pipeline Behavior:**
- Runs on PRs: **No** (only on merge to main)
- Runs on main branch: **Yes**
- Creates PR to umbrella: **Yes**

### Umbrella Chart Pipeline

**Trigger Configuration:**
- **GitHub Push**: Enabled
- **Branches**: `main`, `master`, PR branches
- **Path Filter**: `Chart.yaml`, `services/**/configuration.yml`

**Pipeline Behavior:**
- Runs on PRs: **Yes** (validation only)
- Runs on main branch: **Yes** (full deployment)
- Deploys to k3s: **Only on main branch**

## PR Creation Details

### Service Pipeline PR Creation

The service pipeline creates a PR using the GitHub API with:

**PR Title:**
```
Update <service-name> configuration
```

**PR Body:**
```markdown
This PR updates the <service-name> service configuration.

**Source:** <Jenkins build URL>
**Service Repository:** <service repo URL>
**Branch:** update-<service-name>-<build-number>
**Build Number:** <build number>

Changes:
- Updated `services/<service-name>/configuration.yml`
- Regenerated Helm chart dependencies

Please review and merge when ready.
```

**PR Branch:**
```
update-<service-name>-<build-number>
```

**Base Branch:**
```
main
```

### PR Validation

When a PR is created in the umbrella-chart repository, the pipeline:

1. Validates chart syntax (`helm lint`)
2. Renders templates (`helm template --dry-run`)
3. Checks for errors
4. Does NOT deploy to k3s (deployment only happens on merge)

## Example Workflow

### Step 1: Developer Updates Frontend Configuration

```bash
cd frontend-service
git checkout -b update-frontend-config
# Edit configuration.yml
git add configuration.yml
git commit -m "Add autoscaling to frontend"
git push origin update-frontend-config
```

### Step 2: Create PR in Frontend Service Repo

Developer creates PR: `frontend-service#123`

### Step 3: PR Merged

PR merged to `main` branch in `frontend-service` repository.

### Step 4: Service Pipeline Runs

Jenkins pipeline `frontend-service` runs:
- Builds Docker image
- Generates Helm chart
- Creates PR `umbrella-chart#45` with title "Update frontend configuration"

### Step 5: Umbrella Chart PR Created

PR `umbrella-chart#45` is created with:
- Updated `services/frontend/configuration.yml`
- Updated `Chart.yaml` dependencies
- Updated `values-frontend.yaml`

### Step 6: Umbrella Pipeline Validates PR

Jenkins pipeline `umbrella-chart` runs on PR branch:
- Validates charts
- Lints templates
- Does NOT deploy (validation only)

### Step 7: PR Merged

PR `umbrella-chart#45` is merged to `main`.

### Step 8: Umbrella Pipeline Deploys

Jenkins pipeline `umbrella-chart` runs on `main` branch:
- Validates charts
- Deploys to k3s
- Verifies deployment
- Runs tests

## GitHub Webhook Configuration

### Service Repository Webhooks

**URL:** `http://jenkins-url:30080/github-webhook/`

**Events:**
- ✅ Push events
- ✅ Pull request events (optional, for PR validation)

**Path Filter:** `configuration.yml`

**Branches:** `main`, `master`

### Umbrella Chart Repository Webhooks

**URL:** `http://jenkins-url:30080/github-webhook/`

**Events:**
- ✅ Push events
- ✅ Pull request events

**Path Filter:** `Chart.yaml`, `services/**/configuration.yml`

**Branches:** All branches (for PRs and main)

## GitHub Credentials

Jenkins needs GitHub credentials with:

**Required Permissions:**
- `repo` - Full control of private repositories
  - `repo:status` - Access commit status
  - `repo_deployment` - Access deployment status
  - `public_repo` - Access public repositories
  - `repo:invite` - Access repository invitations
  - `security_events` - Access security events

**Token Setup:**
1. GitHub → Settings → Developer settings → Personal access tokens
2. Generate new token with `repo` scope
3. Add to Jenkins as `github-credentials`

## Branch Protection

### Service Repositories

**Recommended Settings:**
- Require PR reviews before merging
- Require status checks to pass
- Require up-to-date branches
- Do not allow force pushes

### Umbrella Chart Repository

**Recommended Settings:**
- Require PR reviews before merging
- Require status checks to pass (Jenkins pipeline)
- Require up-to-date branches
- Require linear history
- Do not allow force pushes

## Troubleshooting

### PR Not Created

**Check:**
- GitHub credentials are valid
- Token has `repo` permissions
- Branch name doesn't conflict with existing PR
- GitHub API rate limits

**Debug:**
```bash
# Check PR creation response
curl -H "Authorization: token <token>" \
  https://api.github.com/repos/companyinfo/umbrella-chart/pulls
```

### Pipeline Not Triggering

**Check:**
- Webhook is configured correctly
- Webhook secret matches (if configured)
- Jenkins GitHub plugin is installed
- Branch name matches trigger configuration

### PR Validation Fails

**Check:**
- Chart syntax is valid
- Templates render correctly
- Dependencies are correct
- Values files are valid YAML

## Best Practices

1. **Always use PRs** - Never push directly to main
2. **Review PRs** - Have at least one reviewer approve
3. **Test before merge** - Ensure PR validation passes
4. **Use descriptive PR titles** - Include service name and change type
5. **Link related PRs** - Reference service PR in umbrella PR
6. **Monitor deployments** - Check deployment status after merge
7. **Rollback plan** - Know how to revert if deployment fails

