# bridle -- AI knowledge harness generation framework
# Run `make help` to see available targets.

# === Container Runtime Detection ===
# Prefer podman, fall back to docker. Override: make RUNTIME=docker ...
RUNTIME := $(or \
  $(shell command -v podman >/dev/null 2>&1 && echo podman),\
  $(shell command -v docker >/dev/null 2>&1 && echo docker))

# Compose tool detection: podman-compose (standalone) or docker compose (V2 subcommand)
COMPOSE := $(or \
  $(shell command -v podman-compose >/dev/null 2>&1 && echo podman-compose),\
  $(shell docker compose version >/dev/null 2>&1 && echo docker compose))
HAS_COMPOSE := $(if $(COMPOSE),1,0)

CONTAINER_NAME := bridle-dev
IMAGE_NAME     := bridle-dev:latest
WORKDIR        := /home/rstudio/bridle
CONTAINER_DIR  := containers

# When running inside the container (e.g. CI), set BRIDLE_IN_CONTAINER=1
# to bypass container exec and call Rscript directly.
ifdef BRIDLE_IN_CONTAINER
  RSCRIPT := Rscript
else
  RSCRIPT := $(RUNTIME) exec -w $(WORKDIR) $(CONTAINER_NAME) Rscript
endif

.PHONY: help \
	container-build container-up container-down container-shell rstudio \
	renv-init renv-restore renv-snapshot \
	check check-fast test lint format format-check document coverage coverage-check site install clean \
	ci ci-fast ci-pr pr-ready doctor doctor-json validate-schemas \
	changed-lint changed-test test-json lint-json scaffold-test scaffold-class \
	status new-branch install-hooks \
	kb-manifest kb-validate kb-new

# === Help ===

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# === Container Management ===

container-build: ## Build development container
ifeq ($(HAS_COMPOSE),1)
	$(COMPOSE) -f $(CONTAINER_DIR)/compose.yaml build
else
	$(RUNTIME) build -t $(IMAGE_NAME) -f $(CONTAINER_DIR)/Containerfile .
endif

container-up: ## Start development container (detached)
ifeq ($(HAS_COMPOSE),1)
	$(COMPOSE) -f $(CONTAINER_DIR)/compose.yaml up -d
else
	@if $(RUNTIME) inspect $(CONTAINER_NAME) --format '{{.State.Running}}' 2>/dev/null | grep -q true; then \
		echo "Container '$(CONTAINER_NAME)' is already running."; \
	else \
		$(RUNTIME) rm $(CONTAINER_NAME) 2>/dev/null || true; \
		$(RUNTIME) run -d \
			--name $(CONTAINER_NAME) \
			-p 8787:8787 \
			-v "$$(pwd):$(WORKDIR):Z" \
			-e DISABLE_AUTH=true \
			$(IMAGE_NAME); \
	fi
endif

container-down: ## Stop development container
ifeq ($(HAS_COMPOSE),1)
	$(COMPOSE) -f $(CONTAINER_DIR)/compose.yaml down
else
	-$(RUNTIME) stop $(CONTAINER_NAME) 2>/dev/null
	-$(RUNTIME) rm $(CONTAINER_NAME) 2>/dev/null
endif

container-shell: ## Open R console in container
	$(RUNTIME) exec -it -w $(WORKDIR) $(CONTAINER_NAME) R

rstudio: ## Show RStudio Server URL
	@echo "RStudio Server: http://localhost:8787"

# === renv Package Management ===

renv-init: _require_container ## Initialize renv (first time only)
	$(RSCRIPT) -e "renv::init()"

renv-restore: _require_container ## Restore packages from renv.lock
	$(RSCRIPT) -e "renv::restore()"

renv-snapshot: _require_container ## Update renv.lock from installed packages
	$(RSCRIPT) -e "renv::snapshot()"

# === Quality Gates ===

check: _require_container ## Run R CMD check (primary quality gate)
	$(RSCRIPT) -e "devtools::check(env_vars = c('_R_CHECK_SYSTEM_CLOCK_' = '0'))"

test: _require_container ## Run tests
	$(RSCRIPT) -e "devtools::test()"

lint: _require_container ## Run lintr (with package namespace loaded for accurate object_usage_linter)
	$(RSCRIPT) -e "pkgload::load_all('.', quiet = TRUE); lintr::lint_package()"

format: _require_container ## Auto-format with styler
	$(RSCRIPT) -e "styler::style_pkg()"

format-check: _require_container ## Check formatting without modifying files (dry-run)
	$(RSCRIPT) -e "out <- styler::style_pkg(dry = 'on'); if (any(out[['changed']])) stop('Formatting issues found')"

document: _require_container ## Generate documentation with roxygen2
	$(RSCRIPT) -e "devtools::document()"

coverage: _require_container ## Measure test coverage
	$(RSCRIPT) -e "print(covr::package_coverage())"

# Coverage threshold SSOT: test-strategy.mdc § Coverage Threshold Policy
COVERAGE_THRESHOLD ?= 80

coverage-check: _require_container ## Verify test coverage meets threshold (default 80%)
	$(RSCRIPT) -e "\
	  cov <- covr::package_coverage(); \
	  pct <- covr::percent_coverage(cov); \
	  cat(sprintf('Line coverage: %.1f%% (threshold: $(COVERAGE_THRESHOLD)%%)\n', pct)); \
	  if (pct < $(COVERAGE_THRESHOLD)) stop(sprintf('Coverage %.1f%% is below threshold $(COVERAGE_THRESHOLD)%%', pct))"

