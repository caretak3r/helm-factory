# Multi-Repository Setup Guide

This guide explains how to set up the multi-repository structure for the Helm Chart Factory system.

## Repository Overview

The system uses 5+ GitHub repositories:

1. **common-library** - Platform team's library chart (renamed from platform-library)
2. **frontend-service** - Frontend service code and config
3. **backend-service** - Backend service code and config
4. **database-service** - Database service code and config
5. **umbrella-chart** - Umbrella chart with all services (contains chart generation tools)
6. **helm-chart-factory** (this repo) - Source code, templates, and documentation

## Step-by-Step Setup

### 1. Create GitHub Repositories

```bash
# Common library (renamed from platform-library)
gh repo create companyinfo/common-library --public --description "Common library Helm chart"

# Service repositories
gh repo create companyinfo/frontend-service --public --description "Frontend service"
gh repo create companyinfo/backend-service --public --description "Backend service"
gh repo create companyinfo/database-service --public --description "Database service"

# Umbrella chart
gh repo create companyinfo/umbrella-chart --public --description "Umbrella Helm chart"
```

### 2. Setup Common Library Repository

```bash
git clone https://github.com/companyinfo/common-library.git
cd common-library

# Copy common-library directory contents from this repo
# If factory/common-library/ exists:
cp -r ../factory/common-library/* .

# Or create from templates if needed
# (See factory/common-library/ for structure)

git add .
git commit -m "Initial common library chart"
git push origin main
```

**Files to copy:**
- `factory/common-library/Chart.yaml` → `common-library/Chart.yaml`
- `factory/common-library/values.yaml` → `common-library/values.yaml`
- `factory/common-library/templates/` → `common-library/templates/`

### 3. Setup Service Repositories

#### Frontend Service

```bash
git clone https://github.com/companyinfo/frontend-service.git
cd frontend-service

# Copy service files
cp ../factory/services/frontend/configuration.yml .
cp ../factory/services/frontend/Dockerfile .
cp ../factory/services/frontend/nginx.conf .
cp ../factory/services/frontend/package.json .
cp -r ../factory/services/frontend/public .
cp -r ../factory/services/frontend/src .

# Copy Jenkinsfile (use the new version)
cp ../factory/Jenkinsfile.service.new ./Jenkinsfile

# Copy .gitignore, .dockerignore
cp ../factory/services/frontend/.gitignore .
cp ../factory/services/frontend/.dockerignore .

git add .
git commit -m "Initial frontend service"
git push origin main
```

**Files to copy:**
- `factory/services/frontend/configuration.yml` → `frontend-service/configuration.yml`
- `factory/services/frontend/Dockerfile` → `frontend-service/Dockerfile`
- `factory/services/frontend/nginx.conf` → `frontend-service/nginx.conf`
- `factory/services/frontend/package.json` → `frontend-service/package.json`
- `factory/services/frontend/public/` → `frontend-service/public/`
- `factory/services/frontend/src/` → `frontend-service/src/`
- `factory/Jenkinsfile.service.new` → `frontend-service/Jenkinsfile`
- `factory/services/frontend/.gitignore` → `frontend-service/.gitignore`
- `factory/services/frontend/.dockerignore` → `frontend-service/.dockerignore`

#### Backend Service

```bash
git clone https://github.com/companyinfo/backend-service.git
cd backend-service

cp ../factory/services/backend/configuration.yml .
cp ../factory/services/backend/Dockerfile .
cp ../factory/services/backend/main.py .
cp ../factory/services/backend/requirements.txt .
cp ../factory/Jenkinsfile.service.new ./Jenkinsfile
cp ../factory/services/backend/.dockerignore .

git add .
git commit -m "Initial backend service"
git push origin main
```

**Files to copy:**
- `factory/services/backend/configuration.yml` → `backend-service/configuration.yml`
- `factory/services/backend/Dockerfile` → `backend-service/Dockerfile`
- `factory/services/backend/main.py` → `backend-service/main.py`
- `factory/services/backend/requirements.txt` → `backend-service/requirements.txt`
- `factory/Jenkinsfile.service.new` → `backend-service/Jenkinsfile`
- `factory/services/backend/.dockerignore` → `backend-service/.dockerignore`

#### Database Service

