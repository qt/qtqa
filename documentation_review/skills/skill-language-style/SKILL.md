---
name: skill-language-style
description: Language, grammar, and style guidelines for Qt documentation including active voice, terminology, QUIP 25 standards, and proper API documentation patterns. Covers both WHAT to write (style/content) and HOW to write it (QDoc syntax).
metadata:
  version: "3.7"
---

# Qt Language and Style Guidelines

**Version**: 3.7
**Purpose**: Reference for language, grammar, and style standards when writing or reviewing Qt documentation
**Scope**: Applies to all Qt documentation (QDoc comments, user guides, tutorials, API docs, examples)

---

## Overview

Language and style guidelines for Qt documentation, consolidating rules from
Qt Writing Guidelines (S1), QUIP 25 (S2), C++/QML Documentation Style
(S3/S4), and Microsoft Style Guide (S9). QDoc Manual (S10) covers command
syntax.

**Source precedence:** S1 > S2 > S3/S4 > S5/S6 > S9 (supplementary only).
**Full source details:** See `references/sources.md`.

---

## Verification Workflow (Generic)

When reviewing documentation and encountering questions about correctness
(terminology, style, patterns, syntax), follow this workflow:

### Step 1: Identify the Domain and Relevant Source(s)

| Question Type | Authoritative Source(s) |
|---------------|------------------------|
| Terminology (Qt product/module names) | S7 (Qt Terms and Concepts) |
| Language, grammar, style | S2 (QUIP 25), S1 (Qt Writing Guidelines) |
| C++ API documentation patterns | S3 (C++ Documentation Style) |
| QML API documentation patterns | S4 (QML Documentation Style) |
| Example documentation | S5 (Qt Examples Guidelines), S6 (Writing Examples) |
| Alt text | S8 (Qt Alt Text Style) |
| QDoc command syntax | S10 (QDoc Manual) |
| General style (when Qt silent) | S9 (Microsoft Style Guide) |

### Step 2: Check the Authoritative Source(s)

1. **Fetch the relevant source** (URL or local file)
2. **Record what the source says** - this is the official guidance
3. **Note if the source is silent** - may need secondary sources

### Step 3: Check Existing Documentation for Consistency

1. **Search existing docs**: `grep -r "TERM" */doc --include="*.qdoc"`
2. **Count instances** of each variant
3. **Note inconsistencies**:
   - Existing docs may conflict with authoritative source
   - Existing docs may be inconsistent with themselves
   - Some patterns may be module-specific

### Step 4: Report Both and Let Author Decide

**Output format:**
```
**[Topic]: "[Variant A]" vs "[Variant B]"**

Official ([Source]): [What the authoritative source says]

Existing usage:
- "[Variant A]": N instances (file1.qdoc, file2.qdoc...)
- "[Variant B]": M instances (file3.qdoc, file4.qdoc...)

Inconsistency: [Describe if existing docs conflict with official or themselves]

Decision for author: [Options - align with official, maintain local pattern,
or flag for broader cleanup]
```

**Why this workflow matters:**
- Authoritative sources define correctness
- Existing docs show current state (may have accumulated inconsistencies)
- Authors need full information to make informed decisions
- Some inconsistencies may warrant separate cleanup patches
- Reviewers should inform, not unilaterally enforce

---

## Rule and Source Enumeration

This skill contains **65 enumerated rules (R1-R64, R51b)** and **10 enumerated sources (S1-S10)** for easy reference.

### Rules by Category
- **Core Principles**: R1-R10 (10 rules)
- **Grammar Rules**: R11-R13 (3 rules)
- **API Documentation**: R14-R19 (6 rules)
- **Example Documentation**: R20-R23 (4 rules)
- **Alt Text**: R24-R27 (4 rules)
- **Writing Contexts**: R28-R29, R28b (3 rules)
- **Common Mistakes**: R30-R37 (8 rules)
- **Common Substitutions**: R38 (1 rule)
- **QDoc Formatting**: R39-R41 (3 rules)
- **UI and Tools Documentation**: R42-R44 (3 rules)
- **Linking Style and Syntax**: R45-R51, R51b (8 rules)
- **Structured Content**: R52-R56 (5 rules)
- **Exceptions**: R57 (1 rule)
- **Page Templates**: R58-R59 (2 rules)
- **Module Review**: R60-R62 (3 rules)
- **Admonition and Markup**: R63-R64 (2 rules)

### Sources by Authority
- **Tier 1 Qt Official**: S1-S8 (highest precedence)
- **Tier 2 Supplementary**: S9
- **Tool Reference**: S10 (syntax only)

See "Sources and Further Reading" section for complete source details.

---

## API Documentation Requirements

