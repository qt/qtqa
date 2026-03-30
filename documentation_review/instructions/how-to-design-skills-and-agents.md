# How to Design Skills and Agents

**Author:** Jerome Pasion, Qt Documentation Team\
**Produced with:** Claude (Anthropic) — pattern analysis, examples, and
rhetorical framework drafted collaboratively in Cowork mode

How to give an LLM agent access to reference material. This guide covers
seven patterns, from simplest to most sophisticated, with examples from
the Qt Doc Team's agents and skills.

Use this to decide which pattern (or combination) fits your agent.

## At a Glance

| # | Pattern | How It Works | Best For | Watch Out For |
|---|---------|-------------|----------|---------------|
| 1 | **System Prompt Embedding** | Rules pasted into the system prompt | Small, stable rule sets needed every run | Burns fixed context; doesn't scale past ~2 skills |
| 2 | **Upfront Loading** | Agent reads all skill files at start | Short workflows; skills needed continuously | Context decay on long runs; wastes tokens on irrelevant skills |
| 3 | **GATE-Based / Just-in-Time** | Agent reads specific skill at each decision point | Multi-step workflows; large skill libraries | More complex prompt design; extra tool calls per run |
| 4 | **RAG / Retrieval** | External system retrieves relevant chunks | Very large knowledge bases (100+ docs) | Lose control over what's retrieved; chunk boundaries split rules |
| 5 | **Tool-Based Lookup** | Skills exposed as tools the agent calls on demand | Exploratory tasks; strong models (Opus) | Agent may skip lookups; not auditable |
| 6 | **Hierarchical / Cascading** | Knowledge split across prompt layers (orchestrator → agent → skill) | Multi-agent systems with an orchestrator | Adds complexity for single-agent setups |
| 7 | **Multi-Agent Verification** | Second pass checks first agent's output against knowledge base | High-stakes outputs where errors are costly | Slower; doubles compute; needs concrete verification criteria |

