---
trigger: CodeRabbit completion, Review triggered, coderabbit in progress, coderabbit done, incremental review, coderabbit polling, review ack vs completion
---
# CodeRabbit Completion Signals

## Problem

When an agent triggers CodeRabbit with `@coderabbitai review`, CodeRabbit
immediately posts an acknowledgment comment:

> ✅ Actions performed — Review triggered.
> Note: CodeRabbit is an incremental review system and does not re-review
> already reviewed commits.

This **acknowledgment is NOT a completion signal**. It means CodeRabbit
accepted the request and will begin reviewing. The actual review may take
2–5 minutes after this message.

## Common mistake

Treating the "Review triggered" ack as evidence that CodeRabbit found
no new issues. This leads to:

- Skipping legitimate findings on the latest commit
- Proceeding to merge before review is actually complete
- Misreporting "no new findings" when findings haven't been generated yet

## Correct completion detection

CodeRabbit signals completion through **two distinct outputs** (not the
trigger ack):

| Signal | API endpoint | What to look for |
|--------|-------------|------------------|
| **New review** | `pulls/<N>/reviews` | A new entry with `submitted_at` **after** the trigger time |
| **New walkthrough** | `issues/<N>/comments` | A new comment with `<!-- walkthrough_start -->` **after** the trigger time |

### Polling algorithm

```text
1. Record trigger_time (from the ack comment's created_at)
2. Poll every 30s:
   a. GET pulls/<N>/reviews → filter by coderabbit login
      → check if any review has submitted_at > trigger_time
   b. GET issues/<N>/comments → filter by coderabbit login
      → check if any comment has created_at > trigger_time
         AND body contains "walkthrough" or "<!-- walkthrough_start -->"
3. Completion = (a) OR (b) is true
4. Timeout at 7 minutes
```

## Incremental review behavior

The "does not re-review already reviewed commits" note means:

- CodeRabbit reviews **only new commits** pushed after its last review
- Previously reviewed commits are not re-analyzed
- This is **not** a statement that the review is complete or that there
  are no findings — it describes the scope of what will be reviewed

When `auto_review.enabled: false` (current configuration), incremental
push-triggered reviews do NOT happen. The agent must explicitly trigger
`@coderabbitai review` after every push (see `review-fix.md` Step 5b).

## State summary

| Observed state | Meaning | Next action |
|----------------|---------|-------------|
| Trigger ack posted, no new review/walkthrough | **In progress** | Continue polling |
| New review entry after trigger time | **Complete** | Read findings |
| New walkthrough comment after trigger time | **Complete** | Read findings |
| 7 min elapsed, no new output | **Timeout** | Proceed without, note in report |

## Related

- `review--bot-lifecycle.md` § State Detection — canonical state table
- `review--bot-lifecycle.md` § Timing — polling intervals and timeouts
