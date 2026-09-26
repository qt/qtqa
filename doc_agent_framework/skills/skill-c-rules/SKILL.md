---
name: skill-c-rules
description: Qt content types as C-rules (C1-C12, C16 commit messages): how to detect each type and which R- and G-rules apply. Load before R and G.
metadata:
  version: "0.2.0"
  status: provisional
  loading: "Pattern 2 (index upfront) + Pattern 3 (one C page per detected type)"
---

# skill-c-rules

**C-rules** are content types. Each type gets its own set of rules. Detect
the type first, then run only that type's R-rules
([`skill-r-rules`](../skill-r-rules/SKILL.md)) and G-rules
([`skill-g-rules`](../skill-g-rules/SKILL.md)). Rules that don't apply to a type waste
tokens and produce false findings: G4 ("you") doesn't belong in an API
brief, and R14 (`\brief` required) doesn't apply to a tutorial.

Detection is deterministic (the topic command or the `\page` name). The C5, C7, C8, and C12
name and path patterns are heuristics; when a page fits no type, use C6 and say so.
Counts are topics in qt5.git `dev` at `39725828` (2026-09-26) with all submodules checked out, excluding 3rdparty and tests.

| Rule | Type | Detect by | Count | Register |
|------|------|-----------|-------|----------|
| [C1](references/c1-cpp-api.md) | C++ API reference | `\class`, `\fn`, `\property`, `\enum`, `\macro`, `\typedef`, `\namespace` | 19,806 | G23 |
| [C2](references/c2-qml-api.md) | QML API reference | `\qmltype`, `\qmlproperty`, `\qmlmethod`, `\qmlsignal`, `\qmlvaluetype` | 9,160 | G23 |
| [C3](references/c3-module-page.md) | Module page | `\module`, `\qmlmodule`, `\page *-index.html` | 243 | G25 |
| [C4](references/c4-example.md) | Example | `\example`; example group: `\group *_examples` | 471 | G25 or G24 |
| [C5](references/c5-tutorial.md) | Tutorial and getting started | `\page` name matches `tutorial`, `getting-started`, `first` (heuristic) | 32 | G24 |
| [C6](references/c6-overview.md) | Overview and concept page | other `\page` (fallback) | ~1,195 | G25 |
| [C7](references/c7-platform.md) | Platform and deployment | `\page` name matches a platform (`android`, `ios`, `wasm`, `windows`, `macos`, `linux`, `embedded`) or `deploy` (heuristic) | 159 | G24 |
| [C8](references/c8-porting.md) | Porting, changes, and what's new | `\page` name matches `porting`, `changes`, `whatsnew`, `new-in` (heuristic) | 63 | G29, G24, G25 |
| [C9](references/c9-tools.md) | Qt Creator and Qt Design Studio documentation | Qt Creator and Qt Design Studio sources (not in qt5.git) | not counted | G24, G23 |
| [C10](references/c10-external-page.md) | External page declaration | `\externalpage` | 1,212 | none |
| [C11](references/c11-legal.md) | Legal and license text | license headers, `\legalese`, third-party notices | not counted | G28 |
| [C12](references/c12-dev-tools.md) | Qt Framework development tools | `\page` under a tools doc directory or named `qtqml-tooling-*` (heuristic) | 173 pages | G23, G24 |
| [C16](references/c16-commit-message.md) | Commit message | `git log --format=%B` or the Gerrit commit endpoint (not a QDoc topic) | 4,575 commits sampled | G25; G29 for `[ChangeLog]` |

**Node rules.** C1 and C2 carry one sub-rule per QDoc node type (C1.0-C1.10
for C++: class, namespace, header, function, property, variable, enum,
typedef, macro, concept; C2.0-C2.5 for QML: type, property, signal, method,
enumeration). Apply the sub-rule for each topic block and cite it as
`C1.<n>` or `C2.<n>`. For a single node (one warning, one block), load only what it needs:
`python3 tools/c-rules/section.py C1.5`. For a page review, load the whole
C page.

**Register dials.** Each type's register settings live in
`skill-g-rules/references/register-dials.toml` under `[content_types.C<n>]`:
the register(s) the type uses and any per-type overrides. Tune a type
there (for example, a shorter `sentence_words_max` for C1) without
editing rule prose.

**Reserved (not doc.qt.io; not detected or reviewed yet):** C13 Qt Blog
post, C14 qt.io product page, C15 Qt Forum post (C16 is the commit message, above). G26, G27, and G30 name
them as the channels where those registers are expected. Don't reuse
these IDs.

Every prose type (C1-C9, C12) shares:
- **R (tool):** R2, R3, R4, R7, R11, R12, R38, R39, R40, R41, R45, R47, R48, R49, R50, R53, R55, R56, R60, R68.
- **G (LLM):** G1, G2, G5, G6, G7, G8, G14, G19, G20, G21, G22, G26, G27, G30.
- **Images:** R22, R24, R26, G11 wherever an image appears.

## How agents use this skill

1. Detect the C type for each `/*! */` block or `.qdoc` page. State it.
2. Load that type's page from `references/`.
3. Run the shared R-rules and the type's own R-rules with tools, then check the shared G-rules and the type's own G-rules with the LLM.
4. Run `tools/register-dials/check_dials.py --type C<n> FILE` for the tool dials (sentence length, contractions, "we", "So"). Then check the register rule for the type (G23-G29) and the drift rules (G26, G27, G30), from [`skill-g-rules/references/registers.md`](../skill-g-rules/references/registers.md). Each C page has a **Purpose and style** section.
5. Cite findings as `C<n>/R<n>` or `C<n>/G<n>`.

Gaps come from an audit of the S-sources (S1, S3-S8) against skill-r-rules and skill-g-rules; each C page lists its own.

## Adding a content type

The reference file is the source of truth. Everything else lists it.

1. Take the next free ID. Skip the reserved IDs above.
2. Copy a sibling page to `references/c<N>-<slug>.md`. Keep the title
   form `# C<N>. <Type>` and the sections Purpose and style, Detect,
   Rules, Gaps, and Sample. Count the topics with a command and give the
   commit.
3. In this file: add a table row, extend the `description:` range, and
   add the ID to "Every prose type" if the type has prose. Bump
   `metadata.version`.
4. Add `[content_types.C<N>]` to `skill-g-rules/references/register-dials.toml`.
5. Add test content: a row in the content-type table in
   `tests/README.md`, with a fixture page (or "none" and why) and a
   real sample.
6. Run `python3 tools/c-rules-index/check_c_index.py`. It fails until
   steps 3 to 5 agree with the reference files.

