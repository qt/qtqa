---
name: skill-artifact-testing
description: >
  Methodology for testing Claude Code skills and agents ("artifacts") before
  they ship — a 9-layer evaluation that moves a review from "looks fine" to
  "provably works." Load this skill whenever someone wants to review, test,
  validate, or audit a skill or agent (a SKILL.md, an agent definition, or a
  Gerrit change that adds one), asks "is this skill/agent any good?", "does
  this fit the documentation review system?", "will this skill activate correctly?", or wants to
  verify a skill's claims against ground truth. Provides per-layer criteria,
  a prompt library, a one-page checklist, and a fixture template.
metadata:
  version: "1.0.0"
---

# Artifact Testing Methodology

This reference defines how to test a Claude Code **skill** or **agent** (an
*artifact*) before it ships or merges. It is the reference half of the
artifact-testing capability; the **artifact-tester** agent drives the workflow
and loads this skill.

## Core principle

> **Read-throughs find typos; running it against real data finds the lies.**

A skill or agent is a prompt that ships to other people and runs on real work.
Its most dangerous defect is an instruction that *sounds* plausible on a
read-through but is *false* against real input. You only catch those by
executing the artifact and verifying its claims against an independent source
— never against the artifact's own text.

## Skill vs agent — what you are testing

- **Skill** — passive reference (`SKILL.md` + optional references). Tells the
  model *what to know*. Its `description:` frontmatter is its **trigger**: it
  decides *when* the skill auto-loads. A bad trigger means it never fires when
  needed, or fires on unrelated work.
- **Agent** — active worker (an agent definition). Tells the model *what to
  do*: fetch inputs, perform steps, write files, sometimes commit. Agents load
  skills as they work.

A frequent defect is **category error**: a multi-step workflow filed as a
passive skill (or vice versa). Layer 2 catches it.

---

## The 9 layers

Testing is layered; each layer catches a different defect class, and the later
layers are the ones most reviews skip — which is why defects survive.

| # | Layer | Catches | Usually skipped? |
|---|-------|---------|------------------|
| 1 | Define the contract | Vague scope, no success criteria | Yes |
| 2 | Static review | Contradictions, miscounts, style, category error | Partly |
| 3 | System integration | Duplication, fragmentation, orphaning, drift | Almost always |
| 4 | Trigger test | Activates wrongly / never activates | Almost always |
| 5 | Dynamic run (full) | Instructions false in practice | Partly (front half only) |
| 6 | Verification & citation | Wrong results that look right | Often |
| 7 | Edge cases | Fragility, bad failure behavior | Almost always |
| 8 | Baseline comparison | Whether it actually helps | Almost always |
| 9 | Capture as fixture | Regressions on the next revision | Almost always |

A quick "is this any good?" review may stop after Layer 5. Promoting an
artifact to a documentation-review-system standard requires all nine.

---

### Layer 1 — Define the contract first

**What.** Before testing, write the artifact's promise: the task, the exact
activation conditions, and what correct/complete output looks like.

**Why.** Without a contract written in advance, you grade intuitively and
notice only what the artifact does (confirmation bias). A contract written
first is something the artifact can fail against.

**Good looks like.** Three crisp statements (purpose, activation, output spec)
plus 3–5 objective pass/fail criteria.

**Prompts:**

```
Read <TARGET>. Without judging it, state its contract in three parts:
(a) the single task it performs, (b) the exact conditions under which it
should activate or be used, (c) what a correct, complete output looks like.
Then list every place the contract is ambiguous or unstated.
```
```
From <TARGET>, write 3–5 yes/no acceptance criteria a reviewer can check
objectively (e.g. "identifies 100% of new public symbols", "never flags
private/internal symbols").
```

### Layer 2 — Static review (correctness and category)

**What.** Read for internal defects, then check it is the right *kind* of
artifact in the right shape.

**Why.** Two defect classes: *internal* (self-contradiction, miscounts, broken
cross-refs, claims unverifiable from the text) and *category/shape* (a workflow
filed as a skill, broken naming/frontmatter conventions).

**Good looks like.** Each issue quoted with its location; a clear verdict on
category and convention conformance.

**Prompts:**

```
Review <TARGET> for INTERNAL defects only: self-contradictions, miscounts,
broken cross-references, conflicting instructions, and any claim that cannot
be verified from the file itself. Quote each with its line number.
```
```
Is <TARGET> the right CATEGORY — passive reference (skill) vs active workflow
(agent)? Quote the content that proves it. Do its name, location, and
frontmatter match its siblings in <DIR>?
```

### Layer 3 — System integration (the centralization test)

**What.** A skill/agent joins one centralized, coordinated documentation
review system plus a dispatcher. This layer asks: does adding it keep the
documentation review system centralized, or
fragment it?

**Why.** The value of the system is *one* place per capability, *one* source of
truth per rule, *one* dispatcher that knows what exists. Each uncoordinated
addition erodes that:
- **Duplication** — re-implements what a sibling already does → two sources of
  truth that drift.
