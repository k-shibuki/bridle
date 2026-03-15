<!-- sync-check: .cursor/commands/pr-review.md Step 7 categories -->
<!-- last-synced: 2026-03-10 -->
# AGENTS.md

This file configures AI code reviewers that operate on this repository
(CodeRabbit Pro/OSS as primary, Codex Cloud as supplementary). Cursor
uses `.cursor/rules/` and `.cursor/commands/` instead but shares these
review guidelines via the knowledge base.

## Project context

**bridle** is an R package (S7 class system, MIT license) that provides a
knowledge-harness framework for guiding LLM-driven statistical analysis.
Key technologies: S7 classes, cli, httr2, yaml, ellmer.

Architecture decisions live in `docs/adr/`. The most relevant ADRs for
review are:

- ADR-0001: S7 class system — all domain classes use `S7::new_class()`
- ADR-0002: Decision graph flow control
- ADR-0004: Scanner three-layer analysis
- ADR-0008: Scanner resilience (confidence grading, dry-run fuzzing)

Quality is enforced by CI: lintr, styler, R CMD check (0 errors/warnings/notes),
covr (>= 80% coverage), and YAML schema validation.

## Review guidelines

### Severity policy

Only flag **P0** and **P1** issues in reviews.

- **P0 (blocking)**: logic bugs, incorrect control flow, type-safety
  violations, security issues, missing or broken tests for changed code.
- **P1 (significant)**: ADR non-compliance, naming convention violations,
  duplicated logic, missing traceability (`Closes #N` in PR body,
  `Refs: #N` in commit footers), inadequate error handling, missing
  boundary-value test cases.

Do NOT flag:

- **Style or formatting** — lintr (`line_length_linter(120)`,
  `object_name_linter` with snake_case/CamelCase) and styler enforce
  formatting automatically in CI. Do not duplicate their work.
- **Typos in comments** — unless they appear in user-facing messages or
  documentation.
- **Subjective preferences** — e.g. "I would name this differently" when the
  existing name follows project conventions.

### S7 type safety (P0)

- Every S7 property MUST have an explicit type. `class_any` is prohibited
  unless the property genuinely accepts multiple unrelated types.
- Use `S7::new_union()` for known union types instead of `class_any`.
- Property validators must enforce constraints that types alone cannot
  express (value ranges, cross-field dependencies, format patterns).
- Cross-file S7 class references require `#' @include <dependency>.R` in
  the roxygen header — alphabetical file order is unreliable.

### Test quality (P0 if missing, P1 if incomplete)

Flag as P0 if changed code has **no** corresponding tests. Flag as P1 if
tests exist but are incomplete:

- Positive and negative cases should be balanced.
- Boundary values: 0, min, max, +/-1, empty, NULL (omit only when
  meaningless per specification).
- Exception tests must validate both error type and message.
- New function parameters need wiring tests (parameter reaches
  implementation) and effect tests (parameter changes behavior).

### Architecture and ADR compliance (P1)

- Changes to domain classes must follow ADR-0001 (S7).
- Changes to decision graph structure must follow ADR-0002.
- Changes to the scanner must follow ADR-0004 and ADR-0008.
- YAML schemas (`docs/schemas/`) and S7 classes (`R/`) must stay
  consistent. If a schema changes, the S7 class must be updated (or a
  follow-up task created).

### Traceability (P1)

- PR body must contain `Closes #<issue>` or `Fixes #<issue>` (unless an
  exception label `no-issue` or `hotfix` is present).
- Commit messages should follow Conventional Commits format with
  `Refs: #<issue>` in the footer.
- PR title should follow Conventional Commits: `<type>(<scope>): <desc>`.

### Security (P0)

Flag any changes involving:

- Authentication or authorization logic
- Network boundaries (new external API calls, endpoint changes)
- Data retention or PII handling
- Credential management or secret handling

### NULL handling (P1)

Watch for the NULL-assignment trap: `x$field <- NULL` silently removes the
field from a list in R. This is a known source of bugs in this codebase.
Flag when NULL is assigned to a list element where the intent appears to be
setting a value.

## General guidelines

- This is an R package. Use `devtools::test()` for tests, `devtools::check()`
  for R CMD check, `lintr::lint_package()` for linting.
- The project uses renv for dependency management. `renv.lock` is committed.
- Container-based development: R commands run inside a `bridle-dev` container.
- Build targets are managed via `Makefile` (run `make help` for the list).

### Three-layer quality gate model

Quality enforcement uses three layers with increasing scope:

| Layer | Context | Purpose | Scope |
|-------|---------|---------|-------|
| Local | `pre-push` hook | Fail-fast filter | Differential: `format-verify`, `lint-changed`, `test-changed` for R; validators for schemas/renv/kb |
| PR CI | `ci.yaml` | Merge gate | Full: parallel `lint` \| `test` \| `check --no-tests` + validators |
| Main push | `R-CMD-check.yaml` | Full verification | 5-matrix R CMD check + coverage (80% threshold, auto-Issue on failure) |

Coverage is **not** on the PR critical path. It runs post-merge on main push.
See `.cursor/knowledge/ci--three-layer-gate.md` for details.

## Project knowledge base

This project maintains a shared knowledge base that all AI reviewers
(Codex, CodeRabbit) and Cursor can read. Use it to understand
project-specific patterns and avoid known pitfalls.

### Entry point

`.cursor/rules/knowledge-index.mdc` is the lookup table. It maps trigger
keywords to knowledge atom files. When reviewing code that touches a topic
listed there, read the referenced atom for detailed context.

### Knowledge atoms (`.cursor/knowledge/`)

Each atom is a focused document on a specific pattern or decision. Naming
convention: `<category>--<topic>.md`. Categories relevant to review:

- `review--*`: review patterns — includes `review--bot-operations.md` (trigger, detection, timing, polling, re-review), `review--consensus-protocol.md` (disposition, consensus, resolve), and accumulated false-positive patterns
- `test--*`: mock strategies, snapshot guidelines, scope constraints
- `lint--*`: linter quirks, nolint patterns, S7 false positives
- `r--*`: R language traps (NULL assignment, S7 include directives)
- `git--*`: branch safety, squash-merge pitfalls

### Commands (`.cursor/commands/`)

Workflow procedures readable by any agent:
- `pr-review.md`: full review procedure with category table
- `review-fix.md`: procedure for addressing review findings
- `pr-create.md`: PR creation with quality gates