**Our stack combines 1 + 2 + 3 + 6 + 7.** Most real agents layer
multiple patterns. See [Choosing Your Pattern](#choosing-your-pattern)
for a decision tree.

---

## Pattern 1: System Prompt Embedding

**How it works:** Paste all rules directly into the system prompt so the
model always has them in context.

**Tradeoffs:** Maximum recall — the model never forgets what's in its
prompt. But it burns fixed context on every run, whether or not the rules
are relevant. Doesn't scale past roughly two skills' worth of content
before you start crowding out working memory for the actual task.

**Our example — CLAUDE.md orchestrator:**

The `CLAUDE.md` file embeds dispatch rules, verification gates,
environment paths, and the agent inventory directly. Every conversation
sees this content:

```markdown
### Dispatch Rules

| Task                   | Agent                | Model |
|------------------------|----------------------|-------|
| Documentation review   | qt-doc-reviewer      | opus  |
| Create/scaffold docs   | doc-shaper           | opus  |
| QDoc warnings          | qdoc-warning-fixer   | opus  |
```

This works because dispatch logic is small, always needed, and rarely
changes. You wouldn't want 65 language rules here.

**When to use it:**

- Small, stable rule sets (under ~2,000 tokens)
- Rules needed on every run (routing, environment, output format skeleton)
- Configuration that rarely changes

**When to avoid it:**

- Large or growing knowledge bases
- Rules that only apply to specific task types
- Content that changes frequently (each edit means updating the prompt)


---

## Pattern 2: Upfront Loading

**How it works:** The agent reads all skill files at the start of a run,
before doing any work.

**Tradeoffs:** Simple to implement — just list the files to read in the
agent prompt. But it wastes context on skills that may not be relevant,
and the content goes stale: by the time the agent reaches Step 8 and
needs the formatting rules it read at Step 1, those tokens are far back
in context and attention has degraded.

**Our example — doc-impact-analyzer (current, hybrid approach):**

The doc-impact-analyzer still uses partial upfront loading because it
needs cross-reference search patterns available throughout the entire
analysis:

```markdown
## Step 2: Load Skills (MANDATORY)

**You MUST load these skills using the Read tool before proceeding:**

1. `~/.claude/skills/skill-linking-check/SKILL.md`
2. `~/.claude/skills/skill-qdoc/SKILL.md`
3. `~/.claude/skills/skill-all-docs/references/products.md`

**Do NOT proceed to Step 3 until skills are loaded.**
```

It also loads additional skills conditionally based on change type:

```markdown
**Load conditionally:**

| Content              | Load Skill                              |
|----------------------|-----------------------------------------|
| QML type changes     | skill-qdoc/references/link-resolution.md|
| Class renames        | skill-qdoc/references/node-system.md    |
| Cross-product impact | skill-all-docs/references/products.md   |
```

This is a pragmatic compromise — the core search patterns are needed
throughout, but specialized references are loaded only when the change
type requires them.

**Our example — old agents (pre-November 2025):**

Before v5.0 of skill-doc-diff, agents loaded everything at start. The
changelog records the shift:

```
- v5.1 (2025-11-30): Removed agent usage patterns
- v5.0 (2025-11-30): Streamlined to essential reference format
```

The skills were restructured from "agent instruction manuals" into
"reference materials" that agents consult at specific points.

**When to use it:**

- Skills needed continuously throughout the workflow (search patterns,
  cross-reference tables)
- Small skill files (under ~1,000 tokens each)
- Short workflows where context decay isn't an issue

**When to avoid it:**

- Long multi-step workflows (10+ steps)
- Large skill files (the 65-rule language style guide, for instance)
- When only a subset of rules apply to any given task


---

## Pattern 3: GATE-Based / Just-in-Time Loading

**How it works:** The agent workflow defines explicit decision points
(GATEs) where the agent must stop, read a specific skill file, apply it,
and show evidence it followed the skill before continuing.

**Tradeoffs:** Efficient context use — only the relevant skill is in
working memory when it's applied. Fresh recall at the decision point.
Auditable, because the agent must cite evidence. But it requires more
complex prompt engineering: you need to design the workflow with explicit
gates and specify which skill maps to which step.

**Our example — qdoc-warning-fixer (current architecture):**

The agent definition states the design principle explicitly:

```markdown
## Design Principle: Skills at Decision Points

Do NOT load all skills upfront. Instead, load the specific skill at the
moment you need it to make a decision. This ensures:
- The skill content is fresh in context when applied
- You follow the skill as a procedure, not from memory
- You don't waste context on skills irrelevant to the warning type
```

Each step has a labeled GATE:

```markdown
### Step 4: Diagnose

**GATE — Read the skill reference matching the warning type:**

| Warning Type              | Read This Now                              |
|---------------------------|--------------------------------------------|
| "Can't link to 'X'"      | skill-qdoc/references/link-resolution.md   |
| "No such parameter"       | skill-qdoc/references/markup-commands.md   |
| "Has no \inmodule"        | skill-qdoc/references/context-commands.md  |
```

```markdown
### Step 6: Write Documentation

**GATE — Read skill-language-style/SKILL.md NOW.**

Before writing ANY prose, read the skill and apply these specific
sections: R14, R16, R1, R2, R3, R4, R5, R7, R11, R38, R64...
```

```markdown
### Step 7: Verify Line Lengths

**GATE — Read skill-line-wrap/SKILL.md NOW.**
```

```markdown
### Step 8: Format Output

**GATE — Read skill-doc-diff/SKILL.md NOW.**
```

The skill-to-step mapping table in the agent definition makes this
explicit:

```markdown
| Skill               | Decision Point                        |
|---------------------|---------------------------------------|
| skill-qdoc          | Step 4 (Diagnose)                     |
| skill-doc-diff      | Step 8 (Format Output)                |
| skill-qdoc-output   | Step 8 (Output field)                 |
| skill-language-style| Step 6 (Write Documentation)          |
| skill-line-wrap     | Step 7 (Verify Line Lengths)          |
| skill-module-export | Step 4 (public vs internal)           |
```

**How to design your own GATE-based agent:**

1. Map out your workflow as numbered steps
2. Identify which steps require reference material
3. For each step, specify exactly which skill file and which section
4. Label those steps as GATEs
5. Require evidence (validation output, grep results, citations) that
   the skill was followed

**When to use it:**

- Multi-step workflows with distinct decision points
- Large skill libraries where only 2-3 skills apply per task
- When auditability matters (you need to prove rules were followed)
- Skills that are being actively revised (fresh reads pick up changes)

**When to avoid it:**

- Simple single-step tasks
- When the same skill is needed continuously (upfront may be simpler)
- When tool-call overhead is a concern (each GATE adds a Read call)


---

## Pattern 4: RAG / Retrieval-Augmented Generation

**How it works:** An external system (vector database, embedding index)
retrieves the most relevant chunks of your knowledge base at query time
and injects them into the prompt.

**Tradeoffs:** Scales to enormous knowledge bases — thousands of pages,
multiple manuals, entire codebases. But you lose control over exactly
what gets retrieved and what context surrounds it. Chunk boundaries may
split a rule in half. Retrieval relevance depends on embedding quality.

**We don't use this pattern.** Here's why:

- Our rules are precise and interdependent (R14 references R15, R16
  references R3). A retrieved chunk missing the cross-reference is
  worse than no chunk at all.
- QDoc syntax rules have exact formatting requirements. "Close enough"
  retrieval produces confidently wrong suggestions.
- Our knowledge base is moderate-sized (~65 rules + reference files).
  GATE-based loading handles this without RAG overhead.

**When to use it:**

- Very large knowledge bases (100+ documents, entire style guides)
- When questions are unpredictable (you can't pre-map skills to steps)
- When "good enough" recall is acceptable
- When combined with a verification layer to catch retrieval errors

**When to avoid it:**

- Precision-critical domains (syntax rules, compliance checklists)
- Interdependent rules that need to be read together
- When you need full control over what the agent sees


---

## Pattern 5: Tool-Based Lookup

**How it works:** Skills are exposed as callable tools (MCP tools,
function calls) that the agent decides when to invoke. For example:
`get_style_rule(rule_id: "R14")` or `check_line_length(text: "...")`.

**Tradeoffs:** The agent has autonomy to decide when to consult
references. This works well when the agent can reliably judge what it
doesn't know. The risk is skipping: if the tool isn't forced, the agent
may not call it, especially under time pressure or with simpler models.

**How it differs from GATE-based:**

| Aspect         | GATE-Based                  | Tool-Based                |
|----------------|-----------------------------|---------------------------|
| Who decides    | Prompt designer (you)       | Agent (the model)         |
| When loaded    | At predefined workflow steps| When agent chooses         |
| Guarantee      | Mandatory (GATE = must read)| Optional (agent may skip)  |
| Flexibility    | Fixed workflow              | Adaptive to novel tasks    |

**When to use it:**

- Exploratory tasks where the needed reference isn't predictable
- When the agent model is strong enough to self-direct (Opus-class)
- As a supplement to GATE-based loading for edge cases
- When building general-purpose agents (not domain-specific workflows)

**When to avoid it:**

- Compliance-critical workflows (agent might skip a required check)
- When using smaller models that may not reliably self-direct
- When you need auditable proof that every rule was consulted


---

## Pattern 6: Hierarchical / Cascading Prompts

**How it works:** Knowledge is split across layers — a base system
prompt, a task-specific agent prompt, and per-step skill files. Each
layer contains only what's relevant at that level.

**Our example — the three-layer stack:**

```
Layer 1: CLAUDE.md (orchestrator)
  - Dispatch rules, environment, verification gates
  - Always in context, ~2,500 tokens

Layer 2: Agent definition (e.g., qdoc-warning-fixer.md)
  - Workflow steps, skill-to-step mapping, input handling
  - Loaded when agent is dispatched, ~3,000 tokens

Layer 3: Skill files (e.g., skill-language-style/SKILL.md)
  - Detailed rules, examples, reference tables
  - Loaded at GATE points, ~2,000-5,000 tokens each
```

The orchestrator doesn't need to know the 65 language rules. The agent
doesn't need to know the dispatch logic for other agents. Each layer
sees only what it needs.

**When to use it:**

- Multi-agent systems with an orchestrator
- When different tasks need different subsets of knowledge
- When you want to separate "what to do" from "how to do it"

**When to avoid it:**

- Single-agent systems (the layering adds complexity for no benefit)
- When all knowledge is needed at every layer


---

## Pattern 7: Multi-Agent Verification

**How it works:** A second pass (or second agent) checks the first
agent's output against the knowledge base. The reviewer catches errors
the generator missed.

**Our example — orchestrator post-agent verification:**

After every agent run, the orchestrator performs independent checks
before presenting results:

```markdown
## Orchestrator Verification
- [x/!] Public/private API: {header}, {export macro}, {conclusion}
- [x/!] \since: {commit} in {tag} (or: agent inferred — REJECT)
- [x/!] Output filename: {algorithm result} matches agent's field
- [x/!] Source text: line numbers match actual file
- [x/!] Proposed fix compliance: {any rule violations found}
```

Each agent has specific verification gates. For the qdoc-warning-fixer:

```markdown
1. Public/private API — header export macro, .h vs _p.h, class name
2. \since version — git commit + tag evidence (not inferred)
3. Output filename — execute canonicalization algorithm
4. Source text & line numbers — read file, confirm context
5. Fix compliance — scan proposed text for rule violations
```

The key rule: **"If agent output has errors: Regenerate corrected
suggestions, do not list errors then show flawed output."**

This catches a specific failure mode documented in skill-doc-diff:

```markdown
### The Problem

Fixes that address one issue often introduce another:
- Fixing passive voice but introducing wordiness
- Fixing wordiness but leaving passive voice
- Fixing grammar but breaking line length
- Fixing one Latin term but missing another in the same sentence
```

**When to use it:**

- High-stakes outputs where errors have real cost (published docs,
  code patches, compliance reports)
- When your generator agent is known to have blind spots
- When the verification criteria are concrete and checkable

**When to avoid it:**

- Low-stakes tasks where speed matters more than precision
- When verification criteria are subjective


---

## Choosing Your Pattern

Start with this decision tree:

```
Is your knowledge base small (<2,000 tokens) and always needed?
  YES → Pattern 1: System Prompt Embedding

Is your workflow linear with distinct decision points?
  YES → Pattern 3: GATE-Based (our recommended default)

Does the agent need the same reference throughout the entire run?
  YES → Pattern 2: Upfront Loading

Is the knowledge base very large (100+ documents)?
  YES → Pattern 4: RAG / Retrieval

Are tasks unpredictable (can't pre-map skills to steps)?
  YES → Pattern 5: Tool-Based Lookup

Do you have multiple agents with an orchestrator?
  YES → Pattern 6: Hierarchical (combine with Pattern 3)

Is output quality critical and errors costly?
  YES → Add Pattern 7: Multi-Agent Verification
```

Most real agents combine patterns. Our current stack uses:

- **Pattern 1** for orchestration (CLAUDE.md)
- **Pattern 3** as the primary mechanism (GATE-based skill loading)
- **Pattern 2** selectively (doc-impact-analyzer's upfront search patterns)
- **Pattern 6** structurally (orchestrator → agent → skill layers)
- **Pattern 7** as a quality gate (post-agent verification)


---

## Evolution Timeline

How the Qt Doc Team agents moved through these patterns:

```
Nov 2025    Pattern 2 (upfront loading)
            - Agents read all skills at start
            - skill-doc-diff v5.0: "Streamlined to essential reference"
            - skill-doc-diff v5.1: "Removed agent usage patterns"
            - Skills restructured from instructions → reference material

Dec 2025    Transition period
            - skill-doc-diff v5.5: Added Category field
            - Skills getting more structured, smaller, focused

Feb 2026    Pattern 3 (GATE-based, current)
            - skill-doc-diff v5.11: "Mandatory upfront verification rule"
            - skill-language-style v3.0+: 50+ rules, too large for upfront
            - qdoc-warning-fixer redesigned with explicit GATEs
            - skill-qdoc split into reference sub-files:
              link-resolution.md, markup-commands.md, context-commands.md,
              node-system.md, index-files.md, macros-warnings.md

Mar 2026    Pattern 7 added (verification layer)
            - Orchestrator verification gates added to CLAUDE.md
            - Per-agent verification checklists defined
            - skill-language-style v3.8-3.9: verification requirements
              added directly to rules (R16 \since, R60 link verification)
```

The key lesson: **we didn't replace patterns, we layered them.** Each
new pattern addressed a specific failure mode of the previous approach.


---

## Practical Checklist for Building a New Agent

1. **Define the workflow** — Write out the steps your agent follows.
   Number them.

2. **Identify decision points** — Which steps need reference material?
   Mark those as GATEs.

3. **Write or choose skills** — Each GATE maps to a skill file. Keep
   skills focused on one concern (formatting, syntax, terminology).

4. **Choose the loading pattern** for each skill:
   - Needed throughout? → Upfront (Pattern 2)
   - Needed at one step? → GATE (Pattern 3)
   - Small and always needed? → Embed in prompt (Pattern 1)

5. **Add verification** — Define what "correct output" looks like.
   Write a checklist the orchestrator can run independently.

6. **Test and iterate** — Run the agent on real tasks. When it fails,
   ask: did it have the right reference at the right time? Adjust
   the loading pattern accordingly.

7. **Track changes** — Keep a CHANGELOG.md for each skill. When the
   agent makes a recurring error, update the skill and bump the
   version.


---

## Rhetorical Modes in Agent Design

The seven patterns above describe *when* knowledge reaches the agent.
This section covers *how* that knowledge is structured — what kind of
reasoning each step invites from the model.

Every agent step falls into one of three rhetorical modes. Choosing the
wrong mode for a step is a common source of agent failure: a step that
needs dialectic reasoning but receives didactic rules produces brittle,
ungrounded output. A step that needs didactic compliance but gets
open-ended dialectic reasoning produces inconsistent formatting.

### Didactic: "Here are the rules. Apply them."

Direct instruction. The agent receives explicit rules and checks
compliance. No reasoning about *whether* the rule applies — only
*how* to apply it.

**Characteristics:**
- Numbered rules with clear pass/fail criteria
- Checklists and lookup tables
- Mechanical substitution (find X, replace with Y)
- The agent acts as an executor, not a judge

**Where we use it:**

skill-language-style is almost entirely didactic. The rules are
categorical:

```
R1:  Use active voice
R38: No Latin terms — replace "via" with "through", "using", or "with"
R40: 80-column line length limit
R64: Code elements use \c{}, parameters use \a{}
```

The agent doesn't debate whether "via" should be allowed in a
particular context. It finds "via" and replaces it.

skill-line-wrap is pure didactic — a threshold table:

```
| Context                    | Threshold | Action              |
|----------------------------|-----------|---------------------|
| C++ code, examples, QDoc   | 80        | Required — must fix |
| Prose paragraphs, briefs   | 110       | Advisory — flag only|
```

skill-doc-diff is didactic about structure: field names, field order,
arrow alignment, approval prompt wording. The template is prescribed
exactly.

**When to write didactically:**
- Formatting and syntax rules
- Terminology substitutions
- Compliance checklists
- Any step where human judgment is not required

**Prompt pattern for didactic steps:**

```
### Step 7: Verify Line Lengths

**GATE — Read skill-line-wrap/SKILL.md NOW.**

Check every line in your proposed fix against the enforcement table.
Count from column 0 including indentation.
```

Notice the language: "check", "count", "verify". No room for
interpretation.


### Dialectic: "Here is evidence. Reason toward a conclusion."

Dialogue-based reasoning. The agent gathers evidence, consults
references, weighs factors, and arrives at a grounded conclusion.
The output must show the reasoning chain, not just the answer.

**Characteristics:**
- Questions the agent must answer with evidence
- Decision trees with branching logic
- Evidence gathering before judgment (grep results, file reads)
- The agent acts as an investigator, not a rule-checker

**Where we use it:**

The qdoc-warning-fixer's diagnostic sequence (Steps 2–5) is
dialectic. The agent doesn't start with the answer — it builds
toward it:

```
Step 2: Read the source file at the warning line. What does the
        code say?
Step 3: Read the header. Is there an export macro? Is the header
        public (.h) or private (_p.h)? Is the class name *Private?
Step 4: GATE — Read skill-module-export. Walk the decision tree:
        Export macro + public header → full docs.
        No export, or _p.h, or *Private → \internal.
        What's the verdict for THIS class?
Step 5: Based on diagnosis, which fix applies?
```

The Cause field in skill-doc-diff is dialectic output — it requires
the agent to explain *why* an issue exists, citing evidence:

```
**Cause:** `SamplerHint` is a nested enum in
`QQuick3DTextureProviderExtension` and requires full qualification.
Searched `grep 'name="SamplerHint"'` in index files — not found at
top level, only under parent class.
```

The `\since` verification workflow is dialectic: "Find the commit
that introduced this type. Find the earliest tag containing that
commit. What version does the evidence say?" The agent can't skip
to an answer — it must show the git log output.

The orchestrator's post-agent verification (Pattern 7) is the most
explicitly dialectic element. It plays adversary:

```
You said \since 6.2 — show me the git tag.
You said this is public API — I read the header, where's the
  export macro?
You said the output file is X.html — I ran the algorithm and
  got Y.html.
```

**When to write dialectically:**
- Diagnosis and root-cause analysis
- Public vs private API classification
- Any step requiring evidence before judgment
- Verification and adversarial review

**Prompt pattern for dialectic steps:**

```
### Step 3: Check Header for API Status

From the header, extract:
- Export macro (e.g., Q_WAYLANDCOMPOSITOR_EXPORT)
- QML registration macros (QML_NAMED_ELEMENT, QML_ELEMENT)
- Whether the header is public (.h) or private (_p.h)

**GATE — If deciding public vs internal:**
Read skill-module-export/SKILL.md and follow the decision tree to
determine whether the class needs full documentation or \internal.
```

Notice the language: "extract", "determine", "follow the decision
tree". The agent must reason from evidence.


### Deliberative: "Here are the options. Recommend one."

Weighing alternatives and presenting a recommendation with reasons,
then deferring the final decision to a human. The agent acts as an
advisor, not an authority.

**Characteristics:**
- Multiple valid solutions exist
- The agent presents tradeoffs for each option
- A recommendation is given with justification
- The human makes the final call

**Where we use it:**

The Fix Options section of skill-doc-diff is deliberative:

```
**Fix Options:**
1. **Fully qualify** — Use QSSGFrameData::AttachmentSelector in \fn
2. **Use typedef** — Create a typedef at namespace scope
3. **Simplify signature** — Remove the parameter from docs

**Recommended:** Option 1 because it matches the actual function
signature.

Which option should I apply? (1/2/3 or skip)
```

The approval prompt itself ("Should I apply this fix to the file?")
is deliberative — it hands the decision to the human after
presenting the evidence.

The doc-impact-analyzer's severity classification has a deliberative
dimension — the agent must judge whether a change is Breaking, Stale,
or Cosmetic, then present its reasoning for the human to confirm or
override.

**When to write deliberatively:**
- Steps where multiple valid approaches exist
- When human judgment is needed for the final decision
- When the cost of choosing wrong is high enough to warrant review
- When team conventions haven't been established yet

**Prompt pattern for deliberative steps:**

```
### Step 5: Determine Fix

If multiple genuinely valid solutions exist and no existing codebase
pattern dictates one answer, present Fix Options:

1. **{Option}** — {description and tradeoff}
2. **{Option}** — {description and tradeoff}

**Recommended:** Option N because {evidence-based reason}.

**IMPORTANT:** Search codebase first. If grep shows an existing
pattern, recommend that directly WITHOUT presenting options.
```

Notice: the agent is told to check for an existing convention
(didactic compliance) before falling into deliberative mode. This
prevents unnecessary optionality.


### Mapping Modes to Workflow Steps

Use this table when designing a new agent. For each step in your
workflow, identify which mode it needs:

```
| Mode         | Step Does What               | Agent Role     | Evidence Required |
|--------------|------------------------------|----------------|-------------------|
| Didactic     | Checks rules, formats output | Executor       | Rule citation     |
| Dialectic    | Diagnoses, investigates      | Investigator   | Grep, file reads  |
| Deliberative | Weighs options, recommends   | Advisor        | Tradeoff analysis |
```

**The qdoc-warning-fixer mapped by mode:**

```
Step 1: Parse Warning             → Didactic   (extract fields mechanically)
Step 2: Read Source               → Dialectic  (gather evidence)
Step 3: Check Header              → Dialectic  (investigate API status)
Step 4: Diagnose                  → Dialectic  (reason from evidence + skill)
Step 5: Determine Fix             → Deliberative (weigh options if ambiguous)
                                    or Didactic (apply if single clear fix)
Step 6: Write Documentation       → Didactic   (follow R1-R64 rules)
Step 6b: Verify \since            → Dialectic  (trace git evidence)
Step 7: Verify Line Lengths       → Didactic   (check against threshold table)
Step 8: Format Output             → Didactic   (follow doc-diff template)
Step 9: Consider Alternatives     → Deliberative (present options to human)
```

**Common mistake:** treating a dialectic step as didactic. If you
write "Determine whether this is a public or private API" as a
didactic rule ("If _p.h then internal"), the agent will miss edge
cases (exported classes in private headers, QPA classes with public
headers). The dialectic version forces the agent to gather evidence
and reason through the decision tree, catching the exceptions.

**Opposite mistake:** treating a didactic step as dialectic. If you
write "Consider whether active voice would improve this sentence"
instead of "R1: Use active voice", the agent will rationalize
keeping passive constructions. Didactic rules leave no room for
the model to argue itself out of compliance.


### Choosing the Right Mode

When designing a step, ask:

1. **Is there one right answer that a lookup table can give?**
   → Didactic. Write a rule.

2. **Does the answer depend on evidence the agent must gather first?**
   → Dialectic. Write a reasoning chain with evidence requirements.

3. **Are there multiple valid answers that a human should choose between?**
   → Deliberative. Write an options template with recommendation.

Most agents need all three modes at different steps. The skill files
themselves tend to be didactic (reference material), while the agent
workflow orchestrates when to apply dialectic reasoning and when to
defer deliberatively to the human.


---

## Sample Prompts

These are prompts you can give Claude to build agents and skills using
each pattern. Copy, adapt to your domain, and iterate.

### Building a skill from scratch

Start here if you have rules or reference material but no skill file yet.

```
I have a set of rules for [YOUR DOMAIN] that I want my agents to
reference. Here are the rules:

[PASTE YOUR RULES OR ATTACH A FILE]

Create a skill file at ~/.claude/skills/skill-[name]/SKILL.md that
organizes these into a structured reference. Include:
- A YAML frontmatter block with name, description, and version
- Rules grouped by category
- Examples for each rule
- A "Common Mistakes" section based on errors you'd expect

Keep the skill under 3,000 tokens so it fits comfortably in context
when an agent reads it at a GATE point.
```

### Building a simple agent (Pattern 1 — embedded rules)

Use this when your rules are small enough to live inside the agent
definition itself.

```
Create an agent definition at ~/.claude/agents/[name].md for
[DESCRIBE THE TASK].

The agent should [DESCRIBE WHAT IT DOES, STEP BY STEP].

Here are the rules it needs to follow:

[PASTE YOUR SHORT RULE SET — under ~2,000 tokens]

Embed the rules directly in the agent prompt since they're small and
always needed. Don't create separate skill files for this.

Include a Self-Check section at the end listing what the agent
verifies before presenting output.
```

**Example — a commit message reviewer:**

```
Create an agent definition at ~/.claude/agents/commit-msg-reviewer.md
that reviews Git commit messages against our team conventions.

Rules (embed directly — they're short):
- Subject line: imperative mood, max 72 characters, no trailing period
- Body: wrapped at 72 columns, explains WHY not WHAT
- Footer: "Task-number: PROJECT-XXXX" required
- Scope prefix required: "module: Subject line here"

The agent should:
1. Parse the commit message (accept text, SHA, or Gerrit URL)
2. Check each rule
3. Output a pass/fail verdict with specific line-by-line feedback
4. If failing, suggest a corrected version

Include a Self-Check before output.
```

### Building a GATE-based agent (Pattern 3 — recommended)

Use this for multi-step workflows with existing skill files.

```
Create an agent definition at ~/.claude/agents/[name].md that
[DESCRIBE THE TASK].

The agent should follow these steps:

1. [STEP — describe what happens]
2. [STEP — describe what happens]
   GATE: Read ~/.claude/skills/[skill]/SKILL.md at this step
3. [STEP — describe what happens]
   GATE: Read ~/.claude/skills/[other-skill]/SKILL.md at this step
4. [STEP — format output]
   GATE: Read ~/.claude/skills/skill-doc-diff/SKILL.md

Use the GATE-based design principle: do NOT load skills upfront.
Each GATE must:
- Name the exact skill file to read
- Specify which section of the skill applies
- Require the agent to show evidence it followed the skill

Include a skill-to-step mapping table at the top and a Self-Check
section at the end.

Model: opus
```

**Example — a translation review agent:**

```
Create an agent definition at ~/.claude/agents/translation-reviewer.md
that reviews translated .ts (Qt Linguist) files for quality issues.

Steps:
1. Parse the .ts file — extract source strings and translations
2. Check translation completeness — flag untranslated or fuzzy entries
   GATE: Read ~/.claude/skills/skill-translation-rules/SKILL.md
   (apply section: Completeness Checks)
3. Check terminology consistency — verify product names, UI terms
   GATE: Read ~/.claude/skills/skill-qt-terminology/SKILL.md
   (apply section: Product Names, UI Labels)
4. Check placeholder preservation — %1, %n, HTML tags must survive
   GATE: Read ~/.claude/skills/skill-translation-rules/SKILL.md
   (apply section: Placeholder Rules)
5. Format output
   GATE: Read ~/.claude/skills/skill-doc-diff/SKILL.md

Use the GATE-based design. Include skill-to-step mapping table.
Include Self-Check.

Model: opus
```

### Building an agent with upfront + GATE hybrid (Patterns 2 + 3)

Use this when some references are needed throughout the workflow.

```
Create an agent definition at ~/.claude/agents/[name].md that
[DESCRIBE THE TASK].

This agent needs two loading strategies:

**Upfront (read at start, needed throughout):**
- ~/.claude/skills/[skill-A]/SKILL.md — [why needed throughout]
- ~/.claude/skills/[skill-B]/SKILL.md — [why needed throughout]

**GATE-based (read at specific steps):**
- Step N: Read ~/.claude/skills/[skill-C]/SKILL.md — [why here]
- Step M: Read ~/.claude/skills/[skill-D]/SKILL.md — [why here]

Structure the agent prompt with:
1. A "Load Skills (MANDATORY)" section for upfront skills
2. GATE labels at specific workflow steps for just-in-time skills
3. A skill-to-step mapping table showing both strategies
4. A Self-Check section

Model: opus
```

**Example — the doc-impact-analyzer pattern:**

```
Create an agent at ~/.claude/agents/api-changelog-writer.md that
generates changelog entries from API diffs.

Upfront (needed for every diff comparison):
- ~/.claude/skills/skill-api-inventory/SKILL.md — module/class lookup
  tables used to classify every changed symbol

GATE-based (needed at specific steps):
- Step 3 (Categorize): Read ~/.claude/skills/skill-semver/SKILL.md
  to classify as breaking/deprecation/addition
- Step 4 (Write entries): Read ~/.claude/skills/skill-changelog-format/SKILL.md
  for entry templates and wording conventions
- Step 5 (Cross-check): Read ~/.claude/skills/skill-linking-check/SKILL.md
  to verify doc links in changelog entries

Model: opus
```

### Adding verification to an existing agent (Pattern 7)

Use this to add a quality gate after you notice recurring errors.

```
I have an existing agent at ~/.claude/agents/[name].md. It produces
[DESCRIBE OUTPUT] but keeps making these errors:

1. [ERROR PATTERN — e.g., "uses wrong \since version"]
2. [ERROR PATTERN — e.g., "suggests links to undocumented types"]
3. [ERROR PATTERN — e.g., "line lengths exceed 80 columns"]

Add an Orchestrator Verification section to the agent definition.
For each error pattern, define:
- What to check (the specific verification step)
- How to check it (the command or file read to perform)
- What constitutes a REJECT (when to block the output)

Also update CLAUDE.md to include a Per-Agent Verification Gates
entry for this agent, following the existing format used by
qdoc-warning-fixer and qt-doc-reviewer.

The verification must be BLOCKING — output is not presented to the
user until all checks pass.
```

**Example — adding verification to a code example auditor:**

```
My code-example-auditor agent keeps making these mistakes:

1. Claims a .cpp file is an example when it's actually a test
2. Reports line numbers that don't match the actual file
3. Suggests replacing snippets without checking if the snippet
   tag is referenced elsewhere

Add Orchestrator Verification:
- Check 1: Read the CMakeLists.txt — if target is in "tests/",
  it's a test, not an example. REJECT if misclassified.
- Check 2: Read the source file, confirm context lines match
  the agent's claimed line numbers. REJECT if off by >2 lines.
- Check 3: grep for the snippet tag across the doc source tree.
  If used in multiple .qdoc files, note all locations. REJECT
  if agent only found one reference.
```

### Creating a skill for an existing agent

Use this when an agent works but needs better reference material at
a specific step.

```
My agent at ~/.claude/agents/[name].md has a GATE at Step [N] that
reads [SKILL FILE], but the skill doesn't cover [SPECIFIC GAP].

The agent needs guidance on:
- [TOPIC 1 — what's missing]
- [TOPIC 2 — what's missing]

Update the skill file to add a new section covering these topics.
Include examples showing correct and incorrect usage.
Bump the version in the YAML frontmatter.
Add a CHANGELOG.md entry describing what was added and why.
```

**Example — adding QML rules to skill-language-style:**

```
My qt-doc-reviewer agent has a GATE at Step 6 that reads
skill-language-style/SKILL.md, but it doesn't know the rules for
documenting QML value types vs object types.

Add a section covering:
- Brief patterns for QML value types ("Represents..." not
  "Provides...")
- When to use \qmltype vs \qmlvaluetype
- Required commands: \inqmlmodule, \since, \brief
- Cross-linking from QML to C++ backing type

Include 2-3 examples of correct briefs for each type.
Bump version to 3.10. Add CHANGELOG entry.
```

### Splitting a monolithic skill into GATE-friendly sub-files

Use this when a skill has grown too large for a single GATE read.

```
My skill at ~/.claude/skills/[name]/SKILL.md has grown to [N] tokens
and covers multiple topics. Agents that read it at a GATE are getting
too much irrelevant content.

Split it into a main SKILL.md (overview + table of contents, under
1,000 tokens) and reference sub-files:

~/.claude/skills/[name]/
  SKILL.md              (overview, when to use each reference)
  references/
    [topic-a].md        (rules for topic A)
    [topic-b].md        (rules for topic B)
    [topic-c].md        (rules for topic C)

Update the agent definitions that reference this skill:
- Change GATE instructions to read the specific sub-file, not the
  main SKILL.md
- Add a lookup table mapping warning/task types to sub-files

Keep each sub-file under 2,000 tokens.
```

**Example — how skill-qdoc was split:**

```
skill-qdoc/SKILL.md was too large (covered link resolution, markup,
context commands, node system, index files, and macros all in one
file).

It was split into:
  skill-qdoc/
    SKILL.md                        (overview)
    references/
      link-resolution.md           (linking rules)
      markup-commands.md           (\a, \c, \e, \uicontrol)
      context-commands.md          (\since, \deprecated, \internal)
      node-system.md               (topic commands, \fn matching)
      index-files.md               (index file structure)
      macros-warnings.md           (warning patterns)

The qdoc-warning-fixer agent maps warning types to sub-files:

| Warning Type          | Read This Sub-File     |
|-----------------------|------------------------|
| "Can't link to 'X'"  | link-resolution.md     |
| "No such parameter"   | markup-commands.md     |
| "Has no \inmodule"    | context-commands.md    |
```

### Setting up the orchestrator layer (Pattern 6)

Use this when you have multiple agents and need a CLAUDE.md to
coordinate them.

```
I have these agents:
- ~/.claude/agents/[agent-1].md — [purpose]
- ~/.claude/agents/[agent-2].md — [purpose]
- ~/.claude/agents/[agent-3].md — [purpose]

Create a CLAUDE.md that acts as the orchestrator. Include:

1. A dispatch table mapping task types to agents
2. A pre-flight checklist (what to verify before dispatching)
3. Per-agent verification gates (what to check after each agent)
4. An output format section (default format + alternatives)
5. Environment section (paths, tools, build commands)
6. A skills inventory table (all skills and which agents use them)

The orchestrator should:
- Route tasks to the right agent based on keywords
- Provide context the agent can't fetch itself (bug reports, images)
- Verify agent output independently before presenting to user
- Output the agent's full work verbatim (never summarize)
```

**Example — a simplified orchestrator for a QA team:**

```
I have these agents:
- ~/.claude/agents/test-reviewer.md — reviews test patches
- ~/.claude/agents/bug-triager.md — analyzes bug reports
- ~/.claude/agents/coverage-auditor.md — checks test coverage gaps

Create a CLAUDE.md orchestrator with:

Dispatch:
| Task                | Agent             |
|---------------------|-------------------|
| "review test"       | test-reviewer     |
| "triage bug"        | bug-triager       |
| "check coverage"    | coverage-auditor  |

Pre-flight:
- Fetch bug report if commit references JIRA ticket
- Identify test framework (QTest, GTest, Catch2) from CMakeLists.txt

Verification gates per agent:
- test-reviewer: confirm test file exists, line numbers match
- bug-triager: confirm bug ID is valid, cross-check with git log
- coverage-auditor: confirm reported uncovered files exist
```
