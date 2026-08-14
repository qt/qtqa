# QDoc Context Commands Reference

**Source:** `qttools/src/qdoc/qdoc/doc/qdoc-manual-contextcmds.qdoc`
**Source:** `qttools/src/qdoc/qdoc/src/qdoc/docparser.cpp`

Context commands provide metadata about documented elements that QDoc cannot deduce
automatically. They typically appear near the top of a QDoc comment, just below
the topic command.

## Quick Reference

| Command | Purpose | Since |
|---------|---------|-------|
| `\brief` | Short description | - |
| `\since` | Version introduced | - |
| `\deprecated` | Mark as deprecated | - |
| `\internal` | Hide from public docs | - |
| `\preliminary` | Mark as under development | - |
| `\modulestate` | Custom module state | 6.5 |
| `\inmodule` | Assign to module | - |
| `\ingroup` | Assign to group | - |
| `\relates` | Associate with class/header | - |
| `\inherits` | QML type inheritance | - |
| `\overload` | Mark as overload | - |
| `\reimp` | Mark as reimplementation | - |
| `\reentrant` | Thread-safe (per-data) | - |
| `\threadsafe` | Thread-safe (shared data) | - |
| `\nonreentrant` | Not thread-safe | - |
| `\qmldefault` | Mark default QML property | - |
| `\qmlabstract` | Mark abstract QML type | - |
| `\readonly` | Mark read-only QML property | - |
| `\required` | Mark required QML property | - |
| `\default` | Document default value | - |
| `\compares` | Comparison with self | 6.7 |
| `\compareswith` | Comparison with other types | 6.7 |
| `\qmlenumeratorsfrom` | Copy enum docs to QML | 6.8 |
| `\toc` / `\tocentry` | Table of contents | 6.11 |
| `\previouspage` | Legacy; superseded by the TOC tree | - |
| `\nextpage` | Legacy; superseded by the TOC tree | - |
| `\startpage` | Legacy; superseded by the TOC tree | - |
| `\title` | Page title | - |
| `\subtitle` | Page subtitle | - |

---

## Status Commands

### `\brief` - Short Description

**Required for:** All documented entities (classes, functions, pages, QML types)

Provides a one-line description used in lists and tables.

**Syntax:**
```qdoc
\brief Short description ending with a period.
```

**Best Practices:**
```qdoc
// CORRECT - starts with "The <Type> class/type..."
\brief The QString class provides a Unicode character string.

// CORRECT - starts with verb for functions
\brief Returns the length of the string.

// WRONG - doesn't start with article for classes
\brief Provides Unicode string handling.  // Missing "The QString class"

// WRONG - ends with ellipsis
\brief The QString class provides...  // Truncated
```

**Rules:**
- End with a period
- Classes: "The ClassName class..." or "The ClassName type..."
- Functions: Start with a verb (Returns, Sets, Creates, etc.)
- Maximum recommended: ~80 characters

---

### `\since` - Version Information

Indicates when functionality was introduced.

**Syntax:**
```qdoc
\since 6.5                    // Uses productname from qdocconf
\since Qt 6.5                 // Explicit product name
\since Qt Quick Controls 2.5  // Full product name with spaces
```

**Inheritance (Qt 6.5+):**
- Classes inherit `\since` from their `\module`
- QML types inherit `\since` from their `\qmlmodule`
- Explicit `\since` overrides inherited value

**With `\value` (since clause):**
```qdoc
\enum Qt::Alignment
\value AlignLeft Align to the left.
\value [since 6.5] AlignBaseline Align to the baseline.
```

#### Verification (MANDATORY)

**Do NOT copy `\since` from existing docs without verification.** Always verify
using git history:

```bash
# Step 1: Find the commit that introduced the file/class
git log --oneline --follow --diff-filter=A -- "path/to/file.cpp" | tail -1

# Step 2: Find the earliest Qt version tag containing that commit
git tag --contains <commit-hash> --sort=version:refname | head -5
```

