---
name: skill-linking-check
description: Reference for checking documentation link integrity after code changes. Covers link target generation, anchor rules, search patterns, and cross-module dependencies.
metadata:
  version: "1.3.0"
---

# Documentation Link Integrity Reference

Reference material for verifying that code changes don't break documentation links.

## When to Use This Skill

This skill activates when:
- Analyzing commits for documentation impact
- Checking if renames break existing links
- Verifying cross-module link integrity
- Predicting QDoc "Can't link to" warnings

## What Generates Link Targets

| Source | Link Target | Link Syntax |
|--------|-------------|-------------|
| `\class ClassName` | `ClassName` | `\l{ClassName}` |
| `\qmltype TypeName` | `TypeName` | `\l{TypeName}`, `\l [QML]{TypeName}` |
| `\fn void Class::method()` | `Class::method()` | `\l{Class::method()}` |
| `\qmlmethod Type::method()` | `Type::method()` | `\l{Type::method()}` |
| `\qmlproperty type Type::prop` | `Type::prop` | `\l{Type::prop}` |
| `\qmlsignal Type::signalName` | `Type::signalName` | `\l{Type::signalName}` |
| `\enum Class::EnumName` | `Class::EnumName` | `\l{Class::EnumName}` |
| `\typedef Class::TypeName` | `Class::TypeName` | `\l{Class::TypeName}` |
| `\property Class::propName` | `Class::propName` | `\l{Class::propName}` |
| `\title Page Title` | `Page Title` | `\l{Page Title}` |
| `\section1 Section Name` | `#section-name` | `\l{Type#Section Name}` |
| `\target custom-anchor` | `#custom-anchor` | `\l{#custom-anchor}` |
| `\keyword Search Term` | `Search Term` | `\l{Search Term}` |
| `\externalpage URL` | External title | `\l{External Title}` |
| `QML_NAMED_ELEMENT(X)` | QML type `X` | `\l{X}`, `\l [QML]{X}` |
| `QML_ELEMENT` | QML type (class name) | `\l{ClassName}` |

## QML Registration Macros

These C++ macros control what QML type names are exposed:

| Macro | Effect | Documentation Impact |
|-------|--------|---------------------|
| `QML_NAMED_ELEMENT(Name)` | Exposes as `Name` in QML | Links use `Name`, not C++ class name |
| `QML_ELEMENT` | Exposes using C++ class name | Links use class name |
| `QML_ANONYMOUS` | No QML name | Cannot link to type |
| `QML_UNCREATABLE(reason)` | Type exists but not creatable | Can still link |
| `QML_SINGLETON` | Singleton type | Can link normally |

**Key insight:** When `QML_NAMED_ELEMENT` changes, ALL documentation links to the old name break.

## Anchor Generation Rules

QDoc converts section titles to anchors:

1. Lowercase all characters
2. Replace spaces with hyphens
3. Remove special characters
4. Collapse multiple hyphens

| Section Title | Generated Anchor |
|---------------|------------------|
| `Basic Usage` | `#basic-usage` |
| `C++ Integration` | `#c-integration` |
| `QML/Qt Quick` | `#qml-qt-quick` |
| `Hosting in Qt GUI` | `#hosting-in-qt-gui` |
| `Step 1: Setup` | `#step-1-setup` |
| `FAQ & Troubleshooting` | `#faq-troubleshooting` |

## Link Syntax Quick Reference

| Target Type | Correct Syntax | Common Mistake |
|-------------|----------------|----------------|
| Class | `\l{QWidget}` | `\l{qwidget.html}` |
| QML type | `\l{Rectangle}` | `\l{QQuickRectangle}` |
| QML type (explicit) | `\l [QML]{Item}` | `\l{Item}` (ambiguous) |
| Member | `\l{QWidget::show()}` | `\l{show()}` |
| QML property | `\l{Item::width}` | `\l{Item.width}` |
| Section in type | `\l{QWidget#Public Functions}` | `\l{qwidget.html#public-functions}` |
| Page by title | `\l{Getting Started}` | `\l{getting-started.html}` |
| Custom target | `\l{#custom-anchor}` | Works if `\target custom-anchor` exists |

## Search Patterns for References

### QDoc Link Commands

**Note:** `\l` and `\sa` use the same link resolution mechanism (`findNodeForAtom()`).
Both commands will break if a target is renamed or removed.

