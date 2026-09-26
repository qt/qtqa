#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause
"""Print only the parts of a C-rule page that one topic block needs.

For a node sub-rule such as C1.5, prints the page part of the C page
(everything outside the "Node rules" section), the shared sub-rule (C1.0),
and the requested sub-rule. For a plain type such as C6, prints the whole
page. Saves loading every node sub-rule for a single-node job.

Usage:
  section.py C1.5              # page part + C1.0 + C1.5
  section.py C1.5 C1.7         # several sub-rules, shared once
  section.py C1.5 --no-page    # sub-rules only (the page is already loaded)
  section.py C6                # whole C6 page
  section.py --list            # sub-rule IDs and sizes
  section.py --selftest
"""
import argparse, re, sys
from pathlib import Path

REFS = Path(__file__).resolve().parents[2] / "skills/skill-c-rules/references"
NODE_HEAD = re.compile(r"^## Node rules\b.*$", re.M)
SUB_HEAD = re.compile(r"^### (C\d+\.\d+)\. .*$", re.M)


def page_file(ctype):
    hits = sorted(REFS.glob(f"c{ctype[1:]}-*.md"))
    if not hits:
        sys.exit(f"no page for {ctype} in {REFS}")
    return hits[0]


def split(text):
    """Return (page_part, {sub_id: text}) for a C page."""
    m = NODE_HEAD.search(text)
    if not m:
        return text, {}
    end = re.compile(r"^## ", re.M).search(text, m.end())
    end = end.start() if end else len(text)
    node, page = text[m.start():end], text[:m.start()] + text[end:]
    subs, heads = {}, list(SUB_HEAD.finditer(node))
    for i, h in enumerate(heads):
        stop = heads[i + 1].start() if i + 1 < len(heads) else len(node)
        subs[h.group(1)] = node[h.start():stop].rstrip() + "\n"
    intro = node[:heads[0].start()] if heads else node
    return page.rstrip() + "\n", subs, intro


def extract(ids, with_page=True):
    by_type = {}
    for i in ids:
        by_type.setdefault(i.split(".")[0], []).append(i)
    out = []
    for ctype, wanted in by_type.items():
        text = page_file(ctype).read_text(encoding="utf-8")
        parts = split(text)
        if len(parts) == 2 or all("." not in w for w in wanted):
            out.append(text)
            continue
        page, subs, intro = parts
        if with_page:
            out.append(page)
        out.append(intro.rstrip() + "\n")
        shared = f"{ctype}.0"
        for s in ([shared] if shared in subs and shared not in wanted else []) + wanted:
            if s not in subs:
                sys.exit(f"unknown sub-rule {s} (have: {', '.join(subs)})")
            out.append(subs[s])
    return "\n".join(out)


def listing():
    for f in sorted(REFS.glob("c*.md"), key=lambda p: int(re.match(r"c(\d+)", p.name).group(1))):
        text = f.read_text(encoding="utf-8")
        parts = split(text)
        if len(parts) == 2:
            print(f"{f.name:28} ~{len(text)//4} tok (no sub-rules)")
            continue
        page, subs, _ = parts
        print(f"{f.name:28} ~{len(text)//4} tok; page part ~{len(page)//4} tok")
        for k, v in subs.items():
            print(f"  {k:7} ~{len(v)//4} tok")


def selftest():
    ok = True
    full = page_file("C1").read_text(encoding="utf-8")
    one = extract(["C1.5"])
    checks = [("### C1.5." in one, "C1.5 present"), ("### C1.0." in one, "shared C1.0 present"),
              ("### C1.4." not in one, "C1.4 absent"), ("## Detect" in one, "page part present"),
              (len(one) < len(full), "smaller than full page"),
              ("### C1.0." not in extract(["C1.5"], with_page=False).split("### C1.5.")[1], "order"),
              (extract(["C6"]) == page_file("C6").read_text(encoding="utf-8"), "plain type returns whole page")]
    for cond, msg in checks:
        if not cond:
            print("FAIL", msg); ok = False
    print("PASS" if ok else "FAIL", f"(C1.5: ~{len(one)//4} of ~{len(full)//4} tok)")
    return ok


def main():
    a = argparse.ArgumentParser()
    a.add_argument("ids", nargs="*")
    a.add_argument("--no-page", action="store_true")
    a.add_argument("--list", action="store_true")
    a.add_argument("--selftest", action="store_true")
    o = a.parse_args()
    if o.selftest:
        sys.exit(0 if selftest() else 1)
    if o.list:
        listing(); return
    if not o.ids:
        a.error("give a C rule ID such as C1.5")
    sys.stdout.write(extract(o.ids, with_page=not o.no_page))


if __name__ == "__main__":
    main()
