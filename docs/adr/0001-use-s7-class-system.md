# ADR-0001: Use S7 Class System

## Context

bridle defines core domain objects — `DecisionGraph`, `Node`, `KnowledgeEntry`, `Constraint`, `ScanResult` — that flow through the generation pipeline and runtime engine. These objects need formal structure: validated properties, clear contracts, introspectable fields, and extensibility for plugin authors.

R offers four OOP systems:

- **S3**: Minimal formalism. No property declarations, no validation at construction. Ubiquitous but relies on convention over enforcement.
- **S4**: Formal classes with slots and validity methods. Verbose syntax, complex method dispatch rules, not widely adopted outside Bioconductor.
- **R6**: Reference semantics (mutable objects). Well-suited for stateful services but at odds with R's copy-on-modify convention. No method dispatch integration with the S3/S4 ecosystem.
- **S7**: R Consortium's next-generation system. Formal properties with validators, clean syntax via `new_class()`, compatible with S3 generics, active development by Hadley Wickham and the R Consortium OOP Working Group.

bridle's technology stack is rooted in the Posit ecosystem (ellmer, ragnar, vitals), all of which are adopting S7. Domain objects like `DecisionGraph` benefit from property validators (e.g., ensuring all transition targets reference existing nodes) and the ability to define generics that dispatch on bridle types.

## Decision

Use **S7** for all core domain classes in the bridle package.

- Define classes with `S7::new_class()` and property validators for construction-time invariants
- Register methods in `.onLoad()` via `S7::methods_register()`
- Export class constructors for user-facing instantiation
- Use `S7::prop()` for property access to maintain compatibility with R < 4.3.0 (where `@` for S7 is not yet supported)

## Consequences

- **Easier**: Clear contracts with validated properties catch malformed plugins at load time rather than at runtime
- **Easier**: Alignment with the Posit/tidyverse ecosystem — same OOP conventions as the packages bridle depends on
- **Easier**: S7 generics integrate with existing S3 method dispatch, so bridle objects work naturally with `print()`, `format()`, etc.
- **Harder**: S7 is newer; fewer community examples and patterns compared to S3 or R6
- **Harder**: Plugin authors must learn S7 if they want to extend bridle classes (mitigated by the fact that most plugin authoring is YAML-based)
