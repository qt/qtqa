# Macro System and Warnings

## Macro System

### Basic Definition

```qdocconf
macro.QT = "Qt"
macro.author = "\\b{Author:}"
```

### Parameterized Macros

Parameters numbered `\1` through `\7`:

```qdocconf
macro.param = "\\c{\\1}"
macro.link = "\\l{\\1}{\\2}"
macro.tablerow = "\\li \\1 \\li \\2 \\li \\3"
```

### Format-Specific Macros

```qdocconf
macro.note = "\\b{Note:}"
macro.note.HTML = "<div class=\"note\"><b>Note:</b>"
macro.note.DocBook = "<db:note><db:para>"
```

### Regex Match Attribute

Extract portions of expanded result:

```qdocconf
macro.QtVersion = "$QT_VERSION"
macro.QtMajorVersion = "$QT_VERSION"
macro.QtMajorVersion.match = "^(\\d+)\\."
```

If `$QT_VERSION = "6.8.0"`:
- `\QtVersion` → `6.8.0`
- `\QtMajorVersion` → `6`

### Macro Nesting

```qdocconf
macro.important = "\\b{Important:} \\1"
macro.criticalNote = "\\important{\\1} See also \\l{warnings}{Warnings}."
```

### Common Qt Macros

Defined in `qtbase/doc/global/macros.qdocconf`:

| Macro | Expansion | Usage |
|-------|-----------|-------|
| `\QOI` | "Qt Online Installer" | Product name |
| `\QDS` | "Qt Design Studio" | Product name |
| `\QC` | "Qt Creator" | Product name |
| `\macos` | "macOS" | Platform name |

**Example:**
```qdocconf
macro.QOI = "Qt Online Installer"
```

Usage in documentation:
```qdoc
Download the \QOI from the Qt website.
```

---

## External Pages

### Definition

External pages create named targets for external URLs:

```qdoc
/*!
    \externalpage https://download.qt.io/official_releases/online_installers/
    \title \QOI official releases
*/
```

### Link Resolution

**Critical:** Link targets must match the **expanded** `\title` exactly.

| External Page Title | Valid Link | Invalid Link |
|---------------------|------------|--------------|
| `\title \QOI official releases` | `\l{\QOI official releases}` | `\l{Qt Online Installer}` |
| `\title CMake Documentation` | `\l{CMake Documentation}` | `\l{CMake}` |

### Common External Pages Location

- **qtdoc:** `qtdoc/doc/src/external-resources.qdoc` (central repository)
- **Per-module:** `<module>/doc/src/*.qdoc`

### Debugging External Page Links

1. Search for `\externalpage` with the URL or topic
2. Find the exact `\title` (including any macros)
3. Expand macros to get the actual target string
4. Use that exact string in `\l{...}`

**Example investigation:**
```bash
# Find external page
grep -r "externalpage.*online_installer" qtdoc/

# Result: \title \QOI official releases
# \QOI expands to "Qt Online Installer"
# So link target is "Qt Online Installer official releases"
```

---

## Multiple Topic Commands in Single Doc Block

Multiple related functions or signals can share a single documentation block
by listing multiple `\fn` commands:

```cpp
/*!
    \fn void QWebEngineExtensionManager::loadFinished(const QWebEngineExtensionInfo &extension)
    \fn void QWebEngineExtensionManager::installFinished(const QWebEngineExtensionInfo &extension)
    \fn void QWebEngineExtensionManager::unloadFinished(const QWebEngineExtensionInfo &extension)
    \fn void QWebEngineExtensionManager::uninstallFinished(const QWebEngineExtensionInfo &extension)

    Signals that are emitted when \a extension is loaded, unloaded, installed,
    or uninstalled.
*/
```

**Key points:**
- All `\fn` commands must appear at the start of the doc block
- The shared documentation applies to all listed functions/signals
- Parameters referenced with `\a` should exist in at least one signature
- Useful for related signals or overloaded functions with identical behavior

**Also works with other topic commands:**
```cpp
/*!
    \qmlsignal WebEngineView::loadStarted()
    \qmlsignal WebEngineView::loadFinished()

    Signals emitted when page loading starts or completes.
*/
```

---

## Warning and Error System

### Location-Based Diagnostics

```
/path/to/file.cpp:42: warning: Can't link to 'NonexistentClass'
```

### Warning Severity

| Level | Behavior |
|-------|----------|
| `Warning` | Counted, continues processing |
| `Error` | Logged, continues processing |
| `Fatal` | Terminates immediately |

### Exit Code

```cpp
if (warningCount <= warningLimit)
    return EXIT_SUCCESS;
else
    return warningCount;  // Non-zero exit
```

### Suppressing Warnings with `spurious`

The `spurious` qdocconf directive suppresses warnings matching a regex pattern.
Use for unfixable warnings from auto-generated content or known false positives.

