---
name: loop-design-check
description: "Pre-flight gate + review checklist against loop failure modes — spinning, verifier-gaming, wrong-answer completion. Use when designing/reviewing an agent loop. Don't use for one-off tasks."
bucket: meta
metadata:
  origin: ECC
model: inherit
effort: high
---

# Loop Design + Review

> **Premise.** An LLM is a feed-forward system: prompt in → tokens out, with no built-in "steer toward the goal" across turns. To make it *behave* like a goal-oriented system, you wrap a feedback loop around it. This skill helps you **write** that loop correctly and **review** it so it won't run away.

> **Status: advisory checklist, not gated.** No hook or CI job enforces any row below — it's guidance you apply by hand before wiring a new loop, or when reviewing one that already exists. (Honest-status marker pattern — see `eval-harness/SKILL.md`.)

## When to use / not

**Use it when:**
- You want to hand a repeating task to an agent that runs over and over (write→test, test→fix, fix→verify…).
- You already have a loop and worry it spins, cheats, or runs a wrong answer to completion.

**Don't use it for:**
- A one-off task → just do it; don't wrap a loop around it.
- A plain timer/poll → use `/loop` or `/schedule`; no design needed.
- *How to wire the loop architecture* (pipelines, DAGs, long-run recovery) → that's the mechanism layer: `/loop`/`/schedule` for the wiring, the `Workflow` tool for multi-agent DAG pipelines, `orchestrate` for triaging competing tasks before any of that. **This skill only covers "is the goal right, and will it run away" — it does not re-explain mechanism.**

## Red-line premise: two levels of feedback

| Level | Who owns it | What it does |
|---|---|---|
| **Execution** (low) | machine/agent | Measures "how far from the literal goal" and grinds it to zero. The machine is strong here. |
| **Judgment** (high) | **human** | Decides "is this goal itself right, should it change, should it stop." The machine can't step outside its own loop to question the goal. |

> A thermostat can feed back "how far from 26°C," but when you have a fever and want 28°C it can't judge whether 26 is the *right* target — it just grinds toward 26. **"What to set today" is always the human's call.**

This is the same crux as this repo's `CLAUDE.md` § Architecture ("the gate is a verifier, the model is the maker, the maker can never grade its own work") — that paragraph is why ADR 0006 retired the L2–L5 autonomy ladder. Treat the two as one principle stated twice: once as a verifier/maker split, once as a judgment/execution split.

---

## Action 1 — Write a loop (5 steps)

### Step 0 · Subtract first: should you even build it? (4-condition gate, any miss = veto)

① the task repeats weekly or more; ② verification can be automated; ③ the token budget can take it; ④ the agent has tools that actually *run and see the result*

Miss any one → **don't build a loop**; do it by hand or another way. If the read on any condition is genuinely contested rather than a clean miss, that's a decision worth scoring explicitly — escalate to `score-decision` rather than talking yourself past a veto.

### Step 1 · Define a *machine-decidable* goal (the hard part — the loop lives or dies here)

The whole loop rides on the comparator's "is it done yet?" **The comparator can only work if your exit condition can be judged yes/no by a machine.**

- Bad: Vague ("make it good," "write it sharper") → the comparator can't judge → either it never passes (stuck retrying) or it guesses (passes/blocks at random).
- Good: Decidable ("all 96 unit tests green AND a change-list is produced," "module-02 fields filled, pytest passes, business logic untouched") → one check settles it; the loop converges cleanly.

**Five-point goal framework:**
1. **Done-criterion is machine-verifiable.**
2. **Boundary conditions defined alongside the done-criterion** ("what it must NOT do") — anti-Goodhart; missing boundaries = a license to cheat.
   Two boundary categories are easy to skip because they aren't about the goal itself: if the loop
   processes content it didn't generate (a ticket body, a file upload, anything user-controlled),
   that content is untrusted input, not just data — the boundary should say what the loop must not
   do in response to what the input *says*, not just what it contains. And if the loop edits files,
   the boundary should scope *which* files it may touch (excluding migrations, CI config, auth/secrets
   paths by default) rather than leaving write access unrestricted.
