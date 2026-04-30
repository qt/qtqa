# Stub Assembly Reference

Cross-reference index for generating compliant QDoc stubs. For
each documentation type this lists: the topic command, mandatory
companions, brief style (rule reference), filename pattern, and
the source skill that holds the full pattern.

This is an index. Always read the linked source skill before
writing the stub — companions, edge cases, and exceptions live
there.

---

## How to use this reference

1. Identify the doc type from the user's request or from the
   source code being documented (header → C++; QML registration
   → QML; no source → page type).
2. Look up the row below.
3. Read the source skill listed in the "Source" column for the
   full template, mandatory companions, and exceptions.
4. Apply the brief rule from `skill-language-style`.
5. Apply the filename canonicalization from `skill-qdoc-output`.
6. Read a sibling document of the same type in the target
   module to confirm conventions (group names, copyright header
   style, body skeleton, section breakdown).
7. Generate the stub. Mark unknown values with `{TODO: hint}`
   where the hint says what to fill in and where to look.

---

## C++ API reference

| Doc type | Topic command | Brief rule | Filename | Source |
|----------|--------------|-----------|----------|--------|
| Class | `\class ClassName` | R16 ("The {Class} class …") | `{classname}.html` | `skill-language-style` R16; `skill-qdoc/SKILL.md` (node system) |
| Namespace | `\namespace Name` | R5 (sentence describing contents) | `{name}.html` | `references/namespaces-headers-macros.md` |
| Function | `\fn signature` | R17 (action verb: Returns/Sets/Constructs) | section in class page | `skill-language-style` R17 |
| Property | `\property Class::name` | R18 ("This property holds…") | section in class page | `skill-language-style` R18 |
| Enum | `\enum Class::Enum` + `\value` per member | R5 (sentence) | section in class page | `skill-language-style` R14 (recommended) |
| Typedef | `\typedef Class::Name` | R5 (1-2 sentences) | section in class page | `references/namespaces-headers-macros.md` |
| Macro | `\macro NAME(args)` + **mandatory `\relates`** | R17 (action verb) | section in `\relates` target's page | `references/namespaces-headers-macros.md` |
| Header file | `\headerfile <Header>` | R5 (sentence) | `{header}.html` | `references/namespaces-headers-macros.md` |
| Module | `\module ModuleName` | R5 (sentence) | `{module}-module.html` | `references/module-declaration.md` |

**Mandatory companions for C++ API:**
- `\inmodule ModuleName` on `\class`, `\namespace`, `\headerfile`,
  `\module`
- `\since {version}` per S3 (verify via git, see
  `references/context-commands.md`)
- `\relates` on `\macro` (no exceptions — without it the macro
  doc is lost)
- For internal/private classes: `\internal` instead of full doc
  (see R16 internal exception)

---

## QML API reference

| Doc type | Topic command | Brief rule | Filename | Source |
|----------|--------------|-----------|----------|--------|
| QML type | `\qmltype Name` | R5 (imperative — Specifies/Provides/…) | `qml-{module}-{type}.html` | `references/qml-topic-commands.md` |
| QML value type | `\qmlvaluetype name` | R5 (imperative) | `qml-{type}.html` | `references/qml-topic-commands.md` |
| QML property | `\qmlproperty type Module::Type::name` | R18 ("This property holds…") | section in QML type page | `references/qml-topic-commands.md` |
| QML method | `\qmlmethod returnType Module::Type::name(args)` (return type **mandatory**) | R17 (action verb) | section in QML type page | `references/qml-topic-commands.md` |
| QML signal | `\qmlsignal Module::Type::name(args)` | R19 ("This signal is emitted when…") | section in QML type page | `references/qml-topic-commands.md` |
| QML attached property | `\qmlattachedproperty type Module::AttachingType::name` | R18 | section in attaching type page | `references/qml-topic-commands.md` |
| QML attached signal | `\qmlattachedsignal Module::AttachingType::name(args)` | R19 | section in attaching type page | `references/qml-topic-commands.md` |
| QML module | `\qmlmodule ModuleName` | R5 (sentence) | `{module}-qmlmodule.html` | `references/module-declaration.md` |

**Mandatory companions for QML API:**
- `\inqmlmodule ModuleName` on `\qmltype` and `\qmlvaluetype`
  (modern QDoc may infer; prefer explicit)
- Property/method/signal forms must be **fully qualified**
  (`Module::Type::name`)
- `\qmlmethod` MUST include a return type (otherwise dropped
  from index — see `references/node-system.md`)

---

## Page-type docs (hand-written, no source)

