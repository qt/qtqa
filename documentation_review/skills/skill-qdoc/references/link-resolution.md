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

### The `\sa` (See Also) Command

The `\sa` command creates a "See also" section with links to related topics.
**It uses the same resolution mechanism as `\l`** — both call `findNodeForAtom()`
in `qdocdatabase.cpp`.

#### Syntax

```cpp
\sa Target1, Target2, Target3                    // Comma-separated list
\sa {Target With Spaces}, AnotherTarget          // Braces for spaces
\sa {Class::}{member()}, OtherClass              // C++ member shorthand
\sa {target}{display text}, AnotherTarget        // Custom display text
```

#### Parsing Details

**Source:** `docparser.cpp:902-903, 1865-1931` (`parseAlso()`)

| Syntax Element | Behavior |
|----------------|----------|
| Comma (`,`) | Separates targets (required between items) |
| `and`, `.` | Skipped as separators (legacy support) |
| `{target}` | Target with spaces or special characters |
| `{target}{text}` | Custom display text |
| `{Class::}{member()}` | Expands to `Class::member()` |
| Missing comma | Warning: `"Missing comma in '\sa'"` |

#### Resolution Flow

```
\sa QWidget::show(), QDialog
        ↓
parseAlso() parses comma-separated targets
        ↓
Each target → Atom::Link atom → m_alsoList
        ↓
generateAlsoList() during HTML generation
        ↓
For each item: findNodeForAtom() (same as \l)
        ↓
Rendered in "See also" section
```

#### Key Differences from `\l`

| Aspect | `\l` | `\sa` |
|--------|------|-------|
| Rendering | Inline link | "See also" section at end |
| Multiple targets | One per command | Comma-separated list |
| Duplicates | Each rendered | Auto-deduplicated |
| Self-link | Warning: "Can't link to" | Warning: "Redundant link to self" |

#### Common Patterns

**Correct:**
```cpp
\sa QWidget::show(), QDialog::exec(), {Getting Started with Qt}
\sa QString::isEmpty(), QString::isNull()
\sa {QtQuick.Controls::ToolTip::delay}, QWidget::toolTip
```

**Incorrect:**
```cpp
\sa QWidget::show() QDialog::exec()    // Missing comma → warning
\sa show()                              // Ambiguous without class context
\sa Getting Started with Qt             // Needs braces for spaces
```

#### Self-Link Detection

**Source:** `generator.cpp:603-604`

QDoc warns when `\sa` links to the containing node:
```
Redundant link to self in \sa command for ClassName
```

This differs from `\l` which produces "Can't link to" for the same situation.

#### All `\l` Rules Apply

Since `\sa` uses `findNodeForAtom()`, all link resolution rules apply:

- Target types (class, function, QML type, page title, section)
- Cross-module linking requires `depends` in qdocconf
- QML value types use camelCase
- Section links use `TypeName#Section Title` syntax
- External pages require `\externalpage` with matching `\title`

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
| Bare method (outside class) | `trimmed()` in overview page | Add class: `QString::trimmed()` |
| QML properties with `.` | `font.kerning` | Use `\l {font::kerning}` |
| QML types (cross-module) | `ToolTip` | Use `\l {QtQuick.Controls::ToolTip}` |
| Page titles | `Getting Started` | Use `\l {Getting Started with Qt}` |
| Custom display text | any | Use `\l {target}{display text}` |

**Important:** Bare method names like `changeEvent()` DO autolink when used within
class documentation, because QDoc searches up the parent chain. See
"Context-Aware Resolution" below.

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
├─ YES → Does it match autolink pattern? (CamelCase or has ::, (), _)
│        ├─ YES → Is the target in current class context?
│        │        ├─ YES → Autolink handles it (no markup needed)
│        │        │        Example: changeEvent() inside QWidget docs
│        │        │
│        │        └─ NO → Is target in a different class?
│        │                ├─ YES → Qualify it: ClassName::member()
│        │                │        Example: QWidget::changeEvent()
│        │                │
│        │                └─ NO (overview page) → Use \l {target}
│        │
│        └─ NO → Use \l {target}
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

#### Autolink Pattern Matching (Technical Details)

**Source:** `qttools/src/qdoc/qdoc/src/qdoc/docparser.cpp:1666-1708` (`isAutoLinkString()`)

QDoc's parser identifies autolink candidates using these rules:

