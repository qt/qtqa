# Link Resolution and Target System

## Link Resolution

### The `\l` Command Flow

```
\l{QWidget::setGeometry}
        ↓
Parse target → ["QWidget", "setGeometry"]
        ↓
findNodeForAtom() called
        ↓
Search all trees in order
        ↓
Found: ClassNode(QWidget) → FunctionNode(setGeometry)
        ↓
Generate HTML link with anchor
```

### Link Syntax

```cpp
\l{target}                    // Basic link
\l{target}{display text}      // Custom display text
\l [QML]{target}              // Force QML genus
\l [CPP QtCore]{target}       // Force C++ in specific module
```

### Whitespace Handling

**Space before brace**: The parser skips whitespace before parsing arguments, so
`\l{target}` and `\l {target}` are parsed identically. Prefer no space for compactness.

**Source**: `docparser.cpp:2377` - `getArgument()` calls `skipSpacesOrOneEndl()` first.

**Whitespace inside braces**: Arguments are normalized via `.simplified()`:
- Leading/trailing whitespace removed
- Internal whitespace collapsed to single spaces

```cpp
\l{  Getting   Started  }  →  "Getting Started"
```

**Page title matching**: Titles containing spaces are further normalized via
`asAsciiPrintable()` (tree.cpp:1016-1017, 1061-1064):
- Converts to lowercase
- Keeps only alphanumeric characters (a-z, 0-9)
- Replaces all other characters with hyphens
- Collapses multiple hyphens

| Link Target | Normalized Key | Matches |
|-------------|----------------|---------|
| `\l{Getting Started with Qt}` | `getting-started-with-qt` | ✓ |
| `\l{GETTING STARTED WITH QT}` | `getting-started-with-qt` | ✓ |
| `\l{Getting  Started  with  Qt}` | `getting-started-with-qt` | ✓ |

**Implication**: Whitespace and case variations in page title links are tolerated,
but exact matches are recommended for clarity and maintainability.

### Target Types

| Target Format | Resolves To |
|---------------|-------------|
| `ClassName` | Class documentation page |
| `ClassName::member` | Member within class |
| `ClassName#Section Title` | Section within class documentation |
| `QmlType#Section Title` | Section within QML type documentation |
| `function()` | Function (may be ambiguous) |
| `page-name.html` | Documentation page (explicit `\page` only) |
| `#anchor` | Anchor on current page |
| `page.html#anchor` | Anchor on explicit `\page` page (NOT type pages) |
| `Page Title` | Page with matching `\title` |
| `External Page Title` | External page with matching `\title` |
| `{Module::QmlType}` | QML type (cross-module) |
| `{Module::QmlType::property}` | QML property (cross-module) |

### QML Cross-Module Links

For linking to QML types and properties from other modules, use the fully qualified path with `::` as the separator:

```cpp
{Module.Submodule::Type}              // QML type
{Module.Submodule::Type::property}    // QML property
{Module.Submodule::Type::method()}    // QML method
```

**Examples:**
```cpp
\l {QtQuick.Controls::ToolTip}              // Link to ToolTip type
\l {QtQuick.Controls::ToolTip::delay}       // Link to delay property
\sa QWidget::toolTip, {QtQuick.Controls::ToolTip::delay}  // In \sa (no \l needed)
```

**Key points:**
- Use `::` between module and type, and between type and member
- Module names use dots internally (`QtQuick.Controls`) but `::` for scoping
- Braces `{}` required when target contains `.` characters
- In `\sa`, braces alone work (no `\l` prefix needed)

### Section Links Within Type Documentation

To link to a section (`\section1`, `\section2`, etc.) within a C++ class or QML type's
documentation, use the `TypeName#Section Title` syntax:

```cpp
\l{QColor#The HSV Color Model}                    // C++ class section
\l{ListView#Reusing Items}                        // QML type section
\l{QRhi#Frame captures and performance profiling} // C++ class section
\l{QDialog#Modal Dialogs}{modal dialog}           // With display text
```

**Critical rules:**
- Section title must match **exactly** (case-sensitive)
- Use the type name, NOT the HTML filename

