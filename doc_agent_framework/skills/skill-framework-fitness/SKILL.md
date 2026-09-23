---
name: skill-framework-fitness
description: "Fitness test a Qt Doc Agent Framework skill or agent: checks pipeline mapping, four-layer chain, grounding, and boundary before it lands."
metadata:
  version: "1.0.0"
---

# Framework Fitness Testing

Reference for testing a skill or agent against the Qt Doc Agent Framework's
conventions before it lands. A 9-layer methodology with framework-specific
criteria in every layer.

Load this skill for any artifact whose destination is
`qtqa/doc_agent_framework/`. The checks reference the framework's
four-layer chain (harness → orchestrator → agent → skill) and its
pipelines (A / B / C / D).

## Core principle

> **Read-throughs find typos; running the artifact against real data
> finds the lies; running framework checks finds the drift.**

A skill or agent is a prompt that ships to other people and runs on real
work. In the framework's model, it also has to *compose* with the
orchestrator, load skills via one of the seven patterns, respect the
public/internal boundary, and register in the framework's discoverability
layer. Fitness testing catches the drift the generic 9-layer sweep does
not — because the generic sweep does not know about pipelines A/B/C/D,
fan-out designation, or `../../doc/loading-patterns.md`.

## Skill vs agent — what you are testing

- **Skill** — passive reference (`SKILL.md`). Loaded by an agent via one of
  the seven patterns in
  [`loading-patterns.md`](../../doc/loading-patterns.md). Its `description:`
  frontmatter is its trigger.
- **Agent** — active worker (an agent definition under `../../agents/`).
  Executes one pipeline stage; declares its pipeline, fan-out status, and
  which skills it loads.
- **Orchestrator** — the framework's dispatch layer
  ([`../../agents/orchestrator.md`](../../agents/orchestrator.md)). Owns
  routing, pre-flight, and post-agent verification. Only fan-out agents
  can call further subagents; the orchestrator is the primary fan-out.

## The 9 layers

Same skeleton as the generic methodology. Framework-specific criteria are
in **bold** at the end of each layer.

| # | Layer | Framework adds |
|---|-------|----------------|
| 1 | Define the contract | Pipeline (A/B/C/D) and fan-out designation explicit in the contract |
| 2 | Static review | Frontmatter pins `claude-opus-5-5`; category (skill vs agent vs reference doc) correct |
| 3 | Framework integration | Fits four-layer chain; registered in the subdir README; cross-links resolve; sibling composition rather than re-derivation |
| 4 | Trigger / dispatch | Skill trigger fires correctly *and* an agent actually loads it, or the orchestrator dispatches to the agent |
| 5 | Dynamic run | Runs end-to-end on a real framework input (patch review, stub scaffold, bug report, batch task) |
| 6 | Verification & citation | S / R / T citations trace to their source; no invented rules |
| 7 | Edge cases | Behavior on out-of-pipeline input, unclear pipeline, missing skill |
| 8 | Baseline comparison | With vs without the artifact, using the same orchestrator dispatch |
| 9 | Fixture | Re-runnable, anchored by claim text and pipeline letter |

### Layer 1 — Define the contract first

Same shape as the generic layer. Add the framework fields.

Framework contract fields:

- **Pipeline** — which of A / B / C / D does the artifact serve? "All" is
  a valid answer only for the orchestrator, artifact-tester, or a genuine
  cross-pipeline utility.
- **Fan-out** — yes/no. Default no. Only agents that dispatch further
  subagents get yes; the value must match `agents/README.md`'s table.
- **Activation** — for a skill: which agent(s) load it, via which of the
  seven patterns. For an agent: what request routes it, and from where
  (orchestrator dispatch table, direct user invocation).

### Layer 2 — Static review (correctness and category)

Same internal-defects check, plus:

- **Frontmatter.** For an agent: `name`, `description`, `model:
  claude-opus-5-5` (explicit, not the `opus` alias). For a fan-out
  agent: `tools:` includes `Agent`. For a skill: `name`, `description`
  (specific, discovery-driving), `metadata.version`; no `model` field.
- **Reference docs.** Files that describe the framework but are not
  invocable agents (like a comparison doc) get no agent frontmatter and
  are not listed in the orchestrator's dispatch table.
