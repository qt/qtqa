---
name: skill-language-style
description: Language, grammar, and style guidelines for Qt documentation including active voice, terminology, QUIP 25 standards, and proper API documentation patterns. Covers both WHAT to write (style/content) and HOW to write it (QDoc syntax).
version: 3.1
---

# Qt Language and Style Guidelines

**Version**: 3.0
**Purpose**: Reference for language, grammar, and style standards when writing or reviewing Qt documentation
**Scope**: Applies to all Qt documentation (QDoc comments, user guides, tutorials, API docs, examples)

---

## Overview

This document provides language and style guidelines for Qt documentation, consolidating rules from Qt Writing Guidelines, QUIP 25 (Qt Documentation Style), C++/QML Documentation Style guides, and Microsoft Style Guide. Use this as a reference when writing or reviewing documentation text.

**Two-Dimensional Framework**: Qt documentation standards operate in two dimensions:
1. **WHAT to write** - Content, style, patterns, language rules
2. **HOW to write it** - QDoc command syntax and formatting

---

## Documentation Standards Framework

### Content & Style Authority (WHAT to write)

**Tier 1 - Qt Official Standards (HIGHEST AUTHORITY):**

1. **Qt Writing Guidelines** - Primary coordination document
   - Coordinates all Qt documentation standards
   - Establishes overall policies and references

2. **QUIP 25** - Language and style authority
   - Language, grammar, word choice, formatting
   - States: "This QUIP is primary; Microsoft Writing Style Guide is optional"

3. **C++ Documentation Style** - C++ API content patterns
   - Class, function, property, signal documentation patterns
   - Required QDoc commands for C++ APIs

4. **QML Documentation Style** - QML API content patterns
   - QML type, property, signal, method documentation patterns
   - Required QDoc commands for QML APIs

5. **Qt Examples Guidelines** - Example code standards
   - Code quality requirements (zero warnings)
   - Build system requirements
   - Screenshot specifications

6. **Writing Example Documentation** - Example documentation patterns
   - 11 mandatory documentation elements
   - Tutorial structure and style

**Tier 2 - Supplementary Reference:**

7. **Microsoft Style Guide** - Used when Qt sources don't specify
   - Grammar and language reference
   - Applied only when Qt standards are silent

---

### Tool & Syntax Reference (HOW to write it)

**QDoc Manual** - Command syntax and technical specifications
- QDoc command syntax (`\class`, `\fn`, `\property`, etc.)
- Parameter specifications and formatting rules
- Linking and cross-reference syntax
- Not a style/content authority - works in conjunction with content sources

**Relationship**: Content sources (above) tell you WHAT patterns to use. QDoc Manual tells you HOW to express them using QDoc commands.

**Example of how they work together**:
- C++ Doc Style says: "Function briefs start with action verbs like 'Returns...'"
- QDoc Manual says: "Use `\fn` command with syntax `\fn return-type Class::function(params)`"

---

### When to Consult Which Source

**Style questions** ("Should I use active voice?")
→ S1 (Qt Writing Guidelines) → S2 (QUIP 25) → S9 (Microsoft Style Guide)

**Content pattern questions** ("What pattern for property briefs?")
→ S3/S4 (C++/QML Documentation Style)

**Syntax questions** ("How do I format `\qmlproperty`?")
→ S10 (QDoc Manual)

**Combined questions** ("How do I document a function?")
→ S3 (C++ Doc Style) for pattern + S10 (QDoc Manual) for syntax

---

## Rule and Source Enumeration

This skill contains **58 enumerated rules (R1-R57, R51b)** and **10 enumerated sources (S1-S10)** for easy reference.

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

### R1. Use Active Voice

**Rule**: Prefer active voice over passive voice. Active voice is more direct and easier to understand.

**Example**:
```
❌ Passive: Events will be ignored by the item when disabled.
✅ Active:  The item ignores events when disabled.
```

**Exception**: Passive voice acceptable when actor is unknown or irrelevant.

**Sources**: S2 (QUIP 25), S1 (Qt Writing Guidelines), S9 (Microsoft Style Guide - "Verbs")

