---
name: skill-qdoc-output
description: Reference for QDoc HTML output filename generation patterns by node type
metadata:
  version: "1.0"
---

# QDoc Output Filename Generation

How QDoc generates HTML filenames for different documentation node types.

## Source Code Reference

**Primary implementation:** `qttools/src/qdoc/qdoc/src/qdoc/generator.cpp`

| Function | Lines | Purpose |
|----------|-------|---------|
| `Generator::fileBase()` | 308-376 | Generates base filename without extension |
| `Generator::fileName()` | 418-438 | Adds file extension to base |
| `Generator::outputPrefix()` | 2103-2117 | Returns prefix by genus (e.g., "qml-") |
| `Generator::outputSuffix()` | 2119-2132 | Returns suffix by node type |

**Supporting code:**
- `Utilities::asAsciiPrintable()` - `utilities.cpp:157-197` - Canonicalizes to lowercase ASCII

## Filename Patterns by Node Type

| Node Type | Pattern | Example |
|-----------|---------|---------|
| C++ class | `{classname}.html` | `qwidget.html` |
| C++ class (namespaced) | `{namespace}-{class}.html` | `qt-alignment.html` |
| QML type | `qml-{module}-{type}.html` | `qml-qtquick-rectangle.html` |
| QML value type | `qml-{type}.html` | `qml-color.html` |
| C++ module | `{module}-module.html` | `qtcore-module.html` |
| QML module | `{module}-qmlmodule.html` | `qtquick-qmlmodule.html` |
| Group | `{groupname}.html` | `animation.html` |
| Example | `{project}-{name}-example.html` | `qtbase-calculator-example.html` |
| Page (overviews) | per `\page` command in source | `getting-started.html` |

**Important:** For `\page` documents, the HTML filename is explicitly specified in the source file's `\page` command. Always read the source to verify. For all other types (class, QML type, module, group, example), QDoc generates the filename automatically - verify via index files.

## Algorithm Detail

### fileBase() Logic (generator.cpp:308-376)

```
1. If CollectionNode:
   - If QmlModule: append "-qmlmodule"
   - Else if Module: append "-module"
   - Else (Group): no suffix
   - Append outputSuffix()

2. If TextPageNode:
   - If Example: prepend "{project}-", append "-example"

3. If QmlType:
   - If has logicalModuleName and not QmlBasicType:
     - Prepend "{logicalModuleName}{outputSuffix}-"
   - Prepend outputPrefix() (default: "qml-")

4. If ProxyNode:
   - Append "-{moduleName}-proxy"

5. Else (C++ class/namespace):
   - Build from parent chain with hyphens
   - For undocumented-here namespaces: append "-sub-{moduleName}"
   - Append outputSuffix()

6. Prepend outputPrefix()
7. Canonicalize with asAsciiPrintable()
```

### Canonicalization (utilities.cpp:157-197)

The `asAsciiPrintable()` function:
- Converts uppercase to lowercase
- Keeps alphanumerics and hyphens
- Replaces other characters with hyphens
- Adds MD5 hash suffix for non-ASCII content

## Index File Verification

HTML filenames can be verified in QDoc index files:

```bash
# Find class
grep 'class name="QWidget"' */doc/*/*.index
# Output: <class name="QWidget" href="qwidget.html" ...>

# Find QML type
grep 'qmlclass name="Rectangle"' */doc/*/*.index
# Output: <qmlclass name="Rectangle" href="qml-qtquick-rectangle.html" ...>

# Find group
grep '<group name="animation"' */doc/*/*.index
# Output: <group name="animation" href="animation.html" ...>

# Find module
grep '<module name="QtCore"' */doc/*/*.index
# Output: <module name="QtCore" href="qtcore-module.html" ...>
```

## Configuration

Prefixes and suffixes are configurable in qdocconf:

```
outputPrefixes = QML
outputPrefixes.QML = qml-

outputSuffixes = QML
outputSuffixes.QML =
```

**Defaults:**
- QML genus: prefix "qml-", no suffix
- CPP genus: no prefix, no suffix

## Common Patterns

### QML Type in Module

```
Input:  \qmltype Rectangle
        \inqmlmodule QtQuick

Output: qml-qtquick-rectangle.html
```

**Algorithm:**
1. Start with "rectangle" (lowercased)
2. Prepend "qtquick-" (logical module name)
3. Prepend "qml-" (output prefix)
4. Result: "qml-qtquick-rectangle"

### C++ Class in Namespace

```
Input:  \class Qt::Alignment

Output: qt-alignment.html
```

**Algorithm:**
1. Build chain: "Qt" + "-" + "Alignment"
2. Lowercase: "qt-alignment"
3. Result: "qt-alignment"

### Group Page

```
Input:  \group animation
        \title Animation Framework

Output: animation.html
```

**Algorithm:**
1. Start with "animation" (group name)
2. No suffix (not Module or QmlModule)
3. Result: "animation"

## Integration

- **skill-doc-diff:** Uses HTML filename patterns for the HTML field
- **skill-qdoc:** QDoc node system and link resolution context

## Version History

- **v1.0** (2026-02-11): Initial version
  - Documented fileBase() algorithm from generator.cpp
  - Added patterns for all node types including Group
  - Added index file verification examples
