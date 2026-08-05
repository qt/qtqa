---
name: skill-alttext
description: Authoritative style rules for writing accessibility alt text in Qt documentation, including priority order, formatting rules, and terminology guidelines. Use when adding alt text to images.
metadata:
  version: "1.3"
---

# Alt Text Style Directive for Qt Documentation

## Priority Order for Options

1. **Option 1** (Recommended): Include visible text/labels/icons from the image
2. **Option 2**: Context-focused (purpose/behavior/state from image or surrounding documentation)
3. **Option 3**: Generic visual description

## Formatting Rules

- Replace `\borderedimage` with `\image`
- Alt text in curly braces `{...}` on same line as image command
- If same line exceeds 80 columns, put alt text on next line indented to align with the filename
- In table rows, align `\li` commands vertically under each other
- **80-column limit for all lines**

## QUIP 21 Technical Specifications

**Reference:** [QUIP 21 - Using images in Qt documentation](https://contribute.qt-project.org/quips/21)

### File Format

| Format | Use Case | Notes |
|--------|----------|-------|
| **WebP** | Preferred for all images | Smaller file size |
| PNG | Acceptable alternative | Use `optipng` to optimize |
| JPEG | Photos, complex images | Lossy compression |
| GIF | Animated images | Or lossless WebP |
| SVG | Vector graphics | Scalable |

### File Size

- **Recommended:** < 50 KiB
- Git post-commit hooks warn if images exceed this limit
- Crop to include only relevant content
- Use WebP format for smaller size

### Screenshot Requirements

| Spec | Requirement |
|------|-------------|
| Resolution | 1920x1080 pixels |
| Display scaling | 100% |
| Content | Only necessary screen portions |
| Processing | Do not resize; CSS auto-scales > 800px width |
| Highlighting | Use number icons from `qtdoc/doc/images/numbers/` |

### Icon Requirements

- Grayscale images with transparent background
- Ensures visibility in light and dark documentation modes
- Use `qttools/util/recolordocsicons/recolordocsicons.py` for problematic icons

### Image Location

Images must be in a directory listed in the module's `.qdocconf` file:

```qdocconf
imagedirs += images \
             ../images \
             ../../examples/quick/doc/images
```

**Verification:** If `\image myfile.webp` fails, check:
1. File exists in repository
2. File is in a path listed in `imagedirs`
3. Path is relative to qdocconf location

## Terminology

- Use common/generic terms (e.g., "check boxes", "delay button", "switch", "scroll bar", "tab bar", "tool bar")
- NOT Qt control names (e.g., NOT "CheckBox", "DelayButton", "Switch", "ScrollBar", "TabBar", "ToolBar")
- Use lowercase for control names in alt text
- Use terms from the surrounding context when available

## Content Guidelines

- Include visible text, labels, or icons when present (Option 1)
- Describe state or behavior when visible (e.g., "in selected state", "showing partial completion")
- Consider surrounding documentation context
- Describe what users observe, not implementation details
- Focus on behavior and purpose relevant to the section
- **Alt text should align with the topic of the surrounding section or paragraph** - if the section discusses "baked lightmaps", mention "baked lightmap" in the alt text; if discussing "antialiasing modes", reference "antialiasing" in the alt text

## W3C Alt Text Decision Tree

Use these questions to determine alt text approach:

| Question | If Yes |
|----------|--------|
| Does image contain text? | Include text in alt (unless text appears nearby → decorative) |
| Is image in a link/button? | Describe the destination or action |
| Does image contribute meaning? | Brief description conveying the meaning |
| Is it purely decorative? | Empty alt attribute (rare in Qt docs) |

**For complex graphics (charts, diagrams, flowcharts):** Include detailed information elsewhere on the page if alt text alone cannot convey the full meaning.

## Microsoft Alt Text Guidelines

**Do:**
- Keep concise: 1-2 sentences maximum
- Convey content AND purpose of the image
- Include context: setting, emotions, colors, relative sizes when relevant
- For charts/diagrams: describe the **insight**, not just the format
  - Good: "Sales increased 25% in Q3"
  - Bad: "Bar chart showing sales"
- For flowcharts: describe beginning point, progress, and conclusion

**Don't:**
- Start with prefix anti-patterns (see list below)
- Use file names or URLs as alt text
- Repeat surrounding text verbatim
- Write generic/unhelpful descriptions

## Prefix Anti-Patterns (NEVER USE)

**These prefixes describe what the image IS, not what it SHOWS. Never use them:**

| Anti-Pattern | Example (WRONG) |
|--------------|-----------------|
| "Screenshot of" | "Screenshot of the settings dialog" |
| "Screenshot showing" | "Screenshot showing the toolbar" |
| "Illustration of" | "Illustration of the node graph" |
| "Illustration showing" | "Illustration showing the effect" |
| "Image of" | "Image of the application window" |
| "Picture of" | "Picture of the code editor" |
| "Photo of" | "Photo of the hardware" |
| "A graphic of" | "A graphic of the workflow" |
| "An image of" | "An image of the result" |

**Correct approach:** Start directly with what the image shows:
- ❌ "Screenshot of the settings dialog with padding options"
- ✅ "Settings dialog with padding options"
- ❌ "Illustration showing a node graph"
- ✅ "Node graph with Main, BlurHelper, and Output nodes"

**Apply this rule to both original AND suggested replacement text.**

**Decorative images:** Mark as decorative (empty alt); screen readers skip them. Most Qt documentation images are informative, not decorative.

## Common Review Corrections (reinforcements)

Recurring fixes from real reviews. These reinforce the rules above — apply
them before submitting, and to suggested replacement text.

1. **Avoid rendering/drawing-API verbs.** Describe the visible result in plain
   terms, not the API operation. (Sibling to the "no Qt class names" rule.)
   - ❌ "Square outline stroked in dark teal" → ✅ "Dark teal square outline"
   - ❌ "Green square filled and stroked with an outline" → ✅ "Filled green
     square with a dark teal outline"
   - "stroked" → *outline / outlined*; keep "filled" only when plain and needed.

2. **Classify the image type first** — a literal screenshot/scene, or a
   schematic **diagram / chart / sequence**? Frame diagrams as diagrams and
   describe the relationship or insight, not a literal scene (see the
   Wireframes and Diagrams pattern).
   - ❌ "Two devices over the Earth with a magnet nearby"
   - ✅ "Diagram comparing geomagnetic readings, with the axes aligned to the
     Magnetic North Pole, against raw readings skewed by a nearby magnet"

3. **Prefer the shortest accurate description.** Omit non-essential detail and
   redundancy; favor brevity over completeness.
   - Drop unneeded orientation words ("upright"), element/color counts, and
     redundancies ("baseline lines" → "baselines"; "wavy sine line" → "sine
     wave").
   - Avoid uncommon/jargon adjectives ("monoblock device" → "device").

4. **For example-output images, cross-check the example code.** When the image
   shows the result of a code snippet, read the snippet to get the exact
   geometry before describing it — number of curves vs. straight edges, which
   corners are rounded (and by how much), how many arcs/segments.
   - ❌ "Green leaf bounded by a quadratic curve and a straight edge" (the code
     draws two `quadraticCurveTo` calls) → ✅ "Pointed green leaf shape formed
     by two quadratic curves"
   - ❌ "Square with only its bottom-right corner rounded" (radii were
     `0,40,20,80`) → ✅ "Green square with a sharp top-left corner and three
     rounded corners of differing radius"

5. **Read visible text literally.** Transcribe on-screen text exactly; don't
   substitute a placeholder (e.g., handwriting recognizing "hello", not "Abc").

## Alt Text Patterns by Content Type

### 1. Example Page Main Images
**Context**: Example pages (`\example` command) show running applications
**Pattern**: `{[Key feature/object] with [interactive controls/elements]}`
**Priority**: Option 1 (visible UI elements) + Option 2 (demonstrated feature)
**Guidelines**:
- Describe what the running example shows visually
- Focus on the feature being demonstrated
- Mention key interactive controls if visible
- Keep concise - avoid overly detailed UI descriptions
**Examples**:
```
{Qt logo with three light types and lighting controls}
{Space scene with asteroid field and two spaceships}
{Three stacked Qt logo layers with layer toggle checkboxes}
```

### 2. Tutorial/Guide Screenshots
**Pattern**: `{[UI description] with/showing [visible elements and interactions]}`
**Priority**: Option 1 (visible text/elements) + Option 2 (behavior)
**Examples**:
```
{Window with toolbar containing dark mode toggle and buttons}
{Chat messages displaying timestamps below message text}
{Navigation between contact list and conversation pages}
```

### 3. Control Demonstration Images
**Pattern**: `{[Control name] [behavior/state description]}`
**Priority**: Option 2 (behavior/state)
**Examples**:
```
{Button in various interaction states}
{Switch control in on and off states}
{Delay button with progress indicator filling on long press}
```

### 4. Customization Examples
**Pattern**: `{Custom styled [control]}` or `{Custom styled [control] with [notable feature]}`
**Priority**: Option 2 (context - customization section)
**Examples**:
```
{Custom styled button}
{Custom styled menu bar with File and Edit menus}
{Custom styled progress bar showing partial completion}
```

### 5. Style Assets (Imagine Style)
**Pattern**: `{[ControlName] [element] [state] asset}`
**Note**: Uses Qt class names because these match asset file naming conventions
**Priority**: Option 3 (generic - technical asset reference)
**Examples**:
```
{Button background pressed asset}
{CheckBox indicator checked focused asset}
{Switch indicator hovered asset}
{CheckDelegate indicator partial checked pressed asset}
```

### 6. Wireframes and Diagrams
**Pattern**: `{[Type] wireframe/diagram/layout showing [structure/elements]}`
**Priority**: Option 2 (context/structure)
**Examples**:
```
{Stack view wireframe showing page navigation}
{Window layout with Menu bar, Header, Content area, and Footer}
{Page wireframe with header, content area, and footer}
```

### 7. Technical/9-Patch Images
**Pattern**: `{[Subject] showing [technical aspect]}`
**Priority**: Option 2 (technical context)
**Examples**:
```
{Button background 9-patch image showing stretch and padding lines}
{Diagram showing 9-patch line color requirements}
{Diagram showing popup property inheritance}
```

## Terminology Special Cases

### When Qt Class Names Are Acceptable:

1. **Visible text labels**: When the control displays the class name as text
   ```
   {Tool button labeled ToolButton}
   ```

2. **Asset file documentation**: In Imagine style asset tables where names match file patterns
   ```
   {CheckBox indicator asset}
   {RadioButton indicator checked asset}
   ```

3. **Technical wireframes**: When describing a specific control type's layout in technical documentation
   ```
   {ScrollView layout showing scrollable content area with scroll bars}
   ```
   Note: Use sparingly; prefer generic terms when possible

### When to Use Generic Terms:

All other contexts use lowercase generic terms:
- "check boxes", "radio buttons", "combo box", "spin box"
- "scroll bar", "scroll view", "tab bar", "tool bar"
- "switch", "slider", "dial", "button"

## Example: Standalone Image

```
\image qtquickcontrols-button-custom.png {Custom styled button}

\image qtquickcontrols-switch.png
       {Switch control labeled Switch in off state}
```

The first example fits within 80 columns on one line. The second wraps to the next line with the alt text aligned to the filename.

## Example: Table with Rows

```
\table
\header
    \li {1,2} \b {Key}
    \li {1,2} \b {Value}
\row
    \li \inlineimage qtquickcontrols-button-normal.png
        {Button in normal state}
    \li A button in the normal state.
\row
    \li \inlineimage qtquickcontrols-button-pressed.png
        {Button in pressed state}
    \li A button in the pressed state.
\endtable
```

**Indentation pattern in tables:**
- `\row` at base indentation
- `\li` commands aligned vertically
- Alt text on same line, or next line (aligned with filename) if exceeds 80 columns

## Line Length Management

If the line exceeds 80 columns: move alt text to the next line, indented to align with the filename. If still too long, shorten words or remove non-essential words.

## QDoc Configuration: Enforcing Alt Text

### The `reportmissingalttextforimages` Flag

QDoc provides a configuration flag to enforce alt text on all images:

```qdocconf
reportmissingalttextforimages = true
```

**What it does:**
- Reports a warning for any `\image` or `\inlineimage` without alt text
- Warning format: `\inlineimage filename.png is without a textual description, QDoc will not generate an alt text for the image.`
- When combined with `warninglimit = 0`, the build will fail until all images have alt text

**Current status in qtbase:**
- ✅ **Enabled**: `src/widgets/doc/qtwidgets.qdocconf`
- ❌ **Not enabled**: Most other modules (including qtsql, qtgui, qtcore, etc.)

**Location in QDoc source:**
- Flag definition: `qttools/src/qdoc/qdoc/src/qdoc/config.cpp:81-82`
- Warning generation: `qttools/src/qdoc/qdoc/src/qdoc/docparser.cpp:1784-1788`

**To enable for a module:**
Add `reportmissingalttextforimages = true` to the module's .qdocconf file (e.g., `qtsql.qdocconf`, `qtgui.qdocconf`).

---

## Alt Text Review Checklist

When reviewing or creating patches for Qt documentation alt text, **ALWAYS** check:

### 1. Alt Text Content and Formatting
- ✅ Alt text follows priority order (visible text → context/behavior → generic description)
- ✅ Uses generic terminology, not Qt class names (unless exceptions apply)
- ✅ **NO PREFIX ANTI-PATTERNS** - Not starting with:
  - "Screenshot of/showing", "Illustration of/showing"
  - "Image of", "Picture of", "Photo of", "A graphic of"
- ✅ Active voice, not passive constructions
- ✅ 80-column limit compliance
- ✅ Alt text on same line, or next line (indented) if exceeds 80 columns
- ✅ **SUGGESTED FIXES also checked** - Apply same rules to replacement text

### 2. Image Verification ⚠️ **CRITICAL - DO NOT SKIP**

**ALWAYS view images to verify alt text accuracy.** Do not rely on filenames alone.

**Why this matters:**
- Filenames can be misleading or wrong
- Alt text must describe what users actually see
- Copy-paste errors can swap descriptions between similar images
- Accuracy errors mislead screen reader users

**Verification process:**
1. **Locate the image file** using Glob: `**/doc/images/{filename}`
2. **Read the image** using the Read tool (supports PNG, JPG, WebP)
3. **Compare visual content** against the proposed alt text
4. **Check for swapped descriptions** when multiple similar images appear together

**Common accuracy errors to catch:**
- Wrong gradient type (linear vs radial vs conical)
- Wrong spread mode (pad vs repeat vs reflect)
- Wrong join style (bevel vs miter vs round)
- Wrong cap style (square vs flat vs round)
- Wrong state (pressed vs normal vs disabled)
- Swapped descriptions between adjacent images in tables

**Example verification:**
```
Image: qpen-roundjoin.png
Alt text claims: "miter joins"
Visual shows: rounded corners at line joins
Result: ❌ ACCURACY ERROR - should say "round joins"
```

#### Remote Image Verification

When images aren't available locally (e.g., reviewing Gerrit patches for other repos):

**Method 1 - Published docs (preferred):**
```bash
# Most Qt example images are published to doc-snapshots
WebFetch https://doc-snapshots.qt.io/qt6-dev/images/{filename}
```

**Method 2 - Clone repository:**
```bash
git clone --depth 1 https://code.qt.io/qt/{repo}.git /tmp/{repo}
# Then use Read tool on /tmp/{repo}/examples/.../doc/images/{filename}
```

**Method 3 - Gerrit raw file API:**
```bash
# For files in the patch itself
curl -s "https://codereview.qt-project.org/changes/{change-id}/revisions/current/files/{encoded-path}/content" | base64 -d
```

**If ALL methods fail:**
- Explicitly state in review: `"⚠️ IMAGE VERIFICATION BLOCKED - unable to access images. Alt text accuracy UNVERIFIED."`
- Do NOT silently skip this step
- Proceed with other checks but flag that accuracy is unverified

**Orchestrator responsibility:** The orchestrator (Claude Code) should check image availability BEFORE dispatching to the agent and include access instructions in the agent prompt. See CLAUDE.md "Image Verification Context" section.

### 3. QDoc Configuration ⚠️ **CRITICAL - DO NOT FORGET**
- ✅ Check if `reportmissingalttextforimages = true` is in the module's .qdocconf file
- ✅ If missing, **add it to the patch** along with alt text changes
- ✅ Add after `warninglimit = 0` with blank line and comment:
  ```qdocconf
  # Enforce zero documentation warnings
  warninglimit = 0

  # Report warnings for images without alt text
  reportmissingalttextforimages = true
  ```

**Why this matters:** Without this flag, the module won't enforce alt text on future images. Any alt text improvement patch should enable enforcement to prevent regression.

---

## External References

- [W3C WAI Alt Text Decision Tree](https://www.w3.org/WAI/tutorials/images/decision-tree/)
- [Microsoft: Everything you need to know to write effective alt text](https://support.microsoft.com/en-us/office/everything-you-need-to-know-to-write-effective-alt-text-df98f884-ca3d-456c-807b-1a1fa82f5dc2)
- [QUIP 21: Using images in Qt documentation](https://contribute.qt-project.org/quips/21)

---

This directive covers all patterns found in Qt Quick Controls documentation and ensures consistency across all alt text additions.
