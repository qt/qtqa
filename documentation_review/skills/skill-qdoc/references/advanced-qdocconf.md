# Advanced qdocconf Reference

**Verified against:** QDoc manual (doc.qt.io/qt-6) and 268
qdocconf files in qt5 super-repo.

## qdocconf Syntax

### Assignment

```qdocconf
variable = value              # Set
variable += value             # Append
```

### Multi-line

```qdocconf
variable = value1 \
           value2 \
           value3
```

### Quoting

Double quotes for values with special characters:
```qdocconf
description = "Qt Core Reference Documentation"
```

### Comments

```qdocconf
# This is a comment
```

### Variable expansion

```qdocconf
$ENVVAR                       # Environment variable
${ENVVAR}                     # Same, braced form
```

### Brace expansion

Set same value for multiple variables:
```qdocconf
{headerdirs,sourcedirs} += ../include
```

Also used for complex multi-variable assignments:
```qdocconf
{HTML.extraimages,qhp.QtQuick.extraFiles} += images/file.jpg
```

### File inclusion

```qdocconf
include($QT_INSTALL_DOCS/global/qt-module-defaults.qdocconf)
```

---

## Global Include Chain

Every module qdocconf starts with:
```qdocconf
include($QT_INSTALL_DOCS/global/qt-module-defaults.qdocconf)
```

This loads the following chain:

```
qt-module-defaults.qdocconf
  -> qt-module-defaults-offline.qdocconf
       -> macros.qdocconf
            -> grid.qdocconf
            -> cpp-doc-macros.qdocconf
       -> qt-cpp-defines.qdocconf
       -> compat.qdocconf
       -> manifest-meta.qdocconf
       -> fileextensions.qdocconf
       -> qt-html-templates-offline.qdocconf
       -> config.qdocconf
```

All global files live in `qtbase/doc/global/`.

---

## Mandatory Variables

These appear in **every** module qdocconf:

| Variable | Example | Purpose |
|----------|---------|---------|
| `project` | `QtCore` | Module name, determines index filename |
| `description` | `Qt Core Reference Documentation` | Human-readable description |
| `version` | `$QT_VERSION` | Always from env var |
| `qhp.projects` | `QtCore` | Must match `project` |
| `qhp.<ID>.file` | `qtcore.qhp` | Lowercase module |
| `qhp.<ID>.namespace` | `org.qt-project.qtcore.$QT_VERSION_TAG` | Standard pattern |
| `qhp.<ID>.virtualFolder` | `qtcore` | Lowercase module |
| `qhp.<ID>.indexTitle` | `Qt Core` | Human-readable |
| `qhp.<ID>.indexRoot` | (empty) | Always empty |
| `qhp.<ID>.subprojects` | `manual examples classes` | Space-separated |
| `depends` | Module list or `*` | Cross-module linking |
| `imagedirs` | `images` | Almost always just `images` |
| `navigation.landingpage` | `"Qt Core"` | Module name quoted |
| `navigation.toctitles` | `"Qt Core module topics"` | Pattern: `"{Name} module topics"` |
| `warninglimit` | `0` | CI enforcement (0 = no warnings allowed) |

---

## Common Variables

| Variable | When Used | Example |
|----------|-----------|---------|
| `examplesinstallpath` | Modules with examples | `network` |
| `moduleheader` | Default header differs | `QtCoreDoc` |
| `tagfile` | Most modules | `../../qtcore/qtcore.tags` |
| `url.sources.rootdir` | Enable source links | `../../src` |
| `navigation.cppclassespage` | C++ modules | `"Qt Core C++ Classes"` |
| `navigation.qmltypespage` | QML modules | `"Qt Quick QML Types"` |
| `excludedirs` | Exclude paths | `snippets` |

---

## Macro System

### Three tiers

**Tier 1 — Global macros** (`macros.qdocconf`):
- Character entities: `macro.aacute.HTML = "&aacute;"`
- Product abbreviations: `macro.QC = "Qt Creator"`,
  `macro.QDS = "Qt Design Studio"`
- Platform versions: `macro.NdkVer = "r27c"`
- Layout helpers: `macro.borderedimage`,
  `macro.beginfloatleft.HTML`
- YouTube embedding: `macro.youtube.HTML = "<div...>"`

**Tier 2 — C++ doc macros** (`cpp-doc-macros.qdocconf`):
- `macro.memberswap` — standardized swap() documentation
- `macro.qhash` / `macro.qhashT` — qHash() documentation

**Tier 3 — Module-specific macros** (in module qdocconf):
- `macro.gRPC = "\\tm gRPC"` (qtgrpc)
- `macro.QQEM = "Qt Quick Effect Maker"` (qtquick)
- `macro.ffmpegversion = "7.1.3"` (qtmultimedia)

### Macro syntax

**Simple text replacement:**
```qdocconf
macro.QC = "Qt Creator"
```
Usage: `\QC` produces "Qt Creator"

**With arguments:**
```qdocconf
macro.cmakecommandsince = "\n\nThis command was introduced in Qt \1.\n\n"
```
Usage: `\cmakecommandsince{6.5}` produces paragraph with "Qt 6.5"

**Format-specific:**
```qdocconf
macro.youtube.HTML = "<div class=\"video\">...</div>"
```
Only renders in HTML output, not DocBook.

**Regex extraction:**
```qdocconf
{macro.QtMajorVersion,macro.QtMinorVersion} = "$QT_VER"
macro.QtMajorVersion.match = "^(\\d+)\\."
macro.QtMinorVersion.match = "\\d+\\.(\\d+)"
```
Extracts parts of a version string. Captures group 1.

**Macro composition:**
```qdocconf
macro.qhashT = "\\qhash{\1}\\implqhashT{\2}"
```
One macro calls another. Not officially documented but works.

