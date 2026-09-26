---
name: skill-ai-tells
description: >
  The Qt Doc Team AI-Tell Catalogue (T1-T19) as an operational check: writing
  habits that mark prose as padded, generic, or machine-made. Load this skill
  before writing or reviewing any prose that ships: documentation bodies,
  suggested replacement text in a review, commit messages bound for Gerrit,
  generated reports, and chat prose. Also load it when asked "does this read
  like AI wrote it?", when auditing added rule prose in a skill or agent
  definition, or when deciding whether a flagged tell should be rewritten or
  kept. Every pattern here is calibrated against 2.4M words of Qt reference
  documentation, so each tell carries a measured false-positive risk and a
  tier that says whether a single hit is a finding. The Scope section declares
  which tells apply to which artifact and document type; Portability covers
  use on other Qt Group products and outside Qt.
metadata:
  version: "2.2.0"
  calibration: "Qt corpus scan 2026-08-05"
  loading: "Tier 1 patterns run as a tool (tools/doc-diff/verify_after.py, tools/check-artifact); load this file by GATE at the step that judges Tier 2 tells or confirms a Tier 1 hit"
  ported-from: "Doc Team skill set (not in documentation_review), skill-ai-tells 2.1.0"
  fitness: "2026-09-28; framework-fitness layers 1-4, 6, 7 (5, 8, 9 need an agent run); security-hygiene PASS; open findings in the phase2 session log 2026-09-27, Entry 8"
---

# AI-Tell Catalogue (T1-T19)

A **tell** is a writing habit that reveals who, or what, wrote the text. None
is wrong on its own. When they cluster, prose reads as padded, generic, or
machine-made, which fights the direct voice Qt reference documentation aims
for.

Long-form rationale per tell, with worked examples, and the dash rationale
and corpus argument are in the Doc Team's local language-guide reports (not
published with the framework).

## What changed in v2

Every pattern was measured against the Qt corpus. Four tells turned out to
flag Qt's own house habits and were demoted, one was anti-correlated and was
dropped, three new tells were verified, and T1 was rebuilt around the mark and
its position. Details in "Calibration" below.

v2.1 adds two declarations: **Scope**, which says which tells apply to which
artifact and document type, and **Portability**, which says what survives a
move to another product or another corpus.

## Two operating principles

**1. Signals, not proof.** A grep match is a prompt to look, not a reason to
rewrite. The tier tells you how much weight a single hit carries.

**2. Rewrite; do not delete.** A detected tell requires an attempted rewrite.
Deleting the sentence removes the information along with the tell.

> **The test:** does the sentence state a fact? If yes, rewrite it plainly.
> Delete only if it says nothing.

## Calibration corpus

| Corpus | Contents | Size |
|--------|----------|------|
| **A** Qt reference docs | 1,404 `.qdoc` + 2,021 source files with doc comments, across qtbase, qtdeclarative, qtdoc, qtquick3d, qtmultimedia, qttools | 278,083 prose lines / 2,393,908 words |
| **B** machine-written | 5 generated reports, same domain (essay-register guide + 4 workflow reports) | 7,283 words |
| **C** house-rewritten | the same guides after rewrite to Qt register | 5,076 words |

Corpus A excludes `\code`, `\badcode`, `\qml`, `\snippet`, `\raw`, and
`\table` blocks, SPDX headers, and command-only lines. Rates below are hits
per 1,000 words unless marked otherwise. **A is the false-positive estimate:**
a pattern common in A will fire on good Qt prose.

Scripts, raw results, and method notes are kept locally by the Doc Team
(`extract_qt_prose.py`, `compare.py`, `measure.py`), not in the framework.
Re-run them after any Qt corpus refresh.

## Tiers

| Tier | Meaning | Disposition |
|------|---------|-------------|
| **1** | Near-absent in Qt prose (A ≤ 0.05/1k). High precision. | One hit is worth a look. Two is a finding. |
| **2** | Present in Qt prose but concentrated in machine text. | Density only. Never a finding on one instance. |
| **3** | As common in Qt prose as in machine text. **Not evidence of anything.** | Style cleanup under the R-rule, never labeled an AI tell. |

## The catalogue

