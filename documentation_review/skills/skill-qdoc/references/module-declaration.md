# Module Declaration Reference

**Verified against:** QDoc manual (doc.qt.io/qt-6), 94 `\module`
and 104 `\qmlmodule` declarations in qt5 super-repo.

## `\module` — C++ Module Declaration

Creates a page listing all C++ classes belonging to a module.
Classes associate via `\inmodule` in their `\class` docs.

### Syntax

```qdoc
/*!
    \module ModuleName
    \title Qt {Name} C++ Classes
    \qtcmakepackage ComponentName
    \qtvariable variablename
    \ingroup modules
    \since {version}
    \brief {One-line description}.

    {Body paragraph describing what the module provides.}

    \sa {Related modules or pages}
*/
```

### Mandatory companions (from codebase analysis)

| Command | Purpose | Example |
|---------|---------|---------|
| `\title` | Page heading | `Qt Network C++ Classes` |
| `\brief` | Summary for listings | `Provides classes for TCP/IP clients and servers.` |
| `\ingroup modules` | Appears in module listings | Always `modules` |
| `\qtcmakepackage` | CMake `find_package` component | `Network` |

### Common companions

| Command | Purpose | Example |
|---------|---------|---------|
| `\qtvariable` | qmake QT variable | `network` |
| `\since` | Version introduced | `6.5` |
| `\deprecated` | Deprecation notice | `\deprecated [6.10]` |
| `\noautolist` | Suppress auto class list | When using `\generatelist` |

### Title pattern

**Official docs show:** "Qt Network Module"
**Codebase uses:** "Qt Network C++ Classes"

Follow the codebase pattern. Every `\module` title in the
qt5 super-repo uses "Qt {Name} C++ Classes".

### Real examples

**QtSql (typical):**
```qdoc
/*!
    \module QtSql
    \title Qt SQL C++ Classes
    \ingroup modules
    \qtcmakepackage Sql
    \qtvariable sql
    \brief Provides a driver layer, SQL API layer, and a user
    interface layer for SQL databases.
*/
```

**QtWebSockets (with \since):**
```qdoc
/*!
    \module QtWebSockets
    \title Qt WebSockets C++ Classes
    \ingroup modules
    \qtcmakepackage WebSockets
    \qtvariable websockets
    \since 5.3
    \brief Provides classes for WebSocket-based communication.
*/
```

---

## `\qmlmodule` — QML Module Declaration

Creates a page listing all QML types belonging to a module.
QML types associate via `\inqmlmodule`.

### Syntax

**Modern style (no version — preferred):**
```qdoc
/*!
    \qmlmodule ModuleName
    \title Qt {Name} QML Types
    \ingroup qmlmodules
    \brief {One-line description}.

    {Body paragraph describing QML types provided.}

    To use the types, add the following import statement:
    \qml
    import ModuleName
    \endqml
*/
```

**Legacy style (with version):**
```qdoc
/*!
    \qmlmodule QtWebSockets 1.\QtMinorVersion
    \title Qt WebSockets QML Types
    \ingroup qmlmodules
    \brief Provides QML types for WebSocket-based communication.
*/
```

### Mandatory companions

| Command | Purpose | Example |
|---------|---------|---------|
| `\title` | Page heading | `Qt Multimedia QML Types` |
| `\brief` | Summary for listings | `Provides QML types for multimedia support.` |
| `\ingroup qmlmodules` | Appears in QML module listings | Always `qmlmodules` |

### Common companions

| Command | Purpose |
|---------|---------|
| `\since` | Version introduced |
| `\noautolist` | Suppress auto type list (when using `\generatelist`) |

### Version parameter

**Official docs:** Show version as `\qmlmodule ModuleName VERSION`
**Modern codebase:** Omits version entirely
**Legacy codebase:** Uses `1.\QtMinorVersion` macro

Modern modules should omit the version parameter. QDoc infers
module membership from the build system.

### Discrepancy: `\inqmlmodule` usage

The official docs require `\inqmlmodule` in every QML type doc.
In practice, modern QDoc infers QML module membership from CMake
configuration. Explicit `\inqmlmodule` is still common but not
strictly required in all cases.

---

## Relationship between `\module` and `\qmlmodule`

A Qt module with both C++ and QML APIs needs both declarations:

```qdoc
// C++ module
/*!
    \module QtMultimedia
    \title Qt Multimedia C++ Classes
    \ingroup modules
    \qtcmakepackage Multimedia
    ...
*/

// QML module
/*!
    \qmlmodule QtMultimedia
    \title Qt Multimedia QML Types
    \ingroup qmlmodules
    ...
*/
```

The module overview page (`\page qtmultimedia-index.html`)
links to both via `\l{Qt Multimedia C++ Classes}` and
`\l{Qt Multimedia QML Types}`.

---

## Version History

- **v1.0** (2026-03-26): Initial version from audit of 94
  `\module` and 104 `\qmlmodule` declarations
