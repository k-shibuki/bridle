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

This command is bound by `@.cursor/rules/agent-safety.mdc` `HS-NO-SKIP` (no skipping steps or proceeding without evidence). Specifically:

- Follow the defined workflow order without skipping commands or steps within commands
- Present the initial proposal and wait for user confirmation before starting
- Delegate to command specifications (`.cursor/commands/<command>.md`) rather than reimplementing logic inline
- Base all state assessments on evidence from tool output, not assumptions

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
gh pr list --state open --json number,title,headRefName,statusCheckRollup,mergeable --limit 10

# Recently merged PRs (for dependent chain detection)
gh pr list --state merged --json number,title,mergedAt --limit 5

# Environment state
make doctor 2>&1 | tail -5

# Stale branch check (squash-merged branches linger after PR merge)
git branch --merged origin/main | grep -v '^\*\|main$' || true
git branch --no-merged origin/main --format='%(refname:short) %(upstream:track)' | grep '\[gone\]' || true

# Note: Bot review is triggered and waited on by pr-create (Step 5) via
# subagent delegation. next does not manage bot review state directly.
```

**Background task check**: If a background subagent was previously launched (e.g., for CI-wait), check its transcript file for completion. See `subagent-policy.mdc` "Completion guarantee" for the protocol. Incorporate results into the state assessment.

### Step 2: Determine workflow position

Use the evidence to classify the current state into one of these positions:

| State signals | Workflow position | Next command |
|---------------|-------------------|--------------|
| No open Issues | **No work planned** | `issue-create` |
| Open Issues exist, on `main`, no uncommitted changes, Issues not yet reviewed | **Pre-flight review needed** | `issue-review` |
| Open Issues exist, on `main`, no uncommitted changes | **Ready to start** | `implement` (auto-select) |
| On feature branch, uncommitted R/ changes, no tests | **Implementation done** | `test-create` |
| On feature branch, tests exist, not yet checked | **Tests done** | `quality-check` |
| On feature branch, quality OK, tests not run as suite | **Quality OK** | `test-regression` |
| On feature branch, tests pass, docs not reviewed | **Tests pass** | `docs-discover` (Mode 2) |
| On feature branch, docs OK, uncommitted changes | **Docs OK** | `commit` |
| On feature branch, committed, no PR | **Committed** | `pr-create` |
| Open PR, CI still running, independent Issue exists | **CI pending (parallel)** | Delegate CI-wait (Template 2, no merge) to background subagent (see `subagent-policy.mdc`), then start `implement` on independent Issue. When CI completes, proceed to `pr-review`. |
| Open PR, CI still running, no independent Issue | **CI pending (housekeeping)** | Delegate CI-wait to background subagent (see `subagent-policy.mdc`), then do housekeeping (see Step 6). |
| Stale local branches detected | **Cleanup needed** | Delete stale branches (see `pr-merge.md` "Post-merge cleanup"). Can be done during housekeeping. |
| Background subagent running | **Background task in progress** | Check transcript for completion; continue independent work |
| Open PR, CI all green, wait subagent done | **Ready for review** | `pr-review` (retrieves bot review findings if available) |
| Open PR, CI failed | **CI failure** | Fix inline, re-push, then **re-enter `next`** (state will be "CI pending" → delegate to subagent per `subagent-policy.mdc`). Do NOT poll CI inline after re-push. |
| PR reviewed, changes required | **Changes required** | `review-fix` (address findings from `pr-review`, then re-push and re-review) |
| PR reviewed, mergeable | **Review done** | `pr-merge` |
| Open PR, `CONFLICTING` mergeable status, parent PR recently merged | **Dependent chain needs rebase** | Rebase child branch with `git rebase --onto` (see `git--squash-merge-dependent-branch.md`), then force-push and wait for CI. Detect via: `gh pr view <N> --json mergeable -q '.mergeable'` returns `CONFLICTING` AND a related PR was recently squash-merged. |
| PR merged, back on `main` | **Cycle complete** | Post-cycle signal scan (see Step 3), then `implement` (next Issue) or `issue-create` |
| Environment not ready | **Environment issue** | `doctor` |
| On `main`, hotfix needed | **Exception flow** | `implement` → `pr-create` (exception path) |

### Step 3: Refine with context

Beyond the basic position, consider:

- **Blocked Issues**: If the auto-selected Issue depends on unfinished work, flag it.
- **In-progress work**: If uncommitted changes exist on a branch, resuming that work takes priority over starting new Issues.
- **Failed CI**: If an open PR has failing checks, fixing it takes priority.
- **Stale PRs**: If a PR is open but not reviewed, suggest `pr-review`.
- **Post-cycle signal scan**: When the state is **Cycle complete** (PR merged, back on `main`), run a lightweight scan for learning signals before proposing the next action. Follow the Quick Scan procedure in `@.cursor/commands/session-retro.md` § Quick Scan Mode:
  - Scan `git log` and recent closed Issues/PRs for the 5 signal categories (Friction, Discovery, Gap, Drift, Efficiency)
  - Do NOT read agent transcripts — that is the full `session-retro`'s job
  - **"No signals" is the normal result.** Do not manufacture findings. Proceed silently to the next action.
  - If a high-confidence signal is detected, report it in 1-2 lines within the Step 4 proposal and offer `session-retro` as an alternative to `implement`

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
3. **On completion, loop back to Step 1**: Re-assess state, propose and execute the next action without waiting for further user confirmation.

Report progress at each gate with a one-line summary (e.g., "PR #13 created, CI pending — delegated. Starting #9.").

**Approval scope**: User approval removes the confirmation pause between steps — nothing else. All policies remain invariant: subagent delegation (`subagent-policy.mdc`), verification gates, command specifications (`HS-NO-SKIP`), and Hard Stops. Approval is never a basis for skipping steps or changing execution methods.

**Termination conditions**: After initial approval, return to Step 1 after every action. End the turn ONLY when:

1. The user's stated scope is fulfilled — if no scope was stated, when no actionable work remains (no open Issues, no open PRs, no pending CI, no active subagents)
2. A decision requires user judgment
3. An error persists after fix attempt

Intermediate milestones (completing todos, pushing, posting replies) are never termination conditions.

If the user modifies the choice (e.g., "do #8 instead of #7"), adjust and proceed.

**Parallel execution**: When CI is pending and independent Issues exist, delegate CI-wait to a background subagent (Template 2, no merge) and start the next Issue in parallel. When CI completes, the main agent runs `pr-review` → `pr-merge` (or `gh pr merge --auto --squash`):

```
Issue A: implement → ... → pr-create
                                │
                      CI pending on PR #X
                                │
    ┌───────────────────────────┤
    │ Background subagent       │ Main agent
    │ poll CI → report          │ Issue B: implement → ...
    │                           │
    └───────────────────────────┤
                                │
    next re-assessment: CI green → pr-review → pr-merge/auto-merge
