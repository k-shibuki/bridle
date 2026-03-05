# YAML Schemas

These YAML schema files define the structure of plugin artifacts (decision graph, knowledge entries, constraints, context schema, decision log) during the design phase.

## Canonical Source of Truth

Once implemented, **S7 class definitions in bridle core become the canonical source of truth** (see [ADR-0001](../adr/0001-use-s7-class-system.md)). These YAML schemas serve as design-phase aids and will be kept in sync with the S7 classes or deprecated once the implementation stabilizes. Production validation is handled by S7 property validators; YAML schema validation is optional (for design support purposes).

## Files

| File | Describes | Related ADR |
|---|---|---|
| `decision_graph.schema.yaml` | Decision graph structure (nodes, transitions, policies, template ref) | [ADR-0002](../adr/0002-decision-graph-flow-control.md), [ADR-0005](../adr/0005-graph-policy-layer.md), [ADR-0009](../adr/0009-graph-template-composition.md) |
| `knowledge.schema.yaml` | Knowledge entry format (when, computable_hint, properties) | [ADR-0003](../adr/0003-when-condition-semantics.md) |
| `constraints.schema.yaml` | Technical constraint format (forces, requires, valid_values, confidence) | [ADR-0004](../adr/0004-scanner-three-layer-analysis.md), [ADR-0008](../adr/0008-scanner-resilience.md) |
| `context_schema.schema.yaml` | Variable scope for computable_hint (static declarations + data expectations) | [ADR-0007](../adr/0007-context-variable-scope.md) |
| `decision_log.schema.yaml` | Decision audit log entry format (JSONL) | [ADR-0006](../adr/0006-decision-audit-log.md) |

Each schema file contains both the schema definition and a concrete example based on `meta::metabin`.
