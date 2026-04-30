.DEFAULT_GOAL := lint

SHELL                  := /bin/bash -o nounset -o pipefail -o errexit
DATE                   := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ") # Date format RFC3339
OK                     := "🦄"
ERROR                  := "🤬"
REQUIRED_BINS          := kubectl ct kind helm
REQUIRED_BINS_DOCS     := helm-docs
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
	@echo "  - helm: for chart rendering, dependency resolution, and templating"
	@echo "  - kubectl: for applying stub manifests in stubs/"
	@echo ""
	@echo "Available make targets:"
	@echo ""
	@echo "  Linting and basic operations:"
	@echo "    lint                  - Lint Helm charts in the charts/ directory"
	@echo "    readme                - Generate README.md files for Helm charts using helm-docs"
	@echo "    kind-create           - Create a local Kubernetes cluster using kind for testing"
	@echo "    kind-delete           - Delete the local kind Kubernetes cluster"
	@echo ""
	@echo "  Chart-testing (CI flow — installs and auto-uninstalls):"
	@echo "    test-install-core     - Install + test Core via ct"
	@echo "    test-install-minion   - Install + test Minion via ct"
	@echo "    test-install-sentinel - Install + test Sentinel via ct"
	@echo "    test-install-stack    - Install + test the opennms-stack umbrella via ct"
	@echo "                            (with Postgres, Kafka, and Elasticsearch stubs)"
	@echo "    install-all           - Run all four test-install-* targets"
	@echo ""
	@echo "  Dev install (PERSISTS — leaves releases running for interactive use):"
	@echo "    dev-install-core      - helm install Core into the kind cluster (default ns)"
	@echo "    dev-install-minion    - helm install Minion"
	@echo "    dev-install-sentinel  - helm install Sentinel"
	@echo "    dev-install-stack     - helm install opennms-stack umbrella"
	@echo "    dev-uninstall-<name>  - helm uninstall a single release"
	@echo "    dev-uninstall-all     - uninstall all releases AND tear down infra stubs"
	@echo "    dev-clean             - dev-uninstall-all + delete the kind cluster"

build:
	@echo -n "👩‍🔧 Create build directory     ... "
	@mkdir -p build
	@echo "$(OK)"

.PHONY: deps
deps:
	$(foreach bin,$(REQUIRED_BINS),\
		$(if $(shell command -v $(bin) 2>/dev/null),$(info 👮 $(bin) 🌈 ),$(error Please install `$(bin)`)))

.PHONY: deps-docs
deps-docs:
	$(foreach bin,$(REQUIRED_BINS_DOCS),\
		$(if $(shell command -v $(bin) 2>/dev/null),$(info 👮 $(bin) 🌈 ),$(error Please install `$(bin)`)))

.PHONY: lint
lint: deps build
	@echo -n "👩‍🔬 Linting Helm charts        ... "
	@# `--check-version-increment=false`: the chart-releaser-action handles
	@# deduplication at release time (skips versions already published), so
	@# the ct lint version-bump check is redundant friction here — it forces
	@# spurious bumps on PRs that don't actually need them (README regen,
	@# unrelated chart-adjacent changes). Bumps are still enforced at release
	@# time by chart-releaser-action.
	@ct lint --debug --chart-dirs charts --validate-maintainers=true --check-version-increment=false 2>&1>$(LINT_LOG) || { cat $(LINT_LOG); exit 1; }
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
	@ct install --charts charts/core --helm-extra-args "--timeout=10m"
	@echo -n "🧼 Cleanup Postgres Cluster    ... "
	$(MAKE) clean-postgres

.PHONY: test-install-minion
test-install-minion: lint kind-create install-kafka
	@echo -n "🚀 Install Helm Chart Minion    ... "
	@ct install --charts charts/minion --helm-extra-args "--timeout=10m"
	@echo "$(OK)"
	@echo -n "🧼 Cleanup Kafka stub          ... "
	$(MAKE) clean-kafka

.PHONY: test-install-sentinel
test-install-sentinel: lint kind-create install-postgres
	@echo -n "🚀 Install Helm Chart Sentinel ... "
	@ct install --charts charts/sentinel --helm-extra-args "--timeout=10m"
	@echo "$(OK)"
	@echo -n "🧼 Cleanup Postgres Cluster    ... "
	$(MAKE) clean-postgres

