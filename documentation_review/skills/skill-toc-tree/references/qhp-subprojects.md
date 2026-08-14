# QHP Subprojects Reference

**Verified against:** QDoc manual
(`qttools/src/qdoc/qdoc/doc/qdoc-manual-qdocconf.qdoc:1592-1615`,
`:1868-2023`), `helpprojectwriter.cpp`, and live qdocconf files in
qtbase, qtdeclarative, and qtmultimedia (dev, 2026-08).

## Project-Level Properties

```
qhp.projects                   = QtCore
qhp.QtCore.file                = qtcore.qhp
qhp.QtCore.namespace           = org.qt-project.qtcore.$QT_VERSION_TAG
qhp.QtCore.virtualFolder       = qtcore
qhp.QtCore.indexTitle          = Qt Core
qhp.QtCore.indexRoot           =
```

| Property | Meaning |
|----------|---------|
| `file` | Output `.qhp` filename |
| `namespace` | Unique help namespace |
| `virtualFolder` | Folder name inside the help collection |
| `indexTitle` | Title of the page that acts as the module's root topic |
| `indexRoot` | Root path for the index (normally empty) |

Since QDoc 6.6, `qhp = true` at the top level makes QDoc warn when a
project defines no `qhp.projects` — used by Qt's shared top-level
qdocconf to catch unconfigured modules.

## Subprojects — Branches of the Module Tree

```
qhp.QtQuick.subprojects = manual examples qmltypes classes
```

**Item order is significant: it is the order of the branches in the
tree.** Above: manually combined nodes first, then selector-generated
examples, then QML types, then the C++ API.

A subproject block that is defined but **not listed** in the
`subprojects` value is silently ignored (live example: qtdoc defines
`qhp.QtDoc.subprojects.examples.*` but lists only `manual`).

Per-subproject properties:

| Property | Meaning |
|----------|---------|
| `title` | Branch label in the tree |
| `indexTitle` | Page `\title` acting as the branch's root topic |
| `selectors` | Page types collected automatically (see below) |
| `sortPages` | `true` = alphabetical order |
| `type` | `manual` = build the branch from the indexTitle page's `\list` |

A missing/mistyped `indexTitle` warns:
`Failed to find <prefix>.indexTitle '<T>'`, where `<prefix>` is the
full qdocconf path (e.g. `qhp.QtCore.subprojects.manual`).

## `type = manual` — the Hand-Built Branch

```
qhp.QtCore.subprojects.manual.title = Qt Core
qhp.QtCore.subprojects.manual.indexTitle = Qt Core module topics
qhp.QtCore.subprojects.manual.type = manual
```

QDoc walks the `\list` on the `indexTitle` page and mirrors its
structure as the branch contents (`helpprojectwriter.cpp:635-711`).
This is the same page named in `navigation.toctitles` — see
`references/toc-page.md`.

## Selectors — the Automatic Branches

From the manual: multiple selectors can be listed, separated by
whitespace. **If a subproject defines no `selectors`, all pages in the
project are included.**

| Selector | Description |
|----------|-------------|
| `namespace` | Namespaces |
| `class` | Classes |
| `example` | Examples |
| `externalpage` | External page entries |
| `function` | Functions |
| `headerfile` | Header files |
| `page` | Overview pages |
| `property` | C++ properties |
| `typedef` | C++ typedef types |
| `typealias` | C++ type aliases |
| `variable` | C++ variables |
| `qmlproperty` | QML properties |
| `qmltype` | QML types |
| `qmlvaluetype` | QML value types |
| `module[:name]` | C++ modules, or members of the named module |
| `qmlmodule[:name]` | QML modules, or members of the named module |
| `group[:groupname]` | Pages in the named group(s), comma-separated |
| `none` | Selects nothing; only a link to the `indexTitle` is generated (QDoc 6.9+) |

Legacy selector spellings survive in shipped configs and still work:
`fake:headerfile` (qtcore), `qmlclass`, `doc:headerfile` (qtquick).
Use the documented forms (`headerfile`, `qmltype`) in new configs.

## Worked Examples

**Full-size module** — `qtdeclarative/src/quick/doc/qtquick.qdocconf`:

```
qhp.QtQuick.subprojects = manual examples qmltypes classes

qhp.QtQuick.subprojects.manual.title = Qt Quick
qhp.QtQuick.subprojects.manual.indexTitle = Qt Quick module topics
qhp.QtQuick.subprojects.manual.type = manual

qhp.QtQuick.subprojects.examples.title = Examples
qhp.QtQuick.subprojects.examples.indexTitle = Qt Quick Examples and Tutorials
qhp.QtQuick.subprojects.examples.selectors = example
qhp.QtQuick.subprojects.examples.sortPages = true

qhp.QtQuick.subprojects.qmltypes.title = QML Types
qhp.QtQuick.subprojects.qmltypes.indexTitle = Qt Quick QML Types
qhp.QtQuick.subprojects.qmltypes.selectors = qmlclass
qhp.QtQuick.subprojects.qmltypes.sortPages = true
```

**Branch variety** (qtdeclarative): QtQmlCore uses
`permissions qmltypes`; QtQmlTest uses `qmltypes classes concepts`;
several QML-only modules use just `qmltypes`.

**Small module — single-topic subproject** —
`qtmultimedia/src/spatialaudio/doc/qtspatialaudio.qdocconf`:

```
qhp.QtSpatialAudio.subprojects = overview examples classes qmltypes

qhp.QtSpatialAudio.subprojects.overview.title = Overview
qhp.QtSpatialAudio.subprojects.overview.indexTitle = Spatial Audio Overview
qhp.QtSpatialAudio.subprojects.overview.selectors = group:none
```

A subproject whose selectors match nothing contributes a single tree
entry: the `indexTitle` page. `group:none` (a group that does not
exist) is the pre-6.9 idiom; since QDoc 6.9 use the documented
`selectors = none`. QtSpatialAudio has no `manual` subproject and no
`navigation.toctitles` — the pattern for modules with only one or two
doc topics.

## Version History

- **v1.0** (2026-08-14): Initial version
