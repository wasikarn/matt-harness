---
name: review-pr
description: "Multi-agent PR review (quality/tests/security/types/a11y). Use when a PR is ready — by number or current branch. Don't use for quick diffs. Thai: 'รีวิว PR'."
---

# Comprehensive PR Review

Run a comprehensive pull request review using multiple specialized agents, each focusing on a different aspect of code quality.

## Core Principles

- **Route by changes, not by menu**: don't launch every agent on every diff. Phase 3 conditions are gates — touched-auth → security-reviewer, touched-error-handling → silent-failure-hunter, etc.
- **Severity over volume**: agents are issues-only by frontmatter (confidence ≥80). Phase 5 consolidates into Critical / Important / Minor tiers.
- **Findings need decisions**: every Critical / Important finding goes through Phase 6's user choice — *fix-now / fix-later / proceed* on your own branch; on a PR by number, Phase 6 *is* the submit gate (*post line-level / post summary / fix+push / skip*) — no silent dropping.
- **Submit is gated, never automatic**: posting a GitHub review is outward-facing — it requires explicit user confirmation at the submit gate (**Phase 6** for a PR-by-number review, **Phase 7** for an author-flow self-review on an existing PR). The gate is never asked twice. Reviewing a PR by number runs in an isolated worktree, so the current branch and working tree stay untouched.
- **Reproducible window**: Phase 2 pins `BASE_SHA` + `HEAD_SHA` so re-running gives the same result, not drift as commits accumulate.
- **Use TodoWrite**: track phases.

---

## Phase 1: Scope

**Goal**: Decide which review aspects apply — narrow upfront if user specified, else default to "all applicable" routed by Phase 3.

**Actions**:
1. **Detect target PR.** If user prompt contains a bare integer token (e.g. `123`), that is the **PR number** to review — Phase 2 checks it out in an isolated worktree instead of reviewing the current branch. Strip it before the aspect parse. No integer → review the current branch (existing behaviour).
2. Parse remaining arguments — recognized aspects: `code / tests / comments / errors / security / simplify / all` (see Review Aspects Reference below for what each routes to). Default if no aspect = `all`.
3. **Determine dispatch mode:**
   - If user passed `parallel` keyword → mark for parallel dispatch in Phase 4.
   - If user passed `sequential` keyword → mark for sequential.
   - If **neither** keyword passed → **Analyze**: count routed agents (Phase 3), diff size (`git diff --stat`), file types touched.
   - **Default to parallel.** Only recommend sequential when the diff is auth-heavy (security depth benefits from serialized attention) or docs-only (trivial, not worth the overhead).
   - **AskUserQuestion** single-select: "Phase 1: [N] agents routed, diff = [files changed / lines changed], auth-heavy = [yes/no]. My recommendation: [Parallel / Sequential]. Confirm dispatch mode?"
     - `Parallel (Recommended when diff is medium and no auth changes; fastest wall-clock time)` — agents are independent
     - `Sequential (Recommended when diff is auth-heavy or the user wants lower cognitive load)` — one complete report at a time