**Allowed characters:**
- Lowercase letters (`a-z`)
- Uppercase letters (`A-Z`) — not at position 0 for counting
- Digits (`0-9`) — not at position 0
- Underscore (`_`) and at-sign (`@`) — count as "strange symbols"
- Double colon (`::`) — counts as "strange symbol"
- Parentheses `()` at end — counts as "strange symbol"

**Qualification criteria** (line 1707):
```cpp
return ((numUppercase >= 1 && numLowercase >= 2) ||
        (numStrangeSymbols > 0 && (numUppercase + numLowercase >= 1)));
```

A word autolinks if:
1. **CamelCase**: At least 1 uppercase AND at least 2 lowercase letters, OR
2. **Has special syntax**: Contains `::`, `()`, `_`, or `@` AND has at least 1 letter

**Examples:**

| Word | Uppercase | Lowercase | Strange | Autolinks? | Why |
|------|-----------|-----------|---------|------------|-----|
| `QString` | 1 | 5 | 0 | ✓ | CamelCase (1 upper, 5 lower) |
| `changeEvent()` | 1 | 10 | 1 | ✓ | CamelCase + has `()` |
| `QEvent::EnabledChange` | 2 | 12 | 1 | ✓ | CamelCase + has `::` |
| `foo()` | 0 | 3 | 1 | ✓ | Has `()` + letters |
| `WA_OpaquePaintEvent` | 3 | 13 | 1 | ✓ | Has `_` + letters |
| `string` | 0 | 6 | 0 | ✗ | No uppercase, no symbols |
| `URL` | 3 | 0 | 0 | ✗ | No lowercase letters |
| `true` | 0 | 4 | 0 | ✗ | No uppercase, no symbols |

#### Context-Aware Resolution

**Source:** `qttools/src/qdoc/qdoc/src/qdoc/tree.cpp:1374-1451` (`findFunctionNode()`)

When resolving autolinks, QDoc uses the **relative node** (current documentation
context) and walks up the parent chain to find matches.

**Resolution algorithm:**
1. Start from `relative` node (e.g., a property being documented)
2. Search current aggregate for the function/member
3. If class: also search base classes
4. If not found: move to `relative->parent()` and repeat
5. Continue until root is reached

**Example: `changeEvent()` in QWidget::enabled property documentation**

```
Documentation context: QWidget::enabled (property)
Autolink target: changeEvent()

Resolution path:
1. Search QWidget::enabled (property) → not found
2. Move to parent: QWidget (class)
3. Search QWidget for changeEvent() → FOUND (virtual function)
4. Link resolves to QWidget::changeEvent()
```

**Implication for reviewers:**

| Context | Bare `changeEvent()` | Needs `\l`? |
|---------|---------------------|-------------|
| Inside QWidget class docs | ✓ Autolinks | No |
| Inside QWidget property docs | ✓ Autolinks (via parent) | No |
| Inside overview page (`\page`) | ✗ No context | Yes |
| Inside different class docs | ✗ Wrong context | Yes |

**When explicit `\l` IS needed:**
- Overview pages (`\page`) have no class context
- Linking to a function in a *different* class than the current context
- When you need custom display text: `\l{changeEvent()}{the change event handler}`

**When explicit `\l` is redundant:**
- Inside class documentation linking to same-class members
- Inside property/function docs linking to sibling members
- Any autolink-qualified name within its own class scope

#### Cross-Module Autolink Resolution

**Source:** `qttools/src/qdoc/qdoc/src/qdoc/qdocdatabase.cpp:37-45`

Autolinks can resolve to targets in OTHER modules if those modules' index files
are loaded via the `depends` variable in qdocconf.

**How it works:**
1. Index files from dependent modules are loaded at startup (`readIndexes()`)
2. Each index file becomes a Tree in the `QDocForest`
3. Autolink resolution searches ALL trees: primary tree + index trees
4. First match wins (search order matters)

**Implication:** If `QString` autolinks correctly, it's because qtcore.index was
loaded. If it fails, check that `depends += qtcore` is in qdocconf.

#### Autolink Suppression List

**Source:** `qttools/src/qdoc/qdoc/src/qdoc/qdocdatabase.cpp:405-535`

QDoc maintains a hardcoded list of ~130 words that NEVER autolink, even if they
match the CamelCase or special-symbol patterns. These are stored in `s_typeNodeMap`
with `nullptr` values.

**Categories suppressed:**