3. **Has a failure fallback** — retry cap N + escalate to a human when exceeded.
4. **Goal is layered.**
5. **Prefer reconciliation over assertion for the done-criterion** — anchor to external fact (golden sample / upstream total / reconciled diff) before your own assertions. "All tests pass" can be gamed; "diff vs the reference < 0.01" can't.

> **Self-check:** read the goal to someone who doesn't know the domain — can they run one command and tell whether it's done? If not, it isn't decidable enough. Go back.

### Step 2 · Pick the loop type

| Your task | Loop type (cybernetic) | How it stops |
|---|---|---|
| Has a clear "done" test | **servo** (`/goal`-style closed loop) | stops on reaching the goal |
| No endpoint, must keep maintaining state | **regulator** (`/loop`-style thermostat) | never stops; acts only on change |
| Periodic sampling, stop on a condition | **regulator with an exit** | stops when the exit condition holds |
| Must "ensure something happens on time" | wrap the above in `/schedule` | cron fires it |

`/goal` in this environment is always user-typed, never model-invoked — picking "servo" here names the loop shape, it isn't license to fire `/goal` on the user's behalf.

### Step 3 · Pick a skeleton

**Maintenance type (tend something that exists) → document-driven dispatch.**
The loop isn't "run a fixed check on a timer," it's **"read a doc on a timer, and dispatch only when the doc changed."** The doc is the task queue + state machine + human interface. Three disciplines: ① the problem column is human-write-only, the result column is loop-write-only, **state advances one-way and never rolls back**; ② **the exit code is final**; ③ state advances only as far as "awaiting verification" — **the "done" cell is flipped by a human only.**

**Greenfield type (build from scratch) → plan / build / judge, three roles.**

| Role | Does | Key |
|---|---|---|
| **Plan** | break the goal into a spec + **decidable acceptance conditions** | acceptance must be script-judgeable |
| **Build** | write to the spec | **must not change the acceptance conditions** |
| **Judge** | run acceptance **independently**; pass → stop, fail → return with the failure reason to Build | **independent + deterministic** |

Three iron rules: ① **the judge must be independent** — not the same agent as Build; ② **deterministic rules**, never "looks right"; ③ **Build may not edit the acceptance conditions to pass**. Three failed retries → escalate to a human.

This fleet's clearest skeleton match is plan/build/judge, not document-driven dispatch: `orchestrate`'s Validator/Re-validator chain runs the judge as a separate agent invocation from the one that wrote the fix, and `review-pr`'s Phase 5 scrutinize step sends every Critical/Important finding to a fresh, independent agent that tries to refute it — the reviewer that surfaced the finding never gets to be its sole judge either. `recursive-improve`'s gated propose-loop (`AskUserQuestion` as the human-only approve flip) is close in spirit but re-derives its candidate list fresh every run rather than reading a persisted doc that only advances on change — not a strict document-driven-dispatch instance.

### Step 4 · Add damping (against oscillation/runaway)

Retry cap, hard stop, human flips the last switch = damping. **Negative feedback with no damping oscillates** — spinning in place, burning tokens.
For a periodic/regulator loop (Step 2), damping also covers overlapping invocations — a lock or a
skip-if-already-running check — since a cron interval shorter than one run's duration is a different
way to lose control than oscillation, and just as real.

### Step 5 · Land in three stages (don't go fully automatic on day one)

① **Run it once by hand** (forces you to state exactly "how the judge decides") → ② harden into a skill/sub-agents (a main loop dispatching plan/build/judge) → ③ hang it on cron for full automation.

`recursive-improve` is this repo's own stage-1/stage-2 example: hand-run per iteration, human-gated at every round, deliberately never promoted to stage 3. That's not an oversight — ADR 0006 retired unattended cron automation for anything a model would need to judge itself against, and this skill's own red lines (below) are why.

---

## Action 2 — Review a loop (checklist = five failure modes)

> Run the loop past each row. **Hitting any one = this loop will misfire; send it back.**