```bash
git clone https://github.com/companyinfo/database-service.git
cd database-service

cp ../factory/services/database/configuration.yml .
cp ../factory/services/database/Dockerfile .
cp ../factory/services/database/init.sql .
cp ../factory/Jenkinsfile.service.new ./Jenkinsfile

git add .
git commit -m "Initial database service"
git push origin main
```

**Files to copy:**
- `factory/services/database/configuration.yml` → `database-service/configuration.yml`
- `factory/services/database/Dockerfile` → `database-service/Dockerfile`
- `factory/services/database/init.sql` → `database-service/init.sql`
- `factory/Jenkinsfile.service.new` → `database-service/Jenkinsfile`

### 4. Setup Umbrella Chart Repository

```bash
git clone https://github.com/companyinfo/umbrella-chart.git
cd umbrella-chart

# Copy chart generator to src/
mkdir -p src
cp -r ../factory/chart-generator src/

# Copy Jenkinsfile (use the new version)
cp ../factory/Jenkinsfile.umbrella.new ./Jenkinsfile

# Create services directory structure
mkdir -p services/frontend
mkdir -p services/backend
mkdir -p services/database

# Copy service configurations (initial state)
cp ../factory/services/frontend/configuration.yml services/frontend/
cp ../factory/services/backend/configuration.yml services/backend/
cp ../factory/services/database/configuration.yml services/database/

# Create Chart.yaml with common-library dependency
cat > Chart.yaml <<EOF
apiVersion: v2
name: umbrella
description: Umbrella chart for all services
type: application
version: 0.1.0

dependencies:
  - name: common-library
    version: 1.0.0
    repository: file://../common-library
    condition: common-library.enabled
EOF

# Create values.yaml
cat > values.yaml <<EOF
global:
  namespace: default

common-library:
  enabled: true
EOF

# Create .gitignore
cat > .gitignore <<EOF
charts/
*.tgz
Chart.lock
values-*.yaml
EOF

git add .
git commit -m "Initial umbrella chart"
git push origin main
```

**Files to copy:**
- `factory/chart-generator/` → `umbrella-chart/src/chart-generator/`
- `factory/Jenkinsfile.umbrella.new` → `umbrella-chart/Jenkinsfile`
- `factory/services/*/configuration.yml` → `umbrella-chart/services/*/configuration.yml` (initial state)

**Files to create:**
- `umbrella-chart/Chart.yaml` (with common-library dependency)
- `umbrella-chart/values.yaml`
- `umbrella-chart/.gitignore`

### 5. Configure Jenkins

#### Install Required Plugins

- GitHub plugin
- Pipeline plugin
- Git plugin
- Credentials Binding plugin
- AWS Credentials plugin (for ECR)

#### Configure GitHub Credentials

1. **Manage Jenkins** → **Credentials** → **System** → **Global credentials**
2. **Add Credentials**:
   - **Kind**: Username with password
   - **Scope**: Global
   - **Username**: Your GitHub username
   - **Password**: GitHub personal access token (with repo permissions)
   - **ID**: `github-credentials`
   - **Description**: GitHub credentials for repos

#### Configure AWS Credentials (for ECR)

1. **Manage Jenkins** → **Credentials** → **System** → **Global credentials**
2. **Add Credentials**:
   - **Kind**: AWS Credentials
   - **Scope**: Global
   - **Access Key ID**: Your AWS access key
   - **Secret Access Key**: Your AWS secret key
   - **ID**: `aws-credentials`
   - **Description**: AWS credentials for ECR

#### Create Service Pipeline Jobs

For each service (frontend, backend, database):

1. **New Item** → Enter name: `frontend-service`
2. Select **Pipeline** → **OK**
3. Configure:
   - **Pipeline definition**: Pipeline script from SCM
   - **SCM**: Git
   - **Repository URL**: `https://github.com/companyinfo/frontend-service.git`
   - **Credentials**: Select `github-credentials`
   - **Branch**: `*/main`
   - **Script Path**: `Jenkinsfile`
   - **Lightweight checkout**: Unchecked
4. **Save**

Repeat for `backend-service` and `database-service`.

#### Create Umbrella Pipeline Job

