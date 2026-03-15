# doctor

## Reads
- `workflow-policy.mdc` § Container Prerequisite

## Sense
None required.

## Act

1. `make doctor` (human-readable) or `make doctor-json` (machine-readable).
2. If hooks missing: doctor auto-installs via `tools/install-hooks.sh`.
3. If container not running: `make container-build` then `make container-start`.
4. If renv out of sync: `make package-restore`.

### First-time setup

```bash
make container-build
make container-start
make package-init
make doctor
```

## Output
- Status: pass/fail
- Critical issues: missing required components
- Warnings: missing optional components
- Recommended action

## Guard
- `HS-LOCAL-VERIFY`: doctor ensures hooks are installed
