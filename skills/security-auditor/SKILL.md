---
name: security-auditor
description: "Use when auditing or reviewing security flaws in auth, secrets, external input, file uploads, or dependencies. Covers injection, XSS/CSRF/SSRF, path traversal, broken access control, secret leaks, or vulnerable components. Use when PRs touch auth, APIs, admin panels, payments, or dep manifests. Don't use for: code review (kbg:review-pr), incidents (kbg:hotfix/kbg:incident), or non-code security (infra, policy)."
---

# Security Auditor

Security review is not a checkbox — it's threat modeling. Every line of code is a potential attack surface. Assume breach.

**When to use:** Auth flows, API endpoints, dependency updates, security-boundary changes.

**When NOT to use:** General code review, live incident response, infrastructure/policy topics.

**`security-reviewer` agent vs this skill (canonical):** the `security-reviewer` agent is a *flagging* pass — it rides inside `kbg:review-pr`'s panel and serves as orchestrate's pre-write gate on any auth/secrets change. This skill is the *dedicated, comprehensive* audit (threat model → remediation plan → re-audit). Reach for the skill on high-stakes surfaces (auth flows, payment, admin panels, file uploads, dependency manifests) or an explicit "audit" request; for a routine auth/secrets-touching diff, the `security-reviewer` pass inside `kbg:review-pr` is enough — don't run both.

---

## Procedure

1. **Scope & Threat Model** — Parse scope. Identify assets, threat actors, trust boundaries.

2. **Audit** — Deep review of relevant files, dependency manifest, config, prior security decisions. Map attack surface if scope >5 files. Specific checks:
   - **Collection access:** Scan for unguarded dict/collection lookups (`users_db[user_id]`, `data['field']`) without prior membership checks (`in`, `.get()`). These are silent crash vectors and potential DoS.
   - **File verification:** If a file is provided in scope, read it at the exact path. Do NOT claim a file is "missing" without first attempting to read it. If `Read` returns an error, retry with `Bash ls` to verify before concluding absence. Severity for "missing config" must not exceed the severity of the actual vulnerability it would have revealed.
   - **Dependency manifest severity:** When auditing dependency manifests (requirements.txt, package.json, etc.), check whether vulnerable versions are pinned or floating. If a manifest specifies a vulnerable floor version (e.g., `^4.17.15`) with no lockfile, the vulnerable version is installable — treat as Critical if the CVE is exploitable. If a lockfile pins a patched version, downgrade severity accordingly but still flag the manifest floor. For runtime dependencies in payment/auth systems, never assume the registry resolves the safe version.

3. **Consolidate Findings** — Deduplicate. Classify by OWASP:
   - A01: Broken Access Control
   - A02: Cryptographic Failures
   - A03: Injection
   - A04: Insecure Design
   - A05: Security Misconfiguration
   - A06: Vulnerable Components
   - A07: Authentication Failures
   - A08: Integrity Failures
   - A09: Logging Failures
   - A10: SSRF

   Severity:
   - **Critical** — must fix before merge (exploitable, data loss, auth bypass)
   - **Important** — should fix before merge (weakness, info disclosure, DoS vector)
   - **Minor** — nice to have (defense-in-depth gaps)

4. **Remediation Plan** — Per Critical/Important: what to change, why vulnerable, how to verify. Prioritize by exploitability × blast radius.

5. **Verify Fixes** — Re-audit modified code. Run static analysis if available. Verify no secrets leaked. Confirm regression tests pass.

Done.

## Constraints

- Trust nothing. Fail secure. Least privilege. Defense in depth.
- Critical findings = zero before merge.

## METHODOLOGY

- **Rule 1:** Threat model before audit.
- **Rule 7:** Security vs code quality — surface conflict, security wins unless user accepts risk.
- **Rule 12:** Critical = block merge.

## Related

- `kbg:review-pr` — general code review
- `/fix-bug` — after security bug fix, audit before merge
- `kbg:hotfix` — production security patch
- `kbg:incident` — if security incident is live, incident response first
