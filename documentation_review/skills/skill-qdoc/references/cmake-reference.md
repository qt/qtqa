# CMake Reference Pages

Documentation for Qt's CMake API. Each command, variable, and
property is its own `\page` (not a topic-command-derived node)
with conventions specific to the CMake API category.

## Three categories

| Category | Page filename | Group | Since macro |
|----------|---------------|-------|-------------|
| CMake command | `qt-{command}.html` | `cmake-commands-{module}` | `\cmakecommandsince` |
| CMake variable | `cmake-variable-{name}.html` | `cmake-variables-{module}` | `\cmakevariablesince` |
| CMake property | `cmake-target-property-{name}.html` (target) or `cmake-source-file-property-{name}.html` (source) | `cmake-target-properties-{module}` (or `cmake-properties-{module}`) | `\cmakepropertysince` |

The module suffix on group names matches the Qt module that
ships the command (`cmake-commands-qtcore`,
`cmake-variables-qttest`, etc.). Confirm sibling pages in the
target module before assigning a group.

---

## CMake command

### Syntax

```qdoc
// Copyright (C) {year} The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GFDL-1.3-no-invariants-only

/*!
\page qt-{command-with-hyphens}.html
\ingroup cmake-commands-{module}

\title qt_{command_with_underscores}
\keyword qt6_{command_with_underscores}

\summary {One-line — what the command does.}

\include cmake-find-package-{module}.qdocinc

\cmakecommandsince {6.x}
{\preliminarycmakecommand if API is unstable}

\section1 Synopsis

\badcode
qt_{command}(<TARGET> [<ARGS>])
\endcode

\versionlessCMakeCommandsNote qt6_{command}()

\section1 Description

{Behavior, when to use, prerequisites.}

\section1 Arguments

\c ARGNAME

{Argument description.}

\section1 Examples

{Example block(s) using \badcode or \snippet.}
*/
```

### Mandatory commands

| Command | Purpose | Notes |
|---------|---------|-------|
| `\page` | Filename + `.html` | Hyphens in filename, dots→hyphens canonicalization |
| `\ingroup cmake-commands-{module}` | Lists on the module's CMake commands page | Verify the group name from siblings |
| `\title qt_{command}` | Page heading | Underscored form |
| `\keyword qt6_{command}` | Search keyword for legacy alias | Always include for the qt6_ form |
| `\summary {…}` | Brief replacement for CMake pages | Period at end, sentence case |
| `\cmakecommandsince {version}` | Version introduced | Macro expands to "This command was introduced in Qt X.Y." |

### Common companions

| Command | Purpose |
|---------|---------|
| `\preliminarycmakecommand` | API not yet stable |
| `\cmakecommandandroidonly` | Android-only command |
| `\warning` | Deprecation or platform restriction |
| `\note` | Caveats on usage |
| `\versionlessCMakeCommandsNote qt6_{command}()` | Notice that qt_ and qt6_ aliases coexist |

### Why `\summary` not `\brief`

CMake reference pages use `\summary {…}` (with braces) instead
of `\brief`. The summary appears in the CMake API listings;
`\brief` would not.

### Naming rules

- `\page` filename: hyphens, lowercase
  (`qt-add-win-app-sdk.html`)
- `\title`: underscores, lowercase (`qt_add_win_app_sdk`)
- `\keyword`: underscores, lowercase, qt6_ prefix
  (`qt6_add_win_app_sdk`)

### Real example (qtcore)

```qdoc
/*!
\page qt-add-win-app-sdk.html
\ingroup cmake-commands-qtcore

\title qt_add_win_app_sdk
\keyword qt6_add_win_app_sdk

\summary {Adds the Windows App SDK library to the application.}

\include cmake-find-package-core.qdocinc

\cmakecommandsince 6.9
\preliminarycmakecommand

\section1 Synopsis
\badcode
qt_add_win_app_sdk(<TARGET>)
\endcode

\versionlessCMakeCommandsNote qt6_add_win_app_sdk()

\section1 Description
...
*/
```

---

## CMake variable

### Syntax

```qdoc
/*!
\page cmake-variable-{name-with-hyphens}.html
\ingroup cmake-variables-{module}

\title {VARIABLE_NAME}
\target cmake-variable-{VARIABLE_NAME}

\cmakevariablesince {6.x}
{\preliminarycmakevariable if unstable}

\summary {One-line — what the variable controls.}

{Body — when to set, valid values, default, interaction
with other variables.}
*/
```

### Mandatory commands

| Command | Purpose |
|---------|---------|
| `\page cmake-variable-…` | Filename pattern |
| `\ingroup cmake-variables-{module}` | Group membership |
| `\title {VARIABLE_NAME}` | Heading — uppercase variable name as written |
| `\target cmake-variable-{VARIABLE_NAME}` | Stable link target — preserves variable case |
| `\summary {…}` | Brief |
| `\cmakevariablesince {version}` | Version introduced |