| Doc type | Filename pattern | Required commands | Source |
|----------|------------------|-------------------|--------|
| Topic overview | `topics-{name}.html` | `\page`, `\title`, `\keyword topics-{name}`, `\brief`, `\ingroup explanations-{category}` | `references/page-structure.md` |
| Module landing | `{module}-index.html` | `\page`, `\title`, `\ingroup frameworks-technologies`, `\brief`, body | `references/page-structure.md` ("Module Overview Page Template") |
| How-to / guide | `{topic}.html` | `\page`, `\title`, `\brief`, `\section1`s | `references/page-structure.md` |
| Tutorial chain | `{tutorial}-chapter{N}.html` | `\page`, `\title`, `\nextpage`/`\previouspage`, `\brief` | `references/page-structure.md` (Navigation Commands) |
| Porting guide | `porting-from-{old}-to-{new}.html` | `\page`, `\title`, `\brief` | `references/page-structure.md` |
| Changes / release | `{module}-changes-qt{N}.html` | `\page`, `\title`, `\ingroup changes-qt-{prev}-to-{N}`, `\brief` | `references/page-structure.md` |
| Group | `{groupname}.html` | `\group`, `\title`, `\brief`, optional `\generatelist{related}` | `references/group-and-organization.md` |
| External page | n/a (link target only) | `\externalpage URL`, `\title` | `references/page-structure.md` |
| Example | `{project}-{name}-example.html` | `\example`, `\examplecategory`, `\ingroup`, `\title`, `\brief`, `\meta` | `references/page-structure.md`; R20-R23 in `skill-language-style` |
| License | `{module}-licensing.html` | `\page`, `\title`, `\brief` | `references/page-structure.md` |

**Mandatory header for new `.qdoc` files:**
```
// Copyright (C) {current calendar year} The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GFDL-1.3-no-invariants-only
```

The year is the current calendar year (when the file is
created), not the year of any source file being referenced.

---

## CMake reference pages

All CMake reference pages are `\page` documents — not derived
from a topic command. Use `\summary {…}` (with braces) instead
of `\brief`.

| Doc type | Filename | Group | Since macro | Source |
|----------|----------|-------|-------------|--------|
| Command | `qt-{command}.html` | `cmake-commands-{module}` | `\cmakecommandsince` | `references/cmake-reference.md` |
| Variable | `cmake-variable-{name}.html` | `cmake-variables-{module}` | `\cmakevariablesince` | `references/cmake-reference.md` |
| Target property | `cmake-target-property-{name}.html` | `cmake-target-properties-{module}` (+ `cmake-properties-{module}`) | `\cmakepropertysince` | `references/cmake-reference.md` |

---

## Brief rule cheat-sheet

| Brief rule | Pattern | Applies to |
|-----------|---------|-----------|
| R5 | Imperative verb (Specifies, Plays, Represents, Provides) | `\qmltype`, `\qmlvaluetype`, page briefs |
| R16 | "The {Class} class …" + verb | `\class` |
| R17 | Action verb (Returns, Sets, Constructs, Updates) | `\fn`, `\qmlmethod`, `\macro` body |
| R18 | "This property holds…" / describes / represents | `\property`, `\qmlproperty`, `\qmlattachedproperty` |
| R19 | "This signal is emitted when…" / Emitted when… | `\fn` for signals, `\qmlsignal`, `\qmlattachedsignal` |

All briefs end with a period (R15). Briefs that are mandatory:
`\class`, `\qmltype`, `\property`, `\qmlproperty`, `\example`,
`\page`, `\module`, `\qmlmodule`, `\namespace`, `\group`,
`\headerfile`. Recommended (not mandatory): `\fn`, `\qmlmethod`,
`\qmlsignal`, `\enum`. See `skill-language-style` R14 for the
full table.

---

## Standard companion commands

These appear across many doc types; consult
`references/context-commands.md` for the authoritative list.

| Command | Purpose | Required when |
|---------|---------|---------------|
| `\inmodule` | C++ module assignment | C++ API docs |
| `\inqmlmodule` | QML module assignment | QML API docs |
| `\since` | Version introduced | C++ classes/functions per S3; recommended elsewhere |
| `\ingroup` | Group membership | Whenever the doc belongs to a discoverable group |
| `\sa` | "See also" cross-references | When related items exist |
| `\internal` | Marks internal API | Private/internal classes |
| `\preliminary` | API not stable | Unstable APIs |
| `\deprecated` | Deprecation marker | Deprecated APIs |
| `\keyword` | Search keyword / link target | Topic overviews, CMake aliases |
| `\target` | Stable anchor | Variable/property pages, in-page anchors |

---

## Sibling-page rule

For any stub, **read at least one well-documented sibling of
the same type** in the target module before generating output.
This catches:

- Module-specific group conventions (`cmake-variables-qttest`
  vs `cmake-variables-qtcore`)
- Copyright header year and style
- Section breakdown patterns ("Synopsis / Description /
  Arguments" vs "Synopsis / Notes")
- Whether `\inqmlmodule` is explicit or omitted in this module
- Title casing convention (sentence vs title case — see R12)

The sibling is not authoritative for rules — `skill-language-
style` is — but it is authoritative for module-local conventions.

---

## Compliance gates

Every stub must pass these gates:

- [ ] Topic command syntax matches the type (e.g., `\qmlmethod`
  has return type)
- [ ] All mandatory companions present (or marked `{TODO}`
  with hint)
- [ ] `\brief` text follows the rule for the type (R5/R16/R17/
  R18/R19)
- [ ] `\brief` ends with period (R15)
- [ ] Filename matches `skill-qdoc-output` algorithm
- [ ] Lines wrapped at 80 columns (R40)
- [ ] Copyright year is the current calendar year (for new
  `.qdoc` files)
- [ ] Group names match siblings in the target module
- [ ] `{TODO: hint}` placeholders include a hint about what
  to fill in and where to look — never bare `{TODO}`

---

## Version History

- **v1.0** (2026-04-27): Initial stub-assembly index covering
  C++ API, QML API, page types, and CMake reference pages.
