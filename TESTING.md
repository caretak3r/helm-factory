# Testing the Helm Chart Generation

This guide details how to test the generation of a service Helm chart using the `platform-library` and a `configuration.yaml` file.

## Prerequisites

*   Helm v3 installed
*   Kubernetes cluster (optional, for deployment test)
*   `kubectl` configured (optional)

## Automated Test Harness

We have created an automated test harness to streamline the testing process. This harness generates a chart based on the configuration, builds dependencies, lints, and renders the templates.

### Running the Test

Run the following script from the project root:

```bash
./test-harness/test.sh
```

**What this script does:**

1.  **Generates Templates:** Copies relevant template files from `platform-library/templates/` to `test-harness/templates/`. This simulates the code generation phase where a service chart is constructed based on enabled features.
2.  **Updates Dependencies:** Runs `helm dependency update` to pull the `platform-library` chart.
3.  **Lints:** Runs `helm lint` using the values from `configuration.yaml` to ensure validity.
4.  **Templates:** Runs `helm template` to verify that the YAML can be rendered successfully.
5.  **Verifies Output:** Checks for the presence of key resources (Service, Deployment/StatefulSet, Ingress) in the output.

## Manual Testing Steps

If you wish to perform the steps manually, follow this procedure:

1.  **Prepare the Test Chart:**
    *   Navigate to `test-harness/`.
    *   Ensure `Chart.yaml` has the correct dependency on `platform`.
    *   Ensure `configuration.yaml` has your desired test values.

2.  **Generate Templates:**
    *   Copy the template files you want to test from `../platform-library/templates/` into `test-harness/templates/`.
    *   *Note:* Do not copy `_*.yaml` partials or `app.yaml` if you are testing individual resource generation.

3.  **Build Dependencies:**
    ```bash
    cd test-harness
    helm dependency update . --skip-refresh
    ```

4.  **Lint:**
    ```bash
    helm lint . --values configuration.yaml
    ```

5.  **Render Templates (Dry Run):**
    ```bash
    helm template . --values configuration.yaml > output.yaml
    ```
    Inspect `output.yaml` to verify the generated Kubernetes resources.

6.  **Deploy (Local Cluster):**
    If you have a local cluster (e.g., Docker Desktop, Minikube, Kind):
    ```bash
    helm install my-test-release . --values configuration.yaml --dry-run
    # If dry-run looks good:
    helm install my-test-release . --values configuration.yaml
    ```

7.  **Verify Deployment:**
    ```bash
    kubectl get all -l app.kubernetes.io/instance=my-test-release
    ```

8.  **Cleanup:**
    ```bash
    helm uninstall my-test-release
    ```

## Configuration

The `test-harness/configuration.yaml` file is used to configure the test chart. You can modify this file to test different combinations of features (e.g., enabling Ingress, switching to StatefulSet, adding PVCs).

## Troubleshooting

*   **Dependency Errors:** If `helm dependency update` fails, ensure the `platform-library` path in `Chart.yaml` is correct and that the version matches `platform-library/Chart.yaml`.
*   **Template Errors:** Use `helm template . --values configuration.yaml --debug` to see the generated YAML even if it's invalid, which helps in identifying indentation or syntax errors.
