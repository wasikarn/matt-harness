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
