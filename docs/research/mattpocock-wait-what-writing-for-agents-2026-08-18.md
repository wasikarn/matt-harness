# Mattpocock wait-what + writing-for-agents research (2026-08-18)

## Question

Why does `mattpocock-skills:wait-what` work — mechanism, not magic — and does the underlying
principle generalize to (a) kbg-harness's own doctrine/tooling, (b) matt's broader
skill-authoring philosophy (why his skills stay small without losing content), and (c) matt's
approach to grouping/organizing a skill fleet.

## Bottom line

**State a checkable behavior/state, never a shape/length target.** That single principle is what
makes `wait-what`'s live-dialogue repair *and* `writing-for-agents`' no-op test work — the same
mechanism, two different state-anchors for two different genres (a present listener's real-time
failure signal vs. a per-line behavioral deletion test). kbg-harness's own size-driven checks
(20, 36's word-count sub-check, 42, 47, 51, 60) had no such backstop — confirmed via a fresh audit
— now formalized as a "no-op test" convention (GitHub #53/#54). Applying the same framework
(`writing-for-agents`' "context load vs. cognitive load") to kbg-harness's *own* doctrine files
found a bigger, unaddressed lever than the body-compression work this session already spent hours
on: CLAUDE.md + METHODOLOGY.md + staff-eng.md cost **51,261 chars, unconditionally, every single
turn** — dwarfing the ~923K-char on-demand skill/command/agent body corpus that only costs when a
specific surface fires.

## 1. Wait-what mechanism — refined across 2 rounds of adversarial critique

The skill (`skills/productivity/wait-what/SKILL.md`, 3 lines, `disable-model-invocation: true`):

```
Wait — I don't understand where you've got to here. Re-pitch that: give me a little
bit of context, talk in ASD-STE100 Simplified Technical English, and use the
ubiquitous language from `CONTEXT.md`.
```

| Claim | Status | Who refined it |
|---|---|---|
| "Be brief" targets output shape (length, unbounded-below); "wait, you lost me" targets listener state (comprehension, floor-bounded) — Goodhart's law explains why shape-targets degrade | Directionally right, survives | Original framing |
| The sharper claim: no instruction in the bundle asks the model to **minimize** anything. ASD-STE100 is a *local, floor-bounded* register constraint (satisfiable, then stops) — not a global metric a model can keep shrinking. The one quantity word in the whole skill is "a **little** bit" — it points at addition, not subtraction. | Refinement, not a correction — the user independently reached the same conclusion from a different angle ("target is not word count, it's repair, which has a natural floor") | Adversarial-critique agent + user, independently |
| "Wait" itself does a narrower, separate job: it authorizes **scope-reopening** — permission to back up further than the last sentence and revisit premises — not the anti-brevity property directly | Refinement | Adversarial-critique agent |
| The skill's own 3-line length is *part of the mechanism*, not incidental — a short instruction models the terse-but-complete register it asks for; a 400-line "please be concise" ruleset teaches the opposite register by its own bulk | New, uncontested | User's own contribution — no agent surfaced this independently |
| 4 "it's working if" criteria graded for falsifiability: "shorter and clearer, not blunter" (weakest, adjective judgment) < "adds the missing premise" (closer to checkable — entailment test possible) < "project nouns replace invented ones" (string-match against CONTEXT.md) < "use it twice, no degradation" (strongest — a repeated-trial differential test) | Confirmed via direct textual analysis | Adversarial-critique agent |

## 2. The static-document analog: `writing-for-agents`' no-op test

`mattpocock-skills:writing-for-agents` (the doc every matt skill is written against — read in full
from the local clone, `docs/productivity/writing-for-agents.md`) states the identical principle
for compressing static documents, independently of `wait-what`:

> "The no-op test is behavioural, not aesthetic: delete the line and ask whether the agent's
> behaviour changed." — on why agents told to "streamline" fail (they optimize for length,
> "because length is the thing they can see")

> "The document gets shorter as it gets better, and you are surprised how little is left." —
> its own "it's working if" criterion; brevity as a byproduct, not the target — structurally
> identical to wait-what's own criteria

**What transfers and what doesn't:** the live-listener-specific mechanism in `wait-what` (a
present, currently-confused addressee supplying a real-time failure signal) does not transfer to
static text — there is no listener. What transfers is the underlying discipline (anchor to a
checkable state, never a shape), instantiated by a *different* state-anchor suited to static
content: agent-behavior-on-execution, checked per line.

The other lever that keeps matt's skills small without losing content: **leading words** — a
compact, already-pretrained-rich concept (e.g. "tight", "tracer bullet") that does double duty as
both the invocation trigger (in a pointer/description) and the execution anchor (in the body) —
one rich word replaces a paragraph of explanation the model would otherwise need spelled out.

## 3. Applying the same framework to kbg-harness itself

Measured (not estimated), 2026-08-18:

| Load class | What | Size | Cost model |
|---|---|---|---|
| Unconditional, every turn | `CLAUDE.md` | 22,664 chars | Always loaded regardless of task |
| Unconditional, every turn | `docs/METHODOLOGY.md` | 13,931 chars | Injected via `doctrine-bootstrap.sh` on SessionStart |
| Unconditional, every turn | `output-styles/staff-eng.md` | 14,666 chars | `force-for-plugin: true` |
| **Sum, unconditional** | | **51,261 chars (~12.8K tokens)** | Paid every turn, forever |
| On every Task spawn | skill+command description fields | 14,185 chars | Check 47 tracks this (64,000-char ceiling, 22% utilized) |
| On every Task spawn | agent description fields | 7,115 chars | **Not counted by any check** — real gap |
| On-demand, per surface fired | all `skills/*/SKILL.md` bodies | 424,368 chars | Only costs when that skill fires |
| On-demand, per surface fired | all `commands/*.md` bodies | 265,353 chars | Only costs when that command fires |
| On-demand, per surface fired | all `agents/*.md` bodies | 233,436 chars | Only costs when that agent fires |
| **Sum, on-demand** | | **923,157 chars** | Never all paid in one turn |

**Finding:** this session's entire multi-round body-reduction task (8 `skills/*.md` files cut to
≤14,000 chars each, then 8 `commands/*.md` files spec'd for the same) optimized the on-demand
corpus first. `CLAUDE.md` alone (22,664 chars, paid every turn) is bigger than any single file in
that reduction queue, and its cost compounds every turn of every session, forever. Not wasted work
— check 51's gate is real and needed fixing regardless — but wrong priority order if token economy
was the objective from the start.

### CLAUDE.md pruning — claim vs. verified reality

First pass proposed ~4,900 chars (22%) prunable via the no-op test. Adversarially verified against
the actual file, cross-checked against `docs/skill-authoring-conventions.md` and
`docs/METHODOLOGY.md`:

| Block | Claimed prunable | Verified safe | Why the gap |
|---|---|---|---|
| Composer-not-creator incident narrative | 750 | 400 | Scar tissue — CLAUDE.md is the *primary* record that the check-order rule ever mattered (the code-implementer/`/implement` collision); `docs/research/ast-layer-agent-codemods-2026-08-13.md:148` and `CHANGELOG.md`'s `[0.58.10]` entry both cite it, but both point back to CLAUDE.md as their source rather than independently corroborating it. Stripping the narrative here still risks recreating the exact regression it documents, since the derivative citations wouldn't survive a search of CLAUDE.md alone. |
| qmd section's "why this line lives here" | 1,200 | 800 | States plainly the rule was already silently deleted twice by moving it into a skill — the paragraph exists specifically to stop a third recurrence. |
| "Same crux, N-worker fan-in" paragraph | 1,050 | 550 | `docs/METHODOLOGY.md` Rule 13 line 82 points *back* to this exact paragraph as "the enforcing detail" — it's the authoritative source, not a duplicate. |
| Worktree-guard-removed paragraph | 360 | 225 | Closest to the original estimate — its pointer destination (`docs/research/official-docs-audit-2026-07-31.md`) already exists. |
| `disable-model-invocation` 12-file enumeration | 1,000 | **0** | Proposed destination (`docs/skill-authoring-conventions.md`) has zero mentions of this topic — nothing to move it *to* yet. |
| "Same-version stale trap" recipe | 500 | **0** | No troubleshooting doc exists to hold this fix recipe — it's actionable content, not narrative; deleting now is pure information loss. |
| **Total** | **4,900 (22%)** | **1,975 (9%)** | 2.5x overclaim — 2 blocks are load-bearing scar tissue, 2 are blocked on missing companion-doc infrastructure |

## 4. Matt's own skill-grouping structure (2-layer, not a flat taxonomy)

Read directly from the local clone (`~/Codes/Personals/mattpocock-skills`), not just the public
website (which under-renders — its collapsible sections don't convert to fetchable text).

**Layer 1 — on-disk folder** (mechanical; determines public/shipped status):
`skills/engineering/` (18 skills, dev-flow), `skills/productivity/` (7 skills, human-facing/not
about code), `skills/in-progress/` (6, drafts — zero matching `docs/` entries), `skills/misc/` (4,
personal/one-off — zero matching `docs/` entries), `skills/deprecated/` (0 currently). `docs/`
(the site's content source) mirrors only `engineering/` + `productivity/` 1:1 — `in-progress` and
`misc` are never publicly exposed.

**Layer 2 — `ask-matt/SKILL.md`, the real router** (~1,100 words, pure prose, zero
tag/metadata-driven categorization): a single file organized as a navigable flowchart — **Main
flow** (idea→ship, numbered steps with explicit branches), **On-ramps** (situations that generate
work and merge onto the main flow: triage, diagnosing-bugs, wayfinder — each stating exactly where
it merges back in), **Codebase health** (explicitly "Not feature work — upkeep"), **Vocabulary
underneath** (domain-modeling, codebase-design — "the reusable layer other skills invoke or
cite"), **Standalone** (the largest bucket — everything off the main flow), **Precondition**
(one-time setup). Every entry states its trigger *and* its destination in the same sentence — a
context pointer, in `writing-for-agents`' own vocabulary, applied at the fleet level. A skill can
appear in more than one bucket when genuinely justified (`prototype` is both a main-flow detour
and listed under Standalone).

The website's public taxonomy (Main Flow / Shaping / Upkeep / Productivity Skills / Reference
Skills) is a simplified marketing repackaging of this same structure — not the ground-truth
navigational source, which is `ask-matt` itself.

kbg-harness's own equivalent is split across three surfaces (`kbg:inventory` — mechanical list,
`/kbg-help` — flat 6-stage table with no branch/handoff logic, `/ask-kbg` — closest in spirit but
thinner) covering 96 surfaces (51 skills + 20 agents + 25 commands), with no functional/role-based
grouping comparable to `ask-matt`'s. Raised as a candidate improvement, not yet scoped or spec'd.

## 5. The mechanism confirmed in practice — the fleet, measured and read

The earlier sections above were derived mostly from matt's *meta*-doc (`writing-for-agents`) and
one 3-line example (`wait-what`). This section checks the theory against his actual working
skills — measured sizes, read files across the size spectrum, plus one previously-unread doc
(`SKILL-MECHANICS.md`) that turned out to explain a structural difference from kbg's own fleet.

### Size distribution, measured

All 25 published skills (`skills/engineering/` + `skills/productivity/`, excluding the
unpublished `in-progress/`/`misc/` folders — see §4): **count 25, sum 116,728 chars, average
4,669, min 157 (`grill-me`), max 12,056 (`wayfinder` — his own description: "the most cognitively
demanding flow here").** Every one of his skills, including the largest and hardest, sits well
under kbg-harness's own 20,000-char hard ceiling and 14,000-char reduction target — this isn't a
close call.

### The extreme case: composition over restatement

`grill-with-docs/SKILL.md`'s entire body, in full: `Call the Skill tool twice, for "grilling" and
"domain-modeling".` (247 chars total, frontmatter included). This is the no-op test taken to its
logical limit — every sentence explaining the interview procedure would be a no-op duplicate of
what `grilling` and `domain-modeling` already say, so the file states none of them. Single source
of truth enforced by literal reference, not restatement. `grill-me` (157 chars, the smallest skill
in the fleet) does the same for the stateless variant.

### The actual answer to "why small without losing content"

Reading `diagnosing-bugs` (8,614 chars, a 6-phase discipline) shows the identical move
`writing-for-agents` teaches for documents, applied instead to a bug repro: *"Minimise... shrink
the repro to the smallest scenario that still goes red... Done when every remaining element is
load-bearing — removing any one of them makes the loop go green"* (Phase 2). That is the no-op
test, word for word in spirit — "delete it, check if the outcome changes" — pointed at a failing
test case instead of a paragraph. `tdd`'s red-green loop ("only enough code to pass it... don't
anticipate future tests") is the same discipline applied to implementation. `wait-what`'s repair
logic is the same discipline applied to a misunderstood sentence.

**This is the real mechanism, not a documentation trick bolted onto his skill-writing separately:
"minimize to what's load-bearing, verified against a behavioral or outcome check" is matt's one
general-purpose problem-solving move, and he applies it reflexively to his own prose exactly as he
teaches the model to apply it to the user's code, bugs, and documents.** The no-op test isn't a
special writing technique sitting apart from the rest of his doctrine — it's this same move,
pointed at himself.

### Completion criteria as literal checklists, confirmed independently convergent

`diagnosing-bugs`'s phases end in explicit `- [ ]` checkboxes with falsifiable conditions (Phase
1: "Red-capable... Not 'runs without erroring' — it must be able to catch this specific bug"), plus
explicit stop-triggers against premature completion ("If you catch yourself reading code to build
a theory before this command exists, **stop**"). This independently converges with this repo's own
Rule 14 ("score, not feel") — arrived at separately, not copied from either direction.

### Leading words, watched doing real cross-section work

"Tight" is defined once in `diagnosing-bugs` Phase 1, then reused as a load-bearing adjective 4+
times through the rest of the file with no re-explanation. "Seam" is defined narrowly inside `tdd`,
but `tdd` explicitly defers to `codebase-design` for the *full* vocabulary rather than
re-explaining it there — single source of truth for a term shared across skills, enforced the same
way `grill-with-docs` enforces it for a whole procedure. "Load-bearing" is the same word, doing the
same test, in both `diagnosing-bugs` (bug repros) and this repo's own doctrine ("keep only what's
load-bearing") — independently, not borrowed.

### The piece that explains the structural gap with kbg's own fleet: `SKILL-MECHANICS.md`

`writing-for-agents`' own doc names a linked `SKILL-MECHANICS.md` for "what changes when the
document is a skill" but the earlier research pass never opened it. It names two invocation modes
with an explicit tradeoff:

- **Model-invoked** (keeps a `description`): the description is *permanent context load* — loaded
  every session/Task-spawn whether or not the skill ever fires — in exchange for the agent being
  able to fire it autonomously, and for *other skills* being able to reach it by name.
- **User-invoked** (`disable-model-invocation: true`): zero context load, but the cost shifts to
  the human — "you are the index that must remember it exists."

Matt's fleet leans heavily on user-invoked: `wait-what`, `grill-with-docs`, `grill-me`, `implement`,
`to-spec`, `to-tickets`, and `ask-matt` itself all carry the flag. This is a deliberate
context-load-minimization lever, not an accident — and it's *why* `ask-matt` has to exist at all:
*"When user-invoked skills multiply past what you can remember, that piled-up cognitive load is
cured by a router skill... It can only hint, never fire them."*

**This is a genuinely different reason than kbg-harness's own use of the same flag.**
kbg-harness's `disable-model-invocation` convention (12 carriers per root `CLAUDE.md`) is used
almost entirely as a *safety gate* — blocking an irreversible or external action (a PR merge, an
ambient-chat mis-trigger) from firing without deliberate user invocation. Matt's primary use of the
identical YAML field is a *context-load lever*, with safety as at most a secondary side-effect for
a couple of his own surfaces (`wizard`'s credential-handling caution reads closer to kbg's
reasoning than the rest of his fleet does). Two genuinely different problems converging on the same
mechanism — worth keeping distinct rather than assuming kbg's flagged surfaces and matt's flagged
surfaces solve the same thing.

## What this produced (tracked in GitHub, not narrated here)

- **Shipped**, commit `b88015e` (v0.68.368): `staff-eng.md`'s wait-what-repair bullet narrowed
  from literal-word triggers to actual confusion evidence; `ask-kbg.md`'s stale "no equivalent"
  claim corrected.
- **Issue #53** (spec) + **#54–58** (tickets): no-op-test convention in
  `skill-authoring-conventions.md`, plus 5 adversarially-verified fleet gaps in
  `review-pr`/`code-reviewer`/`address-review`/`fix-bug`.
- **Issue #59** (spec) + **#60–67** (tickets): the 8 remaining `commands/*.md` files reduced to
  ≤14,000 chars, using the no-op test *and* the full "it's working if" checklist (added after a
  gap was caught — the first ticket draft cited the doctrine without fully applying it).
- **Deferred, explicitly named, not silently dropped**: CLAUDE.md/METHODOLOGY.md/staff-eng.md
  further pruning (blocked on building 2 pieces of companion-doc infrastructure — see §3 table);
  a new harness-audit size check for `output-styles/*.md` (currently ungated despite
  `force-for-plugin: true`); extending check 47 to cover agent description fields; an
  `ask-matt`-style router for kbg's own fleet (§4); `fix-bug.md` Phase 2's location-explanation
  gap; `score-decision.md`'s 4–6 criteria escape hatch; a per-file audit sweep of the fleet's
  remaining unaudited surfaces (36/51 skills, 17/20 agents, 15/25 commands, 12/18 hooks never
  individually checked for this principle — the doctrine fix generalizes to them regardless, which
  is why a dedicated sweep was judged low-ROI, but "low-ROI to sweep" and "confirmed clean" are
  different claims).
