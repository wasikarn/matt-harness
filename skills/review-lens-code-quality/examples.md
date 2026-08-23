# BAD/GOOD examples appendix (extends SKILL.md)

Illustrative pairs for checklist items already stated in prose bullets in `agents/code-reviewer.md`
— read that file's bullets first; these examples are supporting detail, not new rules.

## Security — SQL injection

```typescript
// BAD: SQL injection via string concatenation
const query = `SELECT * FROM users WHERE id = ${userId}`;

// GOOD: Parameterized query (MySQL/MariaDB ? — Postgres uses $1)
const query = `SELECT * FROM users WHERE id = ?`;
const result = await db.query(query, [userId]);
```

## Code Quality — deep nesting + mutation

```typescript
// BAD: Deep nesting + mutation
function processUsers(users) {
  if (users) {
    for (const user of users) {
      if (user.active) {
        if (user.email) {
          user.verified = true;  // mutation!
          results.push(user);
        }
      }
    }
  }
  return results;
}

// GOOD: Early returns + immutability + flat
function processUsers(users) {
  if (!users) return [];
  return users
    .filter(user => user.active && user.email)
    .map(user => ({ ...user, verified: true }));
}
```

## React/Next.js Patterns — missing dependency array

```tsx
// BAD: Missing dependency, stale closure
useEffect(() => {
  fetchData(userId);
}, []); // userId missing from deps

// GOOD: Complete dependencies
useEffect(() => {
  fetchData(userId);
}, [userId]);
```

## Node.js/Backend Patterns — N+1 query

```typescript
// BAD: N+1 query pattern (MySQL/MariaDB ? placeholder — Postgres uses $1)
const users = await db.query('SELECT * FROM users');
for (const user of users) {
  user.posts = await db.query('SELECT * FROM posts WHERE user_id = ?', [user.id]);
}

// GOOD: Single query with JOIN or batch (MySQL/MariaDB — Postgres: jsonb_agg(p.*) + $1)
const usersWithPosts = await db.query(`
  SELECT u.*, JSON_ARRAYAGG(JSON_OBJECT('id', p.id, 'title', p.title)) AS posts
  FROM users u
  LEFT JOIN posts p ON p.user_id = u.id
  GROUP BY u.id
`);
```

## Review Output Format — templates

(Moved from SKILL.md 2026-08-23, 200-LOC cap refactor. SKILL.md keeps the lead-with-verdict
rule; the full templates and the coverage-mode field contract live here.)

```
[CRITICAL] Hardcoded API key in source
File: src/api/client.ts:42
Issue: API key "sk-abc..." exposed in source code. This will be committed to git history.
Fix: Move to environment variable and add to .gitignore/.env.example
Revisit if: the key turns out to be a test-only placeholder already rotated out of production use

  const apiKey = "sk-abc123";           // BAD
  const apiKey = process.env.API_KEY;   // GOOD
```

**`Reviewer-Confidence: NN%`** — an optional field, added only when the dispatch prompt puts
`code-reviewer` in **coverage mode** (`kbg:review-pr` Phase 4 step 2.6). In coverage mode, report
down to 40% confidence instead of the default 80% floor, and tag every finding with this field so
`kbg:review-pr-tier`'s downstream tiering has a real number to filter on — the whole point of
coverage mode is surfacing findings a downstream stage can triage, not silently dropping them
before they're ever written down. Outside coverage mode (standalone/ad-hoc invocation, no
downstream tier), the default `>80%` pre-report gate applies as before and this field is omitted —
nothing below 80% ever reaches this template in that case. Named `Reviewer-Confidence` (not just
`Confidence`) to avoid collision with `kbg:review-pr-tier`'s own, differently-scaled `confidence:
0.0-1.0` field (the step-3.5 adversarial verifier's confidence in its own refutation) — the two can
appear on the same presented finding and measure different things.

### Summary Format

End every review with:

```
## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0     | pass   |
| HIGH     | 2     | warn   |
| MEDIUM   | 3     | info   |
| LOW      | 1     | note   |

Verdict: WARNING — 2 HIGH issues should be resolved before merge.
```
