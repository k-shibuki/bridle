---
trigger: scanner resilience, Layer 3a, Layer 3b, dry-run fuzzing, review_scan, export_scan, import_scan, confidence grading, withCallingHandlers, function classification review
---
# ADR-0008: Scanner Resilience

## Context

ADR-0004 established a three-layer analysis strategy for `scan_package()`: Layer 1 (formals), Layer 2 (Rd), and Layer 3 (source code). ADR-0004 acknowledged that "source code analysis is inherently fragile" and that "Layer 3 can be implemented incrementally after Layer 1+2."

However, ADR-0004 did not define what happens when Layer 3 partially or fully fails. Concrete failure modes include:

- **Complex conditional `stop()`**: Nested helper function calls or dynamically constructed error messages that regex-based parsing cannot extract.
- **Namespace-qualified calls**: `pkg::fn()` patterns where `getParseData()` does not produce a `SYMBOL_FUNCTION_CALL` token, requiring additional AST traversal.
- **Obfuscated `match.arg()`**: Indirect usage like `do.call(match.arg, ...)` or custom wrapper functions.

The practical impact of Layer 3 failure is significant: `stop()` constraints (e.g., "allstudies applies only when sm is RR, OR, or DOR") are entirely absent from Layer 1 and Layer 2. Missing these constraints means the runtime may allow the LLM to propose invalid parameter combinations.

Three resilience strategies were considered:

1. **Silent fallback**: Layer 3 fails silently; Layer 2 results are used without notification. Rejected: users cannot know which constraints might be missing.
2. **Warning-based fallback**: Layer 2 results are used with a `cli::cli_warn()` notification. Rejected: warnings are easily ignored and provide no remediation path.
3. **Multi-stage extraction with interactive review**: Combine static parsing (L3a) with dry-run fuzzing (L3b) to maximize extraction, grade confidence, and provide `review_scan()` for interactive gap resolution.

## Decision

Adopt **option 3**: multi-stage extraction with confidence grading and interactive review.

### Extraction pipeline

```
scan_package("meta", "metabin")
  |-> Layer 1: formals()        [always succeeds]
  |-> Layer 2: Rd               [always succeeds]
  |-> Layer 3a: source parsing  [may partially fail]
  |-> Layer 3b: dry-run fuzzing [fills gaps from 3a]
  |-> confidence grading
  |-> ScanResult with gaps marked
        |-> review_scan()  [interactive, optional]
        |-> export_scan()  [persist for reuse]
```

**Layer 3a** (static source parsing) remains as defined in ADR-0004: regex/AST-based extraction of `match.arg()`, `stop()`, and `warning()` patterns.

**Layer 3b** (dry-run fuzzing) supplements Layer 3a by actually executing the function with systematically generated parameter combinations:

- Parameter combinations are generated from Layer 2 `valid_values` via `expand.grid()` (with smart pruning to avoid combinatorial explosion).
- Test data is obtained from `data(package = ...)` or extracted from `tools::Rd2ex()` examples.
- Each combination is executed inside `withCallingHandlers()` + `tryCatch()`. Errors and warnings are captured along with stack traces via `sys.calls()` or `rlang::trace_back()`.
- Captured error/warning messages are parsed into constraint entries.

### Confidence grading

Each constraint receives a `confidence` grade based on quantitative criteria:

| Grade | Criteria | Example |
|---|---|---|
| `high` | Confirmed by 2+ layers | Rd valid_values matches `match.arg()` in source |
| `medium` | Single-layer extraction | Rd-only valid_values, or formals-only dependency |
| `low` | Expert or LLM-estimated | `source: expert` with empty `confirmed_by` |
| `gap` | Layer 3 failed; constraint may exist but is unverified | Static parsing failed and dry-run did not trigger the code path |

Constraints carry two new fields:

```yaml
confirmed_by: ["source_code"]   # list of confirming layers
confidence: high                # high | medium | low | gap
```

### Interactive review and persistence

- **`review_scan(scan_result)`**: Displays `gap` entries interactively. For each gap, the user can: ignore (accept `gap` status), add a constraint manually (`source: expert`), or request LLM estimation (`confidence: low`).
- **`export_scan(scan_result, path)`**: Serializes the (possibly reviewed) `ScanResult` to YAML for reuse.
- **`import_scan(path)`**: Restores a previously exported `ScanResult`, avoiding re-scanning and preserving manual additions.

This export/import cycle means that expert corrections persist across re-scans: import the previous result, re-scan to pick up package updates, merge new findings with existing expert entries.

### Addendum to ADR-0004

This ADR extends ADR-0004 without modifying it. ADR-0004's three-layer design is preserved; ADR-0008 adds:

- Layer 3b (dry-run fuzzing) as a complement to Layer 3a (static parsing)
- Confidence grading on all constraints
- `review_scan()` / `export_scan()` / `import_scan()` for interactive remediation and persistence

## Consequences

- **Easier**: Layer 3 failures are recoverable rather than silently degrading constraint quality
- **Easier**: Confidence grading makes constraint reliability transparent to both `validate_plugin()` and expert reviewers
- **Easier**: Export/import enables incremental improvement — expert corrections survive package updates and re-scans
- **Harder**: Dry-run fuzzing requires test data and may trigger side effects in poorly-behaved packages (sandboxing needed)
- **Harder**: Interactive review adds a human-in-the-loop step that may slow down fully automated plugin generation
- **Harder**: The confidence grading system requires maintenance as new extraction methods are added

## Addendum: Function Classification in review_scan()

### Motivation

ADR-0004 Addendum introduces heuristic-based function classification (analysis / visualization / diagnostic / utility) as part of package-level scanning. Heuristics are imperfect — a function like `escalc` (effect size calculator) may be misclassified as "utility" when it is central to the analysis workflow. Expert correction must be possible.

### Extended review_scan() scope

`review_scan(scan_result)` is extended from reviewing only constraint gaps to also reviewing function classifications:

1. **Constraint gaps** (original scope): Present `gap`-confidence constraints for expert resolution.
2. **Function classification review** (new scope): Present functions whose auto-classification has low confidence or ambiguous heuristic signals.

Classification confidence is determined by the number of agreeing heuristic signals:

| Confidence | Criteria |
|------------|----------|
| `high` | 3+ heuristic signals agree (e.g., formals pattern + Rd title + return type) |
| `medium` | 2 signals agree |
| `low` | 1 signal or conflicting signals |
| `unclassified` | No signals matched any role |

Functions with `low` or `unclassified` confidence are presented to the expert during `review_scan()`.

### Interaction format

```
review_scan(scan_result)
# -- Function Classification Review --
# escalc: classified as "utility" (confidence: low)
#   Signals: formals include "measure" (+analysis), Rd title is "Calculate Effect Sizes" (+utility)
#   Override? [analysis / visualization / diagnostic / utility / keep]
```

### Persistence

Classification overrides are stored in the `PackageScanResult@function_roles` property and persisted via `export_scan()` / `import_scan()`. On re-scan, previously overridden classifications are preserved unless the function's signature has changed.