**Example:**
```bash
$ git log --oneline --follow --diff-filter=A -- "src/widgets/qwidget.cpp" | tail -1
abc1234 Add QWidget class

$ git tag --contains abc1234 --sort=version:refname | head -3
v6.3.0-alpha1
v6.3.0-beta1
v6.3.0
```
Result: Use `\since 6.3`

**Why verification matters:**
- Existing `\since` in related docs may be wrong
- Files may have been moved/renamed (git follow handles this)
- Copy-paste errors are common

**When adding `\class` for existing `\qmltype`:**
- Verify independently - don't assume QML `\since` is correct
- Both should match if introduced together, but verify

---

### `\deprecated` - Deprecation Notice

Marks an element as deprecated.

**Syntax:**
```qdoc
\deprecated                              // Basic
\deprecated [6.2]                        // With version
\deprecated [6.2] Use newFunction().     // With replacement
\deprecated Use \l newFunction() instead. // With link
```

**Best Practices:**
```qdoc
/*!
    \fn void Widget::oldMethod()
    \deprecated [6.2] Use newMethod() instead.

    This method is deprecated. Use newMethod() for improved performance.
*/
```

**Generated Output:**
- Creates separate "Deprecated Members" page for classes
- Shows deprecation notice with version and replacement

---

### `\internal` - Internal Documentation

Hides documentation from public output.

**Syntax:**
```qdoc
\internal
```

**When to Use:**
- Private implementation classes (`*Private`, `*Helper`)
- Platform abstraction classes (QPA)
- Internal APIs not for public use
- Classes in `_p.h` headers

**Important:** Export macro + `\internal` is VALID for:
- `*Private` classes
- QPA classes
- Headers ending in `_p.h`

```qdoc
/*!
    \class QWidgetPrivate
    \inmodule QtWidgets
    \internal

    Internal implementation class for QWidget.
*/
```

**Note:** Use `-showinternal` or `QDOC_SHOW_INTERNAL` to include in output.

---

### `\preliminary` - Under Development

Marks functionality as still under development.

**Syntax:**
```qdoc
\preliminary
```

**Customization (Qt 6.12+):**
Configure in qdocconf:
```
preliminary.descriptor = "Technology Preview"
preliminary.note = "This API is subject to change."
```

---

### `\modulestate` - Custom Module State (Since 6.5)

Provides custom module state description.

**Syntax:**
```qdoc
/*!
    \module QtExperimental
    \modulestate Technology Preview
*/
```

**Generated Output:**
```
This module is in Technology Preview state.
```

**Note:** Do NOT use for deprecation - use `\deprecated` instead.

---

## Grouping Commands

### `\inmodule` - Module Assignment

Assigns a class to a Qt module.

**Syntax:**
```qdoc
\inmodule QtCore
```

**Rules:**
- Required for classes not auto-detected by location
- Takes rest of line as argument (no trailing content)
- Must match a documented `\module`

**Warning if missing:**
```
warning: Has no \inmodule command
```

---

### `\ingroup` - Group Membership

Adds entity to a documentation group.

**Syntax:**
```qdoc
\ingroup io
\ingroup network
```

**Rules:**
- Entity can belong to multiple groups
- Takes rest of line as argument
- Group must be documented with `\group`

**Generated output:**
- Link in navigation breadcrumbs
- Entry in group's annotatedlist

---

### `\relates` - Related Entity

Associates a free function/typedef/enum with a class.

**Syntax:**
```qdoc
\relates QChar
\relates QList    // Without template parameters
```

**Use Case:**
```qdoc
/*!
    \relates QChar

    Reads a char from stream \a in into \a chr.
*/
QDataStream &operator>>(QDataStream &in, QChar &chr)
```

**Generated Output:**
- Appears in "Related Non-Members" section of class page

---

## Thread Safety Commands

### `\threadsafe` / `\reentrant` / `\nonreentrant`

**Levels (from most to least safe):**

| Command | Meaning |
|---------|---------|
| `\threadsafe` | Can be called simultaneously with shared data |
| `\reentrant` | Can be called simultaneously with separate data |
| `\nonreentrant` | Cannot be called by multiple threads (default) |

