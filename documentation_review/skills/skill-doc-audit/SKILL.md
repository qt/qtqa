---
name: skill-doc-audit
description: Structured findings report format shared by doc-structure-auditor and doc-impact-analyzer. Covers severity levels, finding types, summary tables, validation blocks, notes, and verdicts.
metadata:
  version: "2.0"
---

# Qt Doc Team Findings Report Format

A structured template for presenting documentation findings. Used by
agents that produce analysis reports (not patches or content).

**Consuming agents:**
- **doc-structure-auditor** — Module release readiness audits
- **doc-impact-analyzer** — Change impact analysis

## Report Structure

Every report has these sections, always in this order:

1. **Header** — Report type, scope, metadata (agent-specific fields)
2. **Summary Table** — Categories x severity counts + status
3. **Special Section** — Agent-specific (Tech Preview / Cross-Product)
4. **Findings** — Numbered issues with typed fields and validation
5. **Notes** — Non-actionable observations
6. **Verdict** — Outcome determination with prioritized action items

---

## 1. Header

The header identifies the report type and scope. Fields vary by agent.

```markdown
# {Report Title}

**Date:** YYYY-MM-DD
**Agent:** {agent name}
{agent-specific fields}
```

**Automation parsing:**
```python
title = re.match(r"# (.+)", line).group(1)
date = re.search(r"\*\*Date:\*\* (\d{4}-\d{2}-\d{2})", block).group(1)
agent = re.search(r"\*\*Agent:\*\* (.+)", block).group(1)
```

**Structure Audit header:**
```markdown
# Documentation Structure Audit: Qt <Module>

**Date:** 2026-04-10
**Agent:** doc-structure-auditor
**Branch:** dev
**Module path:** `qtopenapi/src/openapi/`
**qdocconf:** `qtopenapi/src/openapi/doc/qtopenapi.qdocconf`
```

**Impact Analysis header:**
```markdown
# Documentation Impact Analysis: {change description}

**Date:** 2026-04-10
**Agent:** doc-impact-analyzer
**Commit:** {sha} | **Branch:** {branch}
**Changed modules:** {list}
**Changes analyzed:**
- {OldName → NewName (type rename)}
- {file.h renamed to newfile.h}
```

---

## 2. Summary Table

**Purpose:** At-a-glance view of all categories with severity counts.

Categories are agent-specific (see Report Profiles below), but the
table structure is identical.

```markdown
## Summary

| # | Category | CRITICAL | MODERATE | LOW | INFO | Status |
|---|----------|----------|----------|-----|------|--------|
| 1 | {category} | 0 | 1 | 0 | 0 | WARN |
| 2 | {category} | 0 | 0 | 0 | 0 | PASS |
| ... | | | | | | |
| | **Total** | **0** | **1** | **0** | **0** | |

**Totals:** 1 finding (0 critical, 1 moderate, 0 low, 0 info)
```

**Status values:**
- `PASS` — Zero CRITICAL or MODERATE findings in this category
- `WARN` — One or more MODERATE or LOW findings, zero CRITICAL
- `FAIL` — One or more CRITICAL findings
- `N/A` — Category does not apply (e.g., no QML API; no C++ renames)

**Automation parsing:**
```python
row = re.match(
    r"\|\s*(\d+)\s*\|\s*(.+?)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*"
    r"\|\s*(\d+)\s*\|\s*(PASS|WARN|FAIL|N/A)\s*\|",
    line
)
```

---

## 3. Severity Levels (Shared)

All agents use the same four-level severity scale.

| Severity | Meaning | Action |
|----------|---------|--------|
| CRITICAL | Prevents correct rendering, navigation, or link resolution | Must fix |
| MODERATE | Degrades quality, findability, or accuracy | Should fix |
| LOW | Minor omission or inconsistency; docs function without it | Nice to fix |
| INFO | Observation or suggestion; no functional impact | Optional |

---

## 4. Finding Types

Finding types are agent-specific. Each type has required fields.

### Core Fields (all finding types, all agents)

Every finding has these fields:

```markdown
**Finding N of X:**

**Type:** {agent-specific type}
**Severity:** {CRITICAL | MODERATE | LOW | INFO}
**Category:** {agent-specific category}
```

Plus at least one of:
- **Location** / **File** / **File:line** — Where the issue is
- **Validation** block — ✓/✗ checks showing evidence
- **Fix** — How to resolve (code block, diff, or prose)

**Progress tracking:** "Finding N of X" counts only actionable findings
(not Notes). Separate findings with `---` horizontal rules.