### Tier 1: high precision

| # | Tell | A/1k | B/1k | Pattern or method |
|---|------|------|------|-------------------|
| T1a | Em-dash aside, **paired** | 0.00 | 0.82 | `grep -nE ' —[^—]*— '` (1 instance in all of corpus A) |
| T6 | Symmetric framing | 0.03 | 0.00 | `grep -niE 'not only\|on the other hand\|on one hand'` |
| T7 | Wrap-up scaffolding | 0.02 | 0.00 | `grep -niwE 'in conclusion\|overall\|ultimately\|in summary\|to sum up'` |
| T13 | Hollow superlative, **core set** | 0.00 | n/a | `grep -niwE 'cutting-edge\|state-of-the-art\|world-class\|next-generation\|pivotal\|holistic'` |
| T14 | False balance | 0.01 | 0.00 | `grep -niE 'it depends\|both have\|some (developers\|users).*others'` |
| T16 | **Personification** (new) | 0.00 | 0.27 | `grep -niE '\b(page\|class\|function\|api\|method\|code\|type\|module\|docs\|widget\|reader)s? (speaks\|hears\|knows\|wants\|understands\|cares\|thinks\|remembers\|decides\|lives\|sits\|feels\|asks)\b'` |
| T17 | **Antithesis** (new) | 0.00 | 0.27 | `grep -niE "(is\|are) not [^.]{2,40}\. *(It\|They\|That) (is\|are)\|(isn't\|aren't)[^.]{0,45}(it's\|they're)"` |
| T18 | **Absent lexicon** (new) | 0.00 | n/a | `grep -niwE 'delve\|delves\|plethora\|tapestry\|testament\|nuanced\|elevate\|empower\|intricate\|effortless\|effortlessly\|boasts\|synergy\|undoubtedly'` |

T18's word list is defined by measurement: every entry has **zero** hits in
2,393,908 words of Qt reference prose. Add a word only after confirming it
scores zero; that is the whole basis for the tier.

### Tier 2: density only

| # | Tell | A/1k | B/1k | Method |
|---|------|------|------|--------|
| T1b | Em-dash, **terminal** (single, elaborating) | 0.03 | 11.95 | See "The dash decision" |
| T5 | Rule-of-three triads | 0.49* | 1.78* | read; *proxy pattern `X, Y, and Z` |
| T8 | Intensifier, **strong set** | 0.01 | n/a | `grep -niwE 'extremely\|incredibly\|remarkably\|tremendously'` |
| T11 | Uniform rhythm | n/a | n/a | read |
| T13 | Superlative, **soft set** | 0.03 | 0.14 | `powerful` (46 hits in A), `comprehensive` (31); check, do not auto-flag |
| T15 | Asyndetic coordination | 0.55* | 0.96* | read; the proxy separates the corpora by only 1.7x |
| T19 | **Contraction density** (new) | 0.94 | 5.77 | `grep -cniwE "isn't\|aren't\|doesn't\|don't\|won't\|can't\|it's\|you'll\|we'll\|that's\|there's\|here's"`: a register meter, not a per-instance error. Above ~2/1k words the page is in essay register. Corpus C, after the house rewrite, sits at 0.39 |
| T10 | Restatement of the heading | n/a | n/a | read the first sentence after each heading |

### Tier 3: not tells

These fire on Qt's own prose at the same rate as on machine prose. Treat each
as a style question under its R-rule and **do not cite it as a sign of
generated text**.

| # | Former tell | A/1k | B/1k | What to do instead |
|---|-------------|------|------|--------------------|
| T3 | Hedge words | 0.86 | 0.82 | R2. Flag only a *stack*: two or more hedges in one clause. The single-word grep has no discriminative value |
| T4 | "note that" and friends | 0.55 | 0.00 | R2 filler cleanup. **This is a Qt house habit**: 1,305 instances in corpus A. Promote real caveats to `\note` because it renders better, not because the phrase is a tell |
| T9 | Passive "…ed by" | 1.29 | 0.27 | R1, and Vale's `Microsoft.Passive`. Qt prose is *more* passive than the machine prose measured. Anti-correlated: dropped from the scan |
| T12 | Over-signposting | 0.14 | 0.14 | R2, on short procedures only |

