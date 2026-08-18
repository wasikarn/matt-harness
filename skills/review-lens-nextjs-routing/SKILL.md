---
name: review-lens-nextjs-routing
description: App Router file-convention (error.tsx/loading.tsx/route.ts/parallel routes) and Middleware checklist. Auto-loads when nextjs-reviewer runs. Don't use for caching/Server Actions or standalone review.
metadata:
  origin: kbg
---

# Next.js App Router Conventions & Middleware Reference

Extracted from `agents/nextjs-reviewer.md` (2026-08-18, harness-audit check 60 threshold) to keep
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

Done when every bullet above has been checked against the changed route segment and `middleware.ts`/`proxy.ts` — confirm each either doesn't apply or is filed at the severity this checklist sets.
