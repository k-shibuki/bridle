---
trigger: task prefix, multi-agent artifact, hypothesis ID, concurrent agent naming
---
# Task Prefix Convention (Multi-Agent Support)

Multiple AI agents may debug or work concurrently. Use consistent prefixes across all artifacts to avoid conflicts.

## Artifact Naming

| Artifact | Pattern | Example |
|----------|---------|---------|
| Docs | `debug/docs/<TASK>_report.md` | `debug/docs/GRAPH_report.md` |
| Logs | `debug/scripts/<TASK>_debug.log` | `debug/scripts/NODE_debug.log` |
| Hypothesis IDs | `<TASK>-H1`, `<TASK>-H2`, ... | `GRAPH-H1`, `EVAL-H2` |

## Hypothesis ID Convention

- `<TASK>-H1`, `<TASK>-H2`, ... : Main hypotheses
- `<TASK>-H1a`, `<TASK>-H1b`, ... : Sub-hypotheses
- Use same hypothesis ID for all logs tracing one propagation path
