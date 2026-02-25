---
name: skill-module-export
description: Reference for Qt C++ export macros and QML registration macros that indicate public APIs requiring documentation
version: 1.4
---

# Qt Export Macro Reference

This reference documents Qt export macros that indicate symbol visibility. Export macros alone do NOT determine whether a class should be `\internal` - context matters.

## Purpose

Documentation agents use this reference to:
1. Identify symbol visibility (exported vs internal linkage)
2. Understand when export + `\internal` is valid (common pattern)
3. Distinguish between app-developer APIs and plugin/module-internal APIs

## Quick Decision

**Export macro + `\internal` is VALID for:**
- Private implementation classes (e.g., `QWidgetPrivate`, `QObjectPrivate`)
- QPA classes (Qt Platform Abstraction - for platform plugins)
- Classes in `_p.h` headers exported for cross-module internal use
- Factory classes for internal plugin loading

**Export macro WITHOUT `\internal` required for:**
- Public header classes intended for application developers
- Classes documented in public API reference

**No export macro = truly internal:**
- Can always add `\internal` documentation

## Common Qt Export Macros

**Most frequently used:**
- `Q_CORE_EXPORT` - QtCore classes
- `Q_GUI_EXPORT` - QtGui classes
- `Q_WIDGETS_EXPORT` - QtWidgets classes
- `Q_NETWORK_EXPORT` - QtNetwork classes
- `Q_QML_EXPORT` - QtQml classes
- `Q_QMLCOMPILER_EXPORT` - QtQmlCompiler classes
- `Q_QUICK_EXPORT` - QtQuick classes
- `Q_QUICKCONTROLS2_EXPORT` - QtQuickControls classes
- `Q_QUICKTEMPLATES2_EXPORT` - QtQuickTemplates classes
- `Q_SQL_EXPORT` - QtSql classes
- `Q_MULTIMEDIA_EXPORT` - QtMultimedia classes
- `Q_WEBENGINE_EXPORT` - QtWebEngine classes

**Others:** 70+ additional macros for Qt modules (3D, Charts, Sensors, etc.)

**Complete list:** See qt6/qtbase/src/corelib/global/qglobal.h and module export headers

## Pattern Recognition

Most Qt modules follow the pattern:
```
Q_<MODULE>_EXPORT
```

Where `<MODULE>` is the uppercase module name without "Qt" prefix:
- QtCore -> `Q_CORE_EXPORT`
- QtQuick -> `Q_QUICK_EXPORT`
- QtMultimedia -> `Q_MULTIMEDIA_EXPORT`

## Detection in C++ Headers

Export macros appear between `class` keyword and class name:

```cpp
class Q_CORE_EXPORT QObject  // <- Public API
{
    Q_OBJECT
    ...
};

class QObjectPrivate  // <- No export macro = internal
{
    ...
};
```

## Gadget Export Pattern

Some classes use `Q_GADGET_EXPORT` instead of class-level export macros:

```cpp
class Any final : public QProtobufMessage
{
    Q_GADGET_EXPORT(Q_PROTOBUFWELLKNOWNTYPES_EXPORT)
    Q_PROPERTY(QString typeUrl READ typeUrl WRITE setTypeUrl)
    ...
};
```

**Key differences from class export:**
- Export macro is INSIDE class body, not before class name
- Used with `Q_GADGET` instead of `Q_OBJECT`
- Still indicates public API

**Detection pattern:**
```regex
Q_GADGET_EXPORT\s*\(\s*(Q_\w+_EXPORT)\s*\)
```

**Examples:**
- `Q_GADGET_EXPORT(Q_PROTOBUFWELLKNOWNTYPES_EXPORT)` - QtProtobuf types
- `Q_GADGET_EXPORT(Q_CORE_EXPORT)` - Core value types

## Export + Internal Pattern (Accepted)

**This is a VALID, well-established pattern in Qt.** Many classes have both export macros and `\internal` tags. This is NOT a conflict to be avoided.

```cpp
// Header: Q_GUI_EXPORT for cross-module visibility
class Q_GUI_EXPORT QWidgetPrivate : public QObjectPrivate

// Documentation: \internal = excluded from app-developer docs
/*!
    \class QWidgetPrivate
    \inmodule QtWidgets
    \internal
*/
```

**Why this pattern exists:**
1. **ABI stability** - Symbols must be exported for binary compatibility
2. **Cross-module use** - Other Qt modules need access to these classes
3. **Plugin APIs** - Platform plugins need these symbols
4. **Not for app developers** - `\internal` hides from public documentation

**Existing examples in Qt (18+ classes):**