**Usage:**
```qdoc
/*!
    \class QMutex
    \threadsafe

    The QMutex class provides access serialization between threads.
*/

/*!
    \fn void QLocale::setDefault()
    \nonreentrant

    \warning In a multithreaded application, set the default locale
    at application startup before creating non-GUI threads.
*/
```

**Class-level with exceptions:**
```qdoc
\class QLocale
\reentrant

// Individual functions can override:
\fn void setDefault()
\nonreentrant
```

---

## QML-Specific Commands

### `\qmldefault` - Default Property

Marks a QML property as the default property.

**Syntax:**
```qdoc
\qmlproperty list<Item> children
\qmldefault
```

**Generated Output:** Shows "default" badge on property.

---

### `\qmlabstract` / `\abstract` - Abstract QML Type

Marks a QML type as abstract (cannot be instantiated).

**Syntax:**
```qdoc
\qmltype AbstractButton
\qmlabstract
\internal   // Usually combined with \internal
```

**Effect:** Properties are documented in inheriting types.

---

### `\readonly` - Read-Only Property

Marks a QML property as read-only.

**Syntax:**
```qdoc
\qmlproperty bool pressed
\readonly
```

---

### `\required` - Required Property

Marks a QML property as required.

**Syntax:**
```qdoc
\qmlproperty string name
\required
```

---

### `\default` - Default Value

Documents a default value for a QML property.

**Syntax:**
```qdoc
\qmlproperty real opacity
\default 1.0

\qmlproperty string state
\default "invalid"    // Strings need quotes
```

---

### `\qmlenumeratorsfrom` - Copy Enum Docs (Since 6.8)

Copies C++ enum documentation to QML property.

**Syntax:**
```qdoc
\qmlproperty enumeration Camera::error
\qmlenumeratorsfrom QCamera::Error

// With custom prefix:
\qmlenumeratorsfrom [Errors] QCamera::Error
```

**Requirements:**
- C++ enum must be documented in same project
- Cannot reference enums from `depends` modules

**Generated Output:**
```
Camera.NoError - No error occurred.
Camera.CameraError - A camera error occurred.
```

---

### `\inherits` - QML Inheritance

Documents QML type inheritance.

**Syntax:**
```qdoc
\qmltype PauseAnimation
\inherits Animation
```

**Note:** Usually auto-detected from .qml files; command overrides detection.

---

## Comparison Commands (Since 6.7)

### `\compares` - Self-Comparison

Documents comparison with same type.

**Syntax:**
```qdoc
\class QDate
\compares strong
```

**Categories:**
- `strong` - Total ordering
- `weak` - Weak ordering
- `partial` - Partial ordering
- `equality` - Equality only (no ordering)

---

### `\compareswith` - Cross-Type Comparison

Documents comparison with other types.

**Syntax:**
```qdoc
\compareswith strong int long {unsigned long}
Additional details about comparisons.
\endcompareswith
```

**Rules:**
- Types with spaces need braces: `{unsigned long}`
- Text between commands is additional documentation

---

## Navigation Commands

### `\toc` / `\tocentry` - Table of Contents (Since 6.11)

Creates hierarchical table of contents.

**Syntax:**
```qdoc
\page index.html
\title Qt

\toc
    \tocentry {Introduction to Qt} {Introduction}
    \tocentry {What's new in Qt} {What's new}
    \tocentry {Getting started}
\endtoc
```

**Rules:**
- `\tocentry` only valid inside `\toc` block
- Cannot nest `\toc` commands
- One `\toc` per topic maximum
- Root topic must be set via `navigation.landingpage` or `navigation.homepage`

**Output:** Generates `<project>_toc.xml` file.

---

### `\previouspage` / `\nextpage` / `\startpage` (legacy)

Superseded by the module TOC tree. Page order comes from the
`\list` on the module's TOC page, named in `navigation.toctitles`;
that mechanism overwrites any `\previouspage`/`\nextpage` links on
listed pages. Do not add these commands to new documentation. See
`skill-toc-tree`.

---

## Naming Commands

