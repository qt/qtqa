# Contributing

How to add an agent, a skill, a pipeline stage, an instruction, or a
doc page to the Qt Doc Agent Framework.

If you only want to know what already exists, read the tree — every
agent has a row in [`agents/README.md`](agents/README.md) and every
skill has a row in [`skills/README.md`](skills/README.md).

## Architecture context

The framework runs as a four-layer chain: **harness → orchestrator →
agent → skill.** Every added artifact lands in exactly one layer, and
that decision drives everything else — which directory it lives in,
whether it needs frontmatter, and how it's dispatched. See
[`CLAUDE.md`](CLAUDE.md) for the layer table.

## Ground rules

1. **Only verified, working changes land in qtqa.** Planned work,
   drafts, and sketches live outside the commit. A row appears in
   `agents/README.md` or `skills/README.md` only when the artifact is
   real and exercised.
2. **Every rule an agent enforces is codified as S / R / T.**
   - **S-source** if the rule comes from an external authority (QUIP,
     Qt Writing Guidelines, Microsoft Style Guide).
   - **R-rule** if it's a concrete language do/do-not distilled from an
     S-source (`skill-language-style`).
   - **T-rule** if it's an AI tell to suppress (`skill-ai-tells`).
   Rules that don't fit any of the three are either written down for AI
   use or explicitly excluded. Silent conventions don't survive.
3. **Pin the model.** New agents pin `claude-opus-5-5` in frontmatter,
   not the `opus` alias.
4. **Copyright year is the current calendar year** for new files
   (2026 as of this writing).
