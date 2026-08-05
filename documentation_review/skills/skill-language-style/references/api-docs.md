<!-- Loaded on demand by skill-language-style/SKILL.md router. Part of skill-language-style. -->

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