---

## QHP Configuration

Qt Help Project configuration for Qt Assistant.

### Standard structure

```qdocconf
qhp.projects = QtCore
qhp.QtCore.file = qtcore.qhp
qhp.QtCore.namespace = org.qt-project.qtcore.$QT_VERSION_TAG
qhp.QtCore.virtualFolder = qtcore
qhp.QtCore.indexTitle = Qt Core
qhp.QtCore.indexRoot =
```

### Subprojects

```qdocconf
qhp.QtCore.subprojects = manual examples classes

qhp.QtCore.subprojects.manual.title = Qt Core
qhp.QtCore.subprojects.manual.indexTitle = Qt Core module topics
qhp.QtCore.subprojects.manual.type = manual

qhp.QtCore.subprojects.examples.title = Examples
qhp.QtCore.subprojects.examples.indexTitle = Qt Core Examples
qhp.QtCore.subprojects.examples.selectors = example
qhp.QtCore.subprojects.examples.sortPages = true

qhp.QtCore.subprojects.classes.title = C++ Classes
qhp.QtCore.subprojects.classes.indexTitle = Qt Core C++ Classes
qhp.QtCore.subprojects.classes.selectors = class fake:headerfile
qhp.QtCore.subprojects.classes.sortPages = true
```

For QML modules, add:
```qdocconf
qhp.QtQuick.subprojects = manual examples qmltypes classes

qhp.QtQuick.subprojects.qmltypes.title = QML Types
qhp.QtQuick.subprojects.qmltypes.indexTitle = Qt Quick QML Types
qhp.QtQuick.subprojects.qmltypes.selectors = qmlclass
qhp.QtQuick.subprojects.qmltypes.sortPages = true
```

Subproject/tree semantics (branch order, `type = manual`, the TOC
page, selectors) are owned by
`skill-toc-tree/references/qhp-subprojects.md` — read it before
editing subprojects.

### Selectors

| Selector | Matches |
|----------|---------|
| `class` | C++ classes |
| `qmlclass` | QML types |
| `example` | Examples |
| `doc:headerfile` | Header file docs |
| `doc:page` | Standalone pages |
| `fake:headerfile` | Legacy synonym for `doc:headerfile` |
| `fake:example` | Legacy synonym for `example` |
| `module[:name]` | C++ module |
| `qmlmodule[:name]` | QML module |
| `group[:name]` | Named group |
| `none` | Nothing |

**Discrepancy:** Official docs use `doc:` prefix. Codebase uses
both `doc:` and `fake:` (legacy). Both work. Prefer `doc:` for
new configs.

---

## Path Variables

### Source and header directories

```qdocconf
headerdirs += ../../include/modulename \
              ..

sourcedirs += .. \
              ../../include/modulename
```

Paths are relative to the qdocconf file location.

### Image directories

```qdocconf
imagedirs += images
```

Almost always just `images`. The directory is relative to the
qdocconf file.

### Example directories

```qdocconf
exampledirs += ../../examples/modulename \
               snippets
```

### Excludes

```qdocconf
excludedirs += snippets
excludefiles += ../../include/modulename/private/*.h
```

---

## Warning Control

```qdocconf
# Maximum allowed warnings (0 = none allowed)
warninglimit = 0

# Suppress specific warnings
spurious += "Cannot find file to quote from.*"
spurious += "Undocumented parameter.*"
```

`warninglimit` is enforced by CI. Most modules set it to `0`.

---

## Complete Minimal Example

A minimal qdocconf for a new module:

```qdocconf
include($QT_INSTALL_DOCS/global/qt-module-defaults.qdocconf)

project     = QtNewModule
description = Qt New Module Reference Documentation
version     = $QT_VERSION
# Note: url is set globally by the include chain (config.qdocconf),
# not per-module. Do NOT set url here.

qhp.projects                       = QtNewModule
qhp.QtNewModule.file               = qtnewmodule.qhp
qhp.QtNewModule.namespace          = org.qt-project.qtnewmodule.$QT_VERSION_TAG
qhp.QtNewModule.virtualFolder      = qtnewmodule
qhp.QtNewModule.indexTitle         = Qt New Module
qhp.QtNewModule.indexRoot          =
qhp.QtNewModule.subprojects        = manual examples classes
qhp.QtNewModule.subprojects.manual.title = Qt New Module
qhp.QtNewModule.subprojects.manual.indexTitle = Qt New Module
qhp.QtNewModule.subprojects.manual.type = manual
qhp.QtNewModule.subprojects.examples.title = Examples
qhp.QtNewModule.subprojects.examples.indexTitle = Qt New Module Examples
qhp.QtNewModule.subprojects.examples.selectors = example
qhp.QtNewModule.subprojects.examples.sortPages = true
qhp.QtNewModule.subprojects.classes.title = C++ Classes
qhp.QtNewModule.subprojects.classes.indexTitle = Qt New Module C++ Classes
qhp.QtNewModule.subprojects.classes.selectors = class doc:headerfile
qhp.QtNewModule.subprojects.classes.sortPages = true

depends += qtcore qtgui

headerdirs += ../../include/qtnewmodule
sourcedirs += .. ../../include/qtnewmodule
imagedirs  += images
exampledirs += ../../examples/newmodule

examplesinstallpath = newmodule

navigation.landingpage  = "Qt New Module"
navigation.cppclassespage = "Qt New Module C++ Classes"
navigation.toctitles = "Qt New Module module topics"
navigation.toctitles.inclusive = false

warninglimit = 0
```

---

## Version History

- **v1.0** (2026-03-26): Initial version from audit of 268
  qdocconf files, global macro system, and QHP configurations
