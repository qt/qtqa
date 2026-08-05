<!-- Loaded on demand by skill-language-style/SKILL.md router. Part of skill-language-style. -->

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


