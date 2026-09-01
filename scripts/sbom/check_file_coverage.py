#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

"""
check_file_coverage.py — Audit file-level SBOM coverage of an installed Qt
tree, in both directions:

  forward   Is every shipped binary recorded in one of the SBOM documents
            under <prefix>/sbom? Scoped to --dirs, which defaults to the six
            directories Qt's SPDX documents actually record into:
            bin, lib, libexec, plugins, qml, translations. Auditing the
            whole prefix instead adds no binaries at all (verified on a
            6.12.0 macOS install: 523 either way) and drowns the report in
            headers, CMake files and QML sources that no SBOM lists.

  reverse   Does every file recorded in those documents actually exist in
            the install tree? Never scoped by --dirs: a stale entry is a
            defect wherever it points, and the documents also cover
            plugins/, qml/ and translations/.

  documents Does every module ship the full set of SBOM formats? A module
            with no *.cdx.json has zero CycloneDX coverage no matter what
            its SPDX documents say.

Why file coverage is computed from the SPDX documents, not the CycloneDX
ones:
    Qt ships both *.cdx.json (CycloneDX 1.6) and *.spdx / *.spdx.json
    (SPDX 2.3) per module. Only the SPDX documents carry file-level data
    ('files' entries with fileName + SHA1). The CycloneDX documents
    describe packages only — as of 6.12.0 not one of them populates
    evidence.occurrences, so they contain no installed path anywhere and
    coverage simply cannot be checked against them. Since both formats are
    emitted from the same component set (CycloneDX bom-refs are the SPDX
    SPDXRef-Package ids), a file missing from the SPDX documents is missing
    from the CycloneDX ones too. The script reports the CycloneDX
    occurrence count so a regression there stays visible.

    The tag-value *.spdx documents are not read: they carry the same
    FileName set as their *.spdx.json counterparts. The *.source.spdx
    documents are not read either — they describe the module's source
    tree (tens of thousands of paths relative to the git repository, not
    to the install prefix), so they say nothing about installed files.

Files are classified by magic bytes rather than by extension, because Qt's
macOS framework binaries and its universal static libraries carry no
recognizable suffix (a universal .a is a fat Mach-O, not '!<arch>').

On --verify-sha1 in an *installed* tree:
    Expect mismatches on every code-signed Mach-O. Installers re-sign and
    install_name_tool-relocate binaries after the SBOM checksums are
    written, so frameworks and executables legitimately differ from their
    recorded SHA1. Static .a files and data files such as .qm translations
    are not touched and should always match — those are the meaningful
    integrity signal here.

Usage:
    python check_file_coverage.py ~/Qt/6.12.0/macos
    python check_file_coverage.py <prefix> --dirs bin,lib,libexec
    python check_file_coverage.py <prefix> --verify-sha1
    python check_file_coverage.py <prefix> --reverse-only

Exit code is 0 only if every binary and static library found is recorded in
some SBOM, and every recorded file exists on disk as a regular non-empty
file. Unrecorded scripts and data files, and incomplete SBOM document sets,
are reported but do not affect the exit code.
"""

import argparse
import glob
import hashlib
import json
import os
import sys
from collections import Counter, defaultdict

# Mach-O (both endiannesses, 32/64 bit), fat/universal, ELF, PE.
BINARY_MAGIC = (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
                b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
                b"\x7fELF", b"MZ")
ARCHIVE_MAGIC = b"!<arch>\n"

# Directories the SPDX documents record installed files into, and thus the
# forward check's default scope. Kept in sync with the reverse check's
# per-directory breakdown: if that grows a row not listed here, add it.
DEFAULT_DIRS = "bin,lib,libexec,plugins,qml,translations"

# Per-module SBOM flavors, longest suffix first so stripping is unambiguous.
SBOM_FLAVORS = (".source.spdx", ".spdx.json", ".cdx.json", ".spdx")
# Flavors that describe the installed tree; .source.spdx describes the
# source repository and is therefore not required for file coverage.
INSTALL_FLAVORS = (".spdx", ".spdx.json", ".cdx.json")


def classify(path):
    """Return 'binary', 'script' or 'data' based on the file's magic bytes."""
    try:
        with open(path, "rb") as f:
            magic = f.read(8)
    except OSError:
        return "data"
    if magic.startswith(BINARY_MAGIC) or magic == ARCHIVE_MAGIC:
        return "binary"
    if magic[:2] == b"#!":
        return "script"
    return "data"


