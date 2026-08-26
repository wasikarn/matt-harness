# "Prompt Update Itself" article vs. kbg-harness — audit (2026-08-20)

**Source:** "How to Make Claude's Prompt Update Itself After Every 100 User Decisions," Hanako
(@hanakoxbt), published 2026-06-19 (X/Twitter thread, 176 lines, `~/llm-wiki/raw/`). Not yet
ingested to `wiki/`. Single-author, unreproduced — describes a recruiting-screening system
("Nick Mayhew... on stage at Anthropic"), not a benchmark kbg can independently check.

**The article's proposal, in one paragraph:** a governing prompt ("ideal candidate profile") is
treated as an apprentice, not a config — plain markdown prose, not weighted rules. Every human
decision (approve/reject a candidate, edit the profile) is logged. A cheap/fast model (Haiku)
scores every incoming input against the *current* prompt version, continuously. A slow/smart
model — the apprentice — reads only the last ~100-200 logged human decisions, asks "does the
prompt still match what the user is actually choosing," and **rewrites the prompt if not — no
human review step is described before the new version goes live** for the next batch.

## Verdict

**No build — but not because kbg already does this. Because kbg already considered this exact
shape and explicitly declined it, and the article supplies no new evidence to reopen that call.**
This is a different kind of "nothing to build" than the two prior article audits this session
(`reducer-engineering-article-audit-2026-08-20.md`, and the eval-gate-6step audit from
2026-08-02): those found convergent agreement — kbg's own code independently reached the same
design. This one finds **active divergence on the article's one load-bearing idea** (unsupervised
prompt rewrite, no pre-apply gate), with kbg's side already decided, on the record, before this
article existed.

## Component-by-component

| Article's component | kbg equivalent | Match? |
|---|---|---|
| Prompt as prose, not weighted rules | Every skill/agent/command in this repo is plain-English markdown, editable by a human or by a gated model pass (`recursive-improve`, `iterate-skill`) | ✅ already the convention — nothing to build |
| Log every human decision | `kbg:learn` retrospective-mines session transcripts for correction-shaped language after the fact | Different mechanism, same intent — see below, not a gap |
| Batch threshold, not per-event trigger | `review-pr`'s ledger tightens only after ≥5 sessions AND ≥50% rejection rate (`skills/review-pr/policy.md:7-10`) — the same "don't chase one noisy sample" reasoning, different domain/scale | Principle already applied elsewhere in-repo; "100 decisions" literally doesn't map (kbg has no decision stream at that volume) |
| Cheap evaluator + slow rare apprentice, two layers | No kbg mechanism runs a live per-request scoring layer at all — kbg-harness is a Claude Code plugin, not a service serving thousands of scored requests/day | Doesn't apply — no target surface exists in kbg's domain today (see Ponytail rung 1: speculative need, skip) |
| **Apprentice rewrites the governing prompt, no gate before it goes live** | Every kbg mechanism that free-form-rewrites governing prose (`recursive-improve`, `iterate-skill`) stops at a **mandatory** `AskUserQuestion` gate before any mutation lands. `kbg:learn` never edits an existing governing file at all — append-only new memory files, human-gated before write. | ❌ **direct conflict** — this is the finding that matters |

## The apprentice-rewrites-unsupervised conflict, in evidence

Four kbg mechanisms do something in the neighborhood of "a model updates governing prose from
accumulated signal." All four were checked directly against source, not summarized from memory:

- **`skills/recursive-improve/SKILL.md:20-21, 116`** — "every iteration stops at an
  `AskUserQuestion` gate before any mutation... Only an Approve authorizes Step 4."
- **`iterate-skill` command** (`~/.claude/plugins/cache/<marketplace>/kbg/v0.68.393/commands/iterate-skill.md`)
  — mandatory ASK gate between free-form Propose (Step 3) and Act (Step 5); Act only fires on
  Apply. Manually invoked, capped at 3 iterations — no decision-count trigger of any kind.
