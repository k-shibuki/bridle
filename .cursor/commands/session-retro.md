# session-retro

## Purpose

Reflect on the current session to extract learnings and incrementally improve the AI control system. Identify knowledge gaps, propose new atoms, and suggest rule/command improvements based on session activity.

The `next` command runs a post-cycle signal scan after every `pr-merge` completion. When the scan detects a learning signal, it proposes this command for full analysis. The command can also be invoked explicitly at any time. It complements `controls-review` (the heavyweight structural audit) by capturing incremental, experience-driven improvements.

## When to use

- When `next` post-cycle signal scan detects a learning signal (see § Quick Scan Mode)
- At the end of a multi-Issue session before signing off
- When the agent notices repeated friction or workarounds during implementation
- When the user explicitly asks for a session retrospective

## Inputs

- **Session scope** (optional): `--current` (default, most recent session) or `--id <uuid>` (specific past session)
- Agent transcript files in `agent-transcripts/` (auto-discovered)
- Recent git history (auto-discovered)

## Steps

### Step 1: Gather session activity

Collect evidence from multiple sources in parallel:

```bash
# Recent commits in this session (last ~20)
git log --oneline -20

# Issues closed during this session
gh issue list --state closed --json number,title,closedAt --limit 10

# PRs merged during this session
gh pr list --state merged --json number,title,mergedAt --limit 10
```

**Agent transcript reading**: Read the most recent session transcript (or the one specified by `--id`):

```bash
# List available transcripts (most recent first)
ls -t agent-transcripts/*.jsonl | head -5
```

Parse the JSONL file for assistant messages, tool calls, and error patterns. Gracefully handle missing or malformed transcripts — log a warning and continue with git/GitHub evidence only.

### Step 2: Detect learning signals

Scan the gathered evidence for signals in 5 categories:

| Category | Signal examples | Detection method |
|----------|----------------|------------------|
| **Friction** | Retries, rollbacks, same command invoked multiple times, reverted commits | Git history: `revert` commits, force-pushes. Transcript: repeated tool calls, error-then-retry sequences |
| **Discovery** | New pattern found, first-time error resolved, novel workaround | Transcript: successful resolution after investigation, new helper/utility created |
| **Gap** | No rule/knowledge existed, agent had to improvise, "I'm not sure" moments | Transcript: web searches for project-internal topics, long reasoning chains without rule references |
| **Drift** | Existing atom's description doesn't match current reality, outdated references | Comparison: atom content vs actual codebase state, broken `@` references |
| **Efficiency** | Unnecessarily long procedure, redundant verification, steps that could be parallelized | Transcript: sequential operations that could batch, repeated context-gathering |

For each detected signal, record:

- **Category**: one of the 5 above
- **Evidence**: specific commit, transcript excerpt, or command output
- **Confidence**: high / medium / low (based on signal strength)

### Quick Scan Mode

`next` runs this abbreviated version of Step 2 after every `pr-merge` cycle. The goal is a fast pass/no-pass gate — not a thorough analysis.

**Procedure** (target: seconds, not minutes):

1. Scan `git log --oneline -10` and `gh pr list --state merged --limit 5` for obvious signals:
   - `revert` commits or force-pushes → Friction
   - Same file modified in multiple recent commits → possible Gap or Efficiency
   - `.cursor/` files modified by recent PRs → possible Drift
2. Do NOT read agent transcripts or knowledge atoms — that is the full retro's job.
3. **"No signals" is the expected normal result.** Do not manufacture findings. Return silently.
4. If a high-confidence signal is detected, return a 1-line description. `next` will offer the user a choice between `session-retro` (full analysis) and the default next action.

### Step 3: Cross-reference with existing knowledge

Before proposing new atoms or changes, check for overlap:

1. **Read `knowledge-index.mdc`** trigger keywords — does an existing atom already cover this finding?
2. **Search existing atoms** for related content:

   ```bash
   ls .cursor/knowledge/
   ```

   Read any atoms whose triggers overlap with the finding.
3. **Check rules and commands** for existing coverage — the finding may already be addressed by a rule that wasn't followed, rather than being a genuine gap.

Mark each finding as:

- **New**: no existing coverage — candidate for new atom or rule change
- **Update**: existing atom covers the topic but needs revision
- **Redundant**: already fully covered — no action needed
- **Compliance**: existing rule exists but wasn't followed — flag for process improvement, not content change

### Step 4: Propose improvement actions

For each non-redundant finding, propose an action:

| Action type | Delegation target | When to use |
|-------------|-------------------|-------------|
| New knowledge atom | `knowledge-create` | Pattern/gotcha not covered by any existing atom |
| Atom content update | Direct edit of `.cursor/knowledge/<atom>.md` | Existing atom is outdated or incomplete |
| Atom trigger update | Direct edit of atom + `make knowledge-manifest` | Atom exists but triggers don't match how agents encounter it |
| Rule/command clarification | Direct edit of `.cursor/rules/*.mdc` or `.cursor/commands/*.md` | Minor wording fix, missing edge case |
| Structural problem | Recommend `controls-review` | Cross-file inconsistency, component boundary violation, SSOT breach — beyond session-retro scope |

**For new atoms**: Delegate to `knowledge-create` following its full specification. Do not create atoms inline — the `knowledge-create` command ensures proper scaffolding, validation, and index regeneration.

**For structural problems**: Do not attempt a full audit. Record the finding and recommend running `controls-review` for systematic resolution.

### Step 5: Present findings and apply after approval

Format the retrospective report:

```text
## Session Retrospective

### Session summary
- Commits: <count>
- Issues closed: <list>
- PRs merged: <list>
- Duration: <approximate>

### Findings (<count>)

| # | Category | Signal | Confidence | Action | Status |
|---|----------|--------|------------|--------|--------|
| 1 | Gap | <description> | high | New atom: `<name>` | Proposed |
| 2 | Friction | <description> | medium | Update: `<atom>` | Proposed |
| 3 | Drift | <description> | high | Escalate: `controls-review` | Proposed |

### Proposed actions

#### F1: <finding title>
- **Evidence**: <specific evidence>
- **Action**: <what to do>
- **Delegation**: <target command or direct edit>

...

Apply proposed actions? [Y/n/select specific items]
```

Wait for user confirmation, then execute approved actions.

## Output (response format)

- **Session scope**: which session was analyzed
- **Signals detected**: count per category
- **Findings**: table with category, confidence, and proposed action
- **Actions taken**: list of changes applied (after approval)
- **Escalations**: any `controls-review` recommendations

## Constraints

- Do NOT perform a full structural audit — that is `controls-review`'s responsibility.
- Do NOT create knowledge atoms inline — always delegate to `knowledge-create`.
- Do NOT modify R source code or tests — this command is about the control system, not the codebase.
- Gracefully handle missing or unparseable agent transcripts — continue with available evidence.
- Keep the retrospective lightweight: aim for 5-10 minutes of analysis, not exhaustive review.
- Present all proposals before acting — wait for user approval on each action.

## Related

- `@.cursor/commands/knowledge-create.md` — delegation target for new atoms
- `@.cursor/commands/controls-review.md` — escalation target for structural problems
- `@.cursor/rules/knowledge-index.mdc` — trigger-keyword lookup for existing atoms
- `@.cursor/rules/workflow-policy.mdc` — Issue-driven workflow context
