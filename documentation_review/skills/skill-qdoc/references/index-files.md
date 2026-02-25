# Index Files and Cross-Module Dependencies

## Index Files (.index)

Index files are XML files enabling **cross-module documentation linking**.

### Build Output Location

**Index files are QDoc build outputs** - they are generated during documentation builds and are NOT checked into git. They are **never published online** (doc.qt.io does not serve .index files).

**Location is determined by qdocconf variables:**

```qdocconf
outputdir           # Base output directory
project             # Module name (e.g., "QtCore")
HTML.nosubdirs      # If true, use single shared directory
HTML.outputsubdir   # Subdirectory when nosubdirs=true (default: "html")
```

#### Path Construction (config.cpp:585-603)

```cpp
QString outputDir = config.outputdir;

if (singleexec)
    outputDir += "/" + project.toLower();

if (HTML.nosubdirs)
    outputDir += "/" + HTML.outputsubdir;

// Index file: outputDir + "/" + project.toLower() + ".index"
```

#### Modular Build - Separate Directories

When `HTML.nosubdirs` is not set (default), each module outputs to its own directory:

```
{outputdir}/{project}.index
{outputdir}/*.html
```

**To find index files locally:**
```bash
# Search for index files in the build tree
find . -name "*.index" -type f 2>/dev/null
```

#### Singular Build - Single Directory

When `HTML.nosubdirs = true` (online config), all modules share one directory:

```
{outputdir}/{HTML.outputsubdir}/*.index
{outputdir}/{HTML.outputsubdir}/*.html
```

#### Online Availability

Index files are published on **doc-snapshots.qt.io only** (not doc.qt.io).

**URL pattern:**
```
https://doc-snapshots.qt.io/{product-branch}/{module}.index
```

**Qt Framework:**

| Branch | URL Path | Example Index URL |
|--------|----------|-------------------|
| dev (next+1) | `qt6-dev/` | `qt6-dev/qtcore.index` |
| 6.11 (next release) | `qt6-6.11/` | `qt6-6.11/qtquick.index` |
| 6.10 (current) | `qt6-6.10/` | `qt6-6.10/qtwidgets.index` |
| 6.8 (LTS) | `qt6-6.8/` | `qt6-6.8/qtnetwork.index` |

**Other Qt Products:**

| Product | URL Path | Index File | Notes |
|---------|----------|------------|-------|
| Qt Creator | `qtcreator-master/` | `qtcreator.index` | IDE |
| Qt Design Studio | `qtdesignstudio/` | `qtdesignstudio.index` | UI design tool |
| Qbs | `qbs-master/` | `qbs.index` | Build system |
| Qt for Python | `qtforpython-dev/` | varies | PySide6 |
| Qt for MCUs | `qtformcus-{version}/` | not published | Embedded MCU |

**Examples:**
```
# Qt Framework modules
https://doc-snapshots.qt.io/qt6-dev/qtcore.index
https://doc-snapshots.qt.io/qt6-6.11/qtquick.index
https://doc-snapshots.qt.io/qt6-6.8/qtwidgets.index

# Qt Creator
https://doc-snapshots.qt.io/qtcreator-master/qtcreator.index

# Qt Design Studio
https://doc-snapshots.qt.io/qtdesignstudio/qtdesignstudio.index
```

**To fetch an index file for verification:**
```bash
curl -s https://doc-snapshots.qt.io/qt6-dev/qtcore.index | head -20
```

**Using WebFetch (no local build required):**
```
URL: https://doc-snapshots.qt.io/qt6-dev/qtcore.index
Prompt: "Search for name='QString' and show href and status attributes"
```

This allows verifying link targets without a local documentation build.

### Building Index Files

**Two build modes exist:**

#### Modular Build (Dual Execution)

Default mode for local development. Each module builds separately:

```bash
# Build specific module docs (two-phase: prepare then generate)
ninja html_docs_QtCore
ninja html_docs_QtNetwork

# Build just one module (faster)
cd qtbase && ninja html_docs_qtcore
```

**Behavior:**
- QDoc runs `--prepare` then `--generate` for each module
- Cross-module links require **pre-built index files** from dependencies
- Warnings about missing types in other modules are **expected** if those modules aren't built

**Output structure - separate directories:**

The offline config (`qt-module-defaults-offline.qdocconf`) uses default subdirectories.
Each module's `outputdir` setting determines its location:

```
{outputdir}/
├── {project}.index
├── {project}.html files
└── ...
```

Cross-module links use the `url` attribute from index files to construct paths.

#### Singular Build (Single Execution)

Used for doc.qt.io and CI. All modules build together:

```bash
# Build all docs (single-exec mode internally)
ninja docs
```

**Behavior:**
- QDoc uses `--single-exec` with a master qdocconf listing all modules
- Phase 1: Prepare ALL modules (generates all index files in memory)
- Phase 2: Generate ALL modules (all cross-module links resolve)
- **All cross-Qt link warnings are real errors** (no missing dependencies)

**Output structure - single directory:**

The online config (`qt-module-defaults-online.qdocconf`) sets:
```qdocconf
HTML.nosubdirs = "true"
HTML.outputsubdir = "../html"
```