1. **New Item** → Enter name: `umbrella-chart`
2. Select **Pipeline** → **OK**
3. Configure:
   - **Pipeline definition**: Pipeline script from SCM
   - **SCM**: Git
   - **Repository URL**: `https://github.com/companyinfo/umbrella-chart.git`
   - **Credentials**: Select `github-credentials`
   - **Branch**: `*/main`
   - **Script Path**: `Jenkinsfile`
4. **Save**

### 6. Configure GitHub Webhooks

#### Service Repository Webhooks

For each service repository (frontend-service, backend-service, database-service):

1. Go to repository → **Settings** → **Webhooks** → **Add webhook**
2. Configure:
   - **Payload URL**: `http://your-jenkins-url:30080/github-webhook/`
   - **Content type**: `application/json`
   - **Secret**: (optional) Add webhook secret
   - **Events**: 
     - ✅ Push events (triggers on merge to main)
     - ❌ Pull request events (not needed, only trigger on merge)
   - **Active**: ✅
   - **Branch filter**: `main`, `master` (only trigger on main branch)
3. **Add webhook**

#### Umbrella Chart Webhook

1. Go to `umbrella-chart` repository → **Settings** → **Webhooks** → **Add webhook**
2. Configure:
   - **Payload URL**: `http://your-jenkins-url:30080/github-webhook/`
   - **Content type**: `application/json`
   - **Events**: 
     - ✅ Push events (triggers on PR creation and merge to main)
     - ✅ Pull request events (triggers on PR creation/update)
   - **Active**: ✅
   - **Branch filter**: All branches (for PRs and main)
3. **Add webhook**

### 7. Environment Variables

Set these in Jenkins → Manage Jenkins → Configure System → Global properties:

- `UMBRELLA_CHART_REPO`: `https://github.com/companyinfo/umbrella-chart.git`
- `HELM_CHART_FACTORY_REPO`: `https://github.com/companyinfo/helm-chart-factory.git`
- `ECR_QA_REGISTRY`: `123456789012.dkr.ecr.us-east-1.amazonaws.com`
- `ECR_PROD_REGISTRY`: `123456789012.dkr.ecr.us-east-1.amazonaws.com`
- `COMMON_LIBRARY_REPO`: `https://github.com/companyinfo/common-library.git`

## Testing the Setup

### Test Service Pipeline

1. Edit `configuration.yml` in `frontend-service` repo
2. Commit and push to main
3. Check Jenkins for triggered build
4. Verify:
   - Image built and pushed to QA ECR
   - Chart generated
   - Chart validated
   - Chart pushed to QA ECR
   - PR created to umbrella-chart repo

### Test Umbrella Pipeline

1. Merge PR in `umbrella-chart` repo
2. Verify:
   - All service configs synced
   - Charts generated from `services/` directory
   - Dependencies updated
   - Charts linted and templated
   - Deployment to Kubernetes succeeds (if enabled)

## Troubleshooting

### Webhook Not Triggering

- Check webhook delivery logs in GitHub
- Verify Jenkins URL is accessible
- Check Jenkins GitHub plugin configuration
- Verify webhook secret matches (if configured)

### Pipeline Can't Access Repos

- Verify GitHub credentials are configured
- Check token has correct permissions
- Verify repository URLs are correct

### Chart Generation Fails

- Verify common-library repo is accessible
- Check Python dependencies are installed in `src/chart-generator/`
- Verify configuration.yml syntax
- Check that `src/chart-generator/` exists in umbrella-chart repo

### ECR Push Fails

- Verify AWS credentials are configured
- Check ECR repository exists
- Verify IAM permissions for ECR push/pull
- Check ECR registry URLs are correct

### Umbrella Chart Update Fails

- Check GitHub credentials for pushing
- Verify branch permissions
- Check if PR branch already exists

## Security Considerations

1. **GitHub Tokens**: Use fine-grained tokens with minimal permissions
2. **AWS Credentials**: Use IAM roles with minimal ECR permissions
3. **Webhook Secrets**: Configure webhook secrets for security
4. **Jenkins Credentials**: Store securely, rotate regularly
5. **Repository Access**: Use teams/organizations for access control
6. **Branch Protection**: Enable branch protection on main branches
7. **PR Reviews**: Require reviews for umbrella chart changes
8. **Production Approvals**: Use `withApprovals` parameter for production deployments