| Module | Examples |
|--------|----------|
| QtCore | QAbstractItemModelPrivate, QPropertyBindingPrivate |
| QtGui | QFileSystemModelPrivate, QPointingDevicePrivate, QShortcutPrivate |
| QtWidgets | QWidgetPrivate, QGraphicsItemPrivate |
| QtQml | QQmlComponentPrivate, QQmlPropertyCache, QQmlNotifier |

**When to use export + internal:**
- Private implementation classes (`*Private`)
- QPA classes (Qt Platform Abstraction)
- Factory classes for plugin loading
- Classes in `_p.h` headers needed by other modules

**Impact on links:**
- `\internal` excludes class from public documentation index
- Links to internal classes will produce warnings
- Use `\c` for code formatting instead of `\l` for links to internal classes

## Special Cases

1. **Private classes with export macros** - COMMON pattern; use `\internal` (see "Export + Internal Pattern")
2. **Classes in `_p.h` headers** - Usually `\internal`, even with export macros
3. **QPA classes** - Typically exported + `\internal` (for platform plugins, not app developers)
4. **Namespaced classes** - Check header location and intended audience
5. **Template classes** - No export macro needed (header-only)
6. **Experimental/Labs modules** - Public API if in public header; document as experimental

## Usage in Documentation Agents

**Workflow:**
1. Read header file location and class name
2. Determine intended audience:
   - Public header (`.h`) + public class name → app developers
   - Private header (`_p.h`) OR `*Private` class → internal use
   - QPA class (`QPlatform*`) → platform plugin developers
3. Apply documentation:
   - App developer API → full `\class` documentation required
   - Internal/Private/QPA → `\class`, `\inmodule`, `\internal` is correct

**Decision tree:**
```
Is it a *Private class or in _p.h header?
├─ YES → Use \internal (even with export macro)
└─ NO → Is it a QPA class (QPlatform*)?
        ├─ YES → Use \internal (even with export macro)
        └─ NO → Is it in a public header?
                ├─ YES → Full documentation required
                └─ NO → Use \internal
```

**Examples:**
```cpp
class QWidgetPrivate : public QObjectPrivate  // <- *Private class, use \internal
class Q_GUI_EXPORT QPlatformWindow            // <- QPA class, use \internal
class Q_QUICK_EXPORT QQuickItem : public QObject  // <- Public API, full docs
class QInternalClass : public QObject         // <- No export, use \internal
```

## Detection Pattern

**Class export (before class name):**
```regex
class\s+(Q_\w+_EXPORT|QT\w+_EXPORT|QAXCONTAINER_EXPORT|QAXSERVER_EXPORT)\s+\w+
```

**Gadget export (inside class body):**
```regex
Q_GADGET_EXPORT\s*\(\s*(Q_\w+_EXPORT)\s*\)
```

**Matches:**
- `class Q_CORE_EXPORT QObject`
- `class Q_QUICK_EXPORT QQuickItem`
- `class QT3DCORE_EXPORT QEntity`
- `Q_GADGET_EXPORT(Q_PROTOBUFWELLKNOWNTYPES_EXPORT)`

**Not export macros:**
- `Q_OBJECT`, `Q_GADGET`, `Q_NAMESPACE` (meta-object macros, not exports)
- `Q_DECLARE_FLAGS`, `Q_ENUM` (not exports)

## Summary

**Decision Tree:**

```
Is it a *Private class, in _p.h, or a QPA class?
├─ YES → \internal is correct (even with export macro)
└─ NO → Is it in a public header with export macro?
        ├─ YES → Full documentation required (app developer API)
        └─ NO → \internal is correct
```

**Key Points:**
- Export macros indicate symbol visibility, NOT documentation requirements
- Export + `\internal` is a VALID, common pattern (18+ existing cases)
- Class name and header location determine intended audience
- `*Private` classes, QPA classes, and `_p.h` classes are internal
- Only public header classes for app developers need full documentation

## QML Registration Macros

Classes can be exposed to QML using registration macros. These indicate that a QML type needs documentation.

### Common QML Macros

| Macro | Purpose | QDoc Command |
|-------|---------|--------------|
| `QML_ELEMENT` | Expose class to QML (same name) | `\qmltype ClassName` |
| `QML_NAMED_ELEMENT(Name)` | Expose with custom QML name | `\qmltype Name` |
| `QML_VALUE_TYPE(name)` | Expose Q_GADGET as value type | `\qmlvaluetype name` |
| `QML_UNCREATABLE("reason")` | Abstract type, can't instantiate | Add note in docs |
| `QML_SINGLETON` | Singleton in QML | Document as singleton |
| `QML_ANONYMOUS` | Register but don't expose by name | Usually no docs needed |
| `QML_FOREIGN(Type)` | Register another type | Docs on foreign type |
| `QML_ATTACHED(Type)` | Provides attached properties | `\qmlattachedproperty` |
| `QML_ADDED_IN_VERSION(M, N)` | Version when added | `\since` |

