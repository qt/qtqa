<!-- Loaded on demand by skill-language-style/SKILL.md router. Part of skill-language-style. -->

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


