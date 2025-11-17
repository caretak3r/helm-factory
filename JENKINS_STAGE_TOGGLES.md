# Jenkins Stage Toggles

This document describes how to enable or disable individual stages in the Jenkins pipelines using environment variables.

## Overview

All stages in both `Jenkinsfile.service` and `Jenkinsfile.umbrella` can be toggled on or off using environment variables. This allows you to:
- Skip stages during POC/testing
- Enable/disable features as needed
- Customize pipeline behavior per job

## Usage

### Setting Toggles in Jenkins Job

1. Go to your Jenkins job configuration
2. Navigate to **Build Environment** section
3. Check **Use secret text(s) or file(s)**
4. Add environment variables:

```
ENABLE_DEPLOY=false
ENABLE_VERIFY_DEPLOYMENT=false
```

Or use the **This build is parameterized** option to make them interactive.

### Setting Toggles via Jenkinsfile Parameters

You can also set defaults in the Jenkinsfile itself, or override them via Jenkins job configuration.

## Service Pipeline Toggles

### Available Toggles

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `ENABLE_CHECKOUT_SERVICE` | `true` | Checkout service repository |
| `ENABLE_CHECKOUT_PLATFORM` | `true` | Checkout platform library |
| `ENABLE_CHECKOUT_TOOLS` | `true` | Checkout chart-generator and umbrella-sync tools |
| `ENABLE_SETUP_ENV` | `true` | Setup Python environment and dependencies |
| `ENABLE_VALIDATE_CONFIG` | `true` | Validate service configuration.yml |
| `ENABLE_BUILD_IMAGE` | `true` | Build Docker image for service |
| `ENABLE_GENERATE_CHART` | `true` | Generate Helm chart from configuration |
| `ENABLE_LINT_CHART` | `true` | Lint generated Helm chart |
| `ENABLE_TEMPLATE_CHART` | `true` | Render chart templates |
| `ENABLE_UPDATE_UMBRELLA` | `true` | Update umbrella chart with service changes |
| `ENABLE_CREATE_PR` | `true` | Create PR to umbrella-chart repository |
| `ENABLE_DEPLOY` | `false` | Deploy to k3s cluster (disabled for POC) |
| `ENABLE_VERIFY_DEPLOYMENT` | `false` | Verify deployment status (disabled for POC) |

### POC Configuration

For POC, the following stages are disabled by default:
- `ENABLE_DEPLOY=false` - Skips deployment to k3s
- `ENABLE_VERIFY_DEPLOYMENT=false` - Skips deployment verification

### Example: Enable Deployment for Production

```groovy
// In Jenkins job configuration or Jenkinsfile
environment {
    ENABLE_DEPLOY = 'true'
    ENABLE_VERIFY_DEPLOYMENT = 'true'
}
```

## Umbrella Pipeline Toggles

### Available Toggles

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `ENABLE_CHECKOUT_UMBRELLA` | `true` | Checkout umbrella chart repository |
| `ENABLE_CHECKOUT_PLATFORM` | `true` | Checkout platform library |
| `ENABLE_CHECKOUT_TOOLS` | `true` | Checkout umbrella-sync tool |
| `ENABLE_SETUP_ENV` | `true` | Setup Python environment |
| `ENABLE_SYNC_UMBRELLA` | `true` | Sync all service configurations |
| `ENABLE_LINT_CHARTS` | `true` | Lint all charts |
| `ENABLE_TEMPLATE_CHARTS` | `true` | Render chart templates |
| `ENABLE_DEPLOY` | `false` | Deploy to k3s cluster (disabled for POC) |
| `ENABLE_VALIDATE_PR` | `true` | Validate PR changes (PR branches only) |
| `ENABLE_VERIFY_DEPLOYMENT` | `false` | Verify deployment status (disabled for POC) |
| `ENABLE_RUN_TESTS` | `true` | Run integration tests |

### POC Configuration

For POC, the following stages are disabled by default:
- `ENABLE_DEPLOY=false` - Skips deployment to k3s
- `ENABLE_VERIFY_DEPLOYMENT=false` - Skips deployment verification

## Configuration Examples

### POC Configuration (Default)

```groovy
environment {
    // All stages enabled except deployment
    ENABLE_DEPLOY = 'false'
    ENABLE_VERIFY_DEPLOYMENT = 'false'
}
```

### Full Production Configuration

```groovy
environment {
    // All stages enabled
    ENABLE_DEPLOY = 'true'
    ENABLE_VERIFY_DEPLOYMENT = 'true'
}
```

### Testing Configuration (Skip Image Build)

