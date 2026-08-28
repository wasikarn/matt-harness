# "The AI-Native SDLC playbook" (Anthropic, Louis Claxton) vs matt-harness

**Date:** 2026-08-28
**Source:** https://claude.com/blog/the-ai-native-sdlc-playbook
**Verdict:** Mostly *confirms* architecture matt-harness already shipped. One active conflict
(not a gap — already litigated). Two optional, non-urgent candidates named for the user to
decide; nothing built.

## Method

Anthropic's own Applied AI playbook, six SDLC stages (Plan/Design/Build/Test/Deploy/Maintain),
each with a committed `.md` artifact and a named play. Mapped each play against matt-harness's
actual mechanisms (verified against source this session — not assumed from prior memory) and
against the ADR history in `docs/research/`.

## Stage-by-stage mapping

| Playbook stage/play | matt-harness equivalent | Status |
|---|---|---|
| **Plan** — `intent.md`, brainstorm-with-Claude | `hooks/advisory/flow-nudge.sh`'s chain: `grilling` (bare, model-tier) | Already covered — grilling *is* the intent-capture play, just not written to a committed file by convention |
| **Design** — `spec.md`, requirements+design in one session, guided by skills | `/to-spec` (same chain) | Already covered |
| **Build** — plan mode as default start, `plan.md`, CLAUDE.md, skills as institutional knowledge, hooks as build-time guardrails, parallel sessions/subagents | Claude Code plan mode (used natively all session, e.g. the diagram-overhaul plan just shipped), `CLAUDE.md` (this repo's own, extensively iterated), `hooks/gates/*` (deny) + `hooks/advisory/*` (journal), `Agent` tool + `git worktree add -b` convention | Already covered, more formalized than the playbook's version — mh's gate/advise split (CLAUDE.md's "unifying crux") is a stricter doctrine than the playbook's plain "allow/ask/block" |
| **Test** — feedback loop, continuous evals in CI | TDD-required-for-bugfix rule, `scripts/run-gauntlet.sh` (6 parallel layers) | Feedback loop: covered. Continuous evals-in-CI on agent-config change: **not currently present** — see Candidate 1 below |
| **Deploy** — AI in PR review loop, `REVIEW.md` w/ severity caps, hooks as approval gates | `contexts/review.md` (near-identical shape: Critical/Important/Minor triage, file:line + fix, no hedging), `mattpocock-skills:code-review` (full pipeline), `skills/review/risk-check` (LOW/MED/HIGH scoping, advisory-only), `skills/review/address-review` (reply-to-reviewer loop), `skills/*/ship-merge` (gated merge, `disable-model-invocation`) | Already covered, and more separated: review / risk-scope / address / merge are four distinct gated skills, not one blended loop |
| **Maintain** — autonomous headless invocation on a control-band breach, confidence gates between stages, `bands.yaml` | The retired L2–L5 autonomy ladder | **Active conflict, not agreement** — see below |

## The one real conflict: Stage 6 "Maintain" is the retired ladder

The playbook's Stage 6 — a deterministic trigger invokes Claude with no human in the loop,
Claude diagnoses and acts up to a gate, output re-enters the pipeline as a new `intent.md` — is
structurally the same shape as mh's own L2–L5 autonomy ladder, retired by **ADR 0006**
(`docs/reference/env-vars.md:26`, `docs/harness-decay-cadence.md:242`, reconfirmed 5+ times per
`docs/research/loop-graph-engineering-trend-audit-2026-08-02.md` and 9+ other articles this repo
already checked it against). This isn't new information arriving — it's the same proposal this
repo already tested, found unreliable in exactly this form, and walked back.

The one narrow exception: **ADR 0009** (`docs/research/adr-0009-bounded-review-fix-auto-loop.md`)
re-armed a *bounded* slice of this — per-round human-gated auto-continue for a review→fix loop,
explicitly *not* the ladder's structural definition (no flag, no notches, no self-launch, no
OS-scheduler trigger). The playbook's `bands.yaml` / 1σ-2σ-3σ pattern goes further than even
ADR 0009 permits (autonomous *trigger*, not just autonomous *continue* within an already-started
session) — and it's aimed at a deployed service's live production metrics, which matt-harness
(a plugin/skill repo, not a deployed service) doesn't have. **No build from this stage.**

## Candidates named, not built

**1. Config-change-triggered regression evals.** The playbook's CI job (`.github/workflows/
agent-evals.yml`, runs on `CLAUDE.md`/`.claude/**` diffs) is narrower than what mh deleted —
the removed 204-test suite was bound up with L3/L4/L5 autonomy-machinery testing per
`CLAUDE.md`'s Validation section, not a generic "did this skill edit regress behavior" check.
Worth a look if skill/hook edits ever start regressing silently; not urgent — no such incident
on record.

**2. Reusable release-gate hook template.** The playbook's `production-gate.sh` (block a
`deploy...production` Bash command without `$RELEASE_APPROVAL` set) is a clean pattern for a
downstream project *with* a deploy stage. matt-harness itself has none — no build here, but
worth keeping as a pointer if a future skill ever needs to hand a consuming project a
starter hook.

## What's already stronger than the playbook describes

- The gate/advise split (`docs/reference/operating-model.md`) is a harder invariant than the
  playbook's "hooks can allow/ask/block" — mh's own doctrine forbids a model ever grading its
  own gate (maker≠checker), which the playbook doesn't address at all.
- Review is four separably-gated skills (`code-review` / `risk-check` / `address-review` /
  `ship-merge`), not one blended "Claude reviews and fixes" loop — each irreversible step
  (`ship-merge`, `address-review`) individually carries `disable-model-invocation`.