### Rejected candidates

Measured, and rejected with evidence. Do not re-propose without new data.

| Candidate | Why rejected |
|-----------|--------------|
| Formal connectives (furthermore, moreover, additionally, consequently) | Qt uses them: 86, 31, 161, 24 hits in corpus A |
| Rhetorical question headings | Qt has 238 question headings |
| Vague quantifiers ("a handful of", "a number of") | A 0.09/1k vs B 0.00, the wrong direction |
| "think of X as" | Zero in both corpora |
| Hypothetical-reader narrative | Rare in both |

## The dash decision (T1)

The strongest single finding in the corpus, and the one method change that
matters most.

**What Qt does.** In 2,393,908 words: 85 lines with a spaced literal em dash
(0.04/1k), and **one** line anywhere in the corpus with a paired, bracketing
pair. Meanwhile Qt introduces things with a colon 7,139 times, uses a
parenthetical 10,756 times, and uses `\note` 3,859 times. The house already
made this choice.

**The mark is the signal, not the dash.** Qt's legacy prose uses ` -- `
(106 lines), including CLI text such as `git checkout -- file`. Machine prose
uses U+2014. **Match only the literal em dash.** Matching `--` flags Qt's own
legacy convention and command-line examples, which is why v1's pattern was
wrong.

**The em dash is new to the corpus.** A blame sample of 14 em-dash lines
returned last-touched dates from 2025-08 to 2026-05, all within twelve months.
A control sample of 16 random prose lines spread from 2011 to 2025, with 3 in
the last year. Blame reports last touch rather than introduction, and this
does not establish who or what wrote those lines. It does establish that the
mark is a recent arrival in a corpus that is decades old.

**Reviewers: classify by position, not by presence.**

| Class | Shape | Corpus A | Disposition |
|-------|-------|----------|-------------|
| **Paired** | `… — aside — …` | 1 instance | **Tier 1.** Always flag. Rewrite as a comma clause, a separate sentence, or a `\note` |
| **Terminal** | `… clause — elaboration.` | 83 lines | **Tier 2.** Not an aside; it is a colon substitute. Suggest the colon or a period. Flag a page with more than two |
| **Label** | `\li \b{Term} — text` | 14 (vs 56 with a colon) | Legitimate, but Qt prefers the colon 4:1. Suggest the colon; flag only if the page mixes both (R8) |
| **ASCII** | ` -- ` | 106 lines | Legacy Qt style or CLI text. **Never a tell.** Leave it alone unless the page is inconsistent |

```
grep -nE ' —[^—]*— '   # paired: Tier 1, always flag
grep -nE ' — '         # all literal em dashes, then classify by position
```

**Writers: pick the mark for the relationship.** Corpus counts in brackets.

| Relationship | Mark | Qt usage |
|--------------|------|----------|
| Introduces a list, definition, or label | colon | 7,139 |
| Truly optional aside | parentheses | 10,756 |
| Two facts | period, two sentences | the default |
| A caveat the reader must not miss | `\note` / `\warning` | 3,859 |
| Interruption mid-sentence | none of the above; promote or cut | 1 |

The style-side rule is **R68** in [skill-r-rules](../skill-r-rules/SKILL.md) (the dash check), with
the replacement punctuation in G22 of [skill-g-rules](../skill-g-rules/SKILL.md), which closes the open
recommendation On asides recorded.

## Scope: which tells apply, and where

Two axes decide applicability: **what kind of text it is**, and **who wrote
it**. Check both before reporting anything. A tell that is real in a commit
message can be house style in a `\li` label.

### Axis 1: Qt documentation type

Corpus A was split three ways and re-measured. Rates per 1,000 words:

| Context | Words | Em dash | Contractions | T13 soft | T5 triad | "you" |
|---------|-------|---------|--------------|----------|----------|-------|
| API reference (doc comments) | 1,695,733 | 0.03 | 0.87 | 0.01 | 0.36 | 2.56 |
| Overview pages (`.qdoc`) | 602,397 | 0.04 | 1.10 | 0.10 | 0.78 | 5.44 |
| Tutorials and examples | 95,778 | 0.04 | 0.98 | 0.41* | 1.10 | 3.80 |

