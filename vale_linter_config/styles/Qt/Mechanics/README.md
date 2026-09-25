# Qt.Mechanics

Vale rules that check generic text mechanics: line length, inter-sentence
spacing, word repetition, and spelling. A `Qt.Mechanics` rule applies to any
line of prose. It doesn't care which QDoc element it's in, a job for
[`styles/Qt/Structure`](../Structure/README.md), or how the sentence is
phrased, a job for [`styles/Qt/Language`](../Language/README.md).

These checks were carved out of the original flat `styles/Qt` directory,
which mixed them in with the language and structure rules that became the
top-level `QtLanguage` and `QtStructure` styles. Those three styles were then
consolidated as subdirectories of the `Qt` style (`styles/Qt/Language`,
`styles/Qt/Structure`, `styles/Qt/Mechanics`), which Vale resolves into the
`Qt.Language.*`, `Qt.Structure.*`, and `Qt.Mechanics.*` rule names used
throughout this document.

## Enabled

| Rule | Checks | Vale mechanism |
|---|---|---|
| `Qt.Mechanics.Repetition` | The same word repeated back-to-back | [`repetition`](https://vale.sh/docs/keys/repetition) |
| `Qt.Mechanics.LineLength` | Line exceeds 80 characters (wrap at a word boundary) | [`script`](https://vale.sh/docs/keys/script), `LineLength.tengo` |
| `Qt.Mechanics.Spacing` | Exactly one space after sentence-ending punctuation, with Qt/NXP product-name exceptions (`i.MX`) that `Microsoft.Spacing` can't express | `existence` |
| `Qt.Mechanics.Spelling` | Spell-checking, filtered to ignore CamelCase words and `Q`-prefixed Qt API names (`QSettings`, `QQmlEngine`) | [`spelling`](https://vale.sh/docs/keys/spelling) |

`Qt.Mechanics.Spacing` replaces `Microsoft.Spacing` (left disabled in
`.vale-qdoc.ini`) rather than running alongside it: `nonword` rules don't
consult the vocabulary list
([errata-ai/vale#1058](https://github.com/errata-ai/vale/issues/1058)), so
Microsoft's version has no way to carve out the Qt/NXP exceptions this one
needs.

## Not enabled

| Rule | Status | Why it's off |
|---|---|---|
| `Underfilled` | Noisy | Flags a line where the next line's first word would still fit within 80 columns. Built and working, but noisy enough on real docs that it's left disabled pending tuning. |

## Scripted rules

`LineLength` and `Underfilled` are [`script`](https://vale.sh/docs/keys/script)
rules backed by Tengo scripts in `styles/config/scripts/` (a shared location,
not per-style, so moving a rule's `.yml` between style directories doesn't
require moving its script). `LineLength.tengo` guards two defects found
during development: routing the check through `extends: existence` let a
standalone vocabulary term suppress a match (46% recall over `doc/src`), and
Tengo's `len()` counts bytes, so a line with a multi-byte character measured
long and false-positived. See `tests/run-linelength-test.sh` and
`tests/LineLength.qdoc` for the regression coverage.

## Sources

- These rules build on Vale's `repetition`, `script`, `spelling`, and
  `existence` extension points. See the full list at
  [vale.sh/docs/keys](https://vale.sh/docs/keys/).
- `Qt.Mechanics.Spacing`'s design rationale, including the `nonword`/
  vocabulary limitation it works around, follows the
  [Microsoft Style Guide's periods guidance](https://learn.microsoft.com/en-us/style-guide/punctuation/periods).
- The 80-column line-wrap convention comes from the
  [Qt Coding Style](https://wiki.qt.io/Qt_Coding_Style).

## Tests

`tests/LineLength.qdoc` + `tests/run-linelength-test.sh`. `Spacing`,
`Spelling`, and `Repetition` are covered indirectly through the general
`.qdoc` fixtures under `tests/` (e.g. `tests/QtSpellingTest.qdoc`) rather than
a dedicated two-way EXPECT-FLAG harness.
