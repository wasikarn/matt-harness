---
name: review-pr
description: "Scan a PR review (quality/tests/security/types/db) via multiple agents. Use when a PR is ready, by number/branch. Don't use for quick diffs. Thai: 'รีวิว PR'."
---

# Comprehensive PR Review

Run a comprehensive pull request review using multiple specialized agents, each focusing on a different aspect of code quality.

## Core Principles

- **Route by changes, not by menu**: don't launch every agent on every diff. Phase 3 conditions are gates — touched-auth → security-reviewer, touched-error-handling → silent-failure-hunter, etc.
- **Severity over volume**: agents are issues-only by frontmatter (confidence ≥80). Phase 5 consolidates into Critical / Important / Minor tiers.
- **Findings need decisions**: every Critical / Important finding goes through Phase 6's user choice — *fix-now / fix-later / proceed* on your own branch; on a PR by number, Phase 6 *is* the submit gate (*post line-level / post summary / fix+push / skip*) — no silent dropping.
- **Submit is gated, never automatic**: posting a GitHub review is outward-facing — it requires explicit user confirmation at the submit gate (**Phase 6** for a PR-by-number review, **Phase 7** for an author-flow self-review on an existing PR). The gate is never asked twice. Reviewing a PR by number runs in an isolated worktree, so the current branch and working tree stay untouched.
- **Reproducible window**: Phase 2 pins `BASE_SHA` + `HEAD_SHA` so re-running gives the same result, not drift as commits accumulate.
- **The checker isn't the maker**: Phase 5 step 3.5 sends every Critical/Important finding to a fresh, independent agent that tries to refute it — the same context that found an issue never gets to be the sole judge of whether it survives. Step 3.6 covers the mirror case: when the reviewers find *nothing* on a non-trivial diff, one fresh agent hunts adversarially for the defect a shared blind spot would have hidden — a clean pass is a verdict from a second pair of eyes, not the absence of a finding.
- **Use TodoWrite**: track phases.

---

## Phase 1: Scope

**Goal**: Decide which review aspects apply — narrow upfront if user specified, else default to "all applicable" routed by Phase 3.

**Actions**:
1. **Detect target PR.** If user prompt contains a bare integer token (e.g. `123`), that is the **PR number** to review — Phase 2 checks it out in an isolated worktree instead of reviewing the current branch. Strip it before the aspect parse. No integer → review the current branch (existing behaviour).
2. Parse remaining arguments — recognized aspects: `code / tests / comments / errors / security / types / db / simplify / all` (see Review Aspects Reference below for what each routes to). Default if no aspect = `all`.
3. **Determine dispatch mode:**
   - If user passed `parallel` keyword → mark for parallel dispatch in Phase 4.
   - If user passed `sequential` keyword → mark for sequential.
   - If **neither** keyword passed → **Analyze**: count routed agents (Phase 3), diff size (`git diff --stat`), file types touched.
   - **Default to parallel.** Only recommend sequential when the diff is auth-heavy (security depth benefits from serialized attention) or docs-only (trivial, not worth the overhead).
   - **AskUserQuestion** single-select: "Phase 1: [N] agents routed, diff = [files changed / lines changed], auth-heavy = [yes/no]. My recommendation: [Parallel / Sequential]. Confirm dispatch mode?"
     - `Parallel (Recommended when diff is medium and no auth changes; fastest wall-clock time)` — agents are independent
     - `Sequential (Recommended when diff is auth-heavy or the user wants lower cognitive load)` — one complete report at a time
