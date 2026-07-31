#!/usr/bin/env python3
# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

"""
check_purl.py — Validate github/gitlab Package URLs (PURLs) and check
whether the repo (and optional version/ref) actually exists.

Why not aboutcode-org/purldb-toolkit for this?
    purldb-toolkit's `purlcli validate` command is a good general-purpose
    purl validator, but its existence check ("check_existence") only
    covers cargo, composer, deb, gem, golang, hex, maven, npm, nuget and
    pypi (per its own source: purldb_toolkit/purlcli.py, validate_purl()).
    `github` and `gitlab` are not in that list, so it falls back to
    "check_existence_not_supported" for exactly the two types we care
    about here. Syntax validation (via packageurl-python, which purldb-
    toolkit also uses under the hood) works fine for these types — it's
    only the existence check that's missing — so this script covers
    that gap by querying the GitHub/GitLab APIs directly.

Requires:
    pip install packageurl-python requests

Usage:
    python check_purl.py pkg:github/psf/requests@v2.31.0
    python check_purl.py pkg:gitlab/gitlab-org/gitlab@master
    python check_purl.py --file purls.txt          # one purl per line
    python check_purl.py --github-token YOUR_GH_TOKEN pkg:github/psf/requests

Exit code is 0 only if every purl resolved to 'ok' or was skipped (non
github/gitlab type). Any 'not found', 'error' (couldn't verify — e.g.
rate limit or network issue), or 'invalid' (malformed syntax) result
causes a non-zero exit and is broken out in the summary printed at the end.
"""

import argparse
import json
import sys

import requests
from packageurl import PackageURL

GITHUB_API = "https://api.github.com"
GITLAB_API = "https://gitlab.com/api/v4"


def extract_purls_from_cyclonedx(data):
    """Recursively find every 'purl' value in a parsed CycloneDX JSON document.

    Deliberately schema-version-agnostic: rather than hardcoding paths like
    metadata.component / components[] / services[], this just walks the
    entire document tree and collects any string found under a "purl" key.
    That covers every CycloneDX schema version (1.0 through the current
    1.7, and any future version) since 'purl' has been a stable field name
    throughout, appearing on components (including nested sub-components),
    services, and metadata.component alike.
    """
    found = []

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "purl" and isinstance(value, str) and value.strip():
                    found.append(value.strip())
                else:
                    walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(data)

    # De-duplicate while preserving first-seen order.
    seen = set()
    unique = []
    for p in found:
        if p not in seen:
            seen.add(p)
            unique.append(p)
    return unique