- **Category error.** A multi-step workflow filed as a skill, or a
  passive reference filed as an agent, still fails here; the framework
  does not soften that check.
- **Measurable constraints (advisory).** Spot-check against current
  Claude Code skill-design guidance (description caps, split
  thresholds, re-attach budget). Flag overruns; don't block on them
  alone unless the hard cap is breached.

  | # | Guideline / limit | Kind | How to measure |
  |---|-------------------|------|----------------|
  | 1 | Description length ≤ 150 chars target; 1,536 hard cap | Hard cap / soft target | `wc -c` on the `description:` value |
  | 2 | Trigger keywords in first 50 chars of description | Soft | Read the first 50 chars; the primary noun/verb should be there |
  | 3 | Body length ≤ 150–200 lines (split threshold) | Soft | `wc -l` on SKILL.md; monolithic bodies impair trigger precision |
  | 4 | Body ≤ ~20K chars / 5K tokens re-attach cap | Hard cap | `wc -c`; content past the cap is silently dropped after context compaction |
  | 5 | Initial-check pair + upfront-load skills stays around ≤ 5 combined | Soft | Count skills the orchestrator loads upfront; more than 5 at full budget saturates the 25K shared re-attach pool |
  | 6 | Critical instructions in the first half of the body | Soft | Read the first half; workflow, protocol, and anti-patterns should live there, references and tables last |

- **Content shape (advisory).** Skill body carries *strategy* (workflow,
  decision heuristics, error patterns, anti-patterns), not tool
  contracts (parameters, return values, hard dependencies belong in
  the tool or script description). Flag skills that read like a
  marketing pitch or duplicate tool parameter descriptions.
- **Naming (advisory).** Domain-scoped noun (`skill-language-style`);
  verb-noun for actions (`skill-commit-message`). No version suffix in
  the name. No generic wrappers (`skill-documentation`). Mirrors the
  domain, not the tool.
- **SKILL.md section shape (advisory).** A common template runs
  Overview → When this skill applies → Workflow / Protocol → Error
  patterns → Anti-patterns. The framework doesn't require this exact
  order, but flag skills missing both of "when it applies" and "workflow
  or protocol" — those two are load-bearing.

### Layer 3 — Framework integration (the fitness test)

This is where framework fitness lives. The generic methodology's
"centralization test" against a single documentation review system is
replaced with a **four-layer chain test** against the framework's own
structure.

Ask, for the artifact under test:

1. **Layer placement.** Which of the four layers does the artifact live
   in? Harness = `CLAUDE.md`. Orchestrator = `agents/orchestrator.md`.
   Agent = `agents/{name}.md`. Skill = `skills/skill-{name}/SKILL.md`.
   The file's location and content must agree.
2. **Pipeline mapping.** Is the artifact's pipeline (A / B / C / D)
   consistent across every place it appears: its own contract,
   `agents/README.md`, `skills/README.md`, and the orchestrator
   dispatch table? A row missing from any of these is a fragmentation
   defect.
3. **Loading pattern.** For a skill: does the loading pattern (from
   [`../../doc/loading-patterns.md`](../../doc/loading-patterns.md)) match how the
   agents actually use it? For an agent: does the definition declare
   the loading pattern for every skill it loads?
4. **Grounding.** If the artifact codifies rules, are they marked S / R
   / T with sources? Rules that don't fit any category are either
   spelled out for AI use or explicitly excluded.
5. **Registration.** Row present in the appropriate subdir README
   (`agents/README.md`, `skills/README.md`, `doc/README.md`, or
   `doc/instructions/README.md`). Cross-links from other subdir READMEs
   use relative paths and resolve.
6. **Public/internal boundary.** No URLs to internal Qt sites. No
   internally classified content in a public tree. No user-specific
   filesystem paths (`~/code/…`, `/Users/…`). See
   `skill-security-hygiene` for the full boundary rules.
7. **Sibling composition.** Does the artifact re-derive a rule a
   sibling already owns? Point at the sibling that should be
   referenced instead.

A failure at 6 or 7 blocks landing. Failures at 1–5 are ordinary
integration fixes.

**Prompts:**

