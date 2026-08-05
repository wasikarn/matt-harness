---
name: security-auditor
description: "Scan security vulnerabilities, threat-model + remediation (auth, secrets, injection, XSS, traversal). Use when PRs touch auth/APIs/payments/deps. Don't use for quick branch checks or code review."
---

# Security Auditor

Security review is not a checkbox — it's threat modeling. Every line of code is a potential attack surface. Assume breach.

**When to use:** Auth flows, API endpoints, dependency updates, security-boundary changes.

**When NOT to use:** General code review, live incident response, infrastructure/policy topics.

**`security-reviewer` agent vs this skill (canonical):** the `security-reviewer` agent is a *flagging* pass — it rides inside `kbg:review-pr`'s panel and serves as orchestrate's pre-write gate on any auth/secrets change. This skill is the *dedicated, comprehensive* audit (threat model → remediation plan → re-audit). Reach for the skill on high-stakes surfaces (auth flows, payment, admin panels, file uploads, dependency manifests) or an explicit "audit" request; for a routine auth/secrets-touching diff, the `security-reviewer` pass inside `kbg:review-pr` is enough — don't run both.

---

## Procedure

1. **Scope & Threat Model** — Parse scope. Identify assets, threat actors, trust boundaries. Name an adversary profile per trust boundary crossed (external unauthenticated / authenticated user / insider with elevated access) — this surfaces trust-boundary-crossing issues (IDOR, privilege escalation) that a per-file pattern scan alone misses.

2. **Audit** — Deep review of relevant files, dependency manifest, config, prior security decisions. Map attack surface if scope >5 files. Specific checks:
   - **Collection access:** Scan for unguarded dict/collection lookups (`users_db[user_id]`, `data['field']`) without prior membership checks (`in`, `.get()`). These are silent crash vectors and potential DoS.
   - **File verification:** If a file is provided in scope, read it at the exact path. Do NOT claim a file is "missing" without first attempting to read it. If `Read` returns an error, retry with `Bash ls` to verify before concluding absence. Severity for "missing config" must not exceed the severity of the actual vulnerability it would have revealed.
   - **Dependency manifest severity:** When auditing dependency manifests (requirements.txt, package.json, etc.), check whether vulnerable versions are pinned or floating. If a manifest specifies a vulnerable floor version (e.g., `^4.17.15`) with no lockfile, the vulnerable version is installable — treat as Critical if the CVE is exploitable. If a lockfile pins a patched version, downgrade severity accordingly but still flag the manifest floor. For runtime dependencies in payment/auth systems, never assume the registry resolves the safe version.
   - **Regex/resource-exhaustion DoS (CWE-1333, CWE-400):** Scan for regexes with nested or
     overlapping quantifiers (`(a+)+`, `(a|a)*`, `(.*)+`) applied to user-controlled input —
     catastrophic backtracking turns one request into an exponential-time CPU-pinning DoS (the
     mechanism behind Cloudflare's July 2019 global outage). Also check request-body size, array
     length, and recursion depth are bounded before processing. Classify under A04 (Insecure
     Design) if the pattern is unsafe by construction, or A05 (Security Misconfiguration) if a
     size/depth limit is simply missing.

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

   **Severity ceiling:** Critical/Important requires a demonstrated attack path — entry point → steps → realized impact, walked from the named adversary profile above. A pattern-matched issue with no demonstrated path (e.g. "missing HttpOnly flag" or "no rate limiting" cited on its own, with no chain to an actual exploit) is capped at Minor regardless of how the pattern looks — this is a defense-in-depth gap until a path is shown, not evidence of exploitability.

4. **Remediation Plan** — Per Critical/Important: what to change, why vulnerable, how to verify. Prioritize by exploitability × blast radius.

5. **Verify Fixes** — Don't re-audit your own remediation. Spawn the `security-reviewer` agent (fresh context) as a Task-tool subagent against the remediated files — the same invocation shape `kbg:review-pr` already uses to route security findings. Run static analysis if available. Confirm regression tests pass.

Done.

## Output Format

Emit a findings report. One block per finding; remediation as a separate section.

- **Severity:** Critical | Important | Minor   (Critical/Important require a demonstrated attack path — see Procedure step 3 ceiling)
- **OWASP:** A01–A10
- **Location:** file:line
- **Finding:** <one line: what, and why it matters>
- **Adversary profile:** <named in step 1>
- **Remediation:** <what to change + how to verify>   (Critical/Important only)

End with a one-line verdict: `BLOCK` (any Critical/Important open) or `PASS`.

## Constraints

- Trust nothing. Fail secure. Least privilege. Defense in depth.
- Critical findings = zero before merge.

## METHODOLOGY

- **Rule 1:** Threat model before audit.
- **Surface conflicts, don't average:** security vs code quality — surface conflict, security wins unless user accepts risk.
- **Fail loud:** Critical = block merge.

## Related

- `kbg:review-pr` — general code review
- `/fix-bug` — after security bug fix, audit before merge
- `kbg:incident` — production security patch / live incident response first