**Automation parsing:**
```python
finding = re.match(r"\*\*Finding (\d+) of (\d+):\*\*", line)
ftype = re.search(r"\*\*Type:\*\* (\w+)", block).group(1)
severity = re.search(r"\*\*Severity:\*\* (\w+)", block).group(1)
category = re.search(r"\*\*Category:\*\* (.+)", block).group(1).strip()
```

### Structure Audit Finding Types

Used by **doc-structure-auditor**. These describe what is structurally
wrong with the module's documentation.

#### MISSING

A required element does not exist.

```markdown
**Type:** MISSING
**Severity:** {CRITICAL | MODERATE | LOW}
**Category:** {audit category}
**Location:** `{where it should be created}`
**Check:** {specific check from agent definition}
**Source:** {S reference}

**Impact:** {What breaks without this element}

**Fix template:**
```qdoc
{minimal QDoc skeleton to add}
```

**Validation:**
- ✗ {Failed check}: {Detail} ({Source})
- ✓ {Passed check}: {Detail}
```

**Severity guidelines:**
- CRITICAL: index page, `\module` declaration, navigation entry point
- MODERATE: `\brief`, `\since`, `\sa` on public API
- LOW: optional elements like `\reentrant`

#### ORPHAN

A page exists but is unreachable from navigation.

```markdown
**Type:** ORPHAN
**Severity:** {MODERATE | LOW}
**Category:** {audit category}
**File:** `{full/path/to/orphan.qdoc}`
**Output:** `{output-filename.html}`
**Check:** {specific check}
**Source:** {S reference}

**Issue:** {Why unreachable}

**Searched:**
- {grep commands run}

**Fix:** Add link from `{parent-page.qdoc}`:
```qdoc
\l{target-page.html}{Display Text}
```

**Validation:**
- ✗ {Reachability check}: {Detail} ({Source})
- ✓ {Content check}: {Detail}
```

#### BROKEN

A link target does not resolve.

```markdown
**Type:** BROKEN
**Severity:** {CRITICAL | MODERATE}
**Category:** {audit category}
**File:** `{full/path/to/source.qdoc}:{line}`
**Output:** `{output page}`
**Check:** {specific check}
**Source:** {S reference}

**Link:** `\l{target}` (or `\sa{target}`)
**Target:** `{what the link points to}`

**Issue:** {Why it doesn't resolve}

**Searched:**
- {verification steps}

**Fix:**
```diff
  - NN→\l{broken-target}
  +   →\l{corrected-target}
```

**Validation:**
- ✗ {Link resolution check}: {Detail} ({Source})
- ✓ {Corrected target exists}: {evidence}
```

#### INCOMPLETE

An element exists but is missing required sub-elements.

```markdown
**Type:** INCOMPLETE
**Severity:** {MODERATE | LOW}
**Category:** {audit category}
**File:** `{full/path/to/file.qdoc}`
**Output:** `{output-filename.html}`
**Check:** {specific check}
**Source:** {S reference}

**Present:**
- {elements that exist}

**Missing:**
- {elements that are absent}

**Fix:**
```qdoc
{QDoc commands or content to add}
```

**Validation:**
- ✓ {Present element}: {Detail}
- ✗ {Missing element}: {Detail} ({Source})
```

### Impact Analysis Finding Types

Used by **doc-impact-analyzer**. These describe what a code change
will break or degrade in documentation.

#### BREAKING

Links will fail or QDoc warnings will appear after the change lands.

```markdown
**Type:** BREAKING
**Severity:** CRITICAL
**Category:** {impact category}
**Change:** `{OldName}` → `{NewName}`
**Affected:** {count} file(s)

**Locations:**
- `{path/to/file.qdoc}:{line}` — `\l{OldName}`
- `{path/to/other.qdoc}:{line}` — `\sa OldName`

**Evidence:**
```
{grep output showing references}
```

**Fix:**
```diff
  - NN→\l{OldName}
  +   →\l{NewName}
```

**Validation:**
- ✗ Old target exists after change: removed in commit (S10)
- ✓ New target exists: verified in diff
- ✓ Fix syntax: `\l{NewName}` resolves
```

**Severity:** Always CRITICAL. Broken links produce QDoc warnings and
404 links in published docs.

#### STALE

References are outdated but may still resolve (e.g., description
mentions old behavior, prose uses old name in explanatory text).

```markdown
**Type:** STALE
**Severity:** {MODERATE | LOW}
**Category:** {impact category}
**Change:** `{OldName}` → `{NewName}`
**File:** `{path/to/file.qdoc}:{line}`

**Issue:** {What is outdated and why}

**Evidence:**
```
{grep output}
```

**Fix:**
```diff
  - NN→{old text}
  +   →{updated text}
