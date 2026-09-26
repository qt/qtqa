---
name: skill-g-rules
description: Qt G-rules (G1-G30): style rules that need judgment and have no tool check. Load after the skill-r-rules tool pass.
metadata:
  version: "0.1.0"
  status: provisional
  loading: "Pattern 3 (GATE): this file (G1-G22) at the LLM review step; references/registers.md (G23-G30) at the register check"
  source: documentation_review/skills/skill-language-style
---

# skill-g-rules

**G-rules** (guidance) are the non-deterministic rules from
[`skill-language-style`](../../../documentation_review/skills/skill-language-style/SKILL.md).
No Vale rule or regex decides them reliably, so the LLM checks them.
Run the [`skill-r-rules`](../skill-r-rules/SKILL.md) tool pass first,
and spend LLM tokens only here.

Each G rule names its source R rule. Cite findings as `G<n>`.
**Vale hint** names a Vale rule that is in qt/qtqa
`vale_linter_config/styles/Qt` but disabled in `.vale-qdoc.ini`. Its alerts
can shortlist candidates, but the LLM decides each case. When a Vale rule
proves reliable, move its rule to skill-r-rules.

**Status: provisional.** Numbering is new; don't renumber after publication.

### G1. Active voice (from R1)
Prefer active voice; passive is fine when the actor doesn't matter.
No Vale rule checks it.
- ❌ Events are ignored by the item.
- ✅ The item ignores events.

### G2. Terminology beyond the list (from R3)
Terms that `Qt.Language.QtTerminology` doesn't list: check against S7
(Qt Terms and Concepts).
- ❌ Add the element to the QML scene tree.
- ✅ Add the item to the Qt Quick scene.

### G3. Imperative mood (from R5, R37)
Class and type briefs follow C1.1 and C2.1 ("The X class provides..."),
as S3 requires.
Briefs and instructions use the imperative; descriptions the indicative.
Vale hint: `Qt.Language.ImperativeBrief`.
- ❌ `\brief This function is used to set the width.`
- ✅ `\brief Sets the width.`

### G4. Addressing the reader (from R6, S1, S9)
S1: "Use the pronoun *you* to address the reader when appropriate."
S9 (Microsoft, *Person*): in general, use second person.

**When it's appropriate.** Decide by the actor of the sentence:

| The sentence is about... | Actor | Write |
|--------------------------|-------|-------|
| a step the reader takes | reader | imperative ("Open...") or "you" |
| a choice the reader makes (when to use X, X or Y) | reader | "you" ("Use X when you need...") |
| a requirement on the reader's code | reader | "you" ("You must call...") |
| a result the reader sees | reader | present tense ("A window opens.") |
| what the API, type, or tool does | the API | third person ("Returns...", "The list...") |
| a definition or a property value | the API | third person, no "you" |

Directives:
- Don't turn a clean third-person fact into "you" ("You get the size
  from this function" → "Returns the size").
- Don't replace the reader with "one", "the developer", "the programmer",
  or "we". "The user" means the end user of the application, not the
  reader.
- Omit "you can" when the sentence works without it (S9). Keep it when
  it states an option ("You can also pass a lambda.").
- The register rule for the content type (G23-G30) can narrow this; see
  the Microsoft baseline table there.
- ❌ One can configure the kit in the settings.
- ✅ You can configure the kit in the settings.
- ❌ (C1) You can use this function to get the size of the list.
- ✅ (C1) Returns the size of the list.

### G5. Consistency (from R8, R34)
One term per concept on a page. Vale hint: `Qt.Language.TermConsistency`.
- ❌ Add a delegate to the list view. ... The ListView then ...
- ✅ Add a delegate to the list view. ... The list view then ...

### G6. Parallel structure (from R9)
- ❌ `\li Set the model.` `\li Calling reset().` `\li You should verify it.`
- ✅ `\li Set the model.` `\li Call reset().` `\li Verify the result.`

### G7. Ambiguous pronouns (from R10, R33)
Vale hint: `Qt.Language.AmbiguousPronoun`.
- ❌ The view updates the model. It is refreshed first.
- ✅ The view updates the model. The model is refreshed first.

### G8. Numbers (from R13)
One to nine in words; numerals for 10 and up, versions, sizes, and code.
Vale hint: `Qt.Language.Numbers` (off: flags "Qt 6").
- ❌ The function takes 3 arguments.
- ✅ The function takes three arguments.