.PHONY: test-install-stack
test-install-stack: lint kind-create install-postgres install-kafka install-elasticsearch
	@echo -n "🚀 Install Helm Chart Stack    ... "
	@helm dep update charts/opennms-stack 2>&1 || { echo "$(ERROR)"; exit 1; }
	@ct install --charts charts/opennms-stack --helm-extra-args "--timeout=10m"
	@echo "$(OK)"
	@echo -n "🧼 Cleanup Postgres / Kafka / ES ..."
	$(MAKE) clean-elasticsearch
	$(MAKE) clean-kafka
	$(MAKE) clean-postgres

.PHONY: install-all
install-all: test-install-core test-install-minion test-install-sentinel test-install-stack

# ============================================================================
# Dev install targets — local Helm releases that PERSIST after install.
#
# Unlike `test-install-*` (which uses `ct install` and auto-uninstalls), these
# use `helm upgrade --install` and leave the release running in the kind cluster
# so a developer can interact with OpenNMS, port-forward to the WebUI, run
# Karaf shell sessions, etc.
#
# Releases are installed in the `default` namespace alongside the infrastructure
# stubs so existingSecret references and Service DNS names resolve naturally.
# ============================================================================

.PHONY: dev-install-core
dev-install-core: lint kind-create install-postgres install-stack-pg-secret
	@echo -n "🛠️  Dev install Core           ... "
	@helm upgrade --install core charts/core \
		--namespace default \
		--set postgresql.auth.existingSecret=opennms-stack-pg \
		1>/dev/null
	@echo "$(OK)"
	@echo ""
	@echo "  Access the Core WebUI:"
	@echo "    kubectl port-forward -n default svc/core 8980:8980"
	@echo "    open http://127.0.0.1:8980/opennms/"
	@echo ""
	@echo "  Watch startup:"
	@echo "    kubectl get pods -n default -l app.kubernetes.io/instance=core -w"

.PHONY: dev-uninstall-core
dev-uninstall-core: kind-create
	@echo -n "🧼 Uninstalling core release   ... "
	@helm uninstall core --namespace default --ignore-not-found 1>/dev/null
	@echo "$(OK)"

.PHONY: dev-install-sentinel
dev-install-sentinel: lint kind-create install-postgres install-stack-pg-secret install-kafka install-elasticsearch
	@echo -n "🛠️  Dev install Sentinel       ... "
	@helm upgrade --install sentinel charts/sentinel \
		--namespace default \
		--set postgresql.host=cluster-helm-lint-rw.default.svc.cluster.local \
		--set postgresql.auth.existingSecret=opennms-stack-pg \
		--set kafka.bootstrapServers=kafka.default.svc.cluster.local:9092 \
		--set elasticsearch.url=http://elasticsearch.default.svc.cluster.local:9200 \
		1>/dev/null
	@echo "$(OK)"
	@echo ""
	@echo "  Access the Sentinel Karaf shell:"
	@echo "    kubectl port-forward -n default svc/sentinel 8301:8301"
	@echo "    ssh -p 8301 admin@127.0.0.1   # default password: admin"

.PHONY: dev-uninstall-sentinel
dev-uninstall-sentinel: kind-create
	@echo -n "🧼 Uninstalling sentinel       ... "
	@helm uninstall sentinel --namespace default --ignore-not-found 1>/dev/null
	@echo "$(OK)"

.PHONY: dev-install-minion
dev-install-minion: lint kind-create install-kafka
	@echo -n "🛠️  Dev install Minion         ... "
	@helm upgrade --install minion charts/minion \
		--namespace default \
		--set location=dev \
		--set kafka.bootstrapServers=kafka.default.svc.cluster.local:9092 \
		1>/dev/null
	@echo "$(OK)"
	@echo ""
	@echo "  Access the Minion Karaf shell:"
	@echo "    kubectl port-forward -n default svc/minion 8201:8201"
	@echo "    ssh -p 8201 admin@127.0.0.1   # default password: admin"

.PHONY: dev-uninstall-minion
dev-uninstall-minion: kind-create
	@echo -n "🧼 Uninstalling minion         ... "
	@helm uninstall minion --namespace default --ignore-not-found 1>/dev/null
	@echo "$(OK)"

.PHONY: dev-install-stack
dev-install-stack: lint kind-create install-postgres install-stack-pg-secret install-kafka install-elasticsearch
	@echo -n "🛠️  Updating umbrella deps      ... "
	@helm dep update charts/opennms-stack 1>/dev/null
	@echo "$(OK)"
	@echo -n "🛠️  Dev install opennms-stack   ... "
	@helm upgrade --install opennms-stack charts/opennms-stack \
		--namespace default \
		--set global.postgresql.host=cluster-helm-lint-rw.default.svc.cluster.local \
		--set global.postgresql.auth.existingSecret=opennms-stack-pg \
		--set global.kafka.bootstrapServers=kafka.default.svc.cluster.local:9092 \
		--set global.elasticsearch.url=http://elasticsearch.default.svc.cluster.local:9200 \
		1>/dev/null
	@echo "$(OK)"
	@echo ""
	@echo "  Access the Core WebUI:"
	@echo "    kubectl port-forward -n default svc/opennms-stack-core 8980:8980"
	@echo "    open http://127.0.0.1:8980/opennms/"
	@echo ""
	@echo "  Watch the stack come up:"
	@echo "    kubectl get pods -n default -l app.kubernetes.io/instance=opennms-stack -w"