def load_purls_from_sbom(path):
    """Load a CycloneDX SBOM (JSON) and return the list of purls it contains."""
    with open(path, encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(
                f"could not parse {path!r} as JSON (only CycloneDX JSON is "
                f"supported, not XML): {e}"
            )

    bom_format = data.get("bomFormat")
    if bom_format and bom_format != "CycloneDX":
        print(f"warning: {path} declares bomFormat={bom_format!r}, expected 'CycloneDX'", file=sys.stderr)

    spec_version = data.get("specVersion", "unknown")
    purls = extract_purls_from_cyclonedx(data)
    print(f"loaded {path}: CycloneDX specVersion={spec_version}, found {len(purls)} purl(s)", file=sys.stderr)
    return purls


SKIP = "skip"  # sentinel: well-formed purl, but not github/gitlab (out of scope)


def parse_purl(purl_str):
    """Return (PackageURL, error_message).

    error_message is None if valid and in scope. error_message is the
    string SKIP if the purl is well-formed but not a github/gitlab type
    (this script only checks existence for those two).

    packageurl-python (the same parser purldb-toolkit uses internally)
    already lowercases the namespace/name for github and gitlab types on
    parse, since both platforms are case-insensitive — so no extra
    normalization is needed here.
    """
    try:
        purl = PackageURL.from_string(purl_str)
    except ValueError as e:
        return None, f"malformed purl: {e}"

    if purl.type not in ("github", "gitlab"):
        return None, SKIP
    if not purl.namespace:
        return None, "missing namespace (expected the user/org or group, e.g. 'psf')"
    if not purl.name:
        return None, "missing name (expected the repo name)"
    return purl, None


def check_github(purl, token=None):
    """Return (status, detail). status is one of 'ok', 'not_found', 'error'."""
    headers = {"Accept": "application/vnd.github+json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    repo_url = f"{GITHUB_API}/repos/{purl.namespace}/{purl.name}"
    resp = requests.get(repo_url, headers=headers, timeout=10)
    if resp.status_code == 404:
        return "not_found", "repo not found (or private/no access)"
    if resp.status_code != 200:
        return "error", f"could not verify — unexpected status {resp.status_code}: {resp.text[:200]}"

    if purl.version:
        # Works for branches, tags, and commit SHAs.
        ref_url = f"{repo_url}/commits/{purl.version}"
        ref_resp = requests.get(ref_url, headers=headers, timeout=10)
        if ref_resp.status_code == 404:
            return "not_found", f"repo exists, but ref {purl.version!r} not found"
        if ref_resp.status_code != 200:
            return "error", f"could not verify ref — unexpected status {ref_resp.status_code}"

    if purl.subpath:
        # Contents API: 404 if the path doesn't exist at this ref (or at
        # the default branch, if no version/ref was given).
        contents_url = f"{repo_url}/contents/{purl.subpath}"
        params = {"ref": purl.version} if purl.version else None
        contents_resp = requests.get(contents_url, headers=headers, params=params, timeout=10)
        if contents_resp.status_code == 404:
            ref_note = f" at ref {purl.version!r}" if purl.version else ""
            return "not_found", f"repo exists, but subpath {purl.subpath!r} not found{ref_note}"
        if contents_resp.status_code != 200:
            return "error", f"could not verify subpath — unexpected status {contents_resp.status_code}"

    return "ok", "ok"


def check_gitlab(purl, token=None):
    """Return (status, detail). status is one of 'ok', 'not_found', 'error'."""
    headers = {}
    if token:
        headers["PRIVATE-TOKEN"] = token

    project_path = requests.utils.quote(f"{purl.namespace}/{purl.name}", safe="")
    project_url = f"{GITLAB_API}/projects/{project_path}"
    resp = requests.get(project_url, headers=headers, timeout=10)
    if resp.status_code == 404:
        return "not_found", "project not found (or private/no access)"
    if resp.status_code != 200:
        return "error", f"could not verify — unexpected status {resp.status_code}: {resp.text[:200]}"

    if purl.version:
        commit_url = f"{project_url}/repository/commits/{purl.version}"
        commit_resp = requests.get(commit_url, headers=headers, timeout=10)
        if commit_resp.status_code == 404:
            return "not_found", f"project exists, but ref {purl.version!r} not found"
        if commit_resp.status_code != 200:
            return "error", f"could not verify ref — unexpected status {commit_resp.status_code}"

    if purl.subpath:
        # Repository tree API: list the parent dir and confirm the leaf
        # exists, since GitLab's "get file" endpoint only works for blobs,
        # not directories, and subpaths may point at either.
        ref = purl.version or "HEAD"
        tree_url = f"{project_url}/repository/tree"
        params = {"path": purl.subpath, "ref": ref}
        tree_resp = requests.get(tree_url, headers=headers, params=params, timeout=10)
        if tree_resp.status_code == 200 and tree_resp.json():
            pass  # subpath is a directory that exists
        else:
            # Not a directory (or empty/404) — try it as a file blob instead.
            file_path = requests.utils.quote(purl.subpath, safe="")
            file_url = f"{project_url}/repository/files/{file_path}"
            file_resp = requests.get(file_url, headers=headers, params={"ref": ref}, timeout=10)
            if file_resp.status_code == 404:
                return "not_found", f"project exists, but subpath {purl.subpath!r} not found at ref {ref!r}"
            if file_resp.status_code != 200:
                return "error", f"could not verify subpath — unexpected status {file_resp.status_code}"

    return "ok", "ok"


def check_one(purl_str, gh_token=None, gl_token=None):
    """Return (purl_str, status, detail).

    status is one of: 'ok', 'not_found', 'error', 'invalid', 'skip'.
    """
    purl, err = parse_purl(purl_str)
    if err == SKIP:
        return purl_str, "skip", "not github/gitlab type, skipped"
    if err:
        return purl_str, "invalid", err

    checker = check_github if purl.type == "github" else check_gitlab
    token = gh_token if purl.type == "github" else gl_token
    status, detail = checker(purl, token)
    return purl_str, status, detail


STATUS_LABELS = {
    "ok": "OK",
    "not_found": "NOT FOUND",
    "error": "ERROR",
    "invalid": "INVALID",
    "skip": "SKIP",
}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("purls", nargs="*", help="PURL strings to check")
    ap.add_argument("--file", help="text file with one PURL per line")
    ap.add_argument("--sbom", help="CycloneDX JSON SBOM file; every 'purl' entry found in it will be checked")
    ap.add_argument("--github-token", help="GitHub token (raises rate limit, needed for private repos)")
    ap.add_argument("--gitlab-token", help="GitLab token (needed for private projects)")
    args = ap.parse_args()

    purls = list(args.purls)
    if args.file:
        with open(args.file) as f:
            purls += [line.strip() for line in f if line.strip() and not line.startswith("#")]
    if args.sbom:
        try:
            purls += load_purls_from_sbom(args.sbom)
        except (ValueError, OSError) as e:
            ap.error(str(e))

    if not purls:
        ap.error("no PURLs given (pass as arguments, --file, or --sbom)")

    counts = {"ok": 0, "not_found": 0, "error": 0, "invalid": 0, "skip": 0}
    for purl_str in purls:
        _, status, detail = check_one(purl_str, args.github_token, args.gitlab_token)
        counts[status] += 1
        label = STATUS_LABELS[status].ljust(10)
        print(f"[{label}] {purl_str}  -> {detail}" if status != "ok" else f"[{label}] {purl_str}")

    total = len(purls)
    print("\n--- summary ---")
    print(f"total:     {total}")
    print(f"ok:        {counts['ok']}")
    print(f"not found: {counts['not_found']}")
    print(f"error:     {counts['error']}")
    print(f"invalid:   {counts['invalid']}")
    print(f"skipped:   {counts['skip']}  (not github/gitlab type — out of scope for this script)")

    # not_found is a confirmed failure; error means we couldn't determine
    # (rate limit, network issue, etc.) and invalid means malformed syntax.
    # All three are treated as failures for the exit code — only ok/skip
    # count as success.
    failed = counts["not_found"] + counts["error"] + counts["invalid"]
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
