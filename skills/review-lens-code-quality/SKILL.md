---
name: review-lens-code-quality
description: Fowler smells, AI-generated-code priorities, and BAD/GOOD examples for code-reviewer. Auto-loads when code-reviewer runs its checklist. Don't use for db/fix-authenticity/requirement-coverage lenses or standalone review.
metadata:
  origin: kbg
---

# Code-Quality Baseline Reference

Extracted from `agents/code-reviewer.md` (2026-08-18, harness-audit check 60 threshold) to keep
the agent body under 20,000 chars. Referenced inline from the Code Quality, Security,
React/Next.js Patterns, and Node.js/Backend Patterns sections there — this file is background
material for that checklist, not a separately-triggered review pass. Read it alongside
`agents/code-reviewer.md`: references below to "above," "this section," and the Pre-Report
Gate/HIGH-CRITICAL proof gate point back to that file, not to this one.

## Fowler smell baseline

**Fowler smell baseline** (*Refactoring*, ch. 3) — a fixed set of judgement-call
heuristics that applies even where the repo documents nothing. Two binding
rules: a documented repo standard always overrides the baseline (suppress the
smell where the repo endorses what it would flag), and every smell below is a
labelled heuristic ("possible Feature Envy") never a hard violation — skip
anything tooling already enforces.

These are structural observations about the code's shape, not bug reports.
Default them to **MEDIUM**, not this section's HIGH — "labelled heuristic,
never a hard violation" is a lower bar than a defect that will definitely
misbehave, and MEDIUM findings don't hit the HIGH/CRITICAL proof gate above
(three required items, including a concrete failure scenario — exactly what
a structural observation can't supply). Don't drop a smell just because
nothing calls the code yet; that's this heuristic's own default-severity
question, already answered by MEDIUM, not a reason to withhold the finding
entirely. If a smell is also causing an active, demonstrable bug — not just
a shape problem — report that at the severity and evidence bar the bug
itself earns, using the normal Pre-Report Gate.

- **Mysterious Name** — a function, variable, or type whose name doesn't reveal what it does or holds. → rename it; if no honest name comes, the design's murky.
- **Feature Envy** — a method that reaches into another object's data more than its own. → move the method onto the data it envies.
- **Data Clumps** — the same few fields or params keep travelling together (a type wanting to be born). → bundle them into one type, pass that.
- **Primitive Obsession** — a primitive or string standing in for a domain concept that deserves its own type. → give the concept its own small type.
- **Repeated Switches** — the same `switch`/`if`-cascade on the same type recurs across the change. → replace with polymorphism, or one map both sites share.
- **Shotgun Surgery** — one logical change forces scattered edits across many files in the diff. → gather what changes together into one module.
- **Divergent Change** — one file or module is edited for several unrelated reasons. → split so each module changes for one reason.
- **Speculative Generality** — abstraction, parameters, or hooks added for needs nothing in scope has. → delete it; inline back until a real need shows.
- **Message Chains** — long `a.b().c().d()` navigation the caller shouldn't depend on. → hide the walk behind one method on the first object.
- **Middle Man** — a class or function that mostly just delegates onward. → cut it, call the real target direct.
- **Refused Bequest** — a subclass or implementer that ignores or overrides most of what it inherits. → drop the inheritance, use composition.

(Duplicated Code and Long Method are already covered above as Duplicated
helper/util and Large functions — not repeated here.)

**Sync seam:** `skills/review-pr/reference.md` §Fowler Smell Baseline carries the
full 12-smell table (including Duplicated Code) as background for the `code`
aspect's general-quality lens. The 11-vs-12 gap here is deliberate, not drift —
if you edit this list, check whether that table needs the matching edit.

## v1.8 AI-Generated Code Review Addendum

When reviewing AI-generated changes, prioritize:

1. Behavioral regressions and edge-case handling
2. Security assumptions and trust boundaries
3. Hidden coupling or accidental architecture drift
4. Unnecessary model-cost-inducing complexity

Cost-awareness check:
- Flag workflows that escalate to higher-cost models without clear reasoning need.
- Recommend defaulting to lower-cost tiers for deterministic refactors.

## BAD/GOOD examples appendix

Illustrative pairs for checklist items already stated in prose bullets in `agents/code-reviewer.md`
— read that file's bullets first; these examples are supporting detail, not new rules.

### Security — SQL injection

```typescript
// BAD: SQL injection via string concatenation
const query = `SELECT * FROM users WHERE id = ${userId}`;

// GOOD: Parameterized query (MySQL/MariaDB ? — Postgres uses $1)
const query = `SELECT * FROM users WHERE id = ?`;
const result = await db.query(query, [userId]);
```

### Code Quality — deep nesting + mutation

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

### React/Next.js Patterns — missing dependency array

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

### Node.js/Backend Patterns — N+1 query

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

Done when every relevant BAD/GOOD pair and heuristic above has been checked against the diff under
review — confirm each Fowler smell either doesn't apply, is suppressed by a documented repo
standard, or is filed at the severity this lens sets.
