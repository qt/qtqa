# Qt Doc Agent Framework

A generic agentic framework for automating Qt documentation tasks across
brainstorming, writing, editing, reviewing, and publishing. The framework
runs four pipelines: patch review (A), content creation (B), bug fixing
(C), and batch maintenance (D).

Status: **skeleton**. This directory holds the layout, dispatch
mechanics, and the initial-check skill pair; stage agents, per-pipeline
skills, and how-tos are added incrementally. Basic functionality is
targeted for end of 2026.

## Architecture

The framework runs as a four-layer chain. Each layer dispatches to the
next; skills never dispatch anywhere.

```
harness  →  orchestrator  →  agent  →  skill
```

| Layer | On disk | Role |
|-------|---------|------|
| Harness | Claude Code + [`CLAUDE.md`](CLAUDE.md) | Auto-loaded orientation. Routes framework work to the orchestrator. |
| Orchestrator | [`agents/orchestrator.md`](agents/orchestrator.md) | Picks the pipeline (A/B/C/D), gates pre-flight, dispatches stage agents, verifies output. |
| Agent | [`agents/*.md`](agents/) | Executes one stage. Loads its own skills. |
| Skill | [`skills/*/SKILL.md`](skills/) | Reference material the agent loads on demand. |

Only the orchestrator has the `Agent` tool; stage agents load skills
rather than spawning further subagents (unless explicitly marked
fan-out).

## Getting started

Open Claude Code in this directory (or in a Qt worktree that includes
it). Claude auto-loads [`CLAUDE.md`](CLAUDE.md) and treats framework-
shaped requests as dispatch through the orchestrator.

**Current runnable surface:** the orchestrator plus the initial-check
pair ([`skill-framework-fitness`](skills/skill-framework-fitness/SKILL.md)
and [`skill-security-hygiene`](skills/skill-security-hygiene/SKILL.md)).
No stage agents ship yet, so pipeline invocations (A, B, C, D) are all
"planned" — those land when the corresponding agents do.

**What you can do today:**

- Apply the initial-check pair to a proposed skill or agent before
  contributing it. Example prompt: *"Apply skill-framework-fitness
  and skill-security-hygiene to `path/to/my-artifact/SKILL.md`.
  Enumerate every check and every finding."*
- Read the reference docs in [`doc/`](doc/README.md) to understand
  the four-layer chain and the seven skill-loading patterns.

**When pipelines land**, the invocation shape will be *"run pipeline A
on `<Gerrit URL>`"* or *"scaffold documentation for
`<header/QML type>` using pipeline B"* — the orchestrator picks the
pipeline letter, dispatches the stage agent, and runs the post-agent
verification.

## Where do I find X?