**Common mistake:**
```cpp
// WRONG - page.html#anchor doesn't work for auto-generated type pages
\l{qml-qtquick-listview.html#reusing-items}
\l{qcolor.html#the-hsv-color-model}

// CORRECT - use TypeName#Section Title
\l{ListView#Reusing Items}
\l{QColor#The HSV Color Model}
```

**Why this matters:** The `page.html#anchor` syntax only works for explicit `\page`
pages, not for auto-generated pages from `\class` or `\qmltype` commands.

**Finding the exact section title:**
```bash
# Search index file for section titles
grep 'title=".*keyword.*"' */doc/*/*.index
```

### QML Value Type Links (Case Sensitivity)

QML value types (`Q_GADGET` with `QML_VALUE_TYPE`) use **camelCase** (lowercase
first letter), while C++ classes and QML object types use **PascalCase**.

This is a common source of "Can't link to" warnings.

| C++ Class | QML Value Type | Correct Link |
|-----------|----------------|--------------|
| `WebEngineCertificateError` | `webEngineCertificateError` | `\l{webEngineCertificateError::defer()}` |
| `FullScreenRequest` | `fullScreenRequest` | `\l{fullScreenRequest::accept()}` |
| `GeoCoordinate` | `geoCoordinate` | `\l{geoCoordinate::latitude}` |
| `RegisterProtocolHandlerRequest` | `registerProtocolHandlerRequest` | `\l{registerProtocolHandlerRequest}` |

**Common error pattern:**
```
Can't link to 'WebEngineCertificateError::defer()'
```

**Diagnostic:** If "Can't link to 'PascalCaseType::member'" warning appears for
a QML type, search for `\qmlvaluetype` to check if it's a value type:

```bash
grep -r "\\\\qmlvaluetype" <module>/src/
```

If you find `\qmlvaluetype webEngineCertificateError`, the link must use the
lowercase form.

**Note:** QML object types (`QML_ELEMENT`) retain PascalCase:
- `\qmltype WebEngineView` → `\l{WebEngineView::url}`

### External Page Links

External pages define named targets for external URLs:

```qdoc
/*!
    \externalpage https://cmake.org/cmake/help/latest/
    \title CMake Documentation
*/
```

**Link syntax:** `\l{CMake Documentation}` → links to cmake.org

**Critical rule:** The link target must match the `\title` **exactly** after macro expansion.

| Definition | Correct Link | Incorrect Link |
|------------|--------------|----------------|
| `\title \QOI official releases` | `\l{\QOI official releases}` | `\l{Qt Online Installer}` |
| `\title Qt Creator Manual` | `\l{Qt Creator Manual}` | `\l{Qt Creator}` |

**Common mistake:** Linking to partial title or forgetting macro expansion.

### Page Title Links

Links can target any page by its `\title`:

```qdoc
/*!
    \page getting-started.html
    \title Getting Started with Qt
*/
```

**Link:** `\l{Getting Started with Qt}` → links to getting-started.html

### Autolinks

**Source:** `qttools/src/qdoc/qdoc/src/qdoc/docparser.cpp:1563-1639` (`isAutoLinkString()`)

QDoc automatically creates links for recognized C++ identifiers without requiring
explicit `\l` commands. Understanding autolink behavior prevents unnecessary markup
and ensures links resolve correctly.

#### What Autolinks (no `\l` needed)

| Pattern | Example | Result |
|---------|---------|--------|
| Class names | `QString` | Links to QString docs |
| Qualified names | `QFont::Bold` | Links to QFont::Bold enum value |
| Enum values | `Qt::AlignLeft` | Links to Qt::AlignLeft |
| Functions with `()` | `QString::isEmpty()` | Links to function docs |
| Nested types | `QList::iterator` | Links to nested type |

**Examples in prose:**
```qdoc
The weight can be QFont::Thin to QFont::Black.
// ✓ Both autolink - no \l needed

See QFont::HintingPreference for details.
// ✓ Autolinks to the enum

Call QString::trimmed() to remove whitespace.
// ✓ Autolinks to the function
```

#### What Does NOT Autolink (needs help)

| Pattern | Problem | Fix |
|---------|---------|-----|
| Bare method name | `trimmed()` | Add class: `QString::trimmed()` |
| QML properties with `.` | `font.kerning` | Use `\l {font::kerning}` |
| QML types (cross-module) | `ToolTip` | Use `\l {QtQuick.Controls::ToolTip}` |
| Page titles | `Getting Started` | Use `\l {Getting Started with Qt}` |
| Custom display text | any | Use `\l {target}{display text}` |

