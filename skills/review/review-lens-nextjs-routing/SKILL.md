---
name: review-lens-nextjs-routing
description: Next.js App Router file-convention (error.tsx/loading.tsx/route.ts/parallel routes) and Middleware checklist. Auto-loads when nextjs-reviewer runs. Don't use for caching/Server Actions or standalone review.
metadata:
  origin: kbg
model: inherit
effort: medium
---

# Next.js App Router Conventions & Middleware Reference

Extracted from `agents/nextjs-reviewer.md` (2026-08-18, harness-audit check 51 threshold) to keep
the agent body under 20,000 chars. Loaded via that agent's `skills:` frontmatter field (preloaded
at spawn, independent of the Skill tool — `nextjs-reviewer` carries no `Skill` tool grant) — this
file is background material for its checklist, not a separately-triggered review pass. Read it
alongside `agents/nextjs-reviewer.md`: "step 3 above" below refers to that file's "When invoked"
list (pin the exact Next.js major version before applying any runtime-dependent rule here).

## HIGH — App Router File Conventions

- **`error.tsx` not marked `"use client"`** — error boundaries in App Router must be Client Components; a server-rendered `error.tsx` fails silently or throws a build error depending on version.
- **`error.tsx` placed expecting it to catch errors from its own segment's `layout.tsx`** — an `error.tsx` only catches errors in its sibling `page.tsx` and nested segments, never in the `layout.tsx` at the same level (the layout wraps the error boundary, not the other way around). An error thrown in the layout propagates to the *parent* segment's `error.tsx`.
- **`loading.tsx` present but the page does no `await` before first paint** — a loading state that never actually shows (because nothing suspends) is dead code masking a missing Suspense boundary elsewhere, or is genuinely unnecessary.
- **`route.ts` (Route Handler) and `page.tsx` in the same segment** — not supported; Next.js will error at build time, but the intent ("I want this URL to serve both HTML and JSON depending on Accept header") needs a different route/redirect strategy.
- **Parallel routes (`@slot`) or intercepting routes (`(.)folder`) added without a documented reason** — these are advanced, easy-to-misconfigure primitives (default `default.tsx` fallback missing causes a 404 on hard navigation to an unmatched slot). Flag if the simpler alternative (conditional rendering in a single page) would work.
- **A `fetch()` in a Server Component with no `res.ok` check and no `error.tsx` anywhere in the segment** — a failed or non-2xx response still resolves; `res.json()` either throws on a non-JSON error body or returns a shape missing the fields the JSX expects, and with no error boundary in the tree the page renders with an empty/`undefined` value instead of failing loud. On a route where stale-or-wrong data is worse than an error page (a price, a balance, anything users act on), this is a silent-failure correctness bug, not just a missing try/catch nicety — flag both the missing status check and the missing `error.tsx`.

## HIGH — Middleware

