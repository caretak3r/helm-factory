.PHONY: setup generate sync test clean help

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Install dependencies
	@echo "🚀 Setting up Helm Chart Factory..."
	cd chart-generator && uv pip install -r requirements.txt
	cd umbrella-sync && uv pip install -r requirements.txt
	@echo "✅ Setup complete!"

generate-frontend: ## Generate frontend service chart
	cd chart-generator && python3 main.py \
		--config ../services/frontend/configuration.yml \
		--library ../platform-library \
		--output ../generated-charts/frontend

generate-backend: ## Generate backend service chart
	cd chart-generator && python3 main.py \
		--config ../services/backend/configuration.yml \
		--library ../platform-library \
		--output ../generated-charts/backend

generate-database: ## Generate database service chart
	cd chart-generator && python3 main.py \
		--config ../services/database/configuration.yml \
		--library ../platform-library \
		--output ../generated-charts/database

generate-all: generate-frontend generate-backend generate-database ## Generate all service charts

sync: ## Sync all services to umbrella chart
	cd umbrella-sync && python3 main.py \
		--umbrella ../umbrella-chart \
		--services ../services \
		--library ../platform-library

test: ## Validate generated charts
	@echo "🔍 Validating charts..."
	@for chart in generated-charts/*/; do \
		if [ -d "$$chart" ]; then \
			echo "Validating $$chart..."; \
			helm lint "$$chart" || true; \
		fi \
	done
	@if [ -d "umbrella-chart" ]; then \
		echo "Validating umbrella chart..."; \
		cd umbrella-chart && helm dependency update && helm lint . || true; \
	fi

setup-k3s: ## Setup k3s cluster
	./scripts/setup-k3s.sh

install-jenkins: ## Install Jenkins on k3s
	./scripts/install-jenkins.sh

jenkins-quickstart: ## Complete Jenkins setup (k3s + Jenkins)
	./scripts/quickstart-jenkins.sh

jenkins-password: ## Get Jenkins admin password
	@kubectl exec -n jenkins $$(kubectl get pods -n jenkins -l app=jenkins -o jsonpath='{.items[0].metadata.name}') -- cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "Jenkins not running or not ready"

jenkins-logs: ## View Jenkins logs
	kubectl logs -n jenkins -l app=jenkins --tail=100 -f

jenkins-port-forward: ## Port forward Jenkins to localhost:8080
	kubectl port-forward -n jenkins svc/jenkins 8080:8080

setup-registry: ## Setup local Docker registry
	./scripts/setup-local-registry.sh

build-images: ## Build and push all service images
	./scripts/build-and-push-images.sh

install-cert-manager: ## Install cert-manager and self-signed issuer
	./scripts/install-cert-manager.sh

configure-k3s-registry: ## Configure k3s to use local registry (requires sudo)
	sudo ./scripts/configure-k3s-registry.sh

setup-all: setup setup-registry install-cert-manager configure-k3s-registry build-images ## Complete setup (deps + registry + cert-manager + k3s config + images)

clean: ## Clean generated files
	rm -rf generated-charts/
	rm -rf umbrella-chart/charts/
	rm -f umbrella-chart/Chart.lock
	rm -f umbrella-chart/values-*.yaml
	find . -type d -name __pycache__ -exec rm -r {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete

clean-all: clean ## Clean everything including k3s
	@echo "⚠️  This will stop k3s. Continue? [y/N]"
	@read -r answer && [ "$$answer" = "y" ] && sudo systemctl stop k3s || echo "Cancelled"