```groovy
environment {
    ENABLE_BUILD_IMAGE = 'false'  // Skip image build
    ENABLE_DEPLOY = 'false'       // Skip deployment
    ENABLE_VERIFY_DEPLOYMENT = 'false'
}
```

### Validation Only Configuration

```groovy
environment {
    ENABLE_BUILD_IMAGE = 'false'
    ENABLE_DEPLOY = 'false'
    ENABLE_VERIFY_DEPLOYMENT = 'false'
    ENABLE_CREATE_PR = 'false'  // Don't create PR, just validate
}
```

## Setting Toggles via Jenkins UI

### Method 1: Job Configuration

1. Open Jenkins job
2. Click **Configure**
3. Scroll to **Build Environment**
4. Check **Use secret text(s) or file(s)**
5. Add **Bindings** → **Custom environment variables**
6. Add variables:
   ```
   ENABLE_DEPLOY=false
   ENABLE_VERIFY_DEPLOYMENT=false
   ```

### Method 2: Parameterized Build

1. Open Jenkins job
2. Click **Configure**
3. Check **This build is parameterized**
4. Add **Choice Parameter**:
   - Name: `ENABLE_DEPLOY`
   - Choices:
     ```
     true
     false
     ```
   - Default: `false`
5. Repeat for other toggles

### Method 3: Pipeline Parameters

Add to Jenkinsfile:

```groovy
parameters {
    booleanParam(
        name: 'ENABLE_DEPLOY',
        defaultValue: false,
        description: 'Enable deployment to k3s'
    )
    booleanParam(
        name: 'ENABLE_VERIFY_DEPLOYMENT',
        defaultValue: false,
        description: 'Enable deployment verification'
    )
}

environment {
    ENABLE_DEPLOY = "${params.ENABLE_DEPLOY}"
    ENABLE_VERIFY_DEPLOYMENT = "${params.ENABLE_VERIFY_DEPLOYMENT}"
}
```

## Stage Dependencies

Some stages depend on others. If you disable a required stage, dependent stages will fail:

### Service Pipeline Dependencies

- `Generate Chart` requires: `Checkout Service`, `Checkout Platform`, `Checkout Tools`, `Setup Environment`
- `Lint Chart` requires: `Generate Chart`
- `Template Chart` requires: `Generate Chart`
- `Update Umbrella Chart` requires: `Generate Chart`
- `Create PR` requires: `Update Umbrella Chart`
- `Deploy` requires: `Create PR` (if enabled)
- `Verify Deployment` requires: `Deploy` (if enabled)

### Umbrella Pipeline Dependencies

- `Sync Umbrella Chart` requires: `Checkout Umbrella`, `Checkout Platform`, `Checkout Tools`, `Setup Environment`
- `Lint Charts` requires: `Sync Umbrella Chart`
- `Template Charts` requires: `Sync Umbrella Chart`
- `Deploy` requires: `Sync Umbrella Chart` (if enabled)
- `Verify Deployment` requires: `Deploy` (if enabled)
- `Run Tests` requires: `Deploy` (if enabled)

## Troubleshooting

### Stage Skipped Unexpectedly

Check:
1. Environment variable is set correctly (`'true'` or `'false'` as strings)
2. Variable name matches exactly (case-sensitive)
3. No typos in variable name
4. Variable is set before the stage runs

### Stage Runs When It Shouldn't

Check:
1. Environment variable is set to `'false'` (string, not boolean)
2. `when` condition is correct
3. No conflicting conditions

### Deployment Stage Not Running

For deployment stages, ensure:
1. `ENABLE_DEPLOY=true`
2. Branch is `main` or `master`
3. All prerequisite stages completed successfully

## Best Practices

1. **Use defaults for POC**: Keep deployment stages disabled by default
2. **Enable selectively**: Only enable deployment for production jobs
3. **Document customizations**: Note which toggles are changed and why
4. **Test configurations**: Verify pipeline works with toggles enabled/disabled
5. **Use parameters**: Make toggles interactive for flexibility

## Quick Reference

### Disable All Deployment (POC)

```bash
ENABLE_DEPLOY=false
ENABLE_VERIFY_DEPLOYMENT=false
```

### Enable All Stages (Production)

```bash
ENABLE_DEPLOY=true
ENABLE_VERIFY_DEPLOYMENT=true
```

### Validation Only

```bash
ENABLE_BUILD_IMAGE=false
ENABLE_DEPLOY=false
ENABLE_VERIFY_DEPLOYMENT=false
ENABLE_CREATE_PR=false
```

