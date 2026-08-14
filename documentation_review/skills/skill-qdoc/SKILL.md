---
name: skill-qdoc
description: This skill should be used when discussing QDoc internals, node systems, link resolution, warning diagnosis, index files, qdocconf configuration, macros, Qt Help files, or documentation generation architecture. Provides comprehensive reference for QDoc's documentation generation system.
metadata:
  version: "1.1.0"
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

The `\l` and `\sa` commands resolve targets using the same mechanism:
1. Parsing the target string
2. Searching trees (primary first, then index trees) via `findNodeForAtom()`
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

\sa Target1, Target2          // See also (comma-separated)
\sa {Class::}{member()}       // C++ member shorthand
```

**`\sa` vs `\l`:** Both use `findNodeForAtom()` for resolution. `\sa` renders in a
"See also" section and takes comma-separated targets. See `references/link-resolution.md`
for detailed `\sa` syntax and behavior.

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
| `references/page-structure.md` | `\page`, `\example`, `\externalpage`, navigation commands |
| `references/examples-and-snippets.md` | `\include`, qdocinc fragments, `\snippet`, argument substitution |
| `references/module-declaration.md` | `\module`, `\qmlmodule`, mandatory companions, title patterns |
| `references/group-and-organization.md` | `\group`, `\ingroup`, hierarchical nesting, `\generatelist` |
| `references/namespaces-headers-macros.md` | `\namespace`, `\headerfile`, `\macro`, `\relates` |
| `references/qml-topic-commands.md` | `\qmltype`, `\qmlproperty`, `\qmlmethod`, `\qmlsignal`, `\qmlvaluetype`, `\qmlattachedproperty`, `\qmlattachedsignal` |
| `references/cmake-reference.md` | CMake reference pages: `\cmakecommandsince`, command/variable/property page conventions, `\summary` |
| `references/stub-patterns.md` | Stub-assembly cross-reference index — what topic command + companions + brief rule + filename per doc type |
| `references/advanced-qdocconf.md` | Macro system, QHP config, global include chain, path variables |

## External References

- [QDoc Manual](https://doc.qt.io/qt-6/qdoc-index.html)
- [QDoc Commands](https://doc.qt.io/qt-6/27-qdoc-commands-alphabetical.html)
- [Qt Writing Guidelines](https://wiki.qt.io/Qt_Writing_Guidelines)
- [Qt Help Framework](https://doc.qt.io/qt-6/qthelp-framework.html)

---

## Linking Issue Check

**Question: "Will this change cause linking issues?"**

When reviewing patches that modify titles, sections, or targets, verify no existing links will break.

### What Generates Link Targets

| Source | Generated Anchor |
|--------|------------------|
| `\title {Page Title}` | Page becomes linkable as `\l{Page Title}` |
| `\section1 Section Name` | `#section-name` (lowercase, hyphens) |
| `\section2 Subsection` | `#subsection` |
| `\target custom-anchor` | `#custom-anchor` |
| `\keyword Search Term` | Linkable via `\l{Search Term}` |

### Anchor Generation Rules

QDoc converts section titles to anchors:
1. Lowercase all characters
2. Replace spaces with hyphens
3. Remove special characters

Examples:
- "Hosting in Qt GUI" → `#hosting-in-qt-gui`
- "C++ Integration" → `#c-integration`
- "QML/Qt Quick" → `#qml-qt-quick`

### Check Process

**Step 1: Identify what changed**
- Section title changed? (`\section1`, `\section2`, etc.)
- Page title changed? (`\title`)
- Target removed? (`\target`)
- File renamed? (changes HTML filename)

**Step 2: Search for existing references**

```bash
# 1. Search for \l{} links to the title
grep -r "\\\\l.*{.*Old Title" qt*/

# 2. Search for \sa references
grep -r "\\\\sa.*Old Title" qt*/

# 3. Search for HTML anchor references
grep -r "#old-anchor-name" qt*/

# 4. Search local index files
grep "Old Title\|old-anchor" */doc/*/*.index

# 5. Search online index files
WebFetch: https://doc-snapshots.qt.io/qt6-dev/{module}.index
```

**Step 3: Check cross-module dependencies**

Qt modules link to each other. A title change in qtbase may break links in:
- qtdoc (overview documentation)
- qtdeclarative (QML docs linking to C++ classes)
- Other dependent modules

**Online index files:**
- `https://doc-snapshots.qt.io/qt6-dev/qtcore.index`
- `https://doc-snapshots.qt.io/qt6-dev/qtgui.index`
- `https://doc-snapshots.qt.io/qt6-dev/qtwidgets.index`
- `https://doc-snapshots.qt.io/qt6-dev/qtqml.index`
- `https://doc-snapshots.qt.io/qt6-dev/qtquick.index`
- `https://doc-snapshots.qt.io/qt6-dev/qtdoc.index`

### Special Cases

**New content:** If the patch adds a NEW section/page (not modifying existing), there cannot be existing links. Note: "New file/section - no existing links possible."

**Case sensitivity:** Anchors are case-insensitive in browsers, but `\l{Title}` text must match the actual `\title` or `\section` text exactly (case-sensitive).

**Renamed files:** If a `.qdoc` file with `\page foo.html` is renamed or the page command changed, all `\l{foo.html}` links break.

### Report Template

```markdown
## Linking Issue Check

**Changed:** [describe what title/target changed]

**Searches performed:**
- [ ] `\l{}` patterns in source
- [ ] `\sa` references in source
- [ ] HTML anchor patterns
- [ ] Local index files
- [ ] Online index files (doc-snapshots.qt.io)

**Result:** [No issues / Issues found - list locations]
```
