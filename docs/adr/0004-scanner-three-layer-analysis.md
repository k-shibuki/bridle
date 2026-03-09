---
trigger: scan_package, ScanResult, PackageScanResult, three-layer analysis, formals, Rd, Layer 1 Layer 2 Layer 3, match.arg, dependency graph, source code analysis, package-level scanning, function classification, function family, cross-function constraint
---
# ADR-0004: Scanner Three-Layer Analysis

## Context

`bridle::scan_package()` analyzes an R package to produce a `ScanResult` that feeds the plugin generation pipeline. The question is how deeply to analyze.

R has a language-level property that other ecosystems lack: **`formals()` retains default values as unevaluated expressions**. For example, `meta::metabin` has:

```r
sm = ifelse(!is.na(charmatch(tolower(method), c("peto", "glmm", "lrp", "ssw"),
                              nomatch = NA)), "OR", gs("smbin"))
```

Parsing this expression mechanically reveals that `sm` depends on `method`, and that `method` being one of `"peto"`, `"glmm"`, `"lrp"`, or `"ssw"` forces `sm` to `"OR"`. Similarly:

- `Q.Cochrane = gs("Q.Cochrane") & method == "MH" & method.tau == "DL"` — three-way dependency
- `random = gs("random") | !is.null(tau.preset)` — implicit random effects when `tau.preset` is set
- `method.bias = ifelse(sm == "OR", "Harbord", ifelse(sm == "DOR", "Deeks", ...))` — default varies by `sm`

This dependency graph is critical input for drafting the decision graph (ADR-0002). However, formals alone do not provide valid-value enumerations (found in Rd) or runtime-enforcement constraints (found in source code).

Three depth levels were considered:

1. **formals only** — Cheapest, but misses valid-value lists and runtime constraints.
2. **formals + Rd** — Adds valid values, parameter descriptions, and reference lists from man pages.
3. **formals + Rd + source** — Additionally extracts `match.arg()` enumerations and `stop()`/`warning()` constraints from source code.

## Decision

`scan_package()` analyzes **all three layers**:

- **Layer 1 (formals)**: Parameter names, default expressions, AST-parsed dependency graph, automatic parameter classification by naming convention.
- **Layer 2 (Rd)**: Valid-value lists, parameter descriptions, Details section content, References section bibliography, deprecated-parameter detection.
- **Layer 3 (source)**: `match.arg()` confirmation, `stop()`/`warning()` constraint extraction.

Layer 3 is the most implementation-costly and may not be fully achievable for all packages. The design is additive: Layer 1+2 results are useful on their own, and Layer 3 refines them.

## Consequences

- **Easier**: Maximally comprehensive input for the AI Drafter, yielding higher-quality decision graph and knowledge drafts
- **Easier**: The formals dependency graph — unique to R — gives the drafter structural information that would otherwise require human analysis
- **Easier**: Layers are additive, so Layer 3 can be implemented incrementally after Layer 1+2
- **Harder**: Source code analysis is inherently fragile; `stop()` condition parsing cannot guarantee full accuracy
- **Harder**: Package internals may change across versions, requiring re-scans

## Addendum: Scanner Resilience (see ADR-0008)

ADR-0008 extends this decision with:

- **Layer 3b** (dry-run fuzzing): When Layer 3a static parsing fails, systematically execute the function with generated parameter combinations, capturing errors/warnings via `withCallingHandlers()` + stack traces. Fills gaps that regex-based parsing misses.
- **Confidence grading**: Each constraint receives `confidence` (high/medium/low/gap) and `confirmed_by` fields based on how many layers confirmed it. See ADR-0008 for grading criteria.
- **Interactive review**: `review_scan()` presents gaps for expert resolution. `export_scan()` / `import_scan()` persist corrected results across re-scans.

## Addendum: Package-Level Scanning

### Motivation

The original `scan_package(package, func)` API analyzes one function at a time. For packages like `metafor`, the decision space spans an entire function family (e.g., `rma.uni`, `rma.mh`, `rma.peto`, `rma.glmm`, `rma.mv`) — choosing *which* function to call is itself a core decision. A package-level scan is required to map the full decision space and produce plugins that guide function selection, not just parameter selection within a single function.

### API change

