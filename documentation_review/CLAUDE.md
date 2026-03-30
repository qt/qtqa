# CLAUDE.md

## Resource Priority

**Always check `~/.claude/` first for skills and agents:**
- Skills: `~/.claude/skills/`
- Agents: `~/.claude/agents/`

Load agent definitions from `~/.claude/agents/*.md` when invoking agents with the Task tool.

## Role

Qt Documentation team workflow. Primary focus:
- Writing and editing Qt Reference Documentation
- Reviewing documentation patches for style, accuracy, and QDoc correctness
- Auditing documentation against Qt Writing Guidelines, QUIP 25, and Microsoft Style Guide

Secondary: QDoc tool development and documentation tooling (optional).

## Agent-First Workflow

**ALWAYS delegate to agents using the Task tool. NEVER work directly or summarize.**

### Dispatch Process

1. **Read agent definition** from `~/.claude/agents/{agent}.md`
2. **Extract the Agent Prompt** section from the file
3. **Spawn Task tool** with that prompt + user's input
4. **Receive agent output** - agent loads skills and outputs in Doc Team diff format
5. **Verify output** against skills (rule citations, line lengths, link targets, format)
6. **Output FULL Doc Team diff** to user - no summaries, show complete suggestions

### Dispatch Rules

| Task | Agent | Action |
|------|-------|--------|
| Documentation review | qt-doc-reviewer | Task tool with Agent Prompt from file + input |
| QDoc warnings | qdoc-warning-fixer | Task tool with Agent Prompt from file + input |
| Vale linting of QDoc sources | vale-qdoc-linter | Task tool with Agent Prompt from file + input |

### Verification

**Verify ALL input AND output** according to Qt guidelines and skills.

**CRITICAL: Verify BEFORE presenting suggestions, not after.**

**Source data verification** (BEFORE reviewing):
1. **Prefer local files over WebFetch** - If patch is available locally, ALWAYS read actual files with Read tool
2. **WebFetch is unreliable** - May return corrupted, truncated, or decoded data; verify against local source
3. **Never trust WebFetch for exact content** - Use it only when local files unavailable

**Upfront verification** (BEFORE presenting any fix):
1. **Search index for link target** - `grep 'name="Target"' */doc/*/*.index`
2. **Verify exact target name** - Check `name` attribute (e.g., signals have no parentheses)
3. **Check access** - Verify `access="public"` not `status="internal"`
4. **Get HTML field** - NEVER GUESS. Verify by document type:
   - **For `\page` docs (overviews):** Read source file, find `\page filename.html` command
   - **For type docs (class/QML type):** Search index for CONTAINING TYPE, extract `href`
   - This is the page reviewer opens to verify the fix works
   - Editing SearchField docs? Search `grep 'name="SearchField"'` → get SearchField's href
   - NOT the href of the broken link target
   - If cannot verify, OMIT the HTML field entirely

**Input verification** - command line, agents, proposed fixes:
1. **Link targets** - Grep source for `\class`, `\qmltype`, `\qmlproperty`, etc.
2. **Target is public** - Not marked `\internal`
3. **QDoc syntax** - Verify against skill-qdoc (link resolution, genus)
4. **Export + internal is VALID** - Do NOT reject `\internal` for `*Private`, QPA, or `_p.h` classes even with export macros (see skill-module-export)

**Output verification** - before presenting results:
1. **Rule citations** - Verify against skill-language-style (R1-R57)
2. **QDoc syntax** - Verify against skill-qdoc and skill-language-style R39
3. **Line lengths** - Verify against skill-language-style R40 (≤80 columns)
4. **Format compliance** - Verify matches skill-doc-diff exactly
5. **Language review COMPLETE** - Verify agent checked ALL prose against R1-R57:
   - Every new/changed line of prose reviewed
   - Latin terms checked (R38): "via", "e.g.", "i.e.", "etc."
   - Passive voice checked (R1)
   - Wordiness checked (R2): "in order to", "provide a way to", etc.
   - Articles checked (R10): missing "the", "a", "an"
   - Parallel structure in lists (R9)
   - If agent stopped after QDoc issues, REJECT and require full language review
6. **HTML field verified** - Must be from index file search, never guessed
7. **Fix Options verified** - When agent presents multiple options:
   - Verify each option is valid and correctly described
   - Verify recommended option is appropriate for the context
   - Verify options cover the realistic choices (not missing obvious alternatives)
   - **Check if options are necessary** - If existing codebase usage, consistency, or best practice clearly indicates one correct answer, Fix Options should NOT be used. Search codebase for existing patterns first.
   - Flag if agent used Fix Options when one option is clearly correct based on existing usage

Flag any corrections made.

## Output Format

**ALL documentation suggestions require Doc Team diff format (skill-doc-diff).**

### When to Use Doc Team Diff

| Situation | Format |
|-----------|--------|
| Patch has issues requiring changes | Doc Team diff (MANDATORY) |
| Suggesting fixes (via agent OR direct) | Doc Team diff (MANDATORY) |
| Patch approved with no issues | Plain summary acceptable |
| Research/analysis with no actionable changes | Plain summary acceptable |

### Direct Work Fallback

If working directly (not via agent), you MUST:
1. **Load skill-doc-diff FIRST** - Read `~/.claude/skills/skill-doc-diff/SKILL.md` before analyzing
2. **Format ALL suggestions** using Doc Team diff template
3. **Never present bare summaries** for actionable issues

### Format Requirements

Every suggestion must include:
- Suggestion header with `file:line`
- Category field
- Source field (full repo path)
- Output field (if verifiable)
- Diff block with proper line alignment (arrows)
- Cause (why + evidence)
- Validation with ✓/✗ checks and rule references
- Comments

**Bare summaries like "change X to Y" are NOT acceptable for actionable suggestions.**

## Skills & Agents

**Skills** (reference materials - agents load with Read tool, NOT Skill tool):
| Skill | File | Purpose |
|-------|------|---------|
| skill-doc-diff | `SKILL.md` | Doc Team diff format (MANDATORY output format) |
| skill-language-style | `SKILL.md` | Language, grammar, QUIP 25, MS Style Guide, terminology |
| skill-qdoc | `SKILL.md` | QDoc internals, link warning diagnosis and fixes |
| skill-qdoc-output | `SKILL.md` | QDoc HTML filename generation patterns by node type |
| skill-alttext | `SKILL.md` | Alt text formatting |
| skill-line-wrap | `SKILL.md` | 80-column rule compliance |
| skill-all-docs | `SKILL.md` | Qt modules, repository structure, API types |
| skill-module-export | `SKILL.md` | Qt export macros; export+internal pattern guidance |
| skill-vale-qdoc-lint | `SKILL.md` | Vale binary setup, qtqa config, pre-commit hook, lint commands, report formats |

**Agents** (definitions in `~/.claude/agents/`):
| Agent | Purpose |
|-------|---------|
| qt-doc-reviewer | Documentation patch review |
| qdoc-warning-fixer | Fix all QDoc warning types |
| vale-qdoc-linter | Setup vale-qdoc and lint QDoc source files; report as annotated diff |

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
