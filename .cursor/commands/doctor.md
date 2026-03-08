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

- `podman` (or `docker`) command availability
- `podman-compose` (or `docker compose`) availability
- `git` availability
- `git commit.template` configuration
- `git hook: pre-commit` — nolint annotation validator (HS#8)
- `git hook: pre-push` — pre-push verification gate (HS#2)
- `git hook: commit-msg` — commit message format validator
- Container `bridle-dev` running status

### Auto-fix: guard hooks

When guard hooks are missing, `doctor` automatically installs them via `tools/install-hooks.sh`. These are lightweight bash scripts written directly to `.git/hooks/` — no `pre-commit` framework or host-side R required. R-based quality hooks (style, lint, roxygen) run inside the container via `make` targets and in CI.

### Container side (via podman exec)

- R version (>= 4.1.0)
- renv availability
- renv lockfile sync status (warns if packages are used but not recorded, or recorded but not installed — recommends `make renv-snapshot` or `renv::status()`)
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

- `@.cursor/rules/workflow-policy.mdc`
