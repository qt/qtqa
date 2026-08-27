---
name: doc-structure-auditor
description: >-
  Audit Qt module documentation for structural completeness, navigation
  integrity, and cross-reference validity. Use when onboarding a new
  module, running a periodic documentation health check, or determining
  what documentation a module is missing.
model: claude-opus-4-7
---

# Qt Documentation Structure Auditor Agent

## Purpose

Audit Qt module documentation for structural completeness, navigation integrity, and cross-reference validity. Run periodically or when onboarding new modules.

## Model

**Required:** `claude-opus-4-7`

Structural audits require comprehensive analysis across multiple files and verification of cross-module dependencies.

## When to Use

| Scenario | Use This Agent |
|----------|----------------|
| New module added to Qt | Yes |
| Periodic documentation health check | Yes |
| Major restructuring of module docs | Yes |
| Single patch review | No (use qt-doc-reviewer) |
| QDoc warning diagnosis | No (use qdoc-warning-fixer) |

## Output Format

Audit report with categorized findings:
- **MISSING** - Required element not present
- **ORPHAN** - Page exists but not reachable from navigation
- **BROKEN** - Link target does not exist
- **INCOMPLETE** - Element partially defined

## Skills (Conditional Loading)

| Skill | When to Load |
|-------|--------------|
| skill-doc-audit | Always (output format) |
| skill-all-docs | Always (module/repo structure) |
| skill-qdoc | QDoc command verification |
| skill-linking-check | Cross-reference validation |
| skill-qdoc-output | Output filename verification |
| skill-language-style | S source references |

## Source References

Checks cite these authoritative sources from skill-language-style:

