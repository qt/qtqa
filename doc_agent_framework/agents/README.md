# Agents

**Role:** agent definitions for the Qt Doc Agent Framework
(orchestrator + stage agents).

**See also:** [`../README.md`](../README.md) for the framework
overview · [`../CONTRIBUTING.md`](../CONTRIBUTING.md) for how to add a
new agent.

The framework runs as a four-layer chain: **harness → orchestrator →
agent → skill**. Files in this directory sit at the orchestrator and
agent layers.

- **[`orchestrator.md`](orchestrator.md)** — the dispatcher for the
  whole framework. Picks the pipeline (A/B/C/D), gates pre-flight,
  launches stage agents, verifies output. Has the `Agent` tool.
- **Stage agents** — one per pipeline stage. Self-sufficient: load
  their own skills, fetch their own input, verify their own output.
  No `Agent` tool by default (skill-loading only), unless marked as a
  fan-out node below.

## Pipeline mapping

| Pipeline | Stage | Agent | Fan-out? |
|----------|-------|-------|----------|
| (all) | Dispatch | orchestrator | yes |
| A | Review | qt-doc-reviewer | no |
| A | Warning fix | qdoc-warning-fixer | no |
| A | Impact analysis | doc-impact-analyzer | no |
| A | Module audit | doc-structure-auditor | no |
| A | Build | doc-builder | no |
| A | Vale lint | vale-qdoc-linter | no |
| B | Create / scaffold | doc-shaper | no |
| B | Fill and review stub | *(TBD)* | — |
| C | Bug triage to fix | *(TBD)* | — |
| D | Batch orchestrator | *(TBD)* | likely yes |
| (all) | Artifact testing | artifact-tester | no |

**Fan-out?** column: does the agent get the `Agent` tool so it can spawn
further subagents? Default is **no** — stage agents keep the chain
honest by loading skills rather than spawning agents. Mark **yes** only
for orchestrator-shaped agents (Pipeline D's batch orchestrator is the
obvious future candidate).

Every agent listed above lives (or will live) in this directory.
Additions land here as each pipeline stabilizes.

## Conventions

- Definitions are Markdown files with YAML frontmatter pinned to
  `claude-opus-5-5`.
- Every agent declares which skills it loads, when, and via which
  loading pattern (see the seven patterns in
  [`../doc/loading-patterns.md`](../doc/loading-patterns.md)).
- Every agent that outputs suggestions uses `skill-doc-diff` for the
  Doc Team diff format.
- Only fan-out agents include `Agent` in their `tools:` frontmatter.
  Stage agents omit it, so accidental nesting can't happen.