For detailed requirements by documentation type, see the official style guides:

- **C++ APIs**: S3 (C++ Documentation Style) - https://wiki.qt.io/C%2B%2B_Documentation_Style
- **QML APIs**: S4 (QML Documentation Style) - https://wiki.qt.io/QML_Documentation_Style
- **Examples**: S6 (Writing Example Documentation) - https://wiki.qt.io/Writing_Example_Documentation_and_Tutorials

**Summary of key requirements:**

| Element | \brief | \since | \inmodule/\inqmlmodule |
|---------|--------|--------|------------------------|
| `\class`, `\qmltype` | **MANDATORY** | **MANDATORY** | **MANDATORY** |
| `\property`, `\qmlproperty` | **MANDATORY** | Required (C++) | — |
| `\fn`, `\qmlmethod` | Recommended | Required (C++) | — |
| `\example` | **MANDATORY** | — | — |

**Note**: "Required" means the official style guide says "must include". See R14-R19 for patterns.

---

## Core Principles

**Note**: Rules R1-R13 summarize guidelines from S1 (Qt Writing Guidelines) and S2
(QUIP 25). For full details, consult the authoritative sources directly.

### R1. Use Active Voice

Active voice over passive. See **S1, S2** for details.
- ❌ "Events will be ignored by the item" → ✅ "The item ignores events"

### R2. Be Clear and Concise

Simple, direct language. ≤20 words per sentence. See **S2** for details.
- ❌ "In order to enable" → ✅ "To enable"

**SCAN trigger:** Flag informal phrases (a lot of, kind of, sort of,
pretty much), filler words (indeed, actually, basically, essentially,
just-as-filler), and wordy constructions (causes X to occur → causes X,
a frequent requirement is to → you often need to).

---

### R3. Use Correct Terminology

**Rule**: Use Qt's standard terminology consistently. Don't invent new terms
or use incorrect class names.

**Verification**: Follow the generic **Verification Workflow** (see above).
For terminology questions, the authoritative source is **S7 (Qt Terms and
Concepts)**. The tables below are EXAMPLES, not exhaustive - always verify
against S7 for terms not listed.

**Qt Terminology Guidelines**:

| Concept | Correct Term | Incorrect Terms |
|---------|-------------|-----------------|
| User interface widget | widget | control, component |
| QML type | type | component, object, widget |
| Property value | property | attribute, field, member |
| Signal/slot mechanism | signal, slot | event, callback, handler |
| Item in QML scene graph | item | object, component, widget |
| Qt Quick Controls element | control | widget, component |
| Person writing code | developer | programmer |

**Generic UI Terminology** (for user-facing descriptions):

| Generic Term | Qt Class | Usage |
|--------------|----------|-------|
| button | QPushButton, Button (QML) | Use "button" in user docs |
| list view | QListView, ListView (QML) | Use "list view" in user docs |
| text field | QLineEdit, TextField (QML) | Use "text field" in user docs |
| dialog | QDialog, Dialog (QML) | Use "dialog" in user docs |
| toolbar | QToolBar | Use "toolbar" in user docs |
| menu bar | QMenuBar | Use "menu bar" in user docs |

**When to use which**:
- **API documentation**: Use exact class names (QListView, ListView)
- **User guides/tutorials**: Use generic terms (list view, text field)
- **Alt text**: Use generic terms, lowercase (button, dialog)
- **Code examples**: Use class names (QListView, QPushButton)

**Qt Version Numbers** (CRITICAL - commonly missed):

| Correct | Incorrect | Notes |
|---------|-----------|-------|
| Qt 5 | Qt5 | Space required before version number |
| Qt 6 | Qt6 | Space required before version number |
| Qt 5-based | Qt5-based | Space before version in compounds |
| Qt 6.5 | Qt6.5 | Space required |

