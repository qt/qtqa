# qt.io Marketing Site Structure

Reference for qt.io pages that link to doc.qt.io. Relevant when a Qt documentation
filename changes — marketing pages use hardcoded HTML URLs and will 404 without a
server-side 301 redirect.

Verified 2026-04-14.

---

## Site Hierarchy Relevant to Doc Links

```
qt.io/
└── development/
    ├── (hub page)                          No doc.qt.io links
    └── qt-framework/
        ├── (parent page)                   1 doc link: topics-graphics.html
        ├── networking-connectivity         ← 5 links to topics-network-connectivity.html
        ├── ui-framework                    links to qtquick-index.html, qtmultimedia-index.html
        ├── data-handling                   links to topics-data-io.html, qtserialization.html
        ├── 3d-graphics                     not yet checked
        ├── graphs                          not yet checked
        ├── ui-accessibility                not yet checked
        ├── functional-safety-and-qt        not yet checked
        ├── platforms / target-devices      not yet checked
        ├── qt6 / release-cycle / qt-lts    not yet checked
        ├── python-bindings / languages     not yet checked
        ├── commercial-qt / qt-licensing    not yet checked
        └── security-maintenance            not yet checked
```

**Pattern**: Each capability subpage links to its corresponding `doc.qt.io/qt-6/`
topic overview or module index. Check the subpage matching the changed topic area.

---

## Known Doc Links Per Subpage

### qt.io/development/qt-framework/ (parent)
| Anchor text | URL |
|---|---|
| Graphics Documentation | `https://doc.qt.io/qt-6/topics-graphics.html` |

### qt.io/development/qt-framework/networking-connectivity
| Anchor text | URL |
|---|---|
| Learn More in Documentation | `https://doc.qt.io/qt-6/topics-network-connectivity.html` |
| Explore the Documentation (Networking section) | `https://doc.qt.io/qt-6/topics-network-connectivity.html` |
| Explore the Documentation (Connectivity section) | `https://doc.qt.io/qt-6/topics-network-connectivity.html` |
| See all connectivity options | `https://doc.qt.io/qt-6/topics-network-connectivity.html` |
| Explore the Documentation (footer CTA) | `https://doc.qt.io/qt-6/topics-network-connectivity.html` |

### qt.io/development/qt-framework/ui-framework
| Anchor text | URL |
|---|---|
| Learn More in Documentation | `https://doc.qt.io/qt-6/qtquick-index.html` |
| Learn More in Documentation | `https://doc.qt.io/qt-6/qtquick-positioning-topic.html` |
| Go to Multimedia Documentation | `https://doc.qt.io/qt-6/qtmultimedia-index.html` |
| Go to Qt WebEngine Quick Documentation | `https://doc.qt.io/qt-6/qtwebengine-qmlmodule.html` |
| Explore the QML Documentation | `https://doc.qt.io/qt-6/qmlreference.html` |
| Explore the Documentation | `https://doc.qt.io/qt-6/qtquick-index.html` |

### qt.io/development/qt-framework/data-handling
| Anchor text | URL |
|---|---|
| Learn More in Documentation | `https://doc.qt.io/qt-6/topics-data-io.html` |
| Explore the Documentation | `https://doc.qt.io/qt-6/qtserialization.html` |
| JSON | `https://doc.qt.io/qt-6/json.html` |
| XML Support in Qt | `https://doc.qt.io/qt-6/topics-data-io.html#xml-support-in-qt` |
| CBOR | `https://doc.qt.io/qt-6/cbor.html` |
| Protobuf | `https://doc.qt.io/qt-6/qtprotobuf-index.html` |
| Explore the Documentation | `https://doc.qt.io/qt-6/topics-data-io.html` |
| Databases & Queries | `https://doc.qt.io/qt-6/topics-data-io.html#database` |
| Domain Specific Files | `https://doc.qt.io/qt-6/qtimageformats-index.html` |
| Application Settings | `https://doc.qt.io/qt-6/topics-data-io.html#qsettings-class` |
| Resources | `https://doc.qt.io/qt-6/resources.html` |

---

## Other qt.io Sections Checked

| Section | Doc links found | Notes |
|---------|----------------|-------|
| `qt.io/` (root) | No | General `doc.qt.io` footer link only |
| `qt.io/development/` | No | General `doc.qt.io` footer link only |
| `qt.io/product/` | No | "NETWORKING & CONNECTIVITY" plain text, no link |
| `qt.io/product/features` | No | "Qt Network" listed, links to `doc.qt.io/qt-6/` root only |
| `qt.io/blog/tag/networking-and-connectivity` | No | CMS tag page, no doc links |
| `qt.io/blog/revitalizing-qtnetworkauth-*` | No | Links to API class pages, not overviews |
| `wiki.qt.io/QtNetwork` | No | Old article, no doc.qt.io links at all |
| `wiki.qt.io/Networking_and_Connectivity` | 404 | Page does not exist |

---

## How to Check a qt.io Subpage

For any doc.qt.io page being renamed, identify the matching qt.io/development/qt-framework/
subpage (if one exists) and fetch it:

```
WebFetch https://www.qt.io/development/qt-framework/{capability-name}
Prompt: List ALL links pointing to doc.qt.io with exact anchor text and full URL.
```

Check whether the old HTML filename appears in any link `href`. If yes: BREAKING finding,
fix via 301 redirect (preferred) or CMS update.

---

## Blog Search Pattern

Marketing blog posts sometimes deep-link to specific doc pages when announcing features.
For major API changes, search:

```
WebSearch: site:qt.io/blog "old-page-title" OR "old-filename.html"
```

Then fetch any hits and confirm the link target. Blog posts are archived — a broken
link in a published blog post is a lower-severity issue (STALE) than a broken link
on an active product page (BREAKING).

---

## CMS Note

qt.io uses HubSpot CMS (`?hsLang=en` query params throughout). Links on these pages
cannot be updated via a git commit — the web/marketing team must make the change in
HubSpot. A server-side 301 redirect at the doc.qt.io infrastructure level protects
these pages automatically without requiring CMS involvement.

---

## Capability Subpages Not Yet Checked

These qt.io/development/qt-framework/ subpages have not been systematically audited
for doc.qt.io links. Check them for any future rename affecting their topic area:

- `/3d-graphics` — likely links to `qt3d-index.html` or `qtquick3d-index.html`
- `/graphs` — likely links to `qtgraphs-index.html`
- `/ui-accessibility` — likely links to accessibility overview
- `/functional-safety-and-qt` — likely links to Qt Safe Renderer docs
- `/platforms` — likely links to supported-platforms pages
- `/python-bindings` — likely links to Qt for Python docs
- `/qt6` — likely links to `whatsnew6*.html`
- `/release-cycle`, `/qt-lts`, `/security-maintenance` — likely links to lifecycle pages
- `/commercial-qt`, `/qt-licensing` — likely links to licensing docs