- **Orphaning** — dropped in the folder but never registered in the dispatcher,
  index, or how-to → nothing knows to use it.
- **Fragmentation** — doesn't compose with siblings (re-derives instead of
  referencing), wrong conventions, or lands in a personal/local location.
- **Drift** — a local copy diverges from the centralized source.

These are invisible when the file is reviewed alone. Hold it against the whole
set and the dispatcher.

**Good looks like.** Adds a capability no sibling provides (or supersedes one
that is then removed); **references** siblings rather than restating them; is
**registered** in dispatcher + index/README + how-to; follows shared
conventions; lives in the single canonical source with no local/central drift.

**Prompts:**

```
Treat <DIR> as the centralized documentation review system plus its dispatcher (<DISPATCHER FILE>).
For <TARGET>, report:
1. CAPABILITY OVERLAP — does any existing skill/agent already do part of what
   <TARGET> does? For each, say reference / replace / merge.
2. COMPOSITION — does it re-state rules a sibling owns? Name the sibling it
   should reference instead.
3. REGISTRATION — is it wired into the dispatcher routing table, index/README,
   and how-to docs? List every place it is MISSING.
4. CONVENTIONS — do name, location, and frontmatter match the set?
5. VERDICT — does adding it keep the set centralized or fragment it?
```
```
Map the documentation review system in <DIR>: every skill/agent with its purpose and the
who-loads-what relationships. Place <TARGET> on the map: what it loads, what
loads it, and any duplicated capability or orphaned node.
```
```
SOURCE-OF-TRUTH drift: compare the canonical copy (<CANONICAL PATH>) against
the local install (<LOCAL PATH>) for <TARGET> and its dependencies. Report
content/version differences and what must be synced.
```

### Layer 4 — Trigger / activation test

**What.** Test whether the artifact fires at the right time — and is reached by
the right caller. In the documentation review system a skill is usually
**loaded by an agent** (or routed to that agent by the dispatcher), not just
auto-activated by its `description:` frontmatter. Check both: the trigger and
the loading path.

**Why.** A skill that never activates is dead code; one that over-activates is
noise; one no agent loads is unreachable. The trigger is half the contract and
is almost never tested. Near-misses (same domain, out of scope) are where
triggers fail.

**Good looks like.** Fires on every on-target prompt, silent on every
off-target one, near-misses explainable either way.

**Prompt:**

```
Here is the description frontmatter of a skill:
--- <PASTE description only> ---
For each prompt below answer YES (should activate) or NO, using ONLY the
description. Flag any where it is ambiguous or would decide wrongly.
ON-TARGET (should fire): <3 prompts using/paraphrasing its triggers>
NEAR-MISS (judgment calls): <3 adjacent-but-out-of-scope prompts>
OFF-TARGET (should not fire): <3 unrelated prompts>
Then propose 3 prompts its wording would wrongly MISS and 3 it would wrongly
CATCH, and suggest a tightened description.
```

### Layer 5 — Dynamic run on real input (the whole thing)

**What.** Run the workflow end-to-end on a **real patch or source file** from
its domain — **including phases that write files or commit** — in a scratch
copy, showing diffs instead of applying.

**Why.** This exposes instructions that sound correct but are false. A common
shortcut runs only the safe, early phases and skips the ones that *do*
something — which are exactly the ones that can cause damage.

**Good looks like.** Every phase executed; a phase-by-phase note of where the
instructions matched reality and where they didn't; edits shown, not applied.

**Prompt:**

```
Use <TARGET> to perform its full workflow on <INPUT>. Execute EVERY phase,
including any that write files or create commits — but make changes in a
scratch copy and SHOW diffs/commit messages instead of applying. After each
phase, state in one line whether the instructions matched what you actually
encountered. Choose <INPUT> to exercise each distinct case the artifact claims
to handle.
```

### Layer 6 — Verification & citation

**What.** For every factual claim the run produces, check it against an
**independent** source — rendered output, the live system, the source file —
not the artifact's own description.

**Why.** A confident wrong answer is the most dangerous output; it passes a
glance. Verifying against reality grades the artifact *and* tends to surface
real bugs in the work itself. If a source cannot be reached, mark the claim
**UNVERIFIED** — never assume.

**Good looks like.** Each claim labeled CONFIRMED / REFUTED / UNVERIFIED with
the independent source quoted.

**Prompt:**

```
Take the run's output and verify each factual claim against an INDEPENDENT
source (rendered output, live page, source file) — NOT <TARGET>'s own text.
For each: CONFIRMED / REFUTED / UNVERIFIED, with the source quoted. Record
separately any real bugs in the WORK ITSELF that the run surfaced.
```

Notes on common verification traps:
- **Numeric self-claims** (lengths, counts, versions) — measure them; do not
  trust the prose.
