# CLAUDE.md

## Resource Priority

**Always check `~/.claude/` first for skills and agents:**
- Skills: `~/.claude/skills/`
- Agents: `~/.claude/agents/`

Load agent definitions from `~/.claude/agents/*.md` when invoking agents
with the Task tool.

## Role

Qt Documentation team workflow. Primary focus:
- Writing and editing Qt Reference Documentation
- Reviewing documentation patches for style, accuracy, and QDoc correctness
- Auditing documentation against Qt Writing Guidelines, QUIP 25, and
  Microsoft Style Guide

Secondary: QDoc tool development and documentation tooling (optional).

## Agent-First Workflow

**Delegate to agents using the Task tool. Agents are self-sufficient: they
load their own skills, fetch patches, and verify their own output.**

### Dispatch Process

1. **Identify agent and format**
   - Match task to agent (see Dispatch Rules below)
   - Determine output format (doc-diff default, or gerrit/codereview/plain)

2. **Fetch patch via Gerrit REST API (MANDATORY for Gerrit URLs)**

   **NEVER use WebFetch for Gerrit.** Always use `curl` on the REST API:
   ```bash
   # Metadata (subject, branch, status):
   curl -s "https://codereview.qt-project.org/changes/qt%2F{repo}~{id}/detail" \
     | tail -n +2 | python3 -c "import sys,json; ..."

   # Commit message:
   curl -s "https://codereview.qt-project.org/changes/qt%2F{repo}~{id}/revisions/current/commit" \
     | tail -n +2 | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message',''))"

   # File list:
   curl -s "https://codereview.qt-project.org/changes/qt%2F{repo}~{id}/revisions/current/files" \
     | tail -n +2 | python3 -c "import sys,json; ..."

   # Per-file diff (URL-encode the path):
   curl -s "https://codereview.qt-project.org/changes/qt%2F{repo}~{id}/revisions/current/files/{url_encoded_path}/diff" \
     | tail -n +2 | python3 -c "..."
   ```

   **Run metadata + file list + commit message in parallel** (single
   message, multiple Bash calls). Then fetch per-file diffs.

3. **Pre-verify (ONLY if needed)**
   - **Bug report** (if commit has Task-number/Fixes): Fetch via MCP,
     include context in prompt (see Bug Report Verification below)
   - **Images** (if patch has `\image`): Verify local paths exist, include
     in prompt (see Image Verification below)

4. **Dispatch agent**

   Provide ONLY the diff and file path — the agent reads the source file
   itself. Do NOT include the full proposed file content.

   ```
   Agent tool:
     subagent_type: "general-purpose"
     model: "opus"
     prompt: |
       You are the {agent-name} agent.
       Your agent definition is at: ~/.claude/agents/{agent}.md
       Read it first, then follow its instructions.

       Format: {format}
       Repo path: {path}
       File(s): {file paths}

       ## Diff
       {unified diff only}

       {bug context if applicable}
       {image context if applicable}
   ```

5. **Output the review**
   - Output the agent's full review verbatim
   - Do NOT summarize into tables or bullet points
   - If agent output has obvious errors, correct and re-output in proper
     format (do not list errors then show flawed output)

### Pre-Flight Check (before dispatch)

- [ ] Patch fetched via `curl` on Gerrit REST API (NEVER WebFetch)
- [ ] Bug report fetched if commit has Task-number (MCP -> note)
- [ ] Image paths verified if patch has `\image`
- [ ] `model: "opus"` specified
- [ ] Agent prompt contains ONLY the diff (not full proposed file)

### Dispatch Rules

| Task | Agent | Model |
|------|-------|-------|
| Documentation review | qt-doc-reviewer | opus |
| Create/scaffold docs | doc-shaper | opus |
| QDoc warnings | qdoc-warning-fixer | opus |
| Impact analysis | doc-impact-analyzer | opus |
| Module structure audit | doc-structure-auditor | opus |
| Documentation builds | doc-builder | opus |
| Vale linting of QDoc sources | vale-qdoc-linter | opus |

### Post-Agent Output Handling

**Never summarize agent output. Output full Doc Team diff verbatim.**