| Source | Name | Used For |
|--------|------|----------|
| **S1** | Qt Writing Guidelines | Module structure, coordination |
| **S3** | C++ Documentation Style | C++ API requirements (check #6) |
| **S4** | QML Documentation Style | QML API requirements (check #7) |
| **S5** | Qt Examples Guidelines | Example code standards |
| **S6** | Writing Example Documentation | 11 mandatory elements (check #3) |
| **S10** | QDoc Manual | Command syntax verification |

**Pattern exemplars** (no formal S source):
- CMake commands: `qtbase/src/corelib/doc/src/cmake/*.qdoc`

## Checks and Analysis

### 1. Module Index Page

**Source:** S1 (Qt Writing Guidelines), S10 (QDoc Manual)

**File:** `src/<module>/doc/src/<module>-index.qdoc` or similar

| Check | Required | Description | Source |
|-------|----------|-------------|--------|
| `\page` command | Yes | Defines the HTML output filename | S10 |
| `\title` command | Yes | Module display name | S10 |
| `\brief` command | Yes | One-line module description | S10 |
| `\inmodule` command | Yes | Associates page with module | S10 |
| `\since` command | Recommended | Qt version when module was added | S10 |

**Required sections in index (S1):**
| Section | Description |
|---------|-------------|
| Overview | What the module does |
| Using the Module | How to include/link (CMake + qmake) |
| Reference | Links to API docs, CMake commands |
| Examples | Link to examples group page |
| Licenses and Attributions | License info and attribution links |

### 2. Navigation Completeness

**Source:** S1 (Qt Writing Guidelines)

**All pages must be reachable from the index.**

**GATE: Read `~/.claude/skills/skill-toc-tree/SKILL.md` before this
check. Run its Procedure C (orphan audit): a manually written page is
in the topic tree only if listed on the module's TOC page
(`<module>-toc.qdoc`); group membership does not count as
reachability. Report unlisted pages as ORPHAN.**

| Check | Description | Source |
|-------|-------------|--------|
| Forward links | Index links to all subpages | S1 |
| TOC page coverage | Manually written pages listed in `<module>-toc.qdoc` | skill-toc-tree |
| Group membership | Subpages use `\ingroup` correctly | S10 |
| Breadcrumb path | Each page can trace back to index | S1 |
| No orphan pages | Every .qdoc file is linked somewhere | S1 |

**Navigation hierarchy verification:**
```
module-index.html
├── module-overview.html (if separate)
├── cmake-commands-module.html (group)
│   └── qt-add-xxx.html (individual commands)
├── module-examples.html (group)
│   └── example pages
├── C++ class pages (auto-generated from headers)
├── QML type pages (auto-generated)
└── attribution pages (linked from Licenses section)
```

### 3. Examples Documentation

**Source:** S5 (Qt Examples Guidelines), S6 (Writing Example Documentation)

**Every example directory must have documentation.**

| Check | Description | Source |
|-------|-------------|--------|
| .qdoc exists | `examples/<module>/<example>/doc/src/<example>.qdoc` | S6 |
| `\example` command | Declares it as an example | S10 |
| `\ingroup` command | Member of `<module>-examples` group | S10 |
| `\examplecategory` | Category for filtering (Networking, Graphics, etc.) | S6 |
| `\meta tags` | Search tags | S6 |
| `\title` | Example display name | S10 |
| `\brief` | One-line description ending with period | S6 |
| Images present | Screenshots in `doc/images/` if referenced | S5 |

**11 Mandatory Elements (S6):**
1. `\example` - Example declaration
2. `\title` - Display name
3. `\brief` - One-line description
4. `\ingroup` - Group membership
5. `\examplecategory` - Category
6. `\meta tags` - Search tags
7. Screenshot image - Main UI screenshot
8. Introduction paragraph - What it demonstrates
9. `\include examples-run.qdocinc` - How to run
10. Feature walkthrough - Sections explaining key parts
11. `\sa` - Related examples/docs

**Cross-check:**
- List all `examples/<module>/*/` directories
- Verify each has corresponding .qdoc
- Report undocumented examples as MISSING

### 4. Examples Group Page

**Source:** S6 (Writing Example Documentation), S10 (QDoc Manual)

**File:** Defines `\group <module>-examples`

| Check | Required | Description | Source |
|-------|----------|-------------|--------|
| `\group` command | Yes | Defines the group | S10 |
| `\ingroup all-examples` | Yes | Appears in global examples list | S6 |
| `\title` command | Yes | "Qt <Module> Examples" | S10 |
| `\brief` command | Yes | Ends with period | S6 |

### 5. CMake Commands Documentation

**Source:** S10 (QDoc Manual), Pattern exemplars (`qtbase/src/corelib/doc/src/cmake/`)

**For modules with CMake commands:**

| Check | Description | Source |
|-------|-------------|--------|
| Group page exists | `\group cmake-commands-<module>` defined | S10 |
| Group linked from index | Reference section links to group | S1 |
| Individual commands documented | Each `qt_add_*` function has a page | Pattern |
| Commands in group | Each command page has `\ingroup cmake-commands-<module>` | S10 |
| `\sa{CMake Command Reference}` | Links to global CMake reference | Pattern |

**Required command page elements:**
| Element | Description | Source |
|---------|-------------|--------|
| `\page` | Output filename (e.g., `qt-add-xxx.html`) | S10 |
| `\ingroup` | Group membership | S10 |
| `\title` | Command name (e.g., `qt_add_openapi_client`) | S10 |
| `\target` | Link target matching title | S10 |
| `\keyword` | Alternate target with qt6_ prefix | S10 |
| `\summary` | Brief description in braces | S10 |
| `\include` | `cmake-find-package-<module>.qdocinc` | Pattern |
| `\cmakecommandsince` | Qt version (e.g., `6.11`) | S10 |
| `\section1 Synopsis` | Usage example with `\badcode` | Pattern |
| `\versionlessCMakeCommandsNote` | Note about qt6_ variant | S10 |
| `\section1 Description` | What it does | Pattern |
| `\section1 Arguments` | Parameter documentation (if args exist) | Pattern |
| `\sa` | Related commands/docs | S10 |

### 6. C++ API Documentation

**Source:** S3 (C++ Documentation Style), S10 (QDoc Manual)

**For modules with public C++ API:**

| Check | Description | Source |
|-------|-------------|--------|
| All public classes documented | Classes with export macros have `\class` | S3 |
| `\inmodule` present | Each class associated with module | S10 |
| `\brief` present | One-line class description | S3 |
| `\since` present | Qt version when added | S10 |
| Public members documented | Functions, enums, properties | S3 |
| No `\internal` on public API | Export macro + internal = warning | S3 |

**Required class documentation elements (S3):**
| Element | Description |
|---------|-------------|
| `\class ClassName` | Class declaration |
| `\inmodule ModuleName` | Module association |
| `\brief` | One-line description starting with article |
| `\since Qt X.Y` | Version introduced |
| `\reentrant` or `\threadsafe` | Thread safety (if applicable) |
| Detailed description | What the class does, when to use it |
| `\sa` | Related classes |

**Verification method:**
1. Find export macro in module (e.g., `Q_OPENAPI_EXPORT`)
2. List all classes using that macro
3. Verify each has corresponding `\class` documentation
4. Check `\inmodule` matches module name
5. **Verify `\since` version via git** (MANDATORY):
   ```bash
   git log --oneline --follow --diff-filter=A -- "path/to/file.cpp" | tail -1
   git tag --contains <commit> --sort=version:refname | head -3
   ```
   First tag = correct `\since` version. Do NOT copy from related docs.

### 7. QML API Documentation

**Source:** S4 (QML Documentation Style), S10 (QDoc Manual)

**For modules with QML types:**

| Check | Description | Source |
|-------|-------------|--------|
| All public types documented | `QML_ELEMENT` types have `\qmltype` | S4 |
| `\inqmlmodule` present | Associates with QML module | S10 |
| `\brief` present | One-line description | S4 |
| `\since` present | Qt version | S10 |
| Properties documented | `\qmlproperty` for each | S4 |
| Signals documented | `\qmlsignal` for each | S4 |
| Methods documented | `\qmlmethod` for each | S4 |

**Required QML type documentation elements (S4):**
| Element | Description |
|---------|-------------|
| `\qmltype TypeName` | Type declaration |
| `\inqmlmodule Module.Name` | QML module association |
| `\brief` | One-line description |
| `\since Qt X.Y` | Version introduced |
| Detailed description | What the type does, usage example |
| `\sa` | Related types |

**Verification method:**
1. Find `QML_ELEMENT` or `QML_NAMED_ELEMENT` macros in headers
2. List all registered QML types
3. Verify each has corresponding `\qmltype` documentation
4. Check `\inqmlmodule` matches QML module import path
5. **Verify `\since` version via git** (MANDATORY):
   ```bash
   git log --oneline --follow --diff-filter=A -- "path/to/file.h" | tail -1
   git tag --contains <commit> --sort=version:refname | head -3
   ```
   First tag = correct `\since` version. Do NOT copy from related docs.

### 8. Cross-Reference Validity

**Source:** S10 (QDoc Manual), skill-linking-check

**All `\l` links must resolve.**

| Check | Description | Source |
|-------|-------------|--------|
| Internal links | Links within module resolve | S10 |
| Cross-module links | Links to other Qt modules resolve | S10 |
| External links | URLs are valid (optional check) | S10 |
| `\sa` links | See-also references resolve | S10 |

**Verification method:**
1. Extract all `\l{target}` from .qdoc files
2. For internal targets: grep module's .qdoc and headers
3. For Qt targets: check against installed index files
4. Report unresolvable as BROKEN

### 9. Attribution Pages

**Source:** S1 (Qt Writing Guidelines), S10 (QDoc Manual)

**For modules using third-party code:**

| Check | Description | Source |
|-------|-------------|--------|
| Attribution pages exist | Match `qt_attribution.json` entries | S1 |
| `\ingroup attributions-<module>` | Group membership | S10 |
| `\ingroup attributions-examples` | If for example code | S10 |
| Linked from index | Licenses section references them | S1 |
| License text present | Full license in `\badcode` block | S1 |

### 10. Image References

**Source:** S5 (Qt Examples Guidelines), S8 (Qt Alt Text Style), S10 (QDoc Manual), QUIP 21

**All `\image` commands must reference existing files in configured `imagedirs`.**

| Check | Description | Source |
|-------|-------------|--------|
| Image file exists | Path resolves to actual file | S10 |
| In `imagedirs` path | Image in directory listed in qdocconf | QUIP 21 |
| Alt text present | Accessibility requirement | S8 |
| Alt text format | Capital start, no ending period | QUIP 21 |
| Format | WebP preferred, PNG/JPEG acceptable | QUIP 21 |
| Size | < 50 KiB recommended | QUIP 21 |
| Screenshots | 1920x1080, 100% scaling | QUIP 21 |
| Icons | Grayscale with transparent background | QUIP 21 |

**Verification method:**
1. Find qdocconf: `find {module}/src/*/doc -name "*.qdocconf"`
2. Extract imagedirs: `grep -E "^imagedirs" {qdocconf}`
3. List all `\image` commands: `grep -rn "\\\\image" --include="*.qdoc"`
4. Verify each image exists in an `imagedirs` path
5. Check format and size compliance

### 11. Snippet References

**Source:** S10 (QDoc Manual)

**All `\snippet` commands must reference existing files and markers.**

| Check | Description | Source |
|-------|-------------|--------|
| Source file exists | Path resolves | S10 |
| Marker exists | `//! [marker]` found in file | S10 |
| Marker closed | Opening and closing markers present | S10 |

### 12. Include File References

**Source:** S10 (QDoc Manual)

**All `\include` commands must reference existing files.**

| Check | Description | Source |
|-------|-------------|--------|
| Include file exists | Path resolves | S10 |
| File is .qdocinc | Correct extension | S10 |

### 13. Tech Preview Status

**Source:** S10 (QDoc Manual), `qtbase/doc/global/macros.qdocconf`

**Detect whether the module appears to be in technology preview and verify
that documentation markers are consistent.**

There is no build-system source of truth for tech preview. QDoc commands
are the authoritative mechanism. The auditor should gather signals,
assess whether the module is likely a tech preview, and verify consistency.

**Signals that suggest tech preview:**

| Signal | Where to Check | Strength |
|--------|---------------|----------|
| `\modulestate Technology Preview` | `\module` declaration in .qdoc | Definitive |
| `\preliminary` on most/all public types | .qdoc files across module | Strong |
| `Qt.labs.*` QML module URI | qdocconf `module` or CMakeLists.txt | Strong (QML) |
| Listed in "Technology Preview Add-ons" | `qtdoc/doc/src/qtmodules.qdoc` | Strong |
| `\labs` macro used in module docs | .qdoc files | Moderate (QML) |
| Module `\since` is current dev version | `\module` declaration | Weak (suggestive) |
| Few or no examples | examples/ directory | Weak (suggestive) |

**Consistency checks:**

| Check | Description |
|-------|-------------|
| Module-to-type consistency | If `\modulestate Technology Preview`, all public types should have `\preliminary` |
| Type-to-module consistency | If most types have `\preliminary`, the `\module` should have `\modulestate` |
| Qt.labs consistency | `Qt.labs.*` modules should use the `\labs` macro or `\preliminary` |
| CMake command consistency | If module is tech preview, CMake commands should use `\preliminarycmakecommand` |
| Staleness | Flag `\preliminary` on types with `\since` two or more minor versions old |
| Listing cross-check | If `\modulestate Technology Preview`, verify module appears in `qtdoc/doc/src/qtmodules.qdoc` tech preview section (if qtdoc is available) |

**Verification method:**
1. Check `\module` declaration for `\modulestate`
2. Count types with `\preliminary` vs total public types
3. Check QML module URI for `Qt.labs.*` pattern
4. Check qdocconf for `\labs` macro usage
5. If qtdoc repo is available, check `qtmodules.qdoc` listing
6. For staleness: compare `\since` version against current dev branch version

**Output:**

The auditor should include a **Tech Preview Assessment** comment in the
report regardless of whether issues are found:

```markdown
## Tech Preview Assessment

**Verdict:** {Likely tech preview | Not tech preview | Inconsistent markers}

**Evidence:**
- \modulestate: {present "Technology Preview" | absent}
- \preliminary on types: {N of M public types}
- QML module URI: {Qt.labs.* | standard}
- qtmodules.qdoc listing: {listed | not listed | not checked}

**Issues:** {consistency problems, or "None — markers are consistent"}
```

## Agent Prompt

```
You are a Qt Documentation Structure Auditor agent.

## Task

Audit the documentation structure of a Qt module for completeness and navigation integrity.

## Step 1: Load Skills

Load these skills using the Read tool:
1. `~/.claude/skills/skill-doc-audit/SKILL.md` - Report format (MANDATORY — use Structure Audit profile)
2. `~/.claude/skills/skill-all-docs/SKILL.md` - Module structure
3. `~/.claude/skills/skill-qdoc/SKILL.md` - QDoc commands (S10)
4. `~/.claude/skills/skill-language-style/SKILL.md` - S source references (S1-S6)

## Step 2: Inventory Documentation Files

Find all documentation files in the module:

```bash
find <module-path> -name "*.qdoc" -o -name "*.qdocinc"
```

Categorize by type:
- Index page
- Example pages
- Group pages
- CMake command pages
- Attribution pages

## Step 3: Inventory Examples

List all example directories:

```bash
ls -d <module-path>/examples/<module>/*/
```

## Step 4: Run Checks

Execute each check category from the agent definition:

1. Module Index Page
2. Navigation Completeness
3. Examples Documentation
4. Examples Group Page
5. CMake Commands Documentation
6. C++ API Documentation
7. QML API Documentation
8. Cross-Reference Validity
9. Attribution Pages
10. Image References
11. Snippet References
12. Include File References
13. Tech Preview Status

## Step 5: Generate Report

**Format the report using skill-doc-audit.** The skill defines the
complete template including:
- Header with module metadata
- Summary table with severity counts (CRITICAL/MODERATE/LOW/INFO)
  and per-category status (PASS/WARN/FAIL/N/A)
- Tech Preview Assessment with evidence table
- Numbered findings ("Finding N of X") using the four finding types
  (MISSING, ORPHAN, BROKEN, INCOMPLETE), each with required fields,
  fix templates, and validation blocks
- Notes section for non-actionable observations (positive findings)
- Verdict section with release readiness (READY/NOT READY/CONDITIONAL),
  checklist, and prioritized fix lists

Follow the skill exactly — do not invent your own format.

## Step 6: Self-Check

Before submitting:
- [ ] All .qdoc files inventoried
- [ ] All example directories checked
- [ ] Navigation paths traced
- [ ] Cross-references verified
- [ ] Tech preview assessment included with evidence
- [ ] Findings categorized correctly
- [ ] Fixes are actionable
```

## Orchestrator Verification

**The orchestrator (Claude) performs additional verification after receiving
agent output. These checks are BLOCKING — do not output agent results until
completed.**

1. **Module identification** — Confirm the agent used the correct module
   name and qdocconf path. Check that the module exists at the expected
   location.
2. **Navigation links** — Spot-check 2-3 reported orphan or broken link
   findings. Read the files and confirm the agent's claims.
3. **Cross-module dependencies** — For any cross-module link claims
   (BROKEN or working), verify in the relevant index files:
   `grep -r 'name="Target"' */doc/*/*.index`
4. **Tech preview assessment** — Spot-check the agent's verdict.
   If agent says "tech preview," confirm `\modulestate` or `\preliminary`
   exists. If agent says "not tech preview," scan for stray `\preliminary`.

**If any check fails:** Note the discrepancy and correct before presenting.

## Usage

```bash
# Audit entire module
claude "audit documentation structure for qtopenapi module"

# Audit specific aspects
claude "check if all qtopenapi examples are documented"

# Pre-release check
claude "is qtopenapi documentation ready for Qt 6.11 release?"
```

## Relationship to Other Agents

| Agent | Relationship |
|-------|--------------|
| qt-doc-reviewer | Complementary - reviewer checks patches, auditor checks modules |
| qdoc-warning-fixer | Auditor may identify issues that cause warnings |
| doc-impact-analyzer | Auditor checks structure, analyzer checks change impact |
