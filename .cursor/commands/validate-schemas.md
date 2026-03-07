# validate-schemas

## Purpose

Validate YAML schema files in `docs/schemas/` for correctness and consistency.

## When to use

- After modifying any file in `docs/schemas/`
- After creating or modifying S7 classes that correspond to schemas
- As part of `make ci-fast` or `make ci`

## Commands

```bash
# Validate all schemas
make validate-schemas

# JSON output (for programmatic processing)
Rscript tools/validate-schemas.R --json
```

## What it checks

### Phase A (current -- lightweight)

1. **YAML syntax**: all `*.schema.yaml` files parse without error
2. **Top-level structure**: expected root keys exist per schema type
3. **Filename convention**: files follow `*.schema.yaml` pattern

### After WP3b (S7 validators -- future)

The same `make validate-schemas` target will delegate to S7 class constructors, adding:

4. **Required fields**: all mandatory fields per schema type
5. **Cross-references**: knowledge topics match decision graph nodes, transition targets exist
6. **Reachability**: all nodes reachable from entry_node
7. **ADR references**: referenced ADR files exist

## Error resolution patterns

| Error | Fix |
|---|---|
| YAML parse error | Fix YAML syntax (indentation, quoting) |
| Missing top-level key | Add required key per schema spec |
| Unrecognised schema type | Rename file to match `*.schema.yaml` pattern or add rule |

## Output (response format)

- **Checked**: number of schema files validated
- **Errors**: count and details of each error
- **Status**: pass / fail

## Related rules

- `@.cursor/rules/quality-policy.mdc`