- **Node.js-only API used in `middleware.ts` — but check the pinned version's default runtime first (step 3 above), it has moved twice:**
  - **Through Next.js 15.1**: middleware runs on the **Edge runtime** by default. `fs`, most native Node modules, and many DB client libraries (Prisma's default engine, raw `mysql2`) are unavailable or silently behave differently. Check for imports that assume a Node runtime.
  - **15.2+**: an opt-in Node.js runtime became available; **15.5+** it's stable. The syntax is middleware-specific: `export const config = { runtime: 'nodejs' }` (nested inside the config object) — not a bare top-level `export const runtime = 'nodejs'`, which is the separate Route Segment Config syntax used by Pages/Layouts/Route Handlers, not middleware.
  - **16.x**: the primitive itself was renamed — `middleware.ts` is deprecated in favor of `proxy.ts`, and **Proxy defaults to the Node.js runtime**, the opposite of the pre-15.2 default. On a v16 project, don't assume Edge-runtime constraints apply without checking which convention and runtime the file actually declares.
- **Overly broad `matcher` config** — a matcher of `'/:path*'` with no exclusions runs middleware on every static asset request (`/_next/static/*`, `/favicon.ico`), adding latency to requests that never needed it. Scope the matcher to the actual routes needing the check.
- **Heavy computation or a synchronous external call in middleware** — Edge middleware has tight execution-time limits; a slow auth check here adds latency to *every* matched request, not just the ones that need it. Prefer a lightweight cookie/JWT check in middleware and defer the expensive verification to the route/action itself.
- **Middleware setting cookies then redirecting** — must construct the response first (`NextResponse.redirect` / `.next()`), set cookies on that response object, then return it; setting cookies on a discarded intermediate response is a silent no-op.

## Scope vs typescript-reviewer / mattpocock-skills:code-review

| Concern | Owner |
|---|---|
| Hooks rules, dependency arrays, `key` props, generic memoization | `typescript-reviewer` / `mattpocock-skills:code-review` |
| `any` abuse, `as` casts, generic async/promise correctness | `typescript-reviewer` |
| Generic XSS via `innerHTML`, Node.js sync-fs | `typescript-reviewer` |
| **Static vs Dynamic rendering, Data/Full-Route/Client-Router cache** | **nextjs-reviewer** |
| **`revalidatePath`/`revalidateTag`/ISR correctness** | **nextjs-reviewer** |
| **App Router file conventions (`layout`/`loading`/`error`/`route`)** | **nextjs-reviewer** |
| **Server Actions (validation, auth, revalidation scope)** | **nextjs-reviewer** |
| **`middleware.ts`/`proxy.ts` runtime constraints and matcher precision** | **nextjs-reviewer** |
| **`next/image`/`next/font`/`next/script` optimization correctness** | **nextjs-reviewer** |
| **Metadata API, `generateMetadata` waterfalls** | **nextjs-reviewer** |
| **Server/Client boundary: serialization, `server-only` leaks, `NEXT_PUBLIC_*`** | **nextjs-reviewer** (deeper than typescript-reviewer's basic check) |

For a PR touching App Router internals (caching, Server Actions, middleware, route conventions), invoke this agent. For plain component-logic changes with no framework-specific surface, `typescript-reviewer`/`mattpocock-skills:code-review` alone is sufficient.

## Server Actions — validation+auth example

```typescript
// BAD: no input validation, no auth check — directly callable with arbitrary FormData
'use server'
export async function updateProfile(formData: FormData) {
  await db.users.update(formData.get('userId'), {
    bio: formData.get('bio'),
  });
}

// GOOD: validated shape, ownership enforced against the session — not the client-supplied ID
'use server'
export async function updateProfile(formData: FormData) {
  const session = await getSession();
  if (!session) throw new Error('Unauthorized');
  const parsed = ProfileSchema.safeParse({ bio: formData.get('bio') });
  if (!parsed.success) throw new Error('Invalid input');
  await db.users.update(session.userId, { bio: parsed.data.bio }); // not formData.get('userId')
}
```

### MEDIUM — Data Fetching Patterns

- **Sequential `await` for independent data in a Server Component tree** — awaiting one fetch, then another unrelated fetch, serializes what could run in parallel. Use `Promise.all` or start both fetches before either `await`, same principle as backend async code, but here it directly extends time-to-first-byte for the whole route.
  ```tsx
  // BAD: user fetch blocks orders fetch from even starting
  const user = await getUser(id);
  const orders = await getOrders(id);

  // GOOD: both requests in flight simultaneously
  const [user, orders] = await Promise.all([getUser(id), getOrders(id)]);
  ```
- **The same data fetched via a raw DB call (not `fetch()`) in multiple components on one route** — `fetch()` gets automatic per-request memoization; a direct DB/ORM call does not. Wrap it in React's `cache()` to dedupe across components in the same render pass, or the query runs once per component instead of once per request.
- **A blocking data fetch in a `layout.tsx`** — a slow fetch in a layout blocks every child route from rendering, including ones that don't need that data. Push the fetch down to the page/leaf that actually needs it, and use a `loading.tsx`/`<Suspense>` boundary scoped to just that data.

### MEDIUM — Optimization Primitives

- **`next/image` without `width`/`height` (or `fill` with a sized parent)** — causes layout shift (CLS); the whole point of `next/image` is to prevent this, so a missing dimension defeats it.
- **`next/image` with a `sizes` prop missing on a responsively-styled image** — without `sizes`, the browser assumes the image is as wide as the viewport and over-fetches a larger asset than displayed.
- **`next/script` with the wrong `strategy`** — a non-critical third-party script (analytics, chat widget) loaded with `beforeInteractive` runs earlier than needed (preloaded and fetched before any first-party code) and delays first-party script execution, even though Next's own docs state its execution does not block hydration itself; should default to `afterInteractive` or `lazyOnload` unless the script genuinely must run before the page is interactive.
- **`generateMetadata` awaiting the same data the page component also fetches, sequentially** — Next.js dedupes identical `fetch()` calls automatically via the Data Cache, but a raw DB call in both `generateMetadata` and the page component without `cache()` runs twice, and if not parallelized (metadata resolution can run concurrently with the page render) adds unnecessary latency.

## Diagnostic Commands

```bash
# Confirm App Router vs Pages Router before applying rules
ls app/ 2>/dev/null && echo "App Router" || (ls pages/ 2>/dev/null && echo "Pages Router")

npm run build --if-present            # surfaces static/dynamic rendering decisions per route in the build output
npm run typecheck --if-present
tsc --noEmit -p <tsconfig>            # fallback
eslint . --ext .ts,.tsx               # confirm eslint-config-next is active (catches next/image, next/link misuse)

# Inspect config that changes caching/runtime defaults
cat next.config.* 2>/dev/null
```

The `next build` output's route table (○ Static, ƒ Dynamic — the current two-symbol App
Router legend; ● SSG and λ Dynamic are stale Pages Router-era symbols, not current output) is
the ground truth for
whether a route is actually being statically rendered — don't infer this from source alone
when the build output is available; report a mismatch between stated intent and actual
build-time classification as a finding.

## Output Format

Report findings grouped by severity. For each issue:

```
[CRITICAL] fetch() in Route Handler has no explicit cache directive (project pinned to Next.js 14.2)
File: app/api/prices/route.ts:12
Issue: `fetch(upstreamUrl)` has no cache option. On this project's pinned Next.js 14.x, that
  defaults to `force-cache` — live price data is cached indefinitely on the Data Cache after
  the first request. (On Next.js 15+ the default is the opposite — uncached — so re-verify this
  finding's direction if the project upgrades.)
Fix: Add `{ cache: 'no-store' }` if this must always be live, or `{ next: { revalidate: 60 } }`
  if a 60s staleness window is acceptable.
```

Always include the file path and line number. Quote the offending snippet when it improves clarity.

### Summary Format

End every review with:

```
## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0     | pass   |
| HIGH     | 1     | block  |
| MEDIUM   | 2     | info   |

Verdict: BLOCK — HIGH issues must be fixed before merge.
```

## Anti-Patterns (skip these — common LLM-reviewer false positives on Next.js code)

- **"This fetch should be memoized"** on a call already using `fetch()` — Next.js auto-dedupes `fetch()` calls with identical URL+options within one render pass. Only flag missing memoization for raw DB/ORM calls, which have no automatic dedup.
- **"Missing `'use client'`"** on a component using only server-safe hooks (none) — don't assume every component needs a directive; Server Components are the default and correct default for anything with no interactivity.
- **"This should use `getServerSideProps`"** on an App Router project — that API doesn't exist in App Router; verify Pages vs App Router (step 2 above) before suggesting a Pages Router pattern.
- **Flagging `revalidate = 0` as "caching disabled, bad for performance"** without checking whether the route intentionally needs always-fresh data (e.g., a dashboard, a price page) — `revalidate = 0` is a deliberate correctness choice on those routes, not an oversight.

Done when every bullet above has been checked against the changed route segment and `middleware.ts`/`proxy.ts` — confirm each either doesn't apply or is filed at the severity this checklist sets, the Server Actions example's BAD/GOOD contrast is applied to any Server Action in the diff, and the review's own output matches the Output Format/Summary Format templates above.
