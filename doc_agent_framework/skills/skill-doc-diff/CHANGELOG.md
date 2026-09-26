# skill-doc-diff Changelog

- **7.3.0** (2026-10-08): One view, one format
  - Every fix is shown as a standard git diff, so it pastes into a prompt,
    an editor, or a review and applies with `git apply`
  - Removed the numbered-arrow renderer and its linter
    (`tools/doc-diff/render.py`, `lint.py`, `selftest.py`).
    `render_record.py` writes the header, Source, and diff from the
    records; `lint_record.py` and `verify_after.py` gate the records
  - The record schema moved to `tools/doc-diff/README.md`, next to the
    tools that enforce it

- **7.2.0** (2026-09-27): Execution record in the audit
  - `tools/doc-diff/execution_record.py` builds it from the agent's
    transcript: the prompt (verbatim), the model pin the agent saw vs the
    model that ran, effort, start and end times, requests, tokens by type,
    cost, each tool call with a rule-based class, and input and output files
    with sizes and SHA-1
  - The audit (`--execution`) shows it as tables and as JSON, and ends with
    a machine-readable result summary (verdict and one entry per finding,
    including how each fix was verified)

- **7.1.0** (2026-09-27): Readable views
  - The diff block is a standard git unified diff (`diff --git`, `@@`
    hunks, 3 context lines) that applies with `git apply`. It replaces the
    numbered arrow lines; unchanged lines stay context, so an insertion
    shows only `+` lines
  - Plain-language labels: evidence items are described in words, with
    the evidence path in brackets; judgment checks are marked "agent's
    judgment"; the rebuild line says what happened; a key explains ✓ and ✗
  - Audit view (`--format audit`, skill-doc-audit 2.0 layout): finding
    types and severities are explained in brackets; the verdict is a plain
    sentence ("Ready for approval." / "Not ready. …")
  - Selftest: the rendered diff must pass `git apply --check`; a pure
    insertion must show no `-` lines

- **7.0.0** (2026-09-27): Records and rendered views
  - Agents write JSON records (edit + judgment); tools render the Doc
    Team diff, gerrit, plain, and the new codereview format from
    records + evidence (`tools/doc-diff/render_record.py`)
  - Gate: `lint_record.py` (schema, C/R/G IDs, evidence paths, line range,
    cause length, content deletion), `verify_after.py` (R39, R40, R47, R68,
    R4, Tier 1 tells, secrets on the new text), and `verify_fix.py` (rebuild)
  - New rule: never delete content just to clear a warning
  - `codereview` format defined (alt-formats.md): explains each proposed
    change, for sharing
  - Loading label corrected: the schema is embedded (Pattern 1); this file
    is no longer loaded during a run. 6.0.0 said "Pattern 1 (upfront)", but
    upfront loading is Pattern 2
  - Measured on scenario qdoc-warnings-01 (one run each): −25% tokens per
    run, −53% per warning handled, all fixes rebuild-verified

- **6.0.0** (2026-09-26): Ported into doc_agent_framework from
  documentation_review 5.22
  - Restructured for loading: SKILL.md holds the template and field rules
    (upfront); fields, verification, examples, and alternative formats
    moved to references/ (GATE)
  - Deterministic first: new `tools/doc-diff/render.py` produces the
    header, Source, and diff block from the file; `lint.py` checks a
    finished review. Arrow alignment and line numbers are no longer
    written by the model
  - Warning strings replaced with the verbatim QDoc strings at qttools
    `cff41040`, with file:line. The old alt-text example
    (`\image is without a textual description`) was not the emitted
    text; the real message is a report and needs
    `reportmissingalttextforimages`
  - Rule IDs mapped to the framework: R1 → G1, R25 → G11, R57 → C11/G28;
    dropped "R10 articles" (no such rule here) and the unsourced
    "under 100 characters" and "7 spaces under \image" checks
  - Link verification now points to skill-qdoc
    `references/link-diagnosis.md` (was link-resolution.md)
  - `fileBase()` reference updated to generator.cpp:309
  - Several-options example no longer puts `\c` inside `\sa`, and its
    3-digit lines now follow the alignment rule (the 5.22 example
    didn't; found by lint.py)
  - Integration list names framework skills only

- **5.22** and earlier: see documentation_review/skills/skill-doc-diff/CHANGELOG.md
