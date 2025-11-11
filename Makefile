.DEFAULT_GOAL := lint

SHELL                  := /bin/bash -o nounset -o pipefail -o errexit
DATE                   := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ") # Date format RFC3339
OK                     := "🦄"
ERROR                  := "🤬"
REQUIRED_BINS          := kubectl ct kind helm-docs
BUILD_DIR              := build
LINT_LOG               := $(BUILD_DIR)/lint.log
README_LOG             := $(BUILD_DIR)/readme.log
RENDER_LOG             := $(BUILD_DIR)/render.log
RENDER_OUTPUT          := $(BUILD_DIR)/chart-output.yaml
CNPG_INSTALL_LOGOUTPUT := $(BUILD_DIR)/cnpg-install.log

.PHONY: help
help:
	@echo ""
	@echo "👋 Hello World!"
	@echo "---------------"
	@echo ""
	@echo "This repository contains Helm charts for deploying OpenNMS components."
	@echo "You can install the following application:"
	@echo "  - OpenNMS Core: The main application with essential services and the web user interface."
	@echo "  - OpenNMS Minion: A lightweight proxy agent for collection and monitoring."
	@echo "  - OpenNMS Sentinel: A distributed worker for scalable flow persistence into ElasticSearch"
	@echo ""
	@echo "Requirements:"
	@echo "  - kind: for creating local Kubernetes clusters"
	@echo "  - ct (chart-testing): for linting and testing Helm charts"
	@echo "  - helm-docs: for generating README.md files for Helm charts"
	@echo ""
	@echo "Available make targets:"
	@echo "  lint                  - Lint Helm charts in the charts/ directory"
	@echo "  kind-create           - Create a local Kubernetes cluster using kind for testing"
	@echo "  kind-delete           - Delete the local kind Kubernetes cluster"
	@echo "  test-install-core     - Test installing Core Helm chart into the kind cluster"
	@echo "  test-install-minion   - Test installing Minion Helm chart into the kind cluster"
	@echo "  test-install-sentinel - Test installing Sentinel Helm chart into the kind cluster"
	@echo "  install-all           - Test installing all Helm charts into the kind cluster"
	@echo "  readme                - Generate README.md files for Helm charts using helm-docs"

build:
	@echo -n "👩‍🔧 Create build directory     ... "
	@mkdir -p build
	@echo "$(OK)"

.PHONY: deps
deps:
	$(foreach bin,$(REQUIRED_BINS),\
		$(if $(shell command -v $(bin) 2>/dev/null),$(info 👮 $(bin) 🌈 ),$(error Please install `$(bin)`)))

.PHONY: lint
lint: deps build
	@echo -n "👩‍🔬 Linting Helm charts        ... "
	@ct lint --debug --chart-dirs charts --validate-maintainers=true 2>&1>$(LINT_LOG) || { cat $(LINT_LOG); exit 1; }
	@echo "$(OK)"

.PHONY: kind-create
kind-create: deps
	@if kind get clusters | grep -q helm-lint; then \
		echo "👩‍🔧 Kind cluster 'helm-lint' already exists. Skipping creation."; \
		exit 0; \
	else \
		echo -n "👩‍🔧 Creating kind cluster "; \
		kind create cluster --name helm-lint --wait 5m; \
	fi

.PHONY: kind-delete
kind-delete: deps
	@echo "👩‍🔧 Deleting kind cluster "
	@kind delete cluster --name helm-lint

.PHONY: test-install-core
test-install-core: lint kind-create install-postgres
	@echo -n "🚀 Intall Helm Chart Core      ... "
	@ct install --charts charts/core
	@echo -n "🧼 Cleanup Postgres Cluster    ... "
	$(MAKE) clean-postgres

.PHONY: test-install-minion
test-install-minion: lint kind-create
	@echo -n "🚀 Install Helm Chart Minion    ... "
	@ct install --charts charts/minion
	@echo "$(OK)"

.PHONY: test-install-sentinel
test-install-sentinel: lint kind-create install-postgres
	@echo -n "🚀 Install Helm Chart Sentinel ... "
	@ct install --charts charts/sentinel
	@echo "$(OK)"
	@echo -n "🧼 Cleanup Postgres Cluster    ... "
	$(MAKE) clean-postgres

.PHONY: test-install-all
install-all: test-install-core test-install-minion test-install-sentinel

.PHONE: readme
readme:
	@echo -n "📝 Generating README.md       ... "
	@helm-docs --log-level warning --chart-search-root charts/ 2>&1>$(README_LOG) || { cat $(README_LOG); exit 1; }
	@echo "$(OK)"

.PHONY: render-core
render-core:
	@echo -n "🎨 Rendering Helm charts      ... "
	@helm template core charts/core 1>$(RENDER_OUTPUT) 2>$(README_LOG) || { cat $(RENDER_LOG); exit 1; }
	@cat $(RENDER_OUTPUT)
	@echo "$(OK)"

.PHONY: install-postgres
install-postgres: kind-create
	@echo -n "🚀 Add CNPG repository        ... "
	@helm repo add cnpg https://cloudnative-pg.github.io/charts 2>&1>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@echo "$(OK)"
	@echo -n "🚀 Install CNPG operator      ... "
	@helm upgrade --install cnpg --namespace cnpg-system --create-namespace cnpg/cloudnative-pg 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@echo "$(OK)"
	@echo -n "🚀 Create super user secret   ... "
	@kubectl apply -f stubs/postgres/secret-superuser.yaml 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@echo "$(OK)"
	@echo -n "🚀 Create OpenNMS user secret ... "
	@kubectl apply -f stubs/postgres/secret-opennms-core-db.yaml 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@echo "$(OK)"
	@echo -n "⏱️ Waiting for CNPG operator  ... "
	@kubectl wait --for=condition=available --timeout=300s deployment/cnpg-cloudnative-pg -n cnpg-system 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@echo "$(OK)"
	@echo -n "🚀 Install Postgres Cluster   ... "
	@kubectl apply -f stubs/postgres/pg-database.yaml 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@echo "$(OK)"
	@echo -n "⏱️ Waiting for database init  ... "
	@sleep 5; kubectl wait --for=condition=complete --timeout=900s job/cluster-helm-lint-1-initdb -n default 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@echo "$(OK)"
	@echo -n "⏱️ Waiting for startup        ... "
	@kubectl wait --for=condition=ready --timeout=60s pod/cluster-helm-lint-1 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@echo "$(OK)"

.PHONY: clean-postgres
clean-postgres: kind-create
	@echo -n "🧼 Deleting Postgres Cluster  ... "
	@kubectl delete -f stubs/postgres/pg-database.yaml 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@kubectl delete -f stubs/postgres/secret-superuser.yaml 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@kubectl delete -f stubs/postgres/secret-opennms-core-db.yaml 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@echo "$(OK)"