def load_sboms(sbomdir):
    """Return ({relpath: (document, sha1 or None)}, {cdx document: occurrences}).

    Paths are normalized by stripping the leading './' that Qt's SPDX
    writer emits. The first document mentioning a path wins; duplicates
    across modules are harmless for a coverage check.
    """
    claimed, cdx = {}, {}
    for path in sorted(glob.glob(os.path.join(sbomdir, "*.json"))):
        name = os.path.basename(path)
        with open(path) as f:
            doc = json.load(f)
        if name.endswith(".spdx.json"):
            for entry in doc.get("files", []):
                sha1 = next((c["checksumValue"].lower()
                             for c in entry.get("checksums", [])
                             if c.get("algorithm") == "SHA1"), None)
                claimed.setdefault(entry["fileName"].lstrip("./"), (name, sha1))
        elif name.endswith(".cdx.json"):
            cdx[name] = sum(len(c.get("evidence", {}).get("occurrences", []))
                            for c in doc.get("components", []))
    return claimed, cdx


def scan_tree(prefix, dirs):
    """Walk dirs under prefix, returning (Counter of kinds, {kind: [relpath]}).

    Symlinks are skipped on both files and directories: following them would
    count every macOS framework twice (Versions/Current, and the top-level
    Headers/QtCore aliases) and every versioned .dylib three times.
    """
    totals, files = Counter(), defaultdict(list)
    for d in dirs:
        for dirpath, dirnames, filenames in os.walk(os.path.join(prefix, d)):
            dirnames[:] = [x for x in dirnames
                           if not os.path.islink(os.path.join(dirpath, x))]
            for filename in filenames:
                full = os.path.join(dirpath, filename)
                if os.path.islink(full):
                    continue
                kind = classify(full)
                totals[kind] += 1
                files[kind].append(os.path.relpath(full, prefix))
    return totals, files


def exact_case_path(prefix, rel):
    """True if rel exists under prefix with exactly the recorded spelling.

    os.path.exists lies about case on APFS and NTFS, so a recorded
    './bin/Assistant' would look fine while the tree ships 'assistant'.
    Consumers that resolve SBOM paths on a case-sensitive filesystem would
    then fail, so compare each component against the real directory entries.
    """
    current = prefix
    for component in rel.split("/"):
        try:
            entries = os.listdir(current)
        except OSError:
            return False
        if component not in entries:
            return False
        current = os.path.join(current, component)
    return True


def check_recorded(prefix, claimed):
    """Reverse direction: verify every recorded path exists as a real file.

    Returns (per-top-level-directory Counter, missing, suspect) where
    missing is [(relpath, document)] for paths that are not there at all
    and suspect is [(relpath, document, reason)] for paths that resolve but
    are not the plain, non-empty, exactly-named file the SBOM implies.
    """
    stats = defaultdict(Counter)
    missing, suspect = [], []
    for rel, (doc, _) in sorted(claimed.items()):
        top = rel.split("/")[0]
        full = os.path.join(prefix, rel)
        if not os.path.lexists(full):
            stats[top]["missing"] += 1
            missing.append((rel, doc))
            continue
        stats[top]["present"] += 1
        if os.path.islink(full):
            suspect.append((rel, doc, "symlink, not the file itself"))
        elif os.path.isdir(full):
            suspect.append((rel, doc, "directory, not a file"))
        elif os.path.getsize(full) == 0:
            suspect.append((rel, doc, "zero bytes"))
        elif not exact_case_path(prefix, rel):
            suspect.append((rel, doc, "differs in case from the real entry"))
    return stats, missing, suspect


def check_document_set(sbomdir):
    """Return {module: [flavors it lacks]} across all per-module SBOM files."""
    have = defaultdict(set)
    for name in sorted(os.listdir(sbomdir)):
        for flavor in SBOM_FLAVORS:
            if name.endswith(flavor):
                have[name[:-len(flavor)]].add(flavor)
                break
    return {module: [f for f in SBOM_FLAVORS if f not in flavors]
            for module, flavors in sorted(have.items())
            if len(flavors) < len(SBOM_FLAVORS)}


