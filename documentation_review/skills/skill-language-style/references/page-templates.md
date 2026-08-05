<!-- Loaded on demand by skill-language-style/SKILL.md router. Part of skill-language-style. -->

## Page Templates

These rules define required structure for different documentation page types. Based on patterns from Qt Concurrent, Qt Widgets, Qt Quick Controls, and other Qt modules.

**Reference template**: `qtbase/doc/global/app-examples-template/app-examples-template.qdoc` (examples only)

---

### R58. Module Landing Page Structure

**Rule**: Module landing pages (`{module}-index.qdoc`) must include navigation sections linking to examples and API reference.

**Required sections** (in typical order):

| Section | Required | Content |
|---------|----------|---------|
| `\page {module}-index.html` | ✓ | Page identifier |
| `\title {Module Name}` | ✓ | Human-readable title |
| `\brief` | ✓ | Must end with period |
| Introduction | ✓ | Module description paragraphs |
| `\section1 Using the Module` | ✓ | With `\include module-use.qdocinc` |
| Module-specific content | varies | API overview, concepts, features |
| `\section1 Articles and Guides` | optional | If tutorials/guides exist |
| **`\section1 Examples`** | ✓ | `\l{{Module} Examples}` |
| **`\section1 Reference`** | ✓ | `\l{{Module} C++ Classes}` and/or `\l{{Module} QML Types}` |
| `\section1 Related Modules` | optional | Links to dependencies |
| `\section1 Module Evolution` | optional | `\l{Changes to {Module}}` |
| `\section1 Licenses` | ✓ | Standard license text |

**Examples section** (MANDATORY):
```qdoc
\section1 Examples

\list
    \li \l{Qt TaskTree Examples}
\endlist
```

**Reference section** (MANDATORY):
```qdoc
\section1 Reference

\list
    \li \l{Qt TaskTree C++ Classes}
\endlist
```

For modules with both C++ and QML APIs:
```qdoc
\section1 Reference

\list
    \li \l{Qt Quick Controls QML Types}{QML Types}
    \li \l{Qt Quick Controls C++ Classes}{C++ Classes}
\endlist
```

**Linking API elements in prose**: When mentioning classes or enum values in the module description, use `\l` to link them:
```qdoc
\list
\li \l QProcessTask - Executes external processes.
\li \l{WorkflowPolicy::StopOnError} - Stops execution on first error.
\endlist
```

**Sources**: Qt Concurrent, Qt Widgets, Qt Quick Controls module pages (de facto standard)

---

### R59. Example Group Requirements

**Rule**: Example group pages (`\group {module}_examples`) must be configured for global visibility.

**Required commands**:

```qdoc
/*!
    \group tasktree_examples
    \title Qt TaskTree Examples
    \ingroup all-examples

    \brief Examples demonstrating the Qt TaskTree module.
*/
```

| Command | Required | Purpose |
|---------|----------|---------|
| `\group {name}` | ✓ | Defines the group |
| `\title {Module} Examples` | ✓ | Human-readable title |
| `\ingroup all-examples` | ✓ | Appears in global "All Qt Examples" page |
| `\brief` | ✓ | Must end with period |

**Without `\ingroup all-examples`**: The module's examples won't appear in the global examples listing at doc.qt.io/qt-6/qtexamplesandtutorials.html.

**Individual examples** must include:
```qdoc
\ingroup {module}_examples
```

This links them to the module's example group page.

**Sources**: Qt example groups (qt3d_examples, qtquick_examples, etc.)

---

### R60. Cross-Module Linking

**Rule**: When linking to types from other Qt modules, explicit `\l` is required
in certain contexts. QDoc autolinking depends on context and pattern matching.

**Technical reference**: See `skill-qdoc/references/link-resolution.md` for the
complete autolink pattern matching rules and context-aware resolution behavior.

**When autolink works:**
| Pattern | Autolinks? | Example |
|---------|------------|---------|
| Simple class name from indexed module | ✓ | `QProcess` → links to Qt Core |
| Class name in prose context | ✓ | "Use QTimer for delays" |
| Functions in same-class context | ✓ | `changeEvent()` inside QWidget docs |
| Qualified functions | ✓ | `QTimer::singleShot()` (CamelCase + `::`) |

**When explicit `\l` required:**
| Pattern | Why | Fix |
|---------|-----|-----|
| Bare function outside class context | No class to search | `\l{QWidget::changeEvent()}` |
| Template with `<Type>` | `<` terminates parsing | `\l{QFutureWatcher}<Result>` |
| Same-module types in lists | Context interference | `\l{QtTaskTree::}{QThreadFunction}` |
| Types after operators (`+`, `=`) | Context interference | `\l QNetworkReply = \l{Module::}{Type}` |

**Note**: Parentheses `()` do NOT break autolinking. Functions like `singleShot()`
autolink when qualified (`QTimer::singleShot()`) because QDoc's `isAutoLinkString()`
explicitly handles `()` as a valid autolink pattern component.

