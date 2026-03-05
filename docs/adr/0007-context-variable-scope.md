# ADR-0007: Context Variable Scope

## Context

Knowledge entries and decision graph transitions use `computable_hint` (ADR-0003) — R expressions like `k < 5` or `I2 > 50` that the runtime evaluates when possible. For evaluation to succeed, the runtime must know:

1. **Which variables exist** (`k`, `I2`, `event.e`, etc.)
2. **When each variable becomes available** (after data loading? after model fitting?)
3. **How to obtain each variable's value** (an R expression that extracts it from the session state)

Without a formal variable scope definition, `computable_hint` evaluation is unpredictable: hints may fail not because the condition is inherently unevaluable, but because the runtime doesn't know whether or how to compute the required variable.

The README lists `context_schema.yaml` as a plugin artifact but provides no schema definition. Three approaches were considered:

1. **Fully static declaration**: All variables that `computable_hint` may reference are declared in `context_schema.yaml` with their availability phase and extraction expression. Rejected: data column names (e.g., `event.e`, `n.c`) vary across datasets and cannot be pre-declared.
2. **Fully dynamic detection**: The runtime inspects the current environment (`ls()`, `names(data)`) to determine available variables. No schema needed. Rejected: `validate_plugin()` cannot statically verify that hint expressions reference valid variables; errors surface only at runtime.
3. **Hybrid**: Core statistical quantities (study count, heterogeneity metrics, etc.) are statically declared; data column names are dynamically detected at runtime.

## Decision

Adopt **option 3**: hybrid static + dynamic variable scope.

### Static declarations

`context_schema.yaml` declares variables whose names are known in advance:

```yaml
variables:
  - name: k
    description: "number of studies"
    available_from: data_loaded
    source_expression: "nrow(data)"

  - name: I2
    description: "I-squared heterogeneity statistic"
    available_from: post_fit
    depends_on_node: execute_analysis
    source_expression: "result$I2"

  - name: tau2
    description: "estimated between-study variance"
    available_from: post_fit
    depends_on_node: execute_analysis
    source_expression: "result$tau2"
```

Each variable specifies:
- `available_from`: Phase when the variable becomes computable. One of `data_loaded`, `parameter_decided`, or `post_fit`.
- `depends_on_node` (optional): The specific graph node after which this variable is available. Enables fine-grained availability checking.
- `source_expression`: R expression the runtime evaluates to obtain the value.

### Dynamic detection

Data column names (e.g., `event.e`, `n.c`) are not declared in `context_schema.yaml`. The runtime detects them via `names(data)` after data loading. Hint expressions referencing data columns are evaluated opportunistically — if the column exists, evaluation proceeds; if not, the runtime falls back to LLM judgment per ADR-0003 rules.

### Data expectations

`context_schema.yaml` also defines expected data structure for the plugin:

```yaml
data_expectations:
  - column: event.e
    role: outcome
    required: true
  - column: n.e
    role: group
    required: true
```

This is informational (used by `context_gathering` nodes and `validate_plugin()`) but does not restrict which columns `computable_hint` may reference.

### Validation rules

`validate_plugin()` checks:
- Every `computable_hint` in the decision graph and knowledge entries is parsed with `all.vars()` to extract referenced variable names.
- Variables matching static declarations are verified: does `available_from` / `depends_on_node` make sense given the node's position in the graph?
- Variables not in static declarations are assumed to be dynamic (data columns) and are not flagged as errors.

## Consequences

- **Easier**: `computable_hint` evaluation becomes predictable — the Graph Engine knows exactly when each core variable is available
- **Easier**: `validate_plugin()` can catch common errors (e.g., referencing `I2` before `execute_analysis`) at plugin build time
- **Easier**: Dynamic detection avoids forcing plugin authors to enumerate every possible data column name
- **Harder**: The runtime maintains a variable scope that evolves as nodes are traversed — scope management adds implementation complexity
- **Harder**: Validation is partial — dynamic variables cannot be checked statically, so some hint failures remain runtime-only
