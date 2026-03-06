## Summary

<!-- 1-3 bullet points summarizing the change -->

-

## Related ADR / Issue

<!-- Reference relevant ADR(s) or issues. Required for feat/refactor PRs. -->

- ADR: <!-- e.g. docs/adr/0002-decision-graph-flow-control.md -->
- Issue: <!-- e.g. #42 -->

## Change Type

- [ ] feat: New feature
- [ ] fix: Bug fix
- [ ] refactor: Code restructuring
- [ ] docs: Documentation only
- [ ] test: Test only
- [ ] ci: CI/build changes
- [ ] chore: Other

## Schema Impact

<!-- Does this change affect YAML schemas or S7 class definitions? -->

- [ ] No schema impact
- [ ] Schema updated (`docs/schemas/`)
- [ ] S7 class updated (`R/`)
- [ ] Both schema and S7 updated (consistency verified)

## Test Evidence

<!-- How was this tested? Required for code changes. -->

- [ ] `make test` passes
- [ ] `make check` passes (0 errors, 0 warnings, 0 notes)
- [ ] `make validate-schemas` passes
- [ ] New tests added for new functionality
- [ ] Coverage maintained or improved

## Review Checklist

- [ ] Code follows project conventions (S7 classes, roxygen2, English comments)
- [ ] No prohibited patterns (`suppressWarnings` without justification, `class_any`, etc.)
- [ ] ADR compliance verified
- [ ] `make document` run if roxygen2 tags changed