**Namespace format for same-module types:**
```qdoc
\l{Namespace::}{TypeName}
```

Example:
```qdoc
\li \l QNetworkAccessManager + \l QNetworkReply = \l{QtTaskTree::}{QNetworkReplyWrapper}
\li \l{QtConcurrent::run()} + \l{QFutureWatcher}<Result>
    = \l{QtTaskTree::}{QThreadFunction}<Result>
```

**Verification**: After doc build, check ERR file for "Can't link to" warnings.

**Reviewer pre-verification (BLOCKING):**

Before suggesting link changes, follow the **Reviewer Verification Checklist** in
`skill-qdoc/references/link-resolution.md`. Key: fetch index, check autolink status,
include evidence in Validation field.

**Sources**: QDoc link resolution behavior; Qt TaskTree, Qt Concurrent patterns

---

### R61. qdocconf Module Configuration

**Rule**: Module qdocconf files must properly configure dependencies and subprojects for cross-module linking.

**Required elements:**

```qdocconf
# Dependencies for cross-module links
depends += qtcore \
           qtnetwork \
           qtconcurrent \
           ...

# Subprojects for navigation
qhp.ModuleName.subprojects = examples classes

qhp.ModuleName.subprojects.classes.title = C++ Classes
qhp.ModuleName.subprojects.classes.indexTitle = Module Name C++ Classes
qhp.ModuleName.subprojects.classes.selectors = class fake:headerfile

qhp.ModuleName.subprojects.examples.title = Examples
qhp.ModuleName.subprojects.examples.indexTitle = Module Name Examples
qhp.ModuleName.subprojects.examples.selectors = example

# Navigation
navigation.landingpage = "Module Name"
navigation.cppclassespage = "Module Name C++ Classes"

# Warning limit (0 = fail on any warning)
warninglimit = 0
```

**Verification checklist:**
- [ ] `depends` includes all modules referenced in documentation
- [ ] `subprojects` includes `classes` if module has public C++ API
- [ ] `subprojects` includes `examples` if module has examples
- [ ] `navigation.landingpage` matches `\title` in index.qdoc
- [ ] `warninglimit = 0` for strict builds (recommended)

**Common dependency mappings:**
| If you link to... | Add to depends |
|-------------------|----------------|
| `QProcess`, `QTimer`, `QObject` | `qtcore` |
| `QNetworkAccessManager`, `QNetworkReply` | `qtnetwork` |
| `QtConcurrent::run()`, `QFuture` | `qtconcurrent` |
| `QRestAccessManager` | `qtnetwork` |
| CMake commands | `qtcmake` |

**Sources**: Qt module qdocconf files (qtcore, qtconcurrent, qttasktree)

---

### R62. Module Review Checklist

**Rule**: When reviewing a complete module's documentation, verify all structural elements.

**Landing page (`{module}-index.qdoc`):**
- [ ] `\page {module}-index.html` present
- [ ] `\title` matches navigation.landingpage in qdocconf
- [ ] `\brief` ends with period
- [ ] `\section1 Using the Module` with CMake/qmake instructions
- [ ] `\section1 Examples` with `\l{Module Examples}` (R58)
- [ ] `\section1 Reference` with `\l{Module C++ Classes}` (R58)
- [ ] `\section1 Licenses` present
- [ ] Class/enum names linked with `\l` where mentioned

**Examples group (`\group {module}_examples`):**
- [ ] `\ingroup all-examples` present (R59)
- [ ] `\title` format: "{Module} Examples"
- [ ] `\brief` ends with period

**Individual examples:**
- [ ] `\ingroup {module}_examples`
- [ ] `\example` with correct path
- [ ] `\examplecategory`
- [ ] `\title`
- [ ] `\brief` ends with period
- [ ] `\image` with alt text in `{curly braces}`
- [ ] `\include examples-run.qdocinc`
- [ ] `\sa` at end referencing related examples/pages

**API documentation (`\class`, `\typedef`, `\enum`):**
- [ ] `\inmodule {ModuleName}`
- [ ] `\brief` ends with period
- [ ] `\sa` for related types
- [ ] Cross-module links use explicit `\l` (R60)

**Build verification:**
- [ ] Documentation build completes without errors
- [ ] No "Can't link to" warnings in build output
- [ ] `warninglimit` in qdocconf is satisfied

**Common QDoc warning patterns:**

| Warning | Cause | Fix |
|---------|-------|-----|
| `Can't link to 'TypeName'` | Missing `\l` target or wrong namespace | Use `\l{Namespace::}{TypeName}` or add to `depends` |
| `Can't link to 'function()'` | Functions need explicit link | Use `\l{Class::function()}` |
| `Unknown base 'X' for QML type` | Missing QML module dependency | Add module to `depends` |
| `Failed to find function` | Signature mismatch | Check `\fn` matches actual signature |
| `No such parameter` | Parameter name wrong in docs | Update `\a paramName` to match code |

**Sources**: Qt module documentation patterns

---


