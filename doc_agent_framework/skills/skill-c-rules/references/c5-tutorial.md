# C5. Tutorial and getting started

Back to [`skill-c-rules`](../SKILL.md).

## Purpose and style
**Purpose.** Takes a newcomer from nothing to a working result, one step
at a time, so they learn by doing. The reader follows the page from top
to bottom.

**Style.**
- Register: tutorial (G24). "You", imperative steps, in order.
- State the result of each step in the present tense ("A window opens.")
  rather than reassurance.
- Explain why a step matters, briefly (S6 "Insight"); link to reference
  pages for the details instead of repeating them.
- Asides are allowed but few; prerequisites go before the first step.
- Titles: gerund, progressive form ("Getting Started with Qt Quick",
  "Creating the main window") (S1, S6).

## Detect
`\page` name matches `tutorial`, `getting-started`, `first` (heuristic). Topics in qt5.git `dev` at `39725828` (2026-09-26): 32.

## Rules
- **Shared R (tool):** R2, R3, R4, R7, R11, R12, R38, R39, R40, R41, R45, R47, R48, R49, R50, R53, R55, R56, R60, R68.
- **Shared G (LLM):** G1, G2, G5, G6, G7, G8, G14, G19, G20, G21, G22, G26, G27, G30 (register drift).
- **C5 R (tool):** R20 (example-based tutorials), R52.
- **C5 G (LLM):** G4, G12, G13, G17.
- **Register (LLM):** G24 Tutorial. Dials: `[content_types.C5]` in `skill-g-rules/references/register-dials.toml` (register defaults plus this type\'s overrides). Tool check: `tools/register-dials/check_dials.py --type C5 FILE`.
- **Images:** R22, R24, R26, G11 wherever `\image` appears.

## Exemptions
Section titles use the progressive form (G12).

## Gaps
- Step-by-step structure with snippets and the reason for each step (S6)

## Sample

A minimal passing sample of this type:

```qdoc
\section1 Creating a project

You create the project in Qt Creator:

\list 1
    \li Select \uicontrol File > \uicontrol{New Project}.
    \li Select \uicontrol{Qt Quick Application}.
\endlist
```
