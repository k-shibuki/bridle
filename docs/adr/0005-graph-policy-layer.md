---
trigger: graph policy, skip_when, skip_hint, max_iterations, policy inheritance, manifest graph node, policy_defaults, global_policy, three-layer policy
---
# ADR-0005: Graph Policy Layer

## Context

ADR-0002 established the decision graph as a fixed, reproducible flow-control mechanism. While this rigidity is a strength for evaluation and coverage, it creates a problem: the same graph cannot adapt to different analysis contexts without changing its structure.

Concrete examples from `meta::metabin`:

- **Node skipping**: When the number of studies is very large (k > 100), differences between tau-squared estimators diminish. The `tau2_estimation` node adds no value but still forces user interaction.
- **Loop limits**: The `diagnosis -> execution` loop for sensitivity analysis has no defined stopping criterion. ADR-0002 states "infinite-loop prevention is a runtime responsibility" but provides no mechanism.
- **Priority inheritance**: A plugin author may want to set default policies at the plugin level (e.g., global max iterations) while allowing individual graphs or nodes to override them.

Three approaches were considered:

1. **No policy mechanism**: Keep the graph fully static. Rely on transition conditions alone. Rejected: cannot express "this node is irrelevant in this context" without adding numerous conditional transitions.
2. **Node-level policy only**: Add `skip_when` and `max_iterations` to individual nodes. Simple but requires repeating defaults across many nodes.
3. **Three-layer policy inheritance**: Define policies at plugin (manifest), graph, and node levels with a fixed override order.

## Decision

Adopt **option 3**: three-layer policy inheritance with two policy fields.

### Policy fields

- **`skip_when` + `skip_hint`**: Follows the same two-layer semantics as ADR-0003. `skip_when` is a natural-language string describing when the node should be skipped. `skip_hint` is an optional R expression. Evaluation rules mirror ADR-0003: if `skip_hint` is present and evaluable, use it; otherwise the LLM judges from `skip_when` text.
- **`max_iterations`**: Integer limit on how many times a node can be visited in a single session. Applies to any node but is primarily useful for `diagnosis -> execution` loops.

`emphasis` (presentation priority) was considered and rejected on YAGNI grounds — knowledge entry volume naturally conveys importance, and this can be added later if needed.

### Inheritance order (fixed specification)

Policy resolution follows **manifest < graph < node** — the most specific scope always wins:

1. `manifest.yaml` `policy_defaults` — plugin-wide defaults
2. `decision_graph.yaml` `graph.global_policy` — graph-level defaults, override manifest
3. Node-level `policy` — per-node overrides, override graph

For any policy field, the runtime resolves by checking node first, then graph, then manifest. Unset fields inherit from the next broader scope.

```yaml
# manifest.yaml
policy_defaults:
  max_iterations: 5

# decision_graph.yaml
graph:
  global_policy:
    max_iterations: 3

  nodes:
    tau2_estimation:
      type: decision
      topic: tau2_estimators
      parameter: method.tau
      policy:
        skip_when: "number of studies is very large"
        skip_hint: "k > 100"
      transitions:
        - to: ci_method
          always: true

    sensitivity_analysis:
      type: decision
      topic: sensitivity_approaches
      policy:
        max_iterations: 2
      transitions:
        - to: execute_analysis
          when: "re-run with different parameters"
        - to: publication_bias
          otherwise: true
```

In this example, `sensitivity_analysis` uses max_iterations = 2 (node), other looping nodes use 3 (graph), and if graph did not specify, they would use 5 (manifest).

## Consequences

- **Easier**: Fixed graph structure's reproducibility is preserved while gaining context-dependent adaptation
- **Easier**: `skip_when` / `skip_hint` reuses the proven ADR-0003 evaluation pattern — no new runtime evaluation path
- **Easier**: Three-layer inheritance with a fixed priority order is predictable and debuggable
- **Harder**: The runtime must implement policy resolution across three layers before each node visit
- **Harder**: `validate_plugin()` must check consistency across layers (e.g., skip_hint references valid variables)