The public API becomes `scan_package(package)` with a single argument (the package name). The previous two-argument form is removed; function-level scanning is demoted to an internal helper `scan_function()`.

### Processing pipeline

```
scan_package("metafor")
  |-> 1. Function enumeration: getNamespaceExports()
  |-> 2. S3 method exclusion: filter registered S3 methods (print.*, summary.*, etc.)
  |-> 3. Function classification: heuristic assignment of roles
  |-> 4. Per-function scan: Layer 1-3 for analysis functions
  |-> 5. Family detection: shared prefix + Rd alias grouping
  |-> 6. Family structure construction (Option B)
  |-> 7. Cross-function constraint extraction
  |-> PackageScanResult
```

### Function classification

Each exported function receives a role based on heuristic signals:

| Role | Heuristic signals | Example (metafor) |
|------|------------------|-------------------|
| `analysis` | Returns a model object; formals include `data`, `method`, or `measure`; Rd title contains "fit", "model", "analysis" | `rma.uni`, `rma.mh`, `escalc` |
| `visualization` | Formals include `x` as first arg with model class; calls `plot()` or `grid` graphics; Rd title contains "plot", "forest", "funnel" | `forest.rma`, `funnel.rma` |
| `diagnostic` | Operates on a fitted model; returns influence/residual statistics; Rd title contains "influence", "diagnostic", "residual" | `influence.rma.uni`, `leave1out.rma.uni` |
| `utility` | Data manipulation, formatting, or conversion functions that do not fit the above | `to.long`, `to.table`, `reporter` |

Classification is heuristic and may misclassify. ADR-0008 Addendum extends `review_scan()` to allow expert override of classifications.

### Family detection and structure (Option B)

Functions sharing a common prefix (e.g., `rma.*`) are grouped into families. Family structure uses **Option B: common parameters + per-function differences**, chosen because:

- **Subset relationships** (rma.peto ⊂ rma.uni: all 16 peto formals appear in rma.uni) are naturally expressed as a common set with an empty diff for the subset member.
- **Sibling relationships** (rma.mv shares only 15 of rma.uni's 48 formals, with 13 unique formals) cannot be reduced to a canonical form. Option B treats siblings symmetrically.

```yaml
families:
  rma:
    common_parameters: [yi, vi, data, slab, subset, level, verbose]
    members:
      rma.uni:
        unique_parameters: [sei, weights, ni, m1i, m2i, sd1i, sd2i, ...]
      rma.mh:
        unique_parameters: [measure, ai, bi, ci, di, ...]
      rma.peto:
        unique_parameters: []  # subset of rma.uni
      rma.mv:
        unique_parameters: [V, W, random, struct, ...]
```

### Cross-function constraints

Function selection can impose parameter constraints:

```yaml
cross_function_constraints:
  - function: rma.peto
    constraint: measure == "OR"
    reason: "Peto's method is defined only for odds ratios"
  - function: rma.mh
    constraint: measure %in% c("OR", "RR", "RD", "IRR", "IRD")
    reason: "Mantel-Haenszel works with specific 2x2 table measures"
```

These are extracted by comparing function-specific `match.arg()` enumerations with the family-wide parameter space.

### Output: PackageScanResult

A new S7 class `PackageScanResult` with properties:

| Property | Type | Description |
|----------|------|-------------|
| `@package` | `character(1)` | Package name |
| `@functions` | named `list` of `ScanResult` | Per-function scan results keyed by function name |
| `@function_roles` | named `character` | Role assignment per function (analysis/visualization/diagnostic/utility) |
| `@function_families` | `list` | Family structures (common params + per-function diffs) |
| `@cross_function_constraints` | `list` | Constraints implied by function selection |
| `@scan_metadata` | `list` | Package version, scan timestamp, bridle version |

### Interaction with ADR-0009 (Template Composition)

When `draft_knowledge()` receives a `PackageScanResult`, it generates:

- A top-level decision node for function/method selection (e.g., "Choose analysis approach: standard RE, MH, Peto, GLMM, multivariate")
- Per-function templates following ADR-0009's composition pattern
- `build_graph()` merges them into a single flat decision graph

This connects scanner output to the template composition system without modifying the runtime (which processes flat graphs only, per ADR-0002).