### QDoc Commands for QML

| Command | Purpose |
|---------|---------|
| `\qmltype TypeName` | Documents QML type |
| `\qmlvaluetype typename` | Documents QML value type (lowercase!) |
| `\nativetype ClassName` | Links QML type to backing C++ class |
| `\inqmlmodule ModuleName` | Associates with QML module |
| `\qmlproperty type Type::prop` | Documents QML property |
| `\qmlsignal Type::signalName()` | Documents QML signal |
| `\qmlmethod Type::methodName()` | Documents QML method |

### C++ Export + QML Registration

When a class has BOTH C++ export macro AND QML registration, it may need **separate documentation** for each API:

**Example: QQuick3DTextureData**
```cpp
// Header (public - qquick3dtexturedata.h)
class Q_QUICK3D_EXPORT QQuick3DTextureData : public QQuick3DObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TextureData)
    QML_UNCREATABLE("TextureData is Abstract")
    ...
};
```

**Documentation has TWO blocks:**
```cpp
/*!
    \qmltype TextureData
    \nativetype QQuick3DTextureData
    \inqmlmodule QtQuick3D
    \brief Base type for custom texture data.
    ...
*/

/*!
    \class QQuick3DTextureData
    \inmodule QtQuick3D
    \brief Base class for defining custom texture data.
    ...
*/
```

### Documentation Decision Matrix

| Header | Export? | QML Macro? | C++ Docs | QML Docs |
|--------|---------|------------|----------|----------|
| Public (.h) | Yes | Yes | `\class` required | `\qmltype` required |
| Public (.h) | Yes | No | `\class` required | N/A |
| Public (.h) | No | Yes | Optional | `\qmltype` required |
| Private (_p.h) | Yes | Yes | Usually skip* | `\qmltype` required |
| Private (_p.h) | Yes | No | `\internal` or skip | N/A |
| Private (_p.h) | No | No | `\internal` or skip | N/A |

*Export in private header = internal Qt module use; C++ class docs usually omitted.

### The `\nativetype` Command

`\nativetype` in a `\qmltype` block links QML documentation to its C++ backing class:

```cpp
/*!
    \qmltype WebChannel
    \nativetype QQmlWebChannel    // <-- Links to C++ class
    \inqmlmodule QtWebChannel
    \brief QML interface to QWebChannel.
*/
```

**Key points:**
- `\nativetype` does NOT create C++ class documentation
- If C++ API is public (export + public header), add separate `\class` block
- Links in C++ docs can reference QML type and vice versa

### Common Warning: Undocumented Native Type

**Warning:**
```
No output generated for property 'QFoo::bar' because 'QFoo' is undocumented
```

**Cause:** `\property QFoo::bar` exists but no `\class QFoo` documentation.

**Fix options:**
1. Add `\class QFoo` documentation (if public C++ API)
2. Remove C++ `\property` docs (if QML-only API, `\qmlproperty` suffices)

### Value Types vs Object Types

**QML Object Types** (inherit QObject):
- Use `QML_ELEMENT` or `QML_NAMED_ELEMENT`
- Document with `\qmltype TypeName` (PascalCase)

**QML Value Types** (Q_GADGET):
- Use `QML_VALUE_TYPE(name)`
- Document with `\qmlvaluetype typename` (lowercase!)
- Example: `\qmlvaluetype geoCoordinate` (not `GeoCoordinate`)

### Detection Patterns

**QML registration (any of these = needs QML docs):**
```regex
QML_ELEMENT|QML_NAMED_ELEMENT\s*\(|QML_VALUE_TYPE\s*\(|QML_SINGLETON
```

**Full public API (both C++ and QML docs needed):**
- Public header (no `_p.h`)
- Has C++ export macro (e.g., `Q_QUICK3D_EXPORT`)
- Has QML registration macro

## Version History

- **v1.4** (2026-02-17): Clarified export+internal as VALID pattern; updated decision tree based on codebase search (18+ existing examples)
- **v1.3** (2026-02-04): Added QML registration macros and documentation patterns
- **v1.2** (2026-02-04): Added Q_GADGET_EXPORT pattern and export+internal conflict
- **v1.1** (2026-02-04): Renamed from qt-export-checker to skill-module-export
- **v1.0** (2025-11-27): Initial version with comprehensive Qt 6 export macro list
