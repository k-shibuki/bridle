---
trigger: AI development system, Design domain, Controls domain, control system architecture, Guards component, Surface component, enforcement tier, Deterministic Steering, Hard Stop classification, component boundary, five-component model
---
# AI Development System

## Architecture

The AI development system is organized as a two-domain tree: **Design** defines
what to build and why; **Controls** govern how to build it.

```
AI Development System
├── Design (what & why)
│   ├── ADRs          docs/adr/
│   └── Schemas       docs/schemas/
│
└── Controls (how)
    ├── Rules          .cursor/rules/        ← policy
    ├── Commands       .cursor/commands/     ← procedure
    ├── Knowledge      .cursor/knowledge/    ← reference
    ├── Guards         hooks, CI, BP         ← enforcement
    └── Surface        Makefile, README, …   ← entry point
```

### Design domain

| Element | Location | Purpose |
|---------|----------|---------|
| **ADRs** | `docs/adr/*.md` | Record architectural decisions with context, rationale, and consequences. Immutable once accepted. |
| **Schemas** | `docs/schemas/*.yaml` | Define data contracts for plugin artifacts during design phase |

Design documents **constrain** Controls: implementation choices must be consistent
with accepted ADRs and schema contracts. Unlike Knowledge (advisory), Design
carries architectural authority — deviating from an ADR requires a new ADR that
supersedes it.

### Controls domain

| Component | Location | Purpose |
|-----------|----------|---------|
| **Rules** | `.cursor/rules/*.mdc` | Declare MUST / MUST NOT policies |
| **Commands** | `.cursor/commands/*.md` | Define step-by-step procedures |
| **Knowledge** | `.cursor/knowledge/*.md` | Capture patterns, playbooks, reference |
| **Guards** | `.pre-commit-config.yaml`, `.github/workflows/*.yaml`, `tools/` | Enforce Rules deterministically via hooks, CI, Branch Protection |
| **Surface** | `Makefile`, `README.md`, `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/` | Provide entry points, development API, onboarding |

### Domain and component relationships

```
Design ──constrains──→ Controls (implementation must follow ADRs)

Within Controls:
  Surface ──entry point──→ Commands ──constrained by──→ Rules
                           Commands ──references──→ Knowledge
  Guards ────enforces────→ Rules
  Knowledge ···advisory···→ Commands
```

- **Design** records architectural truth. ADRs are immutable; schemas evolve with the codebase.
- **Rules** declare what is prohibited or required within Controls.
- **Guards** enforce Rules deterministically — if a Guard exists for a Rule, compliance is 100%.
- **Commands** implement workflows, constrained by Rules and referencing Knowledge.
- **Knowledge** advises Commands with patterns and gotchas.
- **Surface** exposes the system to users (human and AI) as the first point of contact.

### Evolution history

The original "Three-Layer Control System" (Rules, Commands, Knowledge) left two
categories unnamed: deterministic enforcement (Guards) and entry points (Surface).
The 5-component model resolved this. The current tree structure adds a Design
domain for ADRs and schemas, which were previously referenced but not formally
positioned in the system.

## Hard Stop Enforcement Tiers

Each Hard Stop in `agent-safety.mdc` is classified by enforcement mechanism:

| Tier | Mechanism | Compliance |
|------|-----------|------------|
| **Deterministic** | Enforced by Guards that are always active (CI workflows, Branch Protection) | 100% — tool prevents violation without setup |
| **Conditionally Deterministic** | Enforced by Guards that require local setup (`make install-hooks`) | 100% when activated, 0% otherwise |
| **Steering** | Declared in Rules, agent self-policing | Probabilistic — depends on agent adherence |

Current classification: See `agent-safety.mdc` § Enforcement Tiers for the authoritative HS-to-tier mapping.

The goal is to maximize the Deterministic tier. When a Steering constraint can be
converted to a Guard, it should be. Conditionally Deterministic Guards should be
promoted to Deterministic where possible (e.g., by adding CI-level checks as
fallback).

## Component Boundary Rules

Each domain and component has a defined responsibility. Violations occur when
content crosses boundaries (detected by `controls-review` Step 6). The boundary
constraints are defined in `@.cursor/rules/coding-policy.mdc` and enforced by
`controls-review`:

- Design records decisions and contracts, not procedures or operational policies
- Rules declare policies (conditions, requirements), not procedures (numbered steps)
- Commands define procedures, referencing Rules via `@` links rather than re-declaring policies
- Knowledge provides advisory patterns and references; policy authority belongs to Rules
- Guards implement enforcement logic and reference Rules for justification
- Surface provides entry points and summaries, linking to Commands for detailed procedures