**Qt Product and Module Names** (from S7 - https://wiki.qt.io/Qt_Terms_and_Concepts):

Always use official capitalization and spelling for Qt products and modules:

| Correct | Incorrect | Notes |
|---------|-----------|-------|
| Qt GUI | Qt Gui, Qt gui | Acronym must be all caps |
| Qt Core | Qt core | Module names are capitalized |
| Qt Network | Qt network | |
| Qt Qml | Qt QML (in module name) | Module is "Qt Qml", language is "QML" |
| Qt Quick | Qt quick, QtQuick (in prose) | Two words in prose |
| Qt Widgets | Qt widgets | |
| Qt Add-Ons | Qt Addon, Qt Addons, Qt Add-on Modules | Hyphenated, capitalized |
| Qt D-Bus | Qt DBus, Qt DBUS | Hyphenated |
| Qt SQL | Qt Sql, Qt sql | Acronym must be all caps |
| Qt SVG | Qt Svg, Qt svg | Acronym must be all caps |
| Qt NFC | Qt Nfc | Acronym must be all caps |
| Qt PDF | Qt Pdf | Acronym must be all caps |
| Qt XML | Qt Xml | Acronym must be all caps |
| Qt Creator | Qt creator, QtCreator | Two words, capitalized |
| Qt Design Studio | Qt design studio | Each word capitalized |
| QDoc | Qdoc, qdoc | CamelCase |

**Compound Words** (Qt documentation conventions):

| Correct | Incorrect | Notes |
|---------|-----------|-------|
| framerate | frame rate | Single word in technical contexts |
| runtime | run time, run-time | Single word as noun/adjective |
| filename | file name | Single word |
| namespace | name space | Single word |
| checkbox | check box | Single word |
| toolchain | tool chain | Single word |
| codebase | code base | Single word |
| standalone | stand-alone | Single word |

**Sources**: S2 (QUIP 25), S1 (Qt Writing Guidelines), S7 (Qt Terms and Concepts)

**IMPORTANT - Authoritative Source Verification**:

The tables above are NOT exhaustive. When reviewing terminology:

1. **Scan for Qt patterns**: `Qt[0-9]`, `Qt [A-Z]`, product names, module names
2. **Verify against S7**: Fetch https://wiki.qt.io/Qt_Terms_and_Concepts for authoritative definitions
3. **When in doubt, check source**: Do not assume a term is correct just because it's not in the tables above

**Common patterns to scan for**:
- `Qt[0-9]` → Should be `Qt [0-9]` (space required)
- `QtQuick` in prose → Should be `Qt Quick` (two words)
- `QtCreator` → Should be `Qt Creator` (two words)

---

### R4. Use Present Tense

Present tense for current behavior. See **S2** for details.
- ❌ "will return" → ✅ "returns"

**SCAN trigger:** Search for "will" + verb (will copy, will happen, will
make, will show, will throw). Flag unless conditional future ("if X, Y
will occur") or planned deprecation ("will be removed in Qt 7").

### R5. Use Imperative Mood for Instructions

Imperative for briefs/instructions, indicative for descriptions. See **S3, S4**.
- Imperative: "Returns the value." / "Call this function..."
- Indicative: "This property holds..."

### R6. Use "You" for User Instructions

Address users with "you" in guides/tutorials. See **S1, S2** for details.
- ❌ "One can configure..." → ✅ "You can configure..."
- API docs: Use imperative/indicative patterns (R14-R19) instead

### R7. Avoid Jargon and Idioms

Write for international audience. No idioms. See **S1, S2** for details.

**SCAN trigger:** Flag common English idioms (double-edged sword, behind
the scenes, under the hood, out of the box, on the fly, from scratch).
Replace with literal equivalents. Also: "like" (introducing examples) →
"such as".

### R8. Be Consistent

Same word for same concept throughout. See **S2** for details.

### R9. Use Parallel Structure

Same grammatical structure in lists. See **S2** for details.
- ❌ "Set... / Calling... / You should..." → ✅ "Set... / Call... / Verify..."

---

### R10. Avoid Ambiguous Pronouns

Clear pronoun references. When in doubt, repeat the noun. See **S2** for details.
- ❌ "It is updated first" → ✅ "The item is updated first"

---

## Grammar Rules

### R11. Commas (Serial/Oxford Comma)

Always use serial comma in lists. See **S1, S2** for details.
- ✅ "name, value, and type" / ❌ "name, value and type"

### R12. Capitalization

**Rule**: Capitalization depends on the command type.

| Command | Case | Example |
|---------|------|---------|
| `\title` | **Title Case** | `\title Getting Started with Qt Quick` |
| `\section1`/`\section2` | **Sentence case** | `\section1 Building your first application` |
| Table `\header` | **Sentence case** | `\li Default value` |

**Note**: Qt Writing Guidelines (S1) specifies sentence case for `\section` titles but
does not address `\title`. Analysis of Qt codebase shows ~80% of `\title` commands use
Title Case. This is the de facto standard.

**Title Case rules** (for `\title`):
- Capitalize first/last words, nouns, verbs, adjectives, adverbs
- Lowercase articles (a, an, the), short prepositions (to, in, of, for), conjunctions (and, but, or)

**Sentence case rules** (for `\section`):
- Capitalize first word and proper nouns only

**Full reference**: `references/title-capitalization.md`

**Sources**: S1, S2, S9, Qt codebase analysis

### R13. Numbers

Spell out 1-9, numerals for 10+. See **S2** for details.
- Always numerals for: dimensions, versions, code values

---

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

## API Documentation Requirements

### R14. \brief Descriptions

**Rule**: \brief requirements vary by documentation type.

**MANDATORY \brief** (QDoc warns if empty):
- `\class` - C++ classes
- `\qmltype` - QML types
- `\property` - C++ properties
- `\qmlproperty` - QML properties
- `\example` - Example pages
- `\page` - Overview pages

**RECOMMENDED \brief** (not mandatory, but follow patterns if provided):
- `\fn` - Functions and methods
- `\qmlmethod` - QML methods
- `\qmlsignal` - QML signals
- `\enum` - Enumerations

**Exception**: Internal classes documented with `\internal` do not require `\brief` (see R16).

**All briefs that are provided must end with a period.** (See R15)

**Sources**: S3 (C++ Documentation Style), S4 (QML Documentation Style), S6 (Writing Example Documentation)
**Syntax Reference**: S10 (QDoc Manual - `\brief` command)

---

### R15. All Briefs End with Period

**Rule**: Mandatory punctuation for all \brief descriptions.

**Sources**: S3 (C++ Documentation Style), S4 (QML Documentation Style), S6 (Writing Example Documentation)

---

### R16. Class Documentation

**Location**: Document C++ classes in `.cpp` implementation files (not headers).

**Required commands**:
- `\class` - Initiates class documentation
- `\brief` - Mandatory summary (must end with period)
- `\inmodule` - Associates class to Qt module
- `\since` - Version when class was added (verify via git - see below)

**`\since` Verification (MANDATORY):**

Do NOT copy `\since` from existing docs. Verify using git:
```bash
git log --oneline --follow --diff-filter=A -- "file.cpp" | tail -1
git tag --contains <commit> --sort=version:refname | head -3
```
First tag = correct `\since` version. See skill-qdoc/references/context-commands.md.

**Brief patterns**:
```
✅ "The [Class] class provides..."
✅ "The [Class] class is the base class of..."
✅ "The [Class] class manipulates..."
```

**Example**:
```cpp
/*!
    \class QWidget
    \brief The QWidget class is the base class of all user interface objects.
    \inmodule QtWidgets
    \since 4.0
*/
```

**Exception - Internal Classes**:

For internal/private classes, use minimal documentation with only:
- `\class` - Initiates class documentation
- `\inmodule` - Associates class to Qt module
- `\internal` - Marks class as internal

**Do NOT include** for internal classes:
- `\brief` - Not required
- `\since` - Not required
- Detailed descriptions - Not required
- `\sa` references - Not required

**Internal class example**:
```cpp
/*!
    \class QWidgetPrivate
    \inmodule QtWidgets
    \internal
*/
```

**Content Source**: S3 (C++ Documentation Style)
**Syntax Reference**: S10 (QDoc Manual - `\class`, `\brief`, `\inmodule`, `\since`, `\internal` commands)

---

### R17. Function Documentation

**Rule**: When providing function briefs, start with action verbs indicating the operation performed.

**Note**: \brief is **recommended but not mandatory** for functions. However, `\since` IS mandatory for C++ functions per S3.

**Common verb patterns**:
- **Constructors**: "Constructs..."
- **Destructors**: "Destroys..."
- **Accessors**: "Returns..."
- **Mutators**: "Sets..."
- **Actions**: "Updates...", "Changes...", "Called..."

**If brief is provided, must end with period.**

**Required elements for functions**:
- `\a` for parameters
- `\c` for return values and code references
- `\since` for version (MANDATORY per S3)

**Example**:
```cpp
/*!
    \fn void QWidget::show()
    \brief Shows the widget and its child widgets.

    This function sets the widget's visibility to visible and makes it
    appear on screen. The widget receives a show event before becoming
    visible.

    \sa hide(), setVisible(), isVisible()
*/
```

**Content Source**: S3 (C++ Documentation Style), S4 (QML Documentation Style)
**Syntax Reference**: S10 (QDoc Manual - `\fn` command)

---

### R18. Property Documentation

**Rule**: Property briefs follow specific opening phrases.

**Opening phrases**:
- "This property holds..."
- "This property describes..."
- "This property represents..."
- "Returns `\c true` when..."
- "Sets the..."

**Must end with period.**

**C++ Example**:
```cpp
/*!
    \property QWidget::enabled
    \brief This property holds whether the widget is enabled.
*/
```

**QML Example**:
```qml
/*!
    \qmlproperty bool Item::enabled
    \brief This property holds whether the item is enabled.
*/
```

**Content Source**: S3 (C++ Documentation Style), S4 (QML Documentation Style)
**Syntax Reference**: S10 (QDoc Manual - `\property`, `\qmlproperty` commands)

---

### R19. Signal Documentation

**Rule**: When providing signal briefs, describe emission conditions.

**Note**: \brief is **recommended but not mandatory** for signals.

**Opening phrases**:
- "This signal is emitted when..."
- "Emitted when..."
- "Triggered when..."

**If brief is provided, must end with period.**

**Example**:
```cpp
/*!
    \fn void QWidget::windowTitleChanged(const QString &title)
    \brief This signal is emitted when the window title changes.
*/
```

**Content Source**: S3 (C++ Documentation Style), S4 (QML Documentation Style)
**Syntax Reference**: S10 (QDoc Manual - `\fn` command for signals)

---

## Example Documentation Requirements

### R20. 11 Mandatory Elements

Every Qt example MUST include documentation with these elements:

1. **Title** - Use `\title` command
2. **Example page** - Use `\example` command with directory
3. **Brief description** - Use `\brief` (must end with period)
4. **Category** - Use `\examplecategory` macro
5. **Visual element** - Include image (especially for GUI examples)
6. **Overview section** - Describe objective and Qt technologies used
7. **Running instructions** - Explain where to find and how to run
8. **Platform notes** - Identify compatible platforms and limitations
9. **Main content** - Cover themes and expected behavior
10. **References** - Link to related documentation
11. **Licenses** - Include appropriate license notices

**Content Source**: S6 (Writing Example Documentation and Tutorials)
**Syntax Reference**: S10 (QDoc Manual - `\title`, `\example`, `\examplecategory` commands)

---

### R21. Example Code Quality

**Requirements**:
- **Zero warnings** from C++ compiler and qmllint
- Follow Qt coding conventions
- Use clang-format for C++ and qmlformat for QML
- Support both qmake and CMake build systems
- Self-contained (no external dependencies)

**Sources**: S5 (Qt Examples Guidelines)

---

### R22. Example Screenshots

**Requirements**:
- High-DPI screenshots (minimum 440x320 resolution)
- Icons minimum 64x64 resolution
- Include alt text following QUIP 21

**Sources**: S5 (Qt Examples Guidelines)

---

### R23. Example Titles

**Rule**: Avoid repeating "Example" in titles. Avoid repeating module names.

```
❌ "Qt Quick Example: Button Example"
✅ "Button"
```

**For tutorials**: Use action-oriented titles with progressive verbs:
```
✅ "Drawing Graphics"
✅ "Integrating QML and C++"
✅ "Handling User Input"
```

**Sources**: S5 (Qt Examples Guidelines), S6 (Writing Example Documentation)

---

## Alt Text for Images

**Note**: This section provides essential alt text principles for general Qt documentation work. For comprehensive guidance including detailed formatting specifications, patterns for different image types, QDoc configuration, and extensive examples, use the **skill-alttext skill**.

**When to use the specialized skill-alttext skill:**
- Adding alt text to multiple images
- Need specific patterns for screenshots, controls, wireframes, or technical diagrams
- Configuring QDoc's `reportmissingalttextforimages` flag
- Need detailed formatting specifications (indentation, line length)
- Doing comprehensive alt text review or accessibility work

---

### R24. Alt Text Format (Essential Rule)

**Rule**: Start with capital letter, no period at end.

**Example**:
```
\image filename.png
       {Window with toolbar containing dark mode toggle and buttons}
```

**Content Source**: S8 (Qt Alt Text Style), QUIP 21
**Syntax Reference**: S10 (QDoc Manual - `\image` command)

---

### R25. Alt Text Priority Order

Follow this priority when writing alt text:

1. **Option 1** (Recommended): Include visible text/labels/icons from the image
2. **Option 2**: Context-focused (purpose/behavior/state)
3. **Option 3**: Generic visual description

**Sources**: S8 (Qt Alt Text Style)

---

### R26. Alt Text Terminology

**Rule**: Use generic UI terms (lowercase), not Qt class names.

**Examples**:
```
✅ "button", "check box", "dialog", "toolbar" (generic, lowercase)
❌ "Button", "CheckBox", "Dialog", "ToolBar" (Qt class names)
```

**Exception**: Asset documentation where names match file patterns.

**Sources**: S8 (Qt Alt Text Style)

---

### R27. Alt Text Style

**Rule**: Use descriptive nominal phrases. Avoid passive voice constructions.

**Note**: The Qt Alt Text Style states "active voice" but demonstrates descriptive phrases. Follow the demonstrated patterns, not the stated rule.

**Examples (from Qt Alt Text Style)**:
```
✅ {Window with toolbar containing dark mode toggle and buttons}
✅ {Dialog for entering contact details such as name and address}
✅ {Switch control in on and off states}
✅ {Button in various interaction states}
```

**These are descriptive phrases, not active voice constructions. This is the correct pattern to follow.**

**Sources**: S8 (Qt Alt Text Style)

---

## Writing for Different Contexts

### R28. API Documentation (QDoc Comments)

**Style**:
- Present tense
- Imperative mood for briefs ("Returns...", "Sets...")
- Indicative mood for descriptions ("This property holds...")
- Start function briefs with action verbs
- All briefs end with period
- Be precise and technical
- Document in .cpp files (C++)

**Example**:
```cpp
/*!
    \fn void QWidget::show()
    \brief Shows the widget and its child widgets.

    This function sets the widget's visibility to visible and makes it
    appear on screen. The widget receives a show event before becoming
    visible.

    \sa hide(), setVisible(), isVisible()
*/
```

**Content Sources**: S3 (C++ Documentation Style), S4 (QML Documentation Style)
**Syntax Reference**: S10 (QDoc Manual)

---

### R28b. Tools Documentation (Qt Creator, Qt Design Studio)

**Style**:
- Present tense
- "You" acceptable for procedural instructions
- UI elements in bold: **File** > **New Project**
- Keyboard shortcuts: `Ctrl+B` (`Cmd+B` on macOS)
- Task-oriented organization
- Menu paths with `>` separator

**Example**:
```
To configure build settings:

1. Go to **Projects** > **Build Settings**.
2. Select the kit you want to configure.
3. In the **Build directory** field, enter the path.

You can also press Ctrl+B to build the project.
```

**Sources**: S1 (Qt Writing Guidelines), Qt Creator documentation

---

### R29. User Guides and Tutorials

**Style**:
- Present tense
- Use "you" for instructions
- Explain concepts clearly
- Less technical jargon
- Action-oriented section titles

**Example**:
```markdown
To create a button:

1. Add a Button type to your QML file.
2. Set the text property to define the button label.
3. Connect the clicked signal to handle user interaction.

You can customize the button's appearance using style properties.
```

**Sources**: S1 (Qt Writing Guidelines), S6 (Writing Example Documentation)

---

## Common Mistakes (Quick Reference)

See rules R1-R38 for details:
- R30: Passive voice → Use active
- R31: Future tense → Use present
- R32: Wordy phrases → Be concise
- R33: Ambiguous "this" → Be specific
- R34: Inconsistent terms → Pick one
- R35: Missing \brief on class/type/property → Add \brief (see R14 for scope)
- R36: No period in brief → Add period
- R37: "Neutral voice" → Use "imperative/indicative mood"

---

## R38. Common Substitutions

Avoid Latin terms, formal/verbose phrases, and hedging words. See **S1, S2, S9**
for complete lists.

**Key substitutions** (most commonly flagged):
| Avoid | Use |
|-------|-----|
| e.g., i.e., etc., via | for example, that is, (be specific), through |
| in order to | to |
| utilize | use |
| simply, obviously, clearly | (omit) |
| since/as (causation) | because |

**Full substitution lists**: Consult S2 (QUIP 25) and S9 (Microsoft Style Guide).

---

## UI and Tools Documentation

### R42. UI Element Markup

**Rule**: Mark UI elements distinctly from surrounding text.

**In tools documentation** (Qt Creator, Qt Design Studio):
- Use bold for UI elements: **File**, **Edit**, **Run**
- Use bold for buttons: **OK**, **Cancel**, **Apply**

**In QDoc**:
- Use `\uicontrol{element}` command for UI text

**Examples**:
```
✅ Go to **File** > **New Project**.
✅ Select the **Run** button.
✅ In QDoc: Select \uicontrol{File} > \uicontrol{New}.
```

**Sources**: S1 (Qt Writing Guidelines), Qt Creator documentation

---

### R43. Keyboard Shortcut Formatting

**Rule**: Format keyboard shortcuts consistently.

**Patterns**:
- Single modifier: `Ctrl+B`, `Alt+F`
- Multiple modifiers: `Ctrl+Shift+F`
- Sequential keys: `Ctrl+K, Ctrl+D`
- Platform variants: `Ctrl+O` (`Cmd+O` on macOS)

**In tables**: Show Windows/Linux and macOS columns separately.

**Examples**:
```
✅ Press Ctrl+S to save.
✅ Press Ctrl+K, Ctrl+D to format the document.
✅ Press Ctrl+B (Cmd+B on macOS) to build.
```

**Sources**: Qt Creator documentation, Qt Design Studio documentation

---

### R44. Menu Path Formatting

**Rule**: Write menu navigation paths with bold elements separated by `>`.

**Examples**:
```
✅ Go to **File** > **New Project**.
✅ Select **Edit** > **Preferences** > **Kits**.
✅ In the **Tools** > **Options** dialog, select **Environment**.
```

**Sources**: Qt Creator documentation, Qt Design Studio documentation

---

## Linking Style and Syntax

**Reference**: For syntax details, examples, and diagnostics, see **skill-qdoc** (`references/link-resolution.md`). This section provides quick style rules.

---

### R45. Basic Link Syntax

**Rule**: Use correct `\l` form. Prefer no space before brace (R39).

| Form | Use |
|------|-----|
| `\l{target}` | Basic link |
| `\l{target}{text}` | Custom display text |
| `\l[QML]{target}` | Force QML genus |

**Details**: skill-qdoc/references/link-resolution.md "Link Syntax"

---

### R46. Link vs Code (`\l` vs `\c`)

**Rule**: `\l{}` for public APIs; `\c{}` for internal/undocumented types.

- Public, documented → `\l{QWidget::show()}`
- Private header (`_p.h`) → `\c{QWidgetPrivate::init()}`
- External URL → `\l{}` with `\externalpage`

**Details**: skill-qdoc/references/link-resolution.md "Decision Tree"

---

### R47. Section Links in Type Docs

**Rule**: Use `TypeName#Section Title`, NOT `page.html#anchor`.

- Correct: `\l{QColor#The HSV Color Model}`
- Wrong: `\l{qcolor.html#the-hsv-color-model}`

**Details**: skill-qdoc/references/link-resolution.md "Section Links"

---

### R48. External Page Links

**Rule**: Link target must match `\externalpage` `\title` exactly (including macro expansion).

**Details**: skill-qdoc/references/link-resolution.md "External Page Links"

---

### R49. QML Cross-Module Links

**Rule**: Use `::` separator; braces `{}` when target contains dots.

- `\l{QtQuick.Controls::ToolTip::delay}`

**Details**: skill-qdoc/references/link-resolution.md "QML Cross-Module Links"

---

### R50. QML Value Type Case

**Rule**: Value types use camelCase; object types use PascalCase.

- Value type: `\l{geoCoordinate::latitude}`
- Object type: `\l{ListView::delegate}`

**Details**: skill-qdoc/references/link-resolution.md "QML Value Type Links"

---

### R51. QML Abstraction: Use Generic Types, Not C++ Types

**Rule**: QML documentation describes the QML interface, not the underlying C++ implementation. Use generic QML/JavaScript types in `\qmlmethod` and `\qmlproperty` signatures rather than exposing C++ type names.

**Rationale**: QML provides an abstraction layer over C++. QML developers should not need to know about C++ implementation details. Using generic types maintains this abstraction and makes documentation accessible to developers who may not know C++.

**Return type guidelines for `\qmlmethod`**:

| C++ Return Type | QML Return Type | Notes |
|-----------------|-----------------|-------|
| `QObject *` | `object` | Generic JS object type |
| `QVariant` | `var` | Generic variant type |
| `QString` | `string` | |
| `int`, `qint32` | `int` | |
| `double`, `qreal` | `real` | |
| `bool` | `bool` | |
| `QList<...>` | `list` | Generic list type |
| Specific QML type | Use the QML type name | e.g., `Item`, `Rectangle` |

**Examples**:
```qdoc
✅ Correct (generic):
\qmlmethod object NodeInstantiator::objectAt(int index)
\qmlmethod object ListModel::get(int index)
\qmlmethod var Context2D::getImageData(real x, real y, real w, real h)

❌ Incorrect (exposes C++ types):
\qmlmethod QtObject NodeInstantiator::objectAt(int index)
\qmlmethod QtQml::QtObject NodeInstantiator::objectAt(int index)
\qmlmethod QObject* NodeInstantiator::objectAt(int index)
```

**Prevalence in Qt codebase**:
- `object` (lowercase, generic): 40+ instances in qtdeclarative
- `QtObject` (specific QML type): 2 instances
- `QtQml::QtObject` (module-qualified): 1 instance (anomaly)

**When to use specific types**: Use specific QML type names when the method returns a known QML type:
```qdoc
✅ \qmlmethod Item Repeater::itemAt(int index)
✅ \qmlmethod Object3D Repeater3D::objectAt(int index)
```

**Sources**: Qt Documentation Team practice, QML Documentation Style (S4)

---

### R51b. QML-to-C++ Cross-API Linking

**Rule**: QML documentation should link to QML targets, not C++ equivalents. Cross-API links are appropriate only in specific contexts.

**Rationale**: QML developers expect to stay within the QML documentation context. The `\nativetype` command establishes a structural relationship but does not mean all links should go to C++.

**When cross-API linking IS appropriate**:

| Context | Example |
|---------|---------|
| Module overview | "TextToSpeech wraps QTextToSpeech for QML" |
| Architecture explanation | "See QTextToSpeech for threading details" |
| C++ integration guidance | "To customize, subclass QTextToSpeechEngine" |
| Shared enum documentation | `\qmlenumeratorsfrom QTextToSpeech::State` |
| Enum value references | `\sa QTextToSpeech::State` (enum, not method) |

**When cross-API linking is NOT appropriate**:

| Context | Reason |
|---------|--------|
| `\sa` within QML method docs | Reader expects QML context |
| QML method brief/description | Should be self-contained |
| Workaround for missing QML index | Masks root cause |
| Default behavior | QML docs should stand alone |

**Example - WRONG**:
```qdoc
\qmlmethod void TextToSpeech::say(string text)

Speaks the given \a text.

\sa QTextToSpeech::pause(), QTextToSpeech::resume()  // ❌ Links to C++
```

**Example - CORRECT**:
```qdoc
\qmlmethod void TextToSpeech::say(string text)

Speaks the given \a text.

\sa pause(), resume()  // ✓ Links to QML methods on same type
```

**If QML target isn't indexed**: Investigate and fix the `\qmlmethod`/`\qmlproperty` command (often missing return type) rather than redirecting to C++.

**Sources**: Qt Documentation Team practice, QML abstraction principle

---

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

## Fix Verification (MANDATORY)

**CRITICAL: Every language fix must be verified against ALL rules before presenting.**

### The Problem

Language fixes often address one issue while introducing another:

| Fix addresses... | But introduces... |
|------------------|-------------------|
| R1 (passive voice) | R2 (wordiness) |
| R2 (wordiness) | R1 (passive voice) |
| R38 (Latin term) | R10 (missing article) |
| Grammar error | R40 (line too long) |

### Verification Process

**Before presenting ANY language suggestion:**

1. **Draft the fix**
2. **Re-read the ENTIRE corrected sentence** - not just the changed part
3. **Check against ALL language rules** (see checklist below)
4. **If fix introduces new issues, revise** - iterate until fully compliant
5. **Only present the final, fully-compliant suggestion**

### Quick Verification Checklist

For every drafted fix, verify:

```
- [ ] R1: Active voice? (no "is/are/was/were [verb]ed", "can be [verb]ed")
- [ ] R2: Concise? (no "in order to", "some of the", "provide a way to")
- [ ] R4: Present tense? (no "will return", "will be")
- [ ] R10: Correct articles? ("the", "a", "an" where needed)
- [ ] R38: No Latin? (no "via", "e.g.", "i.e.", "etc.")
- [ ] R40: ≤80 columns?
- [ ] Grammar correct? (agreement, possessives, parallelism)
- [ ] Clear and readable?
```

### Domain Terms Exception

**Before flagging terminology, verify it's not a valid technical term:**

- **C++ terms**: "in-place" (construction), "move semantics", "RAII", "emplace"
- **Qt terms**: Check Qt Terms and Concepts (S7)
- **QML terms**: Check QML Documentation Style (S4)

**Example**: "inplace" or "in-place" is valid C++ terminology. Do NOT flag as spelling error.

### Example - Iterative Verification

```
Original: "The data can be also assigned directly via the property"

Draft 1: "The data can also be assigned directly via the property"
  ✗ R1: Still passive ("can be assigned")
  ✗ R38: Latin term ("via")
  → REVISE

Draft 2: "You can also assign the data directly via the property"
  ✓ R1: Active ("You can assign")
  ✗ R38: Latin term ("via")
  → REVISE

Draft 3: "You can also assign the data directly through the property"
  ✓ R1: Active
  ✓ R38: No Latin
  ✓ R2: Concise
  ✓ R40: 58 chars
  → PRESENT
```

---

## Sources

**Full source details with URLs:** See `references/sources.md`

| ID | Source | Scope |
|----|--------|-------|
| S1 | Qt Writing Guidelines | Primary coordination |
| S2 | QUIP 25 | Language, grammar, style |
| S3 | C++ Documentation Style | C++ API patterns |
| S4 | QML Documentation Style | QML API patterns |
| S5 | Qt Examples Guidelines | Example code quality |
| S6 | Writing Example Documentation | 11 mandatory elements |
| S7 | Qt Terms and Concepts | Official terminology |
| S8 | Qt Alt Text Style | Alt text (skill-alttext) |
| S9 | Microsoft Style Guide | Supplementary only |
| S10 | QDoc Manual | Command syntax (HOW) |

**Changelog:** See `CHANGELOG.md`
