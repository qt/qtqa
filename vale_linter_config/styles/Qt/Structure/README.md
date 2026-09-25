# Qt.Structure

Vale rules that check Qt's *topic/document structure*: whether a specific
QDoc command or page element sits in the right place and is formatted the way
QDoc itself expects. A `Qt.Structure` rule cares about which QDoc element is
involved and whether it's well-formed. It doesn't judge how the surrounding
prose is phrased. The table below covers the range of elements: briefs,
titles, anchors, tables, images, version clauses, and a module landing
page's required sections.

Sibling styles cover the other concerns this rule set used to mix together:

- [`styles/Qt/Language`](../Language/README.md) checks the wording of the
  prose itself (grammar, tense, tone, terminology), independent of which
  QDoc element it's in.
- [`styles/Qt/Mechanics`](../Mechanics/README.md) checks generic text
  mechanics (line length, spacing, repetition, spelling) that apply to any
  prose line, regardless of QDoc structure.

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
| `Qt.Structure.QDocBrief` | `\brief`/`\class`/`\property`/`\fn`/`\qmlsignal` briefs end with a period | [`existence`](https://vale.sh/docs/keys/existence), `scope: text.class.brief` |
| `Qt.Structure.QDocImageAlt` | `\image`/`\inlineimage` has alt text | `existence`, `scope: meta.noalt` |
| `Qt.Structure.QDocImageAltInlineCmd` | Alt text is plain text, not an inline QDoc command | `existence`, `scope: raw` |
| `Qt.Structure.QDocAnchorAPIName` | `\target`/`\keyword` uses a topic name instead of a raw API identifier | `existence`, `scope: meta.anchor` |
| `Qt.Structure.QDocVersionClauseOrder` | `\value [since X]` clause immediately follows `\value` (QDoc silently drops a misplaced one) | `existence`, `scope: text & doc(p)` |
| `Qt.Structure.QDocDeprecatedVersionOrder` | `\deprecated`/`\obsolete [X]` version bracket comes first (same silent-drop failure mode) | `existence`, `scope: text & doc(p)` |
| `Qt.Structure.KeyboardShortcutFormat` | Keyboard shortcuts read `Ctrl+B`, not `Control+B` or `Ctrl + B` | `existence` |
| `Qt.Structure.SectionLinkAntiPattern` | Section links use `TypeName#Section Title`, not a literal `page.html#anchor` | `existence` |
| `Qt.Structure.NoSpaceBeforeBrace` | No space before a QDoc command's opening brace (`\l{target}`, not `\l {target}`) | `existence`, `scope: raw` |
| `Qt.Structure.ListItemPunctuation` | No trailing comma-before-conjunction in a `\li` item (a run-on split across items) | `existence`, `scope: raw` |
| `Qt.Structure.TableEmptyCell` | No blank table/list cell (best-effort, see [Known gaps](#known-gaps) below) | `existence`, `scope: raw` |
| `Qt.Structure.TableGenericHeaders` | `\header` cells aren't generic labels like "Name"/"Value" | `existence`, `scope: text & doc(th)` |
| `Qt.Structure.AltTextFormat` | Alt text starts with a capital letter, no trailing period | `existence`, `scope: raw` |
| `Qt.Structure.AltTextClassNames` | Alt text uses a generic UI term instead of a Qt class name (`Button` instead of `QPushButton`) | `existence`, `scope: raw` |
| `Qt.Structure.InlineImageAltBraces` | `\inlineimage` alt text is wrapped in `{...}` (qdoc reads unbraced text as ordinary prose, not alt text) | `existence`, `scope: raw` |
| `Qt.Structure.ImageAltTextContinuation` | Unbraced `\image` alt text doesn't spill onto a continuation line (qdoc only reads the same line; multi-line alt text needs `{...}`) | `existence`, `scope: raw` |
| `Qt.Structure.ExampleTitleRepetition` | Example/tutorial titles don't repeat the word "Example" | `existence`, `scope: heading.h1` |
| `Qt.Structure.QMLGenericTypes` | `\qmlmethod`/`\qmlproperty` signatures use generic QML types, not the underlying C++ type | `existence`, `scope: raw` |
| `Qt.Structure.ModuleExamplesSection` | A module page has an Examples section | [`occurrence`](https://vale.sh/docs/keys/occurrence), `scope: doc(section:has(> h2:contains(...)))` |
| `Qt.Structure.ModuleReferenceSection` | A module page has a Reference section | `occurrence`, same selector pattern |
| `Qt.Structure.ExampleGroupIngroup` | An example group page has `\ingroup all-examples` (otherwise its examples never appear on "All Qt Examples") | `occurrence`, `scope: raw` |

**Applicability note:** `ModuleExamplesSection`, `ModuleReferenceSection`, and
`ExampleGroupIngroup` are whole-file presence checks, so left unscoped they'd
match any routed file lacking the section, not only module landing or
example-group pages. They're wired in `.vale-qdoc.ini` under dedicated glob
sections instead of the general `[*.{qdoc,...}]` one:
`ModuleExamplesSection`/`ModuleReferenceSection` under `[*-index.qdoc]`,
`ExampleGroupIngroup` under `[*-examples.qdoc]`. Both filename conventions
were verified against real module docs in `qtbase`/`qtdeclarative`/`qttools`
(`qtwidgets-index.qdoc`, `qtwidgets-examples.qdoc`, `qtdbus-examples.qdoc`,
etc.) -- confirming, for example, that `ExampleGroupIngroup` no longer fires
on unrelated `\group` pages like `cmake-properties.qdoc` or
`xml-processing.qdoc` that were never meant to declare `\ingroup
all-examples`. `ExampleGroupIngroup` still has a residual gap: an individual
example write-up page (documents one `\example`, has no `\group`) can share
the same `*-examples.qdoc`/`*-example.qdoc` naming and would still be
misflagged -- Vale can't additionally require "this file contains `\group`"
in one rule (see [Engine quirks](#engine-quirks)). See
`tests/mod-index.qdoc` / `mod2-index.qdoc` (module landing page, in scope)
and `tests/mod-examples.qdoc` / `mod2-examples.qdoc` (example group, in
scope) for the positive/negative fixture evidence, and
`tests/mod-nonpage.qdoc` for proof that identical "missing everything"
content stays silent when the filename doesn't match either glob.

## Not enabled (research, known gap, or proof of concept)

| Rule | Status | Why it's off |
|---|---|---|
| `MenuPathFormat` | Untested at scale | Matches an unbolded `Capitalized > Capitalized` span as a menu path. Passes its own fixture, but the false-positive rate on real docs, especially outside Qt Creator and Qt Design Studio, is still unknown. |
| `ListIntroPresence` | Works, disabled pending review | Originally attempted a CSS previous-sibling selector (`p + ul`) to detect a list with no preceding paragraph; the `doc()` dialect doesn't support sibling combinators, and the selector matched scattered positions unrelated to actual list locations. Redesigned as a `scope: raw` heuristic: flags a `\list`/`\table` whose nearest preceding non-blank line is itself a QDoc command rather than prose. Deliberately narrow: it catches only the "command immediately before" case, not every missing-intro case (e.g. two blank lines, or an intervening `\note`). Disabled pending validation against the real doc corpus. |
| `SaTargetVocab` | Proof of concept only | Flags an `\sa` target that isn't on a hand-picked 3-entry "valid" list. A real rule needs a vocabulary generated from QDoc `.index` files (`grep 'name="Target"'`) at build time. |
| `UIElementMarkup` | Proof of concept only | Flags a bare UI element name (`File`, `Build`) that isn't wrapped in `**bold**` or `\uicontrol{}`, checked against a hand-curated 6-entry blocklist. Needs a real, generated Qt Creator UI-string list before it's more than a demo. |

## Known gaps

- **`TableEmptyCell`** flags any blank `\li` line, not just blank table
  cells. QDoc uses `\li` for both table cells and list items, so this also
  matches an ordinary blank list item. A `doc(td)`-scoped version was
  attempted and reverted, because `occurrence`/`metric` rules can't measure a
  leaf element (`td`, `th`, `li`) in this Vale build (see
  [Engine quirks](#engine-quirks)). `existence` can only assert the presence
  of a bad pattern, not the absence of any content: an anchor-only pattern
  like `^\s*$` never survives Vale's `MightMatch` pre-filter, which requires a
  literal. This file-wide version is the best available option today, and the
  gap is documented here and in the rule file itself.

## Engine quirks

Useful groundwork for writing any future rule in this repo that uses
`scope: raw` or a `doc(...)` selector. These came up most often while
building the structure rules above, and they apply equally to `Qt.Language`
and `Qt.Mechanics` rules using the same mechanisms.

- A `raw:` list with more than one pattern doesn't produce any matches at
  all. It doesn't just skip past the first entry. Combine multiple patterns
  into one `(?:a|b|c)` alternation instead.
- `scope: raw` sees the whole file as one string. Anchors like `$` and `^`
  need the `(?m)` flag to bind per line.
- Vale's `MightMatch` pre-filter needs a literal in the pattern before it
  considers a rule at all. A pure anchor like `^\s*$` never fires. An
  `existence` check can't express "this cell is empty."
- RE2, Vale's regex engine, has no lookaround. A `raw`-scope pattern can't be
  bounded to stay inside `\table...\endtable`. It can match past that
  boundary.
- `occurrence` and `metric` rules measure containers like `table`, `ul`,
  `p`, and `section`. They don't measure leaf elements like `td`, `th`, or
  `li`. This is the root cause behind the `TableEmptyCell` gap above, and the
  reason a `doc(td)`-scoped `ListIntroPresence`-style check isn't buildable
  either.
- A `scope:` value only needs to name a *subset* of a block's scope
  sections, so a scope naming just the shared prefix of two different
  variants matches both of them. This broke `Qt.Structure.QDocImageAlt`:
  vale's QDoc converter (`internal/lint/qdoc.go`, upstream vale-cli/vale,
  not this fork) marks every image with `class="image"`, and only the ones
  missing alt text get a second `noalt` class, producing scope strings
  `meta.class.image` (has alt) and `meta.class.image.class.noalt` (no alt).
  `scope: meta.image` is a subset of *both* strings, so the rule fired on
  every image regardless of whether alt text was present. Fixed by scoping
  to `meta.noalt`, the token unique to the missing-alt variant.
- The `doc()` selector dialect doesn't support CSS sibling combinators like
  `p + ul`. Matches come back scattered and unrelated to position, not an
  outright error.
- `!doc(...)` negation doesn't work. `:not()` inside the selector does work,
  but only against the matched element's own class, not an ancestor's
  content.
- A `scope: raw` rule anchored near a block's closing `*/` can report its
  alert one line off from the real trigger line. The rule itself is correct.
  Only the fixture tagging shifts. It showed up in the test fixtures for
  `SaTargetVocab.yml` and `PropertySignalOpener.yml` (the latter now in
  `styles/Qt/Language`).

## Microsoft-overlap audit (2026-09-25)

Every rule now in `Qt.Language`/`Qt.Structure` was checked against every rule
already included in `styles/Microsoft` (the synced package), to catch a new
rule quietly duplicating one already enabled. Testing found two real
overlaps, both fixed by extending the existing Microsoft rule directly
(`extends: Microsoft.<Rule>`, per
[docs.vale.sh/topics/styles#extending-another-rule](https://docs.vale.sh/topics/styles/#extending-another-rule))
instead of duplicating its logic:

| Overlap | Evidence | Fix |
|---|---|---|
| `ListItemPunctuation`'s trailing-`;` check vs. `Microsoft.Semicolon` (`scope: sentence`, already enabled) | Both rules matched the same line (`\li First item;`): `Microsoft.Semicolon` at col 40, `ListItemPunctuation` at col 5 | Dropped the `;` alternative from `ListItemPunctuation.yml`. It now only flags the trailing comma-before-conjunction case, which Microsoft has no rule for. |
| `WordyFillers`'s `'a lot of'` token vs. `Microsoft.Wordiness` (`substitution`, already enabled) | Same class of entry Wordiness already carries (`a (?:large)? number of: many`) | Moved `a lot of` into a new `Qt.Language.WordyQuantifier`, which `extends: Microsoft.Wordiness` with `swap+: {a lot of: many}` instead of a standalone `existence` check. |

Everything else was confirmed **not** a duplicate. The remaining rules either
target QDoc structure with no HTML/prose analog in Microsoft's style
(`\li`/`\image`/`\qmlmethod`/`\ingroup`/`doc()`-scoped section checks), or
Qt-specific vocabulary (`QtTerminology`, `Idioms`, `KeyboardShortcutFormat`)
that Microsoft's `Terms.yml`/`Vocab.yml` don't cover.

`Qt.Language.PassiveVoice` and `Qt.Language.AltTextPassive` (the same
be-verb-plus-past-participle heuristic, the latter scoped to `\image {...}`
alt text) were both removed rather than kept disabled: `Microsoft.Passive`
(already enabled, default `scope: text`) uses the same heuristic with a
much larger irregular-verb list, and that scope already covers alt-text
content and fires on it in production (confirmed empirically on `\image
x.png {The widget is displayed here}` and on plain prose across the
`tests/*.qdoc` corpus). Both Qt rules were a strict subset of what
`Microsoft.Passive` already flags: neither added any detection
`Microsoft.Passive` didn't already provide, and `Microsoft.Passive` also
catches irregular participles (`"is shown"`) that their regular-`-ed`-only
pattern couldn't.

## Tests

`tests/QtLanguageRules.qdoc` and `tests/run-qtlanguage-test.sh` cover the
deterministic, enabled rules (shared with `Qt.Language`, since the fixture
predates the split). `tests/mod-index.qdoc`, `mod2-index.qdoc`,
`mod-examples.qdoc`, `mod2-examples.qdoc`, and `mod-nonpage.qdoc` (also run by
`run-qtlanguage-test.sh`, against the real `.vale-qdoc.ini`) cover the
module-page presence checks and their `[*-index.qdoc]`/`[*-examples.qdoc]`
filename scoping. `tests/QtLanguageExperimentalRules.qdoc` and
`tests/run-experimental-rules-test.sh` cover the research-only rules, also
shared with `Qt.Language`.
