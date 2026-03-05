# YAML Schemas

These YAML schema files define the structure of plugin artifacts (decision graph, knowledge entries, constraints) during the design phase.

## Canonical Source of Truth

Once implemented, **S7 class definitions in bridle core become the canonical source of truth** (see [ADR-0001](../adr/0001-use-s7-class-system.md)). These YAML schemas serve as design-phase aids and will be kept in sync with the S7 classes or deprecated once the implementation stabilizes.

## Files

| File | Describes | Related ADR |
|---|---|---|
| `decision_graph.schema.yaml` | Decision graph structure (nodes, transitions, types) | [ADR-0002](../adr/0002-decision-graph-flow-control.md) |
| `knowledge.schema.yaml` | Knowledge entry format (when, computable_hint, properties) | [ADR-0003](../adr/0003-when-condition-semantics.md) |
| `constraints.schema.yaml` | Technical constraint format (forces, requires, valid_values) | [ADR-0004](../adr/0004-scanner-three-layer-analysis.md) |

Each schema file contains both the schema definition and a concrete example based on `meta::metabin`.
