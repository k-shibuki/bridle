# Knowledge Guidelines

## What to include

Knowledge atoms capture project-specific semantics that help the agent
make better decisions. They are advisory — they inform reasoning but
carry no enforcement power.

Appropriate content:

- **Patterns**: recurring solutions to project-specific problems
  (e.g., S7 cross-file reference pattern, layered mock strategy)
- **Gotchas**: non-obvious traps specific to this project's technology
  stack (e.g., NULL assignment trap in R, post-rebase Collate drift)
- **Domain heuristics**: project-specific judgment guidelines
  (e.g., review severity interpretation, CI failure classification)
- **Architectural constraints**: consequences of ADR decisions that
  affect daily development (e.g., S7 `@include` directive requirements)
- **Recovery playbooks**: step-by-step recovery from known failure modes
  (e.g., git quick recovery, squash-merge dependent branch)

## What to exclude

Knowledge atoms must NOT contain:

- **CLI commands meant to be executed**: `gh api ...`, `git rebase ...`,
  `make ...` as procedures. These belong in Evidence targets or Procedure.
- **API call sequences**: multi-step API interactions are Procedure, not
  Knowledge.
- **Transient operational know-how**: information that changes frequently
  (specific version numbers, current CI job names) — these belong in
  Evidence or configuration.
- **Policy declarations**: MUST / MUST NOT rules belong in Principle.
  Knowledge may reference Principle but must not restate it.
- **Workflow steps**: numbered procedural steps belong in Procedure.

## Format

Each knowledge atom is a single Markdown file in `.cursor/knowledge/`
following these conventions:

- **Naming**: `{category}--{topic}.md` (lowercase, double-hyphen separator)
- **Categories**: `test`, `r`, `lint`, `debug`, `ci`, `git`, `agent`,
  `review`, `workflow`, `controls`
- **Frontmatter**: YAML with `trigger:` field containing 3–6 keywords
- **Self-contained**: the atom must be independently useful without
  reading other files (Related links are supplementary, not required)
- **Indivisibility test**: can the content be expressed as a single
  question with a single answer? If yes, it is properly atomic.

## Anti-pattern: execution in Knowledge

When a knowledge atom contains executable commands (`gh`, `git`, `make`),
it transforms from advisory reference into implicit procedure. This causes:

1. **Drift**: the command syntax changes but the Knowledge atom is not
   updated (no Guard enforces Knowledge accuracy)
2. **Duplication**: the same command appears in Knowledge, Procedure,
   and Evidence — violating SSOT
3. **Boundary violation**: Knowledge crosses into Procedure's
   responsibility, undermining the component model

The remedy is to extract executable content into Evidence targets
(for observation) or Procedure (for actions), leaving Knowledge with
only the semantic context: *why* something matters, *when* it applies,
*what* to watch for — never *how* to execute.
