---
name: skill-r-rules
description: Deterministic Qt R-rules, each with the Vale rule, regex, or QDoc message a tool checks. Run before skill-g-rules.
metadata:
  version: "0.1.0"
  status: provisional
  loading: "Pattern 2 (index upfront) + Pattern 3 (references/rules.md at the check step)"
  source: documentation_review/skills/skill-language-style
  vale-source: qt/qtqa vale_linter_config/styles/Qt (Gerrit 774265, merged 2026-10-02), checked against dev 99568de0 on 2026-10-09
---

# skill-r-rules

The **deterministic** R-rules from
[`skill-language-style`](../../../documentation_review/skills/skill-language-style/SKILL.md).
Every rule here has a check that a tool runs: a Vale rule, a regex, or a
QDoc warning message. Same input, same result, no LLM tokens.

Rules that need judgment are in
[`skill-g-rules`](../skill-g-rules/SKILL.md) (G1-G22). A rule that is
partly deterministic keeps its R ID here for the checkable part and has
a G rule for the rest.

**Status: provisional.** The Vale names match the rules in qt/qtqa
`vale_linter_config/styles/Qt` (Gerrit
[774265](https://codereview.qt-project.org/c/qt/qtqa/+/774265), merged).
**(inferred)** marks a rule that change added without naming an R-rule.
The framework uses that configuration as it is and ships no copy of it.

## How agents use this skill

1. **Vale rows.** Run Vale with `vale_linter_config/.vale-qdoc.ini` from
   qt/qtqa. Self-test it first: older QDoc Vale builds load the nested
   `styles/Qt/*` rules but report no alerts and no error, so run it on a
   known-bad line (`Press Control+B.` must report
   `Qt.Structure.KeyboardShortcutFormat`) before trusting a clean result.
   Without a working Vale, check the rows whose tool is a Vale rule with
   the LLM, and say so in the output.
2. Run the regex and QDoc checks that apply to the change.
3. Cite findings as `R<n>` with the tool output. Do not re-check these
   rules with the LLM.
4. Then load `skill-g-rules` for the judgment pass.

Regexes are POSIX ERE for `/usr/bin/grep -E` unless marked `script`.
"QDoc:" means a regex over the QDoc build log.

## Index

| Rule | Topic | Check |
|------|-------|-------|
| R2 | Clear and concise | Vale `Qt.Language.WordyConstructions`, `WordyFillers`, `WordyQuantifier` |
| R3 | Qt terminology (listed names) | Vale `Qt.Language.QtTerminology` |
| R4 | Present tense | Vale `Qt.Language.FutureTense` (inferred) |
| R7 | Idioms | Vale `Qt.Language.Idioms` |
| R11 | Serial comma | Vale `Microsoft.OxfordComma` |
| R12 | Capitalization | Vale `Qt.Language.QDocPageTitle` (inferred), `Microsoft.Headings` |
| R14 | `\brief` required | script: `/*!` block with a top-level topic command (`\class`, `\namespace`, `\headerfile`, `\qmltype`, `\page`, `\module`, ...) and no `\brief`; members exempt |
| R15 | Brief ends with period | Vale `Qt.Structure.QDocBrief` (inferred); QDoc: `'\\brief' statement does not end with a full stop` |
| R16 | Class has `\inmodule` | QDoc: `has no \\inmodule command` |
| R20 | Example page elements | script: each required command present in the `\example` page |
| R21 | Example code builds clean | build log: `warning:`; `qmllint` exit status |
| R22 | Screenshot size | `identify -format '%w %h'`: at least 440 x 320 |
| R23 | Example titles | Vale `Qt.Structure.ExampleTitleRepetition` |
| R24 | Alt text format | Vale `Qt.Structure.AltTextFormat` |
| R26 | Alt text terms | Vale `Qt.Structure.AltTextClassNames` |
| R38 | Substitutions (word lists) | Vale `Qt.Language.HedgingWords`, `LatinTerms`, `LoseLoose` (inferred) |
| R39 | No space before brace | Vale `Qt.Structure.NoSpaceBeforeBrace` |
| R40 | 80 columns | Vale `Qt.Mechanics.LineLength` (inferred); `awk 'length > 80'` |
| R41 | `\sa` targets resolve | QDoc: `Can't link to '` |
| R43 | Keyboard shortcuts | Vale `Qt.Structure.KeyboardShortcutFormat` |
| R45 | `\l` syntax | QDoc: `Can't link to '` |
| R47 | Section links | Vale `Qt.Structure.SectionLinkAntiPattern` |
| R48 | External page links | QDoc: `Can't link to '` |
| R49 | QML cross-module links | QDoc: `Can't link to '` |
| R50 | QML value type case | QDoc: `Can't link to '` |
| R51 | Generic QML types | Vale `Qt.Structure.QMLGenericTypes` |
| R52 | List length 2-7 | script: count `\li` per `\list`; flag 1 or more than 7 |
| R53 | List punctuation | Vale `Qt.Structure.ListItemPunctuation`, `Microsoft.Semicolon` |
| R55 | Empty table cells | Vale `Qt.Structure.TableEmptyCell` |
| R56 | Table headers | Vale `Qt.Structure.TableGenericHeaders` |
| R58 | Module landing page | Vale `Qt.Structure.ModuleExamplesSection`, `ModuleReferenceSection` |
| R59 | Example group | Vale `Qt.Structure.ExampleGroupIngroup` |
| R60 | Cross-module linking | QDoc: `Can't link to '` |
| R61 | qdocconf dependencies | QDoc: `Can't link to '`; qdocconf: `^depends[[:space:]]*\+=` |
| R62 | Module review checklist | composite: R58, R59, R61, R15 |
| R68 | Dashes | Vale `Microsoft.Dashes`; regex `—` |

### Aliases (R30-R37)

Cite the base rule.

| Alias | Mistake | Base |
|-------|---------|------|
| R30 | Passive voice | G1 |
| R31 | Future tense | R4 |
| R32 | Wordy phrases | R2 |
| R33 | Ambiguous "this" | G7 |
| R34 | Inconsistent terms | G5 |
| R35 | Missing `\brief` | R14 |
| R36 | No period in brief | R15 |
| R37 | "Neutral voice" | G3 |

36 deterministic rules. R65-R67 are reserved upstream and not ported.

Statements, samples, and regexes: [`references/rules.md`](references/rules.md).
