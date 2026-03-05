.PHONY: help check test lint style document coverage site install clean

help:        ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

check:       ## Run R CMD check (the primary quality gate)
	Rscript -e "devtools::check()"

test:        ## Run tests
	Rscript -e "devtools::test()"

lint:        ## Run lintr
	Rscript -e "lintr::lint_package()"

style:       ## Auto-format with styler
	Rscript -e "styler::style_pkg()"

document:   ## Generate documentation with roxygen2
	Rscript -e "devtools::document()"

coverage:   ## Measure test coverage
	Rscript -e "print(covr::package_coverage())"

site:       ## Build pkgdown site
	Rscript -e "pkgdown::build_site()"

install:    ## Install package locally
	Rscript -e "devtools::install()"

clean:      ## Clean build artifacts
	rm -rf man/ NAMESPACE docs/ *.Rcheck
