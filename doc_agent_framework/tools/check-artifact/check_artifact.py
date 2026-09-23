#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

"""Run the deterministic checks on a framework artifact.

Takes one or more paths inside doc_agent_framework/ and reports every
check that a script can decide without judgment: frontmatter, model pin,
registration in the subdir READMEs and the orchestrator, skill paths,
relative links, test-scenario coverage, the public/internal boundary,
secrets, and Tier 1 AI-tell patterns.

The artifact kind comes from its location:

  agents/<name>.md               agent
  skills/**/SKILL.md             skill
  tests/scenarios/<name>/        scenario (pass the directory)
  tools/<name>/                  tool (pass the directory)
  anything else                  file (common checks only)

Each finding prints as "SEVERITY CHECK path[:line] message". Exit
status: 0 when no finding is High or Critical, 1 when at least one is,
2 on a usage error.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

FRAMEWORK = Path(__file__).resolve().parent.parent.parent
MODEL = "claude-opus-5-5"
SEVERITIES = ["Critical", "High", "Medium", "Low", "Info"]
BLOCKING = {"Critical", "High"}

DESC_SOFT, DESC_HARD = 150, 1536
BODY_LINES_SOFT, BODY_CHARS_HARD = 200, 20000

# Patterns from skill-security-hygiene, "Quick grep patterns".
SECRET_RE = re.compile(
    r"(-----BEGIN [A-Z ]+PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}"
    r"|xox[bp]-[A-Za-z0-9-]+|AIza[0-9A-Za-z_-]{35}|sk_live_[A-Za-z0-9]{20,}"
    r"|ssh-(rsa|ed25519|dss) AAAA[0-9A-Za-z+/=]+)")
HOME_RE = re.compile(r"(/Users/[^/\s]+/|/home/[^/\s]+/|[A-Z]:\\Users\\[^\\]+\\|~/code/)")
QT_HOST_RE = re.compile(r"\b([a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:qt-project\.org|qt\.io))\b")
PUBLIC_HOSTS = {"doc.qt.io", "doc-snapshots.qt.io", "wiki.qt.io", "code.qt.io",
                "contribute.qt-project.org", "codereview.qt-project.org",
                "bugreports.qt.io", "qt-project.atlassian.net", "www.qt.io", "qt.io"}

# Tier 1 patterns from skill-ai-tells. Each hit is a finding; a person
# confirms it is prose and not a quoted pattern.
AI_TELLS = [
    ("T1a", re.compile(r" —[^—]*— ")),
    ("T6", re.compile(r"not only|on the other hand|on one hand", re.I)),
    ("T7", re.compile(r"\b(in conclusion|overall|ultimately|in summary|to sum up)\b", re.I)),
    ("T13", re.compile(r"\b(cutting-edge|state-of-the-art|world-class|next-generation"
                       r"|pivotal|holistic)\b", re.I)),
    ("T14", re.compile(r"it depends|both have|some (developers|users).*others", re.I)),
    ("T16", re.compile(r"\b(page|class|function|api|method|code|type|module|docs|widget|reader)s? "
                       r"(speaks|hears|knows|wants|understands|cares|thinks|remembers|decides"
                       r"|lives|sits|feels|asks)\b", re.I)),
    ("T17", re.compile(r"(is|are) not [^.]{2,40}\. *(It|They|That) (is|are)"
                       r"|(isn't|aren't)[^.]{0,45}(it's|they're)", re.I)),
    ("T18", re.compile(r"\b(delve|delves|plethora|tapestry|testament|nuanced|elevate|empower"
                       r"|intricate|effortless|effortlessly|boasts|synergy|undoubtedly)\b", re.I)),
]

LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
SKILL_REF_RE = re.compile(r"\.\./skills/([A-Za-z0-9_./-]+?)/SKILL\.md")


class Report:
    def __init__(self):
        self.findings = []
        self.checks = []

    def ran(self, check):
        if check not in self.checks:
            self.checks.append(check)

    def add(self, severity, check, path, message, line=None):
        self.ran(check)
        self.findings.append({"severity": severity, "check": check,
                              "path": rel(path), "line": line, "message": message})


def rel(path):
    try:
        return str(Path(path).resolve().relative_to(FRAMEWORK))
    except ValueError:
        return str(path)


def read(path):
    return Path(path).read_text(encoding="utf-8", errors="replace")


def frontmatter(text):
    """Parse the simple YAML subset the framework uses. Returns (dict, body)."""
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---", 4)
    if end < 0:
        return None, text
    block, body = text[4:end], text[end + 4:].lstrip("\n")
    data, key, folded = {}, None, None
    for raw in block.splitlines():
        if folded is not None and (raw.startswith("  ") or not raw.strip()):
            folded.append(raw.strip())
            data[key] = " ".join(p for p in folded if p)
            continue
        folded = None
        match = re.match(r"^(\s*)([A-Za-z_]+):\s*(.*)$", raw)
        if not match:
            continue
        indent, name, value = match.groups()
        if indent and key == "metadata":
            data[f"metadata.{name}"] = value.strip().strip("\"'")
            continue
        key = name
        if value in (">-", ">", "|", "|-"):
            folded = []
            data[key] = ""
        else:
            data[key] = value.strip().strip("\"'")
    return data, body


def table_rows(text, heading):
    """Return the cells of each row in the first table under a heading."""
    lines = text.splitlines()
    rows, inside = [], False
    for line in lines:
        if line.startswith("#"):
            if inside and rows:
                break
            inside = line.lstrip("#").strip().lower() == heading.lower()
            continue
        if inside and line.startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if not all(set(c) <= set("-: ") for c in cells):
                rows.append(cells)
    return rows[1:] if rows else []


def strip_md(cell):
    return re.sub(r"[`*\[\]]|\(.*?\)", "", cell).strip()


def prose_lines(text):
    """Yield (line number, line, inside fenced code) for a Markdown file."""
    fenced = False
    for number, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        yield number, line, fenced


# Common checks, every file ------------------------------------------------

def check_common(path, report):
    text = read(path)
    is_md = path.suffix == ".md"
    for check in ("boundary-home-path", "boundary-host", "secret", "ai-tell-tier1"):
        report.ran(check)
    if is_md:
        report.ran("link")
    for number, line, fenced in (prose_lines(text) if is_md else
                                 ((n, l, False) for n, l in enumerate(text.splitlines(), 1))):
        if SECRET_RE.search(line):
            report.add("Critical", "secret", path, "possible secret or key", number)
        for match in HOME_RE.finditer(line):
            if is_placeholder(match, line):
                continue
            report.add("High", "boundary-home-path", path,
                       f"user-specific path: {match.group(0)}", number)
        for host in QT_HOST_RE.findall(line):
            if host not in PUBLIC_HOSTS:
                report.add("Medium", "boundary-host", path,
                           f"Qt host not on the public list, needs a human check: {host}", number)
        if is_md and not fenced:
            for target in LINK_RE.findall(line):
                check_link(path, target, number, report)
        if is_md:
            for tell, pattern in AI_TELLS:
                if pattern.search(line):
                    report.add("Medium", "ai-tell-tier1", path,
                               f"{tell} pattern: {pattern.search(line).group(0)!r} "
                               f"(confirm it is a tell, then treat as High)", number)


def is_placeholder(match, line):
    """True for rule text such as /Users/<name>/, ~/code/..., or a regex."""
    text, after = match.group(0), line[match.end():match.end() + 1]
    return (any(c in text for c in "<[{") or after in ("…", ".")
            or "USERNAME" in line or "[^" in line)


def check_link(path, target, number, report):
    if re.match(r"^[a-z]+:", target) or target.startswith("#") or "{" in target:
        return
    target = target.split("#", 1)[0]
    if target and not (path.parent / target).exists():
        report.add("Medium", "link", path, f"relative link does not resolve: {target}", number)


# Agents -------------------------------------------------------------------

def check_agent(path, report):
    text = read(path)
    data, body = frontmatter(text)
    name = path.stem
    report.ran("frontmatter")
    if data is None:
        report.add("High", "frontmatter", path, "no YAML frontmatter")
        data = {}
    for field in ("name", "description", "model"):
        if not data.get(field):
            report.add("High", "frontmatter", path, f"missing '{field}'")
    if data.get("name") and data["name"] != name:
        report.add("High", "frontmatter", path, f"name '{data['name']}' differs from file name '{name}'")
    report.ran("model-pin")
    if data.get("model") and data["model"] != MODEL:
        report.add("High", "model-pin", path, f"model is '{data['model']}', expected '{MODEL}'")
    check_description(path, data.get("description", ""), report)
    check_size(path, body, report, lines_soft=None)

    report.ran("overview-fields")
    for field in ("Pipeline", "Fan-out", "Loading pattern"):
        if not re.search(rf"^\|\s*{field}\s*\|", body, re.M) and name != "orchestrator":
            report.add("Medium", "overview-fields", path, f"overview table has no '{field}' row")
    report.ran("verification-gate")
    if not re.search(r"^#+ .*verification", body, re.I | re.M):
        report.add("Medium", "verification-gate", path, "no verification gate section")

    agents_readme = FRAMEWORK / "agents" / "README.md"
    rows = [r for r in table_rows(read(agents_readme), "Pipeline mapping") if len(r) >= 4]
    mine = [r for r in rows if strip_md(r[2]) == name]
    report.ran("registered-agents-readme")
    if not mine:
        report.add("Medium", "registered-agents-readme", agents_readme,
                   f"no row for '{name}' in the pipeline mapping table")
    report.ran("fan-out-consistency")
    tools = data.get("tools")
    if mine and tools is not None:
        listed_yes = any(strip_md(r[3]).lower().startswith("yes") for r in mine)
        has_agent = re.search(r"\bAgent\b", tools) is not None
        if listed_yes != has_agent:
            report.add("High", "fan-out-consistency", path,
                       f"agents/README.md says fan-out {'yes' if listed_yes else 'no'}, "
                       f"but tools: {'includes' if has_agent else 'omits'} Agent")

    if name != "orchestrator":
        orchestrator = FRAMEWORK / "agents" / "orchestrator.md"
        report.ran("registered-orchestrator")
        dispatch = table_rows(read(orchestrator), "Dispatch table")
        if not any(len(r) > 1 and strip_md(r[1]) == name for r in dispatch):
            report.add("Medium", "registered-orchestrator", orchestrator,
                       f"no dispatch table row for '{name}'")
        report.ran("instruction")
        howto = FRAMEWORK / "doc" / "instructions" / f"how-to-use-{name}.md"
        if not howto.exists():
            report.add("Low", "instruction", howto, "no how-to instruction (CONTRIBUTING step 6)")
        check_scenarios(path, name, report)

    report.ran("skill-path")
    seen = set()
    for number, line in enumerate(text.splitlines(), 1):
        for skill in SKILL_REF_RE.findall(line):
            if "{" in skill or skill in seen:
                continue
            seen.add(skill)
            if not (FRAMEWORK / "skills" / skill / "SKILL.md").exists():
                report.add("Medium", "skill-path", path,
                           f"loads ../skills/{skill}/SKILL.md, which is not in the framework",
                           number)


def check_scenarios(path, name, report):
    report.ran("scenario-coverage")
    tests_readme = FRAMEWORK / "tests" / "README.md"
    rows = table_rows(read(tests_readme), "Scenarios")
    found = [strip_md(r[0]) for r in rows if len(r) > 1 and strip_md(r[1]) == name]
    if found:
        report.add("Info", "scenario-coverage", path, f"scenarios: {', '.join(found)}")
    else:
        report.add("Medium", "scenario-coverage", path,
                   "no test scenario lists this agent in tests/README.md")


# Skills -------------------------------------------------------------------

def check_skill(path, report):
    text = read(path)
    data, body = frontmatter(text)
    name = path.parent.name
    report.ran("frontmatter")
    if data is None:
        report.add("High", "frontmatter", path, "no YAML frontmatter")
        data = {}
    for field in ("name", "description", "metadata.version"):
        if not data.get(field):
            report.add("High" if field != "metadata.version" else "Medium",
                       "frontmatter", path, f"missing '{field}'")
    if data.get("name") and data["name"] != name:
        report.add("High", "frontmatter", path, f"name '{data['name']}' differs from directory '{name}'")
    report.ran("model-pin")
    if "model" in data:
        report.add("Medium", "model-pin", path, "skills carry no model field")
    check_description(path, data.get("description", ""), report)
    check_size(path, body, report, lines_soft=BODY_LINES_SOFT)

    report.ran("registered-skills-readme")
    # A skill in a group directory (skills/personas/) may be listed in
    # the group README instead of skills/README.md.
    skills_dir = FRAMEWORK / "skills"
    readmes = [skills_dir / "README.md"]
    readmes += [p / "README.md" for p in path.parent.parents
                if skills_dir in p.parents and (p / "README.md").exists()]
    if not any(name in read(r) for r in readmes):
        report.add("Medium", "registered-skills-readme", readmes[0],
                   f"'{name}' is not listed in skills/README.md")
    report.ran("loaded-by-agent")
    # A skill in a group directory can be loaded through a template
    # path such as ../skills/personas/skill-persona-{name}/SKILL.md.
    group = path.parent.parent
    group_ref = (f"skills/{group.relative_to(skills_dir)}/" if group != skills_dir else None)
    loaders = [a.stem for a in (FRAMEWORK / "agents").glob("*.md")
               if a.name != "README.md" and (name in read(a) or
                                             (group_ref and group_ref in read(a)))]
    if loaders:
        report.add("Info", "loaded-by-agent", path, f"referenced by: {', '.join(sorted(loaders))}")
    else:
        report.add("Medium", "loaded-by-agent", path, "no agent in agents/ references this skill")



# Scenarios and tools ------------------------------------------------------

def check_scenario(path, report):
    name = path.name
    report.ran("scenario-files")
    for required in ("input.patch", "README.md"):
        if not (path / required).is_file():
            report.add("High", "scenario-files", path, f"missing {required}")
    if not any((path / f).is_file() for f in ("expected-warnings.txt", "expected-findings.txt")):
        report.add("High", "scenario-files", path, "no expected output file")
    report.ran("registered-tests-readme")
    rows = table_rows(read(FRAMEWORK / "tests" / "README.md"), "Scenarios")
    row = [r for r in rows if strip_md(r[0]) == name]
    if not row:
        report.add("Medium", "registered-tests-readme", FRAMEWORK / "tests" / "README.md",
                   f"no row for scenario '{name}'")
    else:
        agent = strip_md(row[0][1])
        report.ran("scenario-agent-exists")
        if not (FRAMEWORK / "agents" / f"{agent}.md").exists():
            report.add("Medium", "scenario-agent-exists", path,
                       f"scenario names agent '{agent}', which is not in agents/")
    for file in sorted(path.iterdir()):
        if file.suffix == ".md":
            check_common(file, report)


def check_tool(path, report):
    report.ran("tool-readme")
    if not (path / "README.md").is_file():
        report.add("Medium", "tool-readme", path, "no README.md in the tool directory")
    report.ran("spdx")
    report.ran("registered-tools-readme")
    if path.name not in read(FRAMEWORK / "tools" / "README.md"):
        report.add("Medium", "registered-tools-readme", FRAMEWORK / "tools" / "README.md",
                   f"'{path.name}' is not listed in tools/README.md")
    for file in sorted(path.rglob("*")):
        if file.suffix in (".py", ".sh") and "SPDX-License-Identifier" not in read(file)[:500]:
            report.add("Medium", "spdx", file, "no SPDX-License-Identifier header")
        if file.suffix in (".md", ".py", ".sh"):
            check_common(file, report)


def check_description(path, description, report):
    report.ran("description-length")
    size = len(description)
    if size > DESC_HARD:
        report.add("High", "description-length", path, f"description is {size} chars (cap {DESC_HARD})")
    elif size > DESC_SOFT:
        report.add("Low", "description-length", path, f"description is {size} chars (target {DESC_SOFT})")


def check_size(path, body, report, lines_soft):
    report.ran("body-size")
    chars, lines = len(body), body.count("\n") + 1
    if chars > BODY_CHARS_HARD:
        report.add("High", "body-size", path,
                   f"body is {chars} chars; content past ~{BODY_CHARS_HARD} is dropped on re-attach")
    if lines_soft and lines > lines_soft:
        report.add("Low", "body-size", path, f"body is {lines} lines (split threshold {lines_soft})")


# Driver -------------------------------------------------------------------

def classify(path):
    parts = path.resolve().relative_to(FRAMEWORK).parts
    if parts[0] == "agents" and len(parts) == 2 and path.suffix == ".md" and path.name != "README.md":
        return "agent"
    if parts[0] == "skills" and path.name == "SKILL.md":
        return "skill"
    if parts[:2] == ("tests", "scenarios") and len(parts) == 3 and path.is_dir():
        return "scenario"
    if parts[0] == "tools" and len(parts) == 2 and path.is_dir():
        return "tool"
    return "file"


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", help="artifacts inside doc_agent_framework/")
    parser.add_argument("--root", help="framework root to check against "
                        "(default: the tree this script lives in)")
    parser.add_argument("--json", action="store_true", help="print the report as JSON")
    parser.add_argument("--min-severity", choices=SEVERITIES, default="Info",
                        help="hide findings below this severity (text output only)")
    args = parser.parse_args()
    if args.root:
        global FRAMEWORK
        FRAMEWORK = Path(args.root).resolve()
        if not (FRAMEWORK / "agents" / "orchestrator.md").is_file():
            print(f"error: {args.root} has no agents/orchestrator.md", file=sys.stderr)
            return 2

    results = []
    for arg in args.paths:
        path = Path(arg).resolve()
        if not path.exists():
            print(f"error: no such path: {arg}", file=sys.stderr)
            return 2
        try:
            path.relative_to(FRAMEWORK)
        except ValueError:
            print(f"error: {arg} is not inside {FRAMEWORK}", file=sys.stderr)
            return 2
        kind = classify(path)
        report = Report()
        if kind == "agent":
            check_agent(path, report)
        elif kind == "skill":
            check_skill(path, report)
        elif kind == "scenario":
            check_scenario(path, report)
        elif kind == "tool":
            check_tool(path, report)
        if kind in ("agent", "skill", "file"):
            if path.is_dir():
                print(f"error: pass a file, not a directory: {arg}", file=sys.stderr)
                return 2
            check_common(path, report)
        results.append({"artifact": rel(path), "kind": kind,
                        "checks": report.checks, "findings": report.findings})

    blocking = sum(f["severity"] in BLOCKING for r in results for f in r["findings"])
    if args.json:
        print(json.dumps({"framework": str(FRAMEWORK), "results": results,
                          "blocking": blocking}, indent=2))
    else:
        cutoff = SEVERITIES.index(args.min_severity)
        for r in results:
            print(f"== {r['artifact']} ({r['kind']}): {len(r['checks'])} checks ran")
            order = sorted(r["findings"], key=lambda f: (SEVERITIES.index(f["severity"]),
                                                         f["check"], f["path"], f["line"] or 0))
            for f in order:
                if SEVERITIES.index(f["severity"]) > cutoff:
                    continue
                loc = f"{f['path']}:{f['line']}" if f["line"] else f["path"]
                print(f"{f['severity']:<8} {f['check']:<26} {loc} {f['message']}")
        print(f"{blocking} blocking (High or Critical) finding(s)")
    return 1 if blocking else 0


if __name__ == "__main__":
    sys.exit(main())
