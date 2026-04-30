---
name: skill-all-docs
description: Qt documentation products, modules, repository structure, and API types. Apply when working with Qt documentation, resolving module names, or understanding Qt's documentation ecosystem.
metadata:
  version: "1.0.0"
---

# Qt Documentation Ecosystem Reference

Reference for Qt documentation products, modules, repository structure, and API documentation patterns.

## When to Use This Skill

This skill activates when working with:
- Qt module names and `\inmodule` / `\inqmlmodule` values
- Qt repository structure and file locations
- C++ vs QML vs hybrid API documentation patterns
- Qt product documentation (tools, solutions, frameworks)
- Finding where documentation lives in the codebase

## Quick Reference

### Common Module Names

| Module | `\inmodule` | QML Module |
|--------|-------------|------------|
| Qt Core | QtCore | - |
| Qt GUI | QtGui | - |
| Qt Widgets | QtWidgets | - |
| Qt Quick | QtQuick | QtQuick |
| Qt Quick Controls | QtQuickControls | QtQuick.Controls |

For complete module lists, read `references/modules.md`.

### API Documentation Commands

| API Type | Type Command | Module Command |
|----------|--------------|----------------|
| C++ | `\class` | `\inmodule QtWidgets` |
| QML | `\qmltype` | `\inqmlmodule QtQuick` |
| Hybrid | Both | Both + `\nativetype` |

For API documentation patterns, read `references/api-types.md`.

### Key Repository Paths

| Path | Content |
|------|---------|
| `qtbase/src/` | Core, GUI, Widgets, Network source |
| `qtdeclarative/src/` | QML, Quick source |
| `qttools/src/qdoc/` | QDoc tool source |
| `qtdoc/doc/` | Cross-module documentation |
| `<module>/src/**/*.qdoc` | Standalone doc files |

For full repository structure, read `references/repository.md`.

## Reference Materials

| File | Content |
|------|---------|
| `references/products.md` | Qt versions, tools, solutions, QA products |
| `references/modules.md` | Essentials and Add-ons module lists |
| `references/repository.md` | Super-repo structure, module categories, paths |
| `references/api-types.md` | C++, QML, hybrid documentation patterns |

## External References

- Published docs: https://doc.qt.io/
- Dev snapshots: https://doc-snapshots.qt.io/qt6-dev/
- All topics: https://doc.qt.io/all-topics.html
- Modules list: https://doc.qt.io/qt-6/qtmodules.html
- Code review: https://codereview.qt-project.org/
