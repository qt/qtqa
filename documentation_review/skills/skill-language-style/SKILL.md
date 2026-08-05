---
name: skill-language-style
description: Language, grammar, and style guidelines for Qt documentation including active voice, terminology, QUIP 25 standards, and proper API documentation patterns. Covers both WHAT to write (style/content) and HOW to write it (QDoc syntax).
metadata:
  version: "4.0"
---

# Qt Language and Style Guidelines

**Version**: 4.0
**Purpose**: Reference for language, grammar, and style standards when writing or reviewing Qt documentation
**Scope**: Applies to all Qt documentation (QDoc comments, user guides, tutorials, API docs, examples)

---

## Overview

Language and style guidelines for Qt documentation, consolidating rules from
Qt Writing Guidelines (S1), QUIP 25 (S2), C++/QML Documentation Style
(S3/S4), and Microsoft Style Guide (S9). QDoc Manual (S10) covers command
syntax.

**Source precedence:** S1 > S2 > S3/S4 > S5/S6 > S9 (supplementary only).
**Full source details:** See `references/sources.md`.

---

## Verification Workflow (Generic)

When reviewing documentation and encountering questions about correctness
(terminology, style, patterns, syntax), follow this workflow:

### Step 1: Identify the Domain and Relevant Source(s)

| Question Type | Authoritative Source(s) |
|---------------|------------------------|
| Terminology (Qt product/module names) | S7 (Qt Terms and Concepts) |
| Language, grammar, style | S2 (QUIP 25), S1 (Qt Writing Guidelines) |
| C++ API documentation patterns | S3 (C++ Documentation Style) |
| QML API documentation patterns | S4 (QML Documentation Style) |
| Example documentation | S5 (Qt Examples Guidelines), S6 (Writing Examples) |
| Alt text | S8 (Qt Alt Text Style) |
| QDoc command syntax | S10 (QDoc Manual) |
| General style (when Qt silent) | S9 (Microsoft Style Guide) |

### Step 2: Check the Authoritative Source(s)

1. **Fetch the relevant source** (URL or local file)
2. **Record what the source says** - this is the official guidance
3. **Note if the source is silent** - may need secondary sources

### Step 3: Check Existing Documentation for Consistency

1. **Search existing docs**: `grep -r "TERM" */doc --include="*.qdoc"`
2. **Count instances** of each variant
3. **Note inconsistencies**:
   - Existing docs may conflict with authoritative source
   - Existing docs may be inconsistent with themselves
   - Some patterns may be module-specific

### Step 4: Report Both and Let Author Decide

**Output format:**
```
**[Topic]: "[Variant A]" vs "[Variant B]"**

Official ([Source]): [What the authoritative source says]

Existing usage:
- "[Variant A]": N instances (file1.qdoc, file2.qdoc...)
- "[Variant B]": M instances (file3.qdoc, file4.qdoc...)

Inconsistency: [Describe if existing docs conflict with official or themselves]

Decision for author: [Options - align with official, maintain local pattern,
or flag for broader cleanup]
```

**Why this workflow matters:**
- Authoritative sources define correctness
- Existing docs show current state (may have accumulated inconsistencies)
- Authors need full information to make informed decisions
- Some inconsistencies may warrant separate cleanup patches
- Reviewers should inform, not unilaterally enforce

---

## Rule and Source Enumeration

This skill contains **65 enumerated rules (R1-R64, R51b)** and **10 enumerated sources (S1-S10)** for easy reference.

### Rules by Category
- **Core Principles**: R1-R10 (10 rules)
- **Grammar Rules**: R11-R13 (3 rules)
- **API Documentation**: R14-R19 (6 rules)
- **Example Documentation**: R20-R23 (4 rules)
- **Alt Text**: R24-R27 (4 rules)
- **Writing Contexts**: R28-R29, R28b (3 rules)
- **Common Mistakes**: R30-R37 (8 rules)
- **Common Substitutions**: R38 (1 rule)
- **QDoc Formatting**: R39-R41 (3 rules)
- **UI and Tools Documentation**: R42-R44 (3 rules)
- **Linking Style and Syntax**: R45-R51, R51b (8 rules)
- **Structured Content**: R52-R56 (5 rules)
- **Exceptions**: R57 (1 rule)
- **Page Templates**: R58-R59 (2 rules)
- **Module Review**: R60-R62 (3 rules)
- **Admonition and Markup**: R63-R64 (2 rules)