| # | Failure mode (how it breaks) | Review question (a hit = red) | Antibody |
|---|---|---|---|
| 1 | Goal is a correct platitude → **spins, burns money** | Can the exit condition be machine-judged yes/no? | Replace with a decidable result condition (Step 1) |
| 2 | "Verification" written as "check if it looks ok" → **agent confidently says fine and stops** | Is the judge the defendant itself? | Reconcile + exit code rules + independent judge |
| 3 | (worst) Only gates on "all tests pass" → **agent deletes the tests** | Is there a boundary ("what it must NOT do")? | Done-criterion **+ boundary** together (the Goodhart antibody) |
| 4 | Counts on the agent asking mid-run → **it runs the wrong answer to the end** | Is there any "clarify only at runtime" point? | **Front-load every clarification**; settle it once before launch |
| 5 | Bloated CLAUDE.md + stale memory → **the faster it loops, the more it errs** | Are the docs/memory it depends on fresh? | Layered memory + periodic lint — this repo's own antibodies: `kbg:memory-lint`, `kbg:context-budget`, `kbg:harness-audit` |

Rows 2–3 are the same discipline as `CLAUDE.md`'s verifier-separation crux and `review-pr`'s fail-closed disposition — a loop's judge role should never be filled by the agent under review, in this repo or anywhere else.

**Plus three red lines (violate any = not allowed to go automatic):**
- **Keep judgment with the human.** Acceptance / the "done" cell is flipped by a human; the loop is not the acceptance officer. In this repo, this is ADR 0006 — see `docs/harness-decay-cadence.md` and `docs/reference/env-vars.md` § Autonomy flags for what got retired and why.
- **Responsibility doesn't transfer.** Anything whose failure you can't afford (merge the wrong PR, publish the wrong thing) → **don't hand over the authority automatically.**
- **Counter-intuitive warning.** The more "self-improving/rewrites-its-own-rules" a loop is, the **stricter the human review it needs** — not looser. The human's judgment must sit **before the action** (a hard gate), not as a post-hoc patch.

---

## Worked example — reviewing a "nightly green-keeper" loop

- **Naive goal:** "make all tests pass." → Step-1 self-check fails: bait for failure mode #3.
- **Decidable goal (fixed):** "all tests green **AND** no test file deleted or weakened **AND** coverage not lowered **AND** a change-list produced."
- **Type:** servo, retry cap 3.
- **Skeleton:** plan/build/judge — the **judge is CI run independently**, never the fixing agent.

Review checklist catches what the naive version missed: **#3** — the naive goal lets the agent delete a failing test to "win," fixed by the boundary. **#2** — if the fixing agent judged its own fix it would pass itself, fixed by an independent CI judge. **#4** — an ambiguous 2 a.m. fix gets committed as a guess unless ambiguous cases are front-loaded to the human. **Red line** — the loop opens a PR but does not auto-merge.

---

## One-line close

> The hard part of writing a loop isn't "can I write a loop," it's **defining a goal a machine can reconcile** — decidable, bounded, reconciliation-based. The controller must be deterministic and external; keep judgment and the standard with the human; the system tends toward entropy, so maintain it.
> **A loop only rewards someone who has already thought it through. Count on it to think for you, and it will happily think wrong, with you, at scale.**

---

> Lineage: Wiener's two-level feedback (*The Human Use of Human Beings*, 1950) for the judgment/execution split and red lines; the plan/build/judge pattern from Anatoli's *Loops explained* and Addy's *Loop Engineering*. Ported from ECC's `skills/loop-design-check`; ECC's mechanism-layer siblings (`autonomous-loops`, `continuous-agent-loop`) were not ported — they assume a level of unattended autonomy ADR 0006 already rejected for this repo.

## Completion criterion

**Action 1 (write):** before calling a loop spec ready to build, confirm it passes the Step-1 self-check (a domain outsider can decide pass/fail from one command), Step 0's gate wasn't overridden on a real miss, and a retry cap is named. A spec missing any of these isn't ready — it's a loop that will spin or cheat once it's running.

**Action 2 (review):** before calling a review done, every one of the five failure-mode rows got an explicit hit/miss verdict and all three red lines were checked against the actual design, not assumed clean. A review that skips a row isn't a review.
