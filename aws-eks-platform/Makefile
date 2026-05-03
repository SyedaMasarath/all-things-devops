################################################################################
# Makefile — AWS EKS Platform
# Run 'make help' to see all available targets
################################################################################

.DEFAULT_GOAL := help
.PHONY: help

ENVIRONMENT ?= dev
AWS_REGION  ?= us-east-1
CLUSTER_NAME ?= eks-platform-$(ENVIRONMENT)

ifneq ($(origin ENVIRONMENT), command line)
BOOTSTRAP_ENV ?= all
else
BOOTSTRAP_ENV := $(ENVIRONMENT)
endif

BOLD  := $(shell tput bold)
GREEN := $(shell tput setaf 2)
RESET := $(shell tput sgr0)

help: ## Show this help message
	@echo "$(BOLD)AWS EKS Platform — Available Commands$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-30s$(RESET) %s\n", $$1, $$2}'

################################################################################
# Bootstrap
################################################################################

bootstrap: ## Bootstrap Terraform remote state (run once)
	@chmod +x scripts/bootstrap.sh
	@./scripts/bootstrap.sh $(BOOTSTRAP_ENV)

################################################################################
# Terraform
################################################################################

tf-init: ## Initialize Terraform for ENVIRONMENT (make tf-init ENVIRONMENT=prod)
	@cd terraform/environments/$(ENVIRONMENT) && terraform init

tf-plan: ## Run Terraform plan for ENVIRONMENT
	@cd terraform/environments/$(ENVIRONMENT) && \
		terraform plan -out=tfplan -no-color | tee plan.txt

tf-apply: ## Apply Terraform plan for ENVIRONMENT
	@cd terraform/environments/$(ENVIRONMENT) && \
		terraform apply tfplan

tf-destroy: ## Destroy infrastructure (DANGEROUS — requires confirmation)
	@read -p "Are you sure you want to destroy $(ENVIRONMENT)? [yes/N] " confirm; \
	[ "$$confirm" = "yes" ] || (echo "Aborting."; exit 1)
	@cd terraform/environments/$(ENVIRONMENT) && \
		terraform destroy -auto-approve

tf-fmt: ## Format all Terraform files
	@terraform fmt -recursive terraform/

tf-validate: ## Validate all Terraform modules
	@for dir in terraform/modules/*/; do \
		echo "Validating $$dir..."; \
		cd "$$dir" && terraform init -backend=false -no-color > /dev/null && \
		terraform validate && cd ../../../; \
	done

tf-docs: ## Generate Terraform module documentation
	@which terraform-docs &>/dev/null || (echo "Install terraform-docs first"; exit 1)
	@find terraform/modules -name "*.tf" -exec dirname {} \; | sort -u | \
		xargs -I{} terraform-docs markdown {} > {}/DOCS.md

################################################################################
# Kubernetes
################################################################################

kubeconfig: ## Update kubeconfig for ENVIRONMENT
	@aws eks update-kubeconfig \
		--region $(AWS_REGION) \
		--name $(CLUSTER_NAME) \
		--alias $(ENVIRONMENT)

apply-k8s: ## Apply all Kubernetes manifests
	@kubectl apply -k kubernetes/

validate: ## Run pre-deploy validation checks
	@chmod +x scripts/validate.sh
	@./scripts/validate.sh $(ENVIRONMENT)

nodes: ## Show cluster nodes and their resource usage
	@kubectl top nodes

pods: ## Show all pods across namespaces
	@kubectl get pods --all-namespaces -o wide

events: ## Show recent warning events
	@kubectl get events --all-namespaces \
		--field-selector type=Warning \
		--sort-by='.lastTimestamp' | tail -20

################################################################################
# Helm
################################################################################

helm-lint: ## Lint the app-platform and frontend Helm charts
	@helm lint helm/charts/app-platform/
	@helm lint helm/charts/frontend/

helm-template: ## Render Helm templates locally for review
	@helm template my-app helm/charts/app-platform/ \
		--values helm/charts/app-platform/values.yaml \
		--values helm/charts/app-platform/values-dev.yaml \
		--debug
	@helm template my-frontend helm/charts/frontend/ \
		--values helm/charts/frontend/values.yaml \
		--values helm/charts/frontend/values-dev.yaml \
		--debug

helm-diff: ## Show diff before upgrading (requires helm-diff plugin)
	@helm diff upgrade api-service helm/charts/app-platform/ \
		--namespace production \
		--values helm/charts/app-platform/values.yaml \
		--values helm/charts/app-platform/values-prod.yaml

monitoring-install: ## Install kube-prometheus-stack
	@helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	@helm repo update
	@helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
		--namespace monitoring \
		--create-namespace \
		--values helm/monitoring/values.yaml \
		--wait

monitoring-uninstall: ## Remove monitoring stack
	@helm uninstall kube-prometheus-stack --namespace monitoring

################################################################################
# Observability
################################################################################

grafana-port-forward: ## Port-forward Grafana to localhost:3000
	@echo "Opening Grafana at http://localhost:3000"
	@kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring

prometheus-port-forward: ## Port-forward Prometheus to localhost:9090
	@echo "Opening Prometheus at http://localhost:9090"
	@kubectl port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 -n monitoring

alertmanager-port-forward: ## Port-forward Alertmanager to localhost:9093
	@echo "Opening Alertmanager at http://localhost:9093"
	@kubectl port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 -n monitoring

################################################################################
# Security
################################################################################

scan-terraform: ## Run tfsec security scan on Terraform code
	@which tfsec &>/dev/null || (go install github.com/aquasecurity/tfsec/cmd/tfsec@latest)
	@tfsec terraform/ --format=table

scan-k8s: ## Scan Kubernetes manifests with kube-score
	@which kube-score &>/dev/null || (echo "Install kube-score: https://kube-score.com"; exit 1)
	@find kubernetes/ -name "*.yaml" | xargs kube-score score

scan-image: ## Scan Docker image with Trivy (IMAGE=repo/name:tag)
	@trivy image $(IMAGE)

################################################################################
# CI/CD helpers
################################################################################

act-plan: ## Run terraform-plan workflow locally with 'act'
	@which act &>/dev/null || (echo "Install act: https://github.com/nektos/act"; exit 1)
	@act pull_request -W .github/workflows/terraform-plan.yml

act-build: ## Run build-push workflow locally
	@act push -W .github/workflows/build-push.yml
