# C4. Example

Back to [`skill-c-rules`](../SKILL.md).

## Purpose and style
**Purpose.** Shows a working program that uses the module, so the
reader can run it, see the result, and copy the pattern. S6 separates
two kinds:
- **Example documentation** (the minimum): what the example shows, the
  Qt modules it uses, a screenshot, and how to run it.
- **Tutorial-style example**: also walks through the code step by step
  and explains why.

**Style.**
- Register: G25 conceptual for the description; G24 tutorial for the
  walkthrough parts.
- Walkthroughs address the reader as "you" in new text. The inclusive
  "we" in existing examples ("we create the model") is not a finding
  (G24 note, S9).
- Show code with `\snippet`, then explain it. Explain why, not only what.
- Include `examples-run.qdocinc`, one `\examplecategory`, a screenshot
  with alt text.
- Titles: descriptive noun phrase ("Gauge Example"); walkthrough sections
  in the progressive form ("Creating the model") (S1, S6).

## Detect
`\example`; example group: `\group *_examples`. Topics in qt5.git `dev` at `39725828` (2026-09-26): 471.

## Rules
- **Shared R (tool):** R2, R3, R4, R7, R11, R12, R38, R39, R40, R41, R45, R47, R48, R49, R50, R53, R55, R56, R60, R68.
- **Shared G (LLM):** G1, G2, G5, G6, G7, G8, G14, G19, G20, G21, G22, G26, G27, G30 (register drift).
- **C4 R (tool):** R15, R20, R21, R22, R23, R59.
- **C4 G (LLM):** G12.
- **Register (LLM):** G25 Conceptual (description) or G24 Tutorial (walkthrough). Dials: `[content_types.C4]` in `skill-g-rules/references/register-dials.toml` (register defaults plus this type\'s overrides). Tool check: `tools/register-dials/check_dials.py --type C4 FILE`.
- **Images:** R22, R24, R26, G11 wherever `\image` appears.

## Gaps
- `\include examples-run.qdocinc`
- One `\examplecategory`, from the accepted list
- `\meta tag` without platform names or words from the title
- No version numbers in QML imports
- Content: overview, walk-through, references (G)

## Sample

A minimal passing sample of this type:

```qdoc
/*!
    \example gauge
    \title Gauge
    \examplecategory{User Interface Components}
    \brief Shows a value on a dial.
    \image gauge.webp {Gauge at 40 percent}

    \include examples-run.qdocinc
*/
```