### Real example

```qdoc
/*!
\page cmake-variable-qt-skip-default-testcase-dirs.html
\ingroup cmake-variables-qttest

\title QT_SKIP_DEFAULT_TESTCASE_DIRS
\target cmake-variable-QT_SKIP_DEFAULT_TESTCASE_DIRS

\cmakevariablesince 6.9
\preliminarycmakevariable

\summary {Disables the test case directory definitions for the Qt Test targets.}

Controls the default value of the
\l {cmake-target-property-QT_SKIP_DEFAULT_TESTCASE_DIRS}{QT_SKIP_DEFAULT_TESTCASE_DIRS}
property...
*/
```

---

## CMake target property

Target properties attach to CMake targets via `set_target_properties()`.

### Syntax

```qdoc
/*!
\page cmake-target-property-{name-with-hyphens}.html
\ingroup cmake-properties-{module}
\ingroup cmake-target-properties-{module}
{\ingroup cmake-{platform}-build-properties — if platform-specific}

\title {PROPERTY_NAME}
\target cmake-target-property-{PROPERTY_NAME}

\summary {One-line — what the property controls.}

\cmakepropertysince {6.x}

{Body — which targets, valid values, default value,
interaction with other properties.}
*/
```

### Common second-group conventions

CMake target-property pages typically declare two `\ingroup`
lines: `cmake-properties-{module}` (the broad property listing)
plus `cmake-target-properties-{module}` (target-specific subset).
Platform-specific properties add a third group like
`cmake-android-build-properties`.

### Real example

```qdoc
/*!
\page cmake-target-property-qt-android-extra-libs.html
\ingroup cmake-properties-qtcore
\ingroup cmake-target-properties-qtcore
\ingroup cmake-android-build-properties

\title QT_ANDROID_EXTRA_LIBS
\target cmake-target-property-QT_ANDROID_EXTRA_LIBS

\summary {Extra libraries to deploy with the target.}

\cmakepropertysince 6.0

...
*/
```

---

## CMake variable/property listing pages

Each module that ships CMake variables or properties typically
maintains a `\group` page that lists them:

```qdoc
/*!
\group cmake-variables-{module}
\title CMake Variables in Qt6 {ModuleName}
\brief Lists CMake variables defined in Qt6::{Module}.

The following CMake variables are defined when Qt6::{Module}
is loaded, for instance with

\badcode
find_package(Qt6 REQUIRED COMPONENTS {Module})
\endcode

\sa{CMake Variable Reference}
*/
```

The `\group` and the `\page` reference docs live in the same
file or directory; pages join via `\ingroup`.

---

## Macros expanded by CMake commands

| Macro | Expands to (approximate) | Where defined |
|-------|--------------------------|---------------|
| `\cmakecommandsince` | "This command was introduced in Qt X.Y." | qtbase global qdocconf |
| `\cmakevariablesince` | "This variable was introduced in Qt X.Y." | qtbase global qdocconf |
| `\cmakepropertysince` | "This property was introduced in Qt X.Y." | qtbase global qdocconf |
| `\preliminarycmakecommand` | Preliminary-API admonition | qtbase global qdocconf |
| `\preliminarycmakevariable` | Preliminary-API admonition | qtbase global qdocconf |
| `\cmakecommandandroidonly` | "This command is only available on Android." | qtbase global qdocconf |
| `\versionlessCMakeCommandsNote` | Note about qt_ ↔ qt6_ aliasing | qtbase global qdocconf |

Definitions live in `qtbase/doc/global/macros.qdocconf` (and
related global qdocconf files). Always confirm sibling pages
before introducing a new macro.

---

## Quick assembly checklist

1. Pick the category: command / variable / target-property /
   source-file-property.
2. Select the page filename pattern from the table at the top.
3. Add `\ingroup cmake-{kind}-{module}` — verify the group
   name in a sibling page in the same module before guessing.
4. Add the title and `\target` per the category's convention
   (titles preserve uppercase variable/property names; commands
   use lowercase qt_ form).
5. Add `\summary {…}` (NOT `\brief`).
6. Add the `\cmake{kind}since` macro.
7. Add the optional `\preliminary{kind}` macro if the API is
   unstable.
8. For commands: add `\section1 Synopsis`, `\section1 Description`,
   `\section1 Arguments`, `\section1 Examples`.
9. For variables/properties: a single body paragraph plus
   "valid values" and "default value" sentences is typical.

For exact sibling lookup, search the module's
`src/{module}/doc/src/cmake/` directory (or
`doc/src/cmake/` at the module root).