```bash
# \l links to a name
grep -rn "\\\\l.*{.*TargetName" --include="*.qdoc" --include="*.cpp" qt*/

# \l with QML genus
grep -rn "\\\\l \[QML\].*{.*TargetName" --include="*.qdoc" qt*/

# \l with display text
grep -rn "\\\\l.*{.*TargetName.*}" --include="*.qdoc" qt*/
```

### \sa (See Also) References

**See also:** skill-qdoc/references/link-resolution.md for comprehensive `\sa` syntax,
parsing details, and resolution behavior.

`\sa` creates comma-separated link lists in "See also" sections. Search for these
separately because the syntax differs from `\l`.

```bash
# Basic \sa search (target anywhere in line)
grep -rn "\\\\sa.*TargetName" --include="*.qdoc" --include="*.cpp" qt*/

# \sa with braced target (for targets with spaces)
grep -rn "\\\\sa.*{.*TargetName" --include="*.qdoc" --include="*.cpp" qt*/

# \sa at start of target list
grep -rn "\\\\sa TargetName" --include="*.qdoc" --include="*.cpp" qt*/

# \sa with target in middle of list (after comma)
grep -rn "\\\\sa.*, *TargetName" --include="*.qdoc" --include="*.cpp" qt*/
```

**`\sa` syntax variations to search for:**

| Pattern | Matches |
|---------|---------|
| `\sa TargetName` | First item, no braces |
| `\sa {TargetName}` | First item, with braces |
| `\sa OtherThing, TargetName` | After comma |
| `\sa {Other Thing}, {TargetName}` | Braced after comma |
| `\sa {Class::}{TargetName()}` | C++ member shorthand |

### QDoc Topic Commands

```bash
# \class documentation
grep -rn "\\\\class.*ClassName" --include="*.cpp" --include="*.qdoc" qt*/

# \qmltype documentation
grep -rn "\\\\qmltype.*TypeName" --include="*.cpp" --include="*.qdoc" qt*/

# \fn documentation
grep -rn "\\\\fn.*functionName" --include="*.cpp" qt*/
```

### Code References

```bash
# QML_NAMED_ELEMENT usage
grep -rn "QML_NAMED_ELEMENT(.*TypeName" --include="*.h" qt*/

# Include/snippet paths
grep -rn "\\\\snippet.*filename" --include="*.qdoc" --include="*.cpp" qt*/
grep -rn "\\\\include.*filename" --include="*.qdoc" qt*/
```

### Index File Searches

```bash
# Local index files
grep 'name="TargetName"' */doc/*/*.index

# Check if target is internal
grep -A2 'name="TargetName"' */doc/*/*.index | grep 'status="internal"'

# Get href for Output field
grep 'name="TargetName"' */doc/*/*.index | grep -o 'href="[^"]*"'
```

### Online Index Files

Available at `https://doc-snapshots.qt.io/qt6-dev/{module}.index`:

| Module | Index URL |
|--------|-----------|
| QtCore | `qtcore.index` |
| QtGui | `qtgui.index` |
| QtWidgets | `qtwidgets.index` |
| QtQml | `qtqml.index` |
| QtQuick | `qtquick.index` |
| QtQuickControls | `qtquickcontrols.index` |

## Change Types and Impact

### Breaking Changes (Will Cause Warnings)

| Change | Impact | Search Pattern |
|--------|--------|----------------|
| `QML_NAMED_ELEMENT(Old)` → `QML_NAMED_ELEMENT(New)` | All `\l{Old}` links break | `grep "\\\\l.*{.*Old"` |
| Class renamed | `\l{OldClass}`, `\class OldClass` break | `grep "OldClass"` |
| Function removed | `\l{Class::func()}` breaks | `grep "\\\\l.*func"` |
| `\target X` removed | `\l{#X}` breaks | `grep "#X"` |
| `\title X` changed (different words) | `\l{X}` breaks | `grep "\\\\l.*{.*X"` |
| `\externalpage` title changed | `\l{Old Title}` breaks | `grep "\\\\l.*{.*Old Title"` |
| File renamed | `\snippet`, `\include` break | `grep "oldfile"` |

### Cosmetic Changes (Links Survive)

| Change | Why Safe | Action |
|--------|----------|--------|
| `\title X` case-only change | QDoc normalizes targets to lowercase | Update refs for consistency |
| `\target X` case-only change | Same normalization | Update refs for consistency |

### Non-Breaking Changes (Safe)

