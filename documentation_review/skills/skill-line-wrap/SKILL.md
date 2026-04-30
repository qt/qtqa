---
name: skill-line-wrap
description: Reference for Qt's 80-column rule and text wrapping guidelines for documentation
metadata:
  version: "1.2"
---

# Qt Line Wrapping Reference

This reference documents Qt's 80-column rule and provides guidelines for wrapping documentation text to comply with Qt code style.

## Purpose

Documentation agents use this reference to:
1. Ensure all documentation lines stay within 80 characters
2. Wrap text at natural boundaries
3. Maintain consistent formatting across Qt documentation
4. Follow Qt Writing Guidelines and Qt Coding Style

## The 80-Column Rule

### Core Principle

**Qt source files follow an 80-column guideline, but enforcement varies by context.**

The rule is **required** for code and structured content, but **advisory** for prose paragraphs.

### Why 80 Columns?

1. **Code review**: Fits in side-by-side diff views
2. **Terminal compatibility**: Works in 80-column terminals
3. **Readability**: Optimal line length for reading
4. **Qt tradition**: Consistent with decades of Qt code style

### Enforcement Levels

| Context | Enforcement | Threshold | Action |
|---------|-------------|-----------|--------|
| C++ code | **Required** | 80 | Flag as issue |
| Code examples (`\code`) | **Required** | 80 | Flag as issue |
| Alt text | **Required** | 80 | Flag as issue |
| QDoc commands | **Required** | 80 | Flag as issue |
| **Prose paragraphs** | **Advisory** | 110 | Flag only if ≥110 |
| **Brief descriptions** | **Advisory** | 110 | Flag only if ≥110 |
| Table cells | Advisory | 110 | Flag only if ≥110 |
| Unbreakable content | Exempt | — | Never flag |

### Advisory Handling

For **advisory** contexts (prose paragraphs, brief descriptions, table cells):

1. **Lines ≤80**: No issue
2. **Lines 81-109**: Do not flag as individual issues
3. **Lines ≥110**: Flag as issue requiring fix

**End-of-review note**: If a patch contains advisory lines between 81-109 characters, add a non-blocking note at the end of the review:

> **Note:** This patch contains prose lines exceeding 80 columns. Consider wrapping for consistency with Qt style.

### How to Count

**Count from column 0 (start of line):**
```
Column: 0         1         2         3         4         5         6         7         8
        0123456789012345678901234567890123456789012345678901234567890123456789012345678901
        This line is exactly 80 characters including spaces and indentation
```

**Includes:**
- Leading whitespace (indentation)
- All characters
- Trailing whitespace (avoid this)

**Maximum**: 80 characters (positions 0-79)

## Indentation Standards

### Use Spaces, Never Tabs

Qt uses **4-space indentation** consistently:
```cpp
/*!
    \class ClassName
    \inmodule ModuleName
    \internal
*/
```

**Each level**: 4 spaces
- Level 0: 0 spaces (first column)
- Level 1: 4 spaces
- Level 2: 8 spaces
- Level 3: 12 spaces

### QDoc Comment Indentation

```cpp
/*!
    Line at indentation level 0 (4 spaces from left margin)
    \command at level 0

    Continued text at level 0
    Text can continue for multiple lines at same level
*/
```

**Rule**: All content inside `/*! ... */` is indented 4 spaces.

## Text Wrapping Guidelines

### When to Wrap

Wrap text when:
1. Line exceeds 80 characters
2. Adding more text would exceed 80 characters
3. Line is exactly 80 characters and needs modification

**Example:**
```
Column count: 81 characters
    This is a very long line of documentation text that exceeds the eighty character limit

Must wrap to:
    This is a very long line of documentation text that exceeds
    the eighty character limit
```

### Where to Break Lines

**Priority order:**

1. **After commas** - `param1, param2, param3` → break after comma
2. **After prepositions** - (for, to, with, in, of, from, by, at, on)
3. **After conjunctions** - (and, or, but)
4. **At natural phrase boundaries**

**Example:**
```
Before (85 chars):
The function takes three parameters: name, age, and address for the user record.

After:
The function takes three parameters: name, age, and address
for the user record.
```

### Where NOT to Break

**Avoid breaking:**
1. In the middle of words (obvious)
2. Between article and noun: "a class", "the method"
3. Between qualifier and noun: "public API", "internal class"
4. Inside class names: `QQuickItem` (keep together)
5. Inside Qt macros: `Q_OBJECT`, `Q_QUICK_EXPORT`
6. Inside URLs or file paths
7. In code snippets

## QDoc-Specific Wrapping

### QDoc Commands

**Keep QDoc commands on their own line:**

✅ **Correct:**
```cpp
/*!
    \class ClassName
    \inmodule ModuleName
    \internal
*/
```