| Category | Examples |
|----------|----------|
| C++ primitives | `void`, `char`, `float`, `short`, `long`, `unsigned`, `signed`, `wchar_t` |
| STL types | `std::string`, `std::vector`, `std::map`, `std::list`, `std::pair`, `std::initializer_list` |
| Common signals | `clicked`, `activated`, `toggled`, `selected`, `hovered`, `timeout`, `closed` |
| Common properties | `data`, `value`, `name`, `index`, `position`, `state`, `format`, `mode` |
| QML concepts | `alias`, `anchors`, `easing`, `parent`, `focus`, `drag` |
| Template placeholders | `T`, `t` |
| System types | `va_list`, `sockaddr`, `size_t` |

**Why this matters for reviewers:**

Words on this list will NOT autolink even if they look like they should:
```qdoc
The clicked() signal...     // "clicked" won't autolink (suppressed)
Returns void.               // "void" won't autolink (suppressed)
Use std::vector for...      // "std::vector" won't autolink (suppressed)
```

If you see `clicked()` without a link in output, it's expected behavior, not a bug.

#### Self-Link Prevention

**Source:** `qttools/src/qdoc/qdoc/src/qdoc/htmlgenerator.cpp:322-326`

QDoc prevents self-referential links. If the autolink target matches the current
node's name, no link is created:

```cpp
if (relative && relative->name() == name.replace("()", "")) {
    out() << protectEnc(atom->string());  // Plain text, no link
    break;
}
```

**Example:** In `QString::isEmpty()` documentation, the word "isEmpty()" won't
link to itself.

#### Deprecated Node Suppression

**Source:** `qttools/src/qdoc/qdoc/src/qdoc/htmlgenerator.cpp:341-344`

Autolinks to deprecated nodes are suppressed when linking FROM non-deprecated
documentation:

```cpp
if (node && node->isDeprecated()) {
    if (relative && (relative->parent() != node) && !relative->isDeprecated())
        link.clear();  // Suppress link
}
```

**Rationale:** Prevents new documentation from linking to deprecated APIs,
encouraging users toward current alternatives.

#### Debugging Autolinks

**`--autolink-errors` flag:**

```bash
qdoc --autolink-errors mymodule.qdocconf
```

Enables warnings for failed autolinks:
```
warning: Can't autolink to 'SomeType'
```

Disabled by default because many autolink failures are expected (suppression list,
cross-module targets not in depends, etc.).

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

### Step 1: Verify qdocconf dependencies (for cross-module links)

Before any other diagnosis, check if the target module is configured as a dependency.

```bash
# Find the source module's qdocconf file
find <source-module>/src -name "*.qdocconf" | head -5

# Check depends variable
grep "^depends" <source-module>/src/<submodule>/doc/<submodule>.qdocconf
```

**Example:**
```
depends = qtcore qtgui qtdoc qtqml qtquick qtquickcontrols
```

**If target module is missing from `depends`:**
- Add the module to `depends +=` in qdocconf
- This is the root cause - no other fixes needed

**If target module is listed:**
- Cross-module linking is configured
- Proceed to verify the exact link target (Step 2)

### Step 2: Search index files for the exact target

**Prerequisites:** Index files are **build artifacts** - they only exist after running
`ninja docs` or `ninja html_docs_<Module>`. They are NOT published online.

```bash
# First, check if index files exist
ls */doc/*/*.index 2>/dev/null || echo "No index files - docs not built"
```

**For page title links:**
```bash
# Search for your assumed title
grep 'title="Qt Quick Controls - Basic Style"' */doc/*/*.index

# If no results, search for a keyword from the title
grep -i 'title=".*Basic.*Style"' */doc/*/*.index

# Find the actual title
grep 'title="Basic Style"' */doc/*/*.index
```

**For type and member links:**
```bash
# Find a class
grep 'name="ClassName"' */doc/*/*.index

# Find a QML type
grep 'name="TypeName".*qml=' */doc/*/*.index

# Find a property (check access is public)
grep 'name="propertyName"' */doc/*/*.index | grep -v 'access="private"'
```

**Verification checklist:**
- [ ] Target exists (`name` or `title` attribute)
- [ ] Access is public (`access="public"` or no access attribute)
- [ ] Note the exact name/title for the fix
- [ ] Note the `href` for Output field verification

**Index file location:** `<build-dir>/<module>/doc/<submodule>/<submodule>.index`

**If no index files exist:** Skip to Step 8 (web verification).

### Step 3: Search for explicit targets

```bash
# Search for \target definitions
grep -r "\\\\target.*<keyword>" <module>/doc/

# Search for \keyword definitions
grep -r "\\\\keyword.*<keyword>" <module>/doc/
```