- **Exact source line citations** (`file.cpp:81-82`) drift across refactors —
  re-measure and prefer citing symbols/functions over line numbers.
- **JS-rendered pages** may not fetch — mark UNVERIFIED rather than assume.

### Layer 7 — Edge cases

**What.** Run it on the inputs it would rather not see: empty, out-of-scope,
malformed, oversized, or containing only what it should ignore.

**Why.** "Notable" examples prove only the happy path. The question is whether
the artifact fails *gracefully* (clear no-op/message) or *wrongly* (invents
work, produces confident garbage).

**Good looks like.** Sensible explicit behavior on every edge input.

**Prompt:**

```
Run <TARGET> against: (a) an empty/no-op input, (b) input with ONLY items it
should ignore, (c) input missing the files/sections it expects,
(d) malformed/truncated input, (e) input just outside its stated scope.
Report each as graceful / wrong / broken. Then try to make it produce a
confidently wrong result and describe what broke it.
```

### Layer 8 — Baseline comparison

**What.** Perform the same task on the same input **without** the artifact,
then **with** it, and diff.

**Why.** The justification for a skill is that it improves on the unaided
model. Same output with and without → ceremony. Worse output → negative value.
Value = (with) − (without).

**Good looks like.** Each difference attributed to the artifact, with a verdict:
adds value / adds noise / no effect.

**Prompt:**

```
Perform <TASK> on <INPUT> WITHOUT loading <TARGET>; save the output. Repeat
WITH <TARGET> loaded. Diff the two. Attribute each difference to the artifact
and label it improvement / noise / neutral. End with a one-line verdict on
whether it earns its place.
```

### Layer 9 — Capture as a re-runnable fixture

**What.** Save the inputs used and the findings expected, so the next revision
can be re-tested identically.

**Why.** A test that lives only in a transcript can't catch a regression. A
fixture turns "tested once" into "re-testable on every change."

**Prompt:**

```
Produce a fixture from this session: the exact inputs (with stable references),
the expected findings for each, the acceptance criteria from Layer 1, and a
short re-run instruction. Anchor re-runs by claim text, not line numbers, so
they survive edits.
```

---

## One-page checklist

```
CONTRACT
[ ] Purpose, activation, output spec written BEFORE testing
[ ] 3–5 objective pass/fail criteria defined
STATIC
[ ] No contradictions, miscounts, broken refs, unverifiable claims
[ ] Correct category (skill vs agent); conventions match siblings
SYSTEM INTEGRATION (centralization)
[ ] No capability overlap with a sibling (or it replaces one)
[ ] Composes: references siblings instead of restating what they own
[ ] Registered in dispatcher + index/README + how-to
[ ] Single canonical source; no local-vs-central drift
TRIGGER
[ ] Fires on all on-target prompts; silent on all off-target
[ ] Near-miss prompts explained either way
DYNAMIC
[ ] Full workflow run on real input — EVERY phase, incl. write/commit (sandboxed)
[ ] Each distinct case the artifact claims to handle was exercised
VERIFICATION
[ ] Every output claim CONFIRMED / REFUTED / UNVERIFIED vs an independent source
[ ] Numeric claims measured; line-number citations re-checked
EDGE CASES
[ ] Empty / ignore-only / missing / malformed / out-of-scope tried
[ ] Failure behavior graceful, not confidently wrong
BASELINE
[ ] Same task run WITHOUT vs WITH; verdict: value / noise / neutral
CAPTURE
[ ] Inputs + expected findings saved as a re-runnable fixture
```

## Fixture template

```markdown
# Fixture: <artifact name>
Artifact under test: <path>
Tested revision: <commit / version>
Date: <YYYY-MM-DD>

## Inputs
| ID | Stable reference | Why chosen (branch/case it exercises) |
|----|------------------|----------------------------------------|

## Expected findings
| Input | Expected outcome |
|-------|------------------|

## Acceptance criteria (Layer 1)
- [ ] <objective pass/fail>

## Re-run instruction
<one paragraph; anchor by claim text, not line numbers>

## Baseline note
With-vs-without verdict: <value / noise / neutral>
```

## Worked examples (defect classes this finds)

- **Wrong illustrative content** — a column-counting skill whose own examples
  asserted "exactly 80 characters" on lines that measured 75/90; found by
  Layer 6 numeric measurement, invisible to a read-through.
- **Stale coordinates + triplicated rule** — a skill citing `config.cpp:81-82`
  (actually 83–84) and `docparser.cpp:1784-1788` (actually ~1813–1830), with
  its alt-text wrapping rule duplicated across three skills; found by Layer 6
  and Layer 3.
- **Category error + fragmentation** — a multi-phase workflow filed as a
  passive skill, duplicating the dispatcher's fetch protocol, restating rules
  other skills own, and unwired from the dispatcher; found by Layers 2 and 3.

In every case the headline defect came from Layers 6 and 3 — verification
against ground truth, and system integration — the two layers most reviews skip.
```