```

### Step 6: Subagent delegation for blocking operations

When Step 2 identifies any **CI pending** state, delegate to a background subagent per `@.cursor/rules/subagent-policy.mdc` (delegation pattern, Two-Tier Gate, completion guarantee). Use prompt templates from `@.cursor/knowledge/agent--delegation-templates.md`.

### Step 7: Handle interruptions

If an error or unexpected state occurs during execution:

- **Fixable locally** (lint error, test failure): Fix it as part of the current command's scope.
- **Needs investigation**: Suggest `debug` command.
- **Scope drift**: Suggest creating a new Issue via `issue-create`.
- **User needs to decide**: Present options and wait.

## Workflow State Diagram

> Canonical pipeline overview: `.cursor/README.md` § Standard Flow.
> This diagram adds `next`-specific details (decision points, retro scan, loop-back).

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
              │     test-regression     │
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
              │  [CI] + bot review     │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │      pr-review         │ (Cursor + bot findings)
              └──────┬─────┬──────┘
                    │     │
             Mergeable  Changes required
                    │     │
                    │     ┌────▼────────────┐
                    │     │   review-fix       │
                    │     └────┬────────────┘
                    │          │ (re-push → re-review)
                    │          └──────┐
                    ▼               │
                           │
              ┌────────────▼────────────┐
              │      pr-merge           │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │  retro signal scan      │ (silent if no signals)
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
