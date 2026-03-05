# Architecture Decision Records (ADR)

This directory contains Architecture Decision Records for the bridle project. ADRs document significant architectural decisions, their context, and trade-offs.

## Format

Each ADR is a Markdown file named `NNNN-short-title.md` where NNNN is a zero-padded sequence number.

### Template

```markdown
# ADR-NNNN: Title

## Context

What is the issue that we're seeing that is motivating this decision?

## Decision

What is the change that we're proposing and/or doing?

## Consequences

What becomes easier or more difficult because of this change?
```

## Workflow

1. Create a new ADR when making a significant architectural decision.
2. Use the next sequence number (e.g., `0005` after `0004`).
3. Reference ADRs from code comments only when the decision directly affects the implementation.

## References

- [Michael Nygard's ADR article](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
- [ADR GitHub organization](https://adr.github.io/)
