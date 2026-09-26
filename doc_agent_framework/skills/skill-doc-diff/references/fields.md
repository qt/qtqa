# Doc Team diff fields

Back to [`skill-doc-diff`](../SKILL.md).

## Header and Source

- Header: `**Suggestion N of X for {basename}:{line}:**`. The basename keeps
  the header short. `{line}` is the first changed line.
- Source: `**Source:** \`{path/from/repo/root}\``. It resolves files with
  the same basename and can be pasted into an editor.
- Use "File N of X" instead when a review walks through several files.

`tools/doc-diff/render_record.py` writes both.

## Category

The issue type. Common values: QDoc Syntax, QDoc Link Error, Missing Alt
Text, Insufficient Alt Text, Grammar, Language, 80-Column Violation,
Empty Section, Character Encoding, Inconsistent Capitalization, Missing
Documentation. Combine with `+` when one suggestion fixes two issues
(`80-Column Violation + Inconsistent Capitalization`).

## Warning

The QDoc warning text, verbatim, in backticks. Copy it from the log; QDoc
Manual section titles are paraphrases and don't match the log. Strings
at qttools `cff41040`:

| Warning | Source |
|---------|--------|
| `Can't link to '%1'` | htmlgenerator.cpp:892 |
| `Failed to find function when parsing \fn %1` | parsererror.cpp:89 |
| `Cannot tie this documentation to anything` | clangcodeparser.cpp:2434 |
| `No output generated for %1 '%2' because '%3' is undocumented` | aggregate.cpp:297 |
| `No documentation for %1 '%2'` | generator.cpp:729 |
| `Missing image: %1` | htmlgenerator.cpp:805 |
| `Output file already exists, overwriting %1` | generator.cpp:267 |
| `\%1 %2 is without a textual description, QDoc will not generate an alt text for the image.` | docparser.cpp:1829; a report, not a warning, and only with `reportmissingalttextforimages = true` |

Full list: skill-qdoc, "Warning → reference".

## Output

The rendered page where the edited text appears, so the reviewer can check
the fix on doc.qt.io or doc-snapshots.qt.io.

- Editing the Place QML type docs → `qml-qtlocation-place.html`. It is
  **not** the page a fixed `\l` points to.
- New page (`\class`, `\qmltype`, `\page` added): add `(new)`.
- **Can't verify → omit the field.** It must never be wrong.

How to find it:

1. `\page` docs: the filename is the `\page` argument (`\page sbom.html`).
2. Types: `grep 'name="Place"'` in the `.index` files and take `href`.
3. Published docs: the URL path is the filename
   (https://doc.qt.io/qt-6/, https://doc-snapshots.qt.io/qt6-dev/).
4. Local build: `ls <module>/doc/<submodule>/` for the type.
5. New docs with no index entry: the skill-qdoc-output algorithm
   (`Generator::fileBase()`, generator.cpp:309 at cff41040), then `(new)`.

| Type | Pattern | Example |
|------|---------|---------|
| C++ class | `{classname}.html` | `qwidget.html` |
| QML type | `qml-{module}-{type}.html` | `qml-qtquick-rectangle.html` |
| QML value type | `qml-{type}.html` | `qml-color.html` |
| C++ module | `{module}-module.html` | `qtcore-module.html` |
| QML module | `{module}-qmlmodule.html` | `qtquick-qmlmodule.html` |
| Group | `{groupname}.html` | `animation.html` |
| Example | `{project}-{name}-example.html` | `qtbase-calculator-example.html` |
| Page | the `\page` argument | `getting-started.html` |

Dots and other non-alphanumeric characters become hyphens
(`asAsciiPrintable()`); see skill-qdoc-output.

## Cause

After the diff. Why the issue happens, what you searched, and what you
found. Quote tool output (index grep, header line, `git tag --contains`).

- ✅ `SamplerHint` is an enum nested in `QQuick3DTextureProviderExtension`.
  `grep 'name="SamplerHint"'` finds it only under that class.
- ❌ The link is broken. (No reason, no evidence.)

## Fix Options

Only when several fixes are equally valid **and** the codebase has no
established pattern. Grep for existing usage first.

Use them for internal-API links with no convention, style choices where the
codebase is inconsistent, and decisions that need a human. Don't use them
when one option is objectively better (a working link beats a broken one),
when best practice names one approach, or when the surrounding code already uses one.

```markdown
**Fix Options:**
1. **Fully qualify** - Use `QSSGFrameData::AttachmentSelector` in `\fn`
2. **Use typedef** - Create a typedef at namespace scope

**Recommended:** Option 1 because it matches the declaration.
```

## Notes (unnumbered)

Observations that need no change go in `## Notes` after the last
suggestion: exempt legal text (C11, G28), content checked and found
correct, and patterns worth knowing. Don't number them, and don't count them in X.

```markdown
## Notes

**Legal text (lines 79-86):** C11 legal text; no style changes suggested.
**Line length:** All added lines are within 80 columns (R40).
```

## Diff block

`render_record.py` produces it from the real file. It is a standard git
unified diff, so it copies into a prompt or an editor and applies with
`git apply`:

- `diff --git a/{path} b/{path}`, then `---` and `+++` lines, then `@@`
  hunks with 3 context lines. The paths are relative to the repository root.
- An addition shows only `+` lines between context lines. A replacement
  shows `-` lines, then `+` lines.
- Changes under 10 lines apart share one hunk.

```diff
diff --git a/qtdeclarative/src/quickcontrols/doc/src/qtquickcontrols-basic.qdoc b/qtdeclarative/src/quickcontrols/doc/src/qtquickcontrols-basic.qdoc
--- a/qtdeclarative/src/quickcontrols/doc/src/qtquickcontrols-basic.qdoc
+++ b/qtdeclarative/src/quickcontrols/doc/src/qtquickcontrols-basic.qdoc
@@ -40,6 +40,7 @@
     \section1 Basic Style

     \image qtquickcontrols-basic-thumbnail.png
+        {Gallery of controls in Basic style}

     The Basic style is a simple and lightweight style.
     It works on every platform.
```

## Validation

What you checked, one line per check, with the rule ID. Include only checks
relevant to the change. `✗` marks a problem in the original that the fix
resolves, or a remaining issue.

| Area | Checks and rule IDs |
|------|---------------------|
| Language | Active voice (G1), concise (R2), substitutions such as Latin terms (R38), terminology (R3, G2), present tense (R4) |
| Alt text | Format: capital start, no final period (R24); no class names (R26); content (G11) |
| QDoc | Syntax valid, no space before brace (R39), link target verified in the index |
| API status | Export macro, `.h` vs `_p.h`, `*Private` → full docs or `\internal` |
| Formatting | 80 columns (R40), indentation matches the surrounding block |
| Content type | The C type and its register (C1-C12, G23-G29) |

```markdown
**Validation:**
- ✗ Alt text: missing (R24)
- ✓ Content: names the visible controls (G11)
- ✓ Terms: "controls", not "QQuickControls" (R26)
- ✓ Line length: 52 columns (R40)
```

## Comments

One or two sentences: why the change matters, an alternative you rejected,
or a follow-up. Example: `Resolves the warning. The same pattern is used
15 times in qtbase.`
