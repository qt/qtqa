# Examples, Snippets, and Includes Reference

**Verified against:** QDoc manual (doc.qt.io/qt-6), 505 `\include`
usages, and 143 qdocinc files in qt5 super-repo.

## `\include` — Include Reusable Content

Inserts content from another file into the current doc comment.
The primary mechanism for sharing boilerplate text across pages.

### Three syntax forms

**Form 1 — Whole file:**
```qdoc
\include examples-run.qdocinc
```
Inserts the entire file. Used when the qdocinc has no fragment
tags.

**Form 2 — Fragment (space-separated):**
```qdoc
\include qtprotoccommon.qdocinc copy_comments-li
```
Inserts only the content between matching `//! [tag]` delimiters.
Works when the fragment name has no spaces.

**Form 3 — Fragment with arguments (braces):**
```qdoc
\include {module-use.qdocinc} {building with cmake} {Protobuf}
```
Braces required when:
1. Fragment name contains spaces
2. Arguments are passed (substituted as `\1`, `\2`, etc.)

### Fragment delimiter syntax

In the qdocinc file, fragments are marked with:
```
//! [fragment-name]
Content to include...
//! [fragment-name]
```

Same tag opens and closes the fragment.

### Argument substitution

The included content can contain `\1`, `\2` placeholders:

**In module-use.qdocinc:**
```
//! [building with cmake]
    Use the \c{find_package()} command to locate the needed
    module component in the \c{Qt6} package:

    \code
    find_package(Qt6 REQUIRED COMPONENTS \1)
    target_link_libraries(mytarget PRIVATE Qt6::\1)
    \endcode
//! [building with cmake]
```

**Called as:**
```qdoc
\include {module-use.qdocinc} {building with cmake} {Protobuf}
```

Result: `\1` is replaced with `Protobuf`.

Multiple arguments: `\include {file} {tag} {arg1} {arg2}`
replaces `\1` with arg1 and `\2` with arg2.

### File extensions included

| Extension | Usage | Notes |
|-----------|-------|-------|
| `.qdocinc` | Most common | Recommended; not parsed as primary source |
| `.qdoc` | Less common | Works but file is also parsed as source |
| `.cpp` | Occasional | For sharing doc snippets between classes |

**Recommendation:** Use `.qdocinc` for dedicated include files.

### Common reusable fragments

| File | Fragment | Used by |
|------|----------|---------|
| `module-use.qdocinc` | `{using the c++ api}` | Every module overview |
| `module-use.qdocinc` | `{building with cmake}` | Every module overview |
| `examples-run.qdocinc` | (whole file) | Every example page |
| `deprecation-phase.qdocinc` | (whole file) | Deprecated modules |

### Discrepancy: official vs codebase

The `\include` brace syntax with argument substitution is the
**most used include pattern** in the codebase (every module's
"Using the Module" section) but is not prominently documented
in the official QDoc manual. The `\1` placeholder system is a
major feature that the manual mentions only briefly.

---

## qdocinc File Format

### Location

- Module-specific: `src/*/doc/src/*.qdocinc` or `src/*/doc/*.qdocinc`
- Global: `qtbase/doc/global/includes/` (shared across all modules)

### Structure

**With fragments (most common):**
```
// Copyright notice
// SPDX license

//! [fragment-one]
Content for fragment one.
//! [fragment-one]

//! [fragment-two]
Content for fragment two with \1 parameter.
//! [fragment-two]
```

**Without fragments (whole-file include):**
```
// Copyright notice
// SPDX license

\section1 Running the Example

To run the example from \l{\QC Documentation}{Qt Creator},
open the \uicontrol Welcome mode and select the example
from \uicontrol Examples.
```

### Fragment naming

No universal convention. Observed patterns:
- kebab-case: `copy_comments-li`
- Spaces: `using the c++ api`
- Underscores: `building_with_qmake`

When a name contains spaces, callers must use braces:
`\include {file} {name with spaces}`. Some fragments have
both underscore and space variants to avoid brace requirement.

---

## `\snippet` — Code from Source Files

The dominant code inclusion method in Qt docs (8,916 usages).
Includes a tagged code fragment from a source file. Preferred
over `\code` because snippets are compiled and tested.

### Syntax

```qdoc
\snippet path/to/file.cpp tag-name
\snippet [language] path/to/file.cpp tag-name
```

The optional `[language]` parameter (Qt 6.11+) controls syntax
highlighting. Not yet used in production docs.

### Fragment delimiters

Delimiters vary by file type:

| File type | Delimiter |
|-----------|-----------|
| C++, QML, JavaScript | `//! [tag-name]` |
| .pro, .py, .cmake, CMakeLists.txt | `#! [tag-name]` |
| .html, .qrc, .ui, .xml | `<!-- [tag-name] -->` |

**Example in C++:**
```cpp
//! [constructor]
MyClass::MyClass(QObject *parent)
    : QObject(parent)
{
}
//! [constructor]
```