def verify_checksums(prefix, claimed):
    """Return (matched count, [(relpath, document, recorded, actual)]).

    Covers every recorded path, not just the --dirs scope, for the same
    reason the reverse check does.
    """
    matched, mismatched = 0, []
    for rel, (doc, sha1) in sorted(claimed.items()):
        full = os.path.join(prefix, rel)
        if not sha1 or not os.path.isfile(full):
            continue
        digest = hashlib.sha1()
        with open(full, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                digest.update(chunk)
        if digest.hexdigest() == sha1:
            matched += 1
        else:
            mismatched.append((rel, doc, sha1, digest.hexdigest()))
    return matched, mismatched


def report_forward(prefix, dirs, claimed, args):
    """Print the installed -> SBOM direction. Returns unrecorded binaries."""
    totals, files = scan_tree(prefix, dirs)
    unrecorded = {kind: sorted(p for p in paths if p not in claimed)
                  for kind, paths in files.items()}

    print(f"=== forward: installed files -> SBOM ({','.join(dirs)}) ===")
    print(f"{'kind':10}{'installed':>10}{'recorded':>10}{'missing':>9}")
    for kind in ("binary", "script", "data"):
        total, missing = totals[kind], len(unrecorded.get(kind, ()))
        print(f"{kind:10}{total:10}{total - missing:10}{missing:9}")
    print()

    listed = ["binary", "script"] + (["data"] if args.list_data else [])
    for kind in listed:
        paths = unrecorded.get(kind, ())
        if paths:
            print(f"--- {kind} files in no SBOM ({len(paths)}) ---")
            for path in paths:
                print("   ", path)
            print()
    return unrecorded.get("binary", [])


def report_reverse(prefix, claimed):
    """Print the SBOM -> installed direction. Returns the missing entries."""
    stats, missing, suspect = check_recorded(prefix, claimed)

    print("=== reverse: SBOM entries -> installed files (whole prefix) ===")
    print(f"{'directory':14}{'recorded':>10}{'present':>9}{'missing':>9}")
    for top in sorted(stats):
        counts = stats[top]
        print(f"{top:14}{sum(counts.values()):10}"
              f"{counts['present']:9}{counts['missing']:9}")
    print()

    if missing:
        print(f"--- recorded but not installed ({len(missing)}) ---")
        for rel, doc in missing:
            print(f"    {rel}  [{doc}]")
        print()
    if suspect:
        print(f"--- recorded but not a plain file ({len(suspect)}) ---")
        for rel, doc, reason in suspect:
            print(f"    {rel}  [{doc}]: {reason}")
        print()
    return missing + suspect


def main():
    parser = argparse.ArgumentParser(
        description="Audit file-level SBOM coverage of an installed Qt tree, "
                    "in both directions.")
    parser.add_argument("prefix", nargs="?", default=".",
                        help="Qt install prefix containing an sbom/ directory")
    parser.add_argument("--dirs", default=DEFAULT_DIRS,
                        help="comma-separated directories for the forward "
                             f"check (default: {DEFAULT_DIRS}); the reverse "
                             "check always covers the whole prefix")
    parser.add_argument("--verify-sha1", action="store_true",
                        help="also compare recorded SHA1 checksums with disk")
    parser.add_argument("--list-data", action="store_true",
                        help="also list unrecorded data files (headers, "
                             ".cmake, .prl, ...), which are usually expected")
    parser.add_argument("--forward-only", action="store_true",
                        help="only check installed files against the SBOMs")
    parser.add_argument("--reverse-only", action="store_true",
                        help="only check SBOM entries against the install "
                             "tree (skips the full directory walk)")
    args = parser.parse_args()

    prefix = os.path.abspath(args.prefix)
    dirs = args.dirs.split(",")
    sbomdir = os.path.join(prefix, "sbom")
    if not os.path.isdir(sbomdir):
        sys.exit(f"error: no sbom/ directory under {prefix}")

    claimed, cdx = load_sboms(sbomdir)
    incomplete = check_document_set(sbomdir)

    print(f"prefix        {prefix}")
    print(f"SPDX          {len({doc for doc, _ in claimed.values()})} documents, "
          f"{len(claimed)} file entries")
    print(f"CycloneDX     {len(cdx)} documents, {sum(cdx.values())} file-level "
          f"occurrences" + (" (no file data — see module docstring)"
                            if not sum(cdx.values()) else ""))
    print()

    if incomplete:
        print(f"=== incomplete SBOM document sets ({len(incomplete)}) ===")
        for module, flavors in incomplete.items():
            scope = "" if any(f in INSTALL_FLAVORS for f in flavors) \
                else "  (source-scope only, not a coverage gap)"
            print(f"    {module}: no {', '.join(flavors)}{scope}")
        print()

    unrecorded_binaries, unresolved = [], []
    if not args.reverse_only:
        unrecorded_binaries = report_forward(prefix, dirs, claimed, args)
    if not args.forward_only:
        unresolved = report_reverse(prefix, claimed)

    if args.verify_sha1:
        matched, mismatched = verify_checksums(prefix, claimed)
        print(f"=== SHA1: {matched} match, {len(mismatched)} mismatch ===")
        print("    Mismatches on code-signed Mach-O binaries are expected in "
              "an installed tree; static .a and data files should match.")
        for rel, doc, recorded, actual in mismatched[:20]:
            print(f"    {rel}  [{doc}] "
                  f"sbom={recorded[:12]} disk={actual[:12]}")
        if len(mismatched) > 20:
            print(f"    ... and {len(mismatched) - 20} more")

    return 1 if unrecorded_binaries or unresolved else 0


if __name__ == "__main__":
    sys.exit(main())