5. Output: scope summary (target: current branch **or** PR #N, which aspects in scope, dispatch mode).

---

## Phase 2: Identify Changes + Pin Review Window

**Goal**: Capture the file list + commit range so the review is reproducible.

**Actions**:
1. **Pin SHAs upfront** (two paths):
   - **Target PR (Phase 1 set a number):** `gh pr view <#> --json baseRefOid,headRefOid,headRefName,url` → take `BASE_SHA`/`HEAD_SHA` from `baseRefOid`/`headRefOid`. Then set up an **isolated worktree** so the current branch/working tree is untouched. Use a **deterministic path per PR** so a re-run reclaims a crashed run's slot instead of leaking worktrees: `git fetch origin "pull/<#>/head"`; `git worktree prune` (drop dead admin entries); `WT="${TMPDIR:-/tmp}/review-pr-<#>"`; `git worktree remove --force "$WT" 2>/dev/null || true` (clear a stale worktree left by a prior crashed run); `git worktree add --detach "$WT" "$HEAD_SHA" && cd "$WT"`. Agents review the PR's files from `$WT`; record `$WT` for Phase 7 cleanup.
   - **Current branch (no PR number):** Resolve the repo's default branch (never assume `develop`): `DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRefName 2>/dev/null || git remote show origin | awk '/HEAD branch/ {print $NF}')`; then `BASE_SHA=$(git merge-base HEAD "origin/$DEFAULT")` and `HEAD_SHA=$(git rev-parse HEAD)`. If a PR exists for this branch, prefer canonical refs: `gh pr view --json baseRefOid,headRefOid`.
2. Run `git diff --name-only "$BASE_SHA".."$HEAD_SHA"` to list files in the **pinned window** (not unstaged-only — covers full review scope, doesn't drift as new commits land mid-review).
3. Check if PR already exists: `gh pr view`.
4. Identify file types and what reviews apply.
5. **Why pin**: re-running with the same `BASE_SHA` / `HEAD_SHA` later gives the same result. Without pinning, "current diff" drifts as commits accumulate — findings become non-reproducible.

---

## Phase 3: Route Reviewers

**Goal**: Map file changes to specific reviewer agents based on what's touched.

**Actions**:
1. Route per conditional rules — each rule fires only if BOTH (a) Phase 2's file list matches the file-type condition AND (b) Phase 1's aspect arg includes the corresponding aspect (or `all`):
   - `code` aspect (or `all`) → **always**: `code-reviewer` (general-quality lens — no file-type condition)
   - `tests` aspect (or `all`) AND (test files changed **OR** files under `claude/{agents,skills,commands,hooks}/` changed) → `code-reviewer` with the **behavioral test-coverage lens** (the harness's own code is the one place an untested change is highest-risk, so it defaults on for harness diffs even with no test files in the change)
   - `comments` aspect (or `all`) AND comments/docs added → `code-reviewer` with the **comment-accuracy lens**
   - `errors` aspect (or `all`) AND error handling changed → `silent-failure-hunter`
   - `security` aspect (or `all`) AND changes touch auth/secrets/external input → `security-reviewer`
   - `types` aspect (or `all`) AND types/interfaces/DTOs/schemas/models changed → `code-reviewer` with the **type-design lens** (encapsulation, invariants, illegal-states-unrepresentable)
   - `ux` aspect (or `all`) AND user-facing UI/components/copy/flows changed → `code-reviewer` with the **UX/a11y lens** (interaction flow, WCAG basics)
   - `db` aspect (or `all`) AND migrations/schema/query files changed (`.sql` files, Drizzle schema, or query-builder calls touched) → `code-reviewer` with the **DB/SQL query-safety lens** (MySQL/MariaDB + Drizzle query and migration safety)
2. **Aspect arg overrides Phase 3's defaults.** `kbg:review-pr tests` runs ONLY code-reviewer's behavioral test-coverage lens (not the general-quality lens). `kbg:review-pr code tests` runs code-reviewer with both the general-quality and test-coverage lenses.
3. Present the routed agent list to the user. Confirm if user wants to add/remove any before Phase 4 dispatch.

**Note**: code simplification is **NOT a reviewer** — it's an optional post-review polish step. See Phase 7 step 2 next-step suggestions (uses the native `/simplify` with clarity-only scope).

---

## Phase 4: Launch Review Agents

**Goal**: Dispatch the routed agents (sequential or parallel per Phase 1's mode) and collect outputs.

**Actions**:
1. **Parallel mode** (default — fastest wall-clock time; launch all routed agents simultaneously, results come back together).
2. **Sequential mode** (when `sequential` keyword in args — one agent at a time, each report complete before next; lower cognitive load for interactive sessions).
3. Wait for all dispatched agents to return. Capture per-agent findings with file:line references.

---

## Phase 5: Aggregate + Tier Findings (Scrutinize Gate)

**Goal**: Consolidate findings, classify into severity tiers — **without** blending across agents. Apply outsider-perspective scrutiny before presenting.

**Actions**:
1. Collect all per-agent findings. **Do NOT blend findings across agents** (surface conflicts, don't average — each agent's report stands independently. Overlap between agents on the same file:line = signal, not noise. Preserve attribution: "code-reviewer + security-reviewer both flagged this" tells the user something dedupe would erase.)
2. **Apply SCRUTINIZE-4 to every finding** (named gate — the 4 questions are *falsifiable*, not vibes). A finding that fails any check goes to `.scratch/review-pr-<timestamp>/rejected.md` with the failing question + reason; the user sees the rejection tally, not the dropped finding:

   | # | Question | Falsifiable check (pass = ) | Reject if |
   |---|----------|-----------------------------|-----------|
   | 1 | **Challenge intent** — is there a simpler way? | You can name the simpler alternative in one sentence, OR you can name why the existing approach is the right one | No alternative named AND no justification for the current shape |
   | 2 | **Trace the call graph** — does the change interact with unmodified callers in surprising ways? | You followed the call path; the result is "safe" or "unsafe" with `file:line` evidence | You only read the diff, not the callers |
   | 3 | **Verify real execution branches** — does the fix break the error path / edge case? | You named at least one branch (success + 1 error/edge) and traced it | You traced the happy path only |
   | 4 | **Evidence requirement** — what supports the claim? | Finding has `file:line` (or commit SHA) + the *minimal* command/output that confirms it | Claim is plausible but unverified (matches "26-50" confidence from `code-reviewer` agent frontmatter — drop) |

   **Why named and tabular:** the prose version of this gate was skipped in real runs because it was exhausting. The named checks turn "did I scrutinize?" from a vibe into a yes/no per finding. The reject-and-log path means dropping a finding is *auditable* — the user can see what got filtered and why (vs the agent's confidence-threshold which is invisible).

   **Audit trail — `rejected.md`.** The dropped findings are not issues (don't use `.scratch/<feature>/issue.md`); they are an ephemeral audit log of a single review session. Write them to `.scratch/review-pr-<UTC-timestamp>/rejected.md` (e.g. `.scratch/review-pr-2026-06-08T15-30Z/rejected.md`) with one line per dropped finding: `- [Q3] hooks/gates/irrecoverable.sh:50 — "happy path only, didn't trace the sudo-wrapped branch"`. The dir is gitignored-by-convention under the issue-tracker's "scratch is local" rule; the user sees only a tally `Rejected: 4 (Q1: 0, Q2: 1, Q3: 2, Q4: 1)`, not the dropped body.

3. **Consolidate into severity tiers.** For each finding, assign a tier by asking *"if this ships as-is, what's the worst that could happen?"* — production breaks / a 2am page / silent data corruption / users see errors → **Critical**; a real but contained issue → **Important**; only "the code is slightly less clean" → **Minor**:
   - **Critical** — must fix before merge (security, data integrity, broken functionality)
   - **Important** — should fix before merge (real issues that don't block but shouldn't ship)
   - **Minor** — nice to have (style, optional refinements)
4. **Blanket approval rejection — clean exits must be auditable.** A bare "LGTM" with no file:line findings is treated as "no findings returned", not a clean bill of health — you can't distinguish "checked and clean" from "didn't check". A clean exit only counts as a green light when the agent names what it verified (e.g. "traced the DB+API path — no transaction gap; auth predicate unchanged"). Surface to the user which agents returned auditable-clean, which returned findings, and which returned only a bare LGTM.
5. **Apply ledger-driven tightening (if eligible).** Read `policy.md` § Threshold and the rolling 10-session aggregation. If any Q is eligible (≥50% rejection rate, ≥5 sessions), apply the *tightened* check from the policy table for that Q *this session only*. Surface a note: `Q3 tightened for this session (67% rejection over 10 sessions — was 45%)`. The user can override by saying "skip the policy" — the default SCRUTINIZE-4 check is then used and the ledger records `policy_skipped: true`.
6. **Write the ledger entry.** Sibling of `rejected.md`, in the same `.scratch/review-pr-<UTC-timestamp>/` dir. See `ledger.md` for the schema. Per-Q counters (Rejected / Survived / %), agents dispatched, scope identifier, and `policy_skipped: true` if applicable. **Prune first** — count existing `ledger.md` files, FIFO-remove oldest until count ≤ 199, then write the new entry. This keeps the rolling window bounded per `ledger.md` § Retention.
7. Surface a tier-grouped finding table to the orchestrator (you), not yet to user — Phase 6 handles user presentation.

---

## Phase 6: Present + User Decision

**Goal**: Show tier-grouped findings, then branch on the review target (set in Phase 1): **own current branch** → fix decision (fixes land in the working tree); **PR by number** → the submit decision. For a reviewer, choosing how to submit the review *is* acting on the findings — there is no "fix later", and in-place fixes in the throwaway worktree are discarded at Phase 7 cleanup unless pushed. This is the **single submit gate**; Phase 7 executes the choice, it does not re-ask.

**Actions**:
1. Present findings in this format:

   ```markdown
   # PR Review Summary

   ## Critical (X found) — must fix before merge
   - [agent-name]: Issue description [file:line]

   ## Important (X found) — should fix before merge
   - [agent-name]: Issue description [file:line]

   ## Minor (X found) — nice to have
   - [agent-name]: Suggestion [file:line]
   ```

   For tiers with zero findings, list as `Critical: 0 ✅` (explicit green light — agents are issues-only by frontmatter, so empty tier = clean signal, not "we forgot to check").

   After the tier table, surface a **1-line ledger trend** (read `ledger.md` § Aggregation — rolling 10 sessions, computed by the awk helper in `policy.md`):
   ```markdown
   **Trend (last 10 sessions)**: Q1: 12% (was 8%) — stable · Q2: 18% (was 22%) — improving · Q3: 67% (was 45%) — WORSENING · Q4: 8% (was 6%) — stable
   ```
   A `WORSENING` flag means the policy is *eligible* to tighten the Q this session (see Phase 5 step 5). The user already saw the tightening note in Phase 5; the trend line here is the *delta* since the last session. If fewer than 5 sessions of history exist, surface `insufficient data` instead of percentages.

   **Proof-verification check** (Rule 4 — define done, loop until verified): look for `.scratch/<slug>/proofs/`. If absent and the task is non-trivial (≥2 files changed or ≥1 test file touched), flag as **[verification-gap] must-fix** — independent proof is required before merge. If present, verify at least one artifact is non-empty (test output, type-check output, or adversarial review). Surface: `Proof: 2 artifacts (test + typecheck) ✅` or `Proof: missing — must-fix`.

2. **Branch on review target (from Phase 1):**

   **A. Reviewing the current branch (your own working tree)** — fixes land directly, so go straight to the fix decision:
   - **AskUserQuestion** single-select: "Phase 6: [N] Critical (must fix before merge), [N] Important (should fix before merge), [N] Minor (nice to have). My recommendation: [option]. How do you want to proceed?"
     - `Fix Critical issues now, proceed with Important/Minor later (Recommended when Critical count is low and the user wants to keep momentum)`
     - `Fix Critical + Important now, Minor later (Recommended when both tiers have real issues that shouldn't ship)`
     - `Fix all tiers now before proceeding (Recommended when review surfaced significant problems across all tiers)`
     - `Proceed as-is — acknowledge risk (Recommended only when findings are false positives or truly cosmetic)`

   **B. Reviewing a PR by number (isolated, throwaway worktree)** — the decision *is* what review to submit to the author. **First build the review payload** (per Phase 7's "Build the review payload" procedure) and show the preview, then ask **once** — Phase 7 executes the choice without re-asking:
   - **Preview** (show before the question):
     - Event type — `REQUEST_CHANGES` if any Critical, `COMMENT` if only Important/Minor, `APPROVE` if zero findings
     - Number of line-level comments to be posted
     - 2–3 sample comments (what the author will see)
     - Review body (the review summary from step 1)
   - **Prior-review check**: `gh pr view <#> --json reviews -q ".reviews[].author.login"` vs `gh api user -q .login`. If you already reviewed this PR, warn that GitHub stacks new reviews (no update-in-place) before asking.
   - **AskUserQuestion** single-select: "Phase 6: reviewing PR #N — [N] line-level comments + [event type], previewed above. My recommendation: [option]. How do you want to act on these findings?"
     - `Post line-level review now (Recommended — findings are concrete; the author sees each issue in context)` — batch via `gh api` (Phase 7)
     - `Post summary only (Recommended when line-level comments would be noisy or the diff is trivial)` — single `gh pr review --body` (Phase 7)
     - `Fix + push to the PR branch (only if you have write access / it's your own PR — worktree fixes are discarded unless committed + pushed)` — apply fixes in `$WT`, commit, push before Phase 7 cleanup
     - `Skip — I'll post manually (Recommended when the body needs rephrasing or the PR isn't ready for external review)` — nothing posted
   - To tweak the top-level body first, pick a post option and say so (or answer Other) — adjust the body, then proceed.

3. Record the decision; Phase 7 executes it:
   - **Fix now** (branch A) / **Fix + push** (branch B) — apply the fixes. For branch B, commit in `$WT` and push to the PR's head branch *before* Phase 7 cleanup removes the worktree.
   - **Fix later** (branch A) — capture as a follow-up.
   - **Post line-level / Post summary** (branch B) — Phase 7 runs the recorded submit (no second gate).
   - **Proceed as-is / Skip** — document the rationale; nothing posted.

---

## Phase 7: Summary

**Goal**: Record what was reviewed, what was addressed, suggested next step.

**Actions**:
1. Mark all todos complete. Write the review-state file so `/ship-merge`'s scored review gate can read it:
   ```bash
   mkdir -p "${REVIEW_PR_STATE_DIR:-$HOME/.claude/state}"
   CLEAN=$([ "${CRITICAL_COUNT:-0}" -eq 0 ] && echo "true" || echo "false")
   REVIEW_MODE=$([ -n "${WT:-}" ] && echo "pr-by-number" || echo "own-branch")
   printf '{"clean":%s,"critical_count":%s,"last_sha":"%s","branch":"%s","review_mode":"%s","ts":"%s"}\n' \
     "$CLEAN" "${CRITICAL_COUNT:-0}" "$HEAD_SHA" \
     "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')" \
     "$REVIEW_MODE" \
     "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     > "${REVIEW_PR_STATE_DIR:-$HOME/.claude/state}/review-last.json"
   ```
   `CRITICAL_COUNT` = number of Critical findings from Phase 5. Always write this file; it is the machine-readable input to `/ship-merge`'s Rule-14-scored review gate. A reviewer-flow run on a PR by number still writes it (using the PR's HEAD SHA) so the author can see the verdict. `review_mode` records provenance: `pr-by-number` means Phase 2 ran the review in an isolated worktree (severity tiering wasn't done by a session that could be the diff's own author); `own-branch` means an author-flow self-review, where Critical/Important tiering has no independent-verification step (see `/ship-merge` Phase 1 step 6 — this gates same-session self-tiering on sensitive diffs).
2. Summarize:
   - PR # and URL (if applicable)
   - Review window: `BASE_SHA..HEAD_SHA`
   - Agents dispatched + their tier counts (e.g. "code-reviewer: 2 Critical / 3 Important / 0 Minor")
   - User decision (author flow: fixed-now / deferred / proceeded-as-is; reviewer flow: posted line-level / posted summary / fixed+pushed / skipped)
   - **Suggested next steps** (pick what applies):
     - Wants clarity polish after fixes → run the native `/simplify` (clarity-only, behavior-preserving) as follow-up (NOT part of kbg:review-pr itself)
     - At PR-ready → `/ship-merge` (or push for review)
     - Review needs another pass after fixes → re-run `kbg:review-pr` (Phase 2 pins a new HEAD_SHA window)
     - Reviewer comments came back externally → `/address-review`
     - Reviewer flow (PR #N), review posted → done; ping the author / await their `/address-review`
3. **Submit the review to GitHub** (gated — never auto-submit; posting a review is outward-facing). Posts findings as **individual line-level review comments** so the author sees each issue in context — not just a single top-level summary.

   **Build the review payload** (canonical procedure — Phase 6 branch B builds its preview from this):
   - **Event**: `REQUEST_CHANGES` if any Critical findings, `COMMENT` if only Important/Minor, `APPROVE` if zero findings.
   - **Review body**: The Phase 6 summary (top-level overview).
   - **Comments array**: For every finding that has `file` + `line`, create:
     ```json
     {"path": "<file-path>", "line": <line-number>, "side": "RIGHT", "body": "[<severity>] <message>"}
     ```
     Findings without file:line go into the review body instead.

   **Two entry points — the gate is never asked twice:**
   - **Reviewer flow (PR #N):** the submit decision (preview + prior-review check + choice) already happened in **Phase 6 branch B**. **Do not re-ask.** Execute the recorded choice: *Post line-level* → JSON + `gh api` (below); *Post summary only* → single `gh pr review --body`; *Fix + push* → already applied/pushed in Phase 6, nothing to post; *Skip* → nothing to post.
   - **Author flow (current branch):** Phase 6 was a fix decision, so offer submit **here**, only if a PR exists for the branch. **Prior-review check**: `gh pr view <#> --json reviews -q ".reviews[].author.login"` vs `gh api user -q .login`; if you already reviewed, warn that GitHub stacks new reviews. **Preview** event type + comment count + 2–3 samples + body, then **AskUserQuestion** single-select: `Post line-level review now` / `Post summary only` / `Skip — post manually`. If no PR exists yet, skip (nothing to submit to).

   **If posting line-level comments**, build JSON (`commit_id: $HEAD_SHA`, `event`, `body`, `comments[]`) and submit:
   ```bash
   python3 -c "import json,sys; print(json.dumps({'commit_id':sys.argv[1],'event':sys.argv[2],'body':sys.argv[3],'comments':json.loads(sys.argv[4])}))" \
     "$HEAD_SHA" "$EVENT" "$REVIEW_BODY" "$COMMENTS_JSON" \
     | gh api repos/{owner}/{repo}/pulls/<n>/reviews --method POST --input -
   ```
   `<#>` = target PR number, or current branch's PR (`gh pr view --json number -q .number`). If no PR exists yet, skip (nothing to submit to).
4. **Clean up the worktree** if Phase 2 created one: `cd` back to the original repo dir, then `git worktree remove "$WT" --force`.

---

**Reference tables** (aspect routing, agent descriptions, tips, workflow examples): `reference.md` in this skill directory.

## Notes

- Agents run autonomously and return detailed reports
- Each agent focuses on its specialty for deep analysis
- Results are actionable with specific file:line references
- Agents use models per their frontmatter (`model:` field)
- Routed agents listed via `kbg:inventory` (your skill that lists everything available) or `claude agents` CLI — **not** `/agents` (that's a UI command for managing definitions, not a listing)

---

## Integration Notes (Project-Specific)

- **Token budget**: Each agent review fits 4K task / 30K session budget. Parallel mode (Phase 4 default) is fastest; sequential is available for interactive sessions that need lower cognitive load.
- **Agent teams**: Not recommended for PR review — latency too high for a task that needs quick iteration.
- **Hooks active**: `hooks/gates/verifier-protect.sh` asks for approval on edits to the gate/audit verifier surfaces during the session; it does not cover CLAUDE.md/METHODOLOGY.md directly. There is no dedicated secret-scanning hook today.
- **GH CLI**: Use `gh pr view` to check PR state; `gh pr checks` to see CI status before launching review. Reviewing by number fetches `pull/<#>/head` into a throwaway `git worktree` (removed in Phase 7). Submitting the review uses `gh api repos/{owner}/{repo}/pulls/<n>/reviews` with a JSON payload containing `commit_id`, `event`, `body`, and `comments[]` — posting findings as individual line-level comments. "Summary only" fallback uses `gh pr review --comment/--request-changes/--approve`. Both paths are gated on user confirmation (requires `Bash(gh api ...)` allow in settings.json).
- **Review routing reference**: Code that touches auth/secrets → `kbg:security-auditor` for full audit. General code → code-reviewer. Tests, comments, types → code-reviewer with its behavioral test-coverage / comment-accuracy / type-design lens. Error handling → silent-failure-hunter. Polish → native `/simplify` with clarity-only scope (post-review opt-in, **not** part of kbg:review-pr).
- **Severity tier rubric** (Phase 5): Critical / Important / Minor are canonical across `/ship`, `/fix-bug`, and `kbg:review-pr` — normalized in commit `9e89bf2`.
- **SCRUTINIZE-4 rubric** (Phase 5): Challenge intent / Trace call graph / Verify execution branches / Evidence requirement. Named + tabular (4 falsifiable checks) so the gate is a yes/no per finding, not prose that gets skipped. Dropped findings go to `.scratch/review-pr-<UTC-timestamp>/rejected.md` (ephemeral audit log, not an `issue.md`) with a per-question tally surfaced to the user.
- **Rejection-rate ledger** (Phase 5+6): per-session per-Q counters written to `ledger.md` (sibling of `rejected.md`). Rolling 10-session window drives a 1-line trend + tightening eligibility. Spec: `ledger.md`. Policy (threshold, tightening action, hard caps, reversibility, awk aggregation helper): `policy.md`. Cap: 200 sessions FIFO, 1 tightening per Q per 90 days, 1 tightening per session max.
