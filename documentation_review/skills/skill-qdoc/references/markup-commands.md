# QDoc Markup Commands Reference

**Source:** `qttools/src/qdoc/qdoc/doc/qdoc-manual-markupcmds.qdoc`
**Source:** `qttools/src/qdoc/qdoc/src/qdoc/docparser.cpp`

This reference documents QDoc inline markup commands, their purposes, and best practices.

## Semantic Purpose of Markup

**Markup encodes meaning, not just formatting.** Each command tells readers what
KIND of information they're seeing:

| Command | What it tells readers | Why it matters |
|---------|----------------------|----------------|
| `\a` | "This is a parameter you pass to this function" | Connects prose to API signature |
| `\c` | "This is code - a literal value or keyword" | Distinguishes code from prose |
| `\e` | "This concept is emphasized/important" | Draws attention without implying code |
| `\b` | "This is a strong callout (Note:, Warning:)" | Signals important notices |
| `\uicontrol` | "This is a UI element to click/interact with" | Guides user through interface |
| `\l` | "Click here to learn more" | Enables navigation to related docs |

**Why semantic markup matters:**

1. **Reader comprehension** - Readers instantly know what type of information each word is
2. **Scannability** - Technical readers scan for parameters, code values, UI elements
3. **Copy-paste accuracy** - Code marked with `\c` is unambiguous for copying
4. **Translation safety** - Translators know `\c{nullptr}` should not be translated
5. **Accessibility** - Screen readers can convey semantic meaning

**Common oversight:** Text reads correctly as English prose, so reviewers miss that
semantic information is absent. "Returns true" is grammatically correct but doesn't
tell readers that `true` is the C++ keyword they'd write in code.

## Quick Reference

| Command | Purpose | Renders As | Example |
|---------|---------|------------|---------|
| `\a` | Parameter marker | *italics* | `\a parent` |
| `\c` | Code font | `monospace` | `\c true` |
| `\e` | Emphasis | *italics* | `\e important` |
| `\b` | Bold | **bold** | `\b{Note:}` |
| `\tt` | Teletype (code with nesting) | `monospace` | `\tt{\l{QString}}` |
| `\uicontrol` | UI element | **bold** | `\uicontrol{Save}` |
| `\underline` | Underline | underlined | `\underline{F}ile` |
| `\sub` | Subscript | x₂ | `a\sub 2` |
| `\sup` | Superscript | x² | `a\sup 2` |

---

## Detailed Command Reference

### `\a` - Parameter Marker

**Source:** docparser.cpp:373-378

Marks function/method parameter names in documentation. QDoc validates that all
parameters are documented and warns about misspellings.

**Syntax:**
```qdoc
\a paramName
\a{paramName}
```

**Correct Usage:**
```qdoc
/*!
    \fn void Widget::setSize(int width, int height)

    Sets the widget dimensions. The \a width and \a height
    parameters specify the new size in pixels.

    If \a{width} is negative, the current width is preserved.
*/
```

**Incorrect Usage:**
```qdoc
// WRONG - \a in property documentation (properties have no parameters)
/*!
    \qmlproperty var font::features

    Applies values based on the contents in \a features.  // ❌
*/

// CORRECT - remove \a since this is a property, not a function
/*!
    \qmlproperty var font::features

    Applies values based on the contents in features.  // ✓
*/
```

**Rules:**
- Use ONLY for function/method parameters
- QDoc emits warning: "Undocumented parameter 'X'" if parameter not mentioned
- QDoc emits warning if `\a` references non-existent parameter
- Curly braces optional but useful for clarity: `\a{parentWidget}`

**QDoc Warnings:**
```
warning: Undocumented parameter 'width' in QWidget::setSize()
warning: No such parameter 'widht' in QWidget::setSize()
```

---

### `\c` - Code Font

**Source:** docparser.cpp:400-405

Renders text in monospace (code) font. Used for inline code elements that are
not function parameters.

**Syntax:**
```qdoc
\c word
\c{multiple words or special chars}
```

**Correct Usage:**
```qdoc
Returns \c true if the operation succeeds, otherwise returns \c false.

The default value is \c{Qt::AlignLeft}.

Set the \c width property to \c 100.

Use the \c{QLineEdit::setText()} function to set text.
```

**Incorrect Usage:**
```qdoc
// WRONG - \c cannot contain backslash commands
\c{\l{QString}}  // ❌ Parse error

// CORRECT - use \tt for nested commands
\tt{\l{QString}}  // ✓
```

**Rules:**
- Use for: keywords (`true`, `false`, `nullptr`), values, property names, enum values
- Single word: `\c true`
- Multiple words or special characters: `\c{Qt::AlignLeft}`
- Cannot contain nested QDoc commands (use `\tt` instead)
- Suppresses autolinking: `\c{QString}` renders as code without link
- Backslash renders literally inside `\c`: `\c{C:\path}` works