| Change | Why Safe |
|--------|----------|
| New class/type added | No existing links to break |
| New function added | No existing links to break |
| Implementation changed | Documentation unaffected |
| Private API changed | Not documented (or `\internal`) |

### Potentially Breaking (Check Carefully)

| Change | Risk | Check |
|--------|------|-------|
| Enum value renamed | Medium | Search for `\value OldValue` |
| Parameter renamed | Low | Only affects `\a param` in same file |
| Namespace changed | High | Search for fully qualified names |
| Module renamed | Very High | All cross-module links break |

## Report Template

```markdown
## Link Integrity Check

**Change:** {describe what was renamed/removed/changed}

**Searches Performed:**
- [ ] `\l{}` patterns in *.qdoc, *.cpp
- [ ] `\sa` references
- [ ] Index file search (local)
- [ ] Index file search (online)
- [ ] Cross-module dependency check

**Findings:**

| Location | Reference | Status |
|----------|-----------|--------|
| `file.qdoc:22` | `\l{OldName}` | BROKEN |
| `other.qdoc:45` | `\sa OldName` | BROKEN |

**Result:** {N issues found / No issues}

**Required Updates:**
1. `file.qdoc:22` - Change `\l{OldName}` to `\l{NewName}`
2. `other.qdoc:45` - Change `\sa OldName` to `\sa NewName`
```

## Special Cases

### New Content

If the change ADDS a new class/type/page (not modifying existing):
- No existing links can be broken
- Report: "New content - no existing links possible"

### Internal APIs

If the changed item is marked `\internal`:
- External documentation should not link to it
- If links exist, they're already bugs
- Report: "Internal API - external links would already be broken"

### Deprecated APIs

If the changed item is marked `\deprecated`:
- Links may exist but content is being phased out
- Lower priority to fix
- Report: "Deprecated API - consider removing references"

### Case Sensitivity

QDoc normalizes all target keys to lowercase ASCII via
`asAsciiPrintable()` (utilities.cpp:157-197). This means:

- `\l{Foo}`, `\l{foo}`, and `\l{FOO}` all resolve to the same target
- `\l{Supported Platforms}` resolves identically to `\l{Supported platforms}`
- Section anchors: Also case-insensitive (same normalization)
- QML types: Also case-insensitive for resolution (but conventionally PascalCase)

**Impact on renames:** A case-only title rename (e.g., `\title Supported
Platforms` to `\title Supported platforms`) does NOT break links. However,
references should still be updated for consistency — categorize as
**Cosmetic**, not Breaking.

**What IS case-sensitive:** The `\l` display text (the part the reader
sees) is rendered as-is. Only the link target lookup is normalized.

### Silent Misdirection (No Warning)

When a `\title` or `\class` is renamed but another module retains a
`\target` or `\keyword` with the same normalized name, QDoc resolves
orphaned links to that surviving definition. This produces **no warning**
— the link appears to work but points to the wrong page.

QDoc's ambiguity detection (tree.cpp:1059-1090) only checks for duplicate
page titles **within the same tree**. Cross-module conflicts are not
detected. The `findUnambiguousTarget()` function returns the first/best
match by priority without warning about cross-module duplicates.

**Detection:** After identifying a rename, search all index files and
source for any other definition of the old name:

```bash
grep 'title="OldName"' */doc/*/*.index
grep -rn "\\\\target.*OldName" --include="*.qdoc" qt*/
grep -rn "\\\\keyword.*OldName" --include="*.qdoc" qt*/
```

**Severity:** Always **Breaking**, even though QDoc produces no warning.
Silent misdirection is harder to detect than a broken link.

### Keyword and Target Aliases

`\keyword`, `\target`, and `\title` all create link targets that participate
in the same resolution. QDoc assigns priorities (tree.cpp):

| Source | Priority | Wins When |
|--------|----------|-----------|
| `\keyword` | 1 (highest) | Always wins over target/section |
| `\target` | 2 | Wins over section titles |
| Section title (`\section1`) | 3 (lowest) | Only if no keyword/target |

When multiple definitions with the same normalized name exist:
- **Same module:** `findUnambiguousTarget()` picks the lowest priority number
- **Cross-module:** First match found wins — behavior is unpredictable and
  depends on index file load order

**Impact on renames:**

