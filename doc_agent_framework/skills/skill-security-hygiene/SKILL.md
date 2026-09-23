---
name: skill-security-hygiene
description: "Security and compliance hygiene for Qt Doc Agent Framework artifacts: flags secrets, PII, deprecated crypto, plain-text auth, boundary breaches."
metadata:
  version: "1.0.0"
---

# Framework Security Hygiene

Security and compliance hygiene for artifacts inside
`qtqa/doc_agent_framework/`. Runs alongside
[`skill-framework-fitness`](../skill-framework-fitness/SKILL.md) as the
framework's initial-check pair; the orchestrator's pre-flight loads
both.

The checks are industry-standard hygiene (secrets, PII, deprecated
crypto, plain-HTTP auth, logging) plus two framework-specific rules:
and public-vs-internal boundary.

## What this catches

Seven checks; every review runs all seven and enumerates a verdict for
each (see [Report structure](#report-structure) for the output shape).

| # | Check | Flags |
|---|-------|-------|
| 1 | Hardcoded secrets | API tokens, private keys, plain-text passwords, JWTs, embedded credentials |
| 2 | PII | Non-`@qt.io` emails, real names in comments, customer IDs, personal filesystem paths |
| 3 | Cryptography defects | Deprecated algorithms, hardcoded IVs/salts, custom crypto, plain-text password storage |
| 4 | Logging hygiene | Credentials, PII, keys inside log/print/trace statements |
| 5 | Access control and auth | Plain-HTTP auth endpoints, missing 2FA, shared accounts on sensitive systems |
| 6 | Framework boundary | URLs to internal Qt sites, user-specific filesystem paths, internally classified content in a public tree |
| 7 | Vulnerability disclosure hygiene | CVE details in commit messages before coordinated disclosure |

## When to apply

- **Pre-submission self-review.** You are about to push a patch (or run
  `git review`) touching `doc_agent_framework/`. Run the
  [self-review checklist](#pre-submission-self-review) first, then the
  pre-merge checks.
- **Reviewing someone else's patch.** Apply the pre-merge checks
  directly.
- **Reviewing agent output.** Any content the framework is about to
  write into the tree or a commit message.

## Pre-submission self-review

You are the patch author. Grep your staged diff for your own identity —
the standard pre-merge scan assumes someone *else* wrote the patch, so
it doesn't think to look for *your* identity leaking in.

Substitute your username, first name, and last name:

```bash
# Replace USERNAME / FIRST / LAST with your own values
/usr/bin/grep -rniE '\b(USERNAME|FIRST|LAST)\b|/Users/USERNAME/|/home/USERNAME/|[A-Z]:\\Users\\USERNAME\\' .
```

Flag and remove:

- Your username in code, comments, paths, sample data.
- Your real name in comments (git trailers like `Co-Authored-By` or
  `Signed-off-by` are intentional and fine — body content is not).
- Your home directory path on any OS (`/Users/<you>/`, `/home/<you>/`,
  `C:\Users\<you>\`). Public readers don't have your paths on their
  machines.
- A personal `@qt.io` address in a doc that doesn't need it — use a
  team alias or an `<engineer@qt.io>` placeholder.

Beyond identity:

- Local tooling output (debugger sessions, IDE config snippets) in
  code or docs.
- IDE artifacts (`.idea/`, `.vscode/`, `*.bak`, `*.orig`, `*.swp`).
- Personal credentials in shared test fixtures.
- Hostnames of your laptop or dev machine.

## Pre-merge checks

### Hardcoded secrets

Flag in any text file (code, config, docs, commit message, test
fixtures, sample data):

- API tokens — `xox[bp]-…` (Slack), `gh[pousr]_…` (GitHub), `AKIA…`
  (AWS), `AIza…` (Google), `sk_live_…` (Stripe), Atlassian tokens.
- Private keys — `-----BEGIN .* PRIVATE KEY-----`, `.pem`, `.p12`,
  `.pfx`.
- Plain-text passwords — `password=`, `pwd:`, `passwd:`, `secret:`.
- Connection strings with embedded credentials — `://user:pass@host`.
- SSH keys — `ssh-rsa AAAA…`, `ssh-ed25519 AAAA…`.
- JWT tokens — `eyJ` + base64 + dot.
- Test credentials that mirror production patterns.

If found, **block merge**. The author must rotate the secret, remove it
from git history (`git filter-repo` / `bfg`), and move it to a secrets
manager.

### PII in code, docs, commit messages

Flag:

- Email addresses other than `@qt.io` / `@qt-project.org` /
  `example.{com,org,net}` placeholders.
- Names of identifiable individuals in comments (not `Co-Authored-By`
  trailers, attributed bug reports, or git history references).
- Customer names, account IDs, contract IDs in code, sample data,
  screenshots.
- Phone numbers, addresses, government IDs, financial info.

Log statements must not include credentials, tokens, session IDs
without truncation, credit-card / payment data, full PII payloads,
encryption keys, or customer identifiers paired with sensitive context.

### Cryptography defects

Flag as industry-standard hygiene:

- Deprecated algorithms — MD5, SHA-1 for signatures, DES, RC4, SSLv3,
  TLS 1.0, TLS 1.1, RSA < 2048, ECDSA < 256.
- Hardcoded IVs / nonces, fixed salts.
- Custom crypto ("roll your own") — prefer vetted libraries (Qt
  Cryptographic Architecture, OpenSSL, libsodium).
- Plain-text password storage.
- Symmetric key in source — treat as a hardcoded secret.

Certificate hygiene:

- Certificate validity > 1 year without a documented business reason.
- Wildcard certificates without a documented business reason.

### Logging hygiene

Flag any log / print / emit / trace / telemetry statement that may
include:

- Authentication credentials (passwords, tokens, session IDs without
  truncation).
- Credit card / payment / bank data.
- Full PII payloads.
- Encryption keys, signing keys, recovery codes.

Acceptable: anonymized, truncated, or hashed values. If a fix uses log
masking, verify masking happens **before** the data reaches the log
sink, not just at display time.

### Access control and authentication

- Login information over TLS, not plain HTTP — flag any `http://…/login`
  or auth endpoint.
- New auth code: 2FA / MFA for systems holding sensitive data.
- No shared user accounts for systems holding sensitive data.

### Framework boundary — public qtqa vs internal Qt material

The `doc_agent_framework/` tree lives in public qtqa. Its readers
include external Qt contributors. Flag:

- Any URL pointing at an internal Qt site — internal Confluence,
  internal Jira, internal wikis, internal dashboards, internal doc
  mirrors, internal build/CI infrastructure. Public readers cannot
  resolve them. Inline the referenced content into a local file in the
  framework tree instead.
- Any user-specific filesystem path — `~/code/…`, `/Users/<name>/`,
  `/home/<name>/`, `C:\Users\<name>\`. Public readers don't have your
  mirror on their machine.
- Any content copied verbatim from an internally classified source
  (internal Confluence spaces, internal-tenant Jira, internal build-
  pipeline docs).
- Any internal-only email addresses, hostnames, or IP ranges.

The rule in one line: content classification must not exceed the
destination's public cap. When it does, redact the content or move it
to a private location.

### Vulnerability disclosure hygiene

A commit that fixes a security issue should:

- Not describe the vulnerability in the public commit message *before*
  coordinated disclosure.
- Not include exploit details, repro steps, or CVSS scores in the diff
  until disclosure is coordinated.
- Route through the appropriate security contact before push.

Public commit messages naming a CVE that has not been coordinated yet
are a disclosure defect — flag for security review before merge.

## Quick grep patterns

Starting points; false positives are expected.

```bash
# Secrets — API keys, private keys, generic assignments
/usr/bin/grep -rnE '(-----BEGIN [A-Z ]+PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|xox[bp]-[A-Za-z0-9-]+|AIza[0-9A-Za-z_-]{35}|sk_live_[A-Za-z0-9]{20,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}|ssh-(rsa|ed25519|dss) AAAA[0-9A-Za-z+/=]+)' .

# Plain-text password assignments
/usr/bin/grep -rniE '(password|passwd|pwd|secret|api[_-]?key|token)\s*[:=]\s*["'"'"'][^"'"'"']{4,}["'"'"']' .

# Plain HTTP for auth or sensitive endpoints
/usr/bin/grep -rnE 'http://[^"[:space:]]+/(login|auth|token|session|api)' .

# Deprecated algorithms
/usr/bin/grep -rnwE '(MD5|SHA-?1|DES|RC4|SSLv[23]|TLSv?1[._]?[01])' .

# Logging suspicious fields (matches log./log_/logger./logging., not dialog./catalog.)
/usr/bin/grep -rniE '\blog[a-z]*[._].*\b(password|passwd|secret|token|api[_-]?key|credit[_-]?card|ssn|cvv|pin)\b' .

# Non-Qt email domains in framework files (PCRE lookahead — needs /usr/bin/grep -P, not -E)
/usr/bin/grep -rnP '[A-Za-z0-9._%+-]+@(?!(qt\.io|qt-project\.org|example\.(com|org|net)))[A-Za-z0-9.-]+\.[A-Za-z]{2,}' .

# Connection strings with embedded creds
/usr/bin/grep -rnE '[A-Za-z]+://[^"[:space:]/:]+:[^"[:space:]/@]+@' .

# Self-PII — home directory paths on any OS
/usr/bin/grep -rnE '(/Users/[^/]+/|/home/[^/]+/|[A-Z]:\\Users\\[^\\]+\\)' .

# Framework boundary — Qt-domain hostnames in a public file. Public
# targets (doc.qt.io, doc-snapshots.qt.io, wiki.qt.io, code.qt.io,
# contribute.qt-project.org) are fine; anything else on a *.qt.io or
# *.qt-project.org subdomain should be reviewed by a person.
/usr/bin/grep -rnE '[a-z0-9-]+\.(qt-project\.org|qt\.io)' .
```

Use `git diff --cached` or `git diff <base>..HEAD` piped through these
patterns when reviewing staged or branch-scoped changes.

Note on `grep`: the shell's `grep` on some setups is shimmed to ugrep,
which accepts `\s` inside bracket expressions (POSIX ERE does not).
When testing a grep pattern that ships in this skill, verify it against
`/usr/bin/grep` explicitly.

## Report structure

Every review that runs this skill must emit two blocks: a check-coverage
table (enumerating every check) and a findings list (enumerating every
finding). Do not skip either — a review that reports only findings hides
which checks ran, and a review that reports only coverage hides the
findings themselves.

### 1. Check coverage — enumerate every check

Emit one row per check. Every row has a verdict: **PASS** (check ran,
no findings), **FINDINGS: n** (check ran, produced *n* findings), or
**N/A** (check does not apply to this artifact type). Never omit a row.

```
## Security Hygiene — Check Coverage

| # | Check                    | Verdict         |
|---|--------------------------|-----------------|
| 1 | Hardcoded secrets        | PASS / FINDINGS: n / N/A |
| 2 | PII                      | PASS / FINDINGS: n / N/A |
| 3 | Cryptography defects     | PASS / FINDINGS: n / N/A |
| 4 | Logging hygiene          | PASS / FINDINGS: n / N/A |
| 5 | Access control and auth  | PASS / FINDINGS: n / N/A |
| 6 | Framework boundary       | PASS / FINDINGS: n / N/A |
| 7 | Vulnerability disclosure | PASS / FINDINGS: n / N/A |
```

An `N/A` row must state the reason on the same line (for example: `N/A
— target is a Markdown SKILL.md with no runtime code`). Don't mark N/A
to duck a check; if the check could plausibly apply, run it.

### 2. Findings — enumerate every finding

Emit one block per finding in the shape below. **Every finding gets
its own block, even when two share a category.** Do not collapse ("3
occurrences of hardcoded API keys") into a single block — the reviewer
needs each `{file}:{line}` and each required action separately.

Order findings: Critical → High → Medium → Low → None. Within a
severity, order by category number from the coverage table.

```
## Security Hygiene Finding <N of M>

**Severity:** {None | Low | Medium | High | Critical}
**Category:** {Secrets | PII | Crypto | Logging | Auth | Boundary | Disclosure}
**Location:** {file}:{line}
**Issue:** {short factual description — no exploit details}
**Required action:** {what the author must do}
```

For Critical findings, prefix the heading with `BLOCKING` and notify
a security contact before merge.

### Empty-report shape

If every check passes, still emit the coverage table (all rows `PASS`
or `N/A` with reasons) and a single line: `No findings.` A silent
review is not a passing review.

## When you find violations

1. **Don't fix silently.** Surface every finding as its own block in
   the report; never collapse duplicates or "one representative"
   findings.
2. **Block the merge** if any finding is High or Critical severity.
3. **Report incidents** to the appropriate security contact.
4. **Never abandon a check mid-scan.** If the coverage table has a row
   marked FINDINGS: n, the findings list must contain exactly n
   findings under that category. A count-without-detail is a bug in
   the review, not a feature.

## Out of scope for this skill

- Workstation / laptop policy, physical security, HR/financial record
  retention — handled elsewhere.
- Customer-facing penetration test coordination — handled by R&D.
- Firewall, network, hardware design — see the relevant IT Security
  team directly.

## Revision

| Date | Change |
| --- | --- |
| 2026-09-23 | Skill created for the Qt Doc Agent Framework initial-check pair. |
