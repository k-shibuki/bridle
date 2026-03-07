# controls-review

## Purpose

Comprehensively audit the structural quality of the AI control system: rules, commands, knowledge atoms, README maps, and Makefile targets. This is the `issue-review` analogue for the AI governance layer — it checks reference integrity, SSOT/DRY compliance, rule contradictions, layer separation, token efficiency, and frontmatter accuracy.

## When to use

- After 3+ PRs that modified control files (triggered by `next`)
- After a major reorganization of `.cursor/` files
- When `session-retro` escalates a structural problem
- Before a milestone or phase transition
- Periodically as a hygiene check (monthly or quarterly)

## Inputs

- **Scope** (optional): `--all` (default), `--scope rules`, `--scope commands`, `--scope knowledge`, `--scope docs`, `--scope build`
- All files under `.cursor/` (auto-discovered)
- `Makefile` (auto-discovered)
- `README.md`, `docs/README.md` (auto-discovered)

## Steps

### Step 1: Inventory collection

Gather a complete manifest of all controls across the 5 control types:

| Control type | Location | Content |
|-------------|----------|---------| 
| Rules | `.cursor/rules/*.mdc` | MUST / MUST NOT policies |
| Commands | `.cursor/commands/*.md` | Step-by-step procedures |
| Knowledge | `.cursor/knowledge/*.md` | Patterns, playbooks, reference |
| Docs | `.cursor/README.md`, `README.md`, `docs/README.md` | Navigation maps, project overview |
| Build | `Makefile` | Build targets that commands reference |

```bash
# Rules
ls -la .cursor/rules/*.mdc | wc -l
wc -c .cursor/rules/*.mdc

# Commands
ls -la .cursor/commands/*.md | wc -l
wc -c .cursor/commands/*.md

# Knowledge
ls -la .cursor/knowledge/*.md | wc -l
wc -c .cursor/knowledge/*.md

# Docs
ls -la .cursor/README.md README.md docs/README.md 2>/dev/null

# Build targets
make help 2>/dev/null | wc -l
```

Record: total file count, total size, per-type breakdown.

### Step 2: Reference integrity check

Scan all control files for cross-references and verify each target exists:

**`@` references** (e.g., `@.cursor/rules/quality-policy.mdc`):
- Extract all `@<path>` patterns from every control file
- Verify each referenced file exists on disk
- Flag broken references as `REF_BROKEN`

**`§` section references** (e.g., `§ Knowledge Consultation Triggers`):
- Extract `§ <section>` patterns
- Verify the referenced section heading exists in the target file
- Flag missing sections as `SECTION_MISSING`

**YAML frontmatter accuracy**:
- For each `.mdc` rule file, verify the `description` field accurately summarizes the content
- Flag misleading descriptions as `FRONTMATTER_DRIFT`

**Makefile target references**:
- Extract all `make <target>` references from commands and rules
- Verify each target exists in the Makefile
- Flag missing targets as `TARGET_MISSING`

### Step 3: SSOT/DRY scan

For each information item below, enumerate all locations where it appears and classify:

