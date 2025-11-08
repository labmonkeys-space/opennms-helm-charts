.DEFAULT_GOAL := lint

SHELL               := /bin/bash -o nounset -o pipefail -o errexit
DATE                := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ") # Date format RFC3339
OK                  := "[ 👍 ]"
ERROR               := "[ ❌ ]"
REQUIRED_BINS   	:= ct kind
BUILD_DIR           := build
LINT_LOG            := $(BUILD_DIR)/lint.log

.PHONY: help
help:
	@echo "Available make targets:"
	@echo "  lint        - Lint Helm charts in the charts/ directory"

build:
	@echo -n "👩‍🔧 Create build directory     ... "
	@mkdir -p build
	@echo "$(OK)"

.PHONY: deps
deps:
	$(foreach bin,$(REQUIRED_BINS),\
		$(if $(shell command -v $(bin) 2> /dev/null),$(info 👮 $(bin) 🌈 ),$(error Please install `$(bin)`)))

.PHONY: lint
lint: deps build
	@echo -n "👩‍🔬 Linting Helm charts        ... "
	@ct lint --debug --chart-dirs charts --validate-maintainers=false 2>&1 > $(LINT_LOG)
	@echo "$(OK)"

.PHONY: kind-create
kind-create: deps
	@if kind get clusters | grep -q helm-lint; then \
		echo "👩‍🔧 Kind cluster 'helm-lint' already exists. Skipping creation."; \
		exit 0; \
	else \
		echo -n "👩‍🔧 Creating kind cluster      ... "; \
		kind create cluster --name helm-lint --wait 5m; \
		echo "$(OK)"; \
	fi

.PHONY: kind-delete
kind-delete: deps
	@echo -n "👩‍🔧 Deleting kind cluster      ... "
	@kind delete cluster --name helm-lint
	@echo "$(OK)"

.PHONY: install-core
install-core: kind-create
	@echo -n "🚀 Intall Helm Chart Core     ... "
	@ct install --charts charts/core
	@echo "$(OK)"

.PHONY: install-minion
install-minion: kind-create
	@echo -n "🚀 Intall Helm Chart Minion   ... "
	@ct install --charts charts/minion
	@echo "$(OK)"

.PHONY: install-sentinel
install-sentinel: kind-create
	@echo -n "🚀 Intall Helm Chart Sentinel ... "
	@ct install --charts charts/sentinel
	@echo "$(OK)"

.PHONY: install-all
install-all: install-core install-minion install-sentinel