\* tutorial T13 rate is 0.03; the 0.41 column above is T3 hedges, which
tutorials use least.

**Use the same thresholds for all three.** This corrects a reasonable
assumption: On asides proposed a looser aside budget for tutorials, and the
corpus does not support it. Qt tutorials use the em dash at the same
near-zero rate as API reference. Three real variations:

| What varies | Reference | Overview | How to apply |
|-------------|-----------|----------|--------------|
| T13 soft (`powerful`, `comprehensive`) | 0.01 | 0.10 | Flag in a `\brief` or API body. In an overview page it is 10x more normal, so check context first |
| T5 triads | 0.36 | 0.78, tutorials 1.10 | Loosen with register. A tutorial triad is usually pacing, not padding |
| Second person | 2.56 | 5.44 | **Not a tell.** R6 governs it. Do not treat "you" density as a register signal |

### Axis 2: artifact

Corpus A gives no baseline outside Qt documentation, so these rows are policy,
not measurement. Marked accordingly.

| Artifact | Tiers that apply | Notes |
|----------|------------------|-------|
| Qt doc patch under review | 1 and 2, per the tier table | Tier 3 never reported. R68 governs dashes |
| Your generated documentation | all, zero tolerance | Nothing upstream filters it |
| Your suggested fix text in a review | all, zero tolerance | Step 8 gate |
| Commit message for Gerrit | all, zero tolerance | Watch **T7** (the crafted closing line), **T15**, and **T4**. Remember the rewrite rule: a deleted line loses the fact with the tell |
| Generated report or HTML | all, zero tolerance | **T19** matters most; essay register creeps into reports |
| Skill or agent markdown | 1 and 2, with one carve-out | The label dash (`**Term** — text`) is the established convention in these files and is consistent, so it stays under R8. Terminal and paired dashes still get fixed |
| Chat prose | 1 and 2 | Weakest surface. **T1** and **T6** first |

### Where no tell applies

Inside any artifact, these are out of scope entirely:

- `\code`, `\badcode`, `\snippet`, `\printto`, and `\raw` blocks
- Signatures, parameter tables, and `\value` lists, apart from T13 and T18
  wording inside a description
- Verbatim quoted text, including a rule that names the tell word
- Table cells holding a null placeholder
- License and legal pages, and `\whatsnew` lists. Corpus evidence: the two
  "comprehensive" hits that look worst are "a comprehensive list of all new
  classes" and "a comprehensive trade embargo", both correct usage

### Order of checks

1. Identify the artifact and, for Qt docs, the document type.
2. Drop everything in "Where no tell applies".
3. Run Tier 1, then Tier 2. Never report Tier 3 as a tell.
4. Apply the authorship rule below: someone else's prose gets thresholds,
   yours gets none.

## Portability: other products, and outside Qt

**The method travels. The numbers do not.** Every rate, tier, and word list
here describes one corpus: Qt reference documentation. Applied to a corpus
with different habits, the tiers misfire in both directions.

| Transfers unchanged | Must be re-derived per corpus |
|---------------------|-------------------------------|
| The tier method: measure the target corpus first, treat its rate as the false-positive estimate | Every rate and threshold in this file |
| Rewrite-not-delete, and the "does it state a fact?" test | T18's word list, which is *defined* as zero hits in Qt prose |
| The dash position taxonomy: paired, terminal, label, legacy | The 4:1 colon-over-label-dash preference, and the ` -- ` legacy finding, both Qt-specific |
| T16 personification and T17 antithesis as structures | R-rule citations (R1, R2, R68) and QDoc mechanics (`\note` promotion, `\li` labels, `\brief`) |
| Rejecting candidates on evidence, and recording why | Which candidates get rejected |

**Other Qt Group products.** Qt Creator, Qt Design Studio, and the tools
documentation share QDoc and the style guide, so the catalogue applies, but
their register is not the reference register: R42-R44 territory, more second
person, more UI strings. Do not inherit these thresholds. The split
measurement above already shows T13-soft varying 10x between reference and
overview pages *inside* one corpus, so a product boundary will move more.
Re-run the scripts against that product's docs and rebuild the tiers.