### Step 4: Search for page titles

```bash
# Search for page by title
grep -r "\\\\title.*<keyword>" <module>/doc/
```

### Step 5: Search for external pages

```bash
# Check central external-resources.qdoc
grep -r "externalpage.*<keyword>" qtdoc/doc/src/external-resources.qdoc

# Check module-specific external pages
grep -r "\\\\externalpage" <module>/doc/
```

### Step 6: Search for macros

```bash
# Check global macros
grep "macro\." qtbase/doc/global/macros.qdocconf
```

**Important:** Link targets must match `\title` **exactly after macro expansion**.

### Step 7: For internal/private APIs

If the target is in a private header (`_p.h`) or lacks public documentation, use `\c{}` instead of `\l{}`:

```qdoc
\c{QPlatformWindow::invalidateSurface()}
```

### Step 8: Verify via published docs (web fallback)

When local index files don't exist, use online resources.

#### Option A: Fetch Index Files from doc-snapshots.qt.io (PREFERRED)

Index files are published on **doc-snapshots.qt.io only** (not doc.qt.io):

```
https://doc-snapshots.qt.io/qt6-dev/{module}.index     # dev branch
https://doc-snapshots.qt.io/qt6-{major}.{minor}/{module}.index  # release branches
```

**Use WebFetch to search the index file:**
```
URL: https://doc-snapshots.qt.io/qt6-dev/qtquickcontrols.index
Prompt: "Search for title containing 'Basic Style' and show the exact title and href"
```

This gives the same information as grepping local index files - you can verify:
- Target exists (`name` or `title` attribute)
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

### Link Verification Fallback Process

**CRITICAL: Verify link targets BEFORE suggesting `\l`. Never guess.**

Follow this fallback chain in order:

| Priority | Method | When Available |
|----------|--------|----------------|
| 1 | Local index files | After `ninja docs` build |
| 2 | Online index files (doc-snapshots) | Always (dev branch) |
| 3 | HTML anchor check | Always |
| 4 | Safe default (`\c`) | When verification fails |

#### Method 1: Local Index Files (Preferred)

```bash
# Check if index files exist
ls */doc/*/*.index 2>/dev/null

# Search for target
grep 'name="TargetName"' */doc/*/*.index
```

#### Method 2: Online Index Files

**Index files are ONLY on doc-snapshots.qt.io** (not doc.qt.io):

```
https://doc-snapshots.qt.io/qt6-dev/{module}.index
```

Use WebFetch to search:
```
URL: https://doc-snapshots.qt.io/qt6-dev/qtgui.index
Prompt: "Search for name='InputMethodHint' and show matching entries"
```

#### Method 3: HTML Anchor Check

If index search fails, check if the anchor exists on the published HTML page:

```
URL: https://doc.qt.io/qt-6/qt.html
Prompt: "Does an anchor exist for ImhFormattedNumbersOnly? Check for id= or name= attributes"
```

**For enum values specifically:**
- Enum TYPE pages (`#InputMethodHint-enum`) usually exist
- Individual enum VALUE anchors often do NOT exist
- If no anchor for individual value → use `\c`, not `\l`

#### Method 4: Safe Default

**If verification fails or is inconclusive, use `\c` instead of `\l`:**

```qdoc
\c{Qt::ImhFormattedNumbersOnly}   // Safe - always works
\l Qt::ImhFormattedNumbersOnly    // Risky - may produce warning
```

**Rationale:**
- `\c` renders correctly regardless of link resolution
- `\l` to non-existent target produces "Can't link to" warning
- For enum values and code literals, `\c` is often semantically better anyway

### Common Fixes Summary

| Situation | Fix |
|-----------|-----|
| qdocconf `depends` missing module | Add `depends += <module>` |
| Wrong page title in link | Use exact title from index file |
| Missing `\target` | Add `\target <name>` at destination |
| External URL | Add `\externalpage` with `\title` |
| Macro in title | Use macro in link: `\l{\QOI ...}` |
| Private/internal API | Use `\c{ClassName::method()}` |
| Cross-module (works in full build) | No fix needed |
| QML value type (PascalCase error) | Use camelCase: `\l{webEngineCertificateError::...}` |
| Section in type page (`page.html#anchor`) | Use `\l{TypeName#Section Title}` |
| Enum values without anchors | Use `\c{Enum::Value}` instead of `\l` |
| Unfixable auto-generated warning | Add `spurious +=` filter in qdocconf |

---

