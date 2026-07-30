---
name: claude-md-health
description: "Scan a CLAUDE.md/doctrine file against 3 health checks (readable-by-behavior, findable, fix-once). Use when a governance doc has grown stale. Don't use for content-completeness (claude-md-management:claude-md-improver)."
---

# CLAUDE.md Health Audit

Source: the Harness Handbook paper (behavior localization + BGPD funnel), applied to kbg-harness's own CLAUDE.md, the global `~/.claude/CLAUDE.md`, and the tathep monorepo root CLAUDE.md across a 2026-07-18 session — three manual runs, real findings every time. This skill is that manual process made repeatable.

Applies to any CLAUDE.md-shaped governance file: a repo's own CLAUDE.md, the global one, a monorepo root navigator, or a doc one of those cites as canonical.

## When to use / not

Use for a periodic health pass on a governance doc that's grown, or before trusting one you haven't touched in a while.

Don't use for:
- A known-small fix (typo, one added line) — just make it, no audit needed.
- Content-completeness review (are commands documented, is the architecture section current, A-F grading) — that's `claude-md-management:claude-md-improver`. Different rubric, near-zero overlap with the check below that actually matters (see Test 3) — run both for full coverage, this doesn't replace it.
- Code or security review.

## The 3 checks

1. **Readable** (อ่านง่ายไหม) — In 30 seconds, can you name every distinct behavior area the file covers? Headers must be behavior-scoped ("before deleting a file, ask first"), not generic buckets ("notes", "gotchas", "misc") hiding unrelated rules under one label.
2. **Findable** (หาเจอไหม) — Given one specific behavior, can you point to the exact line without reading the whole file? A flat list of 8+ unrelated bullets under one header fails this even with bold lead-ins — it needs sub-headers or a table.
3. **Fix-once** (แก้แล้วจบไหม) — Edit the rule in one place: does the behavior actually change everywhere, with no old copy left in another doc — **and** does the rule still match what's actually true right now (a branch that no longer exists, a domain that changed, a count nobody re-grepped)? This is the direct analogue of the paper's BGPD verification step: don't trust a candidate location, check it against the real current source.

**Test 3 is the one that matters most.** Across the 3 audits that produced this skill, every real finding — a stale flag-count in a memory file, a duplicated ticket-prefix rule, a branch-model claim that had drifted out of sync with both its own canonical doc *and* the repo's actual git history, and could send a hotfix to the wrong branch — came from Test 3. Tests 1 and 2 caught cosmetics. Don't let a clean Test-1/2 pass read as "the file is healthy" when Test 3 wasn't actually run.

## Workflow

### Phase 1 — Scope

List the target file(s). If auditing one file, also gather:
- Every file it cross-references: grep for `see `, `canonical in`, `canonical:`, `mirrored in`, `supersedes`, and markdown links (`\[.*\]\(.*\.md\)`).
- Sibling governance files one level up/down (global CLAUDE.md if auditing a project one, or vice versa) even with no explicit pointer between them — the highest-value catch this session (a memory file's stale count vs. the CLAUDE.md line it should've matched) had **no cross-reference at all** between the two copies. A pointer-following sweep alone misses this class; also check the project's memory store (`~/.claude/projects/<enc>/memory/MEMORY.md`) for facts that duplicate anything in the target file.

### Phase 2 — Tests 1 + 2 (structural read, single file)

- List every `#`/`##` header. Flag any whose body mixes ≥2 unrelated behaviors, or reads as a generic bucket (gotchas/misc/notes) instead of naming a specific behavior area.
- For a bucket with many bullets, check whether the file already uses tables/sub-headers elsewhere — match its own established convention before proposing a new structure.

### Phase 3 — Test 3 (two sub-checks, run both)

**3a. Doc-vs-doc** — for each fact in the target file that also appears in a file gathered in Phase 1:

```bash
# find where else a specific fact/claim shows up
grep -rn "<the specific claim, e.g. a count, a flag name, a branch name>" <target-dir> <cross-ref-files> ~/.claude/projects/*/memory/

# once two copies are found, date-check which one is current
git log -1 --format='%ad %s' --date=short -- <file-A>
git log -1 --format='%ad %s' --date=short -- <file-B>
# or, to date-check a specific claim rather than the whole file:
git blame -L <start>,<end> -- <file>
```

If both copies state the same fact independently (not one pointing at the other as source of truth), that's duplication risk. If the dates disagree, the older copy is stale.

**3b. Doc-vs-reality** — for each fact that describes something checkable directly (a branch name, a domain, a file path, a config value, a flag carried by N surfaces), verify it against the live thing it describes, not just against a second doc:

```bash
git -C <repo> branch -a --list '<claimed-branch>'          # does the claimed branch still exist / is it still the production track?
git -C <repo> log -1 --format='%s (%ad)' --date=short <branch>  # what actually happened on it most recently?
grep -rl "<claimed-flag>: true" <skills-or-surfaces-dir>    # does the count in prose match a fresh grep?
```

This is the direct analogue of the paper's BGPD funnel: the last step never trusts a located candidate, it re-checks it against the actual current source. A claim can be internally consistent across every doc that cites it and still be wrong — 3a alone won't catch that, only 3b will.

Report a finding either way — a wrong "canonical" doc, or a doc that's merely internally consistent but stale, can both be actively followed into a wrong operational decision.

**If Phase 1 found no cross-referenced files and 3b has nothing checkable, say so explicitly in the report** — "no cross-references and nothing directly checkable in scope, Test 3 not exercised" — never let an empty Test-3 section read as a pass. A check that silently didn't run is the exact false-confidence failure this skill exists to catch.

### Phase 4 — Report

Table: file | check | verdict | evidence. **Verdict column: exactly one of `pass` / `fail` / `not-exercised`** — lowercase, hyphenated, no other casing or synonyms (`Pass`, `FAIL`, `unverifiable`, `unexercised` all drift from this and make verdicts hard to grep across a batch of audit reports later). A partially-satisfied check is still `fail` — explain the partial nature in the evidence column, don't invent a fourth state. Confirm every fail with the actual grep/git output, not a re-read of the same file — a duplication claim needs a second, independent source before it counts as a finding.

### Phase 5 — Fix (only on request)

Present findings and stop — don't auto-edit, especially for files outside the current repo or with wider blast radius (global config, a shared doc). Fixing a 3a duplication: prefer turning one side into a pointer, matching whichever file already reads as more foundational — unless the duplication is structurally required (e.g. a portable plugin file that must stand alone), in which case make the sync-note reciprocal (both copies say a twin exists), not one-directional. Fixing a 3b drift: correct the claim to match the verified live state directly — there's no second doc to reconcile with, just a fact to update.

## Related

- `claude-md-management:claude-md-improver` — content-completeness/currency grading for a single CLAUDE.md. Complementary, not overlapping: it has no cross-file drift check.
- `memory-lint` — deterministic bookkeeping lint for the memory store itself (dangling links, index drift). Different scope: that's link hygiene, this is fact-duplication across governance docs.
- `harness-audit` — kbg-harness's own fleet/schema audit. Scoped to this repo's surfaces, not arbitrary CLAUDE.md files.
