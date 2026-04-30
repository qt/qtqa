# Qt Documentation Sources

## Content & Style Authority (WHAT to write)

### Tier 1 - Qt Official Standards (HIGHEST AUTHORITY)

**S1. Qt Writing Guidelines** (PRIMARY)
- URL: https://wiki.qt.io/Qt_Writing_Guidelines
- Coordinates all Qt documentation standards

**S2. QUIP 25 - Qt Documentation Writing Style** (AUTHORITATIVE)
- URL: https://code.qt.io/cgit/meta/quips.git/plain/quip-0025-Documentation-Writing-Style.rst
- Language, grammar, style, formatting
- "This QUIP is primary; Microsoft Writing Style Guide is optional"

**S3. C++ Documentation Style**
- URL: https://wiki.qt.io/C%2B%2B_Documentation_Style
- C++ API documentation patterns

**S4. QML Documentation Style**
- URL: https://wiki.qt.io/QML_Documentation_Style
- QML API documentation patterns

**S5. Qt Examples Guidelines**
- URL: https://wiki.qt.io/Qt_Examples_Guidelines
- Example code quality, zero warnings, screenshots

**S6. Writing Example Documentation and Tutorials**
- URL: https://wiki.qt.io/Writing_Example_Documentation_and_Tutorials
- 11 mandatory elements for example documentation

**S7. Qt Terms and Concepts**
- URL: https://wiki.qt.io/Qt_Terms_and_Concepts
- Official Qt terminology definitions

**S8. Qt Alt Text Style**
- Path: ~/.claude/skills/skill-alttext/SKILL.md
- Alt text patterns, formatting, terminology

### Tier 2 - Supplementary Reference

**S9. Microsoft Style Guide**
- URL: https://learn.microsoft.com/en-us/style-guide/welcome/
- Used when Qt sources don't specify

## Tool & Syntax Reference (HOW to write it)

**S10. QDoc Manual**
- URL: https://doc.qt.io/qt-6/qdoc-index.html
- Local: qttools/src/qdoc/doc/qdoc-index.qdoc
- QDoc command syntax, not a style authority

## When to Consult Which Source

| Question | Source |
|----------|--------|
| Style ("active voice?") | S1 > S2 > S9 |
| C++ API patterns | S3 |
| QML API patterns | S4 |
| QDoc syntax | S10 |
| Terminology | S7 |
| Alt text | S8 |
