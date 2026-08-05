<!-- Loaded on demand by skill-language-style/SKILL.md router. Part of skill-language-style. -->

## QDoc Command Formatting

**Note:** This section covers formatting rules for QDoc commands. For the semantic purpose of markup commands (`\a`, `\c`, `\e`, `\uicontrol`)—why we use them and what they communicate to readers—see **skill-qdoc** (`references/markup-commands.md`).

### R39. Prefer No Space Between Command and Curly Brace

**Rule**: Prefer no space between QDoc commands and opening curly braces for compactness.

**Both forms are valid** - the QDoc parser skips whitespace before parsing arguments (`docparser.cpp:2377` calls `skipSpacesOrOneEndl()`), so both forms parse identically:

```
\l{QWidget}              // Preferred: compact
\l {QWidget}             // Valid: matches QDoc Manual examples
```

**Why prefer no space**: Compactness helps meet the 80-column limit (R40):
```qdoc
// No-space: saves characters for long lines
See \l{Getting Started}, \l{Qt Modules}, and \l{Qt Examples}.

// Space: 3 extra characters
See \l {Getting Started}, \l {Qt Modules}, and \l {Qt Examples}.
```

**Applies to all QDoc commands** with curly braces:
- Link commands: `\l`, `\sa`
- Text markup: `\c`, `\b`, `\e`, `\i`, `\sub`, `\sup`
- All other commands using `{}`

**Enforcement**: STYLE PREFERENCE, not enforced. Be consistent within a file.

**Usage in Qt codebase** (qtbase, qtdeclarative, qtdoc):
- No space (`\l{target}`): 71% (7,299 instances)
- Space (`\l {target}`): 29% (2,922 instances)

**Note**: The official QDoc Manual examples show spaces (`\l {target}`). The no-space preference is a Qt Doc Team convention for compactness, not a parser requirement.

**Sources**: QDoc parser source (`qttools/src/qdoc/qdoc/src/qdoc/docparser.cpp`)

---

### R40. 80-Column Line Length for Documentation

**Rule**: Keep documentation lines at or below 80 columns.

**Enforcement**: CI-ENFORCED. This rule is checked automatically by CI.

**Scope**: Applies to ALL lines including:
- Prose paragraphs
- List items (`\li`)
- **Table rows (`\row`)** - commonly overlooked
- Alt text lines
- Code examples in documentation

**Context**:
- Documentation comments in .cpp files follow the surrounding code's column width
- Qt code uses 80-column limit
- Applies to QDoc comments and .qdoc files

**Table rows** are a frequent violation source because multiple cells concatenate:
```qdoc
❌ 102 chars:
    \row \li NVIDIA \li Jetson AGX Orin 64GB Developer Kit \li Yocto 5.2 \li \l{Boot to Qt} \li Qt Group

✓  Split across lines:
    \row \li NVIDIA \li Jetson AGX Orin 64GB Developer Kit \li Yocto 5.2
        \li \l{Boot to Qt} \li Qt Group
```

**Exception**: Single-line content within `{}` should stay on one line when possible for easier searching and error detection.

**Sources**: Qt Coding Style (https://wiki.qt.io/Qt_Coding_Style), QDoc Style Guidelines Wiki

---

### R41. \sa Targets Must Resolve

**Rule**: Each `\sa` (see also) target must resolve to a valid documentation target.
`\sa` uses the **same resolution mechanism as `\l`** (`findNodeForAtom()`), so all
link resolution rules apply.

**Technical Detail**: `\sa` produces the same "Can't link to 'X'" warning as `\l`
when resolution fails. It also warns "Redundant link to self" when linking to the
containing node.

**Validation Method**:
1. Search index files for the target: `grep 'name="Target"' */doc/*/*.index`
2. For page titles: `grep 'title="Target"' */doc/*/*.index`
3. Verify the target exists and is public (`access="public"`)

**Common Mistakes**:
```
❌ \sa {Qt Quick 3D Examples}           (page title is different)
✅ \sa {Qt Quick 3D Examples and Tutorials}

❌ \sa {Qt Examples}                    (page doesn't exist)
✅ \sa {All Qt Examples}

❌ \sa show()                           (ambiguous without class)
✅ \sa QWidget::show()
```

**Syntax**: `\sa` takes comma-separated targets. Missing commas produce warnings.
```
✅ \sa QWidget::show(), QDialog::exec()
❌ \sa QWidget::show() QDialog::exec()   // Missing comma
```

**Cross-reference**: See skill-qdoc/references/link-resolution.md for complete `\sa`
syntax, parsing details, and resolution flow.

**Sources**: QDoc source (`docparser.cpp:parseAlso()`, `generator.cpp:generateAlsoList()`)

---


## Admonition and Markup Rules

### R63. Admonition Appropriateness

**Rule**: Use the correct admonition type for the content severity. Avoid weak warnings and hedging language.

| Admonition | Use When | Do NOT Use For |
|------------|----------|----------------|
| `\note` | Supplementary information worth highlighting | Essential API behavior |
| `\warning` | Serious consequences if ignored (crashes, data loss) | Minor caveats, default values |
| `\important` | Critical information (rarely used) | Regular emphasis |

**Anti-patterns:**

1. **Weak warnings**: Using `\warning` without serious consequences
   ```qdoc
   ❌ \warning Use this property with caution.
   ✓  \note Qt automatically disables this property when...
   ```

2. **Hedging language**: Vague phrases in warnings
   - "use with caution", "be careful", "take care"
   - If you can't specify the danger, it's not a warning

3. **Automatic behavior as warning**: If Qt handles it automatically, use `\note`
   ```qdoc
   ❌ \warning This property is automatically disabled when using style sheets.
   ✓  \note When a widget has a style sheet, Qt automatically disables this property.
   ```

**Full reference**: skill-qdoc/references/admonitions.md

**Sources**: Qt Documentation Team practice, industry standards (ANSI Z535.6)

---

### R64. Markup Consistency

**Rule**: All code elements in prose must have appropriate markup (`\c`, `\l`), applied consistently throughout the document.

**Elements requiring markup:**

| Element Type | Markup | Example |
|--------------|--------|---------|
| Boolean values | `\c` | `\c true`, `\c false`, `\c nullptr` |
| Enum values | `\c` or `\l` | `\c{Qt::AlignLeft}`, `\c{QPalette::Window}` |
| Widget attributes | `\c` or `\l` | `\c{Qt::WA_OpaquePaintEvent}` |
| CSS properties | `\c` | `\c{border-image}` |
| CMake elements | `\c` | `\c Qt6`, `\c find_package()` |
| File extensions | `\c` | `\c{.yaml}` |

**Consistency rule**: If an element appears multiple times, all instances must have the same markup.

```qdoc
❌ Inconsistent:
   QPalette::Window is used. The color is defined by \c{QPalette::Window}.

✓ Consistent:
   \c{QPalette::Window} is used. The color is defined by \c{QPalette::Window}.
```

**Full reference**: skill-qdoc/references/markup-commands.md

**Sources**: Qt Documentation Team practice

---


