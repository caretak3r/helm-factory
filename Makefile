# Local entrypoints for the checks CI runs.
#
# `make lint` is byte-identical to the CI gate by construction, not by
# discipline: .github/workflows/{ci,release}.yaml invoke these same targets
# instead of carrying their own copies of the commands. Change a command here
# and CI changes with it; there is no second place to forget.
#
# Toolchain versions live in scripts/lib/tool-versions.sh, which the workflows
# source. `make tools` reports what you have against what CI pins.

SHELL := /bin/bash
.DEFAULT_GOAL := help
# Prerequisite order IS the contract here — `lint` must run its steps in the
# same order CI does, and -j would happily interleave them.
.NOTPARALLEL:

# `make render FIXTURE=stateful ARGS="--set replicaCount=3"`
FIXTURE ?= full
ARGS ?=

.PHONY: help tools check-tools shellcheck helm-lint schema-meta gate smoke smoke-packaged lint fast render golden clean

help: ## Show this help
	@echo "helm-factory — targets:"
	@grep -hE '^[a-z][a-z-]*:.*## ' $(MAKEFILE_LIST) \
	  | awk -F':.*## ' '{ printf "  %-14s %s\n", $$1, $$2 }'
	@echo
	@echo "  Definition of done: 'make lint' ends '==> PASS'. Nothing else counts."

tools: ## Report the local toolchain against the versions CI pins
	@scripts/check-tools.sh --list

check-tools: ## Fail unless every required tool is installed (silent when fine)
	@scripts/check-tools.sh

shellcheck: check-tools ## Shellcheck every script the repo ships
	shellcheck -x scripts/*.sh scripts/lib/*.sh tests/render.sh

helm-lint: check-tools ## helm lint the library chart
	helm lint platform-library/

schema-meta: check-tools ## Verify the reference values schema is valid JSON Schema
	check-jsonschema --check-metaschema platform-library/values.schema.reference.json

gate: check-tools ## THE gate: render matrix, goldens, kubeconform, guardrails
	REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh

smoke: check-tools ## Consumer scenario: scaffold a chart, build, render, kubeconform
	@scripts/scenario-consumer.sh

smoke-packaged: check-tools ## Packaged-artifact consumer scenario: package, build, render, kubeconform
	@scripts/scenario-packaged-consumer.sh

lint: shellcheck helm-lint schema-meta gate smoke smoke-packaged ## Everything CI runs, in CI's order
	@echo "==> PASS"

fast: check-tools ## Subset loop (~14s). Skips the guardrail suite — NOT done.
	FIXTURES=minimal REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh

render: check-tools ## Render one fixture the gate's way: make render FIXTURE=full ARGS="--set k=v"
	@tests/render.sh $(FIXTURE) $(ARGS)

golden: check-tools ## Accept INTENTIONAL render changes — review every diff line
	UPDATE_GOLDEN=1 REQUIRE_KUBECONFORM=1 REQUIRE_CHECK_JSONSCHEMA=1 scripts/lint-library.sh

clean: ## Remove generated fixture artifacts and the dependency cache
	rm -rf tests/.dep-cache tests/fixtures/*/charts tests/fixtures/*/Chart.lock tests/fixtures/*/values.schema.json
