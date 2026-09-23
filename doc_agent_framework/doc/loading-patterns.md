# The Seven Skill-Loading Patterns

Canonical reference for how agents in the Qt Doc Agent Framework load
skills. Every agent's definition names which patterns it uses; the
orchestrator picks patterns 6 (hierarchical) and 7 (verification) at the
framework level.

Adapted from established Claude Code skill-design practice; the summary
table and detailed sections below are the framework's public reference.

## Summary

| # | Pattern | How it works | Best for | Watch out for |
|---|---------|--------------|----------|---------------|
| 1 | **System Prompt Embedding** | Rules pasted into the system prompt | Small, stable rule sets needed every run | Uses up context permanently; doesn't scale past ~2 skills |
| 2 | **Upfront Loading** | Agent reads all skill files at start | Short workflows; skills needed continuously | Claude forgets earlier content in long conversations; wastes memory on irrelevant skills |
| 3 | **GATE-Based / Just-in-Time** | Agent reads a specific skill at each decision point | Multi-step workflows; large skill libraries | More complex prompt design; extra file reads per run |
| 4 | **RAG / Retrieval** | External search retrieves relevant passages | Very large knowledge bases (100+ docs) | Rules may get cut in half during retrieval; less control over what's retrieved |
| 5 | **Tool-Based Lookup** | Skills exposed as tools the agent calls on demand | Exploratory tasks; strong models (Opus) | Agent may skip lookups; hard to verify which rules were checked |
| 6 | **Hierarchical / Cascading** | Knowledge split across prompt layers (orchestrator → agent → skill) | Multi-agent systems with an orchestrator | Adds complexity for single-agent setups |
| 7 | **Multi-Agent Verification** | Second pass checks first agent's output against the rules | High-stakes outputs where errors are costly | Slower; doubles compute; needs concrete verification criteria |

**The framework's stack combines 1 + 2 + 3 + 6 + 7.** Most real agents
layer multiple patterns.

## How to pick a pattern

Decision tree (in order — take the first `YES`):

- Small, stable, always-needed rule set? → **Pattern 1: System Prompt Embedding.**
- Skill needed at one specific step in a multi-step workflow? → **Pattern 3: GATE-Based** (the recommended default).
- Skill needed continuously across a short workflow? → **Pattern 2: Upfront Loading.**
- Knowledge base too large to fit in any prompt? → **Pattern 4: RAG.**
- Skill better modeled as a tool call the agent decides when to invoke? → **Pattern 5: Tool-Based Lookup.**
- Multi-agent system with an orchestrator? → **Pattern 6: Hierarchical** (combine with Pattern 3).
- High-stakes output where errors are costly? → **Add Pattern 7: Multi-Agent Verification.**

## How the framework uses each pattern

| # | Where |
|---|-------|
| 1 | Orchestration rules embedded in [`../CLAUDE.md`](../CLAUDE.md). |
| 2 | Initial-check pair (`skill-framework-fitness` + `skill-security-hygiene`) loaded upfront on every dispatch. |
| 3 | Stage agents GATE-load skills at the decision point they apply to. Recommended default for new agents. |
| 5 | Tool wrappers live in [`../tools/`](../tools/); a skill invokes them at a specific step. No tool shipped yet. |
| 6 | The four-layer chain (**harness → orchestrator → agent → skill**) is Pattern 6 by construction. |
| 7 | Orchestrator's post-agent verification gates (see [`../agents/orchestrator.md`](../agents/orchestrator.md)). |

Pattern 4 (RAG) is not used and is not planned; the framework's
knowledge base is small enough that GATE-based loading handles it
without retrieval overhead.

## Pattern 1: System Prompt Embedding

**How it works.** Rules are pasted directly into the system prompt so
the model always has them in context.

**Tradeoffs.** Maximum recall — the model never forgets what's in its
prompt. But it permanently uses up context window space on every run,
whether or not the rules are relevant. Doesn't scale past roughly two
skills' worth of content before it crowds out the memory Claude needs
for the actual task.

**Example in this framework.** `../CLAUDE.md` embeds harness orientation
directly: the layer hierarchy, the environment, the resource-priority
rule. Every framework session sees this content because the harness
loads CLAUDE.md automatically.

**When to use it:**

- Small, stable rule sets (under ~2,000 tokens, roughly 1,500 words).
- Rules needed on every run (routing, environment, output-format skeleton).
- Configuration that rarely changes.

**When to avoid it:**

- Large or growing knowledge bases.
- Rules that only apply to specific task types.
- Content that changes frequently (each edit means updating the prompt).

## Pattern 2: Upfront Loading

