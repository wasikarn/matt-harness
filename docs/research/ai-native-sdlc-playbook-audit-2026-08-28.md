# "The AI-Native SDLC playbook" (Anthropic, Louis Claxton) vs matt-harness

**Date:** 2026-08-28
**Source:** https://claude.com/blog/the-ai-native-sdlc-playbook
**Verdict (superseded — see Round 2 below):** ~~Mostly *confirms* architecture matt-harness
already shipped. One active conflict (not a gap — already litigated). Two optional, non-urgent
candidates named for the user to decide; nothing built.~~ Round 1 (this section) was a
single-pass audit and overstated several "already covered" claims. A same-day 4-agent deep
re-pass (below) found two independently-corroborated hook regressions and corrected the
Stage-6 framing to be starker, not narrower. Read Round 2 first.

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

---

## Round 2 — 4-agent deep re-analysis (same day, corrected verdict)

**Method:** 4 independent fresh-context agents, one per stage cluster (Plan+Design /
Build+Test / Deploy / Maintain+measurement), each re-read the article and re-derived evidence
from source directly — instructed to check Round 1's claims last, not lean on them. Two
findings were corroborated independently by different agents working different scopes, which is
the strongest confidence signal this doc has.

**Corrected verdict:** Round 1 was too generous. Several "already covered" rows described the
*doctrine* mh states about itself rather than what's actually wired. The real picture: mh's
design intentions are frequently ahead of matt-harness's own enforcement of them — a pattern
that shows up three separate times below.

### Corroborated finding: retired hooks, never replaced (2 independent hits)