site: _require_container ## Build pkgdown site
	$(RSCRIPT) -e "pkgdown::build_site()"

install: _require_container ## Install package locally
	$(RSCRIPT) -e "devtools::install()"

check-fast: _require_container ## Quick R CMD check (no manual/vignettes)
	$(RSCRIPT) -e "devtools::check(manual = FALSE, vignettes = FALSE, env_vars = c('_R_CHECK_SYSTEM_CLOCK_' = '0'))"

scaffold-test: _require_container ## Create test skeleton (usage: make scaffold-test FILE=R/foo.R)
	@if [ -z "$(FILE)" ]; then echo "Usage: make scaffold-test FILE=R/foo.R"; exit 1; fi
	$(RSCRIPT) -e "usethis::use_test('$$(basename $(FILE) .R)')"

scaffold-class: _require_container ## Generate S7 class from schema (usage: make scaffold-class SCHEMA=docs/schemas/foo.schema.yaml)
	@if [ -z "$(SCHEMA)" ]; then echo "Usage: make scaffold-class SCHEMA=docs/schemas/foo.schema.yaml"; exit 1; fi
	$(RSCRIPT) tools/scaffold-class.R $(SCHEMA)

# === Integrated CI Targets ===

renv-check: _require_container ## Verify renv.lock is in sync with DESCRIPTION
	$(RSCRIPT) -e "s <- renv::status(dev = TRUE); if (!isTRUE(s[['synchronized']])) stop('renv out of sync. Run: make renv-snapshot')"

ci: validate-schemas lint test check ## Full CI: validate-schemas + lint + test + check

ci-fast: validate-schemas renv-check kb-validate lint ## Fast gate: validate-schemas + renv-check + kb-validate + lint

ci-pr: ci document ## PR-ready gate: full CI + document (run before pr-create)

pr-ready: validate-schemas format-check lint test check document ## Full pre-PR gate (format-check + CI + docs)

doctor: ## Check development environment
	@bash tools/doctor.sh

doctor-json: ## Check development environment (JSON output)
	@bash tools/doctor.sh --json

validate-schemas: _require_container ## Validate YAML schemas
	$(RSCRIPT) tools/validate-schemas.R

# === Project Status / Branch Management ===

status: ## Show git + container status
	@echo "=== Git ===" && git status --short --branch
	@echo "=== Container ===" && $(RUNTIME) inspect $(CONTAINER_NAME) --format '{{.State.Status}}' 2>/dev/null || echo "not found"

install-hooks: ## Install git hooks (pre-commit, pre-push, commit-msg)
	@bash tools/install-hooks.sh --force

new-branch: ## Create feature branch (usage: make new-branch PREFIX=feat ISSUE=42 DESC=short-description)
	@if [ -z "$(ISSUE)" ] || [ -z "$(DESC)" ]; then \
		echo "Usage: make new-branch PREFIX=feat ISSUE=42 DESC=short-description"; exit 1; fi
	git checkout -b $(or $(PREFIX),feat)/$(ISSUE)-$(DESC)

# === Differential / Machine-Readable Targets ===

changed-lint: _require_container ## Lint only changed R files
	@files=$$(bash tools/changed-files.sh "R/*.R"); \
	if [ -n "$$files" ]; then \
		$(RSCRIPT) -e "for (f in commandArgs(TRUE)) print(lintr::lint(f))" $$files; \
	else \
		echo "No changed R files to lint"; \
	fi

changed-test: _require_container ## Run tests related to changed files (falls back to full suite)
	@filter=$$(bash tools/changed-files.sh "R/*.R" "tests/testthat/*.R" \
		| sed -n 's|.*/test-\(.*\)\.R$$|\1|p' \
		| paste -sd'|'); \
	if [ -n "$$filter" ]; then \
		echo "Running scoped tests: $$filter"; \
		$(RSCRIPT) -e "devtools::test(filter = '$$filter')"; \
	else \
		echo "No changed test files detected -- running full test suite"; \
		$(RSCRIPT) -e "devtools::test()"; \
	fi

test-json: _require_container ## Run tests with JUnit XML output
	$(RSCRIPT) -e "devtools::test(reporter = testthat::JunitReporter\$$new(file = 'test-results.xml'))"

lint-json: _require_container ## Lint with JSON output
	$(RSCRIPT) -e "writeLines(jsonlite::toJSON(lintr::lint_package(), auto_unbox = TRUE), 'lint-results.json')"

# === Knowledge Base Management ===

kb-manifest: ## Regenerate knowledge-index.mdc from atom frontmatter
	@sh tools/kb-manifest.sh

kb-validate: ## Validate knowledge base consistency (naming, frontmatter, index sync)
	@sh tools/kb-validate.sh

kb-new: ## Scaffold new knowledge atom (usage: make kb-new NAME=test--new-topic)
	@sh tools/kb-new.sh NAME=$(NAME)

# === Cleanup ===

clean: ## Clean build artifacts
	rm -rf man/ docs/ *.Rcheck *.tar.gz test-results.xml lint-results.json

# === Internal ===

_require_container:
ifndef BRIDLE_IN_CONTAINER
	@$(RUNTIME) inspect $(CONTAINER_NAME) --format '{{.State.Running}}' 2>/dev/null \
		| grep -q true \
		|| (printf '\033[0;31mError: Container "%s" is not running.\033[0m\n' "$(CONTAINER_NAME)" \
		    && echo "Run 'make container-up' first." && exit 1)
endif
