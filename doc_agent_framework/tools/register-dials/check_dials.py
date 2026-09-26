#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause
"""Check the [tool] register dials on a text or QDoc file.

Reads skills/skill-g-rules/references/register-dials.toml, resolves the
register for a content type (with its overrides), and reports:
  - sentences over sentence_words_max
  - contraction density against contraction_density_max (per 1,000 words)
  - "we" / "our" and first person singular counts
  - sentence-initial "So" candidates (conversational marker)
The LLM dials (person, tone, structure, analogies) are printed so the
reviewer applies them; this script doesn't judge them.

Usage:
  check_dials.py --type C6 FILE [--register conceptual]
  check_dials.py --show C4           # print resolved dials for a type
  check_dials.py --selftest
"""
import argparse, json, re, sys, tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIALS = ROOT / "skills/skill-g-rules/references/register-dials.toml"
CONTRACTION = re.compile(r"\b\w+n't\b|\b(?:it|you|we|that|there|here|they|I)'(?:s|ll|re|ve|d|m)\b", re.I)


def load():
    return tomllib.loads(DIALS.read_text(encoding="utf-8"))


def resolve(d, ctype, register=None):
    ct = d["content_types"][ctype]
    regs = ct.get("registers", [])
    if not regs:
        return None
    name = register or regs[0]
    if name not in regs:
        sys.exit(f"{ctype} doesn't use register '{name}' (uses {regs})")
    dials = dict(d["registers"][name])
    dials.update(ct.get("overrides", {}))
    dials["register"] = name
    return dials


def prose(text):
    text = re.sub(r"\\(code|badcode|qml)\b.*?\\endcode", " ", text, flags=re.S)
    text = re.sub(r"\\snippet[^\n]*", " ", text)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\\[a-z]+(\{[^}]*\})?", " ", text)
    return " ".join(text.split())


def check(text, dials, so_pattern):
    p = prose(text)
    words = len(p.split()) or 1
    sents = [s for s in re.split(r"(?<=[.!?])\s+", p) if s]
    long = [s for s in sents if len(s.split()) > dials["sentence_words_max"]]
    contr = len(CONTRACTION.findall(p))
    density = 1000 * contr / words
    return {
        "register": dials["register"],
        "words": words,
        "sentences_over_max": len(long),
        "sentence_words_max": dials["sentence_words_max"],
        "long_examples": [s[:120] for s in long[:5]],
        "contraction_density": round(density, 2),
        "contraction_density_max": dials["contraction_density_max"],
        "contraction_over": density > dials["contraction_density_max"],
        "we_our": len(re.findall(r"\b(?:we|our|us)\b", p, re.I)),
        "we_policy": dials["we_allowed"],
        "first_person_singular": len(re.findall(r"\bI\b(?!\.)", p)),
        "first_person_singular_allowed": dials["first_person_singular"],
        "so_candidates": len(re.findall(so_pattern, p)),
        "llm_dials": {k: dials[k] for k in ("person", "tense", "mood", "tone", "structure", "analogies_max", "asides") if k in dials},
    }


def selftest(d):
    ok = True
    for c, ct in d["content_types"].items():
        for r in ct.get("registers", []):
            if r not in d["registers"]:
                print(f"FAIL {c}: unknown register {r}"); ok = False
            for k in ct.get("overrides", {}):
                if k not in d["registers"][r]:
                    print(f"FAIL {c}: override '{k}' isn't a dial of {r}"); ok = False
    for name, r in d["registers"].items():
        if "markers" in r:
            continue
        for k in ("sentence_words_max", "contraction_density_max", "we_allowed", "first_person_singular"):
            if k not in r:
                print(f"FAIL register {name}: missing {k}"); ok = False
    so = d["registers"]["conversational"]["so_pattern"]
    sample = "So, to use the model, set it on the view. We think it's great, isn't it? " + "word " * 40 + "end."
    res = check(sample, resolve(d, "C6"), so)
    for cond, msg in [(res["so_candidates"] == 1, "So candidate"), (res["we_our"] == 1, "we count"),
                      (res["sentences_over_max"] == 1, "long sentence"), (res["contraction_over"], "contraction density")]:
        if not cond:
            print(f"FAIL selftest: {msg} {res}"); ok = False
    print("PASS" if ok else "FAIL")
    return ok


def main():
    a = argparse.ArgumentParser()
    a.add_argument("file", nargs="?")
    a.add_argument("--type")
    a.add_argument("--register")
    a.add_argument("--show")
    a.add_argument("--selftest", action="store_true")
    o = a.parse_args()
    d = load()
    if o.selftest:
        sys.exit(0 if selftest(d) else 1)
    if o.show:
        print(json.dumps(resolve(d, o.show, o.register), indent=2)); return
    if not (o.type and o.file):
        a.error("need --type and FILE")
    dials = resolve(d, o.type, o.register)
    if dials is None:
        print(f"{o.type}: no register (no prose rules)"); return
    res = check(Path(o.file).read_text(encoding="utf-8", errors="ignore"), dials, d["registers"]["conversational"]["so_pattern"])
    print(json.dumps(res, indent=2))


if __name__ == "__main__":
    main()
