---
trigger: graph template, template composition, build_graph, entry_point, exit_point, build-time merge, flat graph, connection point
---
# ADR-0009: Graph Template Composition

## Context

ADR-0002 noted that "different analysis types within the same package may require separate graphs." In practice, the `meta` package exposes `metabin`, `metacont`, `metainc`, `metaprop`, and others — each requiring its own decision graph. Analysis of these functions reveals that ~60% of the decision flow is shared:

- **Common flow**: model type selection -> tau-squared estimation -> CI method -> prediction interval -> execution -> heterogeneity assessment -> sensitivity analysis -> publication bias
- **Function-specific**: outcome type confirmation, effect measure selection (varies by outcome type), zero-cell handling (binary only), GLMM model selection (binary only)

Defining independent flat graphs for each function produces massive duplication. When the shared portion changes (e.g., a new tau-squared estimator requires a graph update), every function-specific graph must be updated in sync.

Three approaches were considered:

1. **No composition**: Each function gets a fully independent graph. Accept duplication. Simple but unmaintainable as the number of functions grows.
2. **Runtime fragment imports**: Decision graphs can import named subgraph fragments at runtime. The Graph Engine resolves imports on the fly. Rejected: adds complexity to the runtime, which should only process flat graphs (ADR-0002).
3. **Template + build-time merge**: Shared flows are defined as templates with connection points. Function-specific graphs reference a template and define only their unique nodes. A build-time tool merges them into flat graphs for the runtime.

## Decision

Adopt **option 3**: template + build-time merge with connection points.

### Template definition

A template defines a reusable subgraph with explicit connection points:

```yaml
# shared/common_re_flow.template.yaml
template:
  id: common_random_effects
  entry_point: model_type
  exit_point: execute_analysis
  nodes:
    model_type:
      type: decision
      topic: model_selection
      parameter: [common, random]
      description: "Choose common-effect, random-effects, or both"
      transitions:
        - to: tau2_estimation
          when: "random-effects model is used"
          computable_hint: "random == TRUE"
        - to: execute_analysis
          otherwise: true

    tau2_estimation:
      type: decision
      topic: tau2_estimators
      parameter: method.tau
      transitions:
        - to: ci_method
          always: true

    ci_method:
      type: decision
      topic: confidence_interval_methods
      parameter: [method.random.ci, adhoc.hakn.ci]
      transitions:
        - to: prediction_interval
          always: true

    prediction_interval:
      type: decision
      topic: prediction_intervals
      parameter: [prediction, method.predict]
      transitions:
        - to: execute_analysis
          always: true

    execute_analysis:
      type: execution
      description: "Run analysis with selected parameters"
      transitions: []   # exit_point — connected by the consuming graph
```

- `entry_point`: The node ID where function-specific graphs connect *into* the template.
- `exit_point`: The node ID where the template connects *back to* the function-specific graph. The template's `exit_point` node has empty transitions; the consuming graph provides them.

### Function-specific graph

A function-specific graph references a template and defines only its unique nodes plus the connections at entry and exit points:

```yaml
# decision_graph.yaml (metabin)
graph:
  entry_node: outcome_type
  template: common_random_effects

  nodes:
    outcome_type:
      type: context_gathering
      description: "Inspect data structure and confirm binary outcome"
      transitions:
        - to: sm_selection
          always: true

    sm_selection:
      type: decision
      topic: effect_measures
      parameter: sm
      transitions:
        - to: method_selection
          always: true

    method_selection:
      type: decision
      topic: pooling_methods
      parameter: method
      transitions:
        - to: glmm_model
          when: "GLMM was selected"
          computable_hint: "method == 'GLMM'"
        - to: continuity_correction
          when: "zero cells exist in the data"
        - to: model_type          # -> template entry_point
          otherwise: true

    glmm_model:
      type: decision
      topic: glmm_models
      parameter: model.glmm
      transitions:
        - to: model_type          # -> template entry_point
          always: true

    continuity_correction:
      type: decision
      topic: zero_cell_handling
      parameter: [incr, method.incr, allstudies]
      transitions:
        - to: model_type          # -> template entry_point
          always: true

    # Nodes after template exit_point (execute_analysis)
    heterogeneity_assessment:
      type: diagnosis
      topic: heterogeneity
      transitions:
        - to: sensitivity_analysis
          when: "heterogeneity is moderate or higher"
          computable_hint: "I2 > 50"
        - to: publication_bias
          otherwise: true

    sensitivity_analysis:
      type: decision
      topic: sensitivity_approaches
      transitions:
        - to: execute_analysis    # loop back into template
          when: "re-run with different parameters"
        - to: publication_bias
          otherwise: true

    publication_bias:
      type: decision
      topic: bias_assessment
      parameter: method.bias
      transitions:
        - to: complete
          always: true

    complete:
      type: context_gathering
      description: "Summarize results and generate report"
      transitions: []
```

### Build-time merge

`build_graph("metabin")` produces a flat `decision_graph.yaml` by:

1. Loading the template YAML.
2. Loading the function-specific YAML.
3. Merging template nodes into the function-specific graph (namespace collision = error).
4. Connecting the template's `exit_point` node to the transitions defined in the function-specific graph that reference post-exit nodes (the `execute_analysis` node gains the `heterogeneity_assessment` transition).
5. Validating the merged graph (reachability, no dangling references).
6. Writing the flat result.

### Boundary rule

Template internals **cannot be overridden** by the consuming graph. If a function needs a different version of a template node, it must either: (a) not use the template and define the full graph, or (b) a new template variant is created. This strict boundary keeps merge logic simple and prevents subtle bugs from partial overrides.

### Runtime impact

**None.** The runtime always receives and processes a flat decision graph. Templates and composition are build-time concerns only. This preserves ADR-0002's simple runtime model.

## Consequences

- **Easier**: Shared decision logic is defined once and reused — changes propagate automatically to all consuming graphs
- **Easier**: Runtime complexity is unaffected — flat graphs only, as established in ADR-0002
- **Easier**: Connection points create a clear boundary between shared and function-specific logic
- **Harder**: A build step is required before the runtime can use a composed graph — the plugin generation pipeline must include `build_graph()`
- **Harder**: Template versioning may become necessary if different functions need slightly different shared flows
- **Harder**: The strict no-override rule means some duplication remains when a function needs a minor variation of a template node
