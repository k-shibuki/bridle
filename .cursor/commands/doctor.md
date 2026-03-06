# doctor

## Purpose

Check the development environment health (host + container).

## When to use

- Before starting any implementation work
- After setting up the environment for the first time
- When encountering unexpected failures that may be environment-related

## Commands

```bash
# Terminal output (human-readable)
make doctor

# JSON output (machine-readable, for programmatic use)
make doctor-json
```

## What it checks

### Host side (no R required)

- `podman` command availability
- `podman compose` availability
- `git` availability
- Container `bridle-dev` running status
- RStudio Server responsiveness (http://localhost:8787)

### Container side (via podman exec)

- R version (>= 4.1.0)
- renv availability
- Required R packages: devtools, testthat, lintr, styler, S7, cli, rlang, yaml, roxygen2
- Optional R packages: covr, ellmer, jsonlite, ragnar, vitals, mcptools, reprex, pkgdown, withr

## First-time setup

If the container is not yet built:

```bash
make container-build    # Build from containers/Containerfile
make container-up       # Start container
make renv-init          # Initialize renv (creates renv.lock)
make doctor             # Verify everything
```

## Output (response format)

- **Status**: pass / fail (with exit code)
- **Critical issues**: list of missing required components
- **Warnings**: list of missing optional components
- **Recommended action**: what to install or fix

## Related rules

- `@.cursor/rules/ai-guardrails.mdc`