- **`skills/learn/SKILL.md:47-49, 126-128`** — `AskUserQuestion` (multiSelect) gate before any
  write ("reject = nothing written"), and structurally never edits an existing governing
  instruction file — only ever writes new standalone `memory/<slug>.md` files.
- **`skill-creator`'s `run_loop.py`** (upstream Anthropic, not kbg's own) — the one mechanism
  in the neighborhood of apply-then-show without a pre-mutation gate: the loop itself
  (`for iteration in range(1, max_iterations + 1)`, up to 5 unattended iterations, no human
  checkpoint inside it) only searches and returns `best_description` as JSON — the actual
  ungated write happens one layer up, in `skill-creator/SKILL.md` Step 4 ("Take `best_description`...
  update the skill's SKILL.md frontmatter. Show the user before/after"), which applies before it
  shows. Either way it's scoped to one skill-description line, not full governing prose, and its
  stop condition is a real measured trigger-rate score against a labeled query set — not an LLM
  judging its own rewrite (`promptwizard-borrow-verdict-2026-08-02.md`'s prior finding,
  re-confirmed this pass).

And the shape the article proposes was already explicitly evaluated and rejected once, before this
article was ever fed into this session. `docs/research/passive-learning-capture-design.md:135-142`,
§7 "Rejected / dropped (record, don't re-propose)":

> **ECC apply half entirely** — observer daemon, headless "do not ask" writes, ≥0.7 auto-inject,
> auto-promote, `/evolve` self-writing files, ecc2 cron + auto-merge. L4 / model-as-gate.

That's the article's exact mechanism — a system watches usage, decides on its own when the
signal is strong enough, and applies a rewrite with no human step in between — described and
declined under a different name, for the same underlying reason CLAUDE.md states as the repo's
"unifying crux": *"the gate is a verifier..., the model is the maker, and the maker can never
grade its own work... So advisory sensors journal but never gate, and the autonomy ladder had to
retire: a model-as-gate is the maker appointing its own verifier."* ADR 0006 retired kbg's own
L2-L5 bounded-autonomy ladder for exactly this reason.

## Steelmanning the article's side, briefly

The article isn't naive — "why 100 decisions, not one" (lines 62-90) makes a real point: a single
reject is noise (tired, distracted, testing the system, misclick), and only a batch shows a real
pattern. That's a legitimate argument for *batching the signal before acting on it* — which kbg
already does elsewhere (`review-pr`'s ≥5-session gate). What the article does **not** argue for,
and never addresses, is why the *application* of that batched signal should skip human review.
Batching answers "is this signal real," not "should a model apply its own conclusion unsupervised."
Those are separable questions, and the article silently treats solving the first as license to skip
the second. Compare: article A ("Reducer Engineering") explicitly flagged its own unresolved risk
(§7, "What I Haven't Tested" — the `normalize()` false-merge rate) and let a downstream builder
decide how to handle it. This article makes no equivalent acknowledgment for a design choice with
materially higher stakes — an auto-deployed prompt change compounding, unreviewed, across an
unbounded number of future batches, versus a single dedup step's local blast radius.

## Bottom line

Four of the article's five structural components are either already kbg's convention, already
solved by a different domain-appropriate mechanism, or don't have an applicable target in kbg's
current shape (no live per-request evaluator product) — none of those three are gaps. The fifth —
unsupervised apply — is a genuine, specific conflict with kbg's own already-decided doctrine, with
a prior explicit rejection on record and no new evidence in this article to revisit it. No build
follows. If kbg-harness ever grows a live per-request scoring surface (a real target for the
cheap-evaluator/slow-apprentice split), that pattern would be worth revisiting *with* the gate kbg
already requires everywhere else — but that surface doesn't exist today, so building the split now
would be scaffolding for a hypothetical (Ponytail rung 1).