| Scenario | Effect |
|----------|--------|
| Page has `\keyword OldTitle` after title rename | Old links still resolve — backward-compatible |
| Another module has `\target OldTitle` | Orphaned links resolve to wrong page — silent misdirection |
| Two modules define same `\keyword` | QDoc picks based on load order — ambiguous |

**Search for aliases:**

```bash
# Existing aliases for old name (mitigations)
grep -rn "\\\\keyword.*OldName" --include="*.qdoc" qt*/
grep -rn "\\\\target.*OldName" --include="*.qdoc" qt*/

# Existing definitions for new name (conflicts)
grep -rn "\\\\keyword.*NewName" --include="*.qdoc" qt*/
grep -rn "\\\\target.*NewName" --include="*.qdoc" qt*/

# Index file check (catches cross-module aliases)
grep 'title="OldName"' */doc/*/*.index
```

### External Pages

`\externalpage` creates an `ExternalPageNode` (inherits `PageNode`) that
participates in normal link resolution. You can link to external pages
with `\l{Title}` just like regular pages.

External page definitions are often collected in a single file
(e.g., `external-resources.qdoc`). A title change there breaks every
`\l{Title}` that references it across all modules.

```bash
# Search for references to an external page title
grep -rn "\\\\l.*{.*Old External Title" --include="*.qdoc" qt*/

# Find all \externalpage definitions
grep -rn "\\\\externalpage" --include="*.qdoc" qt*/
```

## Cross-Module Dependencies

Qt modules declare dependencies in qdocconf:

```qdocconf
depends = QtCore QtGui QtWidgets
```

When module A declares `depends = B C`, QDoc loads `B.index` and `C.index`
into shared target maps (qdocdatabase.cpp:1316-1327). All targets from B
and C become resolvable from A's documentation via `\l`.

### Dependency Direction

| Direction | Risk | Detection |
|-----------|------|-----------|
| **Downstream** (Y depends on X) | Y's `\l{OldName}` breaks if X renames | Grep Y's sources for old name |
| **Upstream** (X depends on Z) | Z's `\target OldName` silently captures orphaned links from X | Grep Z's index for old name |

**Upstream conflicts are more dangerous** because they produce no QDoc
warning — see "Silent Misdirection" above. Always check both directions
for renames.

```bash
# Downstream: find modules that depend on the changed module
grep -rl "depends.*ChangedModule" qt*/src/*/doc/*.qdocconf

# Upstream: find what the changed module depends on
grep "depends" {changed-module}/src/*/doc/*.qdocconf

# For each dependency, check if it defines the old name
grep 'title="OldName"' */doc/{dependency}/{dependency}.index
```

### Common Dependency Chains

```
qtbase (QtCore, QtGui, QtWidgets)
    ↓
qtdeclarative (QtQml, QtQuick)
    ↓
qtquickcontrols
    ↓
qtdoc (links to everything)
```

### High-Impact Modules

| Module | Risk | Reason |
|--------|------|--------|
| qtbase | High | Foundation, many dependents |
| qtdeclarative | High | QML types widely referenced |
| qtdoc | Medium | Overview docs, cross-links |

## Integration

- **skill-qdoc:** Link resolution details, node system
- **skill-doc-diff:** Output format for fixes
- **skill-all-docs:** Module and repository information

---

## Version History

- **v1.3** (2026-04-10): QDoc source-verified resolution behavior
  - Fixed case sensitivity: QDoc normalizes targets to lowercase
    (utilities.cpp:157-197). Case-only renames are Cosmetic, not Breaking.
  - Added "Silent Misdirection" section: cross-module target conflicts
    produce no QDoc warning (tree.cpp ambiguity check is same-tree only)
  - Added "Keyword and Target Aliases" section: priority system
    (keyword=1, target=2, section=3) and conflict detection
  - Added "External Pages" section: `\externalpage` creates linkable
    `PageNode`, title changes break `\l{Title}` references
  - Rewrote "Cross-Module Dependencies" with dependency direction
    (downstream vs upstream) and conflict detection searches
  - Added "Cosmetic Changes" table for case-only renames

- **v1.2** (2026-03-12): Added cross-references to reduce duplication
  - Added reference to skill-qdoc/references/link-resolution.md for `\sa` details

- **v1.1** (2026-03-12): Enhanced `\sa` documentation
  - Added note that `\l` and `\sa` use same resolution mechanism
  - Expanded `\sa` search patterns section with syntax variations
  - Added table of `\sa` syntax patterns to search for

- **v1.0** (initial): Link integrity reference with search patterns
