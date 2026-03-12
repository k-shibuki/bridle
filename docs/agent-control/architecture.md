# Agent Control System for AI-Driven Development

## Purpose

In AI-driven development, AI agents autonomously execute the full
development lifecycle — from Issue selection through implementation,
testing, review, and PR merge. This control system constrains agent
behavior by designing the information space the agent operates within.

Rather than prescribing step-by-step procedures, the system presents
the agent with structured observations (Evidence), declarative
constraints (Principle), and project-specific semantics (Knowledge).
The agent's own reasoning operates within this well-defined
information space.

The system is NOT:

- A code generation framework
- A runtime agent orchestrator
- A project management tool

The system IS:

- A design of the **information space** presented to the agent
- A set of **declarative constraints** that bound agent reasoning
- A collection of **structured observations** that the agent consumes

## Design principles

1. Don't make the agent memorize procedures. Show it state.
2. Don't let observation be ad hoc. Structure it.
3. Don't bury invariants in procedures. Declare them separately.
4. Limit Knowledge to semantics. Never mix in execution.
5. Keep Procedure thin. It is not the thinking itself.
6. Self-improvement starts with Evidence, not Principle. Don't let
   the agent modify its own rules.
7. Treat the control system itself as testable software.

## Components

The control system has 6 components:

```
Controls
├── Principle      .cursor/rules/        ← invariants + policies
├── Procedure      .cursor/commands/     ← thin entry points (Sense → Orient → Act)
├── Knowledge      .cursor/knowledge/    ← project-specific semantics
├── Evidence       Makefile + tools/     ← structured observation → JSON
├── Guard          hooks, CI, BP         ← deterministic enforcement
└── Interface      AGENTS.md, .cursor/templates/, .github/*TEMPLATE*  ← external entry points
```

The architecture design document lives in `docs/agent-control/`
(Design domain), not inside Controls.

| Component | Responsibility | What it must NOT contain |
|-----------|---------------|------------------------|
| **Principle** | Declare MUST / MUST NOT policies, invariants | Procedures (numbered steps), observation commands |
| **Procedure** | Thin SOA entry points: Sense (read evidence) → Orient (classify state) → Act (invoke tool) | Judgment logic, embedded observation, policy declarations |
| **Knowledge** | Project-specific semantics: patterns, gotchas, domain heuristics | CLI commands, API calls, executable procedures |
| **Evidence** | Structured observation via `make` targets → JSON | Policy decisions, workflow logic |
| **Guard** | Deterministic enforcement of Principle | Policy content (reference Principle for justification) |
| **Interface** | External entry points for humans and AI agent reviewers (`AGENTS.md`, `.cursor/templates/`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/`) | Implementation details, procedures |

## Data flow

```
Evidence ──→ Agent reasoning ←── Principle / Knowledge
                  │
             Procedure = entry point (Sense → Orient → Act)
                  │
             Guard = enforcement (deterministic check on output)
```

The agent receives Evidence (structured JSON), reasons about it using
Principle (invariants) and Knowledge (semantics), enters through Procedure
(thin entry point), and Guard enforces constraints deterministically.

## Authority hierarchy

```
Design (ADRs, schemas)     ← architectural authority (immutable once accepted)
  │ constrains
Principle (rules)          ← policy authority (declarative)
  │ referenced by
Procedure (commands)       ← entry point (thin, no authority)
  │ advised by
Knowledge (atoms)          ← advisory (no enforcement power)
```

Declarative rules carry authority. Executable scripts are subordinate.
Deviating from an ADR requires a new ADR that supersedes it.

## SSOT (Single Source of Truth)

Each piece of information exists in exactly one place. When information
must be referenced from multiple locations, one location is authoritative
and others link to it. Duplication is a defect.

Key SSOTs:

| Information | SSOT location |
|-------------|---------------|
| Control system architecture | `docs/agent-control/architecture.md` |
| Hard Stop definitions | `agent-safety.mdc` |
| Workflow policy | `workflow-policy.mdc` |
| Commit format | `commit-format.mdc` |
| Coverage thresholds | `test-strategy.mdc` § Coverage Threshold Policy |
| CI polling intervals | `ci--job-dependency-graph.md` § Adaptive Polling Strategy |
| Bot review operations | `review--bot-operations.md` |
| Consensus protocol | `review--consensus-protocol.md` |
| PR template structure | `.github/PULL_REQUEST_TEMPLATE.md` |
| Issue template structure | `.github/ISSUE_TEMPLATE/` |
| Makefile target naming | `docs/agent-control/evidence-schema.md` |
| FSM state definitions | `docs/agent-control/state-model.md` |

## Reusability

| Aspect | Reusable (project-agnostic) | Coupled (project-specific) |
|--------|----------------------------|---------------------------|
| Observation patterns (evidence targets) | Yes | |
| State transition skeleton (FSM) | Yes | |
| SOA command form | Yes | |
| Guard/validation discipline | Yes | |
| Evidence schema conventions | Yes | |
| | | Project knowledge atoms |
| | | Semantic policies (severity, naming) |
| | | Repo-specific conventions |
| | | Domain review heuristics |

## Anti-patterns

| Anti-pattern | Violation | Correct approach |
|--------------|-----------|-----------------|
| Execution in Knowledge | Knowledge atom contains `gh`, `git`, `make` commands | Move commands to Evidence targets or Procedure |
| Judgment in Procedure | Procedure contains complex conditional logic | Move judgment criteria to Principle; Procedure reads Evidence and applies Principle |
| Ad-hoc observation | Procedure runs raw `gh api` / `git` inline | Create an Evidence target (`make` target) that produces structured JSON |
| Policy in Knowledge | Knowledge atom declares MUST/MUST NOT rules | Move policy to Principle (rules); Knowledge advises |
| Duplication across components | Same information stated in Principle and Procedure | One location is SSOT; other links to it |
| Procedure as thinking | Procedure tells the agent HOW to think | Procedure provides state; agent reasons using Principle + Knowledge |

## Self-correction mechanism

The system improves by improving its **observation instrument**, not by
patching agent behavior:

1. Agent encounters a situation where no evidence target provides the
   needed information
2. This is detected as an **observation gap** (Evidence layer deficiency)
3. Agent proposes a new evidence target (not an ad-hoc workaround)
4. The gap is filled, improving the system for all future runs

Raw `gh`/`git` execution for state observation outside evidence targets is
treated as a Principle violation — a signal that the Evidence layer is
incomplete. Direct content reads and configuration reads remain allowed
exceptions (see `docs/agent-control/migration-mapping.md` Coverage rules).
