# skill-language-style Changelog

- **4.0** (2026-07-17): Progressive-disclosure restructure (no rule content changed)
  - Split monolithic SKILL.md (~14k tokens) into a ~3.8k-token core + 8 on-demand
    reference files under references/. Previous single file exceeded the 5k
    per-skill re-attach cap (~2.8x) and lost its tail after context compaction,
    including the MANDATORY Fix Verification section at the end of the file.
  - Core retains: Overview, Verification Workflow, Rule & Source Enumeration
    (now a router), Core Principles R1-R10, Common Mistakes, R38, and the
    MANDATORY Fix Verification section.
  - Moved rule bodies to references/: prose-rules (R11-R13, R28-R29),
    api-docs (R14-R19), examples-alttext (R20-R27),
    qdoc-formatting (R39-R41, R63-R64), ui-tools (R42-R44), linking (R45-R51b),
    structured-content (R52-R57), page-templates (R58-R62).
  - All 57 rule definitions preserved verbatim; only their location changed.
  - Validated via A/B baseline test (n=4/arm): full rule coverage preserved,
    ~14% fewer tokens per review, no quality regression.
  - Aligned frontmatter version (was stale at 3.7) with the changelog.


- **3.9** (2026-03-16): R60 link verification requirement
  - Added "Reviewer pre-verification (BLOCKING)" note to R60
  - References skill-qdoc/references/link-resolution.md for full checklist

- **3.8** (2026-03-12): `\since` verification requirement
  - Added mandatory `\since` verification via git to R16
  - Commands: `git log --diff-filter=A` + `git tag --contains`
  - Cross-reference to skill-qdoc/references/context-commands.md
  - Do NOT copy `\since` from existing docs without verification

- **3.7** (2026-03-12): R40 table row emphasis
  - Expanded R40 to explicitly list ALL line types that need 80-column compliance
  - Added table rows (`\row`) as commonly overlooked violation source
  - Added example showing how to split long table rows
  - Lesson learned: Agent reviews were skipping table line length checks

- **3.6** (2026-03-12): R60 autolink correction
  - Corrected R60: Parentheses `()` do NOT break autolinking
  - Added context-aware autolink information (same-class functions autolink)
  - Added cross-reference to skill-qdoc/references/link-resolution.md
  - Removed incorrect "Function with `()` | Parentheses break pattern" entry

- **3.5** (2026-03-12): Admonition and markup rules
  - Added R63: Admonition Appropriateness
  - Added R64: Markup Consistency
  - Added "Admonition and Markup" category
  - Updated rule count (now 65 rules total)

- **3.4** (2026-03-01): Module review rules
  - Added R60-R62 (Cross-Module Linking, qdocconf, Module Review Checklist)
  - Added "Module Review" category

- **3.3** (2026-03-01): Page template requirements
  - Added R58-R59 (Module Landing Page Structure, Example Group Requirements)
  - Added "Page Templates" section

- **3.2** (2026-02-24): QML-to-C++ cross-API linking
  - Added R51b: QML-to-C++ Cross-API Linking guidelines

- **3.1** (2026-02-20): R39 whitespace rule clarification
  - Revised R39: "No Space" to "Prefer No Space" (style preference)

- **3.0** (2026-02-18): QML abstraction principle
  - Added R51: QML Abstraction - Use Generic Types, Not C++ Types

- **2.9** (2026-02-17): Linking style and syntax rules (R45-R50)
- **2.8** (2026-02-17): API doc precision, tools docs (R28b, R42-R44)
- **2.7** (2026-02-17): Qt product and module terminology in R3
- **2.6** (2026-02-05): Expanded R38 word substitutions
- **2.5** (2025-12-16): R41 \sa target validation
- **2.4** (2025-12-06): R39-R40 QDoc formatting rules
- **2.3** (2025-11-28): R#/S# enumeration system
- **2.2** (2025-11-28): Skill integration with skill-alttext
- **2.1** (2025-11-28): Two-dimensional framework structure
- **2.0** (2025-11-28): Major update (voice, numbers, alt text, API docs)
- **1.0** (2025-11-28): Initial version
