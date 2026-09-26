# C9. Qt Creator and Qt Design Studio documentation

Back to [`skill-c-rules`](../SKILL.md).

Tools in the Qt Framework `bin` directory are C12, not C9.

## Purpose and style
**Purpose.** Helps Qt Creator and Qt Design Studio users complete a task
in the IDE, learn the tool, or look up a setting. Qt Creator organizes
pages by kind: how-to (`creator-how-to-*`), tutorial, reference, and
overview.

**Style.**
- Register: tutorial (G24) for how-to and tutorial pages; reference
  (G23) for preferences and UI reference.
- "You", imperative steps, UI text marked up (G13), menu paths with each
  element marked.
- Titles: how-to pages use the **bare imperative** ("Add Podman devices",
  "Build with GN"): about 256 of 257 how-to page titles in qt-creator
  `5a652f1cae5`. This departs from S1's progressive form on purpose.
  Tutorials use "Tutorial: <subject>". Reference pages use nouns.

## Detect
Qt Creator and Qt Design Studio sources (not in qt5.git). Topics in qt5.git `dev` at `39725828` (2026-09-26): not counted.

## Rules
- **Shared R (tool):** R2, R3, R4, R7, R11, R12, R38, R39, R40, R41, R45, R47, R48, R49, R50, R53, R55, R56, R60, R68.
- **Shared G (LLM):** G1, G2, G5, G6, G7, G8, G14, G19, G20, G21, G22, G26, G27, G30 (register drift).
- **C9 R (tool):** R43, R52.
- **C9 G (LLM):** G4, G12, G13.
- **Register (LLM):** G24 Tutorial (how-to and tutorial pages); G23 Reference (preferences and UI reference). Dials: `[content_types.C9]` in `skill-g-rules/references/register-dials.toml` (register defaults plus this type\'s overrides). Tool check: `tools/register-dials/check_dials.py --type C9 FILE`.
- **Images:** R22, R24, R26, G11 wherever `\image` appears.

## Exemptions
None for UI markup. Qt Creator docs are QDoc: mark UI text with
`\uicontrol` (6,171 uses in qt-creator `doc/qtcreator/src` at
`5a652f1cae5`). It renders in bold (S1). An earlier "bold instead of
`\uicontrol`" exemption misread R42, which describes the rendered
output, and was removed on 2026-09-26.

## Gaps
- Not audited against the Qt Creator style sources

## Sample

A minimal passing sample of this type:

```qdoc
Go to \uicontrol Edit > \uicontrol Preferences > \uicontrol Kits, then
select \uicontrol Add.
```