### Sources by Authority
- **Tier 1 Qt Official**: S1-S8 (highest precedence)
- **Tier 2 Supplementary**: S9
- **Tool Reference**: S10 (syntax only)

See "Sources and Further Reading" section for complete source details.

---


## Rule router (progressive disclosure)

Core principles (R1-R10), Common Mistakes, and R38 substitutions are inline
below. The remaining rule bodies live in `references/` and are loaded on demand
at the gate that needs them. Cite rules by number; resolve the number here:

| Rules | Reference file |
|-------|----------------|
| R11-R13 (grammar), R28-R29 (contexts) | `references/prose-rules.md` |
| R14-R19 (API docs) | `references/api-docs.md` |
| R20-R27 (examples, alt text) | `references/examples-alttext.md` |
| R39-R41, R63-R64 (QDoc formatting, markup) | `references/qdoc-formatting.md` |
| R42-R44 (UI/tools) | `references/ui-tools.md` |
| R45-R51b (linking) | `references/linking.md` |
| R52-R57 (structured content: lists, tables) | `references/structured-content.md` |
| R58-R62 (page templates, module review) | `references/page-templates.md` |

When a review touches a domain above, READ the matching reference file before
applying those rules. R12 (capitalization) and R24-R27 (alt text) are the
most-missed — always load their reference file if the page has \section
titles or images.

## Core Principles

**Note**: Rules R1-R13 summarize guidelines from S1 (Qt Writing Guidelines) and S2
(QUIP 25). For full details, consult the authoritative sources directly.

### R1. Use Active Voice

Active voice over passive. See **S1, S2** for details.
- ❌ "Events will be ignored by the item" → ✅ "The item ignores events"

### R2. Be Clear and Concise

Simple, direct language. ≤20 words per sentence. See **S2** for details.
- ❌ "In order to enable" → ✅ "To enable"

**SCAN trigger:** Flag informal phrases (a lot of, kind of, sort of,
pretty much), filler words (indeed, actually, basically, essentially,
just-as-filler), and wordy constructions (causes X to occur → causes X,
a frequent requirement is to → you often need to).

---

### R3. Use Correct Terminology

**Rule**: Use Qt's standard terminology consistently. Don't invent new terms
or use incorrect class names.

**Verification**: Follow the generic **Verification Workflow** (see above).
For terminology questions, the authoritative source is **S7 (Qt Terms and
Concepts)**. The tables below are EXAMPLES, not exhaustive - always verify
against S7 for terms not listed.

**Qt Terminology Guidelines**:

| Concept | Correct Term | Incorrect Terms |
|---------|-------------|-----------------|
| User interface widget | widget | control, component |
| QML type | type | component, object, widget |
| Property value | property | attribute, field, member |
| Signal/slot mechanism | signal, slot | event, callback, handler |
| Item in QML scene graph | item | object, component, widget |
| Qt Quick Controls element | control | widget, component |
| Person writing code | developer | programmer |

**Generic UI Terminology** (for user-facing descriptions):

| Generic Term | Qt Class | Usage |
|--------------|----------|-------|
| button | QPushButton, Button (QML) | Use "button" in user docs |
| list view | QListView, ListView (QML) | Use "list view" in user docs |
| text field | QLineEdit, TextField (QML) | Use "text field" in user docs |
| dialog | QDialog, Dialog (QML) | Use "dialog" in user docs |
| toolbar | QToolBar | Use "toolbar" in user docs |
| menu bar | QMenuBar | Use "menu bar" in user docs |

**When to use which**:
- **API documentation**: Use exact class names (QListView, ListView)
- **User guides/tutorials**: Use generic terms (list view, text field)
- **Alt text**: Use generic terms, lowercase (button, dialog)
- **Code examples**: Use class names (QListView, QPushButton)

