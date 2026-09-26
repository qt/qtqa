# Registers (G23-G30)

Back to [`skill-g-rules`](../SKILL.md). Load this at the register check
(skill-c-rules step 4), once per page, after the G1-G22 pass.

Source: the Qt Doc Team Language Guide, *Understanding register* (sections
on the registers Qt documentation uses, the elements that shape register,
and register and document type). The guide is internal; the rules below
restate what the framework needs, so no link is required. Its essay-edition
companion is not a rule source.
These rules have no parent R rule. Each content type (see `skill-c-rules`)
expects one register. G23-G25 and G28-G29 say which types use a register
and how it sounds. G26, G27, and G30 are registers that belong to other
Qt channels (the Qt Blog, qt.io, the Qt Forum). Each has three scopes:
**Expected** (not a finding), **Limited** (allowed within the stated
limit; report only what exceeds it), and **Finding**. Report a finding as: the expected register, the register
found, and the sentence where the text drifts.

**Dials.** Each register's settings (person, tense, mood, tone,
structure, sentence length, analogies, asides, "we", contractions) are
variables in [`register-dials.toml`](register-dials.toml). The rule text
below describes the register; the values come from the dials file, and a
content type can override them there. Tune a value in the dials file, not
in this prose. Tool dials are checked by
`tools/register-dials/check_dials.py --type C<n> FILE`; the LLM applies
the rest.

Boundaries with other rules:
- Briefs follow G3, G9, and G10; section titles follow G12. The register
  rules cover body text.
- Tools check the single words: R4 (future tense), R2 and R38 (fillers
  and hedges such as "basically" and "simply"), T13 and T18 (superlatives).
  The register rules judge the page as a whole. Don't report the same
  word twice.
- G1 (passive) and G4 ("you") still apply inside each register.

### Microsoft baseline (S9) and register overrides
S9 applies wherever Qt sources are silent (source precedence in
`skill-language-style`). A register can discourage an S9 default. When a
cell below says so, the register wins, and the cell is a directive:
follow it and don't report the S9 default as missing.

| S9 default | G23 Reference | G24 Tutorial | G25 Conceptual | G28 Legal | G29 Release notes |
|------------|---------------|--------------|----------------|-----------|-------------------|
| Second person, "you" | **Directive:** third person for API behavior; "you" only for reader actions and choices (G4 test) | Follow S9 | Follow S9 (G4 test) | **Directive:** keep the license's own terms ("Licensee") | **Directive:** no pronouns; start with the verb |
| Omit "you can" when not needed | Follow S9 | Follow S9 | Follow S9 | n/a | n/a |
| Avoid "we"; "we recommend" sparingly, write around it | Follow S9 | Follow S9; inclusive "we" in existing walkthroughs is not a finding, new text uses "you" | Follow S9 | Follow S9 | **Directive:** no "we" |
| No first person singular ("I", "my") | Follow S9 | Follow S9 | Follow S9 | Follow S9 | Follow S9 |
| Common contractions allowed; never noun + verb ("Qt's moving") | **Directive:** allowed, but don't add them to reference text; T19 density above ~2 per 1,000 words is a signal | Follow S9 | Follow S9 | **Directive:** no contractions | **Directive:** no contractions |

G26, G27, and G30 are not doc.qt.io registers, so no row applies to them.

### G23. Reference register (C1, C2; C9 and C12 reference pages)
Dials: `[registers.reference]` in `register-dials.toml`.
Look up one fact fast. Third person, present tense, indicative, one fact
per sentence. No teaching, no steps. "You" only in usage notes about the
reader's code (G4 test).
- ❌ (C1) Now let's add a few items and watch the list grow.
- ✅ (C1) Appends \a value to the list.

### G24. Tutorial register (C5, C7, C9; C4 walkthroughs, C8 porting steps, C12 usage)
Dials: `[registers.tutorial]` in `register-dials.toml`.
Walk the reader through steps. "You", imperative steps, in order. Prefer
stating the result over reassurance ("don't worry", "you should see"):
it's shorter and in the present tense. A preference, not a finding.
- ❌ (C5) Don't worry, you should see a window appear.
- ✅ (C5) Run the application. A window opens.

### G25. Conceptual register (C3, C4 descriptions, C6; C7 and C8 explanations)
Build a mental model: what something is, why it exists, and when to use
it. Dials (`[registers.conceptual]`):
- **Person** (`person`): third person, or "you" when the reader makes a
  choice, following the G4 test ("Use X when you need...").
