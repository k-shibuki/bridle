# scaffold-class

## Purpose

Generate S7 class boilerplate from a YAML schema definition, following ADR-0001.

## When to use

- When implementing a new S7 class that corresponds to a YAML schema in `docs/schemas/`
- As the first step of `implement` for domain model classes

## Inputs (attach as `@...`)

- Target schema file (`@docs/schemas/*.schema.yaml`) (required)
- `@docs/adr/0001-use-s7-class-system.md` (recommended)
- Related ADRs for the specific schema (recommended)

## Steps

1. **Read the schema**: identify all fields, their types, and constraints.
2. **Map to S7 properties**: translate YAML field types to S7 property types.
3. **Generate class file**: create `R/{class_name}.R` with:
   - S7 class definition using `S7::new_class()`
   - Typed properties (NO `class_any` — use concrete types or `new_union()`)
   - Validator function for constraints that types alone cannot express
   - roxygen2 documentation
4. **Generate test skeleton**: create `tests/testthat/test-{class_name}.R` (or use `make scaffold-test FILE=R/{class_name}.R`).

## Type mapping reference

| YAML type | S7 property type |
|-----------|-----------------|
| string | `class_character` |
| integer | `class_integer` |
| number | `class_double` |
| boolean | `class_logical` |
| array of strings | `class_character` (vector) |
| nullable string | `new_union(class_character, class_missing)` |
| enum | `class_character` + validator with `match.arg()` |
| nested object | Another S7 class |
| list of objects | `class_list` + validator |

## Constraints

- Every property MUST have an explicit type. `class_any` is prohibited.
- Validators must check constraints that types cannot express (e.g., value ranges, cross-field dependencies).
- Follow existing patterns in `R/` if any classes already exist.

## Output (response format)

- **Class file**: path to generated `R/{class_name}.R`
- **Test file**: path to generated test skeleton
- **Properties**: list of properties with types
- **Validators**: list of validation rules implemented

## Related

- `@docs/adr/0001-use-s7-class-system.md`
- `@.cursor/rules/ai-guardrails.mdc` (type strictness policy)
- `@.cursor/commands/implement.md` (for the actual implementation)
