# C10. External page declaration

Back to [`skill-c-rules`](../SKILL.md).

## Purpose and style
**Purpose.** Declares an external URL as a link target so other pages can
link to it by title. It has no reader-facing prose.

**Style.** No register. The `\title` matches how pages link to it (R48).

## Detect
`\externalpage`. Topics in qt5.git `dev` at `39725828` (2026-09-26): 1,212.

## Rules
- **C10 R (tool):** R48.
- **C10 G (LLM):** none.
- **Images:** not applicable.

## Exemptions
Declaration only: no prose rules apply.

## Gaps
- None known.

## Sample

A minimal passing sample of this type:

```qdoc
/*!
    \externalpage https://wiki.qt.io/Qt_Writing_Guidelines
    \title Qt Writing Guidelines
*/
```
