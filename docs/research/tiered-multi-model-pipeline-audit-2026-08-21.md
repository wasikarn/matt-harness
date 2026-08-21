# Tiered multi-model agent pipeline research vs. kbg-harness — audit (2026-08-21)

**Source:** `~/llm-wiki/raw/ai-agents/multi-agent/tiered-multi-model-agent-pipeline-research.md`
(wiki twin: `wiki/ai-agents/multi-agent/src-tiered-multi-model-agent-pipeline-research.md`) — a
deep-research dossier on "tiered multi-model agent pipelines": top-tier plans/dispatches →
mid-tier executes repeatedly → senior-tier reviews with a capped retry budget → senior-tier does
a second bug-hunt/test pass → top-tier does a final independent review. A same-day follow-up
research pass (2 parallel agents) then checked the dossier's own flagged open question — does
adding an extra review tier help, and does panel/vote-based review beat single-reviewer
escalation — and found: [Adversarial Review (arXiv:2608.18167)](https://arxiv.org/html/2608.18167)
— a leaner 2-role reviewer+critic setup beat **MARS**'s heavier 4-role reviewer+meta-reviewer
hierarchy by +5pp on SWE-bench Verified (75.2% vs 72.6%); [TAO
(arXiv:2506.12482)](https://arxiv.org/abs/2506.12482) — a real 3-tier healthcare escalation system
helped, but only as complexity-gated triage, not run unconditionally, and agreement quality
degraded climbing tiers (85.0%→70.1% acceptance); ["LLMs as a Jury"
(arXiv:2607.10139)](https://arxiv.org/abs/2607.10139) — a 4-model panel beat self-consistency
resampling by +26.7pp at 8x lower budget.

**Verdict: mostly already built, two doc gaps closed, one addition declined.** kbg-harness
already implements the sound parts of this pattern — model tiering by role, advisory review
feeding a deterministic gate, and a genuinely correct deterministic panel-vote — without ever
having read this dossier. Two real, narrow documentation gaps existed (no numeric retry cap on
`orchestrate`'s Fixer loop; the panel-vote pattern wasn't cross-referenced as a reusable
alternative) and are closed by this audit. One thing the dossier's pattern names —an unconditional
top-tier final sign-off— is deliberately not added; see below.

## Claim-by-claim

| Piece of the pattern | Present in kbg-harness? | Where |
|---|---|---|
| Tier the makers by role (cheap tier bulk-executes, strong tier plans/judges) | ✅ | all 20 `agents/*.md` pin a `model:` field, none inherit — `opus` for judgment-heavy (backend-architect, blind-spot-hunter, plan-reviewer, requirement-analyst, spec-miner, task-prep-checker), `sonnet` for most execution/review, `haiku` for `summarizer` |
| Senior review as advisory input feeding a deterministic gate, not the gate itself | ✅ | `commands/compliance-audit.md:70,93` — fresh-context verifiers judge, but the accept criterion is a deterministic threshold (open-item count must be 0) plus an independent test-suite re-run; `commands/deep-audit.md` Step 6 re-verifies before accepting |
| Panel/vote decided in code, not model self-declaration | ✅ | `scripts/workflows/deep-research.js:21-22,377-382` — `VOTES_PER_CLAIM = 3`, `REFUTATIONS_REQUIRED = 2`, three outcomes (`survives`/`isRefuted`/`unverified`) computed in plain code; an errored vote yields `unverified`, never `refuted` (fail-closed — comment cites `go/ccissue/69883`) |
| Numeric retry cap on a review→fix loop | ❌ → closed this pass | `skills/orchestrate/reference.md`'s Builder→Validator→Fixer chain had a conditional fix pass but no bounded loop-until-N; "retry cap" appeared only as named vocabulary (old line 477), never implemented with a number |
| Panel-vote discoverable as a named, reusable pattern | ❌ → closed this pass | the pattern-vocabulary table's `adversarial verification` row didn't mention it, despite a correct implementation already existing in this repo |
| Unconditional top-tier final sign-off gating "done" | ❌ — declined, see below | — |

## Gaps closed

`skills/orchestrate/reference.md`, three edits:

1. A new paragraph after the 4-step `### Concept` list: a numeric fix-retry cap of 3 attempts on
   the same finding set, the 4th is an escalation not a round. Sourced internally, not just from
   the new research: `skills/loop-design-check/SKILL.md:63` already mandates "retry cap N +
   escalate to a human when exceeded" as a named failure mode, and 3 is the only retry-cap number
   written anywhere in this repo's own loop doctrine (`:137`, "Type: servo, retry cap 3"). The new
   paragraph explicitly reconciles with the pre-existing "retry cap at 1" line elsewhere in the
   same file (L5/unattended-execution regime) — different axis (attended vs. unreachable-human),
   not a contradiction, and now says so in the text instead of leaving two unreconciled numbers.
2. One referencing clause at "Lead check between waves" — no restated number, points back to the
   § Concept paragraph so the cap lives in exactly one place.
3. The `adversarial verification` row in the pattern-vocabulary table gained a "Panel-vote
   variant" clause citing `deep-research.js`'s constants as the working precedent to copy,
   including its fail-closed third outcome — extended the existing row rather than adding a 7th,
   since the table's own framing states "6 named patterns" sourced from an external article; a
   7th row would misattribute a kbg-native addition to that source.

## Declined: unconditional top-tier final sign-off

Two independent reasons, not one — either alone would be enough:

- **Doctrine.** The current root `CLAUDE.md` § Architecture states this repo's live operating
  model directly: "the gate is a verifier (deterministic shell returning a branchable score), the
  model is the maker, and the maker can never grade its own work... advisory sensors journal but
  never gate." An unconditional pass that gates "done" purely on a model's own judgment, with no
  deterministic backstop, is exactly the shape this line rules out.
- **Evidence.** Independent of kbg's own doctrine, the best evidence found cuts against it too.
  Adversarial Review vs. MARS found a leaner setup beating a heavier review hierarchy; TAO found
  agreement quality degrading, not improving, as tiers climb. Nothing in the research supports
  adding an always-on extra tier.

**Correcting a mid-session assumption:** an earlier advisor consult (before this repo's own
architecture was checked) assumed ADR 0006 forbids any multi-tier LLM review structure. A verbatim
re-read (`git show c759a581:docs/adr/0006-ecc-aligned-operating-model.md` — the file is deleted
from HEAD, its content folded into current `CLAUDE.md` prose) shows its actual scope is narrower:
it retired the L2–L5 self-directed autonomy-escalation ladder and the automated computational
ship-gate that blocked pushes pending review, while explicitly keeping "reviewer read-only /
maker≠checker... hermetic, universal, KEEPS RUNNING" and stating that bar "stays a human judgment
matched to stakes, never a hard-coded gate." Multi-tier review itself was never what ADR 0006
forbade — only an unattended push/ship decision made purely by an LLM's say-so is what conflicts
with kbg's live doctrine, and that doctrine lives in the current `CLAUDE.md`, not the deleted ADR.

## Known gap — CLOSED same day (v0.68.423)

`skills/review-pr/scripts/should-continue-loop.sh` computed a real deterministic stop decision,
but nothing hook-enforced a model actually obeying it — a model could read "stop" and re-invoke
`review-pr` anyway. Closed 2026-08-21 by `gate:skill:review-pr-loop`
(`hooks/gates/review-pr-loop-gate.sh`): the loop script now persists its verdict
(`loop_decision`/`loop_reason`) into the state file it already owns (no third copy of the
condition — the gate reads, never re-derives), and a `PreToolUse` Skill-matcher gate emits
`permissionDecision: ask` on a re-invocation only at genuine exhaustion (`ceiling`/`regressed`/
`churning`/`stalled` or `force_human`) on the exact reviewed HEAD and branch. Ask, not deny — a
human deliberately requesting another round stays one click, per this doc's own "human at
exhaustion" framing; converged/clean stops never ask (a plan-review pass caught that an
unconditional version would fire on the success path). Known limits stated in the gate header.

## Relationship to ADR 0009

Same conceptual family as `docs/research/adr-0009-bounded-review-fix-auto-loop.md` — bounded
review→fix, a numeric cap, human at exhaustion — but a different surface: ADR 0009 bounds
`review-pr`'s *scripted* round loop (`write-review-state.sh:238`'s `ROUND_CEILING`, default 5,
computed in real code); this pass bounds `orchestrate`'s *documented* Fixer-chain pattern, which
has no backing script of its own — the cap is a convention for whoever builds off the reference,
not code that enforces itself. Different number, stated reason: PR review rounds over a changing
diff vs. fix attempts on one static finding set are different task shapes.

## Sourcing

Full research (8 primary sources, 4 parallel subagent passes, plus the follow-up pass covered
here) lives in the llm-wiki dossier cited above — not duplicated here.
