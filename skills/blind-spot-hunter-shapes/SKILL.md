---
name: blind-spot-hunter-shapes
description: Catalog of 7 highest-yield blind-spot shapes (cross-file, framework-behavior, data-flow-asymmetry, identity, scope-mismatch, emitted-string, vacuous-test). Auto-loads when blind-spot-hunter runs. Don't use for escalation/output-format or standalone hunting.
bucket: review
metadata:
  origin: kbg
model: inherit
effort: xhigh
---

# Blind-Spot Hunt Shapes Reference

Extracted from `agents/blind-spot-hunter.md` (2026-08-18, harness-audit check 51 threshold) to keep
the agent body under 20,000 chars. Loaded via that agent's `skills:` frontmatter field (preloaded
at spawn, independent of the Skill tool — `blind-spot-hunter` carries no `Skill` tool grant) — this
file is the hunt-shape catalog, not a separately-triggered pass. Read it alongside
`agents/blind-spot-hunter.md`: the posture flip, techniques, severity-escalation contract,
decoy-clearing, advisory-only stance, and output format all stay in that file — this catalog is
reference material for step "walk the delta's data path end to end and hunt each shape" there.

## What you hunt — the shapes, highest-yield first

Empirically, the defects that escape review are *semantic/logic* and *interaction* bugs far more
than mechanical ones, and they cluster where a change spans multiple files. Walk the delta's data
path end to end and hunt each shape. The bug is always specific; the shapes generalize.

1. **Cross-file / interaction (composition wrong, pieces each fine).** The bug appears only when
   reasoning across multiple files, services, or execution paths at once. Highest-yield class.
   - *Sibling-consistency*: N siblings got treatment X, one didn't (a rewritten delete path with
     no transaction+redlock its 3 siblings got; a sibling detail endpoint that whitelists only the
     old types the listing PR just extended).
   - *The pinned diff is a boundary*: the bug lives in a file the diff didn't touch — a second
     consumer of a shared component, a sibling UseCase, an E2E spec under `e2e/` the reviewers'
     `src/`-only grep never reached. Reviewers who review "the diff" cannot see this by
     construction.
   - *Shared component, no prop-level isolation*: an edit to a shared widget silently shifts every
     consumer, not just the one flow being changed.
2. **Framework / library auto-behavior nobody verified.** A framework does something implicit —
   auto-appends, auto-serializes, coerces a default, retries silently, times out on only part of
   the operation. Verify the framework's *actual* runtime behavior against its installed source or
   docs, never from memory.
   - Next.js `prepareDestination` auto-appends any `source` param the `destination` doesn't
     consume to the redirect's query string.
   - axios `timeout` covers header/socket-inactivity, **not** body transfer; `maxContentLength` is
     a no-op for `responseType:'stream'`.
   - a config `.update()` / migration / macro indexer that assumes framework semantics it never
     checked (Forge `findCodeBlocks` counts *every* code block, not one language).
   - a safety guard that exists only in the dev build — wrapped in `if (__DEV__)` / behind a debug
     flag / a dev middleware — and is stripped in production, so the check the reviewer saw does
     not run where it matters.
3. **Data-flow asymmetry along a path (blacklist then whitelist, or acquire vs release).** One
   stage denies known-bad (a blacklist — leaks everything else), a later stage allows known-good
   (a whitelist). A leaked value may or may not be caught downstream — trace it stage by stage,
   both ends. (`lodash.omit` leaks a key into filter context, saved only because the API mapper is
   a whitelist; a lock acquire covers the full key set but rollback only releases the prefix below
   the failure index.) Taint is path-sensitive: the same sink is safe on one path, unsafe on
   another. Ask **"which layer owns validation?"** — a value reaches a sink unsanitized because
   each side assumed the *other* layer cleaned it, or because an internal header/field is trusted
   at face value (a forged internal header that bypasses auth; a delimiter-injected field that
   forges trusted metadata).
4. **Identity assumption (assumed-equal, never proven).** Code assumes two sets/maps/types/keys
   are equal — "this retype is safe," "these ordinals double as the legacy step number," "same as
   the block above." Verify the assumed-equal things are *provably* equal; a retype is safe only
   because the key sets are identical, and an ordinal set that *collides* with legacy values at one
   index is a latent bug the moment the collision is reached.
5. **Scope / glob breadth mismatch.** A wildcard/matcher captures more (or less) than intended, or
   the reviewers' own search scope was narrower than the change's blast radius (a 5-line grep
   window missed a sibling write 25 lines away; `src/`-only greps missed `e2e/`). When you grep,
   grep the whole blast radius, not the diff window.
6. **Emitted STRING contradicts correct code.** Reviewers check code and code *comments*; they
   almost never read the log message, redirect `Location` header, or error string the code
   *emits*. `typeof null === "object"` makes a guard log "dropped non-object input of type:
   object." A comment that misstates or understates a risk is the same class — verify every
   load-bearing comment/string against the code it describes.
7. **Vacuous / tautological test.** A test whose assertion cannot fail — a negative assertion on a
   matcher that can't match the regression's output. Reason statically: does the matcher's pattern
   even match what a broken version would render? Then **name the mutation check** that confirms it
   — "delete the guard this test protects; the test should then FAIL — if it still passes, it's
   vacuous" — for the operator to run (you are read-only; see Techniques).

These seven are the seed, not the ceiling. Any seam between files, or between code and a framework
behavior, or between what code does and what it says it does, is fair game.

Done when the delta's data path has been walked end to end against all 7 shapes above — confirm
each either doesn't apply to this diff or produced a candidate that went through
`agents/blind-spot-hunter.md`'s severity-escalation contract.
