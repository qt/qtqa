# Namespaces, Header Files, and Macros Reference

**Verified against:** QDoc manual (doc.qt.io/qt-6), 64
`\namespace`, 63 `\headerfile`, and 261 `\macro` usages
in qt5 super-repo.

## `\namespace` — Namespace Documentation

Documents the contents of a C++ namespace. Generates a reference
page similar to a class page.

### Syntax

```qdoc
/*!
    \namespace NamespaceName
    \inmodule ModuleName
    \since {version}
    \brief One-line description.

    Body paragraph describing the namespace contents.

    \sa {Related namespaces or classes}
*/
```

### Mandatory companions

| Command | Purpose | Notes |
|---------|---------|-------|
| `\inmodule` | Module assignment | **Mandatory in practice** (official example omits it) |
| `\brief` | Summary | Always present |

### Common companions

| Command | Purpose | Example |
|---------|---------|---------|
| `\since` | Version introduced | `\since 4.4` |
| `\ingroup` | Group membership | `\ingroup network` |
| `\inheaderfile` | Associated header | `\inheaderfile QtWebView` |
| `\keyword` | Search keyword | Rare |

### Discrepancy: `\inmodule` is mandatory

The official QDoc manual example omits `\inmodule`:
```qdoc
\namespace Qt
\brief Contains miscellaneous identifiers...
```

In practice, `\inmodule` is present in nearly every namespace
doc in the codebase. Without it, the namespace won't appear in
the correct module's documentation.

### Restriction: single-module documentation

A namespace spanning multiple modules should be documented in
**only one** module. The official docs warn: "a namespace
documented in one module should not be re-documented in
another." The codebase follows this rule.

### Real examples

**Minimal (QtWebView):**
```cpp
/*!
    \namespace QtWebView
    \inmodule QtWebView
    \brief The QtWebView namespace provides functions that
    make it easier to set up and use the WebView.
    \inheaderfile QtWebView
*/
```

**With since and groups (QSsl):**
```cpp
/*!
    \namespace QSsl
    \brief The QSsl namespace declares enums common to all
    SSL classes in Qt Network.
    \since 4.3
    \ingroup network
    \ingroup ssl
    \inmodule QtNetwork
*/
```

---

## `\headerfile` — Header File Documentation

Documents global functions, types, and macros declared in a
header file outside any class or namespace. Elements use
`\relates` to appear on the headerfile's page.

### Syntax

```qdoc
/*!
    \headerfile <HeaderName>
    \inmodule ModuleName
    \title Display Title
    \ingroup funclists
    \brief One-line description.

    Body paragraph describing header contents.
*/
```

### Mandatory companions

| Command | Purpose | Notes |
|---------|---------|-------|
| `\inmodule` | Module assignment | **Always used** (official example omits it) |
| `\title` | Page heading | Always present |
| `\brief` | Summary | Always present |

### Common companions

| Command | Purpose | Example |
|---------|---------|---------|
| `\ingroup` | Group membership | `\ingroup funclists` |

### Angle bracket convention

Header names **always use angle brackets** in the codebase:
- `\headerfile <QtGlobal>`
- `\headerfile <QtAssert>`
- `\headerfile <QtTypes>`

### File location

Split between `.cpp` files (40%) and `.qdoc` files (60%):
- `.cpp`: Co-located with implementation (e.g., `qglobal.cpp`)
- `.qdoc`: Standalone doc file

### Output filename

Generated from header name: `<QtAlgorithms>` produces
`qtalgorithms.html` (lowercase, no angle brackets).

### Relationship with `\relates`

Macros and global functions use `\relates` to appear on a
headerfile's page:

```cpp
/*!
    \macro void Q_ASSERT(bool test)
    \relates <QtAssert>
    Prints a warning message...
*/
```

The `Q_ASSERT` macro documentation appears on the
`<QtAssert>` page because of `\relates`.

---

## `\macro` — Macro Documentation

Documents C++ preprocessor macros. **Must include `\relates`.**

### Three styles

**Function-like (with parameters):**
```qdoc
/*!
    \macro void Q_ASSERT(bool test)
    \relates <QtAssert>

    Prints a warning message containing the source code
    file name and line number if \a test is \c false.
*/
```

**Declaration-style (with `...`):**
```qdoc
/*!
    \macro Q_PROPERTY(...)
    \relates QObject

    This macro is used for declaring properties in
    classes that inherit QObject.
*/
```

**Simple (no parameters):**
```qdoc
/*!
    \macro Q_OBJECT
    \relates QObject

    The Q_OBJECT macro must appear in the private
    section of a class definition that declares its own
    signals and slots.
*/
```

### Mandatory companion: `\relates`

Every `\macro` must have `\relates` pointing to either:
- A **class**: `\relates QObject`
- A **headerfile**: `\relates <QtAssert>`

Without `\relates`, the macro documentation is **lost** — not
attached to any page.

### Codebase statistics

261 macro docs across 49 files. Heavily concentrated in:
- `qobject.cpp` (25+ macros, all `\relates QObject`)
- `qassert.cpp` (macros `\relates <QtAssert>`)
- `qtypes.cpp`, `qglobal.cpp`, `qnumeric.cpp`

### Common companions

| Command | Purpose | Example |
|---------|---------|---------|
| `\relates` | **Mandatory** — page attachment | `\relates QObject` |
| `\since` | Version introduced | `\since 5.4` |
| `\deprecated` | Deprecation notice | `\deprecated [6.0]` |

### Signature conventions

Function-like macros include full typed signatures with
parameter names:
- `\macro void Q_ASSERT(bool test)`
- `\macro const char *qPrintable(const QString &str)`
- `\macro Q_DECLARE_FLAGS(Flags, Enum)`

The official docs show minimal examples but the codebase
consistently uses full signatures.

---

## Version History

- **v1.0** (2026-03-26): Initial version from audit of 64
  `\namespace`, 63 `\headerfile`, and 261 `\macro` usages
