---
trigger: decision audit log, DecisionLog, JSONL streaming, analyze_log, transition_trace, selection_basis, validate_plugin
---
# ADR-0006: Decision Audit Log

## Context

bridle's runtime produces a stream of decisions: which transition was taken, whether a `computable_hint` was evaluated or the LLM decided, what the user accepted or overrode. This information is critical for:

1. **Evaluation** (vitals, Phase 3): Measuring whether the system makes correct recommendations requires comparing actual flows against gold-standard flows. Without structured logs, this comparison is impossible.
2. **Plugin improvement**: Identifying patterns of user rejection (e.g., "users override tau2 recommendation 40% of the time") pinpoints weak knowledge entries or incorrect graph structure.
3. **Debugging**: When a session produces an unexpected recommendation, the audit trail must show exactly which evaluation path was taken and why.

The question is when and how to design this logging infrastructure. Two timing options were considered:

1. **Design at Phase 3** (alongside vitals). Rejected: Phase 1-2 runtime implementation would emit ad-hoc logs that may not capture the fields needed for evaluation.
2. **Design at Phase 0, implement incrementally**. The schema is defined now; Phase 2 implements basic logging; Phase 3 adds `analyze_log()` and vitals integration.

Three format options were considered:

1. **S7 objects only**: In-memory `DecisionLog` class, exported at session end. Risk: data loss on crash.
2. **JSONL stream**: One JSON object per event, appended to a file in real time. Crash-resistant, parseable by external tools.
3. **Both**: S7 in-memory + JSONL file. Rejected: unnecessary implementation cost for the initial phase.

## Decision

Adopt **JSONL streaming** as the log format. Define the log entry schema at Phase 0. The schema is designed to contain all information needed for future LLM-assisted plugin improvement (`suggest_improvements()`), even though only manual analysis (`analyze_log()`) is implemented initially.

### Activation

Logging is **enabled by default** and can be disabled via `bridle_agent(log = FALSE)`. The performance overhead is negligible (one `writeLines()` call per node visit).

### Log entry structure

Each line in the JSONL file represents one node visit:

```yaml
entry:
  meta:
    session_id: string
    turn_id: integer
    plugin_name: string
    plugin_version: string
    graph_version: string
    timestamp_utc: string           # ISO 8601

  node_id: string
  node_type: string                 # context_gathering | decision | execution | diagnosis

  transition_trace:
    candidates:
      - to: string
        when: string | null
        computable_hint: string | null
        eval_result: true | false | error | not_evaluated
        fallback_to_llm: boolean
    selected_transition: string
    selection_basis: string         # hint | llm | user | rule

  constraints_trace:
    - id: string
      fired: boolean
      forced_values: map | null

  knowledge_context:
    entry_ids_presented: [string]

  llm_output:
    recommendation_text: string
    suggested_value: string | null

  user_response:
    outcome: string                 # accepted | rejected | modified | aborted
    override_value: string | null
    user_reason: string | null
    quality_signal:
      needs_review: boolean

  decision_state:
    parameters_decided: map
    data_fingerprint:
      n_studies: integer | null
      column_names: [string]
      missing_rate: map | null

  policy_applied:
    skipped: boolean
    skip_reason: string | null
    iteration_count: integer | null
```

Optional fields (defined in schema, omitted in initial implementation):

- `model_context`: `{ provider, model, temperature, prompt_hash }`
- `cost_metrics`: `{ latency_ms, input_tokens, output_tokens }`
- `error_info`: `{ class, message, traceback_ref }`

### Key design choices

- **`selection_basis`** includes `rule` (in addition to `hint`, `llm`, `user`) to distinguish constraint-forced transitions from other selection methods. This enables precise root-cause analysis.
- **`transition_trace.candidates`** records evaluation results for all candidate transitions, not just the selected one. This makes ADR-0003's two-path evaluation fully auditable.
- **`data_fingerprint`** captures anonymous data summaries (study count, column names, missingness) without storing raw data, enabling reproducibility analysis across sessions.

### Feedback loop roadmap

- **Phase 2**: Implement logging in the Graph Engine. Provide `analyze_log()` for summary statistics (override rate by node, fallback rate, session duration).
- **Phase 3**: Integrate with vitals for automated evaluation against gold-standard flows.
- **Future**: `suggest_improvements(log, plugin)` passes log patterns to an LLM to draft knowledge/graph corrections, presented as diffs for expert review.

## Consequences

- **Easier**: All runtime decisions are traceable — debugging and evaluation share the same data source
- **Easier**: JSONL is append-only and crash-resistant; parseable by R (`jsonlite::stream_in`), Python, jq, and other tools
- **Easier**: The schema captures sufficient context for future LLM-assisted improvement without redesign
- **Harder**: Every node visit must serialize its state to JSON, adding implementation surface across the Graph Engine, Knowledge Retriever, and Response Parser
- **Harder**: Log files can grow large for extended sessions; rotation or summarization may be needed later
