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

## Structure

```text
Agent Control System
├── Design              README.md, docs/adr/, docs/schemas/
│                       architectural authority (immutable once accepted)
│     constrains ↓
└── Controls
    ├── Principle       .cursor/rules/          ← policy authority (declarative)
    ├── Procedure       .cursor/commands/        ← entry points (see § Procedure layer design)
    ├── Knowledge       .cursor/knowledge/       ← project-specific semantics
    ├── Evidence        Makefile + tools/        ← structured observation → JSON
    ├── Guard           hooks, CI, BP            ← deterministic enforcement
    └── Interface       AGENTS.md, .cursor/templates/, .github/templates  ← external entry points
```

Design defines the project's identity (README) and architectural
decisions (ADRs, schemas). Controls implement the agent's information
space under Design authority. Deviating from an ADR requires a new ADR
that supersedes it — editing a Principle rule is not sufficient.

## Components

| Component | Responsibility | What it must NOT contain |
|-----------|---------------|------------------------|
| **Design** | Project identity (`README.md`), architectural decisions (`docs/adr/`), data contracts (`docs/schemas/`) | Mutable policies, operational procedures |
| **Principle** | Declare MUST / MUST NOT policies, invariants | Procedures (numbered steps), observation commands |
| **Procedure** | Thin entry points: action cards (Reads → Sense → Act → Output → Guard) or full commands for judgment-intensive workflows. See § Procedure layer design. | Judgment logic, embedded observation, policy declarations |
| **Knowledge** | Project-specific semantics: patterns, gotchas, domain heuristics | CLI commands, API calls, executable procedures |
| **Evidence** | Structured observation via `make` targets → JSON | Policy decisions, workflow logic |
| **Guard** | Deterministic enforcement of Principle | Policy content (reference Principle for justification) |
| **Interface** | External entry points for humans and AI agent reviewers (`AGENTS.md`, `.cursor/templates/`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/`) | Implementation details, procedures |

## Design principles

Six principles govern the control system. Each is independent: removing
any one loses the ability to generate a specific structural property or
defend against a specific anti-pattern.

1. **Design is the supreme authority.** The project's identity (README)
   and architectural decisions (ADRs, schemas) constrain all Controls
   components. Principle, Procedure, Knowledge, Evidence, and Guard
   operate under Design authority.
2. **Show the agent structured state; don't make it memorize.** The
   agent receives its situational awareness from Evidence (structured
   JSON), not from memorized procedures or ad-hoc CLI queries. If
   Evidence omits facts that exist in the source system (for example a
   bot terminal outcome visible only in issue comments), the agent cannot
   select the correct workflow state from JSON alone — fix the evidence
   target (see P5), do not compensate with thicker Procedure or new
   Hard Stops.
3. **Knowledge is semantics only.** Knowledge atoms hold domain
   heuristics, patterns, and gotchas. They never contain CLI commands,
   API calls, or executable procedures.
4. **Each piece of information has exactly one authoritative location
   (SSOT).** When information must be referenced from multiple places,
   one location is the source of truth and others link to it.
   Duplication is a defect.
5. **Self-improvement starts with Evidence, not Principle.** When the
   agent encounters an observation gap, it proposes a new evidence
   target — not an ad-hoc workaround or a rule patch. The agent does
   not modify its own Principle rules.
6. **The control system is testable software.** Guards, CI checks, and
   validation targets enforce Principle deterministically. The control
   system itself is subject to the same engineering discipline as the
   code it governs.

### What the principles derive (not stated as principles)

The following properties emerge from the six principles by exclusion
and are not restated as separate principles:

- **Principle layer exists**: Design is immutable (P1) and Knowledge
  holds only semantics (P3), so mutable policies need their own layer.
- **Procedure is thin**: Evidence observes (P2), Principle declares
  (derived from P1), Knowledge advises (P3) — Procedure is the
  residual, providing only routing.
- **Authority hierarchy**: Design constrains Principle (P1); Principle
  declares policy that Procedure references; Knowledge is advisory
  (P3). The hierarchy follows from component responsibilities.

## Procedure layer design

### Action cards

The standard Procedure form is the **action card** — a thin entry point
of ~15–25 lines with a fixed structure:

```text
# <command-name>
## Reads      — prerequisite Principle/Knowledge files
## Sense      — evidence targets to run
## Act        — numbered execution steps (3–8 lines)
## Output     — brief output specification
## Guard      — relevant Hard Stops
```

Action cards are **not** the thinking itself — Procedure is a derived
property, not a principle (see § What the principles derive). They declare
what to read, what to observe, what to do, and what constraints apply.
Judgment logic lives in Principle; domain heuristics live in Knowledge.
The card connects them.

The **Orient** step from the original SOA cycle is deliberately absent
from action cards. State classification is the sole responsibility of
`next` (the orchestrator). When a card executes, the agent already
knows which FSM state it is in — `next` routed it there.

### FSM-to-command mapping

FSM states and Procedure commands are **not** 1:1. The FSM maintains
fine-grained states for accurate workflow position tracking (21 states),
while commands consolidate related states into coarser action units.

```text
FSM states (fine-grained, observational)
  ╲  many-to-one
   ╲
    → Action cards (coarse-grained, actionable)
         ↑
       next (orchestrator: classifies state → routes to card)
```

Examples of many-to-one mapping:

- `TestsDone`, `QualityOK`, `TestsPass` → all route to `verify`
- `ChangesRequired`, `UnresolvedThreads` → both route to `review-fix`
- `CIPending`, `BotReviewPending` → both delegate to background subagents

The canonical routing table lives in `next.md` § Act. The canonical
state definitions live in `state-model.md`.

### Full commands (exception form)

Some workflows require embedded judgment that cannot be cleanly
separated into Principle + Knowledge. These remain as **full commands**
— longer, structured procedures with their own reasoning steps.

Criteria for full command status:

| Criterion | Explanation |
|-----------|-------------|
| Hypothesis-driven | The workflow requires forming, testing, and revising hypotheses (e.g., `debug`) |
| Multi-signal synthesis | The output requires cross-referencing 5+ disparate signal sources (e.g., `session-retro`) |
| Audit scope | The procedure systematically audits an entire subsystem (e.g., `controls-review`) |
| Complex artifacts | The output is a structured artifact (sequence diagrams, propagation maps) that requires step-by-step construction (e.g., `integration-design`) |

Full commands do not follow the action card structure. They use their
own section layout appropriate to their workflow.

### Reads mechanism

Every action card declares a `## Reads` section listing Principle and
Knowledge files the agent must read before execution. This is the
primary mechanism ensuring that judgment context (which lives outside
the card) reaches the agent at the right time.

`workflow-policy.mdc` § Knowledge Consultation Triggers maintains a
cross-reference table of all card reads as a backup. The card's own
`## Reads` is the primary source.

## Data flow

```text
Evidence ──→ Agent reasoning ←── Principle / Knowledge
                  │                      ↑
             Procedure                   │
               next (orchestrator)       │
                  │  routes to           │
               Action card ─── Reads ────┘
                  │
             Guard = enforcement (deterministic check on output)
```

The `next` orchestrator classifies the current FSM state from Evidence,
then routes to the appropriate action card. The card's `Reads` section
directs the agent to load relevant Principle and Knowledge before acting.
Guard enforces constraints deterministically on the output.

## SSOT registry

Design principle 4 establishes the SSOT invariant. This registry is
the authoritative list of source-of-truth locations:

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
| Procedure layer design (action cards, full commands, FSM mapping) | `docs/agent-control/architecture.md` § Procedure layer design |

## Reusability

| Aspect | Reusable (project-agnostic) | Coupled (project-specific) |
|--------|----------------------------|---------------------------|
| Observation patterns (evidence targets) | Yes | |
| State transition skeleton (FSM) | Yes | |
| Action card form (Reads/Sense/Act/Output/Guard) | Yes | |
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

When an agent resorts to raw `gh`/`git` execution for state observation
outside evidence targets, this is a signal that the Evidence layer may
need enhancement — not a rule violation, but an input to control system
improvement. Direct content reads and configuration reads remain allowed
exceptions (see `docs/agent-control/migration-mapping.md` Coverage rules).