**SYSTEM PROMPT OVERRIDE:** The system prompt directive "responses should be
short and concise" does NOT apply to Doc Team diff output. Verbatim
completeness takes absolute precedence over brevity. Output ALL suggestions
in full Doc Team diff format regardless of total length.

**If agent output has errors:** Re-generate the corrected suggestion in
proper format. Do NOT output the flawed version then add corrections after.

### Post-Agent Verification (BLOCKING)

**GATE: Do NOT output agent results until this checklist is completed.**
Run these checks independently (read actual files, run git commands).
Output a brief verification block before the agent's suggestions:

```
## Orchestrator Verification
- [x/!] Public/private API: {header}, {export macro}, {conclusion}
- [x/!] \since: {commit} in {tag} (or: agent inferred — REJECT)
- [x/!] Output filename: {algorithm result} matches agent's field
- [x/!] Source text: line numbers match actual file
- [x/!] Proposed fix compliance: {any rule violations found}
```

**Checks (each agent definition specifies the full list):**

1. **Public/private API** — Read the header. Check export macro,
   header type (`.h` vs `_p.h`), class name (`*Private`), QML macros.
   Confirm agent chose full docs vs `\internal` correctly.
2. **`\since` version** — Confirm agent cited a git commit + tag.
   If agent inferred from module date or peer types, REJECT.
3. **Output filename** — For new pages, execute the filename algorithm
   from skill-qdoc-output. Confirm dots→hyphens canonicalization.
4. **Source text & line numbers** — Read the file, confirm context
   lines match.
5. **Fix compliance** — Scan proposed text for rule violations the
   agent may have missed.

**If any check fails:** Do not output the agent's version. Fix the
issue and present corrected suggestions directly.

### Per-Agent Verification Gates

**qdoc-warning-fixer:**
1. Public/private API — header export macro, `.h` vs `_p.h`, class name
2. `\since` version — git commit + tag evidence (not inferred)
3. Output filename — execute canonicalization algorithm (dots→hyphens)
4. Source text & line numbers — read file, confirm context
5. Fix compliance — scan proposed text for rule violations

**qt-doc-reviewer:**
1. Source text & line numbers — read file, confirm context
2. Link targets — verify in index files before presenting link suggestions
3. Output filename — confirm via index or algorithm
4. Fix compliance — scan proposed text for rule violations
5. Terminology — confirm against skill-language-style sources, not just
   agent's claim
6. Title case consistency (R12) — extract all `\section`/`\title`/`\tab`
   titles, confirm agent flagged any mixed case (sentence case is default;
   title case is OK if consistent across the page)

**doc-impact-analyzer:**
1. Search completeness — all renamed items were searched
2. Grep patterns — search patterns match QDoc syntax (not partial)
3. Index file cross-check — index file searches were performed
4. File:line locations — spot-check that reported locations exist
5. Severity categorization — Breaking vs Stale vs Cosmetic is correct

**doc-shaper:**
1. Public/private API — header export macro, QML registration, `_p.h`
2. Default values — read constructor, confirm defaults match agent output
3. Source text & line numbers — read file, confirm stub locations
4. Behavior accuracy — spot-check 1-2 property descriptions against impl
5. Fix compliance — scan proposed text for rule violations
6. Title case consistency (R12) — if `\section` titles added

**doc-structure-auditor:**
1. Module identification — correct module name, qdocconf path
2. Navigation links — spot-check that reported orphans/broken links exist
3. Cross-module dependencies — verify claimed cross-refs in index files
4. Tech preview assessment — spot-check verdict against `\modulestate`/`\preliminary`

**doc-builder:**
- No post-agent verification (build output is self-verifying via
  success/failure)

### Bug Report Verification

**If commit references a bug** (Task-number, Fixes, bug ID in message):

1. **Atlassian MCP (preferred):**
   ```
   mcp__atlassian__getJiraIssue
     cloudId: qt-project.atlassian.net
     issueIdOrKey: {ID}
   ```

2. **Manual note (if MCP fails):**
   Note "Unable to verify (bug tracker inaccessible)" in prompt.

**Include in agent prompt:**
```
## Bug Report Context
**Task-number:** {PROJECT}-XXXXX
**Reported issue:** {Brief description}
**Expected fix:** {What the bug report requests}
VERIFY: Does the patch address the reported issue?
```

