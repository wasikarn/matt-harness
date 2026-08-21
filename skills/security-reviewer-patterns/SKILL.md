---
name: security-reviewer-patterns
description: Catalog of security-reviewer's BAD/GOOD examples (SQLi, IDOR, JWT, mass assignment, SSRF, ReDoS). Auto-loads when security-reviewer runs. Don't use for the deep-audit workflow (security-auditor).
bucket: review
metadata:
  origin: kbg
model: inherit
effort: xhigh
---

# Security-Reviewer Concrete Patterns Reference

Extracted from `agents/security-reviewer.md` (2026-08-18, harness-audit check 60 threshold) to
keep the agent body under 20,000 chars. Loaded via that agent's `skills:` frontmatter field
(preloaded at spawn, independent of the Skill tool — `security-reviewer` carries no `Skill` tool
grant) — this file is the code-example reference, not a separately-triggered pass. Read it
alongside `agents/security-reviewer.md`: the CWE pattern table in that file's §3 is what these
examples illustrate.

**Distinct from `kbg:security-auditor`:** that skill is a separate, dedicated deep-audit workflow
(threat model → remediation plan → re-audit) with its own callers (`kbg:review-pr`, `/fix-bug`,
`kbg:incident`) — this file is background material for `security-reviewer`'s own flagging pass
only, not a substitute for or extension of that audit procedure.

## 3b. Concrete Patterns (BAD/GOOD)

**SQL injection (CWE-89):**
```javascript
// BAD: user input concatenated into the query
const rows = await db.query(`SELECT * FROM users WHERE email = '${email}'`);

// GOOD: parameterized (MySQL/MariaDB ? — Postgres $1)
const rows = await db.query('SELECT * FROM users WHERE email = ?', [email]);
```

**IDOR — auth present, ownership missing (CWE-639):** the single most common gap between
"looks secure" and "is secure" — auth middleware passing does not mean access control passed.
```javascript
// BAD: any authenticated user can read any invoice by guessing the ID
app.get('/invoices/:id', requireAuth, async (req, res) => {
  const invoice = await db.getInvoice(req.params.id);
  res.json(invoice);
});

// GOOD: ownership checked against the authenticated principal
app.get('/invoices/:id', requireAuth, async (req, res) => {
  const invoice = await db.getInvoice(req.params.id);
  if (!invoice || String(invoice.userId) !== String(req.user.id)) return res.sendStatus(404);
  res.json(invoice);
});
```

**Watch for this specific bug even when an ownership check exists**: a raw `!==` comparison
between an ID from the DB (often a string for `BIGINT`/`NUMERIC` columns depending on the
driver) and an ID from the JWT/session (often a number) silently denies every legitimate user
— strict-but-wrong reads as "secure" in review. Worse, a maintainer chasing that bug report who
"fixes" it with loose `!=` reopens a coercion bypass (`undefined != null` is `false` in JS).
Normalize both sides to the same type before comparing, or push the check into the query itself
(`WHERE id = ? AND user_id = ?`) so there's no comparison to get wrong.

**JWT `alg: none` / algorithm confusion (CWE-347):** if the verifier accepts whatever `alg`
the token header claims, an attacker crafts an unsigned or HS256-signed-with-the-public-key
token and the app trusts it.
```javascript
// BAD: algorithm taken from the attacker-controlled token header
jwt.verify(token, secretOrPublicKey);

// GOOD: pin the expected algorithm explicitly
jwt.verify(token, secretOrPublicKey, { algorithms: ['RS256'] });
```

**The pin matters even though modern `jsonwebtoken` narrows defaults by key shape.** Newer
`jsonwebtoken` versions infer an allowed algorithm family from the shape of `secretOrPublicKey`
(PEM header detection) — for a well-formed PEM key, this correctly locks the allowlist to the
RSA/EC family and rejects a forged HS256 token even with no explicit pin; don't claim an unpinned
call is already broken for a verified well-formed key, that overstates the bug. The gap opens
specifically when the key value is malformed or a placeholder (a truncated PEM, a leftover
default like a literal `your_public_key_here` string): the shape inference falls through to
treating the value as an HMAC secret, and a forged HS256 token signed with that same string
verifies successfully. Verified live on the current jsonwebtoken major version. Score this
CRITICAL whenever the key's well-formedness can't be confirmed from the code (a fallback literal,
an unvalidated env var, no startup check) — that's a realistic misconfiguration, not a rare edge
case. Still recommend the explicit `algorithms` pin regardless of whether the key looks correctly
configured today — it removes the dependency on key-shape inference entirely, so it's the fix
that survives the key being swapped or misconfigured later — but frame that as "pin it so this
class of bug can't reopen," not "the unpinned call is currently exploitable no matter what."

**Mass assignment (CWE-915):** spreading a request body straight into a DB write lets the
client set fields it was never meant to control.
```javascript
// BAD: client can pass { "role": "admin" } in the body and it sticks
await db.users.update(req.user.id, { ...req.body });

// GOOD: allowlist the fields the client is permitted to set
const { name, email } = req.body;
await db.users.update(req.user.id, { name, email });
```

**SSRF (CWE-918):** a server-side fetch of a user-supplied URL (webhooks, image proxies,
URL-preview features) can reach internal services (`169.254.169.254` cloud metadata, internal
admin panels on `10.x`/`192.168.x`, `localhost`) that are unreachable from outside.
```javascript
// BAD: fetches whatever URL the client passed
const res = await fetch(req.body.webhookUrl);

// GOOD: resolve, then reject private/link-local/loopback ranges before fetching
const url = new URL(req.body.webhookUrl);
if (['localhost', '127.0.0.1', '169.254.169.254'].includes(url.hostname) || isPrivateIp(url.hostname)) {
  return res.status(400).send('Blocked target');
}
const result = await fetch(url, { redirect: 'error' }); // also block redirect-based bypass
```

**ReDoS — catastrophic backtracking on user input (CWE-1333):** a regex with nested or
overlapping quantifiers can take exponential time on a crafted input, turning one request into a
CPU-pinning denial of service — the mechanism behind Cloudflare's July 2019 global outage (a
single backtracking regex in the WAF ruleset).
```javascript
// BAD: nested quantifier — backtracking blows up on an input like "a".repeat(40) + "!"
const isValid = /^([a-zA-Z0-9]+)+@/.test(userEmail);

// GOOD: no nested quantifier — same intent, linear time
const isValid = /^[a-zA-Z0-9]+@/.test(userEmail);
```
Rewriting the regex is the real fix; a timeout or the RE2 engine (which guarantees linear time by
construction) is the fallback for a pattern too complex to verify by inspection. Node's built-in
regex engine has no default execution timeout — a catastrophic-backtracking pattern blocks the
entire event loop, not just the one request.

Done when every CWE pattern in `agents/security-reviewer.md`'s §3 Code Pattern Review table that
has a matching example above has been checked against the diff for the BAD shape, and any finding
cites the GOOD fix shown here.
