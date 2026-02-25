# Source File Location from Published URLs

## Overview

When reviewing documentation on doc.qt.io, you need to locate the source .qdoc or .cpp
file to provide accurate line numbers and suggest fixes. This reference documents the
pattern for mapping published URLs to source files.

---

## Quick Reference

### From URL to Source

```
URL: https://doc.qt.io/qt-6/{page-name}.html
                          └─ href: {page-name}.html

Method 1 - Grep local repos (fastest if available):
$ grep -r "{page-name}" {module}/doc/src/

Method 2 - Search index files for href:
$ grep 'href="{page-name}.html"' {module}.index
→ <page name="Page Title" href="{page-name}.html" location="path/to/file.qdoc">

Method 3 - Online index (no local build required):
WebFetch: https://doc-snapshots.qt.io/qt6-dev/{module}.index
Prompt: Search for href="{page-name}.html" and show location attribute
```

### From Title to Source

If you only have the page title:

```bash
# Search by title in index files
$ grep 'title="Supported Platforms"' */doc/*/*.index
→ <page ... title="Supported Platforms" href="supported-platforms.html"
         location="doc/src/platforms/supported-platforms.qdoc">

# Or grep for the title in source files
$ grep -r "\\\\title Supported Platforms" */doc/src/
```

---

## Module-to-Source-Path Mapping

### Common URL Patterns

| URL Pattern | Source Location |
|-------------|-----------------|
| `doc.qt.io/qt-6/{page}.html` | `qt{module}/doc/src/**/{page}.qdoc` |
| Platform pages | `qtdoc/doc/src/platforms/` |
| Getting started | `qtdoc/doc/src/getting-started/` |
| Overviews | `qtdoc/doc/src/overviews/` |
| Class docs | `qt{module}/src/**/*.cpp` (inline comments) |
| QML type docs | `qt{module}/src/**/*.cpp` or `.qdoc` files |

### Module Mappings

| Page Topic | Module | Source Path |
|------------|--------|-------------|
| Platform support | qtdoc | `doc/src/platforms/` |
| Deployment | qtdoc | `doc/src/deployment/` |
| Qt Quick | qtdeclarative | `src/quick/doc/` |
| Widgets | qtbase | `src/widgets/doc/` |
| Core classes | qtbase | `src/corelib/doc/` |
| GUI classes | qtbase | `src/gui/doc/` |
| Network | qtbase | `src/network/doc/` |
| SQL | qtbase | `src/sql/doc/` |
| Qt Creator | qt-creator | `doc/` |

### Documentation Type vs Location

| Doc Type | Topic Command | Source Location |
|----------|---------------|-----------------|
| Overview pages | `\page` | `doc/src/**/*.qdoc` |
| C++ classes | `\class` | Header comments or `.qdoc` files |
| C++ functions | `\fn` | Source file comments |
| QML types | `\qmltype` | `.cpp` or `.qdoc` files |
| Examples | `\example` | Example directory's `doc/` |

---

## Workflow

### Step 1: Identify the Module

From the URL or page content, determine which Qt module owns the page:

```
URL: doc.qt.io/qt-6/supported-platforms.html
Content mentions: "Qt 6.x supported platforms"
→ This is general Qt info → qtdoc module
```

### Step 2: Search for Source

**Option A - Local repos available:**

```bash
# Check if Qt repos exist in current directory
ls -d qt*/

# Search for the page name
grep -r "supported-platforms" qtdoc/doc/src/
→ qtdoc/doc/src/platforms/supported-platforms.qdoc
```

**Option B - Use index files:**

```bash
# Search local index (if built)
grep 'href="supported-platforms.html"' */doc/*/*.index

# Or use online index
# WebFetch https://doc-snapshots.qt.io/qt6-dev/qtdoc.index
# Prompt: Find href="supported-platforms.html" and show location
```

### Step 3: Verify and Read Source

```bash
# Read the source file
cat qtdoc/doc/src/platforms/supported-platforms.qdoc
```

Now you have exact line numbers for your review.

---

## Index File Location Attribute

Index files include a `location` attribute that shows the source file path:

```xml
<page name="supported-platforms.html"
      href="supported-platforms.html"
      title="Supported Platforms"
      location="doc/src/platforms/supported-platforms.qdoc">
```

The `location` attribute is the **relative path from the module root** to the source file.

---

## Examples

### Example 1: Platform Overview Page

```
URL: https://doc.qt.io/qt-6/supported-platforms.html

Step 1: General Qt overview → qtdoc module
Step 2: grep -r "supported-platforms" qtdoc/doc/src/
        → qtdoc/doc/src/platforms/supported-platforms.qdoc
Step 3: Read file for line numbers
```

### Example 2: Class Documentation

```
URL: https://doc.qt.io/qt-6/qstring.html

Step 1: Core class → qtbase module
Step 2: grep -r "\\\\class QString" qtbase/src/
        → qtbase/src/corelib/text/qstring.cpp (inline docs)
Step 3: Read file for line numbers
```

### Example 3: QML Type

```
URL: https://doc.qt.io/qt-6/qml-qtquick-rectangle.html

Step 1: Qt Quick QML type → qtdeclarative module
Step 2: grep -r "\\\\qmltype Rectangle" qtdeclarative/src/
        → qtdeclarative/src/quick/items/qquickrectangle.cpp
Step 3: Read file for line numbers
```

### Example 4: Using Online Index

```
URL: https://doc.qt.io/qt-6/containers.html

Step 1: WebFetch https://doc-snapshots.qt.io/qt6-dev/qtcore.index
        Prompt: Find href="containers.html" and show location attribute

Result: location="doc/src/corelib/doc/src/containers.qdoc"

Step 2: Read qtbase/doc/src/corelib/doc/src/containers.qdoc
```

---

## Common Issues

### "Page not found in index"

The page may be in a different module. Try:
```bash
grep -r 'href="{page}.html"' */doc/*/*.index
```

### "No location attribute"

Some older index files may not include location. Fall back to:
```bash
grep -r "\\\\page {page}.html" */doc/src/
```

### "Multiple matches"

If multiple modules define the same page name:
- Check the URL path for module hints
- Look at the page content for `\inmodule` or `\inqmlmodule`
- The online doc.qt.io uses a single flat namespace

---

## Tips

1. **Prefer local repos** - Faster and more reliable than WebFetch
2. **Check qt5.git layout** - Submodules are in the root directory
3. **Index files are generated** - Need `ninja docs` build to exist locally
4. **doc-snapshots.qt.io has all indexes** - Use for verification without local build
5. **Always verify before suggesting** - Don't guess line numbers from rendered HTML

---

## Version History

- **v1.0** (2026-02-23): Initial version documenting source file location pattern.
  Identified during review of supported-platforms.html where source file was
  needed to verify admonition clustering findings.