**Best Practices:**
```qdoc
// Always use \c for boolean values
Returns \c true if valid.           // ✓
Returns true if valid.              // ✗ Looks like prose

// Always use \c for numeric literals
The default is \c 0.                // ✓
The default is 0.                   // ✗ Ambiguous

// Always use \c for enum values
The alignment is \c{Qt::AlignLeft}. // ✓
The alignment is Qt::AlignLeft.     // Autolinks, but \c is clearer for values
```

**Boolean Function Documentation Pattern:**

For functions returning `bool`, use this pattern consistently:
```qdoc
Returns \c true if the condition is met; otherwise returns \c false.
```

**REVIEW TIP:** When reviewing `is*()`, `has*()`, `can*()` functions, actively
scan for "Returns true" or "returns false" without `\c`. This is the most
commonly missed semantic markup issue because the text reads correctly as prose.

---

### `\e` - Emphasis (Italics)

**Source:** docparser.cpp:631-632

Renders text in italics for general emphasis. Do NOT use for function parameters
(use `\a` instead).

**Syntax:**
```qdoc
\e word
\e{multiple words}
```

**Correct Usage:**
```qdoc
This is an \e important consideration.

The \e{geometric series} converges when the ratio is less than 1.

Unlike the base class, this implementation is \e not thread-safe.
```

**Incorrect Usage:**
```qdoc
// WRONG - use \a for function parameters
The \e parent widget owns this object.  // ❌

// CORRECT
The \a parent widget owns this object.  // ✓
```

**Rules:**
- Use for general emphasis in prose text
- NOT for function parameters (use `\a`)
- Deprecated alias: `\i` (still works but emits deprecation warning)

---

### `\b` - Bold

**Source:** docparser.cpp:393-394

Renders text in bold for strong emphasis.

**Syntax:**
```qdoc
\b word
\b{multiple words}
```

**Correct Usage:**
```qdoc
\b{Note:} This function is reentrant.

\b{Warning:} Calling this on the main thread may cause freezing.

\b{Important:} Always check the return value.
```

**Rules:**
- Use for strong emphasis, headings within documentation
- Deprecated alias: `\bold` (still works but emits warning)
- Often used in macros:
  ```
  macro.note = "\\b{Note:}"
  macro.warning = "\\b{Warning:}"
  ```

---

### `\tt` - Teletype (Code with Nesting)

Renders text in monospace font, but unlike `\c`, allows nested QDoc commands.

**Syntax:**
```qdoc
\tt{text with \commands}
```

**When to Use:**
```qdoc
// Use \tt when you need links inside code font
See the \tt{\l{QString}} class for details.

// Use \c when no nested commands
Use \c{QString} for text handling.
```

**Rules:**
- Use when you need `\l` or other commands inside monospace text
- Prefer `\c` for simple cases (more common in Qt docs)

---

### `\uicontrol` - UI Element Marker

Marks user interface elements like menu items, buttons, and labels. Renders
as bold in HTML output.

**Syntax:**
```qdoc
\uicontrol{Element Name}
```

**Correct Usage:**
```qdoc
Click \uicontrol{File} > \uicontrol{Save} to save the document.

Press the \uicontrol{OK} button to confirm.

Select the \uicontrol{Enable logging} checkbox.

In the \uicontrol{Name} field, enter your username.
```

**Incorrect Usage:**
```qdoc
// WRONG - UI elements not marked up
Click File > Save to save the document.  // ❌

// WRONG - using \b instead of \uicontrol
Click \b{File} > \b{Save}.  // ❌ Semantically incorrect
```

**Rules:**
- Use for ALL user interface elements:
  - Menu items: `\uicontrol{File}`, `\uicontrol{Edit}`
  - Buttons: `\uicontrol{OK}`, `\uicontrol{Cancel}`
  - Checkboxes: `\uicontrol{Enable feature}`
  - Text fields: `\uicontrol{Name}`, `\uicontrol{Password}`
  - Tabs: `\uicontrol{General}`, `\uicontrol{Advanced}`
- Use `>` to show menu paths: `\uicontrol{File} > \uicontrol{Open}`
- Improves accessibility and translation

---

### `\sub` and `\sup` - Subscript and Superscript

For mathematical notation.

**Syntax:**
```qdoc
x\sub 2        // x₂
x\sup 2        // x²
x\sub{index}   // For multi-character subscripts
```

**Usage:**
```qdoc
The formula is a\sup 2 + b\sup 2 = c\sup 2.

The coefficient a\sub{n+1} depends on a\sub n.
```

---

## Decision Tree