### `\title` - Page Title

Sets the title for a documentation page.

**Syntax:**
```qdoc
\page overview.html
\title Qt Overview
```

**Multi-line titles:**
```qdoc
\title Very Long Title That Spans \
       Multiple Lines
```

---

### `\subtitle` - Page Subtitle

Sets a subtitle for a documentation page.

**Syntax:**
```qdoc
\title Qt for Embedded
\subtitle Qt for Embedded Linux
```

---

## Relating Commands

### `\overload` - Function Overload

Marks a function as an overload.

**Syntax:**
```qdoc
\overload                     // Basic
\overload functionName()      // Link to primary
\overload primary             // Designate as primary
```

**Best Practices:**
```qdoc
// Primary function (full documentation)
/*!
    \fn void Widget::setText(const QString &text)

    Sets the widget's text to \a text.
*/

// Overload (brief difference only)
/*!
    \fn void Widget::setText(const char *text)
    \overload

    Convenience overload accepting a C string.
*/
```

**Primary overload:**
- Contains main documentation
- Requires full parameter documentation
- Does not show "This function overloads..." text
- Use `\overload primary` to designate explicitly

---

### `\reimp` - Reimplementation

Marks a virtual function reimplementation.

**Syntax:**
```qdoc
/*!
    \reimp
*/
void MyWidget::paintEvent(QPaintEvent *event)
```

**Effect:**
- Function included without additional documentation
- Links to base class function
- Suppresses "undocumented function" warning

---

## Other Commands

### `\wrapper` - Wrapper Class

Marks a class as a wrapper for non-Qt API.

**Syntax:**
```qdoc
\class QAxObject
\wrapper
```

**Effect:** Suppresses warnings for members accessing external APIs.

---

### `\dontdocument` - Suppress Warnings

Specifies classes that should not be documented.

**Syntax (in dontdocument.qdoc):**
```qdoc
/*!
    \dontdocument (QTypeInfo QMetaTypeId)
*/
```

**Effect:** Suppresses "missing \class" warnings for listed types.

---

### `\inheaderfile` - Custom Include

Overrides the default include statement.

**Syntax:**
```qdoc
\class SpecialWidget
\inheaderfile Widgets/SpecialWidget
```

**Generated Output:**
```cpp
#include <Widgets/SpecialWidget>
```

---

### `\attribution` - License Attribution

Marks a page as license attribution documentation.

**Syntax:**
```qdoc
\page thirdparty-zlib.html
\attribution
\title zlib License
```

**Use with:** `\generatelist annotatedattributions`

---

## CMake Commands

| Command | Purpose |
|---------|---------|
| `\cmakecomponent` | CMake component name |
| `\cmakepackage` | CMake package name |
| `\cmaketargetitem` | CMake target |
| `\qtcmakepackage` | Qt CMake package |
| `\qtcmaketargetitem` | Qt CMake target |

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| Missing `\brief` | No summary in lists | Add brief description |
| `\since` wrong format | Doesn't match productname | Use consistent format |
| `\inmodule` missing | Class not in module lists | Add \inmodule command |
| `\internal` on public API | Hides needed documentation | Remove or use \preliminary |
| `\deprecated` no replacement | Users don't know alternative | Add replacement info |
| `\overload` on primary | Wrong function gets overload text | Use `\overload primary` |

---

## QDoc Warnings

| Warning | Cause | Fix |
|---------|-------|-----|
| Has no \inmodule command | Class not assigned to module | Add `\inmodule ModuleName` |
| Missing \brief | No brief description | Add `\brief ...` |
| No documentation for 'X' | Function/class undocumented | Add documentation or `\internal` |
| \deprecated without version | Missing deprecation version | Add `[version]` argument |

---

## Version History

- **v1.1** (2026-03-12): Added `\since` verification section
  - Mandatory git-based verification for `\since` versions
  - Step-by-step commands: `git log --diff-filter=A` + `git tag --contains`
  - Warning against copying `\since` from existing docs without verification
- **v1.0** (2025-02-18): Initial version with comprehensive context command reference

