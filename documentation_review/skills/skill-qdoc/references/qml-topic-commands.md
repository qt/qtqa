# QML Topic Commands Reference

QDoc topic commands that document QML APIs. Companion to
`namespaces-headers-macros.md` (C++ topic commands) and
`module-declaration.md` (`\module` / `\qmlmodule`).

## `\qmltype` — QML Type

Documents a QML type. Generates a reference page similar to
`\class`.

### Syntax

```qdoc
/*!
    \qmltype TypeName
    \nativetype QNativeBackingClass
    \inqmlmodule ModuleName
    \inherits BaseQmlType
    \since {version}
    \brief {Imperative — Specifies/Provides/Plays/...}.
    \ingroup {group-name}

    {Body paragraph(s) — what the type does, when to use it,
     how it relates to other types.}

    \sa {Related types}
*/
```

### Mandatory companions

| Command | Purpose | Notes |
|---------|---------|-------|
| `\inqmlmodule` | QML module assignment | Modern QDoc may infer from build config; prefer explicit |
| `\brief` | Summary | R5 imperative verb (Specifies, Provides, Represents...) |

### Common companions

| Command | Purpose | Example |
|---------|---------|---------|
| `\nativetype` | Backing C++ class | `\nativetype QQuickAnimatedImage` |
| `\inherits` | QML base type | `\inherits Image` |
| `\since` | Version introduced | `\since 6.5` |
| `\ingroup` | Group membership | `\ingroup qtquick-visual` |
| `\instantiates` | (Legacy synonym for `\nativetype`) | Older docs only |
| `\preliminary` | API not yet stable | Unstable APIs |

### Brief pattern (R5)

Imperative verb, third-person:
- "Plays animations stored as a series of images."
- "Specifies the position and direction of a particle emitter."
- "Provides a reusable button component."

### Output filename

`qml-{module}-{type}.html` (lowercase). Module name in the
filename uses logical-module convention (`qtquick`, not
`QtQuick`). See `skill-qdoc-output`.

### Real example (QtQuick AnimatedImage)

```qdoc
/*!
    \qmltype AnimatedImage
    \nativetype QQuickAnimatedImage
    \inqmlmodule QtQuick
    \inherits Image
    \brief Plays animations stored as a series of images.
    \ingroup qtquick-visual

    The AnimatedImage type extends the features of the
    \l Image type, providing a way to play animations stored
    as images containing a series of frames...

    \sa BorderImage, Image
*/
```

---

## `\qmlproperty` — QML Property

Documents a QML property. The fully-qualified form is required.

### Syntax

```qdoc
/*!
    \qmlproperty type ModuleName::TypeName::propertyName

    {Brief follows R18 — "This property holds...",
     "This property describes...", "This property represents..."}

    {Body — units, range, behavior on change, default value}.

    \sa {related properties or types}
*/
```

### Variants

```qdoc
\qmlproperty url QtQuick::AnimatedImage::source
\qmlproperty list<voice> QtTextToSpeech::TextToSpeech::availableVoices
\qmlproperty real Item::x          // when in same module as type
```

### Brief pattern (R18)

Opens with one of:
- "This property holds..."
- "This property describes..."
- "This property represents..."
- "Returns `\c true` when..."
- "Sets the..."

### Default value

State explicitly: `The default value is \c {value}.`

### Inline `\brief`

`\qmlproperty` does not require `\brief` as a separate command;
the first paragraph functions as the brief. Some docs include an
explicit `\brief` for clarity — both styles exist.

---

## `\qmlmethod` — QML Method

Documents a QML method. **Return type is mandatory** (see
`node-system.md`: missing return type drops the method from the
index).

### Syntax

```qdoc
/*!
    \qmlmethod returnType ModuleName::TypeName::methodName(params)

    {Third-person indicative — Returns/Sets/Creates/...}

    {Parameter descriptions with \a paramname.}

    {Return value description.}

    \sa {related methods}
*/
```

### Examples

```qdoc
\qmlmethod void TextToSpeech::say(string text)
\qmlmethod list<voice> TextToSpeech::availableVoices()
\qmlmethod bool Item::contains(point point)
```

### Brief pattern (R17)

Action verbs:
- Constructors: not applicable in QML (use `\qmlsignal` Component.completed)
- Accessors: "Returns..."
- Mutators: "Sets..."
- Actions: "Updates...", "Triggers...", "Reloads..."

---

## `\qmlsignal` — QML Signal

Documents a QML signal.

### Syntax

```qdoc
/*!
    \qmlsignal ModuleName::TypeName::signalName(params)

    {Brief follows R19 — "This signal is emitted when...",
     "Emitted when...", "Triggered when..."}

    {Parameter descriptions with \a paramname.}

    \sa {related signals or methods}
*/
```

### Brief pattern (R19)

Open with:
- "This signal is emitted when..."
- "Emitted when..."
- "Triggered when..."

---

## `\qmlattachedproperty` — Attached Property

Documents a property attached to types via the parent type's
attached object.

### Syntax