**Qt Version Numbers** (CRITICAL - commonly missed):

| Correct | Incorrect | Notes |
|---------|-----------|-------|
| Qt 5 | Qt5 | Space required before version number |
| Qt 6 | Qt6 | Space required before version number |
| Qt 5-based | Qt5-based | Space before version in compounds |
| Qt 6.5 | Qt6.5 | Space required |

**Qt Product and Module Names** (from S7 - https://wiki.qt.io/Qt_Terms_and_Concepts):

Always use official capitalization and spelling for Qt products and modules:

| Correct | Incorrect | Notes |
|---------|-----------|-------|
| Qt GUI | Qt Gui, Qt gui | Acronym must be all caps |
| Qt Core | Qt core | Module names are capitalized |
| Qt Network | Qt network | |
| Qt Qml | Qt QML (in module name) | Module is "Qt Qml", language is "QML" |
| Qt Quick | Qt quick, QtQuick (in prose) | Two words in prose |
| Qt Widgets | Qt widgets | |
| Qt Add-Ons | Qt Addon, Qt Addons, Qt Add-on Modules | Hyphenated, capitalized |
| Qt D-Bus | Qt DBus, Qt DBUS | Hyphenated |
| Qt SQL | Qt Sql, Qt sql | Acronym must be all caps |
| Qt SVG | Qt Svg, Qt svg | Acronym must be all caps |
| Qt NFC | Qt Nfc | Acronym must be all caps |
| Qt PDF | Qt Pdf | Acronym must be all caps |
| Qt XML | Qt Xml | Acronym must be all caps |
| Qt Creator | Qt creator, QtCreator | Two words, capitalized |
| Qt Design Studio | Qt design studio | Each word capitalized |
| QDoc | Qdoc, qdoc | CamelCase |

**Compound Words** (Qt documentation conventions):

| Correct | Incorrect | Notes |
|---------|-----------|-------|
| framerate | frame rate | Single word in technical contexts |
| runtime | run time, run-time | Single word as noun/adjective |
| filename | file name | Single word |
| namespace | name space | Single word |
| checkbox | check box | Single word |
| toolchain | tool chain | Single word |
| codebase | code base | Single word |
| standalone | stand-alone | Single word |

**Sources**: S2 (QUIP 25), S1 (Qt Writing Guidelines), S7 (Qt Terms and Concepts)

**IMPORTANT - Authoritative Source Verification**:

The tables above are NOT exhaustive. When reviewing terminology:

1. **Scan for Qt patterns**: `Qt[0-9]`, `Qt [A-Z]`, product names, module names
2. **Verify against S7**: Fetch https://wiki.qt.io/Qt_Terms_and_Concepts for authoritative definitions
3. **When in doubt, check source**: Do not assume a term is correct just because it's not in the tables above

**Common patterns to scan for**:
- `Qt[0-9]` → Should be `Qt [0-9]` (space required)
- `QtQuick` in prose → Should be `Qt Quick` (two words)
- `QtCreator` → Should be `Qt Creator` (two words)

---

### R4. Use Present Tense

Present tense for current behavior. See **S2** for details.
- ❌ "will return" → ✅ "returns"

**SCAN trigger:** Search for "will" + verb (will copy, will happen, will
make, will show, will throw). Flag unless conditional future ("if X, Y
will occur") or planned deprecation ("will be removed in Qt 7").

### R5. Use Imperative Mood for Instructions

Imperative for briefs/instructions, indicative for descriptions. See **S3, S4**.
- Imperative: "Returns the value." / "Call this function..."
- Indicative: "This property holds..."

### R6. Use "You" for User Instructions

Address users with "you" in guides/tutorials. See **S1, S2** for details.
- ❌ "One can configure..." → ✅ "You can configure..."
- API docs: Use imperative/indicative patterns (R14-R19) instead

### R7. Avoid Jargon and Idioms

Write for international audience. No idioms. See **S1, S2** for details.

**SCAN trigger:** Flag common English idioms (double-edged sword, behind
the scenes, under the hood, out of the box, on the fly, from scratch).
Replace with literal equivalents. Also: "like" (introducing examples) →
"such as".

### R8. Be Consistent

Same word for same concept throughout. See **S2** for details.

### R9. Use Parallel Structure

Same grammatical structure in lists. See **S2** for details.
- ❌ "Set... / Calling... / You should..." → ✅ "Set... / Call... / Verify..."

---

### R10. Avoid Ambiguous Pronouns

Clear pronoun references. When in doubt, repeat the noun. See **S2** for details.
- ❌ "It is updated first" → ✅ "The item is updated first"

---


## Common Mistakes (Quick Reference)

See rules R1-R38 for details:
- R30: Passive voice → Use active
- R31: Future tense → Use present
- R32: Wordy phrases → Be concise
- R33: Ambiguous "this" → Be specific
- R34: Inconsistent terms → Pick one
- R35: Missing \brief on class/type/property → Add \brief (see R14 for scope)
- R36: No period in brief → Add period
- R37: "Neutral voice" → Use "imperative/indicative mood"

---


## R38. Common Substitutions

Avoid Latin terms, formal/verbose phrases, and hedging words. See **S1, S2, S9**
for complete lists.

**Key substitutions** (most commonly flagged):
| Avoid | Use |
|-------|-----|
| e.g., i.e., etc., via | for example, that is, (be specific), through |
| in order to | to |
| utilize | use |
| simply, obviously, clearly | (omit) |
| since/as (causation) | because |

**Full substitution lists**: Consult S2 (QUIP 25) and S9 (Microsoft Style Guide).

---


## Fix Verification (MANDATORY)

**CRITICAL: Every language fix must be verified against ALL rules before presenting.**

### The Problem

Language fixes often address one issue while introducing another:

| Fix addresses... | But introduces... |
|------------------|-------------------|
| R1 (passive voice) | R2 (wordiness) |
| R2 (wordiness) | R1 (passive voice) |
| R38 (Latin term) | R10 (missing article) |
| Grammar error | R40 (line too long) |

### Verification Process

**Before presenting ANY language suggestion:**

1. **Draft the fix**
2. **Re-read the ENTIRE corrected sentence** - not just the changed part
3. **Check against ALL language rules** (see checklist below)
4. **If fix introduces new issues, revise** - iterate until fully compliant
5. **Only present the final, fully-compliant suggestion**

### Quick Verification Checklist

For every drafted fix, verify:

```
- [ ] R1: Active voice? (no "is/are/was/were [verb]ed", "can be [verb]ed")
- [ ] R2: Concise? (no "in order to", "some of the", "provide a way to")
- [ ] R4: Present tense? (no "will return", "will be")
- [ ] R10: Correct articles? ("the", "a", "an" where needed)
- [ ] R38: No Latin? (no "via", "e.g.", "i.e.", "etc.")
- [ ] R40: ≤80 columns?
- [ ] Grammar correct? (agreement, possessives, parallelism)
- [ ] Clear and readable?
```

### Domain Terms Exception

**Before flagging terminology, verify it's not a valid technical term:**

- **C++ terms**: "in-place" (construction), "move semantics", "RAII", "emplace"
- **Qt terms**: Check Qt Terms and Concepts (S7)
- **QML terms**: Check QML Documentation Style (S4)

**Example**: "inplace" or "in-place" is valid C++ terminology. Do NOT flag as spelling error.

### Example - Iterative Verification

```
Original: "The data can be also assigned directly via the property"

Draft 1: "The data can also be assigned directly via the property"
  ✗ R1: Still passive ("can be assigned")
  ✗ R38: Latin term ("via")
  → REVISE

Draft 2: "You can also assign the data directly via the property"
  ✓ R1: Active ("You can assign")
  ✗ R38: Latin term ("via")
  → REVISE

Draft 3: "You can also assign the data directly through the property"
  ✓ R1: Active
  ✓ R38: No Latin
  ✓ R2: Concise
  ✓ R40: 58 chars
  → PRESENT
```

---


## Sources

See `references/sources.md` for the authoritative source list (S1-S10).