❌ **Wrong:**
```cpp
/*!
    \class ClassName \inmodule ModuleName \internal
*/
```

### Long Class Names

If `\class` command exceeds 80 columns:
```cpp
/*!
    \class VeryLongNamespace::VeryLongClassName::NestedClass
    \inmodule QtVeryLongModuleName
    \internal
*/
```

**Count:**
- 4 spaces (indent)
- 7 characters (`\class `)
- Class name

If total > 80, nothing you can do - keep class name intact.

### Documentation Text

Wrap at natural boundaries:

```cpp
/*!
    \class QQmlSA::PropertyPrivate
    \inmodule QtQmlCompiler
    \internal

    This is an internal class used for managing property
    metadata in the QML static analyzer. It stores information
    about property types, bindings, and validation rules.
*/
```

**Indentation**: Continuation lines maintain same 4-space indent.

### Alt Text for Images

Alt text appears in `{}` braces after image filename:

```qdoc
\image filename.png
       {Alt text description that might be long enough to
       require wrapping across multiple lines}
```

**Rules:**
- First line: 7 spaces (aligns under filename)
- Continuation: Same 7-space indent
- Break at natural phrase boundaries
- Keep opening `{` on first line
- Keep closing `}` on last line

**Column counting:**
```
Column: 0         1         2         3         4         5         6         7         8
        012345678901234567890123456789012345678901234567890123456789012345678901234567890
    \image filename.png
           {Window with toolbar containing dark mode toggle and
           multiple action buttons for file operations}
```

Line 1: 4 (indent) + 6 (`\image`) + 1 (space) + 12 (`filename.png`) = 23 ✓
Line 2: 7 (brace indent) + 57 (text) = 64 ✓
Line 3: 7 (brace indent) + 48 (text including `}`) = 55 ✓

### Lists in Documentation

```cpp
/*!
    This class provides:
    \list
    \li Feature one with a long description that needs
        to wrap to the next line
    \li Feature two
    \li Feature three with another long description
        that also wraps
    \endlist
*/
```

**Indentation:**
- `\list`, `\endlist`: 4 spaces
- `\li`: 4 spaces
- Continuation: 8 spaces (double indent)

### Code Examples

```cpp
/*!
    Example usage:
    \code
    ReallyLongClassName object;
    object.veryLongMethodName(parameter1, parameter2,
                              parameter3);
    \endcode
*/
```

**For code blocks:**
- Follow C++ line length rules
- Use hanging indent for continuation (align with opening `(`)

## Special Cases

### Unbreakable Content

If a single word/element exceeds 80 columns:

1. **URLs**: Keep intact
   ```cpp
   // Acceptable: URLs can exceed 80 columns
   See https://doc.qt.io/qt-6/very-long-page-name-that-exceeds-eighty-characters.html
   ```

2. **File paths**: Keep intact
   ```cpp
   // Acceptable: Paths can exceed 80 columns
   File location: qtdeclarative/src/qmlcompiler/qqmlsomemodule/qqmlsomeverylong filename.cpp
   ```

3. **Class names**: Never break
   ```cpp
   \class QVeryLongNamespaceName::QVeryLongClassName
   ```

4. **Function signatures**: Try to break at parameters
   ```cpp
   void ClassName::veryLongFunctionName(
       int parameter1, int parameter2)
   ```

### Tables in QDoc

```cpp
/*!
    \table
    \header
        \li Property
        \li Description
    \row
        \li propertyName
        \li Long description that wraps to next line
            with proper indentation
    \endtable
*/
```

**Indentation:**
- `\table`, `\endtable`: 4 spaces
- `\header`, `\row`: 4 spaces
- `\li`: 8 spaces
- Content: 12 spaces
- Continuation: 12 spaces (same as content)

### Section Headers

```cpp
/*!
    \section1 Very Long Section Title That Might Exceed
              Eighty Characters

    Content follows...
*/
```

Break section titles at natural boundaries, align continuation.

## Wrapping Algorithms

### Basic Algorithm

```
1. Identify line length (count from column 0)
2. If length ≤ 80: Done
3. If length > 80:
   a. Find last break point before position 80
   b. Break at that point
   c. Apply proper continuation indent
   d. Repeat for next line
```

### Finding Break Points

```
1. Scan from position 80 backwards
2. Look for (in order):
   - Space after comma
   - Space after preposition
   - Space after conjunction
   - Any space at natural phrase boundary
3. Use first found break point
4. If no break point before position 40:
   - Line is mostly unbreakable
   - Keep as-is or break at position 80
```

### Continuation Indent

Depends on context:

