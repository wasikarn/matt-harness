# Phase 1 step 7 — CODEOWNER gate detail

Reference for `skills/workflow/ship-merge/SKILL.md` Phase 1 step 7 (the CODEOWNER
binary/3-way gate). The step keeps the commands to run and the gate outcomes inline;
this file covers the matching engine's grammar, the discovery loop's implementation
note, review-approval SHA-pinning, and fixture coverage — everything a maintainer needs
before changing `_codeowners_match.py` or debugging a mismatch, plus, in the
"Step 7 — commands and gate" section, the step's own commands and gate outcomes (moved
verbatim from `SKILL.md` for progressive disclosure — `SKILL.md` keeps a one-line summary).

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
embedded in SKILL.md. An empty or comment-only CODEOWNERS file naturally parses to
zero rules — the shared script's own `no-owned-files-changed` branch already handles
that correctly, so SKILL.md doesn't special-case it above the script.

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
`tests/skills/test-ship-merge-codeowners.sh` exercises the shared script
directly, not a markdown-embedded copy.

## Step 7 — commands and gate (moved verbatim from `SKILL.md` Phase 1 step 7)

   **Locate CODEOWNERS pinned to this PR's head SHA** (not the local working tree — Phase 2's rebase hasn't run yet), via GitHub's search order (`.github/`, root, `docs/` — first found wins). Resolve `<head_sha>` once (`gh pr view <n> --json headRefOid --jq .headRefOid`) and reuse it for both calls below — never a value captured earlier in Phase 1 (a new commit landing between captures would let a review pinned to the older SHA still pass, the staleness issue #50 fixed):
   ```bash
   CODEOWNERS_CONTENT=$(python3 "${MH_PLUGIN_ROOT}/hooks/gates/lib/_codeowners_match.py" --discover "<head_sha>" 2>"${TMPDIR:-/tmp}/codeowners-err-$$")
   DISCOVER_RC=$?
   CODEOWNERS_FOUND=0
   CODEOWNERS_ERROR=""
   if [ "$DISCOVER_RC" -eq 0 ]; then
     CODEOWNERS_FOUND=1
   elif [ "$DISCOVER_RC" -ne 3 ]; then
     CODEOWNERS_ERROR=$(cat "${TMPDIR:-/tmp}/codeowners-err-$$" 2>/dev/null)
   fi
   trash "${TMPDIR:-/tmp}/codeowners-err-$$" 2>/dev/null
   ```
   Exit codes: `0` = found (content on stdout, possibly empty), `3` = genuinely absent everywhere (verified-N/A), `4` = a real fetch error (message on stderr). `$CODEOWNERS_ERROR` non-empty → **fail-closed, STOP** ("CODEOWNERS fetch failed, not confirmed absent — the 'never fabricate a clean result' rule applies here too"). `$CODEOWNERS_FOUND` still `0` → **N/A**, proceed to Phase 2.

   **If `$CODEOWNERS_FOUND` is `1`**, parse + match with the shared script, not prose reasoning. Reuse `gh pr diff <n> --name-only` (step 6 already calls it) and step 4's `gh pr view <n> --json reviews -q .reviews` (don't re-fetch either), plus the same `<head_sha>`:
   ```bash
   CHANGED_FILES=$(gh pr diff <n> --name-only)
   REVIEWS_JSON=$(gh pr view <n> --json reviews -q .reviews)
   python3 "${MH_PLUGIN_ROOT}/hooks/gates/lib/_codeowners_match.py" "$CODEOWNERS_CONTENT" "$CHANGED_FILES" "$REVIEWS_JSON" "<head_sha>"
   ```
   `tests/skills/test-ship-merge-codeowners.sh` exercises this shared script directly — see `references/codeowners-gate-detail.md` for the matching grammar and fixture list.

   **Gate — 3-way, not binary**, read off the script's first printed line: `PASS` (every required entry satisfied, or N/A/no-owned-files) → proceed to Phase 2. `STOP` (an unsatisfied `@username` entry, an unparseable pattern, or a non-404 fetch error) → hard Phase 1 failure; render the reason + detail lines. `DEFERRED` (every remaining entry is `@org/team` or a bare email — unresolvable against the reviews API's usernames) → don't stop; carry the detail lines into Phase 2 step 5's prompt for human acknowledgment (same pattern as the branch-protection `--admin` bypass) — proceed to Phase 2.