```
Treat qtqa/doc_agent_framework/ as the framework, with:
- CLAUDE.md as the harness
- agents/orchestrator.md as the orchestrator
- agents/*.md as stage agents
- skills/*/SKILL.md as skills
- CONTRIBUTING.md as the add-a-thing rules
- doc/loading-patterns.md as the loading-pattern reference
- agents/README.md and skills/README.md as the canonical "what exists" lists

For <TARGET>, report:
1. LAYER PLACEMENT — which of the four layers does it live in? Location matches content?
2. PIPELINE — A/B/C/D. Consistent across agents/README.md, skills/README.md, orchestrator dispatch?
3. LOADING — for a skill: which of the seven patterns; do agents load it that way? For an agent: is each skill it loads declared with a pattern?
4. GROUNDING — rules marked S/R/T with sources? Any silent conventions?
5. REGISTRATION — row present in the appropriate subdir README? Cross-links resolve?
6. BOUNDARY — any URLs to internal Qt sites? Any Internal-classified content? Any user-specific paths?
7. SIBLINGS — does it re-derive something a sibling already owns?
8. VERDICT — does adding it keep the framework coherent, or fragment it?
```

### Layer 4 — Trigger / dispatch test

Same shape as the generic trigger test, plus the framework's dispatch
path.

For a skill:

- Does the `description:` fire on on-target, near-miss, off-target
  prompts?
- Does an agent (or the orchestrator) actually load it? A skill that
  activates but is not loaded by any agent is unreachable.
- Does the loading pattern in the SKILL.md match how the agents load it?

For an agent:

- Does the orchestrator's dispatch table route the intended requests to
  this agent?
- If the agent is invoked directly (not via the orchestrator), is that
  path documented in the agent definition?

Near-miss cases include: pipeline overlap (a request that could be B or
C), fan-out ambiguity (a request that could plausibly need further
dispatch), and cross-pipeline calls (Pipeline C invoking B invoking A).

### Layer 5 — Dynamic run on real framework input

Same generic layer. Inputs by pipeline:

- **Pipeline A** — a real Qt patch or QDoc warning log.
- **Pipeline B** — a real stub-scaffold target: an undocumented C++/QML
  class, a bare `\page` scaffold.
- **Pipeline C** — a real doc bug report from public Jira (QTBUG-*).
- **Pipeline D** — a real batch task: rename or link-audit across two
  or more modules.

Run every phase in a scratch copy; show diffs, don't apply. Note where
the artifact's stated flow matched reality and where it drifted.

### Layer 6 — Verification & citation

Same generic check with two framework additions:

- **S / R / T citations** — every rule the artifact cites must trace to
  its source. R-rules link to `skill-language-style` (or a numbered
  entry). T-rules cite `skill-ai-tells` and its corpus calibration.
  S-sources link to the actual QUIP, Writing Guidelines page, or MS
  Style Guide entry.
- **Loading-pattern citations** — the seven patterns are locally sourced
  from [`../../doc/loading-patterns.md`](../../doc/loading-patterns.md); an artifact
  that cites internal-Qt URLs for the patterns is a boundary defect,
  not just a citation defect (see Layer 3, item 6).

### Layer 7 — Edge cases

Framework-specific edge cases in addition to the generic list:

- Request that doesn't map cleanly to any pipeline (A / B / C / D
  unclear).
- Request that touches multiple pipelines (a bug fix that's also a
  batch job).
- Agent asked to load a skill that isn't registered in `skills/README.md`.
- Skill loaded by two agents with conflicting loading patterns.
- Fan-out agent invoked in a context where its subagents can't run
  (permission denial, missing tool).

### Layer 8 — Baseline comparison

Same generic layer, dispatched the framework way:

- Run the task without loading `skill-framework-fitness` and the target
  artifact.
- Run the same task with both loaded, dispatched through the
  orchestrator.
- Diff. Attribute each difference to the artifact. Verdict: adds value
  / adds noise / neutral.

The baseline for framework artifacts must use the orchestrator dispatch;
skipping the orchestrator hides fitness defects.

### Layer 9 — Capture as a re-runnable fixture

Same generic template, with a **Pipeline** field added.

## One-page checklist

