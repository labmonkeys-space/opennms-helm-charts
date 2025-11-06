.DEFAULT_GOAL := lint

SHELL               := /bin/bash -o nounset -o pipefail -o errexit
DATE                := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ") # Date format RFC3339
OK                  := "[ 👍 ]"
ERROR               := "[ ❌ ]"
REQUIRED_BINS   	:= ct
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
		$(if $(shell command -v $(bin) 2> /dev/null),$(info '👮' $(bin) '🌈' ),$(error Please install `$(bin)`)))

.PHONY: lint
lint: deps build
	@echo -n "👮 Linting Helm charts        ... "
	@ct lint --debug --chart-dirs charts --validate-maintainers=false 2>&1 > $(LINT_LOG)
	@echo "$(OK)"
