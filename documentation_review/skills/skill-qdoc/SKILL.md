---
name: skill-qdoc
description: This skill should be used when discussing QDoc internals, node systems, link resolution, warning diagnosis, index files, qdocconf configuration, macros, Qt Help files, or documentation generation architecture. Provides comprehensive reference for QDoc's documentation generation system.
version: 1.0.0
---

# QDoc Architecture Reference

Comprehensive guide to QDoc's internal architecture for technical writers and documentation developers.

## When to Use This Skill

This skill activates when working with:
- QDoc internals or architecture questions
- Node creation and link resolution issues
- Link failure diagnosis or warning interpretation
- Index file format or cross-module linking
- Context commands (`\since`, `\deprecated`, `\internal`, `\inmodule`, etc.)
- Markup commands (`\a`, `\c`, `\e`, `\b`, `\l`, etc.)
- qdocconf configuration (depends, macros, qhp)
- Qt Help file generation (.qhp, .qch, .qhc)
- Documentation build troubleshooting
- Locating source files from published URLs (doc.qt.io → .qdoc/.cpp)

## Core Concepts

### Node System

QDoc builds an in-memory tree of nodes representing documentable entities. Topic commands (`\class`, `\fn`, `\page`, etc.) create nodes. Names must be fully qualified.

**Key node types:**
- **C++**: Namespace, Class, Function, Property, Enum, Typedef
- **QML**: QmlType, QmlProperty, QmlMethod, QmlSignal
- **Documentation**: Page, Example, Group, Module

To investigate node-related issues, read `references/node-system.md`.

### Link Resolution

The `\l` command resolves targets by:
1. Parsing the target string
2. Searching trees (primary first, then index trees)
3. Generating HTML link with anchor

**Common link syntax:**
```cpp
\l{ClassName}                 // Link to class
\l{ClassName::member}         // Link to member
\l{ClassName#Section Title}   // Link to section within class
\l{QmlType#Section Title}     // Link to section within QML type
\l{target}{display text}      // Custom display text
\l [QML]{TypeName}            // Force QML genus
\l{Page Title}                // Link to page by title
\l{External Page Title}       // Link to external page
```

**Section links:** Use `TypeName#Section Title` (NOT `page.html#anchor`) to link to sections within C++ class or QML type documentation.

**External pages:** Use `\externalpage` to create named targets for external URLs. Link targets must match the `\title` exactly (including macro expansion).

To diagnose link resolution issues, read `references/link-resolution.md`.

### Index Files

Index files (`.index`) are XML files enabling cross-module linking. The `depends` variable in qdocconf specifies which modules to load.

```qdocconf
depends = QtCore QtGui QtWidgets
```

**Accessing index files:**
- **Local build:** `{outputdir}/{module}.index` (after `ninja docs`)
- **Online:** `https://doc-snapshots.qt.io/qt6-dev/{module}.index`

Index files are published on **doc-snapshots.qt.io** (not doc.qt.io), so a local build is not required to verify link targets.

For index file format and cross-module dependency details, read `references/index-files.md`.

### Qt Help System

QDoc generates `.qhp` files that `qhelpgenerator` compiles into `.qch` files for Qt Assistant.

For Qt Help configuration, read `references/qt-help.md`.

### Semantic Markup

**Markup encodes meaning, not just formatting.** Each command tells readers what KIND of information they're seeing:

| Command | Tells readers |
|---------|---------------|
| `\a` | "This is a parameter you pass to this function" |
| `\c` | "This is code—a literal value or keyword" |
| `\e` | "This concept is emphasized/important" |
| `\b` | "This is a strong callout (Note:, Warning:)" |
| `\tt` | "This is code that contains links or other commands" |
| `\uicontrol` | "This is a UI element to click/interact with" |
| `\l` | "Click here to learn more" |

**Why it matters:**
- **Reader comprehension** — Readers instantly know what type of information each word is
- **Scannability** — Technical readers scan for parameters, code values, UI elements
- **Copy-paste accuracy** — Code marked with `\c` is unambiguous for copying
- **Translation safety** — Translators know `\c{nullptr}` should not be translated
- **Accessibility** — Screen readers can convey semantic meaning

For detailed inline markup reference, read `references/markup-commands.md`.

### Admonitions

Block-level commands that interrupt reading flow intentionally:

