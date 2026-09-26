# C3. Module page

Back to [`skill-c-rules`](../SKILL.md).

## Purpose and style
**Purpose.** The entry point to a module: what the module is for, how
to add it to a project, and where to go next (types, classes, examples,
overviews). The reader decides here whether the module fits their need.

**Style.**
- Register: conceptual (G25). Third person or "you", present tense.
  Explain what the module does and when to use it.
- A short factual introduction is fine. Don't sell: no superlatives
  (T13, T18) or benefit-led marketing (G27).
- Required sections: using the module (CMake and qmake), and for QML
  modules `\section1 QML Types` and `\section1 Related Information` (S4).
- Titles: noun phrases ("Qt Charts"); sections are nouns ("Licenses and
  attributions") or gerunds for the task ("Using the module").

## Detect
`\module`, `\qmlmodule`, `\page *-index.html`. Topics in qt5.git `dev` at `39725828` (2026-09-26): 243.

## Rules
- **Shared R (tool):** R2, R3, R4, R7, R11, R12, R38, R39, R40, R41, R45, R47, R48, R49, R50, R53, R55, R56, R60, R68.
- **Shared G (LLM):** G1, G2, G5, G6, G7, G8, G14, G19, G20, G21, G22, G26, G27, G30 (register drift).
- **C3 R (tool):** R14, R15, R58, R61, R62.
- **C3 G (LLM):** G12, G17.
- **Register (LLM):** G25 Conceptual. Dials: `[content_types.C3]` in `skill-g-rules/references/register-dials.toml` (register defaults plus this type\'s overrides). Tool check: `tools/register-dials/check_dials.py --type C3 FILE`.
- **Images:** R22, R24, R26, G11 wherever `\image` appears.

## Exemptions
R58 covers C++ landing pages; QML module pages are a gap.

## Gaps
- QML module page: `\section1 QML Types` with `\generatelist`, and `\section1 Related Information`

## Sample

A minimal passing sample of this type:

```qdoc
/*!
    \page qtfoo-index.html
    \title Qt Foo
    \brief Provides gauges and dials.

    \section1 Using the module
    ...
    \section1 Examples
    ...
    \section1 Reference
    ...
*/
```