All output from all modules goes to ONE shared directory:
```
{outputdir}/{HTML.outputsubdir}/
├── qtcore.index
├── qtgui.index
├── qstring.html        (from QtCore)
├── qwidget.html        (from QtWidgets)
├── qml-qtquick-rectangle.html  (from QtQuick)
└── ...all modules together
```

This is why doc.qt.io URLs are flat: `doc.qt.io/qt-6/qstring.html` (no module subdirectory).

#### Which mode am I in?

| Command | Mode | Cross-module warnings |
|---------|------|----------------------|
| `ninja html_docs_<Module>` | Modular | Expected if deps not built |
| `ninja docs` | Singular | Real errors |
| CI doc build | Singular | Real errors |

### Searching Index Files

Use grep to verify link targets exist:

```bash
# Find a class
grep 'class name="QString"' qtbase/doc/qtcore/qtcore.index

# Find a function (check if documented)
grep 'name="globalSeed"' qtbase/doc/qtcore/qtcore.index

# Find a QML type
grep 'qmlclass name="Rectangle"' qtdeclarative/doc/qtquick/qtquick.index

# Find a page by title
grep 'title="Getting Started"' */doc/*/*.index

# Find any target by name
grep -r 'name="targetName"' */doc/*/*.index
```

**If a target is NOT in the index file:**
- The function/class may lack `\fn` or `\class` command
- The entity may be marked `\internal`
- The documentation may not have been built yet

### Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE QDOCINDEX>
<INDEX url="https://doc.qt.io/qt-6"
       title="Qt Core Reference Documentation"
       version="6.8.0"
       project="QtCore"
       indexTitle="Qt Core">
    <namespace name="" status="active" access="public" module="qtcore">
        <!-- All documented entities -->
    </namespace>
</INDEX>
```

### Root Attributes

| Attribute | Purpose |
|-----------|---------|
| `url` | Base URL for constructing links |
| `project` | Module name, determines filename (`QtCore` → `qtcore.index`) |
| `version` | Qt version for compatibility |
| `title` | Human-readable documentation title |

### Node Elements

**Classes:**
```xml
<class name="QString"
       fullname="QString"
       href="qstring.html"
       status="active"
       access="public"
       location="qstring.h"
       since="1.0"
       documented="true"
       module="QtCore"
       bases="QByteArrayView"
       brief="The QString class provides a Unicode character string.">
    <function name="length" ... />
    <target name="implicit-sharing"/>
</class>
```

**Functions:**
```xml
<function name="qDebug"
          href="qtlogging.html#qDebug"
          status="active"
          meta="macrowithparams"
          signature="qDebug(const char *message, ...)"
          type="void">
    <parameter type="const char *" name="message"/>
</function>
```

**QML Types:**
```xml
<qmlclass name="Rectangle"
          href="qml-qtquick-rectangle.html"
          qml-module-name="QtQuick"
          qml-module-version="2.15"
          qml-base-type="Item">
    <qmlproperty name="color" type="color" writable="true"/>
</qmlclass>
```

**Pages:**
```xml
<page name="containers.html"
      href="containers.html"
      subtype="page"
      title="Container Classes"
      location="containers.qdoc">
    <contents name="the-container-classes" title="The Container Classes" level="1"/>
    <target name="java-style-iterators"/>
    <keyword name="container"/>
</page>
```

### Common Attributes

| Attribute | Description |
|-----------|-------------|
| `name` | Entity identifier |
| `fullname` | Fully-qualified name |
| `href` | Relative path to HTML file |
| `status` | `active`, `deprecated`, `preliminary`, `internal` |
| `access` | `public`, `protected`, `private` |
| `documented` | Whether entity has documentation |
| `location` | Source file (when `locationinfo=true`) |
| `since` | Version introduced |
| `module` | Owning module name |
| `brief` | Brief description text |

---

## Cross-Module Dependencies

### The `depends` Variable

```qdocconf
# Explicit dependencies
depends = QtCore QtGui QtWidgets

# All available modules (wildcard)
depends = *
```

### The `indexes` Variable

Alternative - direct paths to index files:

```qdocconf
indexes = /path/to/qtcore.index \
          /path/to/qtgui.index
```

### Resolution Process

1. QDoc reads `depends` from .qdocconf
2. Searches paths from `-indexdir` command-line option
3. Looks for `<module>/<module>.index` in each indexdir
4. If multiple index files exist, uses most recently modified
5. Creates an "index tree" for each dependency
6. When resolving `\l{target}`, searches primary tree first, then index trees

### URL Construction

Cross-module links are constructed from the index file's `url` attribute (set via qdocconf):

```qdocconf
url = https://doc.qt.io/qt-6   # For online builds
url = ../qtcore                 # For local builds (relative paths)
```

```
Final URL = INDEX@url + "/" + element@href
```

**Examples:**
```
# Online config
url="https://doc.qt.io/qt-6" + "/" + "qstring.html"
= https://doc.qt.io/qt-6/qstring.html

# Local config with relative paths
url="../qtcore" + "/" + "qstring.html"
= ../qtcore/qstring.html
```

The `url` attribute in each module's index file determines how cross-references resolve. This is configured in the module's qdocconf, not hardcoded.