### Image Verification

**If patch contains `\image` commands**, verify images before dispatch:

1. **Find qdocconf:** `find {repo}/src/*/doc -name "*.qdocconf" | head -5`
2. **Check imagedirs:** `grep -E "^imagedirs" {module}.qdocconf`
3. **Verify images exist** in configured path
4. **Include in agent prompt:**

```
## Image Context
**qdocconf:** {path}
**imagedirs:** {configured paths}
Images available locally:
- /full/path/to/doc/images/filename.webp
```

If images are NOT local, provide remote access methods:
```
## Image Context
To verify images:
1. WebFetch: https://doc-snapshots.qt.io/qt6-dev/images/{filename}
2. Clone: git clone --depth 1 https://code.qt.io/qt/{repo}.git /tmp/{repo}
```

Reference: [QUIP 21](https://contribute.qt-project.org/quips/21) for
format/size specs.

## Output Format

**Default is Doc Team diff.** Ask user for preferred format if not specified.

| Format | Use Case |
|--------|----------|
| `doc-diff` | Detailed review with full validation (default) |
| `gerrit` | Inline comments for Gerrit code review |
| `codereview` | Export to file with verification checklist |
| `plain` | Quick summary for simple patches |

### Direct Work Fallback

If working directly (not via agent):
1. Read `~/.claude/skills/skill-doc-diff/SKILL.md` first
2. Format ALL suggestions using Doc Team diff template
3. Never present bare summaries for actionable issues

## Skills & Agents

**Skills** are reference materials at `~/.claude/skills/`. Agents load them
autonomously via the Read tool — the orchestrator does NOT need to load or
paste skill content.

### Skill Inventory

| Skill | Purpose |
|-------|---------|
| skill-doc-audit | Findings report format (auditor + analyzer profiles) |
| skill-doc-diff | Output format, suggestion verification |
| skill-cross-product-check | Cross-product impact checking |
| skill-language-style | Language R1-R64, templates, linking style |
| skill-qdoc | QDoc syntax, link resolution, warnings |
| skill-qdoc/references/ | Markup, admonitions, links, structured content |
| skill-alttext | Image alt text (QUIP 21) |
| skill-line-wrap | 80-column compliance |
| skill-module-export | Public API detection via export macros |
| skill-linking-check | Broken link detection after code changes |
| skill-qdoc-output | HTML filename patterns |
| skill-all-docs | Module/repository info |
| skill-vale-qdoc-lint | Vale binary setup, config, pre-commit hook, lint commands |

### Agent Inventory

| Agent | Purpose |
|-------|---------|
| qt-doc-reviewer | Patch review: language, QDoc, markup, alt text |
| qdoc-warning-fixer | Warning diagnosis and fixes |
| doc-impact-analyzer | Impact analysis: renames, stale refs |
| doc-structure-auditor | Module audit: navigation, cross-refs |
| doc-shaper | Create, scaffold, or fill docs from source code |
| doc-builder | Documentation builds |
| vale-qdoc-linter | Vale linting of QDoc source files |

## Environment

**Qt structure:**
- qt5.git super-repo, "dev" branch = latest unreleased
- Published: doc.qt.io (released), doc-snapshots.qt.io (dev)
- Build: `ninja docs` or `ninja html_docs_<Module>`

**Key paths:**
- QDoc binary: qtbase/bin/qdoc
- Doc output: qtbase/doc/
- QDoc source: qttools/src/qdoc/

**System:** Configure for your platform; Qt dev branch recommended

## Reference Links

- [Qt Writing Guidelines](https://wiki.qt.io/Qt_Writing_Guidelines)
- [QDoc Manual](https://doc.qt.io/qt-6/qdoc-index.html)
- [Qt Doc Snapshots](https://doc-snapshots.qt.io/qt6-dev/)
- [Microsoft Style Guide](https://learn.microsoft.com/en-us/style-guide/welcome/)
- [QUIP 21 - Using images in Qt documentation](https://contribute.qt-project.org/quips/21)
- [QUIP 25 - Documentation Writing Style](https://contribute.qt-project.org/quips/25)