```qdoc
/*!
    \qmlattachedproperty type ModuleName::AttachingType::propertyName

    {Brief — "This attached property holds..."}

    {Body — when attachment activates, default value, scope}.
*/
```

### Real example

```qdoc
/*!
    \qmlattachedproperty bool QtQuick::Keys::enabled

    This property holds whether key handling is enabled.

    The default value is \c true.
*/
```

The attaching type is the type that defines the attached
mechanism (`Keys`, `Layout`, `KeyNavigation`, `Accessible`).

---

## `\qmlattachedsignal` — Attached Signal

Same shape as `\qmlsignal`, but the signal is attached to
arbitrary parent objects.

### Syntax

```qdoc
/*!
    \qmlattachedsignal ModuleName::AttachingType::signalName(params)

    {Brief — "This attached signal is emitted when..."}

    {Parameter descriptions with \a paramname.}
*/
```

---

## `\qmlvaluetype` — QML Value Type

Documents a QML value type (formerly called "basic type"):
types like `color`, `font`, `vector3d`, `rect`, `size`. Value
types have value semantics — assignment copies, not references.

### Syntax

```qdoc
/*!
    \qmlvaluetype typename
    \inqmlmodule ModuleName
    \ingroup qmlvaluetypes
    \since {version}
    \brief {Imperative — Represents/Specifies/...}.

    {Body paragraph(s) describing semantics, valid range,
     literal/construction syntax, and assignment behavior.}

    \sa {related value types}
*/
```

### Mandatory companions

| Command | Purpose |
|---------|---------|
| `\inqmlmodule` | QML module assignment |
| `\brief` | Summary (R5 imperative) |

### Common companions

| Command | Purpose |
|---------|---------|
| `\ingroup qmlvaluetypes` | Listed on QML value types page |
| `\since` | Version introduced |
| `\nativetype` | Backing C++ value type (e.g., `QColor`) |

### Naming convention

Value type names are **lowercase** (`color`, `font`, `vector3d`),
unlike `\qmltype` names which are PascalCase (`Image`,
`Rectangle`).

### Output filename

`qml-{type}.html` (no module segment for value types — see
`skill-qdoc-output`).

---

## \qmlenum

Documents a QML enumeration type. Introduced in Qt 6.10.

### Syntax

```qdoc
/*!
    \qmlenum Module::Type::EnumName
    \since 6.10
    \brief Specifies the ... .

    \value Value1
           Description of Value1.
    \value Value2
           Description of Value2.
*/
```

### Argument format

`Module::ParentType::EnumName` — the QML module, parent QML
type, and enum name. The module prefix is optional if
`\inqmlmodule` is set on the parent type.

### Mandatory companions

| Command | Purpose |
|---------|---------|
| `\brief` | Summary (R5 imperative) |
| `\value` | One per enumerator |

### Brief pattern (R5)

Imperative verb:
- "Specifies the color channel in the RGB colorspace."
- "Describes the current state of the media player."

### Output

Renders as an "Enumeration Documentation" section on the
parent QML type's page (no separate HTML file).

### Inheriting from C++ enums

Use `\qmlenumeratorsfrom` to replicate `\value` entries from
a documented C++ `\enum` instead of writing them manually:

```qdoc
/*!
    \qmlenum QtMultimedia::Camera::Error
    \qmlenumeratorsfrom QCamera::Error
    \brief Describes the current error state of the camera.
*/
```

By default, each enumerator is prefixed with the parent type
name (e.g., `Camera.NoError`). Override the prefix with an
optional argument:

```qdoc
    \qmlenumeratorsfrom [Errors] QCamera::Error
    //! Outputs: Errors.NoError, Errors.CameraError
```

`\qmlenumeratorsfrom` also works inside `\qmlproperty` topics
with an enumeration type. Available since Qt 6.8.

**Note:** The C++ enum must be documented in the same project.
QDoc cannot access enum docs from external dependencies.

---

## Quick assembly checklist

For ANY QML topic-command stub:

1. Pick the topic command from the list above.
2. Add `\inqmlmodule` (or fully-qualified parent type for
   property/method/signal forms).
3. Add `\brief` matching the rule for the type:
   - `\qmltype`, `\qmlvaluetype`: R5 (imperative)
   - `\qmlproperty`: R18 (This property holds...)
   - `\qmlmethod`: R17 (Returns/Sets/...)
   - `\qmlsignal`, `\qmlattachedsignal`: R19 (This signal is
     emitted when...)
4. Add `\since` if the version is known (else mark TODO).
5. For QML enums: use `\qmlenum` with `\value` entries, or
   use `\qmlenumeratorsfrom` to inherit from a C++ `\enum`.
6. Add common companions per the table above.
7. Body: 2-4 sentences for types; one paragraph + units/default
   for properties; parameter list for methods/signals.
8. Close with `\sa` linking related items.

For exact filename, see `skill-qdoc-output`. For brief patterns,
see `skill-language-style` rules R5, R14-R19. For QML cross-
module link conventions, see `skill-language-style` R49-R51.
