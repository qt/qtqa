---
name: skill-doc-diff
description: Reference for the Qt Doc Team diff format - generic feedback and recommendation template with validation and approval workflow
metadata:
  version: "5.22"
---

# Qt Doc Team Diff Format

A structured template for presenting documentation changes for human review and approval.

## Format Template

**CRITICAL:** Always use ` ```diff ` code fence for syntax highlighting.

```markdown
**Suggestion N of X for {basename}:{line}:**

**Warning:** `{exact warning text}` (if from QDoc warning)
**Category:** {Issue Type}
**Source:** `{full/path/from/repo/root}`
**Output:** `{output-file.html}` (if verifiable)

```diff
    NN→{context}
  - NN→{removed}
  +   →{added}
    NN→{context}
```

**Cause:** {Why this issue occurs + evidence from searches}

**Validation:**
- ✓/✗ {Check}: {Detail} ({Rule Reference})

**Comments:** {Why this matters}

Should I apply this fix to the file?
```

**With multiple fix options:**
```markdown
**Suggestion N of X for {basename}:{line}:**

**Warning:** `{exact warning text}`
**Category:** {Issue Type}
**Source:** `{full/path/from/repo/root/{basename}}`
**Output:** `{output-file.html}` (for link fixes)

**Cause:** {Why this warning occurs}

**Fix Options:**
1. **{Option name}** - {description}
2. **{Option name}** - {description}

**Recommended:** Option N because {reason}

```diff
{diff for recommended option}
```

**Validation:**
...

Which option should I apply?
```

**Progress tracking:**
- Use "Suggestion N of X" (e.g., "Suggestion 8 of 20")
- Or "File N of X" when showing multiple files
- Helps user track progress through large change sets

## Source Field

**Purpose:** Provide both scannable identification (header) and precise location (Source field) for disambiguation.

**Header format:** `**Suggestion N of X for {basename}:{line}:**`
- `{basename}` - Filename only (e.g., `qquickfolderdialog.cpp`)
- `{line}` - Primary line number of the change
- Keeps header scannable and concise

**Source field:** `**Source:** \`{full/path/from/repo/root}\``
- Full path to the source file being edited
- Resolves ambiguity (multiple files with same basename)
- Enables copy-paste to editor
- Placed after Warning and Category fields

**Examples:**
```markdown
**Suggestion 3 of 7 for qquickfolderdialog.cpp:27:**

**Source:** `qtdeclarative/src/quickdialogs/quickdialogs/qquickfolderdialog.cpp`
```

```markdown
**Suggestion 1 of 5 for qquickfolderdialog.cpp:42:**

**Source:** `qtdeclarative/src/labs/platform/qquicklabsplatformfolderdialog.cpp`
```

**When Source can be omitted:**
- Single-file reviews where context is already established
- The file was just opened/read in the conversation

**Automation parsing:**
```python
# Header provides quick identification
header = re.match(r"\*\*Suggestion (\d+) of (\d+) for (.+):(\d+):\*\*", line)
basename, line_num = header.group(3), header.group(4)

# Source field provides full path for file operations
source = re.search(r"\*\*Source:\*\* `(.+)`", block).group(1)
```

## Category

**Purpose:** Clearly identify the type of issue being addressed.

**Placement:** After the Warning field, before the Source field.

**Common categories:**
- QDoc Syntax
- Missing Alt Text
- Insufficient Alt Text
- Grammar
- Language
- 80-Column Violation
- Empty Section
- Character Encoding
- Inconsistent Capitalization
- Missing Documentation

**Combined categories** (when multiple issues in one suggestion):
- `80-Column Violation + Inconsistent Capitalization`
- `Character Encoding + QDoc Syntax`

**Example:**
```markdown
**Suggestion 3 of 10 for example.qdoc:42:**

**Warning:** `\image is without a textual description`
**Category:** Missing Alt Text
**Source:** `qtdoc/doc/src/examples/example.qdoc`

```diff
...
```
```

## Warning Field

**Purpose:** Show the exact QDoc warning being addressed. Enables traceability from warning to fix.

**Placement:** Immediately after the suggestion header, before Category. Optional for non-warning issues.

**Format:** Use backticks to show the exact warning text.

```markdown
**Warning:** `Can't link to 'SamplerHint'`
```

**Common warning patterns:**
- `Can't link to 'Target'` - Link resolution failure
- `Failed to find function when parsing \fn ...` - Signature mismatch
- `No output generated for property '...' because '...' is undocumented` - Missing parent class docs
- `Output file already exists, overwriting ...` - Duplicate page definitions

