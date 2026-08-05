<!-- Loaded on demand by skill-language-style/SKILL.md router. Part of skill-language-style. -->

## Structured Content Rules

For detailed formatting rules, QDoc syntax, and anti-patterns, see **skill-qdoc** (`references/structured-content.md`).

### R52. List Length

**Rule**: Lists should have 2-7 items. A single item is not a list; use prose. More than 7 items should be grouped into sublists or sections.

**Examples**:
```
❌ Single item (not a list):
\list
\li The widget
\endlist

❌ Too many items (hard to scan):
\list
\li Item 1
\li Item 2
... (10 items)
\endlist

✅ Appropriate length:
\list
\li First item
\li Second item
\li Third item
\endlist
```

**Sources**: S9 (Microsoft Style Guide - "Lists")

---

### R53. List Punctuation

**Rule**: Use periods only for complete sentences. Never use semicolons, commas, or conjunctions (and/or) at end of items.

**Examples**:
```
✅ Fragments (no periods):
\list
\li The width in pixels
\li The height in pixels
\li The depth in pixels
\endlist

✅ Complete sentences (periods):
\list
\li Set the width before showing the widget.
\li Call update() to refresh the display.
\li Verify the result matches expectations.
\endlist

❌ Mixed (inconsistent):
\list
\li The width in pixels.
\li Height
\li Sets the depth
\endlist

❌ Conjunctions at end:
\list
\li First item;
\li Second item; and
\li Third item.
\endlist
```

**Exception**: No periods if all items have ≤3 words or are UI labels/headings.

**Sources**: S9 (Microsoft Style Guide - "Lists")

---

### R54. List and Table Introductions

**Rule**: Always introduce lists and tables with context. Lists: heading, sentence, or fragment ending with colon. Tables: complete sentence ending with period (not colon).

**Examples**:
```
✅ List with introduction:
The function accepts the following parameters:

\list
\li \a width - the width in pixels
\li \a height - the height in pixels
\endlist

✅ Table with introduction:
The following table describes the available properties.

\table
...
\endtable

❌ No introduction (purpose unclear):
\list
\li width
\li height
\endlist
```

**Sources**: S9 (Microsoft Style Guide - "Lists", "Tables")

---

### R55. Table Empty Cells

**Rule**: Never leave table cells blank. Use "None" or "Not applicable" instead.

**Exception**: Optional metadata columns (e.g., "Notes", "Comments", "Remarks") may be left
blank when there is nothing to note. In these columns, a blank cell indicates "no special
notes" rather than missing data. This is common in platform support tables and similar
reference tables where most rows have no special notes.

**Examples**:
```
❌ Blank cell (data column):
\row
    \li width
    \li

✅ Explicit (data column):
\row
    \li width
    \li None

✅ Blank cell (optional "Notes" column):
\header
    \li Platform
    \li Compiler
    \li Notes
\row
    \li Windows 11
    \li MSVC 2022
    \li
\row
    \li Ubuntu 24.04
    \li GCC 14
    \li Requires glibc 2.34+
```

**Sources**: S9 (Microsoft Style Guide - "Tables")

---

### R56. Table Headers

**Rule**: Tables must have header rows with specific, descriptive column names. Avoid generic headers like "Name" or "Value".

**Examples**:
```
❌ Generic headers:
\header
    \li Name
    \li Value

✅ Specific headers:
\header
    \li Property
    \li Default value

✅ Specific headers:
\header
    \li Function
    \li Description
```

**Sources**: S9 (Microsoft Style Guide - "Tables")

---

### R57. Legal and Boilerplate Text Exception

**Rule**: Legal text, disclaimers, warranties, and license terms are exempt from standard
style review. These texts follow different conventions and are typically provided by legal
counsel.

**What is exempt**:
- Warranty disclaimers ("AS IS", "WITHOUT WARRANTY OF ANY KIND")
- License terms and conditions
- Legal notices and copyright statements
- Indemnification clauses
- Liability limitations

**Why exempt**:
- Legal text uses specific language for liability protection
- Modifications require legal counsel approval
- Formal/passive constructions are intentional for legal precision
- Standard style rules (R1-R56) do not apply to legal sections

**Detection**: Look for section titles containing:
- "Legal Disclaimer"
- "Warranty"
- "License"
- "Terms and Conditions"
- Standard legal phrases: "AS IS", "TO THE MAXIMUM EXTENT PERMITTED BY LAW"

**Example**:
```qdoc
\section1 General Legal Disclaimer

Please note that Qt is offered on an "as is" basis without warranty
of any kind...
```
This text is EXEMPT from R1 (active voice), R2 (conciseness), R38 (Latin terms), etc.

**Action**: When reviewing legal text, note "Legal text - exempt from style review" and
move on. Do not suggest language changes without explicit legal guidance.

**Sources**: Industry standard practice; legal document conventions

---


