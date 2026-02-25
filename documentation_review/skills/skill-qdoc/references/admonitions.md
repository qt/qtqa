# QDoc Admonitions Reference

**Source:** `qttools/src/qdoc/qdoc/src/qdoc/docparser.cpp`
**Source:** `qttools/src/qdoc/qdoc/doc/qdoc-manual-markupcmds.qdoc`

This reference documents QDoc block-level admonition commands (`\note`, `\warning`,
`\important`), their purposes, when to use them, and anti-patterns to avoid.

## Why Admonitions Exist

**Admonitions interrupt reading flow intentionally.** They signal to readers:
"Stop scanning—this information deserves your attention."

| Command | Signals to reader |
|---------|-------------------|
| `\note` | "This is supplementary but worth knowing" |
| `\warning` | "This could cause serious problems if ignored" |
| `\important` | "This is critical information" |

**Industry standards (ANSI Z535.6, Google, Microsoft) agree:** Admonitions must be
used sparingly and reserved for genuinely noteworthy content. Overuse trains
readers to skip them, defeating their purpose.

---

## Command Reference

### `\note`

**Source:** docparser.cpp:738-741, qdoc-manual-markupcmds.qdoc:2440-2450

Defines a paragraph preceded by "Note:" in bold.

**Syntax:**
```qdoc
\note This is supplementary information worth highlighting.
```

**HTML output:**
```html
<div class="admonition note">
<p><b>Note: </b>This is supplementary information worth highlighting.</p>
</div>
```

**QDoc Manual guidance:**
> "The note command is only for shorter statements and not for longer multiline
> paragraphs. Similar to the `\warning` command, the note is for short and
> important statements."

---

### `\warning`

**Source:** docparser.cpp:1088-1091, qdoc-manual-markupcmds.qdoc:2644-2658

Prepends "Warning:" to the content in bold.

**Syntax:**
```qdoc
\warning Using this type is not portable.
```

**HTML output:**
```html
<div class="admonition warning">
<p><b>Warning: </b>Using this type is not portable.</p>
</div>
```

**Use for:**
- Potential crashes or undefined behavior
- Thread safety violations
- Non-portable code
- Data loss or security risks
- Violations of expected behavior

---

### `\important`

**Source:** docparser.cpp:645-648

Similar to `\note` but generates "Important:" prefix. Rarely used in Qt (1 instance
in qtbase).

**Syntax:**
```qdoc
\important These changes impact the stability of references.
```

---

## When to Use Admonitions

### Use `\note` When ALL Three Conditions Apply

1. **Information is relevant but not essential** — Reader can succeed without it
2. **Interrupting is justified** — Content is noteworthy enough to break flow
3. **Content falls outside main text flow** — Doesn't fit naturally in prose

**Good candidates for `\note`:**
- Platform-specific behavior differences
- Version-specific context (not deprecation—use `\deprecated`)
- Non-obvious clarifications about edge cases
- Performance considerations
- Environment or configuration notes

### Use `\warning` When

- **Serious consequences** — Ignoring leads to crashes, data loss, security issues
- **Non-obvious danger** — Reader wouldn't naturally expect the risk
- **Actionable** — Reader can do something to avoid the problem

**Good candidates for `\warning`:**
- Thread safety violations
- Memory management pitfalls
- Portability issues
- API misuse that causes undefined behavior
- Irreversible operations

---

## When NOT to Use Admonitions

### Do NOT Use `\note` For

| Content Type | Why Not | Use Instead |
|--------------|---------|-------------|
| Prerequisites | Essential, not supplementary | Regular prose before the action |
| Return values | Essential API contract | Integrate into description |
| Error conditions | Essential behavior | Integrate into description |
| Cross-references | Not noteworthy | `\sa` command |
| Obvious information | Wastes reader attention | Omit or integrate |
| Long explanations | Notes must be brief | Dedicated section |

### Do NOT Use `\warning` For

| Content Type | Why Not | Use Instead |
|--------------|---------|-------------|
| Default values | Not dangerous | Regular prose or `\note` |
| Minor caveats | Dilutes warning severity | Regular prose or `\note` |
| Style preferences | Not a consequence | Regular prose |

---

## Anti-Patterns

### Anti-Pattern 1: Clustered Admonitions

**Definition:** Two or more `\note`/`\warning` commands adjacent without intervening prose.

**Clustering detection criteria:**

| Between admonitions | Counts as separation? |
|---------------------|----------------------|
| Nothing (truly adjacent) | NO - clustered |
| Whitespace/blank lines only | NO - clustered |
| Section heading (`\section1`, `\section2`) | YES - separated |
| Prose paragraph (1+ sentences) | YES - separated |
| Code block (`\code`, `\snippet`) | YES - separated |
| List (`\list`) | YES - separated |
| Table (`\table`) | YES - separated |