**How it works.** The agent reads all its skill files at the start of
a run, before doing any work.

**Tradeoffs.** Simple to implement — just list the files to read in the
agent prompt. But it wastes memory on skills that may not be relevant,
and the content goes stale: by the time the agent reaches Step 8 and
needs formatting rules it read at Step 1, that content is far back in
the conversation and Claude pays less attention to it.

**Example in this framework.** The orchestrator's pre-flight loads the
initial-check pair upfront on every dispatch:

```
Load before routing to the stage agent:
  - skills/skill-framework-fitness/SKILL.md
  - skills/skill-security-hygiene/SKILL.md
```

These two skills apply to *every* framework artifact regardless of
pipeline, so paying the upfront cost is worth it — a GATE at every
possible decision point would be wasteful. Every other framework skill
is a candidate for Pattern 3 instead.

**When to use it:**

- Skills needed continuously throughout a short workflow.
- Small skill files (under ~1,000 tokens each).
- When context decay isn't an issue (workflows under ~10 steps).

**When to avoid it:**

- Long multi-step workflows (10+ steps) — content decays; use Pattern 3.
- Large skill files — pay the cost only at the step that needs them.
- When only a subset of rules applies to any given task.

**Failure mode this addresses.** An early version of a hypothetical
review agent could load ten skills at Step 1 (~4,000 lines total). By
Step 8, when it needs the output-format template, that template is
thousands of lines back in the conversation. The agent produces
plain-text output instead of Doc Team diff format — it has "forgotten"
the template it read at the start. Fix: switch that template to
Pattern 3 and load it at Step 8, right when the agent needs it.

## Pattern 3: GATE-Based / Just-in-Time Loading

**This is the recommended default for framework agents.** Handles the
widest range of workflows.

**How it works.** The agent workflow defines explicit decision points
(GATEs) where the agent must stop, read a specific skill file, apply
it, and show evidence it followed the skill before continuing.

**Tradeoffs.** Efficient context use — only the relevant skill is in
working memory when it's applied. Fresh recall at the decision point.
Auditable, because the agent must cite evidence. But it requires more
complex prompt engineering: you design the workflow with explicit gates
and specify which skill maps to which step.

**Example shape for a new agent.** An agent definition that uses
Pattern 3 looks like this:

```markdown
## Design principle: skills at decision points

Do NOT load all skills upfront. Load the specific skill at the moment
you need it to make a decision. This keeps the skill fresh in context
when applied and forces you to follow the skill as a procedure rather
than from memory.

### Step 4: Diagnose

**GATE — Read the skill matching the input type before proceeding.**

| Input type       | Read this now                              |
|------------------|--------------------------------------------|
| {type A}         | ../skills/skill-{name-a}/SKILL.md          |
| {type B}         | ../skills/skill-{name-b}/SKILL.md          |

### Step 8: Format output

**GATE — Read ../skills/skill-doc-diff/SKILL.md NOW.**
```

Every GATE requires evidence: the agent produces a "Skills Loaded"
block, a validation output, a grep result, or a citation showing it
followed the skill.

**How to design a GATE-based agent:**

1. Map the workflow as numbered steps.
2. Identify which steps require reference material.
3. For each step, name the exact skill file and section.
4. Label those steps GATE.
5. Require evidence (validation output, grep results, citations) that
   the skill was followed.

**When to use it:**

- Multi-step workflows with distinct decision points.
- Large skill libraries where only two or three skills apply per task.
- When auditability matters — you need to prove rules were followed.
- Skills that change often; fresh reads pick up revisions.

**When to avoid it:**

- Simple single-step tasks.
- When the same skill is needed continuously (Pattern 2 is simpler).
- When Read-call overhead is a real concern.

## Pattern 4: RAG / Retrieval-Augmented Generation

**Not used in this framework.**

**How it works.** An external search system (a vector database or
embedding index) finds the most relevant passages from a large
knowledge base at query time and injects them into the prompt.

**Tradeoffs.** Scales to enormous knowledge bases — thousands of pages,
multiple manuals, entire codebases. But you lose control over exactly
what gets retrieved and what surrounds it. Chunk boundaries may split
a rule in half. Retrieval relevance depends on embedding quality.

**Why the framework skips it.** The framework's knowledge base is
moderate — a small set of rule skills plus reference materials. GATE-
based loading handles that without RAG overhead. RAG also risks
retrieval that splits interdependent rules (rule R14 references rule
R15; a chunk missing the cross-reference is worse than no chunk).

**When to use it (elsewhere):**

- Very large knowledge bases (100+ documents, entire style guides).
- Questions where skills can't be pre-mapped to steps.
- When "good enough" recall is acceptable — combine with Pattern 7 to
  catch retrieval errors.