The same 2026-08-24 commit (`b31eaa13`, "retire the review pipeline, route to
mattpocock-skills:code-review") removed two different enforcement mechanisms and replaced
neither:

- **`gh pr merge` has no hook anymore.** `convergence-merge-gate.sh` used to intercept raw
  `gh pr merge` outside the `ship-merge` skill flow. It's gone, and `skills/workflow/ship-merge/
  SKILL.md:53` says so in its own words: "this command's in-flow gates are now the only
  merge-door protection." No `PreToolUse` hook matches `gh pr merge` today — `disable-model-invocation`
  on `ship-merge` blocks the *Skill tool call*, not a raw Bash merge. This is a real regression
  against the article's own worked example (`production-gate.sh`, a hard unbypassable block) —
  mh's merge door is currently *less* hook-enforced than the pattern it's being compared to.
- **The ADR 0009 bounded auto-loop is dead code.** Round 1 cited it as a live, narrow exception
  to ADR 0006. It isn't, as of the same commit: `should-continue-loop.sh` / `write-review-state.sh`
  no longer exist anywhere in the tree, and `~/.local/share/kbg/metrics/review-pr-loop-gate.jsonl`
  has exactly 3 rows, all from before the retirement, none since. **The Stage 6 gap vs. the
  article is starker than Round 1 stated, not narrower** — matt-harness currently has zero live
  auto-continue loop machinery of any kind, bounded or not.

Both losses trace to the same commit and the same cause: retiring a subsystem removed its
enforcement without a replacement being scoped in the same change. Worth naming as a pattern,
not just two isolated facts.

### New confirmed gaps (not in Round 1 at all)

| Finding | Evidence | Article claim it contradicts |
|---|---|---|
| Gates log no verdict anywhere | `grep -rl "jsonl\|metrics" hooks/gates/` → zero hits across all 9+ gates | "Every hook decision is written to the OpenTelemetry export with a timestamp and an allow or block verdict" (Deploy, Hooks as approval gates) — mh cannot currently answer "how often did gate X block" |
| Test-file-edit protection during a bugfix is prose-only | `docs/METHODOLOGY.md` Rule 4 has no backing hook/gate/audit-check anywhere in `hooks/` or `skills/meta/harness-audit/scripts/checks/` | Article step 4/7 (Test): "a hook that blocks edits to test files during a fix task" — self-inconsistent with mh's own maker≠checker doctrine, since this is exactly the "same role grades its own work" case that doctrine argues against |
| Formatter/linter-after-edit and credential-in-diff hooks don't exist | No `PostToolUse` hook matches `Write\|Edit`; `credential-guard.sh` blocks *reading* known secret paths, not scanning `Write`/`Edit` content for secret-shaped strings | Article's build-guardrail play names both explicitly |
| mh doesn't use worktree-per-session isolation, contra Round 1's framing | `CLAUDE.md`'s own "Concurrent sessions" section: "no worktree design... There's no isolation to fall back on, so discipline substitutes for it"; `irrecoverable.sh`'s gate blocks *creating new branches*, and by its own documentation doesn't even cover the native `claude --worktree` flag the article recommends | Article's parallel-sessions play assumes `claude --worktree <name>` per task |
| `contexts/review.md` isn't a REVIEW.md match — it says so itself | `contexts/review.md:25-27`: "lighter posture for ad hoc review conversation... load `mattpocock-skills:code-review` instead of hand-replicating its pipeline" | Round 1 called this "near-identical shape" — wrong comparison target |
| Real review pipeline can't do what the article claims | `mattpocock-skills:code-review/SKILL.md:76`: "Do not merge or rerank findings, because the two axes are deliberately separate"; no automated trigger fires any review on PR open (`.github/workflows/` has only plugin-validate) | "All PRs get an identical set of review passes, with findings ranked by severity" — mh's coverage is developer-remembered, not uniform, and one of its three review surfaces explicitly refuses cross-axis ranking |
| `costs.jsonl` has a schema break (pre/post 2026-08-07) | `skills/meta/cost-report/SKILL.md` itself warns never to read a pre/post difference as a spending change | Breaks the article's trend-based lagging-indicator pattern for mh's own longest-running metric |

### Corrections to Round 1's specific claims

- **"Already covered — grilling *is* the intent-capture play, just not written to a file by
  convention"** (Plan row) — understated. There's no committed artifact, no product-owner
  accept/reject gate recorded as a merge, and neither of the article's two intent-stage metrics
  are derivable. Sharper finding: matt-pocock's own `ask-matt` routing already prefers
  `grill-with-docs` (stateful, writes `CONTEXT.md`/ADRs) over bare `grilling` for exactly this
  reason, and it's installed in the plugin cache — `flow-nudge.sh` just doesn't point to it. A
  missing pointer, not a missing capability.
- **"Already covered, more formalized... hooks as build-time guardrails"** (Build row) —
  overstated; see the guardrail-gaps row in the table above.
- **"Not currently present... narrower than what mh deleted... bound up with L3/L4/L5
  autonomy-machinery testing"** (Test row, Candidate 1) — the "narrower" framing doesn't hold up.
  The actual deleted `eval/` directory (`git show c452102 --stat`) was mostly general skill/hook
  regression tests; only 2-3 of ~17 regression files were autonomy-specific. It was lost as
  collateral in a full-repo reset for an unrelated rebuild, not a considered rejection of
  CI-gated evals. `skills/meta/eval-harness/SKILL.md` still exists today as an honest
  "prose-only... no CI job enforces it" design doc — the capability was designed for, then never
  wired, not walked back on purpose.
- **"Already covered, and more separated"** (Deploy row) — the four-skills-not-one-loop
  structure is real, but "identical passes... ranked by severity" and "near-identical shape" to
  REVIEW.md are both overstated per the table above.
- **"The one narrow exception: ADR 0009"** (Maintain section) — dead code as of `b31eaa13`, see
  the corroborated finding above. Also a secondary framing fix: ADR 0009's own text draws a
  categorical wall at self-launch, not a continuum the article's `bands.yaml` merely "goes
  further" along — different axis, not more of the same one.

### Build candidates, ranked by evidence strength (still none built — facts for the user to decide on)

1. **Restore a merge-door hook.** A `PreToolUse (Bash)` gate matching `gh pr merge`, mirroring
   `production-gate.sh`'s pattern, would close the one place mh's Deploy-stage control regressed
   below the article's own baseline example. Concrete, small, evidenced by a real gap left by a
   specific commit.
2. **Test-file-edit gate during Rule 4 bugfix flow.** Closes a gap mh's own doctrine argues
   against leaving open (maker≠checker), not just an absence relative to the article.
3. **Gate-verdict journal.** One-line append from each `hooks/gates/*` script to a
   `gate-decisions.jsonl`, mirroring the pattern already proven by the 3 existing telemetry
   hooks (`cost-tracker.sh`, `skill-usage-telemetry.sh`, `instructions-loaded-journal.sh`).
   Closes the "score, not feel" gap in mh's own stated doctrine, not just an article mismatch.
4. Repoint `flow-nudge.sh` from `grilling` to `grill-with-docs` (near-zero cost, matches
   matt-pocock's own stated preference, closes most of the Plan-stage artifact gap for free).
5. Config-change-triggered regression evals (Round 1's Candidate 1, now better-evidenced: the
   design already exists in `eval-harness/SKILL.md`, unenforced — this is "wire it up," not
   "design it").
6. Reusable release-gate hook template (Round 1's Candidate 2 — unchanged, still speculative,
   no downstream project asking for it).