```qdocconf
# Suppress specific warning text
spurious += "Can't link to 'This is the canonical repository.'"

# Suppress pattern with regex
spurious += "Output file already exists, overwriting .*"
```

**When to use `spurious`:**
- Attribution documentation auto-generates unfixable link warnings
- Cross-product links that only resolve in full Qt builds
- Third-party content produces warnings outside your control
- Known QDoc bugs producing false positives

**When NOT to use `spurious`:**
- Fixable link warnings (fix the source instead)
- Warnings indicating actual documentation problems
- As a workaround for missing documentation

**Example: Attribution documentation warnings**

Qt's attribution system auto-generates documentation from `qt_attribution.json`
files. These can produce warnings like:

```
Can't link to 'This is the canonical repository.'
```

This text comes from third-party metadata and cannot be modified. Suppress with:

```qdocconf
# Ignore incorrect link generated for attribution docs
spurious += "Can't link to 'This is the canonical repository.'"
```

**Combining with `warninglimit`:**

After adding `spurious` filters for unfixable warnings, reset the warning limit
to enforce zero tolerance for remaining warnings:

```qdocconf
spurious += "Can't link to 'This is the canonical repository.'"
warninglimit = 0
```

---

## Common Warnings Reference

### Link Warnings

| Warning | Cause | Fix |
|---------|-------|-----|
| **Can't link to '\<target\>'** | Target doesn't exist or is `\internal` | Verify spelling, check if documented |
| **Duplicate target name** | Two `\target` commands same name | Use unique names |

### Diagnosing Link Warnings

**IMPORTANT:** Before concluding a warning needs no fix, follow the complete diagnostic checklist in `references/link-resolution.md`.

**Diagnostic order:**
1. Search for `\target` definitions
2. Search for page `\title` matches
3. Search for `\externalpage` definitions
4. Search for macros in `macros.qdocconf`
5. Search index files for the target
6. For private APIs, use `\c{}` instead of `\l{}`
7. **Last resort:** Check doc-snapshots.qt.io

### Cross-Module Link Warnings

**Pattern:** `Can't link to 'X'` where X is a type/page from another Qt module.

**Common examples:**
- `Can't link to 'Qt WebEngine'`
- `Can't link to 'Qt Wayland Compositor'`
- `Can't link to 'QWebEngineView'`
- `Can't link to 'qtwebengine-index.html'`

**Cause depends on build mode:**

| Build Mode | Cause | Action |
|------------|-------|--------|
| Modular (`ninja html_docs_<Module>`) | Target module not built locally | Expected - verify on doc.qt.io |
| Singular (`ninja docs` or CI) | Target truly missing or `\internal` | Real error - needs fix |

See `references/index-files.md` for build mode details.

**Verification:** Check published docs to confirm the link works in the singular build:
- [doc.qt.io](https://doc.qt.io/qt-6/) - Released docs (definitive for cross-product links)
- [doc-snapshots.qt.io/qt6-dev](https://doc-snapshots.qt.io/qt6-dev/) - Dev branch (for unreleased APIs)

**If link works there:** **NO FIX NEEDED** - Cross-module/cross-product dependency that resolves in full build.

**Do NOT "fix" cross-module warnings by:**
- Removing the link (breaks navigation in full build)
- Adding absolute URLs (inconsistent with other links)
- Converting to `\c{}` (loses linking in full build)

### Node Warnings

| Warning | Cause | Fix |
|---------|-------|-----|
| **Cannot tie this documentation to anything** | No topic command | Add `\class`, `\fn`, `\page` |
| **Has no \inmodule command** | Class not in module | Add `\inmodule ModuleName` |
| **No documentation for '\<name\>'** | Declaration without doc | Add documentation |
| **Documented more than once** | Duplicate topic commands | Remove duplicate |

### Function Warnings

| Warning | Cause | Fix |
|---------|-------|-----|
| **Failed to find function when parsing \fn** | Signature mismatch | Fully qualify, match exact signature |
| **No such parameter '\<name\>'** | `\a` references bad param | Check spelling |
| **Undocumented parameter** | Parameter not in `\a` | Document all parameters |

### QML Warnings

| Warning | Cause | Fix |
|---------|-------|-----|
| **Could not resolve QML import statement** | Missing `\inqmlmodule` | Add `\inqmlmodule QtModule` |
| **Invalid QML property type** | C++ type in QML doc | Use QML types |
| **Unknown base for QML type** | Bad `\inherits` | Verify base type |

### Snippet Warnings

| Warning | Cause | Fix |
|---------|-------|-----|
| **Cannot find snippets file** | File doesn't exist | Check `exampledirs` |
| **Cannot find '\<tag\>' in '\<file\>'** | Marker missing | Add `//! [tag]` markers |
| **Empty qdoc snippet** | No content between markers | Add content |
