---
name: compliance-audit
description: "Audit a completed implementation against its approved plan via fresh-context verifiers — plan-conformance, not code quality. Use after finishing a multi-phase plan. Don't use for reviewing an unplanned diff (kbg:review-pr) or prod-readiness (kbg:production-audit)."
argument-hint: Optional path to the plan file, PR number, or commit range
disable-model-invocation: true
disable-model-invocation-reason: costly multi-agent fan-out that gates a done-declaration — user decides when the audit runs, not the model
---

# Implementation Compliance Audit

Prove a finished implementation matches the plan that was approved for it —
every planned requirement landed, no unexplained deviation, no regression.
This is a conformance check against a specific prior plan, not a general code
review: quality/security/style lenses belong to `kbg:review-pr` /
`kbg:security-auditor`; production readiness belongs to `kbg:production-audit`.

## Core Principles

- **Maker ≠ checker.** The agent that implemented the plan cannot be the sole
  grader of its own work — that's an LLM judging its own output, circular
  ("two optimists agreeing"). Phase 3 dispatches fresh-context verifiers with
  no memory of the implementation session.
- **Ground truth is the plan's text and the actual diff** — not a summary of
  what you remember doing. Re-derive the checklist from the plan file itself.
- **Falsify, don't rubber-stamp.** Deviations you already know about get
  pre-declared (Phase 2) and then checked against what independent verifiers
  find on their own (Phase 4) — a pre-declared deviation a verifier also
  surfaces independently is confirmed; one only you listed is unverified.
- **Per-item verdict, not a blended score.** Rule 14 says score decisions —
  but compliance is a checklist of booleans (CONFORMS / DEVIATED / MISSING),
  not a graded quality signal. A single "96/100" hides which requirement is
  the unmet 4 points. Report the open count, not a percentage.
- **No MISSING or unjustified DEVIATED survives to "done."**

---

## Phase 1: Locate the Plan + Scope the Audit

**Goal**: Identify what was actually approved, and get sign-off on the audit's scope before spending fan-out budget.