**Example in CMakeLists.txt:**
```cmake
#! [cmake-setup]
find_package(Qt6 REQUIRED COMPONENTS Core)
target_link_libraries(mytarget PRIVATE Qt6::Core)
#! [cmake-setup]
```

### Fragment tag naming

Tags can contain letters, numbers, spaces, hyphens, and dots.
Two conventions coexist:

- **Numeric** (most common in `code/` subdirs):
  `//! [0]`, `//! [1]`, `//! [10]`
- **Descriptive** (preferred for examples):
  `//! [Adding a resource]`, `//! [constructor]`

### Path resolution

QDoc resolves snippet paths via `exampledirs` in qdocconf:
```qdocconf
exampledirs += snippets \
               ../../../examples/corelib
```

**Critical:** Snippet directories are listed in `exampledirs`
(so `\snippet` can find them) AND in `excludedirs` (so QDoc
does not parse them as API documentation):
```qdocconf
exampledirs += snippets
excludedirs += snippets
```

This is a common qdocconf pattern — not a contradiction.

### Snippet testing

Snippet files are compiled as part of the build to ensure
they remain valid:

```cmake
add_library(corelib_snippets OBJECT
    customtype/customtypeexample.cpp
    file/file.cpp
    ...
)
target_link_libraries(corelib_snippets PRIVATE Qt::Core)
set_target_properties(corelib_snippets PROPERTIES
    COMPILE_OPTIONS "-w"
    UNITY_BUILD OFF
)
```

Key details:
- Built as `OBJECT` libraries (compile-checked, not linked)
- `-w` suppresses warnings (snippets are not warning-clean)
- `UNITY_BUILD OFF` because snippets have conflicting symbols
- Feature guards: `if(QT_FEATURE_widgets)` for conditional
  snippets

### Decision guide: `\snippet` vs others

| Command | Source | Compiled? | Use for |
|---------|--------|-----------|---------|
| `\snippet` | External file, tagged | Yes | Tested code examples (8,916 uses) |
| `\quotefromfile` | External file, walkthrough | Yes | Step-by-step code tours (532 uses) |
| `\quotefile` | External file, whole | Yes | Small complete files (71 uses) |
| `\code` | Inline | No | Quick untested examples |
| `\qml` | Inline | No | QML-specific examples |
| `\badcode` | Inline | No | Wrong or partial code |

**Preference:** `\snippet` > `\quotefromfile` > `\quotefile`
> `\code`

---

## `\quotefromfile` — Code Walkthrough

Opens a file for selective quoting with a position pointer.
Used for step-by-step code tours (532 usages).

### Syntax

```qdoc
\quotefromfile path/to/file.cpp
```

### Walkthrough commands

QDoc maintains a current position pointer in the opened file.
These commands move and print relative to that pointer:

| Command | Count | Purpose |
|---------|-------|---------|
| `\skipto pattern` | 793 | Advance to **before** line with pattern (not consumed) |
| `\printuntil pattern` | 978 | Print up to and **including** line with pattern |
| `\printto pattern` | 107 | Print up to but **excluding** line with pattern |
| `\printline pattern` | 103 | Print single line containing pattern |
| `\skipuntil pattern` | 57 | Advance **past** line with pattern (consumed) |
| `\skipline pattern` | 11 | Skip next non-blank line matching pattern |
| `\dots [indent]` | 488 | Insert `...` to indicate omitted code |
| `\codeline` | 194 | Insert blank line within code block |

**`\printuntil` without argument** prints to end of file.

**`\skipto` vs `\skipuntil`:** `\skipto` positions before the
match (so `\printuntil` will include it). `\skipuntil` positions
after the match (skipping past it).

### Common pattern

The typical walkthrough chain:

```qdoc
\quotefromfile demos/thermostat/content/App.qml
\skipto Component.onCompleted
\printuntil })
\dots
\skipto function updateWeather
\printuntil }
```

### `\dots` indentation

Default indent is 4 spaces. Custom indent:
```qdoc
\dots 0     // No indent
\dots 8     // 8-space indent
```

---

## `\quotefile` — Whole File Inclusion

Includes an entire file (71 usages). No fragment tags needed.

### Syntax

```qdoc
\quotefile path/to/file
```

### Common use cases

Small, complete files:
```qdoc
\quotefile tutorials/extending-qml/chapter1/qmldir
\quotefile scenegraph/customgeometry/CMakeLists.txt
\quotefile filesystemexplorer/qml/MyMenu.qml
```

---

## Version History

- **v1.1** (2026-03-26): Expanded snippet coverage with path
  resolution, testing patterns, fragment tag conventions, all
  walkthrough commands with usage counts, `\quotefile`,
  `\codeline`. Verified against 8,916 snippet usages.
- **v1.0** (2026-03-26): Initial version from audit of 505
  `\include` usages and 143 qdocinc files