| I want to... | Go to |
|--------------|-------|
| **Run** the framework today (initial check) | [Getting started](#getting-started) above |
| **Contribute** to the framework | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Read the architecture (four-layer chain) | [`CLAUDE.md`](CLAUDE.md) |
| See how dispatch and verification work | [`agents/orchestrator.md`](agents/orchestrator.md) |
| List the existing agents | [`agents/README.md`](agents/README.md) |
| List the existing skills | [`skills/README.md`](skills/README.md) |
| Learn how skills get loaded (seven patterns) | [`doc/loading-patterns.md`](doc/loading-patterns.md) |
| Run the framework's initial check (fitness + security) | [`skills/skill-framework-fitness/SKILL.md`](skills/skill-framework-fitness/SKILL.md), [`skills/skill-security-hygiene/SKILL.md`](skills/skill-security-hygiene/SKILL.md) |
| Run the framework on a task | [`doc/instructions/README.md`](doc/instructions/README.md) |
| Read the long-form reference docs | [`doc/README.md`](doc/README.md) |
| Find local tools the skills call (Pattern 5) | [`tools/README.md`](tools/README.md) |
| Find the test suite | [`tests/README.md`](tests/README.md) |

**If you want to *use* the framework, start here:**
[Getting started](#getting-started) above.

**If you want to *contribute* to the framework, start here:**
[`CONTRIBUTING.md`](CONTRIBUTING.md) → [`CLAUDE.md`](CLAUDE.md).

## Scope

A generic agentic framework for automating documentation tasks across the
pipeline stages: brainstorming, writing, editing, reviewing, publishing.
Claude Code and Claude Cowork are the primary tools; some portability to
Copilot for agents and skills.

Users:
- Qt Doc team members
- External Qt contributors (all artifacts ship in public qtqa)
- Development teams in the Qt BU and elsewhere in Qt Group who write Qt
  documentation

The framework monitors content strategies but stays parallel and
independent, not downstream of them.

## Pipelines

The framework organizes work into four pipelines. Each composes agents
and skills from `agents/` and `skills/`; usage details land in
`doc/instructions/`.

| ID | Name | Flow |
|----|------|------|
| A | Review patches | Receive content, review, return corrections |
| B | Create documentation | Research, scaffold stub, fill and review stub, push, then (A) |
| C | Fix a doc bug | Receive bug report, run (B), run (A), resolve |
| D | Batch fixes for maintenance | Receive task, batch patch repos, run (A) |

All four pipelines are new work; agents ship as they are built.

## Deliverables

- **Artifacts.** Agents, skills, and output. The AI components.
- **Agents.** AI actors that execute each pipeline stage.
- **Skills.** Reference material that agents load on demand.
- **Doc Team Diff.** Template for corrections and suggestions.
- **Orchestrator.** Delegates and launches agents, verifies their output.
- **Forms and templates.** Structured JSON, Markdown, or HTML for I/O
  between stages.
- **User guides and prompts.** How to use the framework, end to end and
  per stage.
- **S-rules, R-rules, T-rules.** Grounding material:
  - **S-sources.** QUIPs, Qt Writing Guidelines, Microsoft Style Guide.
  - **R-rules.** Concrete language rules (do and do-not).
  - **T-rules.** AI tells to suppress (em-dash overuse, clichés, canned
    sentence shapes).

## Strategy

- **Codification.** Every writing rule the agents rely on gets an
  explicit S, R, or T entry the agents can cite. Anything not codified
  is either spelled out for AI use or explicitly excluded.
- **Deterministic first.** Sort each task into deterministic work
  (counting, matching, parsing, building) and non-deterministic work
  (prose review, ambiguity resolution, structural rewrites). Scripts
  and tools handle the deterministic work: grep, Vale
  (`qtqa/vale_linter_config/`), QDoc, ImageMagick, format checkers. The
  LLM handles only what needs judgment. A deterministic tool is
  preferred whenever one can do the job: it gives the same answer on
  every run and costs no tokens.
- **Skill-loading patterns.** The framework uses seven patterns: upfront
  vs. conditional loading; GATE-based loading (an agent forks, loads the
  skill, blocks progress so memory stays fresh); tool-based lookup
  (delegate to Vale, ImageMagick, Mermaid, scripts); and hierarchical
  prompts (Orchestrator to Agent to Skill). The summary lives locally at
  [`doc/loading-patterns.md`](doc/loading-patterns.md).
- **Test suite and reporting.** A sample doc set (an empty module with
  C++ and QML APIs) is the fixture. Framework output is compared against
  human-edited content. Audits and reports feed back to agents as new
  knowledge.

## Measurable goals

- Token use and execution runtime within reason.
- Output correctness validated against the test suite.
- Adoption within the team and among external contributors.

## Risks and mitigation

| Risk | Mitigation |
|------|------------|
| Hallucinations | Ground each stage in reliable skills |
| Cumbersome usage (permission prompts, multi-agent deploys) | Guidance and sample prompts |
| Token and runtime cost | Guidance; test across models and setups |
| Uncertain maintenance path as models change | Stabilize against models via the test suite |

## Deferred to Phase 3 and later

- **Personas.** Simulate audience personas (Evaluator, New Developer,
  Experienced Developer, QA lead / package manager, Technical Artist,
  Domain and industry) and validate output against them.
- **Extensions.** Snippets, code examples, and demos; image overhaul with
  automated screenshots; dev tools; other Qt Group documentation.

## Layout

```
doc_agent_framework/
├── README.md              # This file
├── CLAUDE.md              # Harness layer: role, layer hierarchy, environment
├── CONTRIBUTING.md        # How to add an agent, skill, tool, test, or doc page
├── REUSE.toml             # SPDX headers
├── agents/                # Orchestrator + stage agents
├── skills/                # Reference skills the agents load
├── tools/                 # Local executables/scripts skills call via Pattern 5
├── tests/                 # Sample doc-set fixtures + comparison harness
└── doc/                   # Documentation: long-form reference + task-oriented instructions
    ├── loading-patterns.md
    ├── instructions/      # Short, task-oriented how-tos
    └── ...
```

Each subdirectory carries a `README.md` that describes what lives there
and how it maps to pipelines A–D.

`doc/instructions/` vs `doc/`: `doc/instructions/` is short,
task-oriented how-tos ("run Pipeline B on module X"); the rest of
`doc/` is long-form reference material aimed at readers who run or
extend the framework. Qt Group renders the doc site internally.

## Reference links

- [Qt Writing Guidelines](https://wiki.qt.io/Qt_Writing_Guidelines)
- [QDoc Manual](https://doc.qt.io/qt-6/qdoc-index.html)
- [Qt Doc Snapshots](https://doc-snapshots.qt.io/qt6-dev/)
- [QUIP 25 - Documentation Writing Style](https://contribute.qt-project.org/quips/25)
- [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/welcome/)

## License

SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GFDL-1.3-no-invariants-only
