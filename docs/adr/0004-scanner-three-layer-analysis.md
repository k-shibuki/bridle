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
