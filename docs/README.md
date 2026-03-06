# Project Documentation

This directory contains architecture decision records (ADRs) and YAML schema definitions.

**Workflow context**: ADRs and schemas are the primary design references for implementation. Before working on any Issue, check which ADRs govern the change (listed in the Issue body). For the full development workflow, see [`.cursor/README.md`](../.cursor/README.md).

## Architecture Decision Records (`adr/`)

ADRs document significant architectural decisions, their context, and trade-offs.

### Format

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

### Workflow

1. Create a new ADR when making a significant architectural decision.
2. Use the next sequence number (e.g., `0010` after `0009`).
3. Reference ADRs from code comments only when the decision directly affects the implementation.

### References

- [Michael Nygard's ADR article](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
- [ADR GitHub organization](https://adr.github.io/)

## YAML Schemas (`schemas/`)

These YAML schema files define the structure of plugin artifacts (decision graph, knowledge entries, constraints, context schema, decision log) during the design phase.

### Canonical Source of Truth

Once implemented, **S7 class definitions in bridle core become the canonical source of truth** (see [ADR-0001](adr/0001-use-s7-class-system.md)). These YAML schemas serve as design-phase aids and will be kept in sync with the S7 classes or deprecated once the implementation stabilizes. Production validation is handled by S7 property validators; YAML schema validation is optional (for design support purposes).

### Files

| File | Describes | Related ADR |
|---|---|---|
| `decision_graph.schema.yaml` | Decision graph structure (nodes, transitions, policies, template ref) | [ADR-0002](adr/0002-decision-graph-flow-control.md), [ADR-0005](adr/0005-graph-policy-layer.md), [ADR-0009](adr/0009-graph-template-composition.md) |
| `knowledge.schema.yaml` | Knowledge entry format (when, computable_hint, properties) | [ADR-0003](adr/0003-when-condition-semantics.md) |
| `constraints.schema.yaml` | Technical constraint format (forces, requires, valid_values, confidence) | [ADR-0004](adr/0004-scanner-three-layer-analysis.md), [ADR-0008](adr/0008-scanner-resilience.md) |
| `context_schema.schema.yaml` | Variable scope for computable_hint (static declarations + data expectations) | [ADR-0007](adr/0007-context-variable-scope.md) |
| `decision_log.schema.yaml` | Decision audit log entry format (JSONL) | [ADR-0006](adr/0006-decision-audit-log.md) |

Each schema file contains both the schema definition and a concrete example based on `meta::metabin`.
