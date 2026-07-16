# Response conciseness/verbosity research (2026-07-16)

## Question

User repeatedly (across many sessions, not project-specific) has to tell Claude Code
"สรุปให้เข้าใจง่ายๆ" (summarize in plain language). `output-styles/staff-eng.md` already has
plain-language rules (line 23: familiar words; line 64: calibrate to stakes). Why don't they
reliably land, and what actually works?

## Bottom line

The existing rules are directionally correct but weak against a trained-in tendency, not a
content gap. **Don't add a hard word-count cap** — Anthropic tried exactly that on Claude Code
and it backfired. **Do** add concrete before/after examples to the existing rules — evidence
says directive instructions + worked examples beat either alone, and this repo's own precedent
(`thai-phrasing-compression` memory) already uses this exact mechanism for a structurally
identical problem (natural-language register quality with no mechanical verifier).

## What's confirmed (deep-research workflow, 110 agents, 3-vote adversarial verification)

| Finding | Confidence | Source |
|---|---|---|
| Plain-language quality is mostly structure/findability, not word choice — only ~7% of ISO 24495-1's guidance is about vocabulary | High, 3-0 | ISO 24495-1, iplfederation.org |
| Cognitive load comes from decision-load and structural complexity, not vocabulary difficulty alone | High, 3-0/2-1 | DeStefano & LeFevre (38-study review); Instructional Science |
| RLHF reward models systematically favor longer responses over higher-quality ones (documented reward-hacking) — the dominant driver of RLHF-model verbosity | High, 2-1 corroborated by 4+ papers | Singhal et al. COLM 2024 (arXiv 2310.03716); arXiv 2511.12573, 2505.12843 |
| DPO specifically has an *algorithmic* length-bias source (sequence-level vs token-normalized KL divergence), not just biased data — emerges in the first 10% of training, extrapolates length beyond training data | High, 3-0 | arXiv 2403.19159 (DPO co-author), 2406.10957 (EMNLP 2024) |
| A training-time debiasing fix (FiMi-RM) reduces verbosity without hurting quality — but single-paper, not independently replicated | Medium | arXiv 2505.12843 |

**Refuted during adversarial verification** (do not resurrect): ISO 24495-1 as "the" sole
plain-language standard (overreach); a formal CLT distinction between extraneous/intrinsic load
(didn't hold); length-only reward reproducing "most" of RLHF's gains (too strong); reward-model
retraining being *proven* necessary over prompting (refuted 0-3 — prompting is not proven futile).

## What the pipeline missed, verified directly by fetching primary sources myself

The workflow extracted 113 claims but only verified the top 25 (budget-ranked) — it dropped 3
directly relevant sources into "unverified," including its own flagged "open question" (does
Anthropic have public guidance on this?). Checked all three by hand:

**1. Anthropic already ran this exact experiment on Claude Code, and it backfired.**
On April 16, 2026, Anthropic added a system-prompt instruction: *"keep text between tool calls
to ≤25 words. Keep final responses to ≤100 words unless the task requires more detail."* It
passed weeks of internal testing with no flagged regression. Broader evaluation later found it
caused a **3% performance drop for both Opus 4.6 and 4.7** — Anthropic reverted it in the April 20
release, 4 days after shipping it.
Source: https://www.anthropic.com/engineering/april-23-postmortem

This is the single most important finding for this repo: **a rigid length cap is the obvious
fix and it's the proven-wrong one.** It looks safe in casual testing and only fails under broader
evaluation — exactly the failure mode to avoid repeating here.

**2. Concise-instruction prompting works, with one real caveat.**
Concise Chain-of-Thought (CCoT) cut average response length by 48.70% (GPT-3.5 and GPT-4) with
negligible accuracy impact on most tasks — but on math-heavy reasoning specifically, GPT-3.5 with
CCoT took a 27.69% accuracy hit (GPT-4 was more resilient). Confirmed by direct fetch.
Source: arXiv 2401.05618 (Concise Chain-of-Thought)
Relevance here: matches `staff-eng.md`'s own "calibrate to stakes" principle — brevity is safe
for routine explanation, risky for logic-heavy/high-stakes reasoning. The existing rule is right;
it just isn't reliably triggered.

**3. Directive instructions + worked examples beat either alone, for code verbosity specifically.**
A November 2025 paper on code-verbosity control found instruction-based prompts had large initial
effect with moderate persistence, example-based prompts had modest effect with no persistence, and
**combining both gave the strongest and most stable compression** — without sacrificing functional
accuracy. Confirmed by direct fetch (exact effect-size numbers the extraction agent reported,
d=-7.84 instructions vs d=-2.63 examples, ~56% vs ~20% token reduction, weren't independently
re-confirmed by me — the abstract gives the directional finding but not the exact figures I could
verify firsthand).
Source: arXiv 2511.13972

## Open questions (genuinely unanswered)

- No confirmed source ties a specific mechanism (self-critique pass, format constraints) to
  measured verbosity reduction beyond the three found above.
- No Anthropic documentation on Claude-*specific* (not just Claude-Code-system-prompt) conciseness
  behavior was found beyond the one postmortem.

## Recommendation

1. **Ruled out:** hard word/length caps in any system prompt or output-style rule — direct,
   first-party counter-evidence.
2. **Recommended:** add 1-2 concrete before/after example pairs to `staff-eng.md`'s Voice section
   (line 23 area) showing jargon-heavy vs plain for a *routine, non-decision* response — matching
   the caught pattern already logged in `plain-language-preference-2026-07-16.md` memory (the
   "one-way door / blast radius in a status ack" example). This is evidence-backed as the
   strongest lever (directive + example > either alone) and structurally identical to how
   `thai-phrasing-compression-2026-07-02.md` already handles this same class of problem.
3. Scope decision (repo-local `staff-eng.md` vs also global `CLAUDE.md`) is the user's call —
   the complaint is stated as generic to Claude Code, not scoped to this repo.
