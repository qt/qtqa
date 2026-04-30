# Qt Documentation Products

## Qt Framework Versions

| Version | Status |
|---------|--------|
| Qt 6.10 | Latest |
| Qt 6.9 | Current |
| Qt 6.8 | LTS |
| Qt 6.5 | LTS |

Each version has corresponding **Qt for Python** and **Boot to Qt** documentation.

---

## Specialized Solutions

| Product | Purpose |
|---------|---------|
| **Qt for MCUs** | Microcontroller development |
| **Qt for Android Automotive** | Automotive platform |
| **Qt Safe Renderer** | Safety-critical rendering |
| **Qt Application Manager** | Wayland compositor/app lifecycle |
| **Qt Interface Framework** | Automotive UI framework |
| **Qt Device Utilities** | Embedded device configuration |

---

## Development Tools

| Tool | Purpose |
|------|---------|
| **Qt Creator** | Main IDE |
| **Qt Design Studio** | UI/UX design tool |
| **Qt Extension for VS Code** | VS Code integration |
| **Qt VS Tools** | Visual Studio integration |
| **Qt Linguist** | Translation tool |
| **Qt Assistant** | Documentation browser |
| **QML Live** | Live QML preview |
| **Qt Installer Framework** | Deployment packaging |

---

## Build Systems

| System | Status |
|--------|--------|
| CMake | Preferred |
| qmake | Legacy |
| Qbs | Alternative |

---

## Quality Assurance Products

| Product | Purpose |
|---------|---------|
| **Squish** | GUI testing |
| **Coco** | Code coverage |
| **Test Center** | Test management |
| **Qt Insight** | Analytics/telemetry |

---

## Cross-Product Documentation Dependencies

When Qt Reference Documentation changes, other products may be affected.

### doc.qt.io Products

| Product | URL | Links to Qt Ref | Check When |
|---------|-----|-----------------|------------|
| **Qt for Python** | doc.qt.io/qtforpython-6/ | C++ classes (via HTML URLs) | Class renamed/removed |
| **Qt Creator** | doc.qt.io/qtcreator/ | Qt APIs, QML types, page titles | Any public API change, page title/target renamed |
| **Qt Design Studio** | doc.qt.io/qtdesignstudio/ | QML types, Controls, page titles | QML type renamed, page title/target renamed |
| **Qt for MCUs** | doc.qt.io/QtForMCUs/ | Subset of Qt Quick | Quick type renamed |
| **Boot to Qt** | doc.qt.io/Boot2Qt/ | Platform APIs | Platform API change |
| **Qt Installer Framework** | doc.qt.io/qtinstallerframework/ | Installer APIs | Installer API change |

### qt.io Materials

| Material | URL Pattern | Links to Qt Ref | Check When |
|----------|-------------|-----------------|------------|
| **Marketing** | qt.io/product/* | Features, modules | Module/feature renamed |
| **Licensing** | qt.io/licensing/* | Modules | Module renamed |
| **Blog** | qt.io/blog/* | APIs, examples | Major API change |
| **Wiki** | wiki.qt.io/* | Guidelines, APIs | API patterns change |

### Link Patterns by Product

| Product | Link Syntax | Example |
|---------|-------------|---------|
| Qt for Python | `:qt6:\`Class <class.html>\`` | `:qt6:\`QWidget <qwidget.html>\`` |
| Qt Creator | `\l{ClassName}`, `\l{QmlType}`, `\l{Page Title}` | `\l{QObject}`, `\l{Supported Platforms}` |
| Qt Design Studio | `\l{QmlType}`, `\l{Page Title}` | `\l{Rectangle}`, `\l{Supported Platforms}` |
| Marketing | HTML links | `<a href="doc.qt.io/qt-6/qwidget.html">` |

### How Cross-Product Linking Works

**Qt Creator and Qt Design Studio** are built with QDoc and declare
`depends` on Qt modules in their qdocconf files. Their builds load Qt
module `.index` files, so `\l{Any Qt Target}` in Creator/DS docs resolves
against those indexes. If a Qt target is renamed, Creator/DS links break
at their next build. This is the same mechanism as cross-module linking
within Qt itself.

**Qt for Python** uses Sphinx with intersphinx and links to Qt docs via
HTML URLs (`:qt6:\`Class <class.html>\``), not QDoc title resolution. A
title rename does NOT break PySide links unless the HTML filename also
changes.

**Marketing/Blog/Wiki** use hardcoded HTML URLs. Only affected if the
HTML filename changes.

| Product | Build System | Links via | Title rename breaks links? |
|---------|-------------|-----------|---------------------------|
| Qt Creator | QDoc + `depends` | Index file resolution | Yes |
| Qt Design Studio | QDoc + `depends` | Index file resolution | Yes |
| Qt for Python | Sphinx + intersphinx | HTML URLs | Only if filename changes |
| Marketing/Blog | Static HTML | Hardcoded URLs | Only if filename changes |

### Index File Locations

| Product | Verified Source | Fallback |
|---------|----------------|----------|
| Qt 6 Reference | `doc-snapshots.qt.io/qt6-dev/{module}.index` | Local: `qtbase/doc/{module}/{module}.index` |
| Qt for Python | (no published index file) | Check published HTML: `doc.qt.io/qtforpython-6/` |
| Qt Creator | (no published index file) | Check published HTML: `doc.qt.io/qtcreator/` |
| Qt Design Studio | (no published index file) | Check published HTML: `doc.qt.io/qtdesignstudio/` |

**Note:** Only Qt 6 Reference modules publish `.index` files at
doc-snapshots.qt.io. Qt Creator, Design Studio, and Qt for Python do not
publish index files externally. For these products, verify by checking the
published HTML pages or by cloning the source repository.

### Repository Locations

| Product | Repository | Doc Path |
|---------|------------|----------|
| Qt for Python | pyside-setup | sources/pyside6/doc/ |
| Qt Creator | qt-creator | doc/qtcreator/ |
| Qt Design Studio | qt-design-studio | doc/ |
| Wiki | wiki.qt.io | (web CMS) |
| Marketing | qt.io | (web CMS) |

### High-Impact APIs

These APIs are referenced across multiple products:

| API | Referenced By |
|-----|---------------|
| QObject, QWidget, QApplication | Qt for Python, Qt Creator |
| Item, Rectangle, ListView | Qt Creator, Qt Design Studio, Qt for MCUs |
| Qt Quick Controls | Qt Creator, Qt Design Studio |
| Qt Core classes | All products |
