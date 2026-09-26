# R-rules: checks and samples

One entry per deterministic rule: the rule, the check a tool runs, and a
sample. ❌ is flagged by the check; ✅ passes. Full text and exceptions:
`documentation_review/skills/skill-language-style/`.

## Language

### R2. Clear and concise
Drop filler and wordy constructions.
**Check:** Vale `Qt.Language.WordyConstructions`, `Qt.Language.WordyFillers`,
`Qt.Language.WordyQuantifier`.
- ❌ This is kind of complex and needs a lot of setup.
- ✅ This is complex and needs several setup steps.

### R3. Qt terminology (listed names)
Qt product and module names are spelled exactly. Terms not on the list: G2.
**Check:** Vale `Qt.Language.QtTerminology`.
- ❌ Qt5 and QtQuick support this.
- ✅ Qt 5 and Qt Quick support this.

### R4. Present tense
**Check:** Vale `Qt.Language.FutureTense` (inferred). Planned removals
("will be removed in Qt 7") are exempt.
- ❌ This function will return the index.
- ✅ This function returns the index.

### R7. Idioms
**Check:** Vale `Qt.Language.Idioms`.
- ❌ The cache works under the hood.
- ✅ The cache works automatically.

### R11. Serial comma
**Check:** Vale `Microsoft.OxfordComma`.
- ❌ name, value and type
- ✅ name, value, and type

### R12. Capitalization
`\title` in title case; `\section` headings in sentence case.
**Check:** Vale `Qt.Language.QDocPageTitle` (inferred), `Microsoft.Headings`.
- ❌ `\section1 Building Your First Application`
- ✅ `\section1 Building your first application`

### R38. Substitutions (word lists)
Hedging words, Latin terms, lose/loose. Causal "since"/"as": G14.
**Check:** Vale `Qt.Language.HedgingWords`, `Qt.Language.LatinTerms`,
`Qt.Language.LoseLoose` (last two inferred).
- ❌ Simply configure it via the settings, e.g. the kit.
- ✅ Configure it through the settings, for example the kit.

## API documentation

### R14. `\brief` required
Top-level nodes need a `\brief`: `\class`, `\struct`, `\union`,
`\namespace`, `\headerfile`, `\qmltype`, `\qmlvaluetype`, `\page`,
`\example`, `\module`, `\qmlmodule`, `\group`. QDoc uses their brief in
annotated and generated lists, index files, and the page's
`<meta name="description">` (qttools `da04c5df8`: htmlgenerator.cpp
generateAnnotatedList, generateHeader; qdocindexfiles.cpp). Member nodes
(`\fn`, `\property`, `\variable`, `\enum`, `\qmlproperty`, ...) don't
need one: member summary tables show no brief, and a member `\brief`
renders as an ordinary first paragraph. QDoc has no warning for a missing
brief.
**Check:** script: for each `/*! ... */` block matching
`\\(class|struct|union|namespace|headerfile|qmltype|qmlvaluetype|page|example|module|qmlmodule|group)[[:space:]]`,
flag it if it has no `\\brief[[:space:]]`.
- ❌ `/*! \class QFoo \inmodule QtCore */`
- ✅ `/*! \class QFoo \inmodule QtCore \brief The QFoo class stores a range. */`

### R15. Briefs end with a period
**Check:** Vale `Qt.Structure.QDocBrief` (inferred). QDoc:
`'\\brief' statement does not end with a full stop`.
- ❌ `\brief Returns the width`
- ✅ `\brief Returns the width.`

### R16. Class has `\inmodule`
**Check:** QDoc: `has no \\inmodule command`. (`\since` comes from git
history; see skill-language-style R16.)
- ❌ `/*! \class QFoo \brief ... */`
- ✅ `/*! \class QFoo \inmodule QtCore \brief ... */`

## Examples and images

### R20. Example page elements
**Check:** script: in the file with `\\example[[:space:]]`, each required
command from skill-language-style R20 is present, including `\\title`,
`\\brief`, `\\examplecategory`, and `\\image`.
- ❌ `\example gauge` `\title Gauge` (no `\brief`, no `\examplecategory`)
- ✅ `\example gauge` `\title Gauge` `\brief Shows a gauge.` `\examplecategory {User Interface Components}` `\image gauge.webp {Gauge at 40 percent}`

### R21. Example code builds clean
**Check:** build log regex `warning:`; `qmllint` exits 0.
- ❌ `main.cpp:12: warning: unused variable 'w'`
- ✅ No `warning:` lines; `qmllint Main.qml` exits 0.

### R22. Screenshot size
At least 440 x 320; icons at least 64 x 64.
**Check:** `identify -format '%w %h' <image>`.
- ❌ `320 240`
- ✅ `880 640`

### R23. Example titles
**Check:** Vale `Qt.Structure.ExampleTitleRepetition`.
- ❌ `\title Qt Quick Example: Button Example`
- ✅ `\title Button`

