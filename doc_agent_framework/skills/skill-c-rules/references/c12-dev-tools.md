# C12. Qt Framework development tools

Back to [`skill-c-rules`](../SKILL.md).

Tools that ship in the `bin` directory of a Qt installation: command-line
tools (`moc`, `rcc`, `qmllint`, `windeployqt`), tools with a UI
(Qt Assistant, Qt Designer, Qt Linguist), and the build tools (`qmake`).
Tracked by [QTBUG-144693](https://qt-project.atlassian.net/browse/QTBUG-144693).
Qt Creator and Qt Design Studio are C9, not C12.

## Purpose and style
**Purpose.** Documents the tools in a Qt installation's `bin` directory:
what each tool does, how to run it, its options, and, for linters,
what each warning means and how to fix it.

**Style.**
- Register: reference (G23) for option tables and diagnostic pages;
  tutorial (G24) for usage walkthroughs and manuals for tools with a UI.
- Tool, option, and file names in `\c`. Usage line in `\badcode`.
- Diagnostic pages: what it means, why it matters, how to fix it, with a
  before-and-after example.
- Titles: the tool name ("qmllint", "rcc"); task sections in the
  progressive form ("Running qmllint in CI").

## Detect
A `\page` in any of these places (path heuristic):
- `doc/src/development/`, `doc/src/tools/`, `concepts/tools/`, `doc/src/qmllint/`
- the Qt Assistant, Qt Designer, Qt Linguist, and qmake doc directories in qttools and qtbase
- `qtdoc/doc/src/qt-tools-utilities.qdoc` (the tools overview)

Or a `\page` name that starts with `qtqml-tooling-`.

Pages in qt5.git `dev` at `39725828` (2026-09-26): 173 (qtbase, qtdeclarative,
qttools, and qtdoc only).

## Page shapes
| Shape | Example |
|-------|---------|
| Tools overview | `qt-tools-utilities.qdoc` |
| Command-line tool reference | `development/rcc.qdoc` |
| Tool diagnostic (one warning per page) | `qmllint/unused-imports.qdoc` |
| Tool with a UI (manual) | `assistant-quick-guide.qdoc` |

## Rules
- **Shared R (tool):** R2, R3, R4, R7, R11, R12, R38, R39, R40, R41, R45, R47, R48, R49, R50, R53, R55, R56, R60, R68.
- **Shared G (LLM):** G1, G2, G5, G6, G7, G8, G14, G19, G20, G21, G22, G26, G27, G30 (register drift).
- **C12 R (tool):** R14, R15, R43, R52.
- **C12 G (LLM):** G3, G4, G12, G13 (tools with a UI), G17.
- **Register (LLM):** G23 Reference (options, diagnostics); G24 Tutorial (usage, UI manuals). Dials: `[content_types.C12]` in `skill-g-rules/references/register-dials.toml` (register defaults plus this type\'s overrides). Tool check: `tools/register-dials/check_dials.py --type C12 FILE`.
- **Images:** R22, R24, R26, G11 wherever `\image` appears.

## Gaps
- Command-line reference: a usage line in `\badcode`, and every option in a table
- Exit status documented when the tool is used in scripts or CI
- Tool, option, and file names in `\c`
- Every tool in `bin` is listed on and linked from the tools overview (QTBUG-144693)
- Diagnostic pages: what the warning means, why it matters, how to fix it, with a before-and-after example

## Sample

A minimal passing sample of this type:

```qdoc
/*!
    \page gaugecheck.html
    \title gaugecheck
    \brief Checks that Gauge values in QML files lie inside their range.

    \badcode
    gaugecheck [options] <file.qml>
    \endcode

    \table
        \header
            \li Option
            \li Description
        \row
            \li \c {--fix}
            \li Replaces each value outside the range with the nearest limit.
    \endtable
*/
```
