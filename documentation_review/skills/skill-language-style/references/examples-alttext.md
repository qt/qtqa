<!-- Loaded on demand by skill-language-style/SKILL.md router. Part of skill-language-style. -->

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


