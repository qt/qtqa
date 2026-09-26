# C16. Commit message

Back to [`skill-c-rules`](../SKILL.md).

## Purpose and style
**Purpose.** Records a change in git history and in Gerrit: what changed
and why. Reviewers read it before the diff. Release managers read it for
change logs.

**Style.** Mixed register. It follows the qt5 `.commit-template` ("One
line only short meaningful description", "Describe what changed and
explain why it changed", "Please wrap at 72 characters") and the Commit
Policy page it links to (https://wiki.qt.io/Commit_Policy).
- **Subject:** one line, imperative mood, no final period. Start with an
  area or feature prefix ("Doc Agent Framework: ", "QLabel: ", "Doc: ").
  When you suggest or generate a message, always include the prefix. The
  author can delete it more easily than invent one. When you review a
  message, a missing prefix isn't a finding: 42% of the corpus has none.
- **Body:** plain prose that states what changed and why (G25). For a
  larger change, one intent paragraph and then one change per bullet,
  each starting with an imperative verb.
- **Footers:** `Task-number:`, `Fixes:`, `Pick-to:`, `Change-Id:`, one
  task per footer, with a space after the colon.
- **`[ChangeLog]`:** only for a feature, fix, or behavior change that
  matters to users. The entry follows G29.

## Detect
Text from `git log --format=%B`, or from the Gerrit `/revisions/current/commit`
endpoint. Not a QDoc topic.

Corpus: the last 200 non-merge commits in each of 46 qt5.git submodules
(`dev`, 2026-09-26), minus the "Update dependencies" bot commits. That
leaves 4,575 commits:

| Feature | Commits | Share |
|---------|---------|-------|
| Subject at most 72 characters | 4,520 | 99% |
| Subject starts with an imperative verb (heuristic) | 3,079 | 67% |
| Subject starts with a past-tense verb | 4 | 0% |
| Area prefix in subject | 2,632 | 58% |
| Body present | 3,806 | 83% |
| All lines wrapped at 72 | 4,136 | 90% |
| `Pick-to:` | 3,223 | 70% |
| `Task-number:` | 1,523 | 33% |
| `Fixes:` | 668 | 15% |
| Bullet list in body | 271 | 6% |
| Intent phrase ("so that", "in order to", "the aim", "this allows") | 220 | 5% |
| `[ChangeLog]` | 150 | 3% |
| `Co-authored-by:` | 53 | 1% |

Repositories and HEADs: qt3d@45531a44b, qtbase@25d8223e59f,
qtdeclarative@ec2f2fdea8, qtdoc@8e238b551, qttools@da04c5df8,
qtrepotools@309df8d, and 40 others.

## Variants by change kind

The same corpus split by change kind. **Doc** means the subject starts
with "Doc", or every file is `.qdoc`, `.qdocinc`, `.qdocconf`, an image,
`.md`, or under `doc/`. **Feature** means there is a `[ChangeLog]` entry,
or the subject starts with Add, Introduce, Implement, or Support.

| Feature | Doc (576) | Feature (567) | Other (3,432) |
|---------|-----------|---------------|---------------|
| Area prefix | 87% | 41% | 55% |
| `Doc:` prefix (Doc, Docs, doc) | 67% | 0% | 0% |
| Body present | 72% | 91% | 84% |
| Body words, median / p90 | 15 / 54 | 29 / 144 | 27 / 112 |
| Bullets | 4% | 9% | 5% |
| Intent or cause word ("so that", "because", "otherwise", ...) | 4% | 15% | 12% |
| `[ChangeLog]` | 0% | 26% | 0% |
| `Task-number:` | 34% | 43% | 31% |

Two variants have consensus, and one is accepted:
- **Doc change (consensus):** `Doc: ` prefix, then a subject in the imperative.
  Body short (median 15 words) or absent. `Task-number:` if there is a bug.
  Release pages use a version prefix (`whatsnew612:`, 49 commits).
- **Feature (consensus):** longer body that explains the design, often with a
  `[ChangeLog]` entry (26%).
- **Lead sentence plus bullets (accepted, 9% of features):** one sentence
  names the change, and a bullet list gives its options, modes, or the APIs
  it covers (for example, qtquick3d "SkyMaterial: add screenspace mode",
  qtwebview "Add C++ example"). Doc-only release updates in qtdoc use
  bullets the same way. The bullets list parts of one change. They don't
  list unrelated changes.

A multi-part framework commit (intent paragraph plus bullets) fits the
third variant. It stays a minority form. Prefer it only when the change
has several distinct parts.

## Rules
- **C16 R (tool):** run `qtrepotools/git-hooks/sanitize-commit` (at
  `309df8d`). It already checks: summary ends with a period, summary not
  imperative, summary too short (< 7) or too long (> 120; > 72 is a
  hint), second line not empty, bug reference in the summary, footer
  spacing, `Task-number` capitalization, and one task per footer. Don't
  reimplement these checks.
- **C16 G (LLM):** G1, G2, G5, G19, G25 for the body, G29 for
  `[ChangeLog]` entries. The body must say why when the diff doesn't
  make it obvious.
- **Security:** skill-security-hygiene checks 7 (no CVE details before
  disclosure) and PII.
- **Images:** not applicable.

## Exemptions
- Bullets are optional. Most Qt commits (94%) use plain paragraphs.
- Tense: subjects and bullets use the imperative ("Add", "Port"), not the
  G29 past tense ("Removed"). G29 applies to `[ChangeLog]` text only.
- G26 and G27 are findings: no contrasts written to persuade, no selling.
  The intent sentence states facts.
- R4 does not apply to planned work in the body ("A follow-up will
  remove X").

## Gaps
- The Commit Policy wiki page wasn't checked at a pinned revision.
- The imperative heuristic counts any capitalized first word that doesn't
  end in "s" or "ed". sanitize-commit's own check is the authority.
- Nothing in the framework reviews commit messages yet. The orchestrator
  only fetches them for context.

## Sample

A minimal passing sample of this type:

```text
QLabel: Elide rich text when wordWrap is off

Plain text was elided, but rich text overflowed the label, so long
links pushed the layout wider than the window.

Fixes: QTBUG-123456
Pick-to: 6.10
Change-Id: I0000000000000000000000000000000000000000
```
