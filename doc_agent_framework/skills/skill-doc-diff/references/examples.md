# Complete examples

Back to [`skill-doc-diff`](../SKILL.md). The file paths and line numbers
are illustrative. In a real review the header, Source, and diff come from
`render_record.py`. The diff is a standard git diff, so it pastes into a
prompt, an editor, or `git apply`.

## Single fix

````markdown
**Suggestion 3 of 7 for qtquickcontrols-basic.qdoc:43:**

**Category:** Missing Alt Text
**Source:** `qtdeclarative/src/quickcontrols/doc/src/qtquickcontrols-basic.qdoc`

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

**Cause:** The `\image` has no alt text, so screen readers get only the
file name.

**Validation:**
- ✗ Alt text: missing (R24)
- ✓ Content: names what the image shows (G11)
- ✓ Terms: "controls", not "QQuickControls" (R26)
- ✓ Format: capital start, no final period (R24)
- ✓ Line length: 45 columns (R40)

**Comments:** Describes the gallery for screen reader users.

Should I apply this fix to the file?
````

## QDoc warning fix

````markdown
**Suggestion 5 of 12 for qquick3dtextureproviderextension.cpp:56:**

**Warning:** `Can't link to 'SamplerHint'`
**Category:** QDoc Link Error
**Source:** `qtquick3d/src/runtimerender/qquick3dtextureproviderextension.cpp`
**Output:** `qquick3dtextureproviderextension.html`

```diff
diff --git a/qtquick3d/src/runtimerender/qquick3dtextureproviderextension.cpp b/qtquick3d/src/runtimerender/qquick3dtextureproviderextension.cpp
--- a/qtquick3d/src/runtimerender/qquick3dtextureproviderextension.cpp
+++ b/qtquick3d/src/runtimerender/qquick3dtextureproviderextension.cpp
@@ -53,7 +53,7 @@
     Sets the sampler used by the texture.
     \note This property is only used when using CustomMaterials.

-    \sa SamplerHint
+    \sa QQuick3DTextureProviderExtension::SamplerHint
 */

 void QQuick3DTextureProviderExtension::setSamplerHint(SamplerHint hint)
```

**Cause:** `SamplerHint` is an enum class nested in
`QQuick3DTextureProviderExtension`. `grep 'name="SamplerHint"'` in the
index finds it only under that class, so the bare name doesn't resolve.

**Validation:**
- ✓ Link target: `QQuick3DTextureProviderExtension::SamplerHint` in the index
- ✓ QDoc syntax: valid `\sa` target (R39)
- ✓ Line length: 54 columns (R40)

**Comments:** Resolves the warning with the qualified enum name.

Should I apply this fix to the file?
````

## Several options

````markdown
**Suggestion 8 of 12 for qssgrenderextensions.cpp:114:**

**Warning:** `Can't link to 'QSSGRenderGraphObject::Type'`
**Category:** QDoc Link Error
**Source:** `qtquick3d/src/runtimerender/qssgrenderextensions.cpp`

**Cause:** `QSSGRenderGraphObject` is declared in a private header
(`_p.h`) and has no `\class` docs. `grep 'name="QSSGRenderGraphObject"'`
finds nothing in the index files, so the link can't resolve.

**Fix Options:**
1. **Use `\c`** - Show the name as code, with no link
2. **Remove the reference** - Rewrite the sentence without the type
3. **Document the type** - Add `\class` docs, only if it's meant to be public

**Recommended:** Option 1 because the type is internal but useful to name.

```diff
diff --git a/qtquick3d/src/runtimerender/qssgrenderextensions.cpp b/qtquick3d/src/runtimerender/qssgrenderextensions.cpp
--- a/qtquick3d/src/runtimerender/qssgrenderextensions.cpp
+++ b/qtquick3d/src/runtimerender/qssgrenderextensions.cpp
@@ -111,7 +111,7 @@
 /*!
     \internal
     Returns the render node for \a nodeId.
-    The type is one of the \l{QSSGRenderGraphObject::Type} values.
+    The type is one of the \c{QSSGRenderGraphObject::Type} values.
 */

 QSSGRenderNode *QSSGRenderExtensions::node(int nodeId)
```

**Validation:**
- ✓ API status: `_p.h`, no export macro, so internal
- ✓ QDoc syntax: `\c{}` renders code without a link
- ✓ Line length: 67 columns (R40)

**Comments:** Keeps the type name for developers without linking to
internal API.

Which option should I apply? (1/2/3 or skip)
````

## Notes section

```markdown
---

## Notes

**Legal text (lines 79-86):** C11 legal text. No style changes suggested.
**Line length:** All added lines are within 80 columns (R40).
```
