# Template: Review Disposition Reply

Every review thread must receive exactly one disposition reply before being
resolved (per `agent-safety.mdc` `HS-REVIEW-RESOLVE`).

## Reply Templates

**Fixed** — evidence: commit SHA, explanation: what was changed
```
Fixed in `<sha7>`. <what changed>.
```

Example:
```
Fixed in `f561c8d`. Aligned timeout values to 20 min across all sections.
```

**By design** — evidence: reference (ADR/rule/command), explanation: design rationale
```
By design. <rationale> (ref: <source>).
```

Example:
```
By design. Step 5 auto-loops after initial consent; HS-NO-SKIP ensures
intra-command steps are still followed (ref: next.md § Approval scope).
```

**False positive** — no evidence (the detection itself was wrong), explanation: why
```
False positive. <why detection was wrong>.
```

Example:
```
False positive. The cross-reference formats differ intentionally —
parenthetical vs dash style matches surrounding sentence structure.
```

**Acknowledged** — evidence: tracking issue, explanation: assessment result
```
Acknowledged. <brief assessment>. Tracked in #<issue>.
```

Example:
```
Acknowledged. Valid observation; container bootstrap step would improve
usability. Out of scope for SSOT cleanup. Tracked in #201.
```

## Design Principles

- **Category keyword first**: grep `^Fixed`, `^By design`, `^False positive`, `^Acknowledged` for machine classification
- **Evidence is minimal and verifiable**: SHA via git, Issue # via GitHub, ref via codebase
- **Explanation is 1-2 sentences**: auditor can understand disposition without opening the thread
- **English**: consistent with code and commit language
