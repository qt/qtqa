---
name: skill-cross-product-check
description: >
  Cross-product impact checking for Qt documentation changes. Load this skill whenever
  a doc change (page rename, title change, filename change, API rename, QML type rename)
  may affect products outside the changed module. Covers all doc.qt.io products, all
  doc-snapshots.qt.io products, and qt.io marketing pages. Provides verified snapshot
  paths, index file availability, link mechanisms per product, and search procedures
  in priority order. Use alongside doc-impact-analyzer Steps 5–6 or standalone when
  auditing cross-product reference breakage.
---

# Qt Cross-Product Reference Check

Reference and workflow for checking whether a Qt documentation change breaks links
or references in any Qt product outside the changed module.

## When to Use

- Page title renamed → QDoc-based products break (title resolution via index)
- HTML filename renamed → HTML-URL-based products break (Qt for Python, marketing)
- Both changed → all product types are at risk
- API/QML type renamed → check all QDoc-based products
- `\target` or `\keyword` removed → check all products

## Link Mechanisms — What Breaks and Why

| Mechanism | Products | Breaks on title rename? | Breaks on filename rename? |
|-----------|----------|------------------------|---------------------------|
| QDoc `depends` + index resolution | Creator, Design Studio, Automotive, Boot2Qt, MCUs, all QDoc tools | **Yes** | No |
| Sphinx + HTML intersphinx URLs | Qt for Python | No | **Yes** |
| Hardcoded HTML `<a href>` | qt.io marketing, blog, wiki | No | **Yes** |

**Why QDoc index resolution breaks on title rename:** Products that declare `depends`
on a Qt module in their qdocconf load that module's `.index` file at build time. Any
`\l{Title Text}` in their source resolves against that index. When the title changes,
the normalized key changes (QDoc lowercases everything), and the link silently produces
a QDoc warning at the product's next build — with no warning at the time the Qt doc
change lands.

**Why filename changes break HTML-URL products:** Qt for Python (Sphinx) and marketing
pages (CMS) embed the HTML path directly (e.g., `doc.qt.io/qt-6/topics-network-connectivity.html`).
No index involved — the URL is hardcoded. A filename rename produces 404s unless a
server-side 301 redirect is in place.

## Verification Priority Order

For each product, try in this order — stop when you get a result:

1. **Index file grep** (fastest, definitive for QDoc products)
   ```bash
   curl -s https://doc-snapshots.qt.io/{snapshot-path}/{index-file}.index \
     | grep -i "old title\|old-filename"
   ```
   ⚠ Index files show what a product *defines*, not what it *links to*. A hit means the
   product has its own node with that name (rare). No hit does NOT mean it has no links —
   use HTML search to find outgoing references.

2. **Published HTML search** (reliable for outgoing links)
   ```bash
   curl -s https://doc-snapshots.qt.io/{snapshot-path}/index.html \
     | grep -i "old title\|old-filename"
   # Also check TOC and overview pages
   ```
   Or via WebSearch: `site:doc-snapshots.qt.io/{path} "Old Title"`

3. **WebFetch key pages** (targeted, no clone needed)
   Fetch the product's index, TOC, and overview pages. Search for the old title or filename.
   See `references/snapshot-paths.md` for key page names per product.

4. **Shallow clone** (authoritative, required for definitive "not affected" verdict)
   ```bash
   git clone --depth 1 https://code.qt.io/{repo}.git /tmp/{repo}
   grep -rn "Old Title\|old-filename" --include="*.qdoc" /tmp/{repo}/doc/
   ```

**Marking results:**
- ✓ **Not affected** — verified by method 3 or 4 (HTML search or clone)
- ⚠ **Unverified** — only method 1 tried, or product not reachable
- ✗ **Affected** — reference found; add as BREAKING finding with file:line

## Scope by Change Type

| Change type | Check QDoc products | Check Qt for Python | Check marketing |
|-------------|--------------------|--------------------|-----------------|
| Title-only rename | ✓ All QDoc products | No | No |
| Filename-only rename | No | ✓ | ✓ |
| Both title + filename | ✓ All QDoc products | ✓ | ✓ |
| C++ class rename | ✓ Creator, DS, Python | ✓ | If flagship API |
| QML type rename | ✓ Creator, DS, MCUs | No | No |
| `\page` URL change | No | ✓ | ✓ |

## Full Product Inventory

For snapshot paths, index file status, and repo locations, read:
→ `references/snapshot-paths.md`

For qt.io marketing page structure and known doc.qt.io links, read:
→ `references/qt-io-structure.md`

## Cross-Module Search Results Table (required in report)

After checking all products, output this table in the Notes section of the impact report.
List every product checked — do not summarise with counts.

```
### Cross-Product Search Results

| Product | Snapshot | Index | Has Reference | Method | Notes |
|---------|----------|-------|---------------|--------|-------|
| Qt Creator | qtcreator-master/ | ✓ | No | HTML + index grep | — |
| Qt Design Studio | qtdesignstudio/ | ✓ | No | HTML + index grep | — |
| Qt for Python | qtforpython-dev/ | — | ⚠ Unverified | No clone | Check pyside-setup repo |
| qt.io/development/qt-framework/networking-connectivity | — | — | ✗ Yes | WebFetch | 5 hardcoded links |
| ... | | | | | |

**Not checked:** [list any product skipped and why]
```

## Verdict Guidance

If any product is **Unverified**, the overall verdict must include:
> "Cross-product impact could not be fully verified. Manual check required for:
> {list of unverified products} before landing."

A change is **SAFE** only when all products are either confirmed Not affected or
the only remaining references are in products being updated in the same commit.
