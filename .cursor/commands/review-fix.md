# review-fix

## Purpose

Address review findings from `pr-review`. This includes findings from both the Cursor review and bot review (if available). Evaluate each finding for validity, apply fixes, and re-push.

## When to use

- After `pr-review` concludes "Changes required"
- The required changes list from `pr-review` is the primary input

## Contract

1. Read all user-attached `@...` context first.
2. If the PR number is missing, ask for it and stop.
3. Do NOT dismiss findings without analysis. Evaluate each on its merits.
4. After fixes, run quality gates before committing.
5. For recurring false positives, create or update a knowledge atom (`.cursor/knowledge/review--*.md`) to capture the pattern. All reviewers can read these files.

## Inputs (ask if missing)

- **PR number** (required)
- **Scope** (optional): `all` (default), `p0-only`, or specific file path

## Steps

### 1. Gather findings

Collect review findings from two sources:

**Source A: `pr-review` output** (primary — always available)

If `pr-review` was just run in this session, use its "Required changes" list directly. Otherwise, retrieve the latest state:

```bash
# Check for pr-review's structured output in PR comments or conversation history
gh pr view <PR> --json reviews --jq '.reviews[-1].body'
```

**Source B: Bot inline comments** (if `pr-review` reported bot review status as "Reviewed")

Use the detection commands from `@.cursor/knowledge/review--bot-lifecycle.md` § Output Detection to retrieve inline comments from whichever reviewer responded.

Merge all sources, deduplicating where Cursor and bot review flagged the same issue.

### 2. Classify and validate findings

Evaluate every finding on technical merit regardless of source. Cursor and bot reviewers have equal weight.

| Classification | Action |
|---|---|
| **P0 (blocking)** | Must fix before merge |
| **P1 (significant)** | Should fix; document reason if deferring |
| **False positive** | Note reason; if a pattern recurs, create/update a knowledge atom (`.cursor/knowledge/review--<pattern>.md`) |
| **Already addressed** | Note the commit that addressed it |

Present the classified list to the user before proceeding.

### 3. Address each finding

**Prerequisite**: Read `@.cursor/knowledge/review--comment-response.md` (SSOT for reply format and resolve procedure).

For each P0 and P1 finding (in priority order):

1. Read the referenced file and surrounding context (at least ±10 lines around the flagged line).
2. Determine whether the finding is valid.
3. If valid: propose a fix and apply it after user confirmation.
4. If false positive: note the reason. If the same pattern has recurred, propose creating a knowledge atom (`.cursor/knowledge/review--<pattern>.md`) via `knowledge-create` so all reviewers learn from it.

### 3b. Reply and resolve each thread

Per `@.cursor/rules/agent-safety.mdc` `HS-REVIEW-RESOLVE`: every review thread must receive a disposition reply before being resolved.

For each unresolved review thread (use the thread list from `pr-review` Step 6, or enumerate via GraphQL):

1. **Post a threaded reply** with one of the 4 disposition categories:

   | Category | Template |
   |---|---|
   | Fixed | `Fixed in \`<sha7>\`. <what changed>.` |
   | By design | `By design. <rationale> (ref: <source>).` |
   | False positive | `False positive. <why detection was wrong>.` |
   | Acknowledged | `Acknowledged. <brief assessment>. Tracked in #<issue>.` |

   ```bash
   gh api repos/{owner}/{repo}/pulls/<N>/comments/<comment_id>/replies \
     -f body="Fixed in \`abc1234\`. Aligned timeout values to 20 min."
   ```

2. **Resolve the thread**:

   ```bash
   gh api graphql -f query='
     mutation($id: ID!) {
       resolveReviewThread(input: {threadId: $id}) {
         thread { isResolved }
       }
     }
   ' -f id="<THREAD_ID>"
   ```

3. **Verify completeness** after all threads are processed:

   ```bash
   gh api graphql -f query='...' --jq '
     [.data.repository.pullRequest.reviewThreads.nodes[]
      | select(.isResolved | not)] | length'
   ```

   Result must be 0. If > 0, missed threads exist — return to the thread list and process remaining.

### 4. Quality gate

After all fixes are applied:

```bash
make ci-fast        # validate-schemas + renv-check + kb-validate + lint
make format-check   # styler dry-run
```

If either fails, fix before proceeding.

### 5. Commit and push

Commit the fixes following `@.cursor/rules/commit-format.mdc`. Use type `fix` and include `Refs: #<issue>` in the footer.

```bash
git add -A
git commit -m "fix(<scope>): address review feedback

Refs: #<issue>"
git push
```

### 5b. Bot re-review decision

**Prerequisite**: Read `@.cursor/knowledge/review--bot-lifecycle.md` § Re-review after review-fix.

Agent re-triggers CodeRabbit after every review-fix push. Agent decides whether to also re-trigger Codex.

```bash
# Always — re-trigger CodeRabbit:
gh pr comment <PR> --body "@coderabbitai review"
```

| Condition | CodeRabbit | Codex |
|-----------|-----------|-------|
| Any push to PR branch | Agent triggers `@coderabbitai review` | — |
| Push addresses a Codex-sourced finding | Agent triggers `@coderabbitai review` | Yes — `gh pr comment <PR> --body "@codex review"` |
| Push addresses only CodeRabbit/Cursor findings | Agent triggers `@coderabbitai review` | No |

Delegate the wait to a background subagent. Choose template based on CI state:

| CI state | Template |
|----------|----------|
| CI pending (push re-triggered CI) | Template 4: CI + Bot Review Wait (`agent--delegation-templates.md`) |
| CI already passed | Template 5: Bot Review Wait Only (`agent--delegation-templates.md`) |

Tell the subagent: CodeRabbit: YES (agent-triggered), Codex: YES/NO. The main agent proceeds with other work (Two-Tier Gate).

### 6. Report

Summarize what was done:

- **Findings addressed**: count by source (Cursor / bot review) and severity (P0 / P1)
- **False positives**: count (with brief reasons, replies posted)
- **Deferred**: count (with justification)
- **Quality gate**: pass / fail
- **Next step**: `pr-review` (re-review to confirm all findings resolved)

## Output (response format)

- **PR**: `#<number>`, title
- **Findings processed**: total count, by source (Cursor / bot review)
- **Classification summary**: P0 / P1 / false positive / already addressed
- **Fixes applied**: list of changes with file and line
- **Quality gate result**: pass / fail
- **Remaining items**: deferred findings with justification
- **Next step**: `pr-review` for re-assessment

## Related

- `@.cursor/commands/pr-review.md` (produces the findings this command addresses)
- `@.cursor/commands/pr-merge.md` (next step after re-review confirms mergeable)
- `@.cursor/rules/quality-policy.mdc` (quality gates)
- `@.cursor/rules/commit-format.mdc` (commit message format)
- `@.cursor/knowledge/review--comment-response.md` (reply format SSOT, resolve API, completeness invariant)