- **Tense and mood** (`tense`, `mood`): present tense; states things
  rather than giving commands.
- **Tone** (`tone`, `sentence_words_target`, `sentence_words_max`): calm
  and factual. Sentences can be a little longer than in reference text,
  but aim for about 20 words.
- **Structure** (`structure`): each paragraph opens with a plain topic
  sentence. Sections go from what, to why, to how.
- **Analogies** (`analogies_max`): at most one, as support, never as the
  definition.

Don't list API facts (`api_facts_allowed = false`: link to the reference
page) or give steps (`steps_allowed = false`: link to the tutorial).
- ❌ (C6) The `connect()` function takes five parameters: ...
- ✅ (C6) Signals and slots let objects communicate without knowing
  which objects receive the signal.

### G26. Essay register
Dials: `[registers.essay]` in `register-dials.toml`.
Persuasion: "X, not Y" contrasts, aphorisms, rhetorical questions, drama
framing ("the paradox", "the catch"), one-sentence paragraphs for punch.
Overlaps T6 and T17; the register rule covers the argument as a whole.
- **Expected:** Qt Blog (C13), design rationale such as QUIPs.
- **Limited:** "why" sections in C6: at most one contrast, no aphorisms.
- **Finding:** C1, C2, C3, C4, C5, C7, C8, C9, C12.
- ❌ The copy is not an inconvenience; it is the whole point.
- ✅ A queued connection copies its arguments because the slot runs
  later, on another thread.

### G27. Marketing register
Dials: `[registers.marketing]` in `register-dials.toml`.
Selling: leads with benefits, superlatives, exclamation, fragments.
Words overlap T13 and T18.
- **Expected:** qt.io product pages (C14), launch posts.
- **Limited:** C3 module pages and C8 What's New pages: one or two
  introductory sentences that state facts, with no T13 or T18 words.
  This allowance is house practice; no S-source covers it.
- **Finding:** C1, C2, C4, C5, C6, C7, C9, C12, and C3/C8 beyond the
  introduction.
- ❌ Build stunning apps faster than ever, with one codebase for every screen.
- ✅ Qt Quick applications run on desktop, mobile, and embedded platforms.

### G28. Legal register (C11)
Dials: `[registers.legal]` in `register-dials.toml`.
Defines obligations. "Shall" and "must" are allowed. Report issues in
Qt-authored `\legalese` notices only. Never rewrite third-party license
text; report it to the user instead. The license and year check is a
C11 tool gap, not part of this rule.

### G29. Release-notes register (C8 change lists)
Dials: `[registers.release_notes]` in `register-dials.toml`.
Records what changed. Past tense, starts with the verb, one change per
item. Applies to change lists only. C8 porting prose uses G24 (steps) or
G25 (explanation). R4 exemption: planned removals ("will be removed in
Qt 7").
- ❌ `\li` We've gone ahead and removed the old API.
- ✅ `\li` Removed QFoo::oldValue(). Use QFoo::value() instead.

### G30. Conversational register
Dials: `[registers.conversational]` in `register-dials.toml`.
Chat: filler, loose grammar, first person singular ("I").
- **Expected:** Qt Forum (C15), chat, code review comments.
- **Limited:** "we recommend", sparingly, when writing around it is
  awkward (S9). Common contractions (S9). Inclusive "we" in existing C4
  and C5 walkthroughs (new text uses "you").
- **Finding:** everything else in C1-C9 and C12.

Contractions alone are not a finding. T19 measures density: above about 2
per 1,000 words, check the page for essay or conversational register.

**Sentence-initial "So".** Filler "So" or "So," at the start of a
sentence is a conversational marker (Qt Doc Team Language Guide, *Understanding register*: "so",
"basically", "yeah"). No S-source or R-rule covers "so". Candidates come
from a regex [tool]: `(^|[.!?] )So,? `. The LLM decides [LLM]: filler
is a finding; a real result is not ("So the view redraws." after a
cause can stay, but "Because..." or a comma join usually reads better).
Flag in new text only: Qt docs use it 0.04 times per 1,000 words (166
in 4.03M words, cc-ph2, 2026-09-26). Result ", so" (1,303), "so that"
(863), and "and so on" (264) are normal Qt prose and not findings.
- ❌ So, to use the model, set it on the view.
- ✅ To use the model, set it on the view.
- ❌ So basically that method's deprecated now, we'd just use the new one.
- ✅ This function is deprecated. Use value() instead.