## Pattern 5: Tool-Based Lookup

**How it works.** Skills are exposed as callable tools — commands the
agent runs on demand, like reading a file, running a grep, or invoking
a binary. The agent decides when to invoke them.

**Tradeoffs.** The agent has autonomy to decide when to consult
references. Works well when the agent can reliably judge what it
doesn't know. The risk is skipping: if the tool isn't forced, the agent
may not call it, especially under time pressure or with simpler models.

**How it differs from Pattern 3 (GATE-Based):**

| Aspect       | GATE-Based                    | Tool-Based                    |
|--------------|-------------------------------|-------------------------------|
| Who decides  | Prompt designer               | Agent (the model)             |
| When loaded  | At predefined workflow steps  | When the agent chooses        |
| Guarantee    | Mandatory (GATE = must read)  | Optional (agent may skip)     |
| Flexibility  | Fixed workflow                | Adaptive to novel tasks       |

**Example in this framework.** A prose-linting workflow that
delegates to Vale would live in [`../tools/`](../tools/) — for
example, `../tools/vale/` with a `run-vale.sh` wrapper. A skill that
loads Vale via Pattern 5 would say: *"When you reach a prose-check
step, call `../tools/vale/run-vale.sh` on the target file and enumerate
findings."* Same shape for an ImageMagick verifier or a Mermaid
renderer. No tool ships in the framework yet; `tools/` is empty.

**When to use it:**

- Exploratory tasks where the reference isn't predictable.
- When the agent model is strong enough to self-direct (Opus-class).
- As a supplement to Pattern 3 for edge cases.
- General-purpose agents (not domain-specific workflows).

**When to avoid it:**

- Compliance-critical workflows — the agent might skip a required check.
- Smaller models that may not reliably self-direct.
- When you need auditable proof every rule was consulted.

## Pattern 6: Hierarchical / Cascading Prompts

**How it works.** Knowledge is split across layers. A base system
prompt, a task-specific agent prompt, and per-step skill files. Each
layer contains only what's relevant at that level.

**Example in this framework — the four-layer chain:**

```
Layer 1 — Harness (../CLAUDE.md, ~2,500 tokens)
  Dispatch rules, environment, resource priority.
  Always in context.

Layer 2 — Orchestrator (../agents/orchestrator.md, ~4,000 tokens)
  Pipeline routing, pre-flight, initial check, verification gates.
  Loaded when framework work is dispatched.

Layer 3 — Stage agent (../agents/{name}.md, ~2,000-3,000 tokens)
  Workflow steps, skill-to-step mapping, input handling.
  Loaded when the orchestrator routes to it.

Layer 4 — Skill (../skills/{skill-name}/SKILL.md, ~2,000-5,000 tokens each)
  Detailed rules, examples, reference tables.
  Loaded at GATE points inside the stage agent.
```

The harness does not need to know pipeline-specific dispatch details.
The stage agent does not need to know the dispatch logic for other
agents. Each layer sees only what it needs.

**When to use it:**

- Multi-agent systems with an orchestrator.
- When different tasks need different subsets of knowledge.
- When you want to separate "what to do" from "how to do it."

**When to avoid it:**

- Single-agent systems — the layering adds complexity for no benefit.
- When all knowledge is needed at every layer.

## Pattern 7: Multi-Agent Verification

**How it works.** A second pass (or a second agent) checks the first
agent's output against the knowledge base. The reviewer catches errors
the generator missed.

**Example in this framework — the orchestrator's post-agent verification.**
After every stage-agent run, the orchestrator performs independent
checks before presenting results:

```markdown
## Orchestrator Verification
- [x/!] Public/private API: {header}, {export macro}, {conclusion}
- [x/!] \since: {commit} in {tag} (or: agent inferred — REJECT)
- [x/!] Output filename: {algorithm result} matches agent's field
- [x/!] Source text: line numbers match actual file
- [x/!] Proposed fix compliance: {any rule violations found}
```

Each agent declares its own gate list in its definition file; the
orchestrator runs those gates independently. The rule: if the agent's
output has errors, regenerate corrected suggestions rather than
listing errors alongside the flawed output.

This catches a specific failure mode: fixes that address one issue but
introduce another (fixing passive voice while adding wordiness, fixing
grammar while breaking line length).

**When to use it:**

- High-stakes outputs where errors have real cost (published docs,
  code patches, compliance reports).
- When the generator agent has known blind spots.
- When verification criteria are concrete and checkable.

**When to avoid it:**

- Low-stakes tasks where speed matters more than precision.
- When verification criteria are subjective.