**Examples:**
```qdoc
// WRONG - bare method won't autolink
Use trimmed() to remove whitespace.

// CORRECT - qualified name autolinks
Use QString::trimmed() to remove whitespace.

// WRONG - dot separator doesn't resolve for QML properties
The \l font.kerning property controls kerning.

// CORRECT - use :: separator with \l
The \l {font::kerning} property controls kerning.
```

**Why `.` fails for QML links:**
QDoc's `findNodeForAtom()` (qdocdatabase.cpp:1528) splits link targets on `::`.
When you write `\l font.kerning`, QDoc gets `["font.kerning"]` as a single element
and can't find a node named "font.kerning". Using `\l {font::kerning}` gives
QDoc `["font", "kerning"]` which resolves correctly to the property.

#### Decision Tree: `\l` vs Autolink vs `\c`

```
Is it a C++ class, function, enum, or qualified name?
├─ YES → Let autolink handle it (no markup needed)
│        Example: QFont::Bold, QString::isEmpty()
│
├─ NO → Is it a QML property or type?
│       ├─ YES → Use \l {Type::property} with :: separator
│       │        Example: \l {font::kerning}, \l {Text::renderType}
│       │
│       └─ NO → Is it a page title or target?
│               ├─ YES → Use \l {title}
│               │        Example: \l {Getting Started with Qt}
│               │
│               └─ NO → Is it internal/private API?
│                       ├─ YES → Use \c (code format, no link)
│                       │        Example: \c{QPrivateClass::method()}
│                       │
│                       └─ NO → Use \l {target}
```

#### Suppressing Autolinks

Use `\c` to render as code without creating a link:

```qdoc
\c{QString}           // Renders as monospace "QString" without link
\c{QFont::Bold}       // Renders as code, no link
```

**When to suppress:**
- Internal/private APIs that have no public documentation
- Code literals that happen to match type names
- Deliberate stylistic choice (rare)

---

## Target System

### Creating Targets

```cpp
\target my-anchor
This section can be linked via \l{my-anchor}.

\keyword search-term
This keyword is searchable in Qt Assistant.
```

### Target Storage (TargetRec)

```cpp
struct TargetRec {
    Node *m_node;      // Owning node
    QString m_ref;     // Anchor fragment
    TargetType m_type; // Target, Keyword, Contents, ContentsKeyword
    int m_priority;    // Higher = preferred match
};
```

### Target Priority

1. Keywords (priority 1) - lowest
2. Explicit targets (priority 2)
3. Section contents (priority 3) - highest

---

## Resolution Pipeline

QDoc resolves documentation in phases:

### Phase 1: Preparing
1. `resolveBaseClasses()` - C++ inheritance
2. `resolvePropertyOverriddenFromPtrs()` - Property overrides
3. `resolveRelates()` - `\relates` associations
4. `normalizeOverloads()` - Group overloaded functions
5. `markDontDocumentNodes()` - Flag undocumented items
6. `removePrivateAndInternalBases()` - Filter private bases
7. `resolveProperties()` - Link properties to getters/setters
8. `resolveQmlInheritance()` - QML `\inherits`
9. `resolveTargets()` - Build target maps
10. `resolveCppToQmlLinks()` - `\nativetype` connections
11. `resolveSince()` - Version tracking

### Phase 2: Generating
- Emit HTML/DocBook with resolved links
- Warnings for unresolved references

---

## Diagnosing "Can't link to" Warnings

When QDoc reports `Can't link to 'X'`, follow this checklist **in order**:

### Step 1: Search for explicit targets
```bash
# Search for \target definitions
grep -r "\\\\target.*<keyword>" <module>/doc/

# Search for \keyword definitions
grep -r "\\\\keyword.*<keyword>" <module>/doc/
```

### Step 2: Search for page titles
```bash
# Search for page by title
grep -r "\\\\title.*<keyword>" <module>/doc/
```

### Step 3: Search for external pages
```bash
# Check central external-resources.qdoc
grep -r "externalpage.*<keyword>" qtdoc/doc/src/external-resources.qdoc

# Check module-specific external pages
grep -r "\\\\externalpage" <module>/doc/
```

