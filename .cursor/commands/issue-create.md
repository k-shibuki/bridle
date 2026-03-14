# issue-create

## Reads
- `.github/ISSUE_TEMPLATE/task.md` or `.github/ISSUE_TEMPLATE/bug_report.md` (read the appropriate template — SSOT for Issue structure)
- `workflow-policy.mdc` § Issue-Driven Workflow (traceability requirements)

## Sense

Search the codebase to understand: relevant ADRs and schemas, existing code paths, change scope.

## Act

1. Determine granularity: small change → 1 Issue; large feature → parent + child Issues.
2. Read the appropriate Issue template file. Draft Issue body with all required sections: Summary, Motivation, Related ADR, Schema Impact, Acceptance Criteria (2-5 verifiable), Test Plan (concrete inputs/outputs — no vague placeholders), Risks.
3. Create: `gh issue create --title "<type>: <desc>" --body "<body>" --label "<type>"`.
4. If decomposed: create child Issues and link from parent via Task List (`- [ ] #<N>`).
5. Recommend next step: `implement` with Issue number.

## Output
- Issue URL
- Related ADRs
- Acceptance criteria (copied from Issue)
- Test plan key scenarios
- Files likely to change
- Sub-issues (if decomposed)

## Guard
- Do NOT write code in this step
- Issue title: `<type>: <description>` convention
- `HS-EVIDENCE-FIRST`: use `make evidence-issue` for observation
