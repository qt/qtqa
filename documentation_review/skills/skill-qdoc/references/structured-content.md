# QDoc Structured Content Reference

**Sources:**
- Microsoft Style Guide: [Lists](https://learn.microsoft.com/en-us/style-guide/scannable-content/lists), [Tables](https://learn.microsoft.com/en-us/style-guide/scannable-content/tables), [Code Examples](https://learn.microsoft.com/en-us/style-guide/developer-content/code-examples)
- Google Technical Writing: [Lists and Tables](https://developers.google.com/tech-writing/one/lists-and-tables)
- Qt Writing Guidelines: https://wiki.qt.io/Qt_Writing_Guidelines

This reference documents QDoc structured content commands (lists, tables, code blocks),
when to use them, formatting rules, and anti-patterns to avoid.

---

## Lists

### QDoc Syntax

```qdoc
\list
\li First item
\li Second item
\li Third item
\endlist
```

**Numbered list:**
```qdoc
\list 1
\li First step
\li Second step
\li Third step
\endlist
```

**Styled lists:**
- `\list` — bulleted (default)
- `\list 1` — numbered (1, 2, 3)
- `\list A` — alphabetical (A, B, C)
- `\list a` — lowercase alphabetical (a, b, c)
- `\list i` — lowercase roman (i, ii, iii)
- `\list I` — uppercase roman (I, II, III)

### When to Use Lists

**Use a bulleted list when:**
- 3+ related items that don't require specific order
- Items benefit from visual separation
- Items are equal in importance

**Use a numbered list when:**
- Steps must be followed in sequence
- Items are prioritized/ranked
- Items will be referenced by number

**Use prose instead when:**
- Only 2 items (not worth the visual overhead)
- Items require explanation or context between them
- Page already has many lists (overuse)
- Relationship between items matters more than items themselves

### List Length

**Source:** [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/scannable-content/lists)

> "A list should have at least two items but (if possible) no more than seven items."

| Items | Action |
|-------|--------|
| 1 | Not a list—use prose |
| 2-7 | Ideal range |
| 8+ | Consider grouping into sublists or sections |

### Parallelism (CRITICAL)

**All list items must have the same grammatical structure.**

**Bad (mixed structures):**
```qdoc
\list
\li Set the property          // imperative verb
\li Calling the function      // gerund
\li You should verify         // "you should" + verb
\endlist
```

**Good (parallel imperatives):**
```qdoc
\list
\li Set the property
\li Call the function
\li Verify the result
\endlist
```

**Good (parallel nouns):**
```qdoc
\list
\li Property configuration
\li Function invocation
\li Result verification
\endlist
```

### Introduction Requirements

**Source:** [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/scannable-content/lists)

> "Make sure the purpose of the list is clear. Introduce the list with a heading,
> a complete sentence, or a fragment that ends with a colon."

**Bad (no introduction):**
```qdoc
\list
\li Create the widget
\li Set properties
\li Show the widget
\endlist
```

**Good (sentence introduction):**
```qdoc
To display a widget:

\list 1
\li Create the widget.
\li Set properties.
\li Show the widget.
\endlist
```

**Good (fragment with colon):**
```qdoc
The function accepts the following parameters:

\list
\li \a width - the width in pixels
\li \a height - the height in pixels
\endlist
```

### Capitalization

Begin each item with a capital letter unless there's a reason not to (e.g., a
command that's always lowercase).

### Punctuation

**Source:** [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/scannable-content/lists)

| Item Type | End Punctuation |
|-----------|-----------------|
| Complete sentences | Period |
| Sentence fragments | No period |
| Items ≤3 words | No period |
| UI labels, headings | No period |

**Never use:**
- Semicolons at end of items
- Commas at end of items
- Conjunctions ("and", "or") at end of items

**Qt guideline:** "Be consistent with forming lists. Use the same tone or mode
and be consistent about ending with periods."

### Term Lists (Definition Lists)

**Source:** [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/scannable-content/lists)

For lists that define terms:

```qdoc
\list
\li \b{Draft.} You created the document but are still working on it.
\li \b{In review.} You submitted the document for review.
\li \b{Approved.} The document was approved.
\endlist
```

**Rules:**
- Use bulleted list (not numbered)
- **Bold** the term
- Period between term and definition (in plain text)
- Definition starts with capital letter
- Definition ends with period

---

## Tables

### QDoc Syntax

```qdoc
\table
\header
    \li Column 1
    \li Column 2
\row
    \li Cell 1
    \li Cell 2
\row
    \li Cell 3
    \li Cell 4
\endtable
```

**With width:**
```qdoc
\table 100%
...
\endtable
```

**Cell spanning:**
```qdoc
\li {2,1} Spans 2 columns, 1 row
\li {1,2} Spans 1 column, 2 rows
```

### When to Use Tables

**Source:** [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/scannable-content/tables)

**Use tables for:**
- Data with 2+ attributes per item
- Comparisons across multiple dimensions
- Reference information (commands + descriptions)
- Collections with consistent structure

**Do NOT use tables for:**
- Simple lists of similar items (use `\list` instead)
- Single-column content
- Heavily narrative content

| Good for Tables | Use List Instead |
|-----------------|------------------|
| Command + Description + Example | List of features |
| Parameter + Type + Default | List of requirements |
| Platform + Behavior | List of supported formats |

### Header Requirements

**Source:** [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/scannable-content/tables)

> "Make headers precise for usability. For example, don't use 'Name'. Instead,
> make column headers specific as in 'Group' or 'Employee'."

**Bad:**
```qdoc
\header
    \li Name
    \li Value
```

**Good:**
```qdoc
\header
    \li Property
    \li Default value
```

**Rules:**
- Always include header row
- Make headers specific, not generic
- Use sentence-case capitalization
- Visually distinguish headers (QDoc does this automatically)

### Left Column

> "Place information that identifies the contents of a row in the leftmost column."

The left column should contain the "key" that readers scan for:
- Function names
- Property names
- Parameter names
- Enum values

### Empty Cells

**Source:** [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/scannable-content/tables)

> "Don't leave a cell blank or use an em dash to indicate there's no entry.
> Instead, use *Not applicable* or *None.*"

**Bad:**
```qdoc
\row
    \li width
    \li —
```

**Good:**
```qdoc
\row
    \li width
    \li None
```

### Cell Content

- Keep brief—ideally one line per cell
- Limit to ~2 sentences maximum
- Maintain parallelism within columns

### Introduction Requirements

**Source:** [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/scannable-content/tables)

> "If there's text that introduces the table, it should be a complete sentence
> and end with a period, not a colon."

**Bad:**
```qdoc
The following table shows the parameters:
```

**Good:**
```qdoc
The following table describes the available parameters.
```

### Parallelism in Tables

All items within a column should have the same structure.

**Bad (mixed):**
```qdoc
\row
    \li width
    \li Sets the width              // verb phrase
\row
    \li height
    \li The height of the widget    // noun phrase
```

**Good (consistent verb phrases):**
```qdoc
\row
    \li width
    \li Sets the width in pixels.
\row
    \li height
    \li Sets the height in pixels.
```

---

## Code Blocks

### QDoc Commands

| Command | Use For |
|---------|---------|
| `\snippet` | **Preferred** — includes code from external file |
| `\code` | Inline code blocks (less preferred) |
| `\badcode` | Incorrect examples or non-code output |
| `\qml` | QML code specifically |
| `\codeline` | Single line of code |

### Qt Preference: \snippet over \code

**Source:** Qt Writing Guidelines

> "It is best to include code snippets using the `\snippet <filename>` command."
> "`\code` and `\endcode` is no longer preferred."

**Why `\snippet` is preferred:**
- Code is compiled and tested (guaranteed to work)
- Single source of truth (code in example, included in docs)
- Easier maintenance (update code once)

**Syntax:**
```qdoc
\snippet snippets/myclass.cpp constructor
```

Where `myclass.cpp` contains:
```cpp
//! [constructor]
MyClass::MyClass(QObject *parent)
    : QObject(parent)
{
}
//! [constructor]
```

### When to Use \code

Use `\code` only when:
- Code is purely illustrative (not meant to be compiled)
- Showing syntax patterns rather than real code
- Very short examples (1-3 lines)

```qdoc
\code
widget->show();
\endcode
```

### When to Use \badcode

Use `\badcode` for:
- Command-line output
- Incorrect examples (showing what NOT to do)
- Non-compilable syntax examples
- File paths or configuration

```qdoc
\badcode
$ cmake --build .
\endcode
```

### When to Use \qml

Use `\qml` for QML code:

```qdoc
\qml
import QtQuick

Rectangle {
    width: 100
    height: 100
    color: "red"
}
\endqml
```

### Code Example Guidelines

**Source:** [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/developer-content/code-examples)

1. **Start simple** — Build complexity after covering common scenarios
2. **Meaningful tasks** — Illustrate real problems, not contrived examples
3. **Introduction required** — Describe scenario, requirements, dependencies
4. **Comments** — Explain non-obvious details; don't overdo
5. **Show output** — Include expected results
6. **Test everything** — Always compile and verify

### Code Introduction

Always introduce code blocks with context:

**Bad:**
```qdoc
\snippet examples/widget.cpp setup
```

**Good:**
```qdoc
The following example creates a widget and sets its geometry:

\snippet examples/widget.cpp setup
```

---

## Decision Framework

### Prose vs List vs Table

```
How many items?
│
├─ 1 item
│   └─ Use prose
│
├─ 2 items
│   ├─ Related/comparable? → Consider prose or simple list
│   └─ Complex with attributes? → Consider table
│
├─ 3-7 items
│   ├─ Sequential/ordered? → Numbered list
│   ├─ Single attribute each? → Bulleted list
│   └─ Multiple attributes? → Table
│
└─ 8+ items
    └─ Group into sections or sublists
```

### When to Convert Prose to List

**Convert when:**
- Sentence contains 3+ items separated by commas
- Items are steps that should be followed
- Items need visual emphasis

**Example conversion:**

Before:
> The function supports PNG, JPEG, GIF, and WebP formats.

After:
```qdoc
The function supports the following formats:

\list
\li PNG
\li JPEG
\li GIF
\li WebP
\endlist
```

**Don't convert when:**
- Only 2 items
- Items need explanation between them
- Page already has many lists

---

## Anti-Patterns

### List Anti-Patterns

| Anti-Pattern | Problem | Fix |
|--------------|---------|-----|
| Single-item list | Not a list | Use prose |
| 10+ items | Too long to scan | Group into sections |
| No introduction | Purpose unclear | Add lead-in sentence |
| Nonparallel items | Hard to scan | Make all items same structure |
| Embedded list in sentence | Hard to read | Convert to proper list |
| Mixed punctuation | Inconsistent | Pick one style, apply to all |
| Ends with "and"/"or" | Unnecessary | Remove conjunctions |

### Table Anti-Patterns

| Anti-Pattern | Problem | Fix |
|--------------|---------|-----|
| Single-column table | Should be a list | Use `\list` |
| Generic headers ("Name", "Value") | Not descriptive | Use specific headers |
| Blank cells | Confusing | Use "None" or "Not applicable" |
| Long cell content | Hard to scan | Shorten or use prose |
| No introduction | Purpose unclear | Add introductory sentence |
| Nonparallel columns | Inconsistent | Make all items same structure |

### Code Anti-Patterns

| Anti-Pattern | Problem | Fix |
|--------------|---------|-----|
| `\code` for real examples | Code may break | Use `\snippet` |
| No introduction | Context missing | Add lead-in sentence |
| Untested code | May not work | Always compile and test |
| Over-commented | Cluttered | Comment only non-obvious parts |
| No output shown | Incomplete | Show expected results |

---

## Reviewer Checklist

### Lists
- [ ] **Length** — 2-7 items (not 1, not 8+)
- [ ] **Type** — Bulleted (unordered) or numbered (sequential)
- [ ] **Introduction** — Lead-in sentence or heading present
- [ ] **Parallelism** — All items same grammatical structure
- [ ] **Capitalization** — Each item starts with capital
- [ ] **Punctuation** — Consistent; periods only for complete sentences
- [ ] **No conjunctions** — No "and"/"or" at end of items

### Tables
- [ ] **Appropriate** — Not a single-column list
- [ ] **Headers** — Present and specific (not "Name"/"Value")
- [ ] **Introduction** — Complete sentence ending with period
- [ ] **Left column** — Contains identifying information
- [ ] **Empty cells** — "None" or "Not applicable" (not blank)
- [ ] **Parallelism** — Items in each column same structure
- [ ] **Cell length** — Brief, ideally one line

### Code Blocks
- [ ] **Command** — `\snippet` preferred over `\code`
- [ ] **Introduction** — Context sentence before code
- [ ] **Tested** — Code compiles and runs
- [ ] **Output** — Expected results shown or described
- [ ] **Comments** — Non-obvious parts explained

---

## Version History

- **v1.0** (2026-02-23): Initial version with lists, tables, code blocks,
  decision framework, anti-patterns, and reviewer checklist. Sources: Microsoft
  Style Guide, Google Technical Writing, Qt Writing Guidelines.
