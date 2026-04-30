# Title and Section Capitalization in Qt Documentation

**Version:** 1.0
**Date:** 2026-03-18
**Status:** Research finding - de facto standard (not officially documented)

---

## Summary

| Command | Convention | Source |
|---------|------------|--------|
| **`\title`** | **Title Case** | De facto (actual Qt usage ~80%) |
| **`\section1`** | **Sentence case** | S1 (Qt Writing Guidelines) |
| **`\section2`+** | **Sentence case** | S1 (Qt Writing Guidelines) |
| **Table headers** | **Sentence case** | S9 (Microsoft Style Guide) |

---

## The Finding: Guidance vs Practice Mismatch

| Element | Written Guidance | Actual Qt Practice |
|---------|-----------------|-------------------|
| `\title` | **Not specified** | **Title Case** (predominant) |
| `\section1`/`\section2` | **Sentence case** (S1) | **Mixed** (inconsistent) |

---

## What the Sources Say

### S1 - Qt Writing Guidelines

> "Write section titles in sentence-case as indicated by the Microsoft Writing Style Guide."
> "The previous guideline about using title-case is no longer valid."

**Critical note:** This guidance mentions `\section` titles only. **No specific guidance
exists for `\title`.**

URL: https://wiki.qt.io/Qt_Writing_Guidelines

### S2 - QUIP 25

> "Sentence case" for regular text. Title case is "optional: If it aligns with the
> documentation set."

URL: https://code.qt.io/cgit/meta/quips.git/plain/quip-0025-Documentation-Writing-Style.rst

### S9 - Microsoft Style Guide

> "Use sentence-style capitalization in most titles and headings."
>
> Title-style capitalization is for: "product and service names, names of blogs, book
> and song titles, article titles in citations, white paper titles."

URL: https://learn.microsoft.com/en-us/style-guide/capitalization

---

## Actual Qt Codebase Usage

### `\title` Examples (from qtdoc, qtbase)

```qdoc
\title All C++ Classes                    ← Title Case
\title How to Report a Bug                ← Title Case
\title Groups Of Related Classes          ← Title Case
\title Networking and Connectivity        ← Title Case
\title Animation Framework                ← Title Case
\title Getting the source code            ← Sentence case (minority)
```

**Pattern:** ~80% use Title Case for `\title`

### `\section1` Examples

```qdoc
\section1 C++ classes that are deprecated  ← Sentence case
\section1 Best Practices                   ← Title Case
\section1 Building UIs with Qt Quick       ← Sentence case
\section1 All Examples                     ← Title Case
\section1 Configure Workflow               ← Title Case
\section1 Configuring                      ← Sentence case
```

**Pattern:** Mixed usage, though guidelines specify sentence case

---

## De Facto Standard

Based on evidence from Qt codebase analysis:

| Command | Convention | Rationale |
|---------|------------|-----------|
| **`\title`** | **Title Case** | Page titles appear in navigation, browser tabs, search results. Title Case gives them prominence. |
| **`\section1`** | **Sentence case** | Per Qt Writing Guidelines. Section headings are subordinate to page title. |
| **`\section2`+** | **Sentence case** | Same as `\section1` |
| **Table `\header`** | **Sentence case** | Per structured content guidelines |

---

## Practical Examples

### Correct Usage

```qdoc
\title Getting Started with Qt Quick        ← Title Case
\brief An introduction to Qt Quick development.

\section1 Setting up your environment       ← Sentence case

\section2 Installing Qt                     ← Sentence case

\section1 Building your first application   ← Sentence case
```

### Title Case Rules (for `\title`)

1. **Always capitalize:**
   - First and last words
   - Nouns, verbs, adjectives, adverbs, pronouns

2. **Lowercase:**
   - Articles: a, an, the
   - Prepositions ≤4 letters: to, in, of, for, on, at, by, up
   - Conjunctions: and, but, or, nor, yet, so

3. **Examples:**
   ```
   ✅ Getting Started with Qt Quick
   ✅ How to Report a Bug
   ✅ All C++ Classes
   ✅ Changes to Qt Modules in Qt 6
   ```

### Sentence Case Rules (for `\section`)

1. Capitalize only:
   - First word
   - Proper nouns (Qt, C++, QML, class names)

2. **Examples:**
   ```
   ✅ Setting up your environment
   ✅ Building your first application
   ✅ Changes to Qt for Android
   ✅ C++ classes that are deprecated
   ```

---

## Why the Distinction?

| Element | Visibility | Purpose |
|---------|------------|---------|
| `\title` | Browser tab, navigation, search results, TOC | **High prominence** - represents the entire page |
| `\section1` | Within page content | **Medium prominence** - organizes page content |
| `\section2`+ | Within page content | **Lower prominence** - sub-organization |

Title Case for `\title` aligns with:
- Book chapter titles
- Article headlines
- Navigation menu items

Sentence case for `\section` aligns with:
- Section headings within articles
- Microsoft Style Guide recommendation
- Modern documentation trends

---

## Reviewer Checklist

When reviewing documentation:

- [ ] **`\title`** uses Title Case (capitalize major words)
- [ ] **`\section1`/`\section2`** use sentence case (first word + proper nouns)
- [ ] **Consistency** maintained within the page
- [ ] **Proper nouns** always capitalized (Qt, C++, QML, class names)
- [ ] **No ALL CAPS** for emphasis

---

## Open Questions

1. Should Qt Writing Guidelines be updated to explicitly address `\title`?
2. Should existing inconsistencies in `\section` titles be corrected?
3. Is there value in enforcing this via CI/linting?

---

## Sources Consulted

| ID | Source | URL |
|----|--------|-----|
| S1 | Qt Writing Guidelines | https://wiki.qt.io/Qt_Writing_Guidelines |
| S2 | QUIP 25 | https://code.qt.io/cgit/meta/quips.git/plain/quip-0025-Documentation-Writing-Style.rst |
| S9 | Microsoft Style Guide | https://learn.microsoft.com/en-us/style-guide/capitalization |
| — | Qt codebase analysis | qtdoc/doc/src/*.qdoc, qtbase/src/*/doc/src/*.qdoc |

---

## Version History

- **1.0** (2026-03-18): Initial research finding documenting the gap between written
  guidance (no `\title` specification) and actual practice (Title Case predominant).
  Based on analysis of Qt Writing Guidelines, QUIP 25, Microsoft Style Guide, and
  actual Qt codebase usage patterns.
