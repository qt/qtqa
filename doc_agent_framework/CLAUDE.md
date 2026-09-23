# CLAUDE.md

> **For human readers.** You don't load this file manually — Claude
> Code auto-loads it when you work in this directory or one below it.
> Modify it only when you're changing the framework's harness behavior;
> for normal use, treat it as read-only.
>
> This file coexists with any other `CLAUDE.md` on your machine — your
> `~/.claude/CLAUDE.md`, a project-level `CLAUDE.md` in a parent
> directory, or anywhere else Claude Code auto-loads. All of them apply
> in the same session; nothing here overwrites your own configuration.
> If a directive here conflicts with something in your own `CLAUDE.md`,
> the closer scope (this file) typically wins because it's more
> specific to the current task, but Claude reads all loaded content and
> resolves in context.

## Resource Priority

**Always check `~/.claude/` first for skills and agents:**
- Skills: `~/.claude/skills/`
- Agents: `~/.claude/agents/`

Load agent definitions from `~/.claude/agents/*.md` when invoking agents
with the Task tool.

## Role

The Qt Doc Agent Framework: a generic agentic framework for automating
documentation tasks across the pipeline stages (brainstorming, writing,
editing, reviewing, publishing). Four pipelines: patch review (A),
content creation (B), bug fixing (C), batch maintenance (D). Stage
agents ship into `agents/` as each pipeline comes online.

## Layer hierarchy

The framework runs as a four-layer chain. Each layer dispatches to the
next; skills never dispatch anywhere.

```
harness  →  orchestrator  →  agent  →  skill
```

| Layer | On disk | Role |
|-------|---------|------|
| Harness | Claude Code + this `CLAUDE.md` | Auto-loaded orientation. Routes framework work to the orchestrator. |
| Orchestrator | [`agents/orchestrator.md`](agents/orchestrator.md) | Picks the pipeline (A/B/C/D), gates pre-flight, dispatches stage agents, verifies output. |
| Agent | `agents/*.md` | Executes one stage. Loads its own skills. |
| Skill | `skills/*/SKILL.md` | Reference material the agent loads on demand. |

Dispatch capability: the orchestrator has the `Agent` tool; stage agents
have it only when marked as fan-out nodes in `agents/README.md`. Default
stage behavior is skill-loading, not agent-spawning.

## What the harness does

- Loads this file on session start.
- Recognizes framework-shaped requests and hands them to the
  orchestrator agent.
- Passes through direct single-agent invocations when the pipeline is
  obvious from the request (for example, a bare patch-review request
  going straight to `qt-doc-reviewer`).

Everything else (pipeline selection, pre-flight, dispatch mechanics,
per-agent verification gates, output-format matrix) lives in the
orchestrator layer. See [`agents/orchestrator.md`](agents/orchestrator.md).

## Grounding

Every writing rule the framework relies on is codified as an S-, R-, or
T-rule so the agents can cite it in output.

- **S-sources.** Root style authorities: QUIPs, Qt Writing Guidelines,
  Microsoft Style Guide.
- **R-rules.** Concrete language rules distilled from the S-sources
  (`skill-language-style`, R1–R64 and beyond).
- **T-rules.** AI tells to suppress in generated prose
  (`skill-ai-tells`, T1–T19, calibrated against 2.4M words of Qt prose).

Anything not covered by an S / R / T entry is either spelled out for AI
use or explicitly excluded.

## Deterministic first

Prefer a deterministic tool over the LLM whenever one can do the job.
Deterministic work gives the same result on every run and costs no
tokens; route it to a script or tool (grep, Vale, QDoc, ImageMagick,
format checkers, `tools/`, the `tests/` harness). Keep the LLM for work
that needs judgment: prose review, ambiguity resolution, structural
rewrites.

- Before reading files to find, count, or compare something, run a
  tool that returns only the answer.
- When an agent step is deterministic, the agent calls a tool
  (Pattern 5) instead of reasoning through it.
- When a deterministic check repeats across runs, turn it into a
  script in `tools/` instead of re-deriving it in each session.

## Skill-loading patterns

The framework uses seven skill-loading patterns. The canonical
reference lives at [`doc/loading-patterns.md`](doc/loading-patterns.md);
every agent's definition names which patterns it uses.

## Environment

**Qt structure:**
- qt5.git super-repo, `dev` branch is the latest unreleased.
- Published: doc.qt.io (released), doc-snapshots.qt.io (dev).
- Build: `ninja docs` or `ninja html_docs_<Module>`.

**Key paths:**
- QDoc binary: `qtbase/bin/qdoc`
- Doc output: `qtbase/doc/`
- QDoc source: `qttools/src/qdoc/`

## Reference links

- [Qt Writing Guidelines](https://wiki.qt.io/Qt_Writing_Guidelines)
- [QDoc Manual](https://doc.qt.io/qt-6/qdoc-index.html)
- [Qt Doc Snapshots](https://doc-snapshots.qt.io/qt6-dev/)
- [QUIP 21 - Using images in Qt documentation](https://contribute.qt-project.org/quips/21)
- [QUIP 25 - Documentation Writing Style](https://contribute.qt-project.org/quips/25)
- [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/welcome/)
