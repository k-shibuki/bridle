# ADR-0002: Decision Graph as Flow Control Mechanism

## Context

bridle's runtime guides users through an R package's parameter space via interactive dialogue. Two approaches for controlling this dialogue flow were considered:

1. **LLM free-flow**: The LLM freely references knowledge entries and autonomously decides what to ask next.
2. **Decision-graph-driven**: A YAML-defined graph structure dictates the flow; the runtime holds the initiative.

LLM free-flow is flexible but has critical drawbacks: low reproducibility (the same data and knowledge can produce different flows each run), no coverage guarantee (the LLM may skip important parameters), and difficulty evaluating correctness with vitals (no defined "correct flow" to measure against).

Analysis of `meta::metabin` (60+ formals) revealed that only ~15 parameters require actual decisions; the rest are presentation, data input, or deprecated. These ~15 parameters have a natural decision ordering (effect measure -> pooling method -> tau-squared estimator -> CI method -> ...) that maps well to a graph structure.

Additionally, statistical analysis inherently involves post-fit diagnosis -> parameter change -> refit loops (e.g., GLM overdispersion diagnosis, meta-analysis sensitivity analysis). A DAG cannot express these patterns.

## Decision

Use a **decision graph** (`decision_graph.yaml`) as the core flow-control mechanism in each plugin. The graph is a directed graph (cycles allowed) where:

- **Nodes** represent decision points, each typed as `context_gathering`, `decision`, `execution`, or `diagnosis`.
- **Transitions** between nodes carry conditions: unconditional (`always`), conditional (`when` + optional `computable_hint`; see ADR-0003), or fallback (`otherwise`).
- **Cycles** are permitted — specifically, `diagnosis -> decision -> execution -> diagnosis` loops for sensitivity analysis and post-diagnostic refitting. Infinite-loop prevention is a runtime responsibility (max iteration limits).

The decision graph is drafted by the AI Drafter from `scan_package()` results and refined by expert review. The formal schema is defined in `docs/schemas/decision_graph.schema.yaml`.

## Consequences

- **Easier**: Explicit, reproducible flow control. Evaluation via vitals becomes straightforward since expected flows are defined
- **Easier**: Knowledge retrieval strategy is clear — the current node's `topic` determines which entries to load
- **Easier**: Coverage is verifiable — `validate_plugin` can check that all statistical-decision parameters appear in the graph
- **Harder**: Different analysis types within the same package (e.g., pairwise binary vs. continuous) may require separate graphs
- **Harder**: Overly rigid graph structure can suppress LLM flexibility; transition condition granularity must be tuned carefully
