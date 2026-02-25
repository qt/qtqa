# API Types and Documentation Patterns

## C++ API

**Documented with**: `\class`, `\fn`, `\enum`, `\property`
**Module declaration**: `\inmodule QtWidgets`
**Location**: `.cpp` and `.h` files

```cpp
/*!
    \class QFileDialog
    \inmodule QtWidgets
    \brief The QFileDialog class provides a dialog for selecting files or directories.
*/
```

---

## QML API

**Documented with**: `\qmltype`, `\qmlproperty`, `\qmlsignal`, `\qmlmethod`
**Module declaration**: `\inqmlmodule QtQuick.Controls`
**Location**: `.qml` files or `.cpp` files exposing types to QML

```cpp
/*!
    \qmltype FolderDialog
    \inqmlmodule QtQuick.Dialogs
    \brief A folder dialog.
*/
```

---

## Hybrid QML/C++ API

**Both** `\class` and `\qmltype` documentation needed. C++ class exposed to QML via `QML_ELEMENT` or `qmlRegisterType`.

**Link QML to C++**: Use `\nativetype`

```cpp
/*!
    \qmltype Rectangle
    \inqmlmodule QtQuick
    \nativetype QQuickRectangle
    \brief A rectangle with optional border and fill.
*/

/*!
    \class QQuickRectangle
    \inmodule QtQuick
    \internal
*/
```

---

## Documentation Commands by API Type

| Aspect | C++ | QML | Hybrid |
|--------|-----|-----|--------|
| Primary user | C++ developer | QML developer | Both |
| Module command | `\inmodule` | `\inqmlmodule` | Both |
| Type command | `\class` | `\qmltype` | Both |
| Function doc | `\fn` | `\qmlmethod` | Both |
| Property doc | `\property` | `\qmlproperty` | Both |
| Signal doc | `\fn` for signals | `\qmlsignal` | Both |

---

## Module Declaration Quick Reference

**C++ classes:**
```cpp
\inmodule QtCore
\inmodule QtWidgets
\inmodule QtNetwork
```

**QML types:**
```cpp
\inqmlmodule QtQuick
\inqmlmodule QtQuick.Controls
\inqmlmodule QtQuick.Dialogs
```

**Combined (hybrid):**
```cpp
\qmltype Button
\inqmlmodule QtQuick.Controls
\nativetype QQuickButton
```
