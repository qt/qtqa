# skill-ai-tells Changelog

- **2.2.0** (2026-09-28): Ported to the Doc Agent Framework.
  - Removed local home paths (framework boundary, SKILL.md and this file); calibration and
    long-form reports described as local, not linked
  - R68 now points at skill-r-rules and G22 in skill-g-rules
    (skill-language-style isn't in the framework)
  - Consumer table: framework agents and the Tier 1 tool copies
  - Added `loading` and `ported-from` metadata

- **2.1.0** (2026-08-06): Declared scope, and portability beyond Qt.
  - **Scope section** on two axes. Axis 1, Qt document type: corpus A was
    split into API reference (1.70M words), overview pages (602k), and
    tutorials (96k). Rates are flat, so **the same thresholds apply to all
    three**. This corrects the looser tutorial aside budget On asides
    proposed; Qt tutorials use the em dash at the reference rate. Three real
    variations recorded: T13-soft (0.01 reference vs 0.10 overview),
    T5 triads (0.36 vs 1.10 in tutorials), and second person, which is R6's
    business and not a tell.
  - Axis 2, artifact: per-row applicability for doc patches, generated docs,
    review fix text, commit messages, reports, skill and agent markdown, and
    chat. Marked as policy rather than measurement, since corpus A gives no
    baseline outside Qt docs.
  - **"Where no tell applies"**: code blocks, signatures and `\value` lists,
    verbatim quotes, table null placeholders, and license or `\whatsnew`
    pages, where "a comprehensive list of all new classes" is correct usage.
  - **Portability section**: what transfers (the tier method, rewrite-not-
    delete, the dash taxonomy, T16/T17 as structures) against what must be
    re-derived per corpus (every rate, T18's word list, the `--` finding,
    R-rule citations). Recalibration recipe, the register limit (do not run
    this on marketing copy), and the license position: the qtqa fleet copy is
    `LicenseRef-Qt-Commercial OR BSD-3-Clause`, so third-party reuse is fine;
    the local calibration data is unpublished.

- **2.0.0** (2026-08-05): Calibrated against the Qt corpus. Every pattern
  measured on 2,393,908 words of Qt reference prose (corpus A), 7,283 words of
  machine-written prose in the same domain (B), and 5,076 words of the same
  guides after a house rewrite (C). Scripts and results
  kept locally by the Doc Team.
  - **Three tiers** replace the flat density model. Tier 1 is near-absent in
    Qt prose, Tier 2 is density-only, Tier 3 is not a tell.
  - **T1 rebuilt** around the mark and its position. Matches the literal em
    dash only; ` -- ` is Qt legacy ASCII and CLI text, not a tell. Four
    position classes: paired (1 instance corpus-wide, always flag), terminal
    (83, colon substitute), label (14 vs 56 with a colon), ASCII (106, leave).
  - **T3, T4, T9, T12 demoted to Tier 3.** They fire on Qt's own prose at the
    same rate as on machine prose. T9 is anti-correlated (Qt 1.29/1k vs
    machine 0.27/1k) and leaves the scan entirely, delegated to R1 and Vale.
  - **T8 and T13 split** into strong and soft sets. `very`, `simply`, `just`,
    `powerful`, and `comprehensive` are Qt-present and no longer auto-flag.
  - **T16 personification** (0 hits in corpus A), **T17 antithesis** (5),
    **T18 absent lexicon** (14 words at exactly 0), **T19 contraction
    density** (register meter, A 0.94/1k vs essay 5.77/1k) added.
  - **Five candidates rejected on evidence**, recorded so they are not
    re-proposed: formal connectives, rhetorical question headings, vague
    quantifiers, "think of X as", hypothetical-reader narrative.
  - Dash recency check added: 14/14 sampled em-dash lines last touched within
    twelve months, against a control spanning 2011-2025.
  - Points at **R68** in skill-language-style for the writer-side dash rule.

- **1.0.0** (2026-08-05): Initial version.
  - T1-T15 table with per-tell fix, R-rule mapping, and detect method
  - Grep cheat sheet: 9 mechanical patterns, 3 partial, 3 read-only
  - Density thresholds calibrated on the 2026-07-14 report-corpus run
  - Rewrite-not-delete rule and the "does it state a fact?" test
  - Legitimate-keep list and scan exclusions
  - Distilled from the Doc Team's local AI-tells catalogue report
