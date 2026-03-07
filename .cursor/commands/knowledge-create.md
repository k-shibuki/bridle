# knowledge-create

## Purpose

Capture a new pattern, decision, or gotcha as an atomic knowledge file during any workflow stage. This is a utility command invocable at any point — it does not have a fixed position in the workflow chain.

## When to use

- During implementation: a recurring pattern or non-obvious decision is discovered
- During debugging: a hard-won insight should be preserved for future sessions
- During test creation: a testing gotcha is identified
- During review: a pattern should be documented for consistency

## Inputs

- **Decision point**: The specific decision or pattern to document (1 sentence)
- **Category**: One of `test`, `r`, `lint`, `debug`, `ci`, `git`, `agent`
- **Topic**: Short kebab-case description (e.g., `mock-scope-constraint`)

## Steps

### Step 1: Identify the decision point

State the decision in one sentence. If it decomposes into independent sub-decisions, each becomes a separate atom.

**Indivisibility test**: Can the decision be stated as a single question with a single answer? If not, split.

### Step 2: Choose category and name

| Category | Prefix | Activity domain |
|----------|--------|-----------------|
| Testing | `test--` | Test creation, mock, helpers |
| R language | `r--` | Cross-cutting R gotchas |
| Lint/Format | `lint--` | styler/lintr/R CMD check |
| Debugging | `debug--` | Investigation, instrumentation |
| CI | `ci--` | Pipeline, polling, failure |
| Git | `git--` | Recovery, rebase, PR management |
| Agent | `agent--` | Subagent delegation, monitoring |

**Naming**: `{category}--{topic}` where `--` separates category from topic and `-` separates words within topic. All lowercase.

### Step 3: Scaffold the file

```bash
make kb-new NAME=<category>--<topic>
```

### Step 4: Fill the template

Edit the scaffolded file:

1. **`trigger:` field**: Add 3-6 comma-separated keywords that an agent would encounter when this knowledge is needed
2. **Title**: `# <Descriptive title>` — matches the decision point
3. **Content**: The pattern, decision, or gotcha with:
   - Problem statement or symptom
   - Resolution or pattern
   - Code example (if applicable)
   - Related atoms (if applicable, but content must be self-contained without them)

### Step 5: Validate self-containment

**Self-containment test**: Can an agent read this file (plus referenced Policy rules) and make the correct decision without following any Related links? If not, add the missing context.

### Step 6: Regenerate index and validate

```bash
make kb-manifest && make kb-validate
```

Both must pass with no errors.

### Step 7: Include in next commit

The new atom, updated index, and any changes should be included in the next `commit` step. No separate commit is needed — the knowledge file is part of the current work.

## Output

- **File created**: `.cursor/knowledge/<name>.md`
- **Index updated**: `.cursor/rules/knowledge-index.mdc`
- **Validation**: `make kb-validate` passes

## Related

- `.cursor/rules/knowledge-index.mdc` — auto-generated index (always-apply)
- `.cursor/rules/workflow-policy.mdc` § Knowledge Consultation Triggers