### G9. Function briefs (from R17)
For C++ and QML API blocks, the node rules C1.4 and C2.4 in `skill-c-
rules` take over.
Start with the verb for the operation.
- ❌ `\brief The width getter.`
- ✅ `\brief Returns the width.`

### G10. Property and signal briefs (from R18, R19)
For C++ and QML API blocks, the node rules C1.5, C1.4 (signals), C2.2,
and C2.3 in `skill-c-rules` take over. Member nodes need no `\brief`
(R14): the body starts "This property holds...".
Properties: "This property holds..."; signals: "This signal is emitted
when...". Vale hint: `Qt.Language.PropertySignalOpener` (policy call).
- ❌ `\brief Value changed.`
- ✅ `\brief This signal is emitted when the value changes.`

### G11. Alt text content (from R25, R27)
Prefer visible labels, then purpose; use noun phrases, not passive
clauses. No Vale rule checks it.
- ❌ `{A dialog is shown where details are entered}`
- ✅ `{Settings dialog with Save and Cancel buttons}`

### G12. Page-type style (from R28, R28b, R29)
API docs: imperative briefs, indicative descriptions. Tools docs and
guides: "you", task-oriented titles.
- ❌ (tutorial) `\section1 The Project` The user will then create a project.
- ✅ (tutorial) `\section1 Creating a project` You create a project.

### G13. UI markup and menu paths (from R42, R44)
Mark UI text with `\uicontrol` in every QDoc source, including Qt
Creator and Qt Design Studio; it renders in bold (S1). Use literal bold
only in formats without `\uicontrol` (Markdown). Mark each menu element.
Vale hints: `Qt.Structure.UIElementMarkup`,
`Qt.Structure.MenuPathFormat`.
- ❌ Go to File > New Project and click OK.
- ✅ Go to \uicontrol File > \uicontrol {New Project} and select \uicontrol OK.

### G14. Causal "since" and "as" (from R38)
Use "because" for cause; keep "since" for time. Vale hint:
`Qt.Language.CausationSinceAs` (off: can't tell the two apart).
- ❌ Since the buffer is full, the write fails.
- ✅ Because the buffer is full, the write fails. (Since Qt 6.5 is fine.)

### G15. `\l` vs `\c` (from R46)
`\l` for public API; `\c` for private or undocumented API. Check the
header and export macro.
- ❌ `\l{QWidgetPrivate::init()}`
- ✅ `\c{QWidgetPrivate::init()}`

### G16. QML-to-C++ links (from R51b)
QML docs link to QML targets, except in module overviews.
- ❌ (QML property) Holds the \l{QTextToSpeech::rate()}{rate}.
- ✅ (QML property) Holds the \l{TextToSpeech::rate}{rate}.

### G17. List and table introductions (from R54)
Vale hint: `Qt.Structure.ListIntroPresence` (infeasible).
- ❌ `\section1 Parameters` `\list` ...
- ✅ The function accepts the following parameters: `\list` ...

### G18. (Removed)
The legal-text exemption from upstream R57 is not ported. Legal and
license text is checked in Phase 2; see C11 in `skill-c-rules`. The ID
stays reserved so that later G numbers don't shift.

### G19. Admonitions (from R63)
`\warning` only for serious consequences, and state the consequence.
Vale hint: `Qt.Language.AdmonitionHedging`.
- ❌ `\warning Use with caution.`
- ✅ `\warning Calling this from another thread corrupts the model.`

### G20. Markup consistency (from R64)
Mark every code element the same way throughout.
- ❌ Returns true if enabled; set Qt::AlignLeft ...
- ✅ Returns `\c true` if enabled; set `\c{Qt::AlignLeft}` ...

### G21. Clarity beyond word lists (from R2)
Sentences at or under about 20 words; one idea per sentence.
- ❌ The function, which is called when the model changes and the view is visible, updates the delegate cache and then emits a signal.
- ✅ The view calls this function when the model changes. It updates the delegate cache and emits a signal.

### G22. Punctuation for relationships (from R68)
After R68 removes a dash, pick the punctuation that names the
relationship: colon, comma, parentheses, or period.
- ❌ Two modes are supported, synchronous, and asynchronous.
- ✅ Two modes are supported: synchronous and asynchronous.

## Registers (G23-G30)

The register rules (one register per content type, and the drift rules
G26, G27, G30) are in [`references/registers.md`](references/registers.md).
Load it at the register check, once per page. Most checks need only
G1-G22 above plus the C type's own rules.
