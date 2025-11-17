# Multi-Repository Setup Guide

This guide explains how to set up the multi-repository structure for the Helm Chart Factory system.

## Repository Overview

The system uses 5+ GitHub repositories:

1. **platform-library** - Platform team's library chart
2. **frontend-service** - Frontend service code and config
3. **backend-service** - Backend service code and config
4. **database-service** - Database service code and config
5. **umbrella-chart** - Umbrella chart with all services
6. **helm-chart-factory** (this repo) - Tools and documentation

## Step-by-Step Setup

### 1. Create GitHub Repositories

```bash
# Platform library
gh repo create companyinfo/platform-library --public --description "Platform library Helm chart"

# Service repositories
gh repo create companyinfo/frontend-service --public --description "Frontend service"
gh repo create companyinfo/backend-service --public --description "Backend service"
gh repo create companyinfo/database-service --public --description "Database service"

# Umbrella chart
gh repo create companyinfo/umbrella-chart --public --description "Umbrella Helm chart"
```

### 2. Setup Platform Library Repository

```bash
git clone https://github.com/companyinfo/platform-library.git
cd platform-library

# Copy platform-library directory contents from this repo
cp -r ../factory/platform-library/* .

git add .
git commit -m "Initial platform library chart"
git push origin main
```

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

# Copy Jenkinsfile
cp ../factory/Jenkinsfile.service ./Jenkinsfile

# Copy .gitignore, .dockerignore
cp ../factory/services/frontend/.gitignore .
cp ../factory/services/frontend/.dockerignore .

git add .
git commit -m "Initial frontend service"
git push origin main
```

#### Backend Service

```bash
git clone https://github.com/companyinfo/backend-service.git
cd backend-service

cp ../factory/services/backend/configuration.yml .
cp ../factory/services/backend/Dockerfile .
cp ../factory/services/backend/main.py .
cp ../factory/services/backend/requirements.txt .
cp ../factory/Jenkinsfile.service ./Jenkinsfile
cp ../factory/services/backend/.dockerignore .

git add .
git commit -m "Initial backend service"
git push origin main
```

#### Database Service

```bash
git clone https://github.com/companyinfo/database-service.git
cd database-service

cp ../factory/services/database/configuration.yml .
cp ../factory/services/database/Dockerfile .
cp ../factory/services/database/init.sql .
cp ../factory/Jenkinsfile.service ./Jenkinsfile

git add .
git commit -m "Initial database service"
git push origin main
```

### 4. Setup Umbrella Chart Repository

```bash
git clone https://github.com/companyinfo/umbrella-chart.git
cd umbrella-chart

# Copy umbrella chart files
cp ../factory/umbrella-chart/Chart.yaml .
cp ../factory/umbrella-chart/values.yaml .

# Create services directory structure
mkdir -p services/frontend
mkdir -p services/backend
mkdir -p services/database

# Copy service configurations (initial state)
cp ../factory/services/frontend/configuration.yml services/frontend/
cp ../factory/services/backend/configuration.yml services/backend/
cp ../factory/services/database/configuration.yml services/database/

# Copy Jenkinsfile
cp ../factory/Jenkinsfile.umbrella ./Jenkinsfile

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

### 5. Configure Jenkins

#### Install Required Plugins

- GitHub plugin
- Pipeline plugin
- Git plugin
- Credentials Binding plugin

#### Configure GitHub Credentials

1. **Manage Jenkins** → **Credentials** → **System** → **Global credentials**
2. **Add Credentials**:
   - **Kind**: Username with password
   - **Scope**: Global
   - **Username**: Your GitHub username
   - **Password**: GitHub personal access token (with repo permissions)
   - **ID**: `github-credentials`
   - **Description**: GitHub credentials for repos

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

### 7. Setup Tools in Jenkins

The `chart-generator` and `umbrella-sync` tools need to be available in Jenkins. Options:

#### Option A: Clone Tools Repo in Jenkins

Add a stage to checkout the tools repository:

```groovy
stage('Checkout Tools') {
    steps {
        dir('tools') {
            checkout([
                $class: 'GitSCM',
                branches: [[name: '*/main']],
                userRemoteConfigs: [[
                    url: 'https://github.com/companyinfo/helm-chart-factory.git',
                    credentialsId: 'github-credentials'
                ]],
                extensions: [[
                    $class: 'SparseCheckoutPaths',
                    sparseCheckoutPaths: [[
                        path: 'factory/chart-generator'
                    ], [
                        path: 'factory/umbrella-sync'
                    ]]
                ]]
            ])
        }
    }
}
```

#### Option B: Install Tools as Jenkins Shared Libraries

Create a Jenkins shared library with the tools.

#### Option C: Package Tools as Docker Images

Build Docker images for the tools and use them in Jenkins pipelines.

## Testing the Setup

### Test Service Pipeline

1. Edit `configuration.yml` in `frontend-service` repo
2. Commit and push
3. Check Jenkins for triggered build
4. Verify:
   - Image built and pushed
   - Chart generated
   - Umbrella chart updated

### Test Umbrella Pipeline

1. Manually trigger `umbrella-chart` pipeline
2. Verify:
   - All service configs synced
   - Charts generated
   - Deployment to k3s succeeds

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

- Verify platform-library repo is accessible
- Check Python dependencies are installed
- Verify configuration.yml syntax

### Umbrella Chart Update Fails

- Check GitHub credentials for pushing
- Verify branch permissions
- Check if PR branch already exists

## Environment Variables

Set these in Jenkins → Manage Jenkins → Configure System → Global properties:

- `PLATFORM_LIBRARY_REPO`: `https://github.com/companyinfo/platform-library.git`
- `UMBRELLA_CHART_REPO`: `https://github.com/companyinfo/umbrella-chart.git`
- `LOCAL_REGISTRY`: `localhost:5000`
- `K3S_CLUSTER_NAME`: `helm-factory-cluster`
- `PLATFORM_NAMESPACE`: `platform`

## Security Considerations

1. **GitHub Tokens**: Use fine-grained tokens with minimal permissions
2. **Webhook Secrets**: Configure webhook secrets for security
3. **Jenkins Credentials**: Store securely, rotate regularly
4. **Repository Access**: Use teams/organizations for access control
5. **Branch Protection**: Enable branch protection on main branches
6. **PR Reviews**: Require reviews for umbrella chart changes

