# controls-review

## Purpose

Comprehensively audit the structural quality of the AI development system: design documents (ADRs, schemas), rules, commands, knowledge atoms, guards, and surface assets. This is the `issue-review` analogue for the AI governance layer — it checks reference integrity, SSOT/DRY compliance, rule contradictions, component boundary separation, token efficiency, and frontmatter accuracy.

## When to use

- When `session-retro` escalates a Drift or structural problem
- After a major reorganization of `.cursor/` files
- Before a milestone or phase transition
- Periodically as a hygiene check (monthly or quarterly)
- When the user explicitly requests a control system audit

## Inputs

- **Scope** (optional): `--all` (default), `--scope design`, `--scope rules`, `--scope commands`, `--scope knowledge`, `--scope guards`, `--scope surface`
- All files under `.cursor/` (auto-discovered)
- Design documents: `docs/adr/*.md`, `docs/schemas/*.yaml` (auto-discovered)
- Guard configs: `.pre-commit-config.yaml`, `.github/workflows/*.yaml`, `tools/` (auto-discovered)
- Surface assets: `Makefile`, `README.md`, `.github/CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/` (auto-discovered)

## Steps

### Step 1: Inventory collection

Gather a complete manifest of all controls across both domains (Design + Controls):

| Domain | Component | Location | Content |
|--------|-----------|----------|---------|
| Design | ADRs | `docs/adr/*.md` | Architectural decisions (immutable records) |
| Design | Schemas | `docs/schemas/*.yaml` | Data contracts for plugin artifacts |
| Controls | Rules | `.cursor/rules/*.mdc` | MUST / MUST NOT policies |
| Controls | Commands | `.cursor/commands/*.md` | Step-by-step procedures |
| Controls | Knowledge | `.cursor/knowledge/*.md` | Patterns, playbooks, reference |
| Controls | Guards | `.pre-commit-config.yaml`, `.github/workflows/*.yaml`, `tools/` | Hooks, CI checks, enforcement scripts |
| Controls | Surface | `Makefile`, `README.md`, `.github/CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/` | Entry points, development API, navigation maps |

