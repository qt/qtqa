# skill-artifact-testing Changelog

- **1.1.0** (2026-08-27): Layer 2 now validates artifact frontmatter.
  - Added a frontmatter-validation check to Layer 2 (Static review):
    presence and closure of the `---` block, valid YAML, required keys
    (agent: name/description/model; skill: name/description/metadata.version),
    name-matches-basename, and the explicit `claude-opus-4-7` model pin for
    agents (not the floating `opus` alias).
  - Added a matching STATIC line to the one-page checklist.

- **1.0.0** (2026-06-16): Initial version.
  - 9-layer methodology (contract, static, system integration, trigger,
    dynamic, verification, edge cases, baseline, fixture)
  - Per-layer criteria and prompt library
  - One-page checklist and fixture template
  - Distilled from testing skill-line-wrap and skill-alttext
