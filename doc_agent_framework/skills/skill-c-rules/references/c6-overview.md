# C6. Overview and concept page

Back to [`skill-c-rules`](../SKILL.md).

## Purpose and style
**Purpose.** Builds a mental model of a concept or subsystem: what it
is, why it exists, how the parts relate, and when to use it. The reader
wants understanding before details.

**Style.**
- Register: conceptual (G25). Third person or "you", present tense,
  indicative.
- Open each paragraph with a plain topic sentence. Order sections: what,
  why, how.
- At most one analogy, as support, never as the definition.
- Don't list API facts (link to C1/C2) or give long procedures (link to
  C5/C7).
- Titles: noun phrases ("Signals and Slots", "The Meta-Object System");
  task sections inside the page use the progressive form (S1).

## Detect
other `\page` (fallback). Topics in qt5.git `dev` at `39725828` (2026-09-26): ~1,195.

## Rules
- **Shared R (tool):** R2, R3, R4, R7, R11, R12, R38, R39, R40, R41, R45, R47, R48, R49, R50, R53, R55, R56, R60, R68.
- **Shared G (LLM):** G1, G2, G5, G6, G7, G8, G14, G19, G20, G21, G22, G26, G27, G30 (register drift).
- **C6 R (tool):** R52.
- **C6 G (LLM):** G12, G17.
- **Register (LLM):** G25 Conceptual. Dials: `[content_types.C6]` in `skill-g-rules/references/register-dials.toml` (register defaults plus this type\'s overrides). Tool check: `tools/register-dials/check_dials.py --type C6 FILE`.
- **Images:** R22, R24, R26, G11 wherever `\image` appears.

## Gaps
- No type-specific rules in S1 or S3-S8; QUIP 25 not audited yet

## Sample

A minimal passing sample of this type:

```qdoc
\page qtfoo-overview.html
\title Qt Foo Overview
\brief Explains how gauges map values to angles.

\section1 Value ranges
...
```