## Reviewer Verification Checklist (BLOCKING)

**Before suggesting ANY link change (`\l`, `\c`, or autolink comments), complete this checklist:**

### Step 1: Fetch Index

```bash
# Preferred: Online index (always available)
WebFetch https://doc-snapshots.qt.io/qt6-dev/{module}.index
# Prompt: "List all indexed names: classes, typedefs, enums, functions"

# Alternative: Local index (if docs built)
grep 'name="TargetName"' */doc/*/*.index
```

### Step 2: Determine Target Type

| What You Found | Target Type | Autolinks? |
|----------------|-------------|------------|
| `<class name="QFoo"...>` | Class | ✓ Yes |
| `<typedef name="QFooTask"...>` | Typedef | ✓ Yes |
| `<function name="foo"...>` | Function | ✓ Yes (with `()`) |
| `<enum name="MyEnum"...>` | Enum type | ✓ Yes |
| Not found at top level | Enum VALUE | ✗ No - needs markup |
| Not found anywhere | Internal/missing | ✗ No - use `\c` |

### Step 3: Apply Decision

| Situation | Action | Example |
|-----------|--------|---------|
| Target autolinks | Don't suggest `\l` | `QProcessTask` in prose → leave as-is |
| Enum value | Add `\c` or `\l{Enum::Value}` | `\c StopOnError` or `\l{WorkflowPolicy::StopOnError}` |
| Internal type | Use `\c` | `\c{QPrivateClass}` |
| Cross-module type | Verify in target module's index | Check if `depends +=` includes module |

### Step 4: Include Evidence

**Always show verification in Validation field:**

```markdown
**Validation:**
- ✓ Index check: `QProcessTask` found in qttasktree.index as typedef (autolinks)
- ✓ Index check: `WorkflowPolicy` enum found, but `StopOnError` value not at top level
- ✗ `StopOnError` needs `\c` markup (enum values don't autolink)
```

### Common Mistakes to Avoid

| Mistake | Problem | Prevention |
|---------|---------|------------|
| Suggesting `\l` for indexed classes | Creates redundant markup | Check index FIRST |
| Assuming enum values autolink | They don't (only enum type does) | Verify in index |
| Guessing without verification | May suggest wrong fix | Always fetch index |
| Checking after suggesting | Wastes reviewer time | Verify BEFORE presenting |

---

## Version History

- **v1.5** (2026-03-16): Added Reviewer Verification Checklist
  - New "Reviewer Verification Checklist (BLOCKING)" section
  - Step-by-step verification: fetch index, determine type, apply decision
  - Decision table for autolink vs manual markup
  - Common mistakes to avoid
  - All link verification across skills/agents now references this section

- **v1.4** (2026-03-12): Added `\sa` (See Also) command documentation
  - Added "The `\sa` (See Also) Command" section with syntax, parsing, resolution flow
  - Documented that `\sa` uses same `findNodeForAtom()` as `\l`
  - Added comparison table: `\l` vs `\sa` differences
  - Added self-link detection behavior ("Redundant link to self" warning)
  - Added common patterns and anti-patterns

- **v1.3** (2026-03-12): Added comprehensive autolink documentation
  - Added "Cross-Module Autolink Resolution" - how index files enable cross-module links
  - Added "Autolink Suppression List" - ~130 hardcoded words that never autolink
  - Added "Self-Link Prevention" - nodes don't link to themselves
  - Added "Deprecated Node Suppression" - deprecated targets suppressed from non-deprecated docs
  - Added "Debugging Autolinks" - `--autolink-errors` flag

- **v1.2** (2026-03-12): Added Link Verification Fallback Process
  - Added prioritized fallback chain: local index → online index → HTML check → safe default
  - Clarified that index files are ONLY on doc-snapshots.qt.io (not doc.qt.io)
  - Added guidance for enum values: individual values often lack anchors, use `\c`
  - Added "Enum values without anchors" to Common Fixes Summary

- **v1.1** (2026-03-12): Added detailed autolink technical documentation
  - Added "Autolink Pattern Matching (Technical Details)" section with
    `isAutoLinkString()` rules from docparser.cpp:1666-1708
  - Added "Context-Aware Resolution" section explaining parent chain walking
    from tree.cpp:1374-1451
  - Updated "What Does NOT Autolink" table to clarify context-dependent behavior
  - Updated Decision Tree to include context-aware considerations
  - Clarified that `()` enables (not breaks) autolinking

- **v1.0** (2026-02-17): Initial version with link resolution and target system