**Key point:** Blank lines between admonitions do NOT prevent clustering. Only substantive
content (prose, code, sections) separates admonitions.

**Example - CLUSTERED (blank lines don't separate):**
```qdoc
\note All configurations are not provided as binary packages.

\note Linux packages are linked against glibc 2.34.
```
These are clustered because only whitespace separates them.

**Example - NOT CLUSTERED (prose separates):**
```qdoc
\note Some platforms require commercial licenses.

For a complete list of supported configurations, see the tables below.

\note Linux packages are linked against glibc 2.34.
```
These are NOT clustered because prose separates them.

**Example (Bad):**
```qdoc
\note On Windows, the path separator is backslash.

\note On macOS, the path separator is forward slash.

\note On Linux, the path separator is forward slash.
```

**Why problematic:**
- Visual noise—readers skip "walls of warnings"
- Diluted importance—if everything is a note, nothing is noteworthy
- Cognitive overload—multiple context switches
- Scanning failure—specific notes get lost

**Industry source:** Google Style Guide: "Never place two admonitions next to each other."

**Fixes:**

Option A — Combine into single note:
```qdoc
\note Path separators are platform-specific:
\list
\li Windows: backslash (\\)
\li macOS and Linux: forward slash (/)
\endlist
```

Option B — Create dedicated section:
```qdoc
\section2 Platform-Specific Behavior

The path separator varies by platform: backslash (\\) on Windows,
forward slash (/) on macOS and Linux.
```

Option C — Integrate into prose:
```qdoc
The path separator is platform-specific: backslash (\\) on Windows,
forward slash (/) on macOS and Linux.
```

**Detection:** Adjacent `\note`, `\warning`, or `\important` commands.

---

### Anti-Pattern 2: Long/Multiline Notes

**Definition:** A `\note` or `\warning` containing multiple sentences, multiple
paragraphs, or content exceeding ~2-3 rendered lines.

**Example (Bad):**
```qdoc
\note When using this function on Android, you must first ensure that the
appropriate permissions have been granted in the AndroidManifest.xml file.
Additionally, the function may behave differently depending on the Android
API level. On API level 23 and above, runtime permissions are required,
which means you must call checkSelfPermission() before invoking this
function. If the permission is not granted, the function will return an
error code. You should handle this error gracefully by prompting the user
to grant the permission through the system dialog.
```

**Why problematic:**
- QDoc Manual explicitly prohibits: "only for shorter statements"
- Defeats scannability—notes should be glanceable
- Buried information—critical details lost in lengthy text
- Wrong tool—extended explanations belong in sections

**Fixes:**

Option A — Extract to section:
```qdoc
\section2 Android Permissions

When using this function on Android, ensure appropriate permissions
are granted in AndroidManifest.xml.

On API level 23+, runtime permissions are required. Call
checkSelfPermission() before invoking this function.
```

Option B — Shorten to essential point:
```qdoc
\note On Android API 23+, requires runtime permissions.
See \l{Android Permissions} for details.
```

**Detection:**
- Content exceeds ~50 words
- More than 2 sentences
- Contains list structures
- Spans more than 3 source lines

---

### Anti-Pattern 3: Notes Containing Prerequisites

**Definition:** Using `\note` for information the reader MUST know BEFORE
performing an action.

**Example (Bad):**
```qdoc
Call the initialize() function to set up the connection.

\note You must call configure() before calling initialize().
```

**Why problematic:**
- Wrong placement—prerequisites come BEFORE actions, not after
- Reader may have already acted—too late when they see the note
- Notes are skippable—prerequisites are NOT skippable
- Misuse of severity—prerequisites are essential, not supplementary

**Industry source:**
- Google: "Do not use notes for prerequisites or prior steps."
- ANSI Z535.6: "Place safety messages BEFORE the instruction."

**Fixes:**

Option A — Reorder as prose:
```qdoc
Before calling initialize(), call configure() to set the required
parameters.

Call initialize() to set up the connection.
```

Option B — Use numbered steps:
```qdoc
To set up the connection:
\list 1
\li Call configure() to set the required parameters.
\li Call initialize() to establish the connection.
\endlist
```

**Detection:**
- `\note` contains "must ... before"
- `\note` contains "requires" + action verb
- `\note` contains "first" or "prior to"
- `\note` appears AFTER an instruction it modifies

---

### Anti-Pattern 4: Notes Containing Essential Information

**Definition:** Using `\note` for information required for reader success—
information they cannot skip.

**Example (Bad):**
```qdoc
Returns the user's home directory path.

\note Returns an empty string if the home directory cannot be determined.
```

**Why problematic:**
- Notes are semantically "skippable"—signals optional reading
- Return value behavior is essential—readers MUST know edge cases
- Breaks API contract clarity—critical behavior in "supplementary" callout

**Industry source:** Google: "Do not use notes for information essential to
reader success."

**What makes information essential:**
- Return values and their meanings
- Error conditions and handling
- Required parameters or configurations
- Behavior differing from reasonable expectations
- Side effects affecting program state

**Fixes:**

Option A — Integrate into description:
```qdoc
Returns the user's home directory path, or an empty string if the
home directory cannot be determined.
```

Option B — Explicit edge case:
```qdoc
Returns the user's home directory path.

If the home directory cannot be determined (for example, on a system
without user directories), returns an empty string.
```

**Detection:**
- `\note` describes return values ("returns", "Returns")
- `\note` describes error conditions ("throws", "emits", "fails")
- `\note` describes edge cases ("if...then")

---

### Anti-Pattern 5: Note as Cross-Reference

**Definition:** Using `\note` solely to point to related content.

**Example (Bad):**
```qdoc
\note See also QWidget::show().
```

**Why problematic:** Cross-references are not noteworthy—use the dedicated command.

**Fix:**
```qdoc
\sa QWidget::show()
```

---

### Anti-Pattern 6: Note Stating the Obvious

**Definition:** Using `\note` for information already conveyed by the function
name, brief, or surrounding context.

**Example (Bad):**
```qdoc
/*!
    \fn int QWidget::width() const
    \brief Returns the width of the widget.

    \note This function returns the width of the widget.
*/
```

**Why problematic:** Wastes reader attention; trains them to skip notes.

**Fix:** Remove the note entirely.

---

### Anti-Pattern 7: Warning for Non-Critical Issues

**Definition:** Using `\warning` when consequences are not serious.

**Example (Bad):**
```qdoc
\warning The default value is 0.
```

**Why problematic:** Dilutes warning severity; readers will ignore real warnings.

**Fix:** Use regular prose or `\note` if truly noteworthy:
```qdoc
The default value is \c 0.
```

---

### Anti-Pattern 8: Note Restating Prose

**Definition:** Using `\note` to repeat or summarize what was just said.

**Example (Bad):**
```qdoc
The widget must be visible before calling this function.

\note Make sure the widget is visible first.
```

**Why problematic:** Redundant; adds noise without new information.

**Fix:** Remove the note—the prose already conveys the requirement.

---

## Decision Tree

```
Is the information...
│
├─ Required for reader success (return values, prerequisites, errors)?
│   └─ NO → Do not use \note. Integrate into prose.
│
├─ About serious consequences (crashes, data loss, security)?
│   └─ YES → Use \warning
│   └─ NO → Continue...
│
├─ Supplementary but genuinely noteworthy?
│   └─ YES → Continue...
│   └─ NO → Do not use \note. Integrate or omit.
│
├─ Short (1-2 sentences, <50 words)?
│   └─ YES → Use \note
│   └─ NO → Create dedicated section instead
│
└─ Already have a \note nearby?
    └─ YES → Combine or create section
    └─ NO → Use \note
```

---

## Usage Statistics (qtbase)

| Command | Count | Percentage |
|---------|-------|------------|
| `\note` | ~302 | 84% |
| `\warning` | ~58 | 16% |
| `\important` | 1 | <1% |

**Ratio:** Approximately 5:1 notes to warnings. This aligns with the principle
that warnings are reserved for serious consequences.

---

## Industry Standards Alignment

### ANSI Z535.6 (Product Safety Information)

Defines severity hierarchy for manuals:
- DANGER → WARNING → CAUTION → NOTICE

Qt's `\warning` maps to WARNING/CAUTION; `\note` maps to NOTICE.

### Google Developer Documentation Style Guide

> "When to use Note: All three conditions must apply:
> - Information is relevant but unnecessary for reader success
> - Interrupting doesn't obstruct their path forward
> - Content falls outside main text flow"

### Microsoft Writing Style Guide

> "Keep the number of notes to a minimum."

### Cognitive Load Research

> "When you overuse special statements, they are ignored."

> "Too many callouts can distract readers and make topics hard to scan."

The "cry wolf" effect: Excessive admonitions train readers to skip them.

---

## Reviewer Checklist

When reviewing documentation, check for:

- [ ] **Clustered admonitions** — Two or more adjacent `\note`/`\warning`
- [ ] **Long notes** — More than ~50 words or 2 sentences
- [ ] **Prerequisites in notes** — "must...before", "requires", "first"
- [ ] **Essential info in notes** — Return values, errors, edge cases
- [ ] **Cross-references in notes** — Should use `\sa`
- [ ] **Obvious statements** — Already conveyed by name/brief
- [ ] **Weak warnings** — Non-serious issues using `\warning`
- [ ] **Redundant notes** — Restating prose

---

## Version History

- **v1.1** (2026-02-23): Added clustering detection criteria table clarifying that
  whitespace alone does not separate admonitions; only prose, sections, code, lists,
  or tables count as separation
- **v1.0** (2026-02-23): Initial version with command reference, usage guidance,
  8 anti-patterns, decision tree, industry standards alignment