### Step 4: Search for macros
```bash
# Check global macros
grep "macro\." qtbase/doc/global/macros.qdocconf
```

**Important:** Link targets must match `\title` **exactly after macro expansion**.

### Step 5: Search index files (for cross-module targets)

**Prerequisites:** Index files are **build artifacts** - they only exist after running
`ninja docs` or `ninja html_docs_<Module>`. They are NOT published online.

```bash
# First, check if index files exist
ls */doc/*/*.index 2>/dev/null || echo "No index files - docs not built"

# Find a class
grep 'name="ClassName"' */doc/*/*.index

# Find a function
grep 'name="functionName"' */doc/*/*.index

# Find a page by title
grep 'title="Page Title"' */doc/*/*.index

# Find any target
grep -r 'name="targetName"' */doc/*/*.index
```

**Index file location:** `<build-dir>/<module>/doc/<submodule>/<submodule>.index`

**If no index files exist:** Skip to Step 7 (web verification).

### Step 6: For internal/private APIs

If the target is in a private header (`_p.h`) or lacks public documentation, use `\c{}` instead of `\l{}` to render as code without attempting a link:

```qdoc
\c{QPlatformWindow::invalidateSurface()}
```

### Step 7: Verify via published docs (web fallback)

When local index files don't exist, use online resources.

#### Option A: Fetch Index Files from doc-snapshots.qt.io (PREFERRED)

Index files are published on **doc-snapshots.qt.io only** (not doc.qt.io):

```
https://doc-snapshots.qt.io/qt6-dev/{module}.index     # dev branch
https://doc-snapshots.qt.io/qt6-{major}.{minor}/{module}.index  # release branches
```

**Use WebFetch to search the index file:**
```
URL: https://doc-snapshots.qt.io/qt6-dev/qtcore.index
Prompt: "Search for name='QString' and show the href and status attributes"
```

This gives the same information as grepping local index files - you can verify:
- Target exists (`name` attribute)
- Public vs internal (`status` attribute)
- HTML filename (`href` attribute)

#### Option B: Check if HTML page exists

**Base URLs:**
- **Released:** `https://doc.qt.io/qt-6/`
- **Dev branch:** `https://doc-snapshots.qt.io/qt6-dev/`

**Construct the URL using skill-qdoc-output patterns:**

| Target Type | URL Pattern | Example |
|-------------|-------------|---------|
| C++ class | `{class}.html` | `https://doc.qt.io/qt-6/qstring.html` |
| QML type | `qml-{module}-{type}.html` | `https://doc.qt.io/qt-6/qml-qtquick-rectangle.html` |
| QML value type | `qml-{type}.html` | `https://doc.qt.io/qt-6/qml-color.html` |
| Module | `{module}-module.html` | `https://doc.qt.io/qt-6/qtcore-module.html` |

**Verification method:**
1. Construct expected URL from target name
2. Use WebFetch to check if page exists
3. If 404: target likely doesn't exist or is `\internal`
4. If exists: link will resolve in full Qt build

**Example verification:**
```
Target: QString
URL: https://doc.qt.io/qt-6/qstring.html
Result: Page exists → NO FIX NEEDED (cross-module dependency)

Target: QInternalClass
URL: https://doc.qt.io/qt-6/qinternalclass.html
Result: 404 → Use \c{QInternalClass} instead of \l
```

**If link works on published docs:**
- **NO FIX NEEDED** - Cross-module/cross-product dependency that resolves in full build

**If 404 on published docs:**
- Needs actual fix (missing `\target`, `\externalpage`, or documentation)
- Or target is `\internal` - use `\c{}` instead of `\l{}`

### Common Fixes Summary

| Situation | Fix |
|-----------|-----|
| Missing `\target` | Add `\target <name>` at destination |
| External URL | Add `\externalpage` with `\title` |
| Macro in title | Use macro in link: `\l{\QOI ...}` |
| Private/internal API | Use `\c{ClassName::method()}` |
| Cross-module (works in full build) | No fix needed |
| QML value type (PascalCase error) | Use camelCase: `\l{webEngineCertificateError::...}` |
| Section in type page (`page.html#anchor`) | Use `\l{TypeName#Section Title}` |
| Unfixable auto-generated warning | Add `spurious +=` filter in qdocconf |