```bash
# Design — ADRs
ls -la docs/adr/*.md 2>/dev/null | wc -l
wc -c docs/adr/*.md 2>/dev/null

# Design — Schemas
ls -la docs/schemas/*.yaml 2>/dev/null | wc -l

# Rules
ls -la .cursor/rules/*.mdc | wc -l
wc -c .cursor/rules/*.mdc

# Commands
ls -la .cursor/commands/*.md | wc -l
wc -c .cursor/commands/*.md

# Knowledge
ls -la .cursor/knowledge/*.md | wc -l
wc -c .cursor/knowledge/*.md

# Guards
ls -la .pre-commit-config.yaml .github/workflows/*.yaml tools/*.sh 2>/dev/null

# Surface
ls -la Makefile README.md .github/CONTRIBUTING.md .github/ISSUE_TEMPLATE/*.md 2>/dev/null
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
| 1 | Workflow flow diagram | `docs/agent-control/state-model.md` |
| 2 | Exception types (hotfix / no-issue) | `workflow-policy.mdc` |
| 3 | fix vs hotfix criteria | `workflow-policy.mdc` |
| 4 | Hard Stop list (8 items, mnemonic IDs) | `agent-safety.mdc` |
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
| 16 | Guard-Policy alignment (CI checks vs Rule claims) | `agent-safety.mdc` Enforcement Tier table |
| 17 | Commit hook exemptions | `commit-format.mdc` |
| 18 | Enforcement tier accuracy (claimed vs actual) | `controls--agent-control-system.md` |
| 19 | ADR-to-schema consistency | `docs/adr/` ↔ `docs/schemas/` |
| 20 | Agent control system structure (Design + Controls) | `docs/agent-control/architecture.md` |

For each item:

- **SSOT_OK**: defined in one place, referenced elsewhere with pointers
- **SSOT_DUPLICATED**: substantive content repeated in multiple locations (fix: replace duplicates with `@` references)
- **SSOT_MISSING**: not defined anywhere (fix: add to expected SSOT location)
- **SSOT_CONTRADICTED**: conflicting definitions in different locations (fix: reconcile to SSOT)

### Step 4: Guard effectiveness audit

Verify that Guards (Deterministic and Conditionally Deterministic) correctly implement the Rules they claim to enforce. This step detects enforcement gaps where a Rule declares a constraint but the corresponding Guard does not implement it (or implements it incorrectly).

**4a. Extract Hard Stops from enforcement tier table**:

- Read `agent-safety.mdc` § Enforcement Tiers
- List all Hard Stops classified as **Deterministic** or **Cond. Deterministic**
- For each, identify the declared Guard mechanism

**4b. Verify Guard implementation logic**:

For each Deterministic/Cond. Deterministic Hard Stop, compare the Rule declaration with the Guard implementation:

| Guard | Rule source | Check |
|-------|-------------|-------|
| `pr-policy.yaml` | `agent-safety.mdc` `HS-PR-TEMPLATE`, `HS-PR-BASE`; `workflow-policy.mdc` § Label Taxonomy | Each declared check has a corresponding implementation block in the workflow script |
| `check-commit-msg.sh` | `commit-format.mdc` § Footer | Exemption logic matches declared exceptions |
| `check-nolint.sh` | `quality-policy.mdc` § Prohibited forms | Rejected patterns match the prohibited forms table |
| `pre-push.sh` | `agent-safety.mdc` `HS-LOCAL-VERIFY` | Gate conditions match the `HS-LOCAL-VERIFY` requirements |
| Branch Protection | `agent-safety.mdc` `HS-CI-MERGE` | `make evidence-branch-protection` shows `required_status_contexts` when protection is present |

Flag mismatches as `GUARD_RULE_MISMATCH`.

**4c. Verify Guard activation prerequisites**:

- **Branch Protection**: `make evidence-branch-protection` (optional `BRANCH=main`) — confirm `protection_present` and required status contexts match policy
- **Git hooks**: Check `.git/hooks/` for pre-commit, pre-push, commit-msg installation
- Flag inactive Guards as `GUARD_INACTIVE`

### Step 5: Contradiction detection

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

### Step 6: Component boundary check

Verify the Design + Controls architecture boundaries are maintained:

| Violation type | Detection | Example |
|---------------|-----------|---------|
| `DESIGN_HAS_PROCEDURE` | ADR contains step-by-step operational procedures | An ADR with "Step 1: Run make lint" |
| `CONTROL_OVERRIDES_DESIGN` | A Rule or Command contradicts an accepted ADR without a superseding ADR | A rule declaring a pattern that conflicts with an ADR decision |
| `RULE_HAS_PROCEDURE` | Rule file contains numbered steps (Step 1, Step 2, ...) | A rule file with "Step 1: Run make lint" |
| `COMMAND_HAS_POLICY` | Command file contains MUST/MUST NOT policy statements | A command file with "You MUST always..." |
| `KNOWLEDGE_HAS_POLICY` | Knowledge atom contains MUST/MUST NOT policy statements | A knowledge atom with "MUST NOT use..." |
| `GUARD_HAS_POLICY` | Guard config embeds policy prose instead of referencing Rules | A CI workflow with policy justification instead of `@` link |
| `SURFACE_HAS_PROCEDURE` | Surface asset contains step-by-step procedures instead of linking to Commands | A README with inline implementation steps |

Exceptions: Rules may reference command steps via `@` links. Commands may quote rule requirements when explaining why a step exists. Surface assets may summarize workflows for onboarding purposes. ADRs may include code examples to illustrate decisions.

### Step 7: Token efficiency analysis

Assess the token cost of the control system:

**`alwaysApply` rules total size**:

- Sum the character count of all rules with `alwaysApply: true`
- These are loaded into every agent context — excessive size wastes tokens

**Content density per rule**:

- For each rule, calculate the ratio of actionable content (MUST/MUST NOT statements, tables, code blocks) to prose
- Flag rules with low density as `LOW_DENSITY` (candidate for compression)

**Design document duplication**:

- Compare `docs/agent-control/` content with `README.md`
- Flag significant overlaps as `DESIGN_DOC_OVERLAP`

### Step 8: Classify findings and apply

Split all findings into two categories following the `issue-review` pattern:

#### Category A: Fix immediately

Improvements that can be applied without design discussion:

- Broken `@` references (update path or remove)
- Missing `§` section targets (add section or update reference)
- Frontmatter description drift (update description)
- Missing Makefile target references (add target or update reference)
- SSOT duplications where the SSOT location is clear (replace with pointer)
- Component boundary violations where the fix is obvious (move content)

Apply fixes directly and report what changed.

#### Category B: Discussion required

Changes that require design decisions:

- SSOT contradictions (which version is correct?)
- Structural reorganization (split/merge files)
- Token efficiency trade-offs (compress vs readability)
- New SSOT items not yet catalogued
- Significant component boundary violations with unclear resolution

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
- **Component boundaries**: violations by type
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
- `@docs/agent-control/architecture.md` — agent control system architecture
- `@docs/agent-control/state-model.md` — FSM state model