4. Output: scope summary (target: current branch **or** PR #N, which aspects in scope, dispatch mode).
5. **Detect a Jira ticket reference (opt-in requirement cross-check).** Only when the prompt contains the case-insensitive substring `jira` **and** a ticket-key-shaped token (`[A-Z][A-Z0-9]*-\d+`, e.g. `TP-871`) — requiring both avoids false-triggering on unrelated tokens shaped like `UTF-8`/`COVID-19`/`ISO-8601` with no Jira context. If both are present, record `JIRA_KEY` = the matched token and continue to Phase 1.5. **If either is missing, `JIRA_KEY` stays unset and every step below tagged "opt-in" or "if `JIRA_KEY` set" is skipped** — this feature is additive; the default no-ticket flow is unchanged.

---

## Phase 1.5: Requirement Cross-Check (opt-in — only if Phase 1 detected `JIRA_KEY`)

**Goal**: Ground the review in the ticket's actual requirements, not just code quality — fetch it, analyze it for gaps, and hand grounded requirements to Phase 3's requirement-coverage lens.

**Skip this entire phase if `JIRA_KEY` is unset.**

**Actions**:
1. **Fetch the ticket via the `jira-acli:acli` skill** — never a raw `acli` command or a direct `mcp__*atlassian*`/`mcp__*Rovo*` tool call (CLAUDE.md's global Jira/Confluence routing rule covers read-only search/view too). This fetch happens here, in the main loop, precisely because a dispatched subagent has no `Skill` tool and cannot do this itself. **`jira-acli` is a separate plugin** — if it isn't installed, that's the same as a fetch failure (next step): note it and move on, don't fall back to a raw `acli`/MCP call.
2. **Fetch fails** (bad key, no access, empty body, or `jira-acli` not installed) → record `JIRA_FETCH_FAILED=true`, surface a one-line note in Phase 6, and skip the rest of this phase. An unresolved ticket reference never blocks the code review.
3. **Dispatch `requirement-analyst`** (Agent tool) with the fetched ticket body as its prompt — it never fetches anything itself. Capture the structured report: `verdict`, `business_trace`, `functional_requirements`, `non_functional_requirements`, `transition_requirements`, `ambiguities`, `bundled_requirements`, `acceptance_criteria`, `open_questions`.
4. Record `JIRA_REQS` = `functional_requirements` + `acceptance_criteria` + `transition_requirements` (Phase 3's requirement-coverage lens checks the diff against these). Keep this separate from the ticket-quality findings (`ambiguities` / `bundled_requirements` / `open_questions` / `verdict`) — those aren't code findings; Phase 6 presents them as their own section, never blended into the Critical/Important/Minor tiers.

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
   - `code` aspect (or `all`) AND the dominant changed-file language (by extension plurality among Phase 2's file list) has a matching specialist → **also** dispatch the specialist alongside `code-reviewer`: `.ts`/`.tsx`/`.js`/`.jsx` → `typescript-reviewer`, `.py` → `python-reviewer`, `.dart` → `flutter-reviewer`. No specialist for other languages — `code-reviewer`'s general-quality lens is the only pass. (These three agents already exist in the fleet, reachable via `kbg:orchestrate`; `review-pr` itself never routed to them before.)
   - `tests` aspect (or `all`) AND (test files changed **OR** files under `claude/{agents,skills,commands,hooks}/` changed) → `code-reviewer` with the **behavioral test-coverage lens** (the harness's own code is the one place an untested change is highest-risk, so it defaults on for harness diffs even with no test files in the change)
   - `comments` aspect (or `all`) AND comments/docs added → `code-reviewer` with the **comment-accuracy lens**
   - `errors` aspect (or `all`) AND error handling changed → `silent-failure-hunter`
   - `security` aspect (or `all`) AND changes touch auth/secrets/external input → `security-reviewer`
   - `types` aspect (or `all`) AND types/interfaces/DTOs/schemas/models changed → `code-reviewer` with the **type-design lens** (encapsulation, invariants, illegal-states-unrepresentable)
   - `db` aspect (or `all`) AND migrations/schema/query files changed (`.sql` files, Drizzle schema, or query-builder calls touched) → `code-reviewer` with the **DB/SQL query-safety lens** (MySQL/MariaDB + Drizzle query and migration safety)
   - `JIRA_KEY` set (Phase 1.5 ran and didn't hit `JIRA_FETCH_FAILED`) → **always** dispatch `code-reviewer` with the **requirement-coverage lens** (checks the diff against `JIRA_REQS`), **regardless of aspect narrowing** — an explicit ticket reference is a stronger signal than an aspect filter, same as the harness-diff default in the `tests` rule above.
2. **Aspect arg overrides Phase 3's defaults.** `kbg:review-pr tests` runs ONLY code-reviewer's behavioral test-coverage lens (not the general-quality lens). `kbg:review-pr code tests` runs code-reviewer with both the general-quality and test-coverage lenses.
3. Present the routed agent list to the user. Confirm if user wants to add/remove any before Phase 4 dispatch.

**Note**: code simplification is **NOT a reviewer** — it's an optional post-review polish step. See Phase 7 step 2 next-step suggestions (uses the native `/simplify` with clarity-only scope).

---

## Phase 4: Launch Review Agents

**Goal**: Dispatch the routed agents (sequential or parallel per Phase 1's mode) and collect outputs.

**Actions**:
1. **Parallel mode** (default — fastest wall-clock time; launch all routed agents simultaneously, results come back together).
2. **Sequential mode** (when `sequential` keyword in args — one agent at a time, each report complete before next; lower cognitive load for interactive sessions).
3. **Pass the pinned window into every dispatch prompt**: state the exact range, `git diff $BASE_SHA..$HEAD_SHA` (Phase 2's pinned SHAs). An agent's own default context-gathering step (uncommitted `git diff --staged`/`git diff`) is for ad-hoc invocation outside this skill — when dispatched from here, it must review the pinned range, not whatever happens to be sitting in the working tree.
3.5. **Requirement-coverage lens dispatch** (only when Phase 3 routed it): include `JIRA_REQS` (Phase 1.5's extracted requirements) verbatim in `code-reviewer`'s dispatch prompt, plus the instruction to apply the requirement-coverage lens per `agents/code-reviewer.md`'s dedicated checklist section — including its "grep beyond the diff before flagging unaddressed" rule. This can be the same `code-reviewer` dispatch as the general-quality lens (one dispatch, multiple active lenses) — no separate agent call needed.
4. Wait for all dispatched agents to return. Capture per-agent findings with file:line references. **An agent that returns nothing, errors, or times out is not a clean pass** — record it in `dispatch_failures` for Phase 5 step 4; never let a missing report silently read as zero findings.

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

   **Requirement-coverage findings tier the same way, no special-casing** — they arrive as ordinary `code-reviewer` findings (Phase 4 step 3.5's lens dispatch), so they flow through SCRUTINIZE-4 and step 3.5's adversarial verifier below exactly like any other finding. This is load-bearing, not incidental: a coverage finding claims "not in the diff," and the "already implemented elsewhere" false-positive that risk is exactly what the fresh-agent refutation below exists to catch — don't route these around it.
3.5. **Independent adversarial verification — Critical/Important findings only.** SCRUTINIZE-4 (step 2) is self-graded: the same orchestrator context that ran the checklist decides whether its own checklist passed. That's the maker grading its own work — the exact pattern CLAUDE.md's verifier-separation principle rejects everywhere else in this harness. This step is the actual independent check: for every unique Critical/Important finding, dispatch a **fresh** agent (the general-purpose type, not the specialist that raised the finding — a fresh generalist lens is what makes it independent, not a repeat of the same specialist's framing) with the finding's description + file:line + evidence, instructed to *try to refute it* by reading the real code at that location. The verifier returns a structured verdict: `isReal` (bool), `confidence` (0.0–1.0), `reasoning` (one paragraph).

   **Fail-closed disposition** (mirrors ECC's `orch-review` Workflow verify stage):
   - `isReal: true`, or `isReal: false` with `confidence < 0.8` → **stays at its tier.** An unconfident refutation doesn't override the original reviewer.
   - `isReal: false` with `confidence >= 0.8` → **demote one tier** (Critical → Important, Important → Minor) and tag `[verifier-refuted, confidence: 0.NN]` in the presented finding (Phase 6) — visible to the user, not silently dropped.
   - Verifier errors, times out, or returns an unparseable verdict → **stays at its tier.** Same principle as Phase 4 step 4: a missing response is not evidence the finding is wrong.
   - When there are zero Critical/Important findings, this step has nothing to verify — hand off to **step 3.6**, which runs the symmetric guard for that case (a shared blind spot produces *no* finding, and step 3.5 only checks findings that already exist).

   This roughly doubles agent dispatches on a review with several Critical/Important findings (see Integration Notes — Token budget). That cost buys the one thing SCRUTINIZE-4 structurally cannot: a verdict from someone other than the finder.
3.6. **Zero-findings adversarial re-hunt — the blind-spot guard.** Step 3.5 defends against *false positives* (findings that shouldn't survive) and does nothing when the reviewers returned zero Critical/Important findings. But zero findings is exactly the shared-blind-spot case the verifier-separation principle warns about: the maker and same-distribution reviewers can miss the *same* defect and surface no finding at all — a false *negative*, which no amount of refuting-existing-findings can catch. When **zero Critical/Important findings remain after step 3.5's dispositions** — either none were raised, or every one was refuted down to Minor (the trigger is the *final* state, not what step 3 first produced; a review that demoted its only real finding to Minor is exactly as blind-to-the-rest as one that found nothing) — AND the diff is **non-trivial** (≥2 files changed or ≥1 test file touched — the same threshold as Phase 6's proof check), dispatch **one** fresh `general-purpose` agent framed as an **adversarial hunt, not a re-review**: instruct it to *assume a defect exists in the pinned range (`$BASE_SHA..$HEAD_SHA`) and go find it*. Re-reviewing with the same lens just reproduces the zero; changing the posture from "check this" to "there is a bug here — locate it" is what gives a shared blind spot a chance to surface. The hunter returns structured findings (possibly none).
   - **Any Critical/Important finding it raises is verified before it counts.** A hunter told "assume a bug exists" is primed to manufacture a weak one — the exact false positive step 3.5 exists to kill — so apply step 3.5's fail-closed refutation (a *fresh* refuter, same disposition) to each hunter finding once, then tier it. The re-hunt itself runs **once**: a hunter finding never triggers another step 3.6, so the pass always terminates.
   - **Returns nothing** → the zero-findings clean pass stands, now backed by an independent adversarial pass. Record that the re-hunt ran (Phase 6 surfaces it).
   - **Skip** on a trivial diff (a single non-test file) — Rule 2, not worth the dispatch — and whenever any Critical/Important finding *survives* step 3.5 (there's already a real finding to act on; step 3.5 owns that path).
   - Hunter errors, times out, or returns unparseable output → treat as **re-hunt-not-run**, not as a clean result (Phase 4 step 4's principle: a missing response is not evidence the code is clean). Surface it so the clean verdict isn't overstated.
4. **Zero findings is a valid clean pass — a missing report is not, and on a non-trivial diff it must clear step 3.6 first.** `agents/code-reviewer.md` explicitly sanctions a bare zero-findings APPROVE ("do not withhold approval to appear rigorous") — don't demand narration a clean pass doesn't need. What actually distinguishes "checked and clean" from "didn't check" is that Phase 4 now hands every agent the exact pinned range (`$BASE_SHA..$HEAD_SHA`): a zero-findings return against a known, scoped diff *is* the clean signal — backed, on a non-trivial diff, by step 3.6's adversarial re-hunt so the clean verdict isn't just the reviewers' shared blind spot restated. The failure mode this guards against is an agent that never returns at all — that's `dispatch_failures` from Phase 4 step 4, not a clean tier. Surface to the user which agents returned clean, which returned findings, and (if any) which are in `dispatch_failures` — the latter blocks a clean overall verdict regardless of what the other agents found.
5. **Apply ledger-driven tightening (if eligible).** Read `policy.md` § Threshold and the rolling 10-session aggregation. If any Q is eligible (≥50% rejection rate, ≥5 sessions), apply the *tightened* check from the policy table for that Q *this session only*. Surface a note: `Q3 tightened for this session (67% rejection over 10 sessions — was 45%)`. The user can override by saying "skip the policy" — the default SCRUTINIZE-4 check is then used and the ledger records `policy_skipped: true`.
6. **Write the ledger entry.** Sibling of `rejected.md`, in the same `.scratch/review-pr-<UTC-timestamp>/` dir. See `ledger.md` for the schema. Per-Q counters (Rejected / Survived / %), agents dispatched, scope identifier, and `policy_skipped: true` if applicable. **Prune first** — count existing `ledger.md` files, FIFO-remove oldest until count ≤ 199, then write the new entry. This keeps the rolling window bounded per `ledger.md` § Retention.
7. Surface a tier-grouped finding table to the orchestrator (you), not yet to user — Phase 6 handles user presentation.

**Named models** (cc-thinking-skills): the SCRUTINIZE-4 falsifiable checks + multi-agent overlap (don't blend, surface conflicts) are *red-team* (argue against the finding) + *steel-manning* (synthesize the strongest version of the reviewer's concern before deciding to reject); tier assignment by "worst that could happen" is *pre-mortem* (catastrophic-failure branch first, detection, rollback). Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.

---

## Phase 6: Present + User Decision

**Goal**: Show tier-grouped findings, then branch on the review target (set in Phase 1): **own current branch** → fix decision (fixes land in the working tree); **PR by number** → the submit decision. For a reviewer, choosing how to submit the review *is* acting on the findings — there is no "fix later", and in-place fixes in the throwaway worktree are discarded at Phase 7 cleanup unless pushed. This is the **single submit gate**; Phase 7 executes the choice, it does not re-ask.

**Actions**:
1. **If `JIRA_KEY` was set (Phase 1.5 ran), present the ticket-quality report first, as its own section before the code findings — never blended into the Critical/Important/Minor tiers below** (same "don't blend across agents" principle as Phase 5 step 1; this is a report on the *ticket*, the tiers below are about the *code*):

   ```markdown
   ## Requirement Analysis — TP-871 (verdict: <verdict>)
   - Business trace: <business_trace, or "not stated — flagged as gap">
   - Ambiguities: <count> — <one line each, or "none">
   - Bundled requirements: <count> — <one line each, or "none">
   - Open questions: <count> — <one line each, or "none">
   ```

   If `JIRA_FETCH_FAILED`, show `## Requirement Analysis — <key> — fetch failed, cross-check skipped` instead and continue with the ordinary code review. **Skip this sub-step entirely when `JIRA_KEY` is unset** — go straight to presenting findings below.

   **Terminal-only — never part of the posted review body.** This section critiques the *ticket* (ambiguities, open questions, bundling); posting a critique of someone else's ticket onto their PR is out of scope for a code review, and this repo is public, so ticket content (names, internal detail) landing in a public GitHub comment is a real consequence, not a hypothetical. Phase 7's review-body construction starts from the code findings below only — this section never feeds it, on either review target.

   Then present code findings in this format:

   ```markdown
   # PR Review Summary

   ## Critical (X found) — must fix before merge
   - [agent-name]: Issue description [file:line]

   ## Important (X found) — should fix before merge
   - [agent-name]: Issue description [file:line]

   ## Minor (X found) — nice to have
   - [agent-name]: Suggestion [file:line]
   ```

   A finding demoted by Phase 5 step 3.5's verifier carries its tag into whichever tier it landed in: `- [code-reviewer] [verifier-refuted, confidence: 0.85]: Issue description [file:line]` — still visible, just at a lower tier, never silently dropped.

   For tiers with zero findings, list as `Critical: 0 ✅` (explicit green light — agents are issues-only by frontmatter, so empty tier = clean signal, not "we forgot to check"). **Carry step 3.6's provenance onto the green light so the user stamps the code, not the summary** — a bare `Critical: 0 ✅` is exactly the rubber-stamp the verifier-separation principle warns about. Append the re-hunt outcome: `Critical: 0 ✅ · adversarial re-hunt ran clean` (non-trivial diff, hunter found nothing), `Critical: 0 ✅ · re-hunt skipped — trivial diff` (single non-test file), or `Critical: 0 — re-hunt did not return, verdict incomplete` (hunter errored/timed out; do not print an all-clean verdict). **If Phase 4 recorded any `dispatch_failures`, list them first and do not print an all-clean verdict** — `Dispatch: security-reviewer did not return — verdict incomplete, do not treat as clean` — a non-returning agent blocks the green light regardless of what the other agents found.

   After the tier table, surface a **1-line ledger trend** (read `ledger.md` § Aggregation — rolling 10 sessions, computed by the awk helper in `policy.md`):
   ```markdown
   **Trend (last 10 sessions)**: Q1: 12% (was 8%) — stable · Q2: 18% (was 22%) — improving · Q3: 67% (was 45%) — WORSENING · Q4: 8% (was 6%) — stable
   ```
   A `WORSENING` flag means the policy is *eligible* to tighten the Q this session (see Phase 5 step 5). The user already saw the tightening note in Phase 5; the trend line here is the *delta* since the last session. If fewer than 5 sessions of history exist, surface `insufficient data` instead of percentages.

   **Proof-verification check** (own-branch flow only — Rule 4, define done, loop until verified): a PR-by-number review runs in a throwaway worktree with no `.scratch/` of its own, so this check does not apply there. On your own branch, look for `.scratch/<slug>/proofs/`. If absent and the task is non-trivial (≥2 files changed or ≥1 test file touched), flag as **[verification-gap] must-fix** — independent proof is required before merge. If present, verify at least one artifact is non-empty (test output, type-check output, or adversarial review). Surface: `Proof: 2 artifacts (test + typecheck) ✅` or `Proof: missing — must-fix`.

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
     - Review body (the tier table + trend + proof-check from step 1 — **not** the Requirement Analysis section, which is terminal-only per step 1's note and never posted)
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
   STATE_DIR="${REVIEW_PR_STATE_DIR:-$HOME/.claude/state}"
   mkdir -p "$STATE_DIR"
   # DESTINATION — $STATE_DIR is OUTSIDE the throwaway worktree ($WT from Phase 2).
   # Write the state file HERE, not to .scratch/ — .scratch/ is a relative path that
   # resolves INSIDE $WT (rejected.md/ledger.md live there and are intentionally
   # ephemeral), so anything written to .scratch/ is deleted in step 4's worktree
   # cleanup. The state file is different: /ship-merge reads it AFTER the worktree
   # is gone, so it MUST survive cleanup. (Reported in production: PR #2619's
   # review-pr-2619.json was written to $WT/.scratch/ and lost with the worktree,
   # so the merge gate read "no review ran." The assertion after the write below
   # exists to make that failure loud instead of silent.)
   # REHUNT_STATUS (Phase 5 step 3.6): "clean" (ran, nothing) | "skipped-trivial" | "incomplete"
   # (required but hunter errored/timed out) | "n/a" (findings existed → 3.5 path, no re-hunt).
   # An incomplete re-hunt or ANY dispatch failure means the review never certified zero criticals.
   # It must NOT reach /ship-merge as clean — otherwise the machine gate reads critical_count:0 as a
   # clean pass, the exact rubber-stamp the human was told was "verdict incomplete." Force clean:false.
   REHUNT="${REHUNT_STATUS:-n/a}"
   if [ "$REHUNT" = "incomplete" ] || [ -n "${DISPATCH_FAILURES:-}" ]; then
     CLEAN=false
   else
     CLEAN=$([ "${CRITICAL_COUNT:-0}" -eq 0 ] && echo "true" || echo "false")
   fi
   REVIEW_MODE=$([ -n "${WT:-}" ] && echo "pr-by-number" || echo "own-branch")
   # PR-by-number reviews are keyed per PR (recovered from $WT="<tmp>/review-pr-<#>",
   # no new variable needed) — a single shared file would let a second PR's review
   # clobber the first's before /ship-merge reads it (reported in production: #357
   # overwritten by #358 from two reviews run close together). Own-branch reviews
   # have only one active branch per working tree, so the shared file stays fine there.
   if [ -n "${WT:-}" ]; then
     STATE_FILE="$STATE_DIR/review-pr-${WT##*-}.json"
   else
     STATE_FILE="$STATE_DIR/review-last.json"
   fi
   printf '{"clean":%s,"critical_count":%s,"rehunt":"%s","last_sha":"%s","branch":"%s","review_mode":"%s","ts":"%s"}\n' \
     "$CLEAN" "${CRITICAL_COUNT:-0}" "$REHUNT" "$HEAD_SHA" \
     "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')" \
     "$REVIEW_MODE" \
     "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     > "$STATE_FILE"
   # Post-write assertion — the state file MUST land OUTSIDE $WT so step 4's
   # `git worktree remove "$WT" --force` can't delete it. If this exits non-zero,
   # the write went to the wrong place (a prior run wrote to $WT/.scratch/ and
   # lost the file to cleanup) — fix the path and re-run the block BEFORE step 4.
   if [ -n "${WT:-}" ]; then
     STATE_FILE_DIR=$(cd -- "$(dirname -- "$STATE_FILE")" && pwd -P)
     WT_REAL=$(cd -- "$WT" && pwd -P)
     case "$STATE_FILE_DIR" in
       "$WT_REAL"|"$WT_REAL"/*) echo "ERROR: state file $STATE_FILE resolves INSIDE $WT — it will be deleted by step 4's cleanup. Rewrite it to \$STATE_DIR (outside the worktree) and re-run this block before proceeding." >&2; exit 1 ;;
     esac
   fi
   test -s "$STATE_FILE" || { echo "ERROR: state file $STATE_FILE is missing/empty after write" >&2; exit 1; }
   ```
   `CRITICAL_COUNT` = number of Critical findings from Phase 5. `rehunt` records step 3.6's outcome (`clean` / `skipped-trivial` / `incomplete` / `n/a`) so the downstream gate can tell a certified-clean review from one whose blind-spot hunt never returned — an `incomplete` re-hunt (or any `dispatch_failures`) writes `clean:false` even at `critical_count:0`, because an unfinished review has not certified zero criticals. Always write this file; it is the machine-readable input to `/ship-merge`'s Rule-14-scored review gate. A reviewer-flow run on a PR by number still writes it (using the PR's HEAD SHA) so the author can see the verdict — to `review-pr-<#>.json`, not the shared `review-last.json`. `review_mode` records provenance: `pr-by-number` means Phase 2 ran the review in an isolated worktree (severity tiering wasn't done by a session that could be the diff's own author); `own-branch` means an author-flow self-review. Phase 5 step 3.5 now runs an independent verifier per Critical/Important finding regardless of `review_mode` — but that verifier is still dispatched and its verdict interpreted by the same session that may have authored the diff, so `own-branch` still doesn't fully close the self-review gap (see `/ship-merge` Phase 1 step 6 — this still gates same-session self-tiering on sensitive diffs).
2. Summarize:
   - PR # and URL (if applicable)
   - Review window: `BASE_SHA..HEAD_SHA`
   - Jira ticket + verdict, if `JIRA_KEY` was set (e.g. "TP-871: ready-with-assumptions" or "TP-871: fetch failed, cross-check skipped")
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
   - **Review body**: The Phase 6 summary's tier table + trend + proof-check (top-level overview) — **excludes** the Requirement Analysis section (ticket ambiguities/open questions). That section critiques the ticket, not the diff, and is terminal-only (Phase 6 step 1) — it never goes into a posted GitHub body on either review target.
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

- **Token budget**: Each agent review fits 4K task / 30K session budget. Parallel mode (Phase 4 default) is fastest; sequential is available for interactive sessions that need lower cognitive load. Phase 5 step 3.5's verifier dispatches are additional — one fresh agent per unique Critical/Important finding, so a review with several such findings roughly doubles total dispatches for that session. Phase 5 step 3.6 fires only on the zero-surviving-findings path with a non-trivial diff — one hunter dispatch, plus one 3.5-style refuter for each Critical/Important finding the hunter raises (usually zero). So the zero-findings path costs 1 + N dispatches where N is small; the several-findings path costs 3.5's ~one-per-finding. They're near-exclusive by trigger (3.6 only when nothing survived 3.5), so a single review never pays both at full volume. Phase 1.5 (opt-in, only when `JIRA_KEY` is detected) adds one `jira-acli:acli` fetch + one `requirement-analyst` dispatch, flat cost regardless of diff size — negligible next to the per-finding verifier cost above.
- **Agent teams**: Not recommended for PR review — latency too high for a task that needs quick iteration.
- **Hooks active**: `hooks/gates/verifier-protect.sh` asks for approval on edits to the gate/audit verifier surfaces during the session; it does not cover CLAUDE.md/METHODOLOGY.md directly. There is no dedicated secret-scanning hook today.
- **GH CLI**: Use `gh pr view` to check PR state before launching review. `review-pr` reviews code, not CI status — plenty of repos have no CI wired up at all, so this skill never checks or gates on `gh pr checks` (that belongs to `/ship-merge`'s own required-checks gate, which only runs against repos that actually have branch protection configured). Reviewing by number fetches `pull/<#>/head` into a throwaway `git worktree` (removed in Phase 7). Submitting the review uses `gh api repos/{owner}/{repo}/pulls/<n>/reviews` with a JSON payload containing `commit_id`, `event`, `body`, and `comments[]` — posting findings as individual line-level comments. "Summary only" fallback uses `gh pr review --comment/--request-changes/--approve`. Both paths are gated on user confirmation (requires `Bash(gh api ...)` allow in settings.json).
- **Review routing reference**: Code that touches auth/secrets → `kbg:security-auditor` for full audit. General code → code-reviewer, plus `typescript-reviewer` / `python-reviewer` / `flutter-reviewer` when that language dominates the changed files (Phase 3). Tests, comments, types, db → code-reviewer with its behavioral test-coverage / comment-accuracy / type-design / DB-query-safety lens. A detected Jira ticket → `requirement-analyst` (Phase 1.5, ticket-quality report) + code-reviewer's requirement-coverage lens (Phase 3/4, diff-vs-requirements). Error handling → silent-failure-hunter. Polish → native `/simplify` with clarity-only scope (post-review opt-in, **not** part of kbg:review-pr).
- **Severity tier rubric** (Phase 5): Critical / Important / Minor are canonical across `/ship`, `/fix-bug`, and `kbg:review-pr`.
- **SCRUTINIZE-4 rubric** (Phase 5): Challenge intent / Trace call graph / Verify execution branches / Evidence requirement. Named + tabular (4 falsifiable checks) so the gate is a yes/no per finding, not prose that gets skipped. Dropped findings go to `.scratch/review-pr-<UTC-timestamp>/rejected.md` (ephemeral audit log, not an `issue.md`) with a per-question tally surfaced to the user.
- **Rejection-rate ledger** (Phase 5+6): per-session per-Q counters written to `ledger.md` (sibling of `rejected.md`). Rolling 10-session window drives a 1-line trend + tightening eligibility. Spec: `ledger.md`. Policy (threshold, tightening action, hard caps, reversibility, awk aggregation helper): `policy.md`. Cap: 200 sessions FIFO, 1 tightening per Q per 90 days, 1 tightening per session max.