```

**Validation:**
- ✗ Reference current: mentions old name/behavior ({Source})
- ✓ Fix accuracy: updated text matches new behavior
```

**Severity guidelines:**
- MODERATE: API description, parameter docs, behavioral claims
- LOW: Comments, tangential mentions

#### GAP

New content needs documentation that does not yet exist.

```markdown
**Type:** GAP
**Severity:** {MODERATE | LOW}
**Category:** {impact category}
**Location:** `{where docs should be added}`
**Change:** {what was added that needs docs}

**Impact:** {What users can't find without this documentation}

**Fix template:**
```qdoc
{minimal skeleton}
```

**Validation:**
- ✗ Documentation exists: no `\class`/`\qmltype`/`\page` found ({Source})
- ✓ Public API: export macro confirmed in header
```

**Severity guidelines:**
- MODERATE: New public class, QML type, or CMake command
- LOW: New enum value, property, or overload

#### COSMETIC

Prose or comments mention old names but links still work (e.g.,
case-only renames, explanatory text).

```markdown
**Type:** COSMETIC
**Severity:** LOW
**Category:** {impact category}
**File:** `{path/to/file.qdoc}:{line}`

**Issue:** {What is cosmetically wrong}

**Fix:**
```diff
  - NN→{old text}
  +   →{updated text}
```

**Validation:**
- ✓ Links still resolve: QDoc normalizes to lowercase (S10)
- ✗ Text consistency: prose uses old name/casing
```

**Severity:** Always LOW. Links function; only text is inconsistent.

#### FLAG

Requires review by another team (marketing, legal, other product).

```markdown
**Type:** FLAG
**Severity:** INFO
**Category:** {impact category}
**Team:** {marketing | legal | Qt for Python | Qt Creator | ...}

**Issue:** {Why this team needs to review}

**Action:** {What they should check}
```

**Severity:** Always INFO. The impact analyzer cannot fix these —
only flag them.

#### UNVERIFIED

A cross-product or cross-module check could not be performed.

```markdown
**Type:** UNVERIFIED
**Severity:** MODERATE
**Category:** {impact category}
**Product:** {Qt for Python | Qt Creator | Qt Design Studio | ...}

**Issue:** {What could not be checked and why}

**Attempted:**
- {verification methods tried and why they failed}

**Action:** Manual check required before landing.
```

**Severity:** Always MODERATE. Unknown risk that cannot be dismissed.

---

## 5. Validation Requirements

**Every finding MUST include a Validation block.** Minimum checks:

| Finding Type | Minimum Validations |
|--------------|---------------------|
| MISSING | 2 — failed existence check + impact verification |
| ORPHAN | 2 — failed reachability check + content existence |
| BROKEN | 2 — failed resolution check + corrected target |
| INCOMPLETE | 2 — at least one ✓ + at least one ✗ |
| BREAKING | 2 — old target removed + new target exists |
| STALE | 2 — reference outdated + fix verified |
| GAP | 2 — no docs exist + public API confirmed |
| COSMETIC | 2 — links still work + text inconsistent |
| FLAG | 0 — no validation needed (delegation) |
| UNVERIFIED | 1 — at least one attempted verification |

**Validation marks:**
- `✓` — Check passed
- `✗` — Check failed

**Every ✗ must have a corresponding fix.** A finding with only ✓
marks is not a finding — move it to Notes.

---

## 6. Notes Section

**Purpose:** Non-actionable observations and positive findings that
prove audit coverage. Do NOT count toward finding total.

```markdown
## Notes

**{Label}:** {Detail — what was checked and found correct.}

**{Label}:** {Observation with no action required.}
```

**Rules:**
- One entry per observation, bold label + colon + detail
- Include positive findings to show coverage
- Do NOT number entries or use severity levels
- For impact analysis: include "Searches Performed" checklist here

---

## 7. Verdict Section

**Purpose:** Final determination with prioritized action items.

```markdown
## Verdict

**{Verdict label}:** {VERDICT_VALUE}

**Checklist:**
- [x] {check that passed}
- [ ] {check that failed} ← N findings

**Blocking issues (must fix):**
1. Finding N: {description} (CRITICAL)

**Recommended fixes (should fix):**
2. Finding N: {description} (MODERATE)

**Optional improvements:**
3. Finding N: {description} (LOW)
```

**Automation parsing:**
```python
readiness = re.search(
    r"\*\*(?:Release readiness|Commit safety):\*\* (.+)", block
).group(1)

checklist_item = re.match(
    r"- \[(x| )\] (.+?)(?:\s*←\s*(.+))?$", line
)

blocking = re.match(
    r"\d+\. Finding (\d+): (.+?) \((\w+)\)", line
)
```