---

### R2. Be Clear and Concise

**Rule**: Use simple, direct language. Aim for ≤20 words per sentence.

**Example**:
```
❌ Verbose: In order to enable the feature, you need to set the property.
✅ Concise: Set the property to enable the feature.
```

**Avoid**: "In order to" → "To", "It is possible to" → "Can", "Make use of" → "Use"

**Sources**: S2 (QUIP 25), S9 (Microsoft Style Guide - "Conciseness")

---

### R3. Use Correct Terminology

**Rule**: Use Qt's standard terminology consistently. Don't invent new terms or use incorrect class names.

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

---

### R4. Use Present Tense

**Rule**: Write in present tense. Documentation describes current behavior.

**Example**:
```
❌ Future:  The function will return \c true if the item is enabled.
✅ Present: The function returns \c true if the item is enabled.
```

**Exception**: Future tense for sequential actions ("The window will appear...").

**Sources**: S2 (QUIP 25), S1 (Qt Writing Guidelines), S9 (Microsoft Style Guide - "Verbs")

---

### R5. Use Imperative Mood for Instructions

**Rule**: Use imperative mood (commands) for function briefs and instructions. Use indicative mood for descriptions.

**Imperative**: "Returns the value." (function brief), "Call this function..." (instruction)

**Indicative**: "This property holds..." (description), "The widget receives..." (explanation)

**Sources**: S9 (Microsoft Style Guide - "Verbs"), S3 (C++ Documentation Style), S4 (QML Documentation Style)

---

### R6. Use "You" for User Instructions

**Rule**: Address the user directly with "you" when giving instructions in guides and tutorials. API documentation patterns typically don't require "you" because they use imperative and indicative constructions.

**User guides/tutorials**:
```
❌ Impersonal: One can configure the settings in the dialog.
❌ Third-person: The developer can configure the settings.
✅ Direct:      You can configure the settings in the dialog.
```