| Context | Indent Rule | Example |
|---------|-------------|---------|
| QDoc comment | Same as first line (4 spaces) | `    Text continues` |
| Alt text | Align under text (7 spaces) | `       {Text continues` |
| Function params | Align under opening `(` | `        parameter)` |
| List items | Double indent (8 spaces) | `        continuation` |
| Table cells | Triple indent (12 spaces) | `            continuation` |
| **QDoc command + text** | **Hanging indent (align with text)** | See below |

### Hanging Indent Alignment

**Valid pattern:** Continuation lines align with the start of text after a QDoc command, not with the command itself.

```qdoc
    \note Support for specific configurations or operating system versions may
          end before the support for Qt \qtver does.
    ^^^^  ^^^^^^
    4sp   +6 chars (\note ) = 10 spaces aligns with "Support..."
```

**This is correct.** The continuation aligns with the prose, not the `\note` command.

**Applies to:**
- `\note` + text (6 chars → 10-space continuation)
- `\warning` + text (9 chars → 13-space continuation)
- `\section1` + title (10 chars → 14-space continuation)
- Any command where text follows on the same line

**Do NOT flag as inconsistent indentation.** This is intentional alignment for readability.

**Contrast with block-level continuation:**
```qdoc
    \note
    This is a note that starts on its own line.
    Continuation stays at 4-space indent.
```

When the command and text are on separate lines, use standard 4-space indent.

## Examples

### Example 1: Simple Text Wrapping

**Before** (83 characters):
```cpp
    This is a documentation line that is too long and exceeds the eighty character rule.
```

**After** (break after "exceeds"):
```cpp
    This is a documentation line that is too long and exceeds
    the eighty character rule.
```

### Example 2: Alt Text

**Before** (88 characters on line 2):
```qdoc
\image controls-gallery.png
       {Gallery window displaying all Qt Quick Controls in the Basic style with examples}
```

**After** (break at natural boundary):
```qdoc
\image controls-gallery.png
       {Gallery window displaying all Qt Quick Controls in the
       Basic style with examples}
```

## Validation Checklist

Before submitting documentation:

**Required (must fix):**
- [ ] Code and code examples ≤80 characters
- [ ] Alt text ≤80 characters
- [ ] QDoc commands ≤80 characters and on separate lines
- [ ] Proper indentation (4 spaces per level)
- [ ] No mid-word breaks
- [ ] Continuation lines properly indented
- [ ] No trailing whitespace

**Advisory (flag if ≥110, note if 81-109):**
- [ ] Prose paragraphs checked for excessive length
- [ ] Brief descriptions checked for excessive length
- [ ] Table cells checked for excessive length

**Exempt (never flag):**
- [ ] URLs, file paths, class names kept intact
- [ ] QDoc link targets kept intact
- [ ] Unbreakable identifiers preserved
- [ ] Hanging indent alignment (continuation aligns with text after command)

## Tools for Checking

**Bash command:**
```bash
# Check line lengths in a file
cat file.cpp | awk '{print length, $0}' | grep "^[8-9][0-9]" | head -20
```

## Common Mistakes

1. **Counting wrong** - Count from column 0, including indentation
2. **Breaking class names** - Keep intact even if > 80 chars
3. **Wrong continuation indent** - Match context (4 spaces for docs, 7 for alt text)
4. **Breaking mid-phrase** - Use priority order (after commas, prepositions, etc.)
5. **Combining QDoc commands** - One command per line

## Related References

- **Qt Writing Guidelines**: https://wiki.qt.io/Qt_Writing_Guidelines
- **Qt Coding Style**: https://wiki.qt.io/Qt_Coding_Style
- **QDoc Manual**: https://doc.qt.io/qt-6/qdoc-index.html

## Summary

**Key Points:**
- ✅ 80-column **required** for: C++ code, code examples, alt text, QDoc commands
- ✅ 80-column **advisory** for: prose paragraphs, brief descriptions, table cells
- ✅ Advisory threshold: flag only if line ≥110 characters
- ✅ Use 4-space indentation (never tabs)
- ✅ Break at natural boundaries (commas, prepositions, conjunctions)
- ✅ Keep QDoc commands on separate lines
- ✅ Preserve unbreakable elements (class names, URLs, link targets)

**Quick Reference:**
- Documentation indent: 4 spaces
- Alt text indent: 7 spaces (align under filename)
- List continuation: 8 spaces
- Table cell continuation: 12 spaces

**End-of-Review Note (for advisory content 81-109 chars):**
> **Note:** This patch contains prose lines exceeding 80 columns. Consider wrapping for consistency with Qt style.

## Version History

- **v1.2** (2026-02-23): Added hanging indent alignment pattern (command + text continuation)
- **v1.1** (2026-02-23): Added advisory enforcement for prose; 110-char threshold; end-of-review note
- **v1.0** (2025-11-27): Initial version with comprehensive wrapping guidelines
