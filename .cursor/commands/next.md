# next

## Purpose

Determine the next action for the AI agent by analyzing the current project state, propose it with rationale, and after user approval, autonomously drive the workflow forward by invoking the appropriate command(s).

This is a **meta-command** that orchestrates all other commands. It does not implement logic itself — it delegates to the existing command chain.

## When to use

- At the start of a session ("what should I work on?")
- After completing a command ("what's next?")
- When the user says "continue" or "proceed" without specifying a command
- When the agent is unsure which command applies

## Constraints

- **Never skip commands**: Always follow the defined workflow order. Do not jump from `implement` to `pr-create` without going through `test-create`, `quality-check`, `regression-test`, `docs-discover`, and `commit`.
- **Never skip steps within commands**: Following the command chain is not enough. Each command's full specification (every step) must be executed. "Called the command" does not mean "followed its steps".
- **Never act without approval**: Present the proposed action and wait for user confirmation before executing.
- **Delegate, don't duplicate**: Once the next command is determined, invoke it by following its full specification (`.cursor/commands/<command>.md`). Do not reimplement the command's logic inline.
- **State assessment must be evidence-based**: Use `git status`, `gh issue list`, `make doctor`, etc. to determine state. Do not guess.

## Continuous Execution Mode

When the user instructs continuous execution ("keep going", "do everything", "till close all issues", etc.):

1. **Execute every step of every command in full**. "Never skip commands" means both "do not skip commands in the workflow" AND "do not skip steps within each command". Speed is never a justification for omitting verification.
2. **Parallelize via subagent delegation, not by skipping gates**: When CI is pending on a PR, **Hard Stop #7 applies** — always delegate CI-wait + merge to a background subagent. If independent Issues exist, start `implement` immediately. If not, perform housekeeping (see Step 6). Never merge until CI passes. Never poll inline.
3. **Report progress at each gate**: Print a one-line summary at each workflow transition (e.g., "PR #13 created, CI pending — delegated to background. Starting #9.") so the user can track progress.
4. **User's "hurry up" does not exempt safety checks**: Achieve speed by reducing unnecessary explanation, delegating blocking operations to subagents, and batching tool calls. Never by skipping `make ci-fast`, `gh pr checks`, or any verification step.

**Typical parallel execution pattern** (multi-Issue batch):

```
Issue A: implement → test → quality → commit → pr-create
                                                    │
                                          CI pending on PR #X
                                                    │
                    ┌───────────────────────────────┤
                    │ Background subagent            │ Main agent
                    │ poll CI → merge PR #X          │ Issue B: implement → test → ...
                    │                                │
                    └───────────────────────────────┤
                                                    │
                    next re-assessment: check subagent transcript
```

## Steps

### Step 1: Assess current state

Sync remote tracking information first, then gather evidence from multiple sources in parallel:

```bash
# Sync local tracking refs with remote (prune deleted branches)
git fetch --prune origin

# Git state
git branch --show-current
git status --short
git log --oneline -5

# GitHub state
gh issue list --state open --json number,title,labels,body --limit 30
gh pr list --state open --json number,title,headRefName,statusCheckRollup --limit 10

# Environment state
make doctor 2>&1 | tail -5

# Stale branch check (squash-merged branches linger after PR merge)
git branch --merged origin/main | grep -v '^\*\|main$' || true
git branch --no-merged origin/main --format='%(refname:short) %(upstream:track)' | grep '\[gone\]' || true
```

**Background task check**: If a background subagent was previously launched (e.g., for CI-wait + merge), check its transcript file for completion. See `subagent-policy.mdc` "Completion guarantee" for the protocol. Incorporate results into the state assessment.

### Step 2: Determine workflow position

Use the evidence to classify the current state into one of these positions:

| State signals | Workflow position | Next command |
|---------------|-------------------|--------------|
| No open Issues | **No work planned** | `issue-create` |
| Open Issues exist, on `main`, no uncommitted changes, Issues not yet reviewed | **Pre-flight review needed** | `issue-review` |
| Open Issues exist, on `main`, no uncommitted changes | **Ready to start** | `implement` (auto-select) |
| On feature branch, uncommitted R/ changes, no tests | **Implementation done** | `test-create` |
| On feature branch, tests exist, not yet checked | **Tests done** | `quality-check` |
| On feature branch, quality OK, tests not run as suite | **Quality OK** | `regression-test` |
| On feature branch, tests pass, docs not reviewed | **Tests pass** | `docs-discover` (Mode 2) |
| On feature branch, docs OK, uncommitted changes | **Docs OK** | `commit` |
| On feature branch, committed, no PR | **Committed** | `pr-create` |
| Open PR, CI still running, independent Issue exists | **CI pending (parallel)** | **Hard Stop #7**: Delegate CI-wait + merge to background subagent, then start `implement` on independent Issue. |
| Open PR, CI still running, no independent Issue | **CI pending (housekeeping)** | **Hard Stop #7**: Delegate CI-wait to background subagent, then do housekeeping (see Step 6). |
| Stale local branches detected | **Cleanup needed** | Delete stale branches (see `pr-merge.md` "Post-merge cleanup"). Can be done during housekeeping. |
| Background subagent running | **Background task in progress** | Check transcript for completion; continue independent work |
| Open PR, CI all green | **CI green** | `pr-review` |
| Open PR, CI failed | **CI failure** | `debug` or fix + re-push |
| PR reviewed, mergeable | **Review done** | `pr-merge` |
| PR merged, back on `main` | **Cycle complete** | `implement` (next Issue) or `issue-create` |
| Environment not ready | **Environment issue** | `doctor` |
| On `main`, hotfix needed | **Exception flow** | `implement` → `pr-create` (exception path) |