**Non-Qt and third-party use.** Supported, with three conditions:

1. **Recalibrate.** A house style that legitimately uses em dashes turns T1
   into noise. Point `extract_qt_prose.py` at the target corpus, run
   `compare.py`, then rebuild the tiers by the same two rules: Tier 1 is
   ≤ 0.05 hits per 1,000 words in the target corpus; Tier 3 is anything whose
   target-corpus rate matches its machine-prose rate.
2. **Remap or drop the R-rule column.** The T-number is a diagnostic; the
   authority has to be that product's style guide.
3. **Check the register.** These tells assume a reference or technical
   register. On a marketing page, T13 superlatives are the genre, not a
   defect. Do not run the catalogue on copy that is meant to sell.

**Licensing.** The framework copy carries
`LicenseRef-Qt-Commercial OR BSD-3-Clause` (see the framework `REUSE.toml`),
so this skill can be shared and reused outside the team under BSD-3. The
calibration data is local and unpublished: cite numbers by re-running the
scripts, not by pointing at a local path.

## Applying the tiers

**Reviewing prose someone else wrote:**

| Observation | Disposition |
|-------------|-------------|
| One Tier 1 hit | Notes, with the rewrite offered |
| Two Tier 1 hits, or one that is idiomatic-free and clear | Suggestion |
| Tier 2, single instance | Silent |
| Tier 2, two or more of the same tell | Suggestion |
| Three or more different tells in one paragraph | Suggestion, cite the cluster |
| Tier 3 anything | Cite the R-rule only. Never say "AI tell" |

**Text you wrote yourself:** no threshold. Every Tier 1 and Tier 2 hit gets a
rewrite before the text leaves your hands. This covers generated
documentation, suggested replacement text in a review, commit messages,
reports, and chat prose.

## Citing a tell

The R-rule is the authority; the T-number is the diagnostic:

```
Category: Language (R2) — AI tell T17 (antithesis)
```

## Scan exclusions

`\code`, `\badcode`, `\snippet`, `\printto`, and `\raw` blocks; verbatim
quoted rule text; any line that names the tell word as a word to avoid; and
CLI text containing `--`. Word-list tells fire constantly in style-guidance
prose for exactly this reason.

One more, found while scanning this file: a **table row using `—` as a null
placeholder** (`| T11 | n/a | n/a |`) trips the paired-dash pattern. Two
placeholder cells look like a bracketed aside. Write `n/a` instead, and skip
table rows whose only dashes sit alone in a cell.

**Verify patterns before shipping them.** The shell `grep` on this machine is
shimmed to `ugrep`, which accepts syntax POSIX ERE rejects. Test against
`/usr/bin/grep -E`.

## Legitimate keeps

- **Verbatim quoted rule text.** A T6 "never a subset" added *as a rule* is
  the rule's wording, not the author's habit.
- **Content-set counts.** A triad is fine when three is the real number.
- **Genuine caveats.** `\note` and `\warning` are not T4 filler.
- **Label dashes in an established page.** Qt prefers the colon, but a page
  that uses the label dash consistently is following R8.
- **Real trade-offs with a stated criterion.** "Use X when…, use Y when…" is
  guidance, not T14.

## Known weak spots

Chat prose runs worse than commit messages on T1 (em-dash asides) and T6
(symmetric framing). Check those first in conversational output.

Style-adjacent text carries the highest visibility cost: a tell inside a
writing rule discredits the rule.

## Where this is wired in

| Consumer | Use |
|----------|-----|
| `qt-persona-reviewer` | Step 7, check own prose |
| `qt-doc-reviewer` (port proposed) | Tiered pass on the patch; GATE on proposed After text after the Tier 1 tool pass |
| `tools/doc-diff/verify_after.py`, `tools/check-artifact` | Tier 1 patterns as code |
| `skill-r-rules` R68, `skill-g-rules` G22 | Dash choice, the style-side half of T1 |
| Orchestrator (direct work) | Commit messages, reports, and chat prose |

Vale rules for the Tier 1 patterns are proposed but not built; the Python
copies in `tools/` run until they are.
