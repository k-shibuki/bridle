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

Use the detection commands from `@.cursor/knowledge/review--bot-operations.md` § Detection to retrieve inline comments from whichever reviewer responded.

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

**Prerequisite**: Read `@.cursor/knowledge/review--consensus-protocol.md` (SSOT for consensus model, reply format, and resolve procedure).

For each P0 and P1 finding (in priority order):

1. Read the referenced file and surrounding context (at least ±10 lines around the flagged line).
2. Determine whether the finding is valid.
3. If valid: propose a fix and apply it after user confirmation.
4. If false positive: note the reason. If the same pattern has recurred, propose creating a knowledge atom (`.cursor/knowledge/review--<pattern>.md`) via `knowledge-create` so all reviewers learn from it.

### 3b. Reply, seek consensus, and resolve each thread

Per `@.cursor/rules/agent-safety.mdc` `HS-REVIEW-RESOLVE` and `@.cursor/knowledge/review--consensus-protocol.md`:

1. **Post a disposition reply** (Fixed / By design / False positive / Acknowledged) using the Reply API from `review--consensus-protocol.md` § Reply API.
2. **Trigger re-review** (Step 5b below) — the bot must confirm the disposition.
3. **After re-review completes**: check for bot agreement per `review--consensus-protocol.md` § Bot Agreement Signals.
   - No new finding on thread → **consensus reached** → resolve via GraphQL Resolve API.
   - New finding / objection → address and return to step 1.
   - Timeout → resolve with timeout justification.
4. **Verify completeness**: enumerate threads (GraphQL Thread Enumeration in `review--consensus-protocol.md`), confirm unresolved == 0.

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

### 5b. Bot re-review (consensus verification)

Re-trigger per `@.cursor/knowledge/review--bot-operations.md` § Re-review:
- CodeRabbit: `@coderabbitai review` (if CR review budget remaining)
- Codex: only if the user instructs

If the CR review budget (2 per PR) is exhausted, skip re-review and
verify consensus using existing evidence (CR's disposition replies,
auto-resolves, and agent verification).

Delegate wait via `.cursor/templates/delegation--review-wait.md` (Monitor CI: YES if CI re-triggered, NO otherwise). The re-review result is needed by Step 3b to verify consensus — see `review--consensus-protocol.md` § Consensus Flow.

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
- `@.cursor/knowledge/review--consensus-protocol.md` (consensus model, reply format, resolve API)