---

## Report Profiles

### Profile: Structure Audit

**Agent:** doc-structure-auditor
**Title:** `Documentation Structure Audit: Qt <Module>`
**Verdict label:** `Release readiness`
**Verdict values:** READY | NOT READY | CONDITIONAL

**Categories (13):**

| # | Category |
|---|----------|
| 1 | Module Index |
| 2 | Navigation |
| 3 | Examples |
| 4 | Examples Group |
| 5 | CMake Commands |
| 6 | C++ API |
| 7 | QML API |
| 8 | Cross-References |
| 9 | Attributions |
| 10 | Images |
| 11 | Snippets |
| 12 | Includes |
| 13 | Tech Preview |

**Finding types:** MISSING, ORPHAN, BROKEN, INCOMPLETE

**Special section — Tech Preview Assessment:**

Always included between Summary and Findings.

```markdown
## Tech Preview Assessment

**Verdict:** {Likely tech preview | Not tech preview | Inconsistent markers}

**Evidence:**
| Signal | Value | Strength |
|--------|-------|----------|
| `\modulestate` | {present / absent} | Definitive |
| `\preliminary` on types | {N of M} | Strong |
| QML module URI | {Qt.labs.* / standard / N/A} | Strong |
| qtmodules.qdoc listing | {tech preview / released / not checked} | Strong |
| Module `\since` | {Qt X.Y} | Weak |

**Consistency:** {All markers agree / Inconsistencies found — see findings}
```

**Verdict criteria:**
- `READY` — Zero CRITICAL, zero or few MODERATE
- `NOT READY` — One or more CRITICAL
- `CONDITIONAL` — Zero CRITICAL, multiple MODERATE

### Profile: Impact Analysis

**Agent:** doc-impact-analyzer
**Title:** `Documentation Impact Analysis: {change description}`
**Verdict label:** `Commit safety`
**Verdict values:** SAFE | HAS ISSUES | UNVERIFIED

**Categories (7):**

| # | Category |
|---|----------|
| 1 | Link References |
| 2 | API Documentation |
| 3 | Page Targets |
| 4 | Image References |
| 5 | Snippet/Include Paths |
| 6 | Cross-Module |
| 7 | Cross-Product |

**Finding types:** BREAKING, STALE, GAP, COSMETIC, FLAG, UNVERIFIED

**Special section — Cross-Product Impact:**

Always included between Summary and Findings.

```markdown
## Cross-Product Impact

| Product | Status | Method | Detail |
|---------|--------|--------|--------|
| Qt for Python | ✓ Not affected | Grepped local repo | No references found |
| Qt Creator | ⚠ Check needed | Published HTML | 2 links to old name |
| Qt Design Studio | ⚠ **Unverified** | Repo not available | Manual check required |
| Marketing/Legal | ✓ N/A | | Not a major change |
```

**Rules:**
- Every "Not affected" MUST state the verification method
- A status without evidence is UNVERIFIED, not "Not affected"
- Unverified products generate UNVERIFIED findings

**Verdict criteria:**
- `SAFE` — Zero BREAKING/STALE/GAP findings, all products verified
- `HAS ISSUES` — One or more BREAKING, STALE, or GAP findings
- `UNVERIFIED` — One or more products could not be checked; add:
  "Cross-product impact could not be fully verified. Manual check
  required before landing."

