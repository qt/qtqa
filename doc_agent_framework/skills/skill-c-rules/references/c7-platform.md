# C7. Platform and deployment

Back to [`skill-c-rules`](../SKILL.md).

## Purpose and style
**Purpose.** Gets Qt or a Qt application working on a specific platform:
setup, building, deploying, and platform-specific limits. The reader has
a concrete goal and often an error to solve.

**Style.**
- Register: tutorial (G24) for setup and deployment steps; conceptual
  (G25) for sections that explain platform behavior.
- "You", imperative steps, exact commands in `\badcode`, keyboard
  shortcuts per R43.
- State versions and prerequisites up front. Limitations get their own
  section, not asides.
- Titles: "Qt for <Platform>" (noun); task sections in the progressive
  form ("Deploying an application").

## Detect
`\page` name matches a platform (`android`, `ios`, `wasm`, `windows`, `macos`, `linux`, `embedded`) or `deploy` (heuristic). Topics in qt5.git `dev` at `39725828` (2026-09-26): 159.

## Rules
- **Shared R (tool):** R2, R3, R4, R7, R11, R12, R38, R39, R40, R41, R45, R47, R48, R49, R50, R53, R55, R56, R60, R68.
- **Shared G (LLM):** G1, G2, G5, G6, G7, G8, G14, G19, G20, G21, G22, G26, G27, G30 (register drift).
- **C7 R (tool):** R43, R52.
- **C7 G (LLM):** G4, G12, G13, G17.
- **Register (LLM):** G24 Tutorial. Dials: `[content_types.C7]` in `skill-g-rules/references/register-dials.toml` (register defaults plus this type\'s overrides). Tool check: `tools/register-dials/check_dials.py --type C7 FILE`.
- **Images:** R22, R24, R26, G11 wherever `\image` appears.

## Gaps
- No type-specific rules in S1 or S3-S8

## Sample

A minimal passing sample of this type:

```qdoc
\section1 Deploying to Android

You deploy the app with \c androiddeployqt. Press \c Ctrl+R to build and run.
```
