# Phase 1 step 7 — CODEOWNER gate detail

Reference for `commands/ship-merge/COMMAND.md` Phase 1 step 7 (the CODEOWNER
binary/3-way gate). The step keeps the commands to run and the gate outcomes inline;
this file covers the matching engine's grammar, the discovery loop's implementation
note, review-approval SHA-pinning, and fixture coverage — everything a maintainer needs
before changing `_codeowners_match.py` or debugging a mismatch, but nothing the agent
needs to just execute the step.

**Discovery loop implementation.** The 3-path search order (`.github/`, root, `docs/`
— first found wins, not a merge of all three) and the exit-code-based
found/absent/error distinction live in the shared `hooks/gates/lib/_codeowners_match.py`'s
`discover()` — a single shared implementation, not a second, independently-maintained copy.
This doc-driven path can't fetch `headRefOid`, `changed_files`, and `reviews`
atomically in one `gh pr view --json headRefOid,files,reviews` call — Phase 2 step 3's rebase
re-check is the backstop if a race here slips a stale approval through.

**Matching grammar.** GitHub's documented CODEOWNERS grammar (verified against
GitHub's own docs, 2026-08-14): two `.gitignore` features explicitly do NOT carry
over — `[ ]` character ranges and `!` negation, so the matcher needs neither. No `/`
in a pattern matches the basename at any depth; a `/` anywhere except a lone trailing
one anchors to the repo root; a trailing `/` matches that directory and everything
under it; `*` matches within one path segment, `**` crosses segments, `?` matches one
character; last-matching-line wins. This logic lives in the shared script, not
embedded in COMMAND.md. An empty or comment-only CODEOWNERS file naturally parses to
zero rules — the shared script's own `no-owned-files-changed` branch already handles
that correctly, so COMMAND.md doesn't special-case it above the script.

**Review-approval SHA pinning.** An approval only counts if it's pinned to the PR's
*current* head commit. `gh pr view --json reviews` generally includes each review's
`commit.oid`; GitHub's GraphQL schema documents the field as nullable (e.g. on
rewritten history), and a null/missing oid is treated the same as a non-matching one
— no approval — since a repo without branch protection's "dismiss stale reviews"
enabled never strips it out upstream.

**Fixture coverage.** Verified against 22 fixture cases — matching-engine cases
(exact path match, `*.ext` any-depth, `/docs/` root-anchored directory, `apps/`
unanchored directory, `docs/*` single-level-only confirming a nested file does NOT
match, `db/**/index.md` recursive, last-match-wins, an `[abc]` bracket pattern
correctly failing the whole check closed rather than silently resolving to no-match)
plus the review-decision-state, email-owner-`DEFERRED`, and head-SHA-pinning
regressions — plus `discover()`'s own found/found-but-empty/absent/error fixtures.
`tests/commands/test-ship-merge-codeowners.sh` exercises the shared script
directly, not a markdown-embedded copy.
