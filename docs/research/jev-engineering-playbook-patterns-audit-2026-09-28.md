# "Jev Engineering" playbook — pattern adoption audit (2026-09-28)

**Date:** 2026-09-28
**Source:** "Jev Engineering: Stop Using LLMs for Every Decision" by @0xwhrrari (published
2026-09-21), from `~/llm-wiki/raw/Jev Engineering Stop Using LLMs for Every Decision.md`. Fetched
by the operator as a local file, saved verbatim to scratchpad, read directly (no WebFetch).
**Verdict:** Not adopted. This audit is deliberately narrow — adopting TypeSafe's Jev itself is
settled (5 prior rounds, most recently `jev-as-a-judge-cascade-audit-2026-09-28.md`, 5.05/10 FAIL);
this evaluates only the article's general engineering *patterns* (decision contracts, confidence-
routing, shadow-mode rollout, receipt logging) for mh's own judge mechanisms. The two cheap, real
candidates (a `contract_version` field, a `mh_version` field on the gate journal) are genuine but
marginal at mh's current judge-call volume (a handful of dispatches per week). **This round had a
second-order correction worth recording as its own lesson**: the adversarial attacker's strongest-
sounding finding — that `deep-audit`/`idea-audit`'s `check-verdict.py` "trusts the checker's/
attacker's own self-reported `pass`," a live instance of the article's worst-named failure mode —
was itself a category error, caught only in a post-Phase-3 advisor review, not by the attacker
pass. `check-verdict.py` is correctly scoped as a schema-shape validator only; the actual pass/fail
authority sits one layer up, at the skill level: `skills/review/deep-audit/SKILL.md:195-196`
states the checker's `pass` is "distinct from this skill's Final Verdict," and
`skills/workflow/idea-audit/SKILL.md:392` names this exact caveat by policy ("The attacker is
advisory evidence, not a verdict the user can't question"). Pattern 8 holds after all — see the
corrected table below.
**Score:** 5.65/10 — **FAIL** (threshold 6/10, fatal-weakness floor 40% of each criterion's own
max — not tripped; confidence high, 4 confirmed corrections to the two analysts' reports plus 1
further correction to the attacker's own strongest finding, all independently re-verified here
against the live repo, not taken on any single source's word).

Every claim below about the source's internals is what it describes as of this read, not a
verified fact about TypeSafe/Jev's actual product.

## Method

2 isolated `general-purpose` analysts (Agent A: claims + repo-state checks; Agent B: fit/pattern
overlap), each fresh-context, neither seeing the other's output, both explicitly scoped away from
re-litigating the settled Jev-as-vendor question. 1 adversarial attacker (`codex exec`,
`gpt-6-sol`/medium, `--sandbox read-only`) independently re-checked both reports; exit 0,
schema-valid, citations passed `check-citations.py`. The attacker returned 5 findings; an advisor
review after Phase 3 caught that the attacker's own strongest finding (correction #3 below) was
itself a category error, missing a skill-level architecture layer both analysts' original reports
had actually gotten right implicitly. **Net: 4 confirmed corrections stand, 1 attacker finding
is itself corrected** — every one independently re-verified directly against the live repo below,
not taken on any single source's word, including the attacker's.

## Attacker corrections (independently re-verified; #3 is itself corrected below, not confirmed)

1. **"Batching absent elsewhere" was wrong.** Agent B claimed batched independent typed
   sub-questions exist only in `compliance-audit`. Re-checked: `skills/review/deep-audit/references/checker-output-schema.json:5-9,30-33,50-57`
   requires `pass` (boolean-or-null), `checked[]`, `scope_ok`, and `unexpected_files[]` — four
   independently-typed answers in one dispatch, matching Agent A's own (correct) version of this
   finding. Batching is present in **both** deep-audit and compliance-audit.
2. **The "already bit once" case for schema/contract versioning is weaker than presented.** Agent
   B cited `check-verdict-mirrored-regex-drift-2026-09-20`'s `CITATION_RE` incident as proof that
   missing contract versions already caused a failure. Re-checked directly: `rg -n 'CITATION_RE'
   skills/workflow/idea-audit/scripts/check-citations.py skills/review/compliance-audit/scripts/check-verdict.py`
   shows the two copies now **match** (already fixed, per that memory file's own text). More
   importantly: that incident is about mirrored *validation-script regex* drift, not the output
   *schema's* version — a `contract_version` field in the JSON schema would not have caught or
   prevented it. The two gaps are related in spirit (no shared version to track drift) but not the
   same remedy; citing one as evidence for the other overstates the case.
3. **The attacker's own claim that pattern 8 is only partially true was checked further, in a
   post-Phase-3 advisor review, and does not hold — this is a correction to the attacker, not by
   it.** The attacker (and this audit's own first draft) read `skills/review/deep-audit/scripts/check-verdict.py:127-134,196-199`
   and `skills/workflow/idea-audit/scripts/check-verdict.py:102-105,136-140` returning the
   checker's/attacker's own self-reported `pass` boolean as a live instance of "the policy lives
   inside the classifier." Re-checked one layer up, at the skill level: `skills/review/deep-audit/SKILL.md:195-196`
   states explicitly, "The checker returns `{pass, findings[], checked[], scope_ok,
   unexpected_files[]}` — its own return value, **distinct from this skill's Final Verdict**";
   `skills/workflow/idea-audit/SKILL.md:392` states, "The attacker is advisory evidence, **not a
   verdict the user can't question**." `check-verdict.py` is correctly scoped as a schema-shape
   validator only (it neither claims nor needs to compute policy) — the actual enforcement is one
   layer up, in each skill's own Phase 3 reconciliation, which explicitly treats the checker's/
   attacker's `pass` as one advisory input, never the final word. Pattern 8 holds for all three
   mechanisms, not just compliance-audit.
4. **"Distribution-shaped" receipt evidence was wrong.** Agent A cited `weighted-score.py`'s
   `sensitivity.totalRange` as evidence mh already has something distribution-like in its receipts.
   Re-checked: `scripts/_lib/weighted-score.py:13-17`'s `totalRange` is the min/max *total* under a
   **weight perturbation**, not a probability distribution over answer options the way the
   article's `Choice`/`Score`/`Noul` primitives return. mh's judges are categorical
   (pass/verdict-enum), never probabilistic — this receipt-logging gap is real and unqualified,
   not partially closed by an unrelated sensitivity feature.
5. **The proposed `_journal.py` receipt expansion is only "near-zero-risk" for the version field,
   not for state-reference/route-context fields.** `hooks/gates/_journal.py:12`'s `journal()`
   function signature accepts only `gate_id, tool_name, decision, session_id` — adding a state
   reference or route context means changing the function's own API and updating every caller
   (`hooks/gates/secret-scan.py:105` and others) to supply a value they don't currently compute,
   not just appending one more constant field the way `mh_version` (read once, globally) would be.

## Pattern-by-pattern (corrected)

Legend: `MATCH` = confirmed present in this repo · `PARTIAL` = partially present · `GAP` = absent
· `N-A` = not applicable.

| # | Pattern | This repo's posture (corrected) | Verdict |
|---|---|---|---|
| 1 | Three-layer stack (generate / decide / enforce) | Present in different vocabulary: `docs/reference/operating-model.md`'s maker≠checker split, METHODOLOGY.md Rule 13's fresh-context validator | MATCH |
| 2 | Decision contracts (versioned independently of code, state fields, escalation, fallback) | Escalation/fallback present (`pass: null`, `NEEDS-DECISION` exit 2, `UNVERIFIABLE`). Version field absent from all 3 schemas (confirmed: `rg -n 'contract_version\|decision_contract\|schema_version\|\$id\|version'` across all three → no matches) — but the regex-drift incident doesn't demonstrate this specific gap already caused a failure (correction #2 above) | PARTIAL |
| 3 | Batched independent typed sub-questions against one snapshot | Present in **both** deep-audit and compliance-audit (correction #1), homogeneously typed (not Jev's heterogeneous Choice/Score/Noul mix); compliance-audit pins a state SHA, deep-audit/idea-audit explicitly don't (by documented design) | MATCH |
| 4 | Confidence+consequence joint routing (3 zones) | Consequence-tiering exists (Rule 1 triad, fail-open/fail-closed split); confidence-ranked-last doctrine exists (`operating-model.md:85-96`); the two are never combined into one routing function, and every existing fallback trigger (`codex-integration-map.md:19-21`) is availability-only, confirmed directly, not confidence-gated | GAP |
| 5 | Shadow-mode rollout before granting a new judge authority | Absent — repo-wide `rg -n -i 'shadow'` across every file type returns only module/alias-shadowing hits and one unrelated "shadow traffic" mention in an unrelated doc; one weak seed (`secret-scan.py`'s `allow-suppressed`, a recorded-but-unenforced verdict for one gate only) | GAP |
| 6 | Full-distribution receipt logging | Gate layer (`_journal.py`): only `ts, id, tool_name, decision, session_id` — no version, state ref, threshold, or distribution. mh's judges are categorical, so "full probability distribution" specifically has no analog to log yet (correction #4 removes the partial credit Agent A gave this) | GAP |
| 7 | Option menu rebuilt from live state | Mixed: ideate's `frames.md` is a fixed static pool (closer to the article's anti-pattern); model-selection doctrine requires re-verifying against the live catalog before dispatch (closer to the article's intent, but human/agent-executed policy, not an automatic rebuild function) | PARTIAL |
| 8 | "Policy lives inside the classifier" — guarded against | True for all three mechanisms, not just compliance-audit: `check-verdict.py` is a schema-shape validator only, never the policy authority; each skill's own Phase 3 reconciliation treats the checker's/attacker's `pass` as advisory (`deep-audit/SKILL.md:195-196`, `idea-audit/SKILL.md:392`) — the attacker's claim that this was only partial did not survive a further check (correction #3, self-corrected) | MATCH |

## Shipped

Nothing — this is a read-only research pass.

## Deliberately not shipped

- **A `contract_version`-style field on the 3 judge-output schemas** — weaker-motivated than first
  presented (correction #2: doesn't address the actual mirrored-regex-drift incident it was cited
  against), cheap and harmless if built, but no concrete trigger makes it worth doing now over
  other backlog. Labeled: **deferred**.
- **`mh_version` on `hooks/gates/_journal.py`'s logged row** — genuinely cheap, real precedent
  (`hooks/stop/cost-tracker.sh:321`), tiny blast radius, `skills/meta/gate-report/scripts/gate-report.py`
  already tolerates unknown fields via `.get()`. Labeled: **deferred** — real and buildable, just
  not urgent enough to justify a session on its own; bundle with the next `gate-report`/`_journal.py`
  touch rather than a standalone commit.
- **State-reference/route-context fields on the same journal** — correction #5: not the same
  cheap shape as the version field; would need a new `journal()` parameter and caller updates
  repo-wide. Labeled: **declined on evidence** (the "near-zero-risk" case for it doesn't hold).
- **A systematic shadow-mode rollout process for new judges/gates** — low judge-call volume (a
  handful of dispatches per week, per `~/.local/share/kbg/metrics/skill-usage.jsonl`'s live counts
  and the modeled cost in the prior Jev-cascade audit, `jev-as-a-judge-cascade-audit-2026-09-28.md`)
  is the same volume disqualifier that audit used for a comparable pattern (accuracy-vs-confidence
  plotting needs bulk data mh doesn't generate) — a new *process step* competing with how rarely mh
  adds a new gate risks becoming ignored ritual rather than a working control. Labeled: **declined
  on evidence**.
- **A confidence+consequence joint router** — mh's own operating doctrine (`operating-model.md:85-96`)
  ranks model confidence last among evidence inputs, but (per this session's own JEV-cascade audit
  correction) that's a weighting choice, not an outright ban on using confidence as one signal
  among several — so this isn't dead-on-arrival doctrine, just weak fit: no existing mh mechanism
  has both a confidence signal and a consequence signal to jointly route on today. Labeled:
  **declined on evidence**.

## Process lesson (not an open question — settled by this round's own re-check)

- **The attacker's strongest-sounding finding (pattern 8) was a category error, and this audit's
  own first draft repeated it before an advisor review caught it.** `check-verdict.py`'s job is
  schema-shape validation; the policy authority lives at the skill level (Phase 3 reconciliation),
  which both `deep-audit/SKILL.md` and `idea-audit/SKILL.md` already document explicitly as
  treating the checker's/attacker's `pass` as advisory, not final. No further action needed here —
  this was a correction, not a discovered gap. Recorded for the general lesson: a citation one
  layer removed from where a mechanism's real authority sits (the validator script, not the skill
  that calls it) can look like a finding and not be one — check the calling layer, not just the
  callee, before treating "the code returns the model's own value" as evidence the model's value
  is trusted as final.

## Decision score (METHODOLOGY Rule 14)

Scale: 0–10 per criterion, matching this session's established convention. Weights sum to 10.

| Criterion | Weight | Score | Reason |
|---|---|---|---|
| Primary-source fidelity | 4.5 | 6/10 | Largest weight, same rationale as prior rounds. Score reflects a real error density: 4 confirmed corrections stand (batching-absent-elsewhere was wrong; the versioning/regex-drift linkage was overstated; distribution-shaped receipt evidence was wrong; the journal-change blast-radius was overstated) — but the attacker's 5th and strongest-sounding finding (pattern 8) did not itself survive a further check, and this round's own first draft repeated that error before catching it. A 8/10 would mean every verdict held up clean through one adversarial pass with no second-order correction needed; this round needed two passes to reach ground truth. |
| Fit (does mh have this need) | 3.0 | 4/10 | Second-largest. Two cheap real candidates survive (schema versioning weaker-motivated but harmless; `mh_version` on the journal, genuinely low-risk) — real but marginal given mh's tiny judge-call volume. The one candidate that would have carried this axis higher — a live gap in maker≠checker enforcement — evaporated on closer check; nothing in this round rises above small, marginal housekeeping. |
| Blast radius / reversibility | 2.5 | 7/10 | The two real candidates that survive (schema versioning, `mh_version` field) are both small, additive, and reversible if built later. Consistent with this session's other Jev-adjacent rounds landing here. |

Weighted sum: `(6/10)*4.5 + (4/10)*3.0 + (7/10)*2.5 = 2.7 + 1.2 + 1.75 = 5.65/10` (via
`scripts/_lib/weighted-score.py`). Pass threshold 6/10, fatal-weakness floor 40% of each
criterion's own max — **no criterion trips it** (lowest is fit at 40% exactly, which is not
`< 40%` and so does not trip). **FAIL** on the weighted total alone, not a floor trip.
`primaryWeightOk: true`. Confidence: high — every correction above (both the 4 that stand and the
1 that itself needed correcting) was independently re-verified directly against the live repo in
this reconciliation, not taken on any single source's word, including the attacker's own.

## Open questions

- **The deep-audit/idea-audit self-reported-`pass`-trust gap** (see above) — revisit as its own
  targeted review, not from re-reading this article.
- **Does mh's judge-call volume ever reach a scale where shadow-mode rollout or a confidence+
  consequence router becomes worth building?** — Revisit only if `~/.local/share/kbg/metrics/skill-usage.jsonl`
  shows deep-audit/idea-audit/compliance-audit dispatches sustained well above "a handful per
  week" over a rolling 30-day window — an observable count, not a feeling that usage grew.

<!-- Reserved: a later pass appends a dated correction here, never rewrites the sections above.
**Correction (date, mechanism):** ... -->