| Command | Use for |
|---------|---------|
| `\note` | Supplementary information worth highlighting |
| `\warning` | Serious consequences if ignored (crashes, data loss) |
| `\important` | Critical information (rarely used) |

**Key constraints:**
- Short statements only—not for multiline paragraphs
- Use sparingly—overuse trains readers to skip them
- Never cluster—don't place two admonitions adjacent

For usage guidance, anti-patterns, and industry rationale, read `references/admonitions.md`.

### Structured Content

Block-level commands for organizing information:

| Command | Use for |
|---------|---------|
| `\list` / `\li` | Bulleted or numbered lists (2-7 items ideal) |
| `\table` / `\row` / `\header` | Data with 2+ attributes per item |
| `\snippet` | Code examples (preferred over `\code`) |
| `\code` | Inline code blocks (less preferred) |
| `\qml` | QML code specifically |

**Key rules:**
- Lists need 2-7 items with parallel structure
- Tables need headers and introductions; no blank cells
- Always introduce lists, tables, and code with context
- Prefer `\snippet` over `\code` for tested, maintainable examples

For complete formatting rules, anti-patterns, and decision framework, read `references/structured-content.md`.

## Diagnosing Common Issues

### Link Warnings ("Can't link to 'X'")

**Follow the diagnostic checklist in order** (see `references/link-resolution.md`):

1. Search for `\target` definitions in source
2. Search for page `\title` matches
3. Search for `\externalpage` definitions
4. Search for macros in `macros.qdocconf`
5. Search index files for the target:
   - Local: `grep 'name="Target"' */doc/*/*.index`
   - Online: WebFetch `https://doc-snapshots.qt.io/qt6-dev/{module}.index`
6. For private APIs, use `\c{}` instead of `\l{}`
7. Verify HTML page exists on [doc.qt.io](https://doc.qt.io/qt-6/)

| Warning | Likely Cause |
|---------|--------------|
| Can't link to 'X' | Target undocumented or `\internal` |
| Can't link to 'Page Title' | Title mismatch (check macro expansion) |
| Can't link to 'External Thing' | No `\externalpage` with matching `\title` |
| Duplicate target | Multiple `\target` with same name |

### Node Warnings

| Warning | Likely Cause |
|---------|--------------|
| Cannot tie documentation to anything | Missing topic command |
| Has no \inmodule command | Class not assigned to module |
| Failed to find function | Signature mismatch in `\fn` |

For complete warning reference, read `references/macros-warnings.md`.

## Key Source Files

| File | Purpose |
|------|---------|
| `node.h/cpp` | Base Node class |
| `aggregate.h/cpp` | Parent nodes |
| `tree.h/cpp` | Tree structure, target resolution |
| `qdocdatabase.h/cpp` | Forest management |
| `qdocindexfiles.h/cpp` | Index file I/O |

## Reference Materials

| File | Content |
|------|---------|
| `references/node-system.md` | Node hierarchy, topic commands, tree/forest architecture |
| `references/link-resolution.md` | Link syntax, target system, resolution pipeline, autolinks |
| `references/markup-commands.md` | Inline markup (`\a`, `\c`, `\e`, `\b`, `\uicontrol`), best practices |
| `references/admonitions.md` | Block-level admonitions (`\note`, `\warning`), anti-patterns, usage guidance |
| `references/structured-content.md` | Lists, tables, code blocks—formatting rules, anti-patterns, decision framework |
| `references/context-commands.md` | Context commands (`\since`, `\deprecated`, `\internal`, `\inmodule`, etc.) |
| `references/index-files.md` | Index XML format, cross-module dependencies |
| `references/source-file-location.md` | Mapping published URLs to source files (.qdoc, .cpp) |
| `references/qt-help.md` | Qt Help files, HTML output configuration |
| `references/macros-warnings.md` | Macro system, common warnings reference |
| `references/qdocconf-reference.md` | Complete qdocconf example, command quick reference |

## External References

- [QDoc Manual](https://doc.qt.io/qt-6/qdoc-index.html)
- [QDoc Commands](https://doc.qt.io/qt-6/27-qdoc-commands-alphabetical.html)
- [Qt Writing Guidelines](https://wiki.qt.io/Qt_Writing_Guidelines)
- [Qt Help Framework](https://doc.qt.io/qt-6/qthelp-framework.html)
