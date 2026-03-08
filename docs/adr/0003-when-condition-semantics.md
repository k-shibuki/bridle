---
trigger: when condition, computable_hint, data condition, post-fit condition, LLM interpretation, R expression evaluation, technical constraint
---
# ADR-0003: When Condition Semantics

## Context

Knowledge entries and decision graph transitions both use a `when` field to express "under what circumstances does this apply?" Concrete analysis reveals four inherently different categories:

| Category | Example | Evaluation |
|---|---|---|
| Data condition | `k < 5`, `any(events == 0)` | Computable as an R expression |
| Post-fit condition | `I2 > 75`, `residual deviance / df > 1.5` | Computable after model fitting |
| Technical constraint | `method == 'Peto'` forces `sm = 'OR'` | Rule-based at parameter selection |
| Contextual condition | "event rate is very low", "intervention protocols vary across studies" | Requires LLM judgment |

Three design alternatives were considered:

1. **Typed hybrid**: `when` carries an explicit `type: computable | interpretive`. Computable conditions are R-evaluated; interpretive ones go to the LLM. Rejected: schema complexity is high, and the type boundary is blurry (a condition may be computable in one context but not another).
2. **All LLM interpretation**: `when` is always natural-language text; the LLM handles everything. Rejected: numeric conditions like `k < 5` are unreliable when delegated to the LLM (the LLM may misread the value of k from context).
3. **Natural language + computable hint**: `when` is human-readable natural language; `computable_hint` is an optional R expression. The runtime uses the hint when it can evaluate it and falls back to LLM interpretation otherwise.

## Decision

Adopt **option 3**: `when` is always a natural-language string; `computable_hint` is an optional R expression.

Evaluation rules:

1. No `computable_hint` present -> LLM judges from `when` text
2. `computable_hint` present and all required variables are in scope -> evaluate as R expression
3. `computable_hint` present but required variables are undefined -> fall back to LLM on `when` text
4. `computable_hint` evaluation errors -> fall back to LLM on `when` text

Technical constraints (`Peto -> OR`) are separated into `constraints/technical.yaml` and do not use the `when` mechanism.

## Consequences

- **Easier**: Simple YAML schema — `when` is always a string, `computable_hint` is an optional string
- **Easier**: Natural for expert review — reading `when` conveys intent; an R expression alone does not explain "why 5?"
- **Easier**: Supports incremental quality improvement — start with `when` only, add `computable_hint` later
- **Harder**: The runtime carries two evaluation paths (R expression / LLM fallback), requiring care to ensure consistent behavior