5. **Prose that ships gets checked against `skill-ai-tells`.** Tier 1
   hits are hard failures; Tier 2 hits need rewrites; Tier 3 is
   tolerated (Qt's own corpus uses those patterns).
6. **Deterministic first.** If a script or tool can produce the result
   (grep, Vale, QDoc, ImageMagick, a format checker), the artifact
   calls it instead of asking the LLM. Deterministic results repeat
   across runs and cost no tokens. Each agent marks which of its steps
   are deterministic (tool call) and which need LLM judgment. Checks
   that repeat go into `tools/` as scripts.
7. **Trace and test every rule claim.** Before a rule, exemption, or
   "never"/"always" lands in a skill or agent:
   - **Trace** it down the chain (C/G rule → R-rule → S-source) and quote
     the S-source text. A claim that exists only in a derived rule is
     unverified. Rewording at each step can change the meaning
     ("renders in bold" became "bold instead of `\uicontrol`").
   - **Test** it against the corpus with grep: qt5.git, and the repo
     the rule targets (for example, qt-creator for C9). Record the
     count and the commit. If the corpus contradicts the claim, the
     claim is wrong or needs a scope.
   - **Separate markup from output.** "Bold", "italic", and "code font"
     describe rendering; name the QDoc command that produces it.

## Adding an agent

1. **Decide fan-out or stage.** Fan-out agents dispatch further
   subagents; stage agents only load skills. Default is stage. Fan-out
   is only for orchestrator-shaped work (batch, multi-repo, parallel
   research).
2. **Create `agents/{name}.md`** with YAML frontmatter:
   ```yaml
   ---
   name: {name}
   description: One sentence, action-first, states the pipeline stage.
   model: claude-opus-5-5
   # tools: only include Agent if this is a fan-out agent.
   ---
   ```
3. **In the body, declare:**
   - Which pipeline (A / B / C / D) the agent serves.
   - Which skills it loads, when, and via which of the seven loading
     patterns (see
     [`doc/loading-patterns.md`](doc/loading-patterns.md)).
   - Its own verification gate (what it checks before returning).
4. **Add a row to `agents/README.md`** in the pipeline mapping table.
5. **Extend the orchestrator.** Update `agents/orchestrator.md`
   dispatch table with the new task-to-agent mapping.
6. **Write the instruction.** Add
   `doc/instructions/how-to-use-{name}.md` (short, task-oriented;
   long-form goes elsewhere in `doc/`).
7. **Run the initial check.** Load
   [`skills/skill-framework-fitness/SKILL.md`](skills/skill-framework-fitness/SKILL.md)
   and
   [`skills/skill-security-hygiene/SKILL.md`](skills/skill-security-hygiene/SKILL.md)
   and apply both to the new agent. Framework fitness catches pipeline,
   registration, and chain defects; security hygiene catches secrets,
   PII, and public/internal boundary breaches. Landing is blocked on
   either producing a High or Critical finding.

## Adding a skill

1. **Create `skills/skill-{name}/SKILL.md`** with the standard skill
   frontmatter (`name`, `description`, `metadata`). Description drives
   discovery; be specific about triggers.
2. **Choose the loading pattern** (see the seven patterns in
   [`doc/loading-patterns.md`](doc/loading-patterns.md)).
   Document the choice in the SKILL.md header.
3. **If the skill codifies a rule set**, mark the entries S / R / T so
   agents can cite them.
4. **Add a row to `skills/README.md`** under the pipeline mapping.
5. **Link from every agent that uses it.** Agents declare their skill
   dependencies in their own body.

## Adding a pipeline stage

Pipelines B, C, and D are still being built. To add or refine a stage:

1. **Update the pipeline flow.** Edit `README.md` and
   `agents/orchestrator.md` so the pipeline table reflects the new
   stage.
2. **Add or extend the agent.** Follow "Adding an agent" above.
3. **Write the how-to.** `doc/instructions/how-to-{pipeline-verb}.md`.
4. **Add the doc page.** `doc/{topic}.html`, once the stage is real
   enough to document for external readers.

## Adding an instruction

Instructions live in `doc/instructions/` and are short, task-oriented
Markdown. Convention: filenames start with `how-to-`.

1. **Create `doc/instructions/how-to-{action}.md`.**
2. **State the target pipeline in the opening line.**
3. **Include copy-paste-ready sample prompts** pinned to
   `claude-opus-5-5`.
4. **Cross-link to the S / R / T rules the pipeline enforces.**

## Adding a doc page

Doc pages are long-form reference material for readers who run or
extend the framework; Qt Group renders them as a site internally.

1. **Mirror the internal `qt-doc-agent-guide` shape.** Markdown source
   next to the HTML output, `images/` for referenced media.
2. **Add the page to `doc/README.md`** expected-pages table.
3. **Deploy separately** from qtqa via rsync (see the deploy note in
   `doc/README.md` once the script lands).

## Naming conventions

- **Agents.** `{verb}-{scope}` or `{scope}-{role}`. Existing shapes:
  `qt-doc-reviewer`, `doc-shaper`, `qdoc-warning-fixer`, `orchestrator`.
  Lowercase, hyphenated, no `agent-` prefix.
- **Skills.** `skill-{topic}`. Lowercase, hyphenated, `skill-` prefix
  mandatory. Example: `skill-ai-tells`, `skill-qdoc-output`.
- **Instructions.** `how-to-{action}.md`. Lowercase, hyphenated,
  Markdown.
- **Doc pages.** `{topic}.html` (+ `{topic}-content.md` when the HTML
  is generated from Markdown). Lowercase, hyphenated.
- **Pipelines.** Referenced by letter (A / B / C / D). Names are
  descriptive but the letter is the identifier.
- **Rules.** S1, S2, ...; R1, R2, ...; T1, T2, .... Sequential,
  never renumber after publication.

## Verification requirements before landing

Every added agent runs through the orchestrator's verification gates
(see `agents/orchestrator.md`, "Post-agent verification"). Additionally:

- **All new agent and doc prose:** run through `skill-ai-tells` Tier
  1 + Tier 2 patterns. Zero hits at Tier 1.
- **All new rule entries:** confirm the source citation. R-rules link
  to their S-source; T-rules cite the corpus calibration.
- **Initial check** on any new agent, skill, or doc page:
  [`skill-framework-fitness`](skills/skill-framework-fitness/SKILL.md)
  and
  [`skill-security-hygiene`](skills/skill-security-hygiene/SKILL.md).
  Framework fitness applies the 9-layer methodology adapted for this
  framework; security hygiene catches secrets, PII, and the
  public/internal boundary.

## Scale strategy

As the framework grows past the first handful of agents and skills:

- **Flat directories hold to ~20 entries.** Beyond that, subdivide by
  pipeline (`agents/pipeline_b/`, etc.) rather than by alphabet.
- **Only verified, working artifacts land in the tree.** Planned or
  half-built work lives outside the commit — the subdir READMEs are
  the authoritative "what exists" list.
- **Cross-links use relative paths**, so moves don't break them.
- **Every subdir README opens with a one-line role statement and a
  link back to top-level `README.md` and `CONTRIBUTING.md`.**
