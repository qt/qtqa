# Qt.Language

Vale rules that check the *wording* of Qt documentation prose: grammar,
tense, tone, terminology, and word choice. A `Qt.Language` rule judges how a
sentence is phrased, independent of which QDoc command or page element it
appears in.

Sibling styles cover the other concerns this rule set used to mix together:

- [`styles/Qt/Structure`](../Structure/README.md) checks whether a specific
  QDoc command or page element (brief, title, anchor, table, image, version
  clause, module section) is present, ordered, and formatted the way QDoc
  itself expects.
- [`styles/Qt/Mechanics`](../Mechanics/README.md) checks generic text
  mechanics (line length, spacing, repetition, spelling) that apply to any
  prose line, regardless of wording or QDoc structure.

This grouping replaces the original flat `styles/Qt`, `styles/QtLanguage`,
and research-only `styles/QtLanguageExperimental` styles. Every rule was
first reclassified by what it checks, not by which directory it used to live
in, into three top-level styles (`QtLanguage`, `QtStructure`, `QtMechanics`).
Those three were then consolidated as subdirectories of the `Qt` style
(`styles/Qt/Language`, `styles/Qt/Structure`, `styles/Qt/Mechanics`), which
Vale resolves into the `Qt.Language.*`, `Qt.Structure.*`, and
`Qt.Mechanics.*` rule names used throughout this document. See each rule's
own header comment for the file it originally moved from.

## Enabled

| Rule | Checks | Vale mechanism |
|---|---|---|
| `Qt.Language.FutureTense` | Present tense instead of future/conditional ("returns", not "will return") | [`existence`](https://vale.sh/docs/keys/existence) |
| `Qt.Language.LatinTerms` | Latin-derived terms replaced with plain English ("via" → "through") | [`substitution`](https://vale.sh/docs/keys/substitution), [`extends: Microsoft.Foreign`](https://docs.vale.sh/topics/styles/#extending-another-rule) |
| `Qt.Language.LoseLoose` | "loose" vs. "lose" verb confusion | [`substitution`](https://vale.sh/docs/keys/substitution) |
| `Qt.Language.QDocPageTitle` | `\title` uses title-style capitalization | [`capitalization`](https://vale.sh/docs/keys/capitalization) |
| `Qt.Language.QtTerminology` | Correct spacing/spelling of Qt product and module names ("Qt5" → "Qt 5") | `existence` |
| `Qt.Language.HedgingWords` | Hedging/filler adverbs to delete ("simply", "obviously", "clearly") | `existence` |
| `Qt.Language.WordyFillers` | Informal filler phrases with no fixed replacement ("kind of", "sort of") | `existence` |
| `Qt.Language.WordyQuantifier` | "a lot of" → "many" | `existence`, [`extends: Microsoft.Wordiness`](https://docs.vale.sh/topics/styles/#extending-another-rule) |
| `Qt.Language.WordyConstructions` | Wordy constructions with no fixed replacement ("causes X to occur") | `existence` |
| `Qt.Language.Idioms` | Idioms that don't translate for a non-native-English audience | `existence` |

`Qt.Language.WordyQuantifier` extends `Microsoft.Wordiness` directly instead of
duplicating it as a standalone check. "A lot of" is the same class of vague
quantifier Wordiness already handles ("a number of" → "many"). It was split
out of `Qt.Language.WordyFillers` for that reason. See that file's header
comment.

## Not enabled (research or known gap)

These rules are built and tested, but commented out in `.vale-qdoc.ini`. None
were rejected outright as false positives. Each one has a specific, documented
reason to stay opt-in. Uncomment the corresponding `Qt.Language.<Rule> = YES`
line to try one.

| Rule | Status | Why it's off |
|---|---|---|
| `Numbers` | Infeasible as written | Flags "Qt 6" as a false positive, since the pattern matches a version number the same way it matches a prose count |
| `CausationSinceAs` | Infeasible as written | Can't distinguish causal "since"/"as" from temporal ("since Qt 6.5") |
| `Headings` | Works, overlaps `Microsoft.Headings` | `Microsoft.Headings` already enforces sentence-case on `\section1` through `\section4`, but testing found a missed, obvious violation. That points to a confidence-threshold issue in the `capitalization` rule type. This rule now matches correctly as a second opinion. The `scope` bug was a comma-joined string that doesn't split into multiple selectors; the fix is a YAML list instead. Track down the `Microsoft.Headings` gap and decide on overlap policy before enabling both. |
| `TermConsistency` | Proven, needs scale | [`consistency`](https://vale.sh/docs/keys/consistency) rule type. The first term variant that appears in a file sets the accepted form, and later variants get flagged. Works today with one hand-picked `either:` pair (`list view`/`ListView`). A real project-wide term vocabulary is needed before it's useful broadly. |
| `AdmonitionHedging` | Proven, narrow scope | Matches hedging phrases ("use with caution") inside `\warning` via `doc(div.warning)`. Doesn't match the same phrase inside `\note`. Extend the scope before enabling. |
| `AmbiguousPronoun` | Proven, low noise | Matches vague sentence-initial "This/It is/was/does/has…". Needs wider sampling against real docs before enabling by default. |
| `ImperativeBrief` | Proven, needs scale | Matches "This function is used to…" instead of imperative mood ("Sets…"). Needs wider sampling before enabling. |
| `PropertySignalOpener` | Works, but is a policy call | Enforces a closed allow-list of approved property/signal brief openers. The style guide lists these as *examples* today, not a mandatory set. Turning them into one is a team decision to make deliberately, before enabling this rule. |

`PassiveVoice` (the classic "be + past participle" heuristic, known to
false-positive on predicate adjectives like "is enabled"/"is cached") was
removed rather than kept in this table: `Microsoft.Passive` (already
enabled) uses the same heuristic with a larger irregular-verb list, so it
already produces the same false positives in production. `PassiveVoice`
didn't add any detection `Microsoft.Passive` didn't already provide. See
[`styles/Qt/Structure/README.md`](../Structure/README.md) for the fuller
comparison.

## Sources

These rules build on Vale's own extension points: `existence`,
`substitution`, `capitalization`, `consistency`, and the mechanism for
[extending another rule](https://docs.vale.sh/topics/styles/#extending-another-rule).
See the full list at [vale.sh/docs/keys](https://vale.sh/docs/keys/).

Style-choice references cited by individual rules include the
[Microsoft Writing Style Guide](https://learn.microsoft.com/en-us/style-guide/)
and the Qt Wiki's
[Qt Writing Guidelines](https://wiki.qt.io/Qt_Writing_Guidelines) and
[Qt Terms and Concepts](https://wiki.qt.io/Qt_Terms_and_Concepts).

Engine-level quirks that shaped several of these rules, such as RE2 having no
lookaround, `raw:` lists only evaluating their first entry, and `MightMatch`
needing a literal, are documented in
[`styles/Qt/Structure/README.md`](../Structure/README.md#engine-quirks).
They came up most often while writing the structure rules, and they apply to
any rule in this Vale build that uses `scope: raw` or a `doc()` selector.

## Tests

`tests/QtLanguageRules.qdoc` and `tests/run-qtlanguage-test.sh` cover the
deterministic, enabled rules (shared with `Qt.Structure`, since the fixture
predates the split). `tests/QtLanguageExperimentalRules.qdoc` and
`tests/run-experimental-rules-test.sh` cover the research-only rules, also
shared with `Qt.Structure`.
