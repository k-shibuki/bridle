---
trigger: ADR-0011, MCP interface, MCP server, dual-mode, Free mode, Strict mode, mcptools, MCP Resource, MCP Tool, bridle_mcp_server, aggregate_knowledge, turn_prepare, turn_resolve, hybrid execution, CodeSandbox, mcp_session
---
# ADR-0011: MCP Interface and Dual-Mode Design

## Context

bridle's Phase 2 delivered a graph-driven REPL (ADR-0002) where the
decision graph holds initiative and walks users through parameter
decisions sequentially. This works well for structured, reproducible
workflows but has two limitations:

1. **Single interface**: The REPL requires an interactive R session.
   LLM clients like Cursor and Claude Code cannot use bridle's knowledge
   base or decision engine — they need a protocol-level interface.
2. **Rigid flow control**: The graph-driven approach enforces strict
   ordering, which frustrates experienced analysts who know what they
   want and prefer to explore freely with domain knowledge available
   as reference.

The Model Context Protocol (MCP) has emerged as a standard for
connecting LLM clients to external tools and knowledge. The mcptools
R package provides a native MCP server implementation. Cursor, Claude
Code, and other clients support MCP natively.

Separately, users have requested a "conversational" mode where bridle's
knowledge is injected into the system prompt without graph enforcement —
effectively treating bridle as a domain knowledge server rather than a
workflow engine.

## Decision

### 1. MCP interface adoption

Expose bridle as an MCP server via mcptools, alongside (not replacing)
the existing REPL. Both interfaces share the same core orchestration
layer.

**Rationale**: MCP is protocol-native to the LLM client ecosystem.
Rather than building custom integrations for each client, a single MCP
server serves all compliant clients. The REPL remains for users who
prefer a direct R-session experience.

### 2. Strict/Free dual-mode design

Introduce two operating modes, extending ADR-0002:

- **Strict mode**: The existing graph-driven workflow (ADR-0002). The
  decision graph controls flow; the runtime holds initiative. Used when
  reproducibility, coverage guarantees, and evaluability are priorities.
- **Free mode**: All plugin knowledge (entries, constraints, graph
  structure) is loaded into the LLM context for open-ended conversation.
  No graph enforcement. Used when the analyst wants to explore freely
  with domain knowledge as reference.

Both modes are available in both interfaces (REPL and MCP).

**Rationale**: Strict mode serves beginners and formal analysis. Free
mode serves experienced analysts and exploratory work. The dual-mode
model accommodates both without compromising either.

### 3. Free as default

Free mode is the default for both REPL (`agent$console()`) and MCP.
Strict mode is opt-in (`agent$console(mode = "strict")`).

**Rationale**: Most users start by exploring — they want to understand
what bridle knows about their package before committing to a structured
workflow. Free mode provides immediate value with zero ceremony. Users
who need structure explicitly opt into Strict mode.

### 4. Hybrid code execution

Code execution uses two backends:

- **CodeSandbox** (default): Restricted environment with allowed
  packages only, blocked system calls, and 10-second timeout. Safe for
  automated workflows and untrusted code.
- **mcp_session**: Routes execution to the user's interactive R session
  via `mcptools::mcp_session()`. Full R access, no restrictions. Opted
  into explicitly via `execution_mode = "session"`.

**Rationale**: CodeSandbox provides safety guarantees required for
reproducible analysis. But real-world statistical analysis often
requires loading data from files, using arbitrary packages, and running
long computations. mcp_session bridges this gap while making the
security tradeoff explicit.

### 5. MCP Tool/Resource design

The MCP interface maps modes to MCP primitives:

- **Free mode → MCP Resources**: Stateless knowledge delivery.
  `bridle://knowledge`, `bridle://graph`, `bridle://constraints`
  provide read-only access to plugin contents. The `bridle_execute`
  Tool enables code execution.
- **Strict mode → MCP Tools**: Stateful session management.
  `bridle_start`, `bridle_guidance`, `bridle_decide`, `bridle_status`
  form a session lifecycle. The graph engine tracks state across
  tool calls.

**Rationale**: MCP Resources suit the stateless, reference-oriented
nature of Free mode. MCP Tools suit the stateful, step-driven nature
of Strict mode. This maps cleanly to MCP's design intent.

### 6. Core orchestration extraction

Extract per-turn logic from `console.R` into `R/orchestrator.R`:

- `turn_prepare(agent)`: Advance graph, retrieve knowledge, assemble
  prompt. Returns structured turn data.
- `turn_resolve(agent, parameter_value, transition_choice)`: Update
  context, select transition, log. Returns status.
- `aggregate_knowledge(agent)`: Compile all plugin knowledge into a
  single formatted string for Free mode system prompts.

Both REPL and MCP call these functions — no duplicated orchestration.

**Rationale**: The REPL currently mixes orchestration (graph, knowledge,
logging) with interface concerns (readline, LLM call, display).
Extracting orchestration enables code reuse across interfaces without
duplication.

## Consequences

### Easier

- Cursor and Claude Code can access bridle knowledge and analysis
  guidance via standard MCP protocol
- Experienced analysts get immediate value from Free mode without
  learning the graph-driven workflow first
- New interfaces (VSCode extension, web UI, etc.) only need to
  implement MCP client, not custom integration
- Testing orchestration logic is simpler when decoupled from
  interface concerns

### Harder

- Two modes require testing both paths for every feature
- Strict mode MCP tools require in-memory session management with
  cleanup and isolation concerns
- mcptools API stability (0.2.0) may require adaptation; thin
  abstraction layer recommended
- Free mode system prompt size scales with plugin knowledge — large
  plugins may approach context window limits (deferred to Phase 3
  vitals evaluation)
- CodeSandbox and mcp_session have fundamentally different security
  models; clear documentation of the tradeoff is essential
