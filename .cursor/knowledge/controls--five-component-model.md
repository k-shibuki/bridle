---
trigger: five-component model, control system architecture, Guards component, Surface component, enforcement tier, Deterministic Steering, Hard Stop classification, component boundary
---
# Five-Component Control System

## Architecture

The AI control system comprises five components:

| Component | Location | Purpose |
|-----------|----------|---------|
| **Rules** | `.cursor/rules/*.mdc` | Declare MUST / MUST NOT policies |
| **Commands** | `.cursor/commands/*.md` | Define step-by-step procedures |
| **Knowledge** | `.cursor/knowledge/*.md` | Capture patterns, playbooks, reference |
| **Guards** | `.pre-commit-config.yaml`, `.github/workflows/*.yaml`, `tools/` | Enforce Rules deterministically via hooks, CI, Branch Protection |
| **Surface** | `Makefile`, `README.md`, `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/` | Provide entry points, development API, onboarding |

### Component relationships

```
Surface ──entry point──→ Commands ──constrained by──→ Rules
                         Commands ──references──→ Knowledge
Guards ────enforces────→ Rules
Knowledge ···advisory···→ Commands
```

- Rules **declare** what is prohibited or required.
- Guards **enforce** Rules deterministically — if a Guard exists for a Rule, compliance is 100%.
- Commands **implement** workflows, constrained by Rules and referencing Knowledge.
- Knowledge **advises** Commands with patterns and gotchas.
- Surface **exposes** the system to users (human and AI) as the first point of contact.

### Migration from 3-layer model

The original "Three-Layer Control System" (Rules, Commands, Knowledge) left two
categories of controls unnamed:

- Git hooks, CI workflows, and Branch Protection were treated as infrastructure,
  not as first-class controls. This meant Hard Stops declared in Rules had no
  deterministic enforcement — compliance depended entirely on agent self-policing.
- Makefile targets, READMEs, and Issue templates were called "controls" in
  `.cursor/README.md` but did not belong to any of the three layers.

The 5-component model resolves both inconsistencies by promoting Guards and
Surface to named components with defined boundaries.

## Hard Stop Enforcement Tiers

Each Hard Stop in `agent-safety.mdc` is classified by enforcement mechanism:

| Tier | Mechanism | Compliance |
|------|-----------|------------|
| **Deterministic** | Enforced by Guards (hooks, CI, Branch Protection) | 100% — tool prevents violation |
| **Steering** | Declared in Rules, agent self-policing | Probabilistic — depends on agent adherence |

Current classification:

- **Deterministic**: HS#1 (Branch Protection), HS#2 (pre-push hook), HS#5 (PR policy CI), HS#8 (pre-commit hook), HS#9 (PR policy CI)
- **Steering**: HS#3 (no step skipping), HS#4 (gate evidence), HS#6 (no dismissing diagnostics), HS#7 (no inline CI polling)

The goal is to maximize the Deterministic tier. When a Steering constraint can be
converted to a Guard, it should be.

## Component Boundary Rules

Each component has a defined responsibility. Violations occur when content crosses
boundaries (detected by `controls-review` Step 5):

- Rules MUST NOT contain procedures (Step 1, Step 2...).
- Commands MUST NOT declare MUST/MUST NOT policies.
- Knowledge MUST NOT declare MUST/MUST NOT policies.
- Guards MUST NOT embed policy prose — they reference Rules via links.
- Surface MUST NOT contain step-by-step procedures — it links to Commands.