```
CONTRACT
[ ] Purpose, activation, output spec written BEFORE testing
[ ] Pipeline (A/B/C/D) declared; fan-out yes/no declared
[ ] 3–5 objective pass/fail criteria defined
STATIC
[ ] No contradictions, miscounts, broken refs, unverifiable claims
[ ] Correct category (skill vs agent vs reference doc)
[ ] Frontmatter: model claude-opus-5-5 (agents); no model field (skills)
[ ] Fan-out agents have tools: Agent; stage agents do not
[ ] Description ≤ 150 chars target (hard cap 1,536); trigger keywords in first 50 chars
[ ] Body ≤ 200 lines target; ≤ ~20K chars / 5K tokens hard re-attach cap
[ ] Critical instructions in the first half of the body
[ ] Naming: domain-scoped noun, no version suffix, no generic wrappers
[ ] Section shape carries "when it applies" and "workflow / protocol"
[ ] Skill body is strategy, not tool contracts (params belong in tool docstring)
FRAMEWORK INTEGRATION
[ ] Correct layer placement (harness/orchestrator/agent/skill)
[ ] Pipeline consistent across agents/README, skills/README, orchestrator
[ ] Loading pattern (from loading-patterns.md) matches actual use
[ ] Rules marked S/R/T with sources
[ ] Row in the appropriate subdir README (agents/, skills/, doc/, doc/instructions/)
[ ] Cross-links resolve (relative paths)
[ ] No URLs to internal Qt sites; no Internal-classified content; no user-specific paths
[ ] Doesn't re-derive rules siblings own
TRIGGER / DISPATCH
[ ] Skill fires on on-target; silent on off-target
[ ] Skill is actually loaded by an agent
[ ] Agent is dispatched from the orchestrator's routing table
DYNAMIC
[ ] Full workflow run on a real pipeline-appropriate input (sandboxed)
VERIFICATION
[ ] Every output claim CONFIRMED / REFUTED / UNVERIFIED vs independent source
[ ] S/R/T citations trace to their sources
[ ] Loading-pattern citations point at loading-patterns.md, not an internal URL
EDGE CASES
[ ] Unclear/multi-pipeline inputs tried
[ ] Unregistered skill / conflicting loading pattern tried
BASELINE
[ ] Same task run WITHOUT vs WITH the artifact through the orchestrator
CAPTURE
[ ] Fixture saved with a Pipeline field
```

## Fixture template

```markdown
# Framework fitness fixture: <artifact name>
Artifact under test: <path>
Pipeline: <A | B | C | D | all>
Fan-out: <yes | no>
Tested revision: <commit / version>
Date: <YYYY-MM-DD>

## Inputs
| ID | Stable reference | Pipeline case exercised |
|----|------------------|--------------------------|

## Expected findings
| Input | Expected outcome |
|-------|------------------|

## Acceptance criteria (Layer 1)
- [ ] <objective pass/fail>

## Framework-integration findings (Layer 3)
- Layer placement: <verdict>
- Pipeline consistency: <verdict>
- Loading pattern match: <verdict>
- Grounding (S/R/T): <verdict>
- Registration: <verdict>
- Boundary (public/internal): <verdict>
- Reference-only respect: <verdict>
- Sibling composition: <verdict>

## Re-run instruction
<one paragraph; anchor by claim text and pipeline letter, not line numbers>

## Baseline note
With-vs-without-through-orchestrator verdict: <value / noise / neutral>
```

## Worked examples (framework defects this finds)

- **Wrong pipeline row.** Agent listed as Pipeline B in
  `agents/README.md` but dispatched as Pipeline A in `orchestrator.md`.
  Layer 3 item 2 catches it; users hit dispatch-vs-listing disagreement
  in production.
- **Undeclared fan-out.** Agent that spawns subagents but is not marked
  fan-out in `agents/README.md`. Layer 3 item 1 + Layer 2 frontmatter
  check catch it; the four-layer chain becomes untraceable.
- **Internal-Qt URL in a public file.** Author cites an internal
  seven-patterns URL instead of `loading-patterns.md`. Layer 3 item 6
  + Layer 6 citation trace catch it; public readers get a broken link.
- **Skill loaded but not registered.** Agent's definition references
  `skill-foo` but no `skills/skill-foo/SKILL.md` exists and
  `skills/README.md` has no row. Layer 4 dispatch test catches it;
  requests silently fail.
