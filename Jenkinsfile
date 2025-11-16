pipeline {
    agent any
    
    environment {
        KUBECONFIG = "${WORKSPACE}/kubeconfig"
        HELM_HOME = "${WORKSPACE}/.helm"
        K3S_CLUSTER_NAME = "helm-factory-cluster"
        NAMESPACE = "platform"
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    echo "📦 Checking out code..."
                    checkout scm
                }
            }
        }
        
        stage('Setup Environment') {
            steps {
                script {
                    echo "🔧 Setting up environment..."
                    sh '''
                        # Install Python dependencies
                        cd chart-generator && uv pip install -r requirements.txt
                        cd ../umbrella-sync && uv pip install -r requirements.txt
                        
                        # Setup Helm
                        helm version || echo "Helm not installed, will use k3s bundled version"
                        
                        # Ensure local registry is running
                        if ! docker ps | grep -q local-registry; then
                            echo "Starting local registry..."
                            docker run -d --name local-registry --restart=always -p 5000:5000 registry:2 || true
                            sleep 2
                        fi
                    '''
                }
            }
        }
        
        stage('Build Images') {
            steps {
                script {
                    echo "🏗️ Building and pushing service images..."
                    sh '''
                        REGISTRY="localhost:5000"
                        
                        # Build and push frontend
                        cd services/frontend
                        docker build -t $REGISTRY/frontend:latest .
                        docker push $REGISTRY/frontend:latest
                        cd ../..
                        
                        # Build and push backend
                        cd services/backend
                        docker build -t $REGISTRY/backend:latest .
                        docker push $REGISTRY/backend:latest
                        cd ../..
                        
                        # Build and push database
                        cd services/database
                        docker build -t $REGISTRY/database:latest .
                        docker push $REGISTRY/database:latest
                        cd ../..
                    '''
                }
            }
        }
        
        stage('Validate Configurations') {
            steps {
                script {
                    echo "✅ Validating service configurations..."
                    sh '''
                        python3 -c "
                        import yaml
                        import sys
                        from pathlib import Path
                        
                        errors = []
                        for config_file in Path('services').rglob('configuration.yml'):
                            try:
                                with open(config_file) as f:
                                    config = yaml.safe_load(f)
                                    if not config.get('service', {}).get('name'):
                                        errors.append(f'{config_file}: Missing service.name')
                                    if not config.get('deployment', {}).get('image', {}).get('repository'):
                                        errors.append(f'{config_file}: Missing deployment.image.repository')
                            except Exception as e:
                                errors.append(f'{config_file}: {e}')
                        
                        if errors:
                            print('\\n'.join(errors))
                            sys.exit(1)
                        print('All configurations valid!')
                        "
                    '''
                }
            }
        }
        
        stage('Generate Charts') {
            steps {
                script {
                    echo "🏗️ Generating Helm charts..."
                    sh '''
                        mkdir -p generated-charts
                        
                        # Generate charts for all services
                        for config_file in services/*/configuration.yml; do
                            if [ -f "$config_file" ]; then
                                service_name=$(basename $(dirname "$config_file"))
                                echo "Generating chart for $service_name..."
                                cd chart-generator
                                python main.py \
                                    --config "../$config_file" \
                                    --library ../platform-library \
                                    --output "../generated-charts/$service_name"
                                cd ..
                            fi
                        done
                    '''
                }
            }
        }
        
        stage('Lint Charts') {
            steps {
                script {
                    echo "🔍 Linting generated charts..."
                    sh '''
                        for chart_dir in generated-charts/*/; do
                            if [ -d "$chart_dir" ]; then
                                echo "Linting $(basename $chart_dir)..."
                                helm lint "$chart_dir" || exit 1
                            fi
                        done
                    '''
                }
            }
        }
        
        stage('Template Charts') {
            steps {
                script {
                    echo "📄 Rendering chart templates..."
                    sh '''
                        mkdir -p rendered-manifests
                        for chart_dir in generated-charts/*/; do
                            if [ -d "$chart_dir" ]; then
                                service_name=$(basename "$chart_dir")
                                echo "Rendering templates for $service_name..."
                                helm template "$service_name" "$chart_dir" \
                                    --output-dir "rendered-manifests/$service_name" \
                                    --namespace "$NAMESPACE" || exit 1
                            fi
                        done
                    '''
                }
            }
        }
        
        stage('Setup k3s Cluster') {
            steps {
                script {
                    echo "🚀 Setting up k3s cluster..."
                    sh '''
                        # Check if k3s is already running
                        if kubectl cluster-info &>/dev/null; then
                            echo "k3s cluster already running"
                        else
                            echo "Starting k3s cluster..."
                            ./scripts/setup-k3s.sh
                        fi
                        
                        # Wait for cluster to be ready
                        kubectl wait --for=condition=Ready nodes --all --timeout=300s || exit 1
                        
                        # Setup namespace
                        kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
                    '''
                }
            }
        }
        
        stage('Install Dependencies') {
            steps {
                script {
                    echo "📥 Installing cluster dependencies..."
                    sh '''
                        # Install cert-manager if not present
                        if ! kubectl get namespace cert-manager &>/dev/null; then
                            echo "Installing cert-manager..."
                            kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
                            kubectl wait --for=condition=Ready pods -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
                        fi
                        
                        # Install self-signed ClusterIssuer
                        kubectl apply -f cert-manager/cluster-issuer.yaml || true
                        
                        # Install ingress-nginx if not present
                        if ! kubectl get namespace ingress-nginx &>/dev/null; then
                            echo "Installing ingress-nginx..."
                            kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
                            kubectl wait --for=condition=Ready pods -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=300s
                        fi
                        
                        # Configure k3s to use local registry (if not already configured)
                        # This allows k3s to pull from localhost:5000
                        if ! grep -q "localhost:5000" /etc/rancher/k3s/registries.yaml 2>/dev/null; then
                            echo "Configuring k3s registry..."
                            sudo mkdir -p /etc/rancher/k3s
                            echo "mirrors:
  localhost:5000:
    endpoint:
      - \"http://localhost:5000\"" | sudo tee /etc/rancher/k3s/registries.yaml
                            sudo systemctl restart k3s || true
                            sleep 5
                        fi
                    '''
                }
            }
        }
        
        stage('Sync Umbrella Chart') {
            steps {
                script {
                    echo "🔄 Syncing umbrella chart..."
                    sh '''
                        cd umbrella-sync
                        python main.py \
                            --umbrella ../umbrella-chart \
                            --services ../services \
                            --library ../platform-library
                        cd ..
                        
                        # Update umbrella chart dependencies
                        cd umbrella-chart
                        helm dependency update
                        cd ..
                    '''
                }
            }
        }
        
        stage('Deploy to k3s') {
            steps {
                script {
                    echo "🚢 Deploying charts to k3s cluster..."
                    sh '''
                        cd umbrella-chart
                        
                        # Build values files list
                        VALUES_ARGS="--values values.yaml"
                        for values_file in values-*.yaml; do
                            if [ -f "$values_file" ]; then
                                VALUES_ARGS="$VALUES_ARGS --values $values_file"
                            fi
                        done
                        
                        # Install or upgrade
                        helm upgrade --install platform . \
                            --namespace "$NAMESPACE" \
                            --create-namespace \
                            $VALUES_ARGS \
                            --wait \
                            --timeout 10m \
                            --atomic || exit 1
                        cd ..
                    '''
                }
            }
        }
        
        stage('Verify Deployment') {
            steps {
                script {
                    echo "✅ Verifying deployment..."
                    sh '''
                        # Wait for all deployments to be ready
                        kubectl wait --for=condition=available \
                            --timeout=300s \
                            deployment \
                            -n "$NAMESPACE" \
                            --all || exit 1
                        
                        # Check pod status
                        kubectl get pods -n "$NAMESPACE"
                        
                        # Verify services
                        kubectl get svc -n "$NAMESPACE"
                        
                        # Verify ingress (if any)
                        kubectl get ingress -n "$NAMESPACE" || echo "No ingress resources"
                    '''
                }
            }
        }
        
        stage('Run Tests') {
            steps {
                script {
                    echo "🧪 Running tests..."
                    sh '''
                        # Run smoke tests
                        ./scripts/run-tests.sh "$NAMESPACE"
                    '''
                }
            }
        }
        
        stage('Cleanup (Optional)') {
            when {
                expression { env.BRANCH_NAME == 'main' || env.BRANCH_NAME == 'master' }
            }
            steps {
                script {
                    echo "🧹 Cleanup skipped for main branch"
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "📊 Pipeline completed"
                sh '''
                    echo "=== Deployment Status ==="
                    kubectl get all -n "$NAMESPACE" || true
                    echo ""
                    echo "=== Pod Status ==="
                    kubectl get pods -n "$NAMESPACE" || true
                '''
            }
        }
        success {
            echo "✅ Pipeline succeeded!"
            archiveArtifacts artifacts: 'rendered-manifests/**/*', allowEmptyArchive: true
            archiveArtifacts artifacts: 'generated-charts/**/*', allowEmptyArchive: true
        }
        failure {
            echo "❌ Pipeline failed!"
            sh '''
                echo "=== Pod Logs (last 50 lines) ==="
                kubectl logs -n "$NAMESPACE" --tail=50 -l app.kubernetes.io/managed-by=Helm || true
                echo ""
                echo "=== Pod Events ==="
                kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -20 || true
            '''
        }
        cleanup {
            cleanWs()
        }
    }
}

