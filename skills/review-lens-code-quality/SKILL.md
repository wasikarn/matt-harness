---
name: review-lens-code-quality
description: Fowler smells, React/Next.js & Node.js patterns, false positives, and output templates for code-reviewer's checklist. Auto-loads when code-reviewer runs. Don't use for db/fix-authenticity/requirement-coverage or standalone review.
bucket: review
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
— read that file's bullets first; these examples are supporting detail, not new rules. Full pairs
(Security/SQL injection, Code Quality/deep nesting, React-Next.js/missing deps, Node.js/N+1 query)
moved to `examples.md` to clear this file's own check-60 threshold — read it alongside this section.

## Common False Positives - Skip These

Patterns that LLM reviewers commonly mis-flag. Skip unless you have evidence
specific to this codebase:

- **"Consider adding error handling"** on a call whose error path is handled by
  the caller or framework, such as Express error middleware, React error
  boundaries, top-level `try/catch`, or Promise chains with `.catch` upstream.
  Before concluding the path is covered, trace one hop outward — a wrapper
  import (`asyncHandler`-style), the route registration, or the middleware
  chain — this coverage is usually one hop away, not visible in the function
  body itself, so reasoning from the body alone risks landing on the right
  non-finding without ever checking the thing this bullet is about.
- **"Missing input validation"** when the function is internal and its callers
  already validate. Trace at least one caller before flagging.
- **"Magic number"** for well-known constants: `200`, `404`, `1000` ms, `60`,
  `24`, `1024`, array index `0` or `-1`, HTTP status codes, and single-use
  local constants whose meaning is obvious from the variable name.
- **"Function too long"** for exhaustive `switch` statements, configuration
  objects, test tables, or generated code. Length is not complexity.
- **"Missing JSDoc"** on single-purpose internal helpers whose name and
  signature are self-describing.
- **"Prefer `const` over `let`"** when the variable is reassigned. Read the
  whole function before flagging.
- **"Possible null dereference"** when the preceding line narrows the type or an
  `if` guard is in scope. Trace type flow instead of pattern-matching on `?.`.
- **"N+1 query"** on fixed-cardinality loops, such as iterating a four-element
  enum, or on paths already using `DataLoader` or batching.
- **"Missing await"** on fire-and-forget calls that are intentionally detached,
  such as logging, metrics, or background queue pushes. Check for a comment or
  `void` prefix before flagging.
- **"Should use TypeScript"** or **"Should have types"** in a JavaScript-only
  file. Match the project's existing language; do not suggest a stack change.
- **"Hardcoded value"** for values in test fixtures, example code, or
  documentation snippets. Tests should have hardcoded expectations.
- **Security theater**: flagging `Math.random()` in a non-cryptographic context
  such as animation, jitter, or sampling, or flagging `eval`/`Function` in a
  plugin system that is explicitly a code-loading surface.
- **"Needs a feature flag / rollout plan"** for a single-line constant or
  config-value change on an existing branch — a flag protects a new deploy
  surface; a bare value swap doesn't create one. See the
  `transition_requirement` rule under the Requirement-Coverage Lens for the
  full test.

When tempted to flag one of the above, ask: "Would a senior engineer on this
team actually change this in review?" If no, skip.

## React/Next.js Patterns (HIGH)

When reviewing React/Next.js code, also check:

- **Missing dependency arrays** — `useEffect`/`useMemo`/`useCallback` with incomplete deps
- **State updates in render** — Calling setState UNCONDITIONALLY during render causes infinite loops. Conditional setState during render (the "adjusting state when props change" pattern) is officially supported and safe.
- **Missing keys in lists** — Using array index as key when items can reorder
- **Prop drilling** — Props passed through 3+ levels (use context or composition)
- **Unnecessary re-renders** — Missing memoization for expensive computations
- **Client/server boundary** — Using `useState`/`useEffect` in Server Components
- **Missing loading/error states** — Data fetching without fallback UI
- **Stale closures** — Event handlers capturing stale state values

(BAD/GOOD example for this section: `examples.md` § React/Next.js Patterns.)

## Node.js/Backend Patterns (HIGH)

When reviewing backend code:

- **Unvalidated input** — Request body/params used without schema validation
- **Missing rate limiting** — Public endpoints without throttling
- **Unbounded queries** — `SELECT *` or queries without LIMIT on user-facing endpoints
- **N+1 queries** — Fetching related data in a loop instead of a join/batch
- **Missing timeouts** — External HTTP calls without timeout configuration
- **Error message leakage** — Sending internal error details to clients
- **Missing CORS configuration** — APIs accessible from unintended origins
- **Process-lifetime reference retention** — `emitter.on` without a matching `off`, an unbounded `Map`/`Set` cache that never evicts, and closures capturing large objects are slow leaks that crash hours in, not request-scoped failures. Pair every `on` with `off`/`once`, use an LRU with `max` not a bare `Map`, and extract needed values from closed-over large objects instead of retaining them.

(BAD/GOOD example for this section: `examples.md` § Node.js/Backend Patterns.)

## Performance (MEDIUM)

- **Inefficient algorithms** — O(n^2) when O(n log n) or O(n) is possible — but size the flag to realistic n and whether the path is per-request hot. A 4-element nested loop is noise (over-flagging erodes trust); a 10k-row O(n^2) inside an AdonisJS/FastAPI request handler is a real p99 source. Benchmark before flagging small-n quadratic.
- **Unnecessary re-renders** — Missing React.memo, useMemo, useCallback
- **Large bundle sizes** — Importing entire libraries when tree-shakeable alternatives exist
- **Missing caching** — Repeated expensive computations without memoization
- **Caching auth/permission/session lookups is a correctness bug, not a perf win** — a Redis/memo cache on a permission or session read without a verified write-through invalidation path ships a stale-authz bypass. If anything permission-adjacent is cached, require that every mutating write invalidates the entry (or version-bumps the key) before approving; this is where MEDIUM perf filings hide CRITICAL authz misses.
- **Unoptimized images** — Large images without compression or lazy loading
- **Synchronous I/O** — Blocking operations in async contexts
- **Deeper algorithmic fix beyond the O(n^2) flag above** (heap/priority-queue, sliding window,
  binary search, backtracking) once a real bottleneck is confirmed → hand off to
  `performance-optimizer` rather than prescribing the specific data-structure rewrite here.

## Best Practices (LOW)

- **TODO/FIXME without tickets** — TODOs should reference issue numbers
- **Missing JSDoc for public APIs** — Exported functions without documentation
- **Poor naming** — Single-letter variables (x, tmp, data) in non-trivial contexts
- **Magic numbers** — Unexplained numeric constants
- **Inconsistent formatting** — Mixed semicolons, quote styles, indentation

## Review Output Format — templates

**Lead with the verdict.** Before the per-issue findings, print a one-line verdict headline —
`Verdict: <PASS|WARNING|BLOCKED> — <one-line reason>` — using the same severity counts and
wording as the Summary Format's `Verdict:` line below. The full Summary Format block still closes
the review with the detailed table; the headline just gives a reader the outcome first, matching
the Minto/BLUF discipline this fleet already applies elsewhere (`agents/summarizer.md`).

```
[CRITICAL] Hardcoded API key in source
File: src/api/client.ts:42
Issue: API key "sk-abc..." exposed in source code. This will be committed to git history.
Fix: Move to environment variable and add to .gitignore/.env.example
Revisit if: the key turns out to be a test-only placeholder already rotated out of production use

  const apiKey = "sk-abc123";           // BAD
  const apiKey = process.env.API_KEY;   // GOOD
```

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

## Project-Specific Guidelines — full checklist

- File size limits (e.g., 200-400 lines typical, 800 max)
- Emoji policy (many projects prohibit emojis in code)
- Immutability requirements (spread operator over mutation)
- Database policies (RLS, migration patterns)
- Error handling patterns (custom error classes, error boundaries)
- State management conventions (Zustand, Redux, Context)

Done when every relevant BAD/GOOD pair and heuristic above has been checked against the diff under
review — confirm each Fowler smell either doesn't apply, is suppressed by a documented repo
standard, or is filed at the severity this lens sets; every applicable React/Next.js, Node.js/Backend,
Performance, Common-False-Positives, Best-Practices, and Project-Specific-Guidelines bullet has
been checked against the diff; and the review's own output matches the Review Output
Format/Summary Format templates above.
