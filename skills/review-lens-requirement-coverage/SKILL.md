---
name: review-lens-requirement-coverage
description: Requirement-coverage checklist for code-reviewer's ticket-gap dispatch. Use when review-pr passes extracted requirements. Don't use for self-invoked or standalone review.
metadata:
  origin: kbg
---

# Requirement-Coverage Lens

Loaded by `code-reviewer` only when `kbg:review-pr` dispatches it with a ticket's extracted
requirements (from `requirement-analyst`) in the prompt — never self-invoked, never assumed
present.

- For each `functional_requirements` / `acceptance_criteria` entry: does the
  pinned diff (`$BASE_SHA..$HEAD_SHA`) contain a change that satisfies it?
- **"Not in the diff" is not the same as "not implemented."** Before flagging
  a requirement as unaddressed, `Grep`/`Read` the surrounding codebase (not
  just the diff) to check it isn't already satisfied outside the pinned
  range — pre-existing code, a sibling PR, a shared utility. Flag only if
  it's genuinely absent everywhere reachable, not just absent from the diff.
  Skipping this check manufactures confident false positives that drive a
  bogus `REQUEST_CHANGES`.
- Tier by what's missing: an explicit, stated acceptance criterion with no
  trace anywhere → **Critical** (the PR doesn't do what the ticket asked).
  An implied non-functional requirement (rate limit, audit log, i18n) with
  no trace → **Important**. A `transition_requirement` (migration/rollback/
  flag) with no trace → **Important** if the diff's change size plausibly
  needs one, otherwise skip — don't manufacture a transition-plan gap on a
  change too small to need one. A single-line constant or config-value
  change on an already-existing branch (no new branch, endpoint, schema, or
  migration added by the diff) is the paradigm skip case — and the
  requirement being named in the ticket doesn't change that: every
  `transition_requirement` reaching this lens is by definition ticket-named
  (that's what `requirement-analyst` extracted it as), so "the ticket says
  so" can't be the test or this clause never fires. These tiers render on
  `agents/code-reviewer.md`'s CRITICAL/HIGH/MEDIUM/LOW scale (its Review Output
  Format section) as **Critical → CRITICAL** and **Important → HIGH** — a
  missing stated acceptance criterion blocks the same way a Security CRITICAL
  does; it isn't capped at HIGH/Warning.
- Every coverage finding still needs `file:line` evidence where a match
  *does* exist (to explain why it's a partial match, not silence) or an
  explicit "checked \<paths\> via grep, no match" when it's a true absence —
  same evidence bar as every other finding (`agents/code-reviewer.md`'s
  Confidence-Based Filtering section). A finding with no trace of having
  checked beyond the diff doesn't meet the bar.
- This lens finds gaps in the *diff*, not the *ticket*. Ambiguous or
  untestable requirements are `requirement-analyst`'s job (already run
  before you were dispatched) — don't re-litigate ticket quality here, only
  whether the diff satisfies what was extracted.

Confirm every `functional_requirements`/`acceptance_criteria` entry against the diff
before verdict — done when each one is tiered, matched, or filed as a coverage gap.
