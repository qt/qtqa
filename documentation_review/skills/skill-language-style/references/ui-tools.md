<!-- Loaded on demand by skill-language-style/SKILL.md router. Part of skill-language-style. -->

## UI and Tools Documentation

### R42. UI Element Markup

**Rule**: Mark UI elements distinctly from surrounding text.

**In tools documentation** (Qt Creator, Qt Design Studio):
- Use bold for UI elements: **File**, **Edit**, **Run**
- Use bold for buttons: **OK**, **Cancel**, **Apply**

**In QDoc**:
- Use `\uicontrol{element}` command for UI text

**Examples**:
```
✅ Go to **File** > **New Project**.
✅ Select the **Run** button.
✅ In QDoc: Select \uicontrol{File} > \uicontrol{New}.
```

**Sources**: S1 (Qt Writing Guidelines), Qt Creator documentation

---

### R43. Keyboard Shortcut Formatting

**Rule**: Format keyboard shortcuts consistently.

**Patterns**:
- Single modifier: `Ctrl+B`, `Alt+F`
- Multiple modifiers: `Ctrl+Shift+F`
- Sequential keys: `Ctrl+K, Ctrl+D`
- Platform variants: `Ctrl+O` (`Cmd+O` on macOS)

**In tables**: Show Windows/Linux and macOS columns separately.

**Examples**:
```
✅ Press Ctrl+S to save.
✅ Press Ctrl+K, Ctrl+D to format the document.
✅ Press Ctrl+B (Cmd+B on macOS) to build.
```

**Sources**: Qt Creator documentation, Qt Design Studio documentation

---

### R44. Menu Path Formatting

**Rule**: Write menu navigation paths with bold elements separated by `>`.

**Examples**:
```
✅ Go to **File** > **New Project**.
✅ Select **Edit** > **Preferences** > **Kits**.
✅ In the **Tools** > **Options** dialog, select **Environment**.
```

**Sources**: Qt Creator documentation, Qt Design Studio documentation

---


