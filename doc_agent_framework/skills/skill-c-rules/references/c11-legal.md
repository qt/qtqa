# C11. Legal and license text

Back to [`skill-c-rules`](../SKILL.md).

## Purpose and style
**Purpose.** States licenses, copyrights, and third-party attributions so
that users of Qt know their obligations. Accuracy outranks readability.

**Style.**
- Register: legal (G28). "Shall" and "must" are allowed; no
  contractions; keep the license's own terms ("Licensee").
- Never rewrite third-party license text. Report issues to the user.
- Qt-authored notices around the legal text follow the shared rules.
- License headers: BSD-3-Clause for example code, GFDL-1.3-no-invariants-only
  for docs, current year (S6; a tool check, not yet written).

## Detect
license headers, `\legalese`, third-party notices. Topics in qt5.git `dev` at `39725828` (2026-09-26): not counted.

## Rules
Legal and license text is checked in Phase 2. It is not exempt.
- **C11 R (tool):** none yet.
- **C11 G (LLM):** none yet.
- **Register (LLM):** G28 Legal. Dials: `[content_types.C11]` in `skill-g-rules/references/register-dials.toml` (register defaults plus this type\'s overrides). Tool check: `tools/register-dials/check_dials.py --type C11 FILE`.
- **Images:** not applicable.

## Gaps
- The rule set for legal text is to be defined in Phase 2.
- S6 requires a license and year check: `BSD-3-Clause` for example code,
  `GFDL-1.3-no-invariants-only` for documentation, and the current year in
  the copyright line. A regex over the file header can check all three.

## Sample

A minimal passing sample of this type:

```qdoc
// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause
```
