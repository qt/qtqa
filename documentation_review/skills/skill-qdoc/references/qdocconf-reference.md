# QDocconf Reference

## Complete qdocconf Example

```qdocconf
# Project identification
project = MyModule
description = My Module Reference Documentation
version = $QT_VERSION
url = https://doc.qt.io/qt-6

# Dependencies
depends = QtCore QtGui
indexes = $QT_INSTALL_DOCS/qtcore/qtcore.index

# Sources
headerdirs = ../src
sourcedirs = ../src ../doc/src
exampledirs = ../examples
imagedirs = ../doc/images

# Output
outputdir = ./html
outputformats = HTML

# Warning control
warninglimit = 0                                    # Fail build if warnings exceed limit
spurious += "Can't link to 'unfixable target'"     # Suppress unfixable warnings
spurious += "Output file already exists, .*"        # Regex pattern supported

# Index generation
generateindex = true
locationinfo = true

# HTML configuration
HTML.outputsubdir = mymodule
HTML.stylesheets = style/offline.css
HTML.footer = "<div>My Company</div>"

# Qt Help
qhp.projects = MyModule
qhp.MyModule.file = mymodule.qhp
qhp.MyModule.namespace = com.mycompany.mymodule.$QT_VERSION_TAG
qhp.MyModule.virtualFolder = mymodule
qhp.MyModule.indexTitle = My Module
qhp.MyModule.subprojects = classes
qhp.MyModule.subprojects.classes.title = C++ Classes
qhp.MyModule.subprojects.classes.selectors = class

# Macros
macro.myproduct = "My Product"
macro.since = "\\b{Since:} \\1"
macro.deprecated = "\\b{Deprecated since \\1.} Use \\l{\\2} instead."
```

---

## File Flow Summary

```
Source Code (.cpp, .h, .qml)
        ↓
    QDoc parses
        ↓
┌───────┴────────┐
↓                ↓
.index           HTML
(for deps)       (.html files)
                     ↓
                 qhelpgenerator
                     ↓
                   .qch
                     ↓
              Qt Assistant
```

---

## QDoc Commands Quick Reference

### Topic Commands
`\class`, `\fn`, `\enum`, `\property`, `\typedef`, `\variable`, `\namespace`, `\headerfile`, `\module`, `\page`, `\group`, `\example`, `\externalpage`

### QML Topic Commands
`\qmltype`, `\qmlproperty`, `\qmlmethod`, `\qmlsignal`, `\qmlattachedproperty`, `\qmlattachedsignal`, `\qmlenum`, `\qmlvaluetype`, `\qmlmodule`

### Context Commands
`\inmodule`, `\ingroup`, `\inheaderfile`, `\inqmlmodule`, `\relates`, `\inherits`, `\since`, `\deprecated`, `\internal`, `\preliminary`

### Linking Commands
`\l`, `\sa`, `\target`, `\keyword`

### Markup Commands
`\a`, `\b`, `\c`, `\e`, `\tt`, `\uicontrol`, `\note`, `\warning`

### Code Commands
`\code`, `\endcode`, `\qml`, `\endqml`, `\snippet`, `\quotefile`, `\quotefromfile`

### Structure Commands
`\section1`-`\section4`, `\list`, `\li`, `\table`, `\row`, `\header`

---

## References

- [QDoc Manual](https://doc.qt.io/qt-6/qdoc-index.html)
- [QDoc Commands](https://doc.qt.io/qt-6/27-qdoc-commands-alphabetical.html)
- [Qt Writing Guidelines](https://wiki.qt.io/Qt_Writing_Guidelines)
- [Qt Help Framework](https://doc.qt.io/qt-6/qthelp-framework.html)
