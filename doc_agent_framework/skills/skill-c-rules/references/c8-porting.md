# C8. Porting, changes, and what's new

Back to [`skill-c-rules`](../SKILL.md).

## Purpose and style
**Purpose.** Tells developers what changed between releases and how to
update their code: what's new, what's removed or deprecated, and
porting steps.

**Style.**
- Change lists: release-notes register (G29). Start with the verb,
  past tense, one change per item, no pronouns ("Removed
  QFoo::oldValue(). Use QFoo::value() instead.").
- Porting procedures: tutorial register (G24). Explanations of new
  concepts: conceptual (G25).
- Planned removals may use the future ("will be removed in Qt 7") (R4).
- A short factual feature introduction is fine; no marketing (G27).
- Titles: nouns ("What's New in Qt 6.12", "Removed APIs"). "Deprecations"
  and "Known Issues" are accepted labels.

## Detect
`\page` name matches `porting`, `changes`, `whatsnew`, `new-in` (heuristic). Topics in qt5.git `dev` at `39725828` (2026-09-26): 63.

## Rules
- **Shared R (tool):** R2, R3, R4, R7, R11, R12, R38, R39, R40, R41, R45, R47, R48, R49, R50, R53, R55, R56, R60, R68.
- **Shared G (LLM):** G1, G2, G5, G6, G7, G8, G14, G19, G20, G21, G22, G26, G27, G30 (register drift).
- **C8 R (tool):** R52.
- **C8 G (LLM):** G12, G17.
- **Register (LLM):** G29 Release notes (change lists); G24 or G25 for prose. Dials: `[content_types.C8]` in `skill-g-rules/references/register-dials.toml` (register defaults plus this type\'s overrides). Tool check: `tools/register-dials/check_dials.py --type C8 FILE`.
- **Images:** R22, R24, R26, G11 wherever `\image` appears.

## Exemptions
R4 exception: planned removals ("will be removed in Qt 7") are allowed.

## Gaps
- No type-specific rules in S1 or S3-S8

## Sample

A minimal passing sample of this type:

```qdoc
\section1 Removed APIs

QFoo::oldValue() was removed. Use QFoo::value() instead.
QFoo::legacyMode() will be removed in Qt 7.
```