**API documentation** (patterns don't require "you"):
```
✅ "Returns the current value."                  (imperative - brief)
✅ "This property holds the enabled state."      (indicative - description)
✅ "Call this function to update the view."      (imperative - instruction)
```

**Note**: QUIP 25 says "use second person ('you')" generally. The convention of not using "you" in API docs follows from the standard patterns (R17-R19), not an explicit prohibition.

**Sources**: S2 (QUIP 25), S1 (Qt Writing Guidelines), S9 (Microsoft Style Guide - "Person")

---

### R7. Avoid Jargon and Idioms

**Rule**: Write for international audience. Avoid idioms and culturally-specific references.

**Example**: "This feature is easy to use" not "a piece of cake to use"

**Avoid**: Latin abbreviations (use "that is" not "i.e.", "for example" not "e.g.")

**Sources**: S2 (QUIP 25), S1 (Qt Writing Guidelines), S9 (Microsoft Style Guide - "Global communications")

---

### R8. Be Consistent

**Rule**: Use the same word for the same concept throughout documentation.

**Examples**:
```
❌ Inconsistent: "Set the property... Configure the option... Adjust the setting..."
✅ Consistent:   "Set the property... Set the option... Set the setting..."

❌ Inconsistent: "The application starts... The program launches... The app begins..."
✅ Consistent:   "The application starts... The application starts... The application starts..."
```

**Create a term list** for your module:
- Choose one term per concept
- Document your choices
- Apply consistently

**Sources**: S9 (Microsoft Style Guide - "Consistency")

---

### R9. Use Parallel Structure

**Rule**: In lists or series, use the same grammatical structure for each item.

**Examples**:
```
❌ Not parallel:
- Set the property
- Calling the function
- You should verify the result

✅ Parallel:
- Set the property
- Call the function
- Verify the result
```

**For lists with descriptions**:
```
✅ Parallel:
- **Set the property**: Configures the initial state
- **Call the function**: Triggers the update
- **Verify the result**: Checks the outcome
```

**Sources**: S9 (Microsoft Style Guide - "Lists")

---

### R10. Avoid Ambiguous Pronouns

**Rule**: Make pronoun references clear. When in doubt, repeat the noun.

**Examples**:
```
❌ Ambiguous: The item and the parent both have properties. It is updated first.
✅ Clear:      The item and the parent both have properties. The item is updated first.

❌ Ambiguous: Call show() after creating the widget. This ensures visibility.
✅ Clear:      Call show() after creating the widget. This call ensures visibility.
```

**Sources**: S2 (QUIP 25), S9 (Microsoft Style Guide - "Pronouns")

---

## Grammar Rules

### R11. Commas (Serial/Oxford Comma)

**Rule**: Always use the serial comma (Oxford comma) in lists.

**Examples**:
```
✅ "The function takes three parameters: name, value, and type."
✅ "Set the property, call the method, and verify the result."
❌ "Set the property, call the method and verify the result."
```

**Sources**: S2 (QUIP 25), S1 (Qt Writing Guidelines)

---

### R12. Capitalization

**Section titles**: Use sentence-case for section titles (capitalize only the first word and proper nouns).

**Examples**:
```
✅ "Getting started with Qt Quick"
✅ "Using the property system"
❌ "Getting Started With Qt Quick" (title case)
❌ "Using The Property System" (title case)
```

**Capitalize**:
- Proper nouns: Qt, QML, JavaScript, OpenGL
- Class names: QWidget, QObject, ListView
- First word of sentences
- First word after colons in titles

**Don't capitalize**:
- Generic terms: widget, object, property, signal
- Function names (unless starting a sentence): setProperty(), show()
- Technical terms: boolean, integer, string

**Example**:
```
✅ "The QWidget class provides the base functionality for UI widgets."
✅ "The setProperty() function sets the property value."
```

**Sources**: S1 (Qt Writing Guidelines), S2 (QUIP 25), S9 (Microsoft Style Guide)

---

### R13. Numbers

**Rule from S2 (QUIP 25)** (clear and unambiguous):

**Spell out one through nine** in prose/narrative text:
```
✅ "You have three options"
✅ "Consider these five approaches"
```

**Use numerals for 10 and above**:
```
✅ "15 items"
✅ "100 pixels"
```

**ALWAYS use numerals for** (even if below 10):
- **Parameters and return values**: "takes 3 parameters", "returns 2 values"
- **Dimensions**: "5 milliseconds", "3 x 4 grid", "2.5 meters"
- **Versions**: "Qt 6.5"
- **Code values**: "3 items in the list"

**Numbers starting sentences**: Spell out
```
✅ "Ten items are available."
```

**Sources**: S2 (QUIP 25)

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

**Context**:
- Documentation comments in .cpp files follow the surrounding code's column width
- Qt code uses 80-column limit
- Applies to QDoc comments and .qdoc files

**Exception**: Single-line content within `{}` should stay on one line when possible for easier searching and error detection.

**Sources**: Qt Coding Style (https://wiki.qt.io/Qt_Coding_Style), QDoc Style Guidelines Wiki

---

### R41. \sa Targets Must Match Exact Page Titles

**Rule**: Each `\sa` (see also) target must resolve to an actual documentation page title. The target text must match the page title exactly.

**Validation Method**:
1. Identify the expected page URL from the target
2. Fetch the page (e.g., `https://doc.qt.io/qt-6/quick3d-examples.html`)
3. Verify the page exists (no 404)
4. Confirm the target matches the actual page title exactly

**Common Mistakes**:
```
❌ \sa {Qt Quick 3D Examples}           (page title is different)
✅ \sa {Qt Quick 3D Examples and Tutorials}

❌ \sa {Qt Examples}                    (page doesn't exist)
✅ \sa {All Qt Examples}
```

**Why This Matters**: Unlike `\l{}` which may auto-resolve or show warnings, `\sa` targets that don't match exact page titles produce broken links in the generated documentation with no build-time warning.

**LESSON LEARNED**: Missing \sa validation caused undetected broken links in production. Always verify \sa targets against actual page titles.

**Sources**: QDoc Manual, Qt Documentation Team practice

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
- `\since` - Version when class was added

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

## R38. Quick Reference: Common Substitutions

### Latin Terms (Always Avoid)

Per R7, avoid Latin terms for international readability.

| Instead of... | Use... | Source |
|---------------|--------|--------|
| e.g. | for example, such as, like | S9 (MS Style Guide) |
| i.e. | that is | S9 (MS Style Guide) |
| etc. | (be specific, or use "such as" + examples) | S9 (MS Style Guide) |
| via | through, using, with, by | S2 (QUIP 25), S9 |
| per | according to, for each, a | Plain language |
| versus / vs. | compared to, or, against | Plain language |
| re: | about, regarding | Plain language |
| ergo | so, therefore | Plain language |
| vis-à-vis | compared with, about | Plain language |

### Formal/Verbose Phrases

| Instead of... | Use... | Source |
|---------------|--------|--------|
| In order to | To | S2 (QUIP 25), S9 |
| It is possible to | You can / Can | S2 (QUIP 25) |
| There are X that | X do... | S2 (QUIP 25) |
| Make use of | Use | S9 (MS Style Guide) |
| At this point in time | Now | Plain language |
| In the event that | If | Plain language |
| With regard to | About | Plain language |
| Is able to | Can | Plain language |
| In addition to | Also / Besides | S9 (MS Style Guide) |
| Prior to | Before | Plain language |
| Subsequent to | After | Plain language |
| In lieu of | Instead of | Plain language |
| Due to the fact that | Because | Plain language |
| For the purpose of | To, For | Plain language |
| In the process of | (omit, or use -ing verb) | Plain language |
| On a daily basis | Daily | Plain language |

### Formal Verbs

| Instead of... | Use... | Source |
|---------------|--------|--------|
| utilize | use | S9 (MS Style Guide) |
| leverage | use, take advantage of | S9 (MS Style Guide) |
| commence | begin, start | Plain language |
| terminate | end, stop | Plain language |
| implement | carry out, do, put in place | Plain language |
| facilitate | help, make easier | Plain language |
| endeavor | try | Plain language |
| ascertain | find out, learn | Plain language |
| indicate | show, say | Plain language |
| obtain | get | Plain language |
| provide | give | Plain language |
| require | need | Plain language |
| sufficient | enough | Plain language |
| additional | more | Plain language |
| approximately | about | Plain language |
| currently | now | Plain language |

### Hedging Words (Avoid or Use Sparingly)

Per S2 (QUIP 25), avoid words that undermine confidence or assume reader knowledge.

| Avoid... | Reason | Source |
|----------|--------|--------|
| simply, just | Implies task is trivial; condescending | S2 (QUIP 25) |
| obviously, clearly | Assumes reader knowledge | S2 (QUIP 25) |
| easily | May not be easy for reader | S2 (QUIP 25) |
| please | Use only for inconvenient requests | S2 (QUIP 25) |
| note that, notice that | Often unnecessary; just state the fact | Plain language |
| it should be noted | Wordy; just state the fact | Plain language |

### Terminology

| Instead of... | Use... | Source |
|---------------|--------|--------|
| programmer | developer | S2 (QUIP 25) |
| neutral voice | imperative mood / indicative mood | S2 (QUIP 25) |
| since / as (causation) | because | S2 (QUIP 25), S9 |

### Causal Connectors

When expressing cause/effect relationships:

| Instead of... | Use... | Source |
|---------------|--------|--------|
| hence | so, as a result | Plain language |
| therefore | so, as a result | Plain language |
| thus | so, this way | Plain language |
| consequently | so, as a result | Plain language |
| accordingly | so | Plain language |

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

**Note**: For detailed link resolution diagnostics and debugging, see **skill-qdoc** (`references/link-resolution.md`). This section covers basic style rules for writing links.

---

### R45. Basic Link Syntax

**Rule**: Use the correct `\l` command form for each linking situation.

**Syntax forms**:
```qdoc
\l{target}                    Basic link
\l{target}{display text}      Custom display text
\l[QML]{target}               Force QML genus
\l[CPP]{target}               Force C++ genus
\l[CPP QtCore]{target}        Force C++ in specific module
```

**No space before brace** (per R39):
```
✅ \l{QWidget}
❌ \l {QWidget}
```

**Examples**:
```qdoc
\l{QWidget::setGeometry()}
\l{ListView#Reusing Items}
\l{Getting Started with Qt Quick}{getting started guide}
```

**Sources**: S10 (QDoc Manual), skill-qdoc (link-resolution.md)

---

### R46. Link vs Code Formatting (`\l` vs `\c`)

**Rule**: Use `\l{}` for documented/public APIs; use `\c{}` for undocumented or internal types.

**Decision matrix**:
| Target Status | Command | Example |
|---------------|---------|---------|
| Documented, public | `\l{}` | `\l{QWidget::show()}` |
| Undocumented, internal | `\c{}` | `\c{QWidgetPrivate::init()}` |
| Private header (`_p.h`) | `\c{}` | `\c{QPlatformWindow::invalidateSurface()}` |
| External URL | `\l{}` with `\externalpage` | `\l{CMake Documentation}` |

**Diagnostic**: If you see "Can't link to 'X'" warning for a type in a private header, use `\c{}`.

**Sources**: skill-qdoc (link-resolution.md), QDoc Manual

---

### R47. Section Links Within Type Documentation

**Rule**: Use `TypeName#Section Title` syntax to link to sections within C++ class or QML type documentation. Do NOT use `page.html#anchor` syntax.

**Correct syntax**:
```qdoc
\l{QColor#The HSV Color Model}
\l{ListView#Reusing Items}
\l{QRhi#Frame captures and performance profiling}
\l{QDialog#Modal Dialogs}{modal dialog}
```

**Incorrect syntax** (will fail):
```qdoc
❌ \l{qcolor.html#the-hsv-color-model}
❌ \l{qml-qtquick-listview.html#reusing-items}
```

**Why**: The `page.html#anchor` syntax only works for explicit `\page` pages, not auto-generated pages from `\class` or `\qmltype` commands.

**Sources**: skill-qdoc (link-resolution.md)

---

### R48. External Page Links

**Rule**: Use `\externalpage` to create named targets for external URLs. The link target must match the `\title` exactly (including after macro expansion).

**Definition**:
```qdoc
/*!
    \externalpage https://cmake.org/cmake/help/latest/
    \title CMake Documentation
*/
```

**Usage**: `\l{CMake Documentation}` → links to cmake.org

**Common mistakes**:
```qdoc
❌ \l{CMake}                    (partial title)
❌ \l{cmake documentation}      (wrong case)
✅ \l{CMake Documentation}      (exact match)
```

**With macros**: If title uses `\QOI`, link must too: `\l{\QOI official releases}`

**Sources**: skill-qdoc (link-resolution.md), QDoc Manual

---

### R49. QML Cross-Module Links

**Rule**: Use `::` separator for linking to QML types and properties from other modules. Use braces `{}` when target contains dots.

**Syntax**:
```qdoc
{Module.Submodule::Type}              QML type
{Module.Submodule::Type::property}    QML property
{Module.Submodule::Type::method()}    QML method
```

**Examples**:
```qdoc
\l{QtQuick.Controls::ToolTip}
\l{QtQuick.Controls::ToolTip::delay}
\sa QWidget::toolTip, {QtQuick.Controls::ToolTip::delay}
```

**Key points**:
- Use `::` between module and type, and between type and member
- Module names use dots internally (`QtQuick.Controls`) but `::` for scoping
- Braces `{}` required when target contains `.` characters
- In `\sa`, braces alone work (no `\l` prefix needed)

**Sources**: skill-qdoc (link-resolution.md)

---

### R50. QML Value Type Case Sensitivity

**Rule**: QML value types (from `Q_GADGET` with `QML_VALUE_TYPE`) use **camelCase** (lowercase first letter). QML object types use **PascalCase**.

**Value types (camelCase)**:
| C++ Class | QML Value Type | Correct Link |
|-----------|----------------|--------------|
| `WebEngineCertificateError` | `webEngineCertificateError` | `\l{webEngineCertificateError::defer()}` |
| `GeoCoordinate` | `geoCoordinate` | `\l{geoCoordinate::latitude}` |

**Object types (PascalCase)**:
```qdoc
\l{WebEngineView::url}
\l{ListView::delegate}
```

**Diagnostic**: If "Can't link to 'PascalCaseType::member'" warning appears for a QML type, search for `\qmlvaluetype` to check if it's a value type requiring camelCase.

**Sources**: skill-qdoc (link-resolution.md)

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

## Sources and Further Reading

### Content & Style Authority (WHAT to write)

#### Tier 1 - Qt Official Standards (HIGHEST AUTHORITY)

**S1. Qt Writing Guidelines** (PRIMARY - HIGHEST PRECEDENCE)
   - URL: https://wiki.qt.io/Qt_Writing_Guidelines
   - Coordinates all Qt documentation standards
   - Establishes overall policies

**S2. QUIP 25 - Qt Documentation Writing Style** (AUTHORITATIVE)
   - URL: https://code.qt.io/cgit/meta/quips.git/plain/quip-0025-Documentation-Writing-Style.rst
   - Language, grammar, style, formatting standards
   - States: "This QUIP is primary; Microsoft Writing Style Guide is optional"

**S3. C++ Documentation Style**
   - URL: https://wiki.qt.io/C%2B%2B_Documentation_Style
   - C++ API documentation patterns and requirements
   - Class, function, property, signal patterns

**S4. QML Documentation Style**
   - URL: https://wiki.qt.io/QML_Documentation_Style
   - QML API documentation patterns and requirements
   - QML type, property, signal, method patterns

**S5. Qt Examples Guidelines**
   - URL: https://wiki.qt.io/Qt_Examples_Guidelines
   - Example code quality and structure requirements
   - Zero warnings, screenshot specifications

**S6. Writing Example Documentation and Tutorials**
   - URL: https://wiki.qt.io/Writing_Example_Documentation_and_Tutorials
   - 11 mandatory elements for example documentation
   - Tutorial structure and style

**S7. Qt Terms and Concepts**
   - URL: https://wiki.qt.io/Qt_Terms_and_Concepts
   - Official Qt terminology definitions
   - Product naming conventions

**S8. Qt Alt Text Style** (Local authoritative guide)
   - Path: ~/.claude/skills/skill-alttext/SKILL.md
   - Alt text patterns, formatting, terminology
   - Priority order for alt text content

#### Tier 2 - Supplementary Reference

**S9. Microsoft Style Guide**
   - URL: https://learn.microsoft.com/en-us/style-guide/welcome/
   - Used when Qt sources don't specify
   - Specific sections:
     - Person: https://learn.microsoft.com/en-us/style-guide/grammar/person
     - Verbs: https://learn.microsoft.com/en-us/style-guide/grammar/verbs

---

### Tool & Syntax Reference (HOW to write it)

**S10. QDoc Manual** (Command syntax and technical specifications)
- URL: https://doc.qt.io/qt-6/qdoc-index.html
- Local: qttools/src/qdoc/doc/qdoc-index.qdoc
- **Purpose**: QDoc command syntax, parameter specs, formatting rules
- **Not a style authority**: Works in conjunction with content sources above
- **Referenced for**:
  - Command syntax (`\class`, `\fn`, `\property`, `\brief`, etc.)
  - Linking and cross-reference syntax
  - Image and media command formatting
  - QDoc configuration options

**Relationship**: Content sources tell you WHAT patterns to use. QDoc Manual tells you HOW to express them using QDoc commands.

**Example**:
- C++ Doc Style: "Function briefs start with action verbs like 'Returns...'"
- QDoc Manual: "Use `\fn` command with syntax `\fn return-type Class::function(params)`"

---

## Version History

- **3.2** (2026-02-24): QML-to-C++ cross-API linking
  - Added R51b: QML-to-C++ Cross-API Linking guidelines
  - Enums: C++ enum links in QML docs ARE appropriate
  - Methods/Properties: QML docs should link to QML, not C++ equivalents
  - If QML target not indexed, fix topic command rather than redirect to C++
  - Updated rule count (now 58 rules total)

- **3.1** (2026-02-20): R39 whitespace rule clarification
  - Revised R39: "No Space" → "Prefer No Space" (style preference, not requirement)
  - Added parser evidence: `docparser.cpp:2377` shows both forms parse identically
  - Added rationale: compactness helps meet 80-column limit
  - Added Qt codebase usage stats: 71% no-space, 29% space
  - Removed "Incorrect" labels - both forms are valid
  - Changed enforcement from "RECOMMENDED" to "STYLE PREFERENCE"
  - Updated skill-qdoc with whitespace normalization details

- **3.0** (2026-02-18): QML abstraction principle
  - Added R51: QML Abstraction - Use Generic Types, Not C++ Types
  - Key guidance: Use `object` (not `QtObject` or `QtQml::QtObject`) for QObject* returns
  - QML documentation describes QML interface, not C++ implementation
  - Added return type mapping table (C++ to QML types)
  - Updated rule count (now 51 rules total)

- **2.9** (2026-02-17): Added linking style and syntax rules
  - Added R45: Basic Link Syntax (`\l{}`, `\l[]{}`, `\l{}{text}`)
  - Added R46: Link vs Code Formatting (`\l` vs `\c` decision)
  - Added R47: Section Links Within Type Documentation (TypeName#Section)
  - Added R48: External Page Links (`\externalpage` with `\title` matching)
  - Added R49: QML Cross-Module Links (`::` separator, braces for dots)
  - Added R50: QML Value Type Case Sensitivity (camelCase for value types)
  - Added "Linking Style and Syntax" section
  - Cross-referenced skill-qdoc for detailed diagnostics
  - Updated rule count (now 50 rules total)

- **2.8** (2026-02-17): Precision for API documentation requirements
  - Corrected R14: \brief is MANDATORY only for classes, types, properties, examples; RECOMMENDED for functions, signals, enums
  - Simplified API Documentation Requirements section with links to official style guides
  - Updated R17: Clarified \brief is recommended (not mandatory) for functions; \since IS mandatory per S3
  - Updated R19: Clarified \brief is recommended (not mandatory) for signals
  - Updated R35: Narrowed scope to classes/types/properties
  - Updated R39: Clarified as RECOMMENDED (not strictly enforced), preferred for compact text
  - Updated R40: Clarified as CI-ENFORCED
  - Added R28b: Tools documentation style (Qt Creator, Qt Design Studio)
  - Added R42: UI element markup
  - Added R43: Keyboard shortcut formatting
  - Added R44: Menu path formatting
  - Added tools-specific terminology to R3
  - Updated rule count (now 44 rules total)

- **2.7** (2026-02-17): Qt product and module terminology
  - Added "Qt Product and Module Names" table to R3 from S7 (Qt Terms and Concepts)
  - Added "Compound Words" table with Qt documentation conventions
  - Key additions: Qt GUI (not Gui), Qt Add-Ons (hyphenated), acronyms all caps
  - Compound words: framerate, runtime, filename, namespace, checkbox, toolchain

- **2.6** (2026-02-05): Expanded R38 word substitutions
  - Added Latin terms section with "via", "per", "versus", "ergo", "vis-à-vis"
  - Added formal verbs section (utilize, leverage, commence, terminate, etc.)
  - Added hedging words section (simply, obviously, easily, please)
  - Added causal connectors section (hence, therefore, thus, consequently)
  - Organized into categorized tables with source citations
  - Cross-referenced with S2 (QUIP 25), S9 (Microsoft Style Guide), plain language principles

- **2.5** (2025-12-16): \sa target validation
  - Added R41: \sa targets must match exact page titles
  - Updated rule count (now 41 rules total)
  - Added lesson learned about \sa validation causing undetected broken links

- **2.4** (2025-12-06): QDoc command formatting
  - Added R39: No space between QDoc commands and curly braces
  - Added R40: 80-column line length for documentation
  - Added "QDoc Command Formatting" section
  - Updated rule enumeration (now 40 rules total)
  - Clarified QDoc Style Guidelines wiki precedence over QDoc Manual examples

- **2.3** (2025-11-28): Enumeration system
  - Added comprehensive R# (rule) and S# (source) numbering throughout
  - Updated all 38 rules with R1-R38 references
  - Updated all 10 sources with S1-S10 references
  - Added "Rule and Source Enumeration" section for quick reference
  - Corrected rule count documentation (38 rules total)

- **2.2** (2025-11-28): Skill integration
  - Added cross-reference to skill-alttext skill for specialized alt text work
  - Added guidance on when to use the specialized skill-alttext skill
  - Clarified that Alt Text section provides essential principles while skill-alttext provides deep-dive guidance

- **2.1** (2025-11-28): Structure refinement
  - Restructured source hierarchy into two dimensions (WHAT vs HOW)
  - Clarified QDoc Manual as tool/syntax reference, not style authority
  - Added "Documentation Standards Framework" section
  - Added "When to Consult Which Source" guidance
  - Enhanced source descriptions with clear purpose statements
  - Added syntax references alongside content sources in rules

- **2.0** (2025-11-28): Major update
  - Fixed "neutral voice" terminology (now uses "imperative/indicative mood")
  - Clarified numbers rule from QUIP 25 (spell 1-9, numerals for code values)
  - Removed unsubstantiated "omit articles" rule
  - Fixed alt text "active voice" guidance (now uses "descriptive phrases")
  - Added API documentation requirements (\brief mandatory, patterns)
  - Added example documentation requirements (11 elements, zero warnings)
  - Updated source precedence hierarchy (Qt Writing Guidelines primary)
  - Added proper source URLs (code.qt.io for QUIPs)
  - Added C++/QML Documentation Style guidance
  - Added sentence length guideline (≤20 words)
  - Added "developer" not "programmer" terminology

- **1.0** (2025-11-28): Initial version consolidating language and style guidelines

---

## Important Notes

### Authority Framework

**Content & Style Authority** (WHAT to write):
When sources conflict, follow this hierarchy:
1. Qt Writing Guidelines
2. QUIP 25
3. C++/QML Documentation Style
4. Example Documentation guides
5. Microsoft Style Guide (supplementary only)

**Tool & Syntax Reference** (HOW to write it):
- QDoc Manual is the authoritative reference for QDoc command syntax
- Use QDoc Manual for technical syntax questions
- Use content sources for style and pattern questions

### Critical Requirements

**\brief is mandatory**: QDoc generates warnings if \brief is missing or empty. All briefs must end with a period.

**Terminology correction**: The term "neutral voice" does not appear in any Qt or Microsoft documentation. Use "imperative mood" (for commands) and "indicative mood" (for descriptions) instead.

**Numbers are clear**: QUIP 25 provides unambiguous guidance: spell out 1-9 in prose, but always use numerals for parameters, dimensions, versions, and code values.

**Alt text style**: Despite stating "active voice", Qt Alt Text Style demonstrates descriptive nominal phrases. Follow the demonstrated patterns.

### How Content and Syntax Work Together

Every documentation task requires both dimensions:

**Example: Documenting a function**
1. Content source (C++ Doc Style): Tells you to start with action verb like "Returns..."
2. Syntax source (QDoc Manual): Tells you to use `\fn` command with proper parameters

**Example: Adding an image**
1. Content source (Qt Alt Text Style): Tells you to use descriptive phrase, capitalize, no period
2. Syntax source (QDoc Manual): Tells you syntax is `\image filename.png` with alt text on next line

**Specialized skills**: For complex or extensive work in specific areas, specialized skills provide deeper guidance:
- **skill-alttext skill**: Deep dive on alt text (patterns, formatting, QDoc config)
- This skill provides the foundation; specialized skills add depth for focused work

Always consult both dimensions for complete guidance.