## Output Field

**Purpose:** Show the generated HTML output page where the documented text appears. This enables the reviewer to verify the fix in the actual published documentation.

**Why it matters:** After applying a fix, the reviewer can navigate to this HTML page (on doc.qt.io or doc-snapshots.qt.io) to confirm the link works correctly in the rendered output.

**Placement:** After Source field, before diff block. Optional but helpful for context.

**Format:** `**Output:** \`{filename.html}\``

**New pages:** When adding `\qmltype`, `\class`, or `\page` documentation that creates a new HTML page (rather than editing an existing one), add `(new)` suffix:
```markdown
**Output:** `qml-qt-labs-stylekit-theme.html` (new)
```

**CRITICAL:** Only include if verified. If you cannot find the output file, **omit the field entirely**. It cannot be wrong or guessed.

**Important distinction:**
- **Output field** = The rendered page where the edited text appears (e.g., editing Place QML type docs → `qml-qtlocation-place.html`). Reviewer opens THIS page to verify the fix.
- **NOT** = The page the link resolves to (e.g., NOT `qml-geocoordinate.html` just because you're fixing a `\l geoCoordinate` link)

**How to find the output file:**

**NEVER GUESS.** Use the method appropriate for the document type:

1. **For `\page` docs (overviews, manual pages)**
   Read the source file and find the `\page` command:
   ```qdoc
   \page sbom.html
   \title Qt SBOM Overview
   ```
   The HTML filename is specified directly: `sbom.html`

2. **For type docs (class, QML type, module)**
   Search index files for the CONTAINING TYPE being documented:
   ```bash
   grep 'name="Place"' */doc/*/*.index
   ```
   Extract the `href` attribute:
   ```xml
   <qmltype name="Place" href="qml-qtlocation-place.html" ...>
   ```

3. **Published docs** - URL path = HTML filename
   - [doc.qt.io/qt-6/](https://doc.qt.io/qt-6/) for released
   - [doc-snapshots.qt.io/qt6-dev/](https://doc-snapshots.qt.io/qt6-dev/) for dev

4. **Local build output**
   ```bash
   ls <module>/doc/<submodule>/*.html | grep <type>
   ```

5. **For NEW documentation (no index entry yet)**
   Apply the QDoc filename algorithm from skill-qdoc-output:
   - C++ class: lowercase class name → `{classname}.html`
   - QML type: `qml-{module}-{type}.html` (all lowercase)
   - Module: `{module}-module.html` or `{module}-qmlmodule.html`
   - Source: `generator.cpp:fileBase()` (lines 308-376)

   Mark with `(new)` suffix in the Output field.

**Naming patterns (see skill-qdoc-output for full reference):**

| Type | Pattern | Example |
|------|---------|---------|
| C++ class | `{classname}.html` | `qwidget.html` |
| QML type | `qml-{module}-{type}.html` | `qml-qtquick-rectangle.html` |
| QML value type | `qml-{type}.html` | `qml-color.html` |
| C++ module | `{module}-module.html` | `qtcore-module.html` |
| QML module | `{module}-qmlmodule.html` | `qtquick-qmlmodule.html` |
| Group | `{groupname}.html` | `animation.html` |
| Example | `{project}-{name}-example.html` | `qtbase-calculator-example.html` |
| Page | per `\page` command | `getting-started.html` |

**Examples:**
```markdown
**Output:** `qml-qtlocation-place.html`              (existing QML type)
**Output:** `qml-qt-labs-stylekit-theme.html` (new)  (new QML type)
**Output:** `mapviewer-example.html`                 (existing example)
```

**When to include:**
- QML type/class documentation edits - include if verified
- Page documentation edits - include if verified
- New type/class/page documentation - include with `(new)` suffix
- **Cannot verify** - omit (do not guess)

## Cause

**Purpose:** Explain WHY the issue occurs and show evidence from your investigation.

**Placement:** After the diff block.

**Include:**
- Why the warning/issue occurs
- What you searched for (grep, index files)
- What you found that confirms your diagnosis

**Examples:**
```markdown
**Cause:** `SamplerHint` is a nested enum in `QQuick3DTextureProviderExtension` and requires full qualification. Searched `grep 'name="SamplerHint"'` in index files — not found at top level, only under parent class.

**Cause:** The `\fn` signature uses `AttachmentSelector` but QDoc expects `QSSGFrameData::AttachmentSelector`. Verified in header: `enum class AttachmentSelector` is declared inside `QSSGFrameData`.

**Cause:** Uses "via" which is a Latin term. Per R38, use "through", "using", or "with" instead.
```

## Fix Options

**Purpose:** Present multiple valid solutions when there's genuinely no single correct answer.

**IMPORTANT: Search codebase first.** Before presenting options, grep for existing usage patterns. If the codebase already has an established pattern, consistency, or best practice that indicates one correct solution, recommend that solution directly WITHOUT presenting Fix Options.

**When to use Fix Options:**
- Multiple genuinely equivalent solutions exist AND no existing codebase pattern
- Internal API links where no established convention exists
- Style choices where the codebase is inconsistent
- Architectural decisions requiring human judgment

**When NOT to use Fix Options:**
- Existing codebase usage clearly shows one pattern (grep first!)
- Qt documentation best practices specify one approach
- One option is objectively better (working link vs broken link)
- Consistency with surrounding code dictates the answer

**Format:**
```markdown
**Fix Options:**
1. **Fully qualify** - Use `QSSGFrameData::AttachmentSelector` in `\fn`
2. **Use typedef** - Create a typedef at namespace scope
3. **Simplify signature** - Remove the parameter from docs

**Recommended:** Option 1 because it matches the actual function signature.
```

**Approval prompt for options:**
```
Which option should I apply? (1/2/3 or skip)
```

## Exemptions and Informational Notes

**Purpose:** Separate actionable suggestions from informational observations.

**Rule:** Only actionable fixes get numbered as "Suggestion N of X". Exemptions and observations go in a separate **Notes** section at the end of the review.

**What goes in Notes (not numbered):**
- Legal text exemptions (R57)
- Content that was reviewed but found correct
- Observations that don't require changes
- Context about patterns found in the file

**Format:**
```markdown
## Notes

**Legal Text (lines 79-86):** Exempt from style review per R57. No changes suggested.

**Line Length:** All prose lines within advisory threshold. No issues.
```

**Wrong (numbered as suggestion):**
```markdown
**Suggestion 4 of 5 for file.qdoc:79:**

**Category:** Legal Text - Exempt
...
**Decision:** EXEMPT - No changes suggested.
```

**Correct (in Notes section):**
```markdown
**Suggestion 3 of 4 for file.qdoc:43:**
... [actionable fix] ...

---

## Notes

**Legal Text (lines 79-86):** Exempt per R57. The "General Legal Disclaimer" section uses standard legal boilerplate that should not be modified without legal counsel.
```

**Counting:** Only count actionable suggestions in "N of X". If you have 4 actionable fixes and 1 exemption, use "Suggestion N of 4" (not "N of 5").

## Line Alignment

**Arrow (`→`) is the fixed anchor.** All lines align to keep arrows in the same column.

**Purpose:** The aligned arrows create a visual column marking where file content begins. This lets readers:
- Instantly see where code/text starts on every line
- Compare before/after content without eye-jumping
- Scan the diff block like reading the actual file

### Rules

**Arrow position = line number width + 5**
- 2-digit → position 7
- 3-digit → position 8
- 4-digit → position 9

**Formats (3-digit example):**
- Context: `    122→content` (4 spaces + number + arrow)
- Deleted: `  - 123→content` (2 spaces + minus + space + number + arrow)
- Added: `  +    →content` (2 spaces + plus + space + 3 spaces + arrow)

**Key:** Added lines replace the line number with spaces to keep arrow aligned. For 2-digit lines use 2 spaces after `+ `; for 3-digit use 3 spaces; for 4-digit use 4 spaces.

### Examples

**2-digit (arrow at position 7):**
```diff
    40→content
  - 42→deleted
  +   →added
```

**4-digit (arrow at position 9):**
```diff
     1097→content
  - 1098→deleted
  +     →added
```

## Change Types

**Addition:**
```diff
    22→Q_QML_DEBUG_PLUGIN_LOADER(Adapter)
  +   →/*!
  +   →    \class QQmlProfilerServiceImpl
  +   →    \inmodule QtQml
  +   →*/
    23→QQmlProfilerServiceImpl::QQmlProfilerServiceImpl() :
```

**Replacement:**
```diff
    40→    \section1 Basic Style
  - 42→    \image qtquickcontrols-basic-thumbnail.png
  +   →    \image qtquickcontrols-basic-thumbnail.png
  +   →           {Gallery of controls in Basic style}
    43→
```

## Validation

**Purpose:** Show your work — what you checked and verified before suggesting the fix.

**The agent fills this field.** Include only relevant checks for the specific change.

### Keywords

**Language:**
- Active voice: "function removes" (not "is removed")
- Present tense: "returns" (not "will return")
- Concise: Under 100 characters
- Generic terms: "button" (not "QPushButton")
- Clear: Subject and action explicit

**Alt text:**
- Descriptive: Page topic + element
- Capitalization: Starts with capital
- No punctuation: No ending period
- Indentation: 7 spaces under \image

**QDoc:**
- QDoc syntax: \class, \inmodule, \internal valid
- Module: Verified (use skill-module-export)
- Internal: No export macro

**Formatting:**
- Line length: Within 80-column limit
- Indentation: 4 spaces
- Spacing: No blank line after */

### Examples

**Simple (4 checks):**
```markdown
**Validation:**
- ✓ Descriptive: "Gallery of controls in Basic style"
- ✓ Generic terms: "controls" (not "QQuickControls")
- ✓ Indentation: 7 spaces under \image
- ✓ Line length: 62 characters (within 80-column limit)
```

**Complex (6 checks):**
```markdown
**Validation:**
- ✓ Active voice: "method returns" (changed from "is returned")
- ✓ Present tense: "returns"
- ✓ Clear: Subject and action explicit
- ✓ Concise: Reduced from 28 to 22 characters
- ✓ Generic terms: "method" (not "QObject::method")
- ✓ Line length: 67 characters (within 80-column limit)
```

**With issue:**
```markdown
**Validation:**
- ✓ Descriptive: Page topic + element
- ✗ Class names: Uses "QLineEdit" (should be "text field")
- ✓ Indentation: 7 spaces
- ✓ Line length: 58 characters (within limit)
```

## Comments

**Purpose:** Additional notes, context, or explanation from the agent.

**Format:** 1-2 sentences. Can include why the change matters, alternatives considered, or follow-up suggestions.

**Examples:**
```markdown
**Comments:** Resolves QDoc warning. Consider also adding \since tag.

**Comments:** Active voice is clearer per Microsoft Style Guide.

**Comments:** Alt text improves accessibility for screen reader users.

**Comments:** This pattern is used 15+ times elsewhere in qtbase.
```

## Approval

**Always use exactly:**
```
Should I apply this fix to the file?
```

**Responses:**
- "yes", "y", "ok", "apply" → Apply with Edit tool
- "no", "n", "skip" → Skip
- "modify", "change" → Revise suggestion

## Complete Example

### Standard Fix (single solution)

```markdown
**Suggestion 3 of 7 for qtquickcontrols-basic.qdoc:42:**

**Warning:** `\image is without a textual description`
**Category:** Missing Alt Text
**Source:** `qtquickcontrols/src/quickcontrols/doc/src/qtquickcontrols-basic.qdoc`

```diff
    40→    \section1 Basic Style
    41→
  - 42→    \image qtquickcontrols-basic-thumbnail.png
  +   →    \image qtquickcontrols-basic-thumbnail.png
  +   →           {Gallery of controls in Basic style}
    43→
    44→    The Basic style is a simple and lightweight style.
```

**Validation:**
- ✗ Alt text: Missing (required for accessibility per QUIP 21, R24)
- ✓ Descriptive: Page topic + element (R25)
- ✓ Generic terms: "controls" (not "QQuickControls") (R26)
- ✓ Capitalization: Starts with capital (R24)
- ✓ No punctuation: No ending period (R24)
- ✓ Indentation: 7 spaces under \image
- ✓ Line length: 62 characters (within 80-column limit, R40)

**Comments:** Improves accessibility by describing the gallery of controls for screen reader users.

Should I apply this fix to the file?
```

### QDoc Warning Fix

```markdown
**Suggestion 5 of 12 for qquick3dtextureproviderextension.cpp:56:**

**Warning:** `Can't link to 'SamplerHint'`
**Category:** QDoc Link Error
**Source:** `qtquick3d/src/runtimerender/qquick3dtextureproviderextension.cpp`
**Output:** `qquick3dtextureproviderextension.html`

```diff
    54→    \note This property is only used when using CustomMaterials.
    55→
  - 56→    \sa SamplerHint
  +   →    \sa QQuick3DTextureProviderExtension::SamplerHint
    57→*/
```

**Cause:** `SamplerHint` is an enum class nested inside `QQuick3DTextureProviderExtension`. Searched `grep 'name="SamplerHint"'` — found only under parent class, not at top level. QDoc requires full qualification for nested types.

**Validation:**
- ✓ Link target: `QQuick3DTextureProviderExtension::SamplerHint` exists (verified in header)
- ✓ QDoc syntax: No space before brace (R39)
- ✓ Line length: 54 characters (within 80-column limit)

**Comments:** Resolves QDoc warning by using fully qualified enum name.

Should I apply this fix to the file?
```

### Multiple Fix Options

```markdown
**Suggestion 8 of 12 for qssgrenderextensions.cpp:116:**

**Warning:** `Can't link to 'QSSGRenderGraphObject::Type'`
**Category:** QDoc Link Error
**Source:** `qtquick3d/src/runtimerender/qssgrenderextensions.cpp`

**Cause:** `QSSGRenderGraphObject` is in a private header (`_p.h`). Searched `grep 'name="QSSGRenderGraphObject"'` — not found in index files. No `\class` documentation exists. Links to undocumented types fail.

**Fix Options:**
1. **Use `\c` instead of `\l`** - Render as code without attempting to link
2. **Remove the link** - Rewrite to avoid referencing the internal type
3. **Add documentation** - Create `\class QSSGRenderGraphObject` (if meant to be public API)

**Recommended:** Option 1 because the type is intentionally internal but useful to mention.

```diff
   114→    This function is useful to determine the type of a \a nodeId.
   115→
  -116→    \sa QSSGRenderGraphObject::Type
  +   →    \sa \c{QSSGRenderGraphObject::Type}
   117→*/
```

**Validation:**
- ✓ Internal type: No export macro in header (confirmed internal)
- ✓ QDoc syntax: `\c{}` renders as code without link attempt
- ✓ Line length: 38 characters (within limit)

**Comments:** Preserves type reference for developers while avoiding link to internal API.

Which option should I apply? (1/2/3 or skip)
```

## Special Cases

**Multiple changes close together (<10 lines):** Combine in one diff

**Multiple changes far apart (>20 lines):** Show separately

**File boundaries:**
```diff
  +  →  /*! \file */
     1→#include "header.h"
```

**Skip (no diff needed):**
```markdown
**Analysis Report:**
...
**Decision:** SKIP - Class has Q_QUICK_EXPORT (public API)

---
Moving to next warning...
```

## Suggestion Verification (MANDATORY)

**CRITICAL: Every suggestion must be verified against ALL applicable rules before presenting.**

### Link Verification (BLOCKING for link suggestions)

**Before suggesting `\l` additions or commenting on autolinking:**

Follow the **Reviewer Verification Checklist** in `skill-qdoc/references/link-resolution.md`.

**Key requirement:** Fetch module index and verify target type BEFORE suggesting.
Include verification evidence in Validation field.

**DO NOT present link-related suggestions until index verification is complete.**

### The Problem

Fixes that address one issue often introduce another:
- Fixing passive voice but introducing wordiness
- Fixing wordiness but leaving passive voice
- Fixing grammar but breaking line length
- Fixing one Latin term but missing another in the same sentence

### Verification Process

**Before presenting ANY suggestion:**

1. **Draft the fix** - Write your proposed corrected text
2. **Re-read the ENTIRE corrected sentence/paragraph** - Not just the changed part
3. **Check against ALL applicable rules**:
   - R1: Active voice (no "is/are/was/were [verb]ed", "can be [verb]ed")
   - R2: Conciseness (no "in order to", "provide a way to", etc.)
   - R38: No Latin terms ("via", "e.g.", "i.e.", "etc.")
   - R10: Correct articles ("the", "a", "an")
   - R40: Line length ≤80 columns
   - Grammar: Subject-verb agreement, possessives, etc.
4. **If fix introduces new issues, revise** - Iterate until fully compliant
5. **Only present the final, fully-compliant suggestion**

### Verification Checklist Template

Include this in your working notes (not in final output):

```
DRAFT FIX: "..."
CHECK:
- [ ] R1 Active voice: No passive constructions?
- [ ] R2 Concise: No wordiness patterns?
- [ ] R38 Latin: No via/e.g./i.e./etc.?
- [ ] R10 Articles: Correct article usage?
- [ ] R40 Length: ≤80 columns?
- [ ] Grammar: Correct agreement, possessives?
- [ ] Clear: Readable and unambiguous?

If any check fails → REVISE and re-check
If all checks pass → Present suggestion
```

### Example - WRONG Approach

```
Original: "The data can be also assigned directly"
Fix: "The data can also be assigned directly"  ← Still passive! (R1 violation)
```

Presented without verifying → User catches the error → Trust lost.

### Example - CORRECT Approach

```
Original: "The data can be also assigned directly"
Draft 1: "The data can also be assigned directly"
  CHECK: ✗ R1 - still passive ("can be assigned")
  → REVISE

Draft 2: "You can also assign the data directly"
  CHECK:
  - ✓ R1 Active: "You can assign" is active
  - ✓ R2 Concise: No wordiness
  - ✓ R38 Latin: No Latin terms
  - ✓ R40 Length: 42 chars
  - ✓ Grammar: Correct
  → PRESENT
```

### Domain-Specific Terms

**Before flagging terminology as incorrect, verify it's not a valid technical term:**

- C++ terms: "in-place" (construction), "move semantics", "RAII"
- Qt terms: Check Qt Terms and Concepts (S7)
- QML terms: Check QML Documentation Style (S4)

**Example**: "inplace" or "in-place" is valid C++ terminology (in-place construction, emplace). Do NOT flag as spelling error.

## Common Mistakes

- **Presenting before verifying**: NEVER present a suggestion until link targets are verified in index files. Search index files FIRST, then present with verified Output field.
- **Presenting partial fixes**: NEVER present a fix that addresses one rule but violates another. Verify against ALL rules first.
- No line number in header: Use `for file.cpp:27:` not `for file.cpp:`
- No source field: Include **Source:** for disambiguation (especially in large repos)
- No category: Always include **Category:** line after Path field
- No warning: For QDoc warning fixes, always include the exact **Warning:** text
- No root cause: Explain WHY the warning occurs, not just what to change
- **Unnecessary fix options**: Presenting options when codebase grep shows existing pattern. Search for usage FIRST - if pattern exists, recommend directly without options.
- Missing fix options: When multiple genuinely valid solutions exist AND no existing pattern, present all options
- No context lines: Include 2+ lines before/after
- Wrong indentation: Show exact spacing
- No validation: Always include checks
- Missing rule references: Include (R#) references in validation where applicable
- Vague rationale: Explain specific benefit
- Wrong prompt: Use exact phrasing ("Should I apply..." or "Which option...")
- No syntax highlighting: Always use ` ```diff ` code fence

## Bug Report Verification Output

**When commit references a bug**, include verification in review output.

**Workflow:** See CLAUDE.md "Bug Report Verification Context" for fetch methods (MCP → WebFetch → manual).

**Output format template:**

```markdown
## Bug Report Verification

**Task-number:** {PROJECT}-XXXXX
**Issue:** [Brief description of reported issue]
**Verdict:** ✓ Patch addresses the reported issue

[Or if concerns: ✗ Patch may not address the reported issue + explanation]
```

**If bug tracker inaccessible:** Note "Unable to verify (bug tracker inaccessible)" and proceed with review.

## Alternative Output Formats

The Doc Team diff format (above) is the default and most detailed format. Two
alternative formats are available for specific use cases.

### Gerrit Format

For posting inline comments directly to Gerrit code review. The comment text
goes above the suggestion block as plain text. The suggestion block contains
ONLY the replacement code with original indentation preserved.

**Format:**
```
{Rule}: {Brief explanation of the issue}

```suggestion
    {replacement code with original indentation}
```
```

**Example:**
```
R1: Passive voice "is needed" → active voice.

```suggestion
    The \c update() method returns a timestamp indicating when the engine
    needs the next update, allowing devices to enter sleep modes between
    updates.
```
```

**Rules:**
- No markdown formatting in comment text (Gerrit renders plain text)
- Preserve original indentation in the suggestion block
- Keep explanations brief (one line preferred)
- Suggestion block contains ONLY replacement text, nothing else

### Plain Format

For quick summaries when detailed validation is not needed.

```
Line X: {Issue}. Fix: {replacement}
```

**Example:**
```
Line 42: Passive voice. Fix: "when the engine needs the next update"
Line 58: Missing \c markup. Fix: \c{file://}
```

## Integration

- **skill-qdoc:** QDoc syntax, link resolution, warning diagnosis
- **skill-qdoc-output:** HTML filename patterns by node type
- **skill-language-style:** Rule references (R1-R50) for validation checks
- **skill-alttext:** Alt text formatting and terminology
- **skill-line-wrap:** 80-column validation (R40)
- **skill-module-export:** Public API detection via export macros

**Changelog:** See `CHANGELOG.md`
