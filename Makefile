# bridle -- AI knowledge harness generation framework
# Run `make help` to see available targets.

# === Container Runtime Detection ===
# Prefer podman, fall back to docker. Override: make RUNTIME=docker ...
RUNTIME := $(or \
  $(shell command -v podman >/dev/null 2>&1 && echo podman),\
  $(shell command -v docker >/dev/null 2>&1 && echo docker))

# Compose support detection (optional; targets have direct fallbacks)
HAS_COMPOSE := $(shell $(RUNTIME) compose version >/dev/null 2>&1 && echo 1 || echo 0)

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
	check check-fast test lint format document coverage site install clean \
	ci ci-fast ci-pr doctor doctor-json validate-schemas \
	changed-lint changed-test test-json lint-json scaffold-test

# === Help ===

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# === Container Management ===

container-build: ## Build development container
ifeq ($(HAS_COMPOSE),1)
	$(RUNTIME) compose -f $(CONTAINER_DIR)/compose.yaml build
else
	$(RUNTIME) build -t $(IMAGE_NAME) -f $(CONTAINER_DIR)/Containerfile .
endif

container-up: ## Start development container (detached)
ifeq ($(HAS_COMPOSE),1)
	$(RUNTIME) compose -f $(CONTAINER_DIR)/compose.yaml up -d
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
	$(RUNTIME) compose -f $(CONTAINER_DIR)/compose.yaml down
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
	$(RSCRIPT) -e "devtools::check()"

test: _require_container ## Run tests
	$(RSCRIPT) -e "devtools::test()"

lint: _require_container ## Run lintr
	$(RSCRIPT) -e "lintr::lint_package()"

format: _require_container ## Auto-format with styler
	$(RSCRIPT) -e "styler::style_pkg()"

document: _require_container ## Generate documentation with roxygen2
	$(RSCRIPT) -e "devtools::document()"

coverage: _require_container ## Measure test coverage
	$(RSCRIPT) -e "print(covr::package_coverage())"

site: _require_container ## Build pkgdown site
	$(RSCRIPT) -e "pkgdown::build_site()"

install: _require_container ## Install package locally
	$(RSCRIPT) -e "devtools::install()"

check-fast: _require_container ## Quick R CMD check (no manual/vignettes)
	$(RSCRIPT) -e "devtools::check(manual = FALSE, vignettes = FALSE)"

scaffold-test: _require_container ## Create test skeleton (usage: make scaffold-test FILE=R/foo.R)
	@if [ -z "$(FILE)" ]; then echo "Usage: make scaffold-test FILE=R/foo.R"; exit 1; fi
	$(RSCRIPT) -e "usethis::use_test('$$(basename $(FILE) .R)')"

# === Integrated CI Targets ===

ci: validate-schemas lint test check ## Full CI: validate-schemas + lint + test + check

ci-fast: validate-schemas lint ## Fast gate: validate-schemas + lint

ci-pr: ci document ## PR-ready gate: full CI + document (run before pr-create)

doctor: ## Check development environment
	@bash tools/doctor.sh

doctor-json: ## Check development environment (JSON output)
	@bash tools/doctor.sh --json

validate-schemas: _require_container ## Validate YAML schemas
	$(RSCRIPT) tools/validate-schemas.R

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