### R24. Alt text format
Capital first letter; no final period.
**Check:** Vale `Qt.Structure.AltTextFormat`.
- ❌ `\image toolbar.png {toolbar with dark mode toggle.}`
- ✅ `\image toolbar.png {Toolbar with dark mode toggle}`

### R26. Alt text terms
Generic lowercase UI terms, not Qt class names.
**Check:** Vale `Qt.Structure.AltTextClassNames`.
- ❌ `{Dialog with a PushButton and a CheckBox}`
- ✅ `{Dialog with a button and a check box}`

## QDoc formatting

### R39. No space before brace
**Check:** Vale `Qt.Structure.NoSpaceBeforeBrace`.
- ❌ See `\l {QWidget}`.
- ✅ See `\l{QWidget}`.

### R40. 80 columns
Table rows included.
**Check:** Vale `Qt.Mechanics.LineLength` (inferred); `awk 'length > 80'`.
- ❌ a 95-character `\li` line
- ✅ the same line wrapped at 80

### R41. `\sa` targets resolve
**Check:** QDoc: `Can't link to '`.
- ❌ `\sa setWidht()`
- ✅ `\sa setWidth()`

### R68. Dashes
No em dash as a connector. Which punctuation to use instead: G22.
**Check:** Vale `Microsoft.Dashes`; regex `—`.
- ❌ The model — which is shared — updates the view.
- ✅ The model, which is shared, updates the view.

## UI

### R43. Keyboard shortcuts
**Check:** Vale `Qt.Structure.KeyboardShortcutFormat`.
- ❌ Press Control+B or Ctrl + B.
- ✅ Press `Ctrl+B` (`Cmd+B` on macOS).

## Linking

R45, R48, R49, R50, and R60 share one check: QDoc reports
`Can't link to '<target>'`. The samples show the usual cause for each.

### R45. `\l` syntax
- ❌ `\l QWidget{the widget}`
- ✅ `\l{QWidget}{the widget}`

### R47. Section links
**Check:** Vale `Qt.Structure.SectionLinkAntiPattern`.
- ❌ `\l{qcolor.html#the-hsv-color-model}`
- ✅ `\l{QColor#The HSV Color Model}`

### R48. External page links
Target matches the `\externalpage` `\title` exactly.
- ❌ `\l{Qt Wiki Writing Guidelines}` (title is "Qt Writing Guidelines")
- ✅ `\l{Qt Writing Guidelines}`

### R49. QML cross-module links
- ❌ `\l QtQuick.Controls.ToolTip.delay`
- ✅ `\l{QtQuick.Controls::ToolTip::delay}`

### R50. QML value type case
- ❌ `\l{GeoCoordinate::latitude}`
- ✅ `\l{geoCoordinate::latitude}`

### R51. Generic QML types
**Check:** Vale `Qt.Structure.QMLGenericTypes`.
- ❌ `\qmlmethod QObject* Instantiator::objectAt(int index)`
- ✅ `\qmlmethod object Instantiator::objectAt(int index)`

### R60. Cross-module linking
- ❌ `\l{QNetworkReply}` from a module whose qdocconf lacks `qtnetwork`
- ✅ the same link, with `depends += qtnetwork` (see R61)

## Lists and tables

### R52. List length
**Check:** script: count `\\li` between `\\list` and `\\endlist`; flag
1 or more than 7.
- ❌ `\list` `\li The widget` `\endlist`
- ✅ The function takes the widget.

### R53. List punctuation
**Check:** Vale `Qt.Structure.ListItemPunctuation`, `Microsoft.Semicolon`.
- ❌ `\li The width, and`
- ✅ `\li The width`

### R55. Empty table cells
**Check:** Vale `Qt.Structure.TableEmptyCell`. "Notes" columns are exempt.
- ❌ `\row \li height \li`
- ✅ `\row \li height \li None`

### R56. Table headers
**Check:** Vale `Qt.Structure.TableGenericHeaders`.
- ❌ `\header \li Name \li Value`
- ✅ `\header \li Property \li Default value`

## Module pages

### R58. Module landing page
**Check:** Vale `Qt.Structure.ModuleExamplesSection`,
`Qt.Structure.ModuleReferenceSection`.
- ❌ `\page qtfoo-index.html` `\title Qt Foo` (no Examples or Reference section)
- ✅ ... `\section1 Examples` ... `\section1 Reference` ...

### R59. Example group
**Check:** Vale `Qt.Structure.ExampleGroupIngroup`.
- ❌ `\group qtfoo_examples` `\title Qt Foo Examples`
- ✅ `\group qtfoo_examples` `\ingroup all-examples` `\title Qt Foo Examples`

### R61. qdocconf dependencies
**Check:** QDoc: `Can't link to '`; qdocconf regex
`^depends[[:space:]]*\+=` lists every linked module.
- ❌ links to QtNetwork types; `depends += qtcore`
- ✅ `depends += qtcore qtnetwork`

### R62. Module review checklist
**Check:** composite: R58, R59, R61, and R15 on the landing page.
- ✅ one report line per item, each with its tool output