### Step 3: Refine with context

Beyond the basic position, consider:

- **Blocked Issues**: If the auto-selected Issue depends on unfinished work, flag it.
- **In-progress work**: If uncommitted changes exist on a branch, resuming that work takes priority over starting new Issues.
- **Failed CI**: If an open PR has failing checks, fixing it takes priority.
- **Stale PRs**: If a PR is open but not reviewed, suggest `pr-review`.

### Step 4: Present proposal

Format the proposal clearly:

```
## Next Action

### Current state
- Branch: `<branch>`
- Uncommitted changes: <yes/no> (<file count> files)
- Open Issues: <count> (<unblocked count> actionable)
- Open PRs: <count> (CI status: <pass/fail/pending>)
- Environment: <healthy/issues>

### Proposed action: `<command-name>`
- Reason: <why this is the right next step>
- Target: <Issue #N / PR #N / specific scope>
- Expected outcome: <what will be done>

### Workflow context
- Previous step: <what was last completed>
- After this step: <what comes next in the workflow>

Proceed? [Y/n/other]
```

### Step 5: Execute on approval

Once the user approves (or modifies the choice):

1. **Read the command specification**: Load `.cursor/commands/<command>.md`
2. **Follow the command's steps exactly**: Do not abbreviate or skip steps defined in the command.
3. **On completion, loop back to Step 1**: After the command finishes, re-assess state and propose the next action. Continue until the user stops or the workflow cycle completes.

If the user modifies the choice (e.g., "do #8 instead of #7"), adjust and proceed.

### Step 6: Subagent delegation for blocking operations

When Step 2 identifies any **CI pending** state (Hard Stop #7 — always delegate):

1. **Delegate the blocking operation** to a background subagent:
   - Use `subagent_type: "shell"`, `model: "fast"`, `run_in_background: true`
   - Prompt must include: goal, numbered steps with exact commands, error handling, return format
   - For sequential multi-PR merges, include the full rebase → CI-poll → merge chain in one subagent prompt
   - For dependent PRs with shared commits, use the "Dependent PR Merge Chain" template (see `agent--delegation-templates.md`)
   - See `pr-merge.md` "Delegated merge" section for the prompt template

2. **Note the subagent transcript path** returned by the Task tool for later completion checking.

3. **Run the Two-Tier Gate** (see `@.cursor/rules/subagent-policy.mdc` § Productive work during delegation):
   - Tier 1: Signal scan (`git status`, `gh issue list`, `git stash list`, session-findings) — parallel, ~2-3 s.
   - If all clear → proceed directly to step 4.
   - If any signal fires → Tier 2: reason about highest-value action, execute, then proceed to step 4.
   - The main agent MUST NOT touch `main` or the merge-target branches while the subagent is working.

4. **Completion guarantee** (Hard Stop #7):
   - After productive work is exhausted, check the subagent output file.
   - If still running: enter monitoring loop (read output file → `sleep 15` → read again → repeat).
   - If completed: incorporate result into state assessment, report to user, then proceed to next action or end turn.
   - **NEVER end the turn while a delegated subagent is still running.**

**Fallback**: If the environment does not support background subagents, fall back to inline CI polling as before.

### Step 7: Handle interruptions

If an error or unexpected state occurs during execution:

- **Fixable locally** (lint error, test failure): Fix it as part of the current command's scope.
- **Needs investigation**: Suggest `debug` command.
- **Scope drift**: Suggest creating a new Issue via `issue-create`.
- **User needs to decide**: Present options and wait.

## Workflow State Diagram

```
                    ┌─────────────┐
                    │   doctor    │ (environment check)
                    └──────┬──────┘
                           │
              ┌────────────▼────────────┐
              │  Any open Issues?       │
              │  No → issue-create      │
              │  Yes ↓                  │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │     implement           │ (auto-select or specified)
              │  + docs-discover Mode 1 │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │     test-create         │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │     quality-check       │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │     regression-test     │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │  docs-discover Mode 2   │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │       commit            │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │      pr-create          │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │    [CI] → pr-review     │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │      pr-merge           │
              └────────────┬────────────┘
                           │
                    ┌──────▼──────┐
                    │  Loop back  │ → implement (next Issue)
                    └─────────────┘
```

## Output (response format)

- **State assessment**: branch, changes, Issues, PRs, environment (concise)
- **Proposed action**: command name + rationale
- **Workflow position**: where we are in the flow, what comes after
- **User prompt**: confirmation request

After execution:

- **Action result**: output from the delegated command
- **Next proposal**: automatic re-assessment for the following step

## Related

- All commands in `.cursor/commands/` — this meta-command delegates to them
- `.cursor/README.md` — workflow overview and knowledge map
- `.cursor/rules/workflow-policy.mdc` — Issue-driven workflow requirements
- `.cursor/rules/agent-safety.mdc` — Hard Stops (absolute prohibitions)
- `.cursor/rules/subagent-policy.mdc` — Subagent delegation policy
