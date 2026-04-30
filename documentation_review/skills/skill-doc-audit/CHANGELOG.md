# skill-doc-audit Changelog

- **v2.0** (2026-04-10): Generalized to shared findings report format
  - Renamed from "Audit Report" to "Findings Report" — serves both
    doc-structure-auditor and doc-impact-analyzer
  - Added Report Profiles: Structure Audit and Impact Analysis
  - Added 6 impact analysis finding types: BREAKING, STALE, GAP,
    COSMETIC, FLAG, UNVERIFIED with severity mappings
  - Added Impact Analysis categories (7): Link References, API
    Documentation, Page Targets, Image References, Snippet/Include
    Paths, Cross-Module, Cross-Product
  - Added Cross-Product Impact special section (impact profile)
  - Added impact verdict: SAFE, HAS ISSUES, UNVERIFIED
  - Unified core format: Header, Summary, Special Section, Findings,
    Notes, Verdict shared across profiles
  - Updated Field Reference table to cover all 10 finding types
  - Updated validation requirements for all finding types
  - Removed v1.0 complete example (auditor-only) — profiles are
    self-documenting
- **v1.0** (2026-04-10): Initial release
  - Structured audit report format with Header, Summary, Tech Preview
    Assessment, Findings, Notes, and Verdict sections
  - Four finding types: MISSING, ORPHAN, BROKEN, INCOMPLETE
  - Four severity levels: CRITICAL, MODERATE, LOW, INFO
  - Summary table with per-category pass/fail/warn status
  - Release readiness verdict: READY, NOT READY, CONDITIONAL
  - Automation parsing patterns (Python regex) for all fields
  - Validation requirements per finding type
  - Complete example using qtopenapi module audit