.PHONY: dev-uninstall-stack
dev-uninstall-stack: kind-create
	@echo -n "🧼 Uninstalling opennms-stack  ... "
	@helm uninstall opennms-stack --namespace default --ignore-not-found 1>/dev/null
	@echo "$(OK)"

.PHONY: dev-uninstall-all
dev-uninstall-all: dev-uninstall-stack dev-uninstall-core dev-uninstall-sentinel dev-uninstall-minion clean-elasticsearch clean-kafka clean-stack-pg-secret clean-postgres
	@echo "$(OK) all dev releases and stubs torn down"

.PHONY: dev-clean
dev-clean: dev-uninstall-all kind-delete
	@echo "$(OK) kind cluster destroyed"

.PHONY: readme
readme: deps-docs
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
	@echo -n "⏱️ Waiting for primary pod    ... "
	@for i in $$(seq 1 60); do \
		kubectl get pod/cluster-helm-lint-1 -n default >/dev/null 2>&1 && break; \
		sleep 2; \
	done
	@kubectl get pod/cluster-helm-lint-1 -n default >/dev/null 2>&1 || { echo "$(ERROR) timed out waiting for cluster-helm-lint-1 to be created"; exit 1; }
	@echo "$(OK)"
	@echo -n "⏱️ Waiting for startup        ... "
	@kubectl wait --for=condition=ready --timeout=300s pod/cluster-helm-lint-1 -n default 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@echo "$(OK)"

.PHONY: clean-postgres
clean-postgres: kind-create
	@echo -n "🧼 Deleting Postgres Cluster  ... "
	@kubectl delete -f stubs/postgres/pg-database.yaml 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@kubectl delete -f stubs/postgres/secret-superuser.yaml 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@kubectl delete -f stubs/postgres/secret-opennms-core-db.yaml 2>&1>>$(CNPG_INSTALL_LOGOUTPUT) || { cat $(CNPG_INSTALL_LOGOUTPUT); exit 1; }
	@echo "$(OK)"

.PHONY: install-stack-pg-secret
install-stack-pg-secret: kind-create
	@echo -n "🚀 Create stack PG secret     ... "
	@kubectl apply -f stubs/postgres/secret-opennms-stack.yaml 1>/dev/null
	@echo "$(OK)"

.PHONY: clean-stack-pg-secret
clean-stack-pg-secret: kind-create
	@echo -n "🧼 Deleting stack PG secret   ... "
	@kubectl delete -f stubs/postgres/secret-opennms-stack.yaml --ignore-not-found 1>/dev/null
	@echo "$(OK)"

.PHONY: install-kafka
install-kafka: kind-create
	@echo -n "🚀 Install Kafka stub         ... "
	@kubectl apply -f stubs/kafka/kafka.yaml 1>/dev/null
	@echo "$(OK)"
	@echo -n "⏱️ Waiting for Kafka ready    ... "
	@kubectl wait --for=condition=available --timeout=300s deployment/kafka -n default 1>/dev/null
	@echo "$(OK)"

.PHONY: clean-kafka
clean-kafka: kind-create
	@echo -n "🧼 Deleting Kafka stub        ... "
	@kubectl delete -f stubs/kafka/kafka.yaml --ignore-not-found 1>/dev/null
	@echo "$(OK)"

.PHONY: install-elasticsearch
install-elasticsearch: kind-create
	@echo -n "🚀 Install Elasticsearch stub ... "
	@kubectl apply -f stubs/elasticsearch/elasticsearch.yaml 1>/dev/null
	@echo "$(OK)"
	@echo -n "⏱️ Waiting for ES ready       ... "
	@kubectl wait --for=condition=available --timeout=300s deployment/elasticsearch -n default 1>/dev/null
	@echo "$(OK)"

.PHONY: clean-elasticsearch
clean-elasticsearch: kind-create
	@echo -n "🧼 Deleting Elasticsearch stub... "
	@kubectl delete -f stubs/elasticsearch/elasticsearch.yaml --ignore-not-found 1>/dev/null
	@echo "$(OK)"