**Actions**:
1. Resolve the source plan: this command runs in the same session that did the implementing — prefer the plan already in this conversation's context, and use `$ARGUMENTS` only to override or disambiguate. **Don't trust the plan file's mtime as a fallback**: plan mode reuses the same file path per session, so a later unrelated plan-mode entry silently overwrites the one you meant to audit — the most-recent file on disk may belong to a different task entirely. If neither conversation context nor `$ARGUMENTS` gives a clear source, stop and ask the user which plan to audit rather than guessing from a file timestamp.
2. Extract every discrete requirement from the plan — numbered findings, phases, explicit "must" statements — into a flat checklist. This list is the audit's ground truth.
3. Identify the diff to audit: commit range, PR, or `git log` since the plan was approved, across **every** repo the plan touched (multi-repo plans list each repo separately — don't audit only the one you remember editing). Pin the exact commit range/SHA here — Phase 3 hands it forward to each verifier so they don't have to re-derive it.
4. Enter Plan Mode (Shift+Tab / `EnterPlanMode`) and present: the requirement checklist, how it partitions into fresh-context verifiers (mirror the plan's own phase/repo boundaries; cap at 5 concurrent per the fan-out cap), and any deviation you're already aware of.
5. **Gate**: user approves scope → Phase 2. User flags a missing requirement or wrong diff range → revise and re-present.

---

## Phase 2: Pre-Declare Known Deviations

**Goal**: Separate "I already know this differs from the plan, here's why" from what the audit must discover independently.

**Actions**:
1. List every point where the implementation diverged from the plan as written — scope narrowed, scope widened, an approach substituted, an extra file touched — with the reason for each.
2. Carry this list forward unopened; Phase 4 is where it gets checked, not asserted.
3. This phase assumes you're the implementer declaring your own known deviations. Auditing someone else's already-completed work with no first-hand deviation knowledge is fine too — this list just starts empty; Phase 4 still catches anything real through the verifiers' independent findings.

---

## Phase 3: Dispatch Fresh-Context Verifiers

**Goal**: Independently re-derive plan-vs-diff conformance — not confirm your own summary of it.

**Actions**:
1. Partition the checklist along the plan's own natural boundaries (per phase, per repo, per finding cluster). Cap at 5 concurrent agents.
2. Each verifier receives **only** its slice of the plan's requirements, plus the exact commit range/SHA pinned in Phase 1 step 3 so it can run `git show` / `git diff` against the right target without re-deriving it — **not** your Phase 2 deviation list, **not** your narrative of what you did.
3. **Adversarial-completeness mandate** for any verifier touching a security/gate/verifier-perimeter surface — treat a requirement as touching one whenever its own text names auth, access control, rate limiting, input validation, secrets, or an abuse/fraud gate; when genuinely unsure, default to applying the mandate rather than hedging (a false positive costs one extra check, a false negative costs a missed finding). Applying it means tracing the diff's actual comparison/validation logic for that surface, not naming a plausible bypass category and stopping — confirmed twice that naming the mandate without tracing the code still misses a real, open bypass (an HMAC check running against a framework-parsed body instead of raw bytes; a clock-skew guard whose comparison silently passes when the claim it depends on is simply absent, not wrong). Not "confirm my new tests are honest" but "enumerate bypass permutations in this family and try to find one still open" — read the actual validation code line by line for this surface, don't recall a category from memory and call it enumerated. An in-family bypass found → flag for remediation in this same audit. An out-of-family gap (new attack class entirely) → log as a known-gap for the user's decision; do not silently widen scope (Rule 2).
4. Each verifier returns one verdict per requirement in its slice: **CONFORMS** / **DEVIATED** (state what changed) / **MISSING**. When an adversarial-completeness finding (step 3) surfaces a bypass, it downgrades the verdict only if the bypass falls within the scenario the requirement's own text names — e.g. a requirement to validate "the incoming signature" that turns out to validate the wrong bytes is still about validating the incoming signature, so DEVIATED is correct. A bypass that exploits a scenario the requirement's text never named at all — e.g. a guard scoped to "exp too far in the future" doesn't cover a token missing `exp` entirely — stays **CONFORMS**, with the bypass logged as an attached note, not folded into the verdict: the requirement is met on its own terms even though a related gap exists nearby. Confirmed once already: without this distinction, a verifier that traces deep enough to find a real bypass has nowhere to put it except downgrading an otherwise-conforming requirement, which hides which items are the actual open ones (see "Per-item verdict, not a blended score" above).
5. **Independent deterministic backstop**: re-run the project's actual validation/test suite fresh — don't trust an in-session "green" claim carried over from the implementation phase.

---

## Phase 4: Reconcile + Remediate

**Goal**: Falsify the pre-declared deviations against independent findings; close any real gap before declaring done.

**Actions**:
1. Compare each verifier's independently-found deviations against Phase 2's pre-declared list. Match on both sides → justified-and-confirmed. Verifier found one you didn't list → an unflagged gap; judge it now, don't wave it through.
2. Any MISSING requirement, or DEVIATED without a justification the user accepts → fix now, then re-run only that verifier over the fix — not the whole audit.
3. Any new in-family bypass an adversarial verifier surfaced → remediate in this same pass with a regression test, same as the finding it's adjacent to.

---

## Phase 5: Report

**Goal**: One table, one honest verdict.

**Actions**:
1. One row per plan requirement: **CONFORMS** / **DEVIATED (justified)** / **MISSING (fixed)**.
2. State N/N conform, list pre-declared deviations judged justified, list any residual gaps closed with their regression tests.
3. No blended percentage for the whole audit — state the actual open-item count (must be 0 before declaring done).
4. **Suggested next step:**
   - All conform, nothing open → done; ship/merge if not already.
   - A residual gap was found and fixed → note it; consider `/post-mortem` if it reveals a systemic pattern rather than a one-off miss.

**Done.**

## Anti-Patterns

- Auditing from memory of "what I think I did" instead of the actual diff.
- Letting the implementing session's own verifiers grade its own work — no fresh context, no audit.
- Reporting compliance as one blended percentage instead of a per-requirement verdict.
- Trusting "gauntlet was green during implementation" without re-running it fresh.
- Declaring done with an open MISSING or an unjustified DEVIATED still on the table.

## Arguments

`$ARGUMENTS`:
- optional path to the plan file (defaults to the most recent plan mode used)
- optional PR number or commit range to scope the diff

## Named Model

Phase 3's fresh-context dispatch is the verifier-separation / maker≠checker
principle — CLAUDE.md's own "unifying crux": an LLM judging its own output is
circular. Phase 4's falsify-don't-rubber-stamp step is the scientific-method
lens: a claim survives by surviving an attempt to disprove it, not by being
asserted twice. Catalog + honesty caveat: read via Bash with
`cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.
