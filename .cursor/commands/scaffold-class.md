# scaffold-class

## Reads
- `docs/adr/0001-use-s7-class-system.md` (ADR-0001: S7 class system)
- `quality-policy.mdc` § Type Strictness (S7) (no `class_any`, explicit types, validators)

## Sense

Read the target schema file (`docs/schemas/*.schema.yaml`).

## Act

1. `make scaffold-class SCHEMA=docs/schemas/<name>.schema.yaml` — generates `R/{name}.R` and `tests/testthat/test-{name}.R`.
2. Refine generated code: replace `class_list` TODO comments with dedicated S7 classes, add cross-field validator logic, fill test skeletons.
3. Ensure `#' @include <dependency>.R` for cross-file S7 class references.

### Type mapping

| YAML type | S7 property type |
|-----------|-----------------|
| string | `class_character` |
| integer | `class_integer` |
| number | `class_double` |
| boolean | `class_logical` |
| nullable string | `new_union(class_character, class_missing)` |
| enum | `class_character` + validator with `match.arg()` |
| nested object | Another S7 class |

## Output
- Class file: `R/{name}.R`
- Test file: `tests/testthat/test-{name}.R`
- Properties and validators summary

## Guard
- `class_any` prohibition per `quality-policy.mdc`