**Searches Performed** (in Notes section):
```markdown
**Searches performed:**
- [x] `\l{}` patterns in .qdoc files
- [x] `\sa` references in .qdoc files
- [x] Index file searches (`*/doc/*/*.index`)
- [x] Cross-module dependencies (qdocconf `depends`)
- [x] Cross-product impact (Qt for Python, Creator, Design Studio)
- [x] Alias/conflict check (`\keyword`, `\target`)
```

---

## Field Reference

All fields across all finding types:

| Field | Finding Types | Required | Format |
|-------|--------------|----------|--------|
| Finding N of X | All | Yes | `**Finding N of X:**` |
| Type | All | Yes | `**Type:** {TYPE}` |
| Severity | All | Yes | `**Severity:** {LEVEL}` |
| Category | All | Yes | `**Category:** {category}` |
| Location | MISSING, GAP | Yes | `**Location:** \`{path}\`` |
| File | ORPHAN, INCOMPLETE, STALE, COSMETIC | Yes | `**File:** \`{path}\`` |
| File:line | BROKEN | Yes | `**File:** \`{path}:{line}\`` |
| Output | ORPHAN, BROKEN, INCOMPLETE | When verifiable | `**Output:** \`{file.html}\`` |
| Check | MISSING, ORPHAN, BROKEN, INCOMPLETE | Yes | `**Check:** {name}` |
| Source (ref) | MISSING, ORPHAN, BROKEN, INCOMPLETE | Yes | `**Source:** {S ref}` |
| Change | BREAKING, STALE, GAP, COSMETIC | Yes | `**Change:** \`old\` → \`new\`` |
| Affected | BREAKING | Yes | `**Affected:** {count} file(s)` |
| Locations | BREAKING | Yes | List of `path:line` |
| Link | BROKEN | Yes | `**Link:** \`{cmd}\`` |
| Target | BROKEN | Yes | `**Target:** {desc}` |
| Impact | MISSING, GAP | Yes | `**Impact:** {text}` |
| Issue | ORPHAN, BROKEN, STALE, COSMETIC, FLAG, UNVERIFIED | Yes | `**Issue:** {text}` |
| Present | INCOMPLETE | Yes | `**Present:**` (list) |
| Missing | INCOMPLETE | Yes | `**Missing:**` (list) |
| Team | FLAG | Yes | `**Team:** {name}` |
| Product | UNVERIFIED | Yes | `**Product:** {name}` |
| Evidence | BREAKING, STALE | Recommended | Code block |
| Searched | ORPHAN, BROKEN | Recommended | `**Searched:**` (list) |
| Attempted | UNVERIFIED | Yes | `**Attempted:**` (list) |
| Action | FLAG, UNVERIFIED | Yes | `**Action:** {text}` |
| Fix | All except FLAG, UNVERIFIED | Yes | Code block |
| Validation | All except FLAG | Yes | `- ✓/✗ {Check}: {Detail}` |

**Generic finding parser:**
```python
import re

def parse_finding(block):
    finding = {}
    finding["number"] = int(
        re.search(r"\*\*Finding (\d+) of \d+:\*\*", block).group(1)
    )
    finding["total"] = int(
        re.search(r"\*\*Finding \d+ of (\d+):\*\*", block).group(1)
    )
    finding["type"] = re.search(
        r"\*\*Type:\*\* (\w+)", block
    ).group(1)
    finding["severity"] = re.search(
        r"\*\*Severity:\*\* (\w+)", block
    ).group(1)
    finding["category"] = re.search(
        r"\*\*Category:\*\* (.+)", block
    ).group(1).strip()

    # Optional fields
    for field in ["Location", "File", "Output", "Check", "Source",
                   "Change", "Link", "Target", "Team", "Product"]:
        m = re.search(
            rf"\*\*{field}:\*\* `?(.+?)`?\s*$", block, re.MULTILINE
        )
        if m:
            finding[field.lower()] = m.group(1).strip()

    validations = re.findall(
        r"- ([✓✗]) (.+?):\s*(.+?)(?:\s*\((.+?)\))?$",
        block, re.MULTILINE
    )
    finding["validations"] = [
        {"pass": v[0] == "✓", "check": v[1],
         "detail": v[2], "ref": v[3]}
        for v in validations
    ]
    return finding
```

---

## Common Mistakes

- **Counting Notes as findings**: Only actionable issues get
  "Finding N of X". Notes are separate.
- **Wrong severity**: Use the guidelines for each finding type. BREAKING
  is always CRITICAL; COSMETIC is always LOW.
- **No evidence on BROKEN/ORPHAN/BREAKING**: Show what you searched.
  The orchestrator re-runs these.
- **Fix template too vague**: Provide actual QDoc commands or diff, not
  "add documentation here."
- **Summary table math wrong**: Column totals must match finding counts.
- **Verdict contradicts Summary**: CRITICAL findings → NOT READY / HAS
  ISSUES. No exceptions.
- **Missing positive Notes**: Show what passed to prove coverage.
- **UNVERIFIED reported as "Not affected"**: If you can't check, say so.
- **Mixing profiles**: Don't use audit finding types (MISSING/ORPHAN) in
  impact analysis, or vice versa.

---

## Integration

- **skill-doc-diff:** Sibling format for patch-level suggestions. When
  an impact analysis finding needs a concrete fix, the fix block within
  the finding uses doc-diff diff syntax.
- **skill-qdoc:** QDoc command syntax (S10 references)
- **skill-qdoc-output:** HTML filename verification for Output field
- **skill-language-style:** S source references (S1-S6) for check
  citations
- **skill-all-docs:** Module and repository structure
- **skill-linking-check:** Cross-reference validation and search patterns
- **skill-module-export:** Public API detection for API checks

**Changelog:** See `CHANGELOG.md`