| # | Information item | Expected SSOT location |
|---|-----------------|----------------------|
| 1 | Workflow flow diagram | `.cursor/README.md` |
| 2 | Exception types (hotfix / docs-only / no-issue) | `workflow-policy.mdc` |
| 3 | fix vs hotfix criteria | `workflow-policy.mdc` |
| 4 | Hard Stop list (HS#1-9) | `agent-safety.mdc` |
| 5 | Branch naming convention | `commit-format.mdc` |
| 6 | PR template / required sections | `pr-create.md` |
| 7 | CI polling strategy | `ci--job-dependency-graph.md` |
| 8 | Mock conventions | `test-strategy.mdc` |
| 9 | nolint decision tree / accepted patterns | `quality-policy.mdc` / `lint--nolint-accepted-patterns.md` |
| 10 | Knowledge consultation triggers | `workflow-policy.mdc` |
| 11 | Issue template structure | `issue-create.md` |
| 12 | Commit message format | `commit-format.mdc` |
| 13 | Coverage thresholds (80% line / 90% patch) | `test-strategy.mdc` |
| 14 | Container prerequisite | `workflow-policy.mdc` |
| 15 | S7 type strictness rules | `quality-policy.mdc` |

For each item:
- **SSOT_OK**: defined in one place, referenced elsewhere with pointers
- **SSOT_DUPLICATED**: substantive content repeated in multiple locations (fix: replace duplicates with `@` references)
- **SSOT_MISSING**: not defined anywhere (fix: add to expected SSOT location)
- **SSOT_CONTRADICTED**: conflicting definitions in different locations (fix: reconcile to SSOT)

### Step 4: Contradiction detection

Scan for logical contradictions across controls:

**MUST/MUST NOT exclusivity**:
- Extract all MUST and MUST NOT statements from rules
- Check for pairs that contradict (e.g., "MUST use X" vs "MUST NOT use X")
- Flag as `CONTRADICTION`

**Command procedures vs rule constraints**:
- For each command step, verify it does not violate any rule constraint
- Flag violations as `PROCEDURE_VIOLATES_RULE`

**Makefile target preconditions vs command preconditions**:
- Verify that command-documented preconditions match Makefile target dependencies
- Flag inconsistencies as `PRECONDITION_MISMATCH`

### Step 5: Layer separation check

Verify the Three-Layer architecture is maintained:

| Violation type | Detection | Example |
|---------------|-----------|---------|
| `RULE_HAS_PROCEDURE` | Rule file contains numbered steps (Step 1, Step 2, ...) | A rule file with "Step 1: Run make lint" |
| `COMMAND_HAS_POLICY` | Command file contains MUST/MUST NOT policy statements | A command file with "You MUST always..." |
| `KNOWLEDGE_HAS_POLICY` | Knowledge atom contains MUST/MUST NOT policy statements | A knowledge atom with "MUST NOT use..." |

Exceptions: Rules may reference command steps via `@` links. Commands may quote rule requirements when explaining why a step exists.

### Step 6: Token efficiency analysis

Assess the token cost of the control system:

**`alwaysApply` rules total size**:
- Sum the character count of all rules with `alwaysApply: true`
- These are loaded into every agent context — excessive size wastes tokens

**Content density per rule**:
- For each rule, calculate the ratio of actionable content (MUST/MUST NOT statements, tables, code blocks) to prose
- Flag rules with low density as `LOW_DENSITY` (candidate for compression)

**README information duplication**:
- Compare `.cursor/README.md` content with `README.md` and `docs/README.md`
- Flag significant overlaps as `README_OVERLAP`

### Step 7: Classify findings and apply

Split all findings into two categories following the `issue-review` pattern:

#### Category A: Fix immediately

Improvements that can be applied without design discussion:
- Broken `@` references (update path or remove)
- Missing `§` section targets (add section or update reference)
- Frontmatter description drift (update description)
- Missing Makefile target references (add target or update reference)
- SSOT duplications where the SSOT location is clear (replace with pointer)
- Layer separation violations where the fix is obvious (move content)

Apply fixes directly and report what changed.

#### Category B: Discussion required

Changes that require design decisions:
- SSOT contradictions (which version is correct?)
- Structural reorganization (split/merge files)
- Token efficiency trade-offs (compress vs readability)
- New SSOT items not yet catalogued
- Significant layer separation violations with unclear resolution

Present as numbered discussion points with context and options.

## Output (response format)

### Per-file report

For each control file with findings:

- **File**: `<path>` (`<type>`)
- **Findings**: list of defects with severity and classification
- **Status**: Clean / Needs fix (Cat A) / Needs discussion (Cat B)

### Cross-file report

- **Reference integrity**: broken links count, missing sections count
- **SSOT/DRY**: duplications, contradictions, missing items
- **Contradictions**: list with affected files
- **Layer separation**: violations by type
- **Token efficiency**: `alwaysApply` total size, low-density rules

### Action summary

- **Category A fixes applied**: count + list
- **Category B discussion points**: count + list
- **Overall health**: healthy / needs attention / critical issues

## Constraints

- Do NOT create or close Issues. Only edit existing control files.
- Do NOT modify R source code or tests. This command audits the control system only.
- Preserve original author intent when editing — clarify, don't rewrite.
- When editing, note changes in a comment or commit message (control files don't have Revision History sections).
- If using `--scope`, only audit the specified control type but still check cross-references to other types.
- For large control systems (50+ files), present a progress summary every 10 files.

## Related

- `@.cursor/commands/issue-review.md` — analogous command for GitHub Issues
- `@.cursor/commands/session-retro.md` — lightweight session retrospective (escalates structural problems here)
- `@.cursor/rules/knowledge-index.mdc` — auto-generated knowledge index
- `@.cursor/README.md` — control system overview and navigation map