```
What are you marking up?
│
├─ Function/method parameter?
│   └─ Use \a
│      └─ \a width, \a{parentWidget}
│
├─ Code element (keyword, value, property name)?
│   ├─ Need nested commands inside?
│   │   └─ Use \tt
│   │      └─ \tt{\l{QString}}
│   └─ No nested commands?
│       └─ Use \c
│          └─ \c true, \c{Qt::AlignLeft}, \c nullptr
│
├─ UI element (menu, button, field, checkbox)?
│   └─ Use \uicontrol
│      └─ \uicontrol{Save}, \uicontrol{File} > \uicontrol{Open}
│
├─ General emphasis (important concept)?
│   └─ Use \e
│      └─ \e important, \e{key concept}
│
├─ Strong emphasis (note, warning)?
│   └─ Use \b
│      └─ \b{Note:}, \b{Warning:}
│
└─ Mathematical notation?
    ├─ Subscript → \sub
    │   └─ x\sub 2
    └─ Superscript → \sup
        └─ x\sup 2
```

---

## Reviewer Scanning Guide

**Scan documentation for these patterns that indicate missing semantic markup:**

### `\a` - Parameter References
```
Pattern: Parameter name from signature appears in prose without \a
Scan for: Words matching parameter names in the \fn signature
Fix:      Add \a before each parameter reference
```
Example: If `\fn void setSize(int width, int height)`, scan prose for "width" and "height"

### `\c` - Code Literals
```
Pattern: Code values appearing as plain text
Scan for: true, false, nullptr, NULL, numeric literals, enum values
Fix:      Wrap in \c or \c{}
```
Examples to find and fix:
- "Returns true" → "Returns `\c true`"
- "default is 0" → "default is `\c 0`"
- "set to Qt::AlignLeft" → "set to `\c{Qt::AlignLeft}`"

### `\uicontrol` - UI Elements
```
Pattern: Menu items, buttons, or UI labels in prose
Scan for: Quoted UI text, menu paths with >, button names
Fix:      Wrap each UI element in \uicontrol{}
```
Examples to find and fix:
- "click OK" → "click `\uicontrol{OK}`"
- "File > Save" → "`\uicontrol{File}` > `\uicontrol{Save}`"
- "the Name field" → "the `\uicontrol{Name}` field"

### `\e` - Emphasis (NOT for code or params)
```
Pattern: Important concepts that need emphasis
Scan for: Words that should be italicized for emphasis
Verify:   NOT a parameter (use \a), NOT code (use \c)
```

---

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| `\a` in property docs | Properties don't have parameters | Remove `\a` or use plain text |
| `\e` for parameters | Inconsistent; QDoc can't validate | Use `\a` for parameters |
| Unmarked UI elements | Poor accessibility, hard to translate | Use `\uicontrol` |
| `\c` with nested `\l` | `\c` can't parse backslash inside | Use `\tt` |
| Unmarked `true`/`false` | Looks like prose, not code | Use `\c true`, `\c false` |
| `\b` for UI elements | Semantically incorrect | Use `\uicontrol` |
| `\i` instead of `\e` | Deprecated, causes warning | Use `\e` |
| `\bold` instead of `\b` | Deprecated, causes warning | Use `\b` |

---

## Deprecated Commands

| Deprecated | Replacement | Warning |
|------------|-------------|---------|
| `\i` | `\e` | "'\\i' is deprecated. Use '\\e' for italic or '\\li' for list item" |
| `\bold` | `\b` | "'\\bold' is deprecated. Use '\\b'" |
| `\o` | `\li` | For list items |

---

## QDoc Warnings Related to Markup

| Warning | Cause | Fix |
|---------|-------|-----|
| "Undocumented parameter 'X'" | Parameter not mentioned with `\a` | Add `\a X` to documentation |
| "No such parameter 'X'" | `\a` references non-existent parameter | Check spelling, remove if not a parameter |
| "'\\i' is deprecated" | Using `\i` instead of `\e` | Replace with `\e` |
| "'\\bold' is deprecated" | Using `\bold` instead of `\b` | Replace with `\b` |

---

## Integration with Other Commands

### With `\l` (Links)

```qdoc
// Link renders as link (clickable)
See \l{QString} for details.

// \c suppresses link, renders as code
Use \c{QString} for text.  // Not clickable

// \tt allows link inside code font
See \tt{\l{QString}} docs.  // Clickable, monospace
```

### With Autolinks

```qdoc
// Autolinks (no markup needed for C++ types)
QString handles Unicode text.  // Autolinks

// Suppress autolink with \c
The \c{QString} type is...     // No link, just code font

// Don't add unnecessary \l to autolinked types
\l{QString} handles text.      // Redundant - autolinks anyway
```

---

## Version History

- **v1.0** (2026-02-18): Initial version with comprehensive markup command reference
