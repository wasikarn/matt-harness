# Autonomous-loop doctrine — full drill-down (2026-09-28)

**Date:** 2026-09-28
**Source:** Internal doctrine history (no new external article) — triggered by a request to
re-examine "the AI-Native SDLC playbook"'s Stage 6 (autonomous σ-band loop) once more given (a)
it's an official Anthropic blog post, (b) LLMs have shipped several generations since the
retiring decisions were made, (c) Claude Code itself has shipped many versions since. This is not
an `mh:idea-audit` re-run — the article itself was already re-scanned in full 4 times (most
recently today, `ai-native-sdlc-playbook-audit-2026-08-28.md` Round 4, 81/100 PASS). This document
instead traces the *doctrine's own primary sources* end to end, checks two specific claims that
could plausibly be stale, and reports what actually changed vs. what didn't.
**Verdict:** The decision to decline an autonomous/self-launching loop is not stale. It rests on
a structural (not capability) argument that current 2026 external research reconfirms rather than
undermines, and no Claude Code feature shipped since these decisions touches the specific boundary
they name. One real documentation defect was found and is worth a small fix (see below), and one
structural fact changed silently over time (ADR-0009's own implementation was later deleted) —
neither changes the verdict.
**Score:** N/A — this is a doctrine-history verification pass, not an adoption decision. No
PASS/FAIL threshold applies.

## Method

Read every primary source in this repo's own history, not summaries of them: `git log`/`git show`
across the full history (including the pre-"kbg→mh" rename era), the current live
`docs/reference/operating-model.md`, the two still-existing frozen ADRs
(`docs/research/adr-0009-bounded-review-fix-auto-loop.md`,
`docs/research/adr-0011-scheduled-recursive-improve-invocation.md`), 3 archived memory files
(`rgs-pushback-descope-2026-07-01`, `l3-bounded-autonomy-build`, `l4-l5-autonomy-build`), and
fresh external research (qmd `llm-wiki` + `WebSearch`) on the two claims most likely to have aged:
self-preference bias in LLM judges, and self-grading accuracy of frontier models.

## Finding 1: the cited primary source for the "crux" never existed

Roughly a dozen audit docs in `docs/research/` (`adr-0009-...`, `loop-graph-engineering-trend-
audit-...`, `agents-loops-graphs-article-audit-...`, `ai-native-sdlc-playbook-audit-...`, and
others) cite `agent-loop-verifier-crux.md` as the source document for the "two optimists
agreeing" / maker≠checker argument. **That file never existed anywhere in this repo's git
history** — confirmed by `git log --all --diff-filter=A -- "*agent-loop-verifier-crux*"`
(zero results) and `git grep -il crux` across the pre-rebuild tree (the string "crux" appears in
~15 files, none named that). The actual, real, currently-live primary source is
`docs/reference/operating-model.md`, section **"2. The maker never grades its own work"**
(the section was titled "Why — the unifying crux" before the 2026-06-27 rebuild; substance
survived, the filename citation others copied from it did not — likely a paraphrase that got
treated as a real path once, then copy-pasted forward without anyone re-checking it against the
actual file tree). This is a live citation-hygiene defect, not a doctrine problem: the argument
itself is real and current, but ~10 documents point at a file that doesn't exist.

## Finding 2: the two questions actually raised — checked against fresh evidence

### 2a. Have LLM generations since these decisions solved self-grading?

`docs/reference/operating-model.md:56-57` states: *"An LLM cannot reliably judge output it
produced in the same context (self-preference bias; task-completion self-grading tops out near
chance)."* This line was last (re)written in the 2026-06-27 `10b6230f` rebuild commit, with **no
citation anywhere in this repo's history** — confirmed by `git log --all -p -S "tops out near
chance"`, which finds no accompanying source/paper/benchmark reference ever added alongside it.

Checked against current (2026) external research (`llm-wiki` + live web search):

- **Self-preference bias is a structural problem, not a capability gap** — it recurs across
  every frontier-model generation checked in 2026 sources, including the newest ones. A 2026
  benchmark cited in `llm-wiki` (`Eval Engineering — build the gate that lets your agents merge
  without you`) found GPT-5.2 and Gemini 3.1 Pro hand their own model families 75-84% win rates in
  self-judged comparisons; Claude Opus 4.7 under-rated its own family instead (10.6-41.2%) — bias
  in both directions, not a solved problem in either. A 2026 RAND Corporation study (via
  futureagi.com) found frontier models exceed 50% error rates on the hardest bias benchmarks, and
  "no judge is uniformly reliable across benchmarks."
- **This is why the argument is architectural, not empirical-and-therefore-decaying**: the
  mechanism (a model marking its own homework has a built-in conflict of interest) doesn't shrink
  as the model gets smarter — a smarter model is still the same model grading itself. The 2026
  literature's own standard mitigation is "use a judge from a different model family," which is
  exactly this repo's `mh:deep-audit`/`mh:idea-audit`/`mh:compliance-audit` Codex-primary,
  different-model-family verifier pattern already in place — not a novel insight this repo is
  behind on, but independent confirmation it picked the right mitigation.
- **What is genuinely stale**: the specific phrase "tops out near chance" is an overclaim with no
  citation. The 2026 evidence found here shows a real, serious, *measured* bias (10-25% uniform
  skew; 50%+ error on adversarial benchmarks) — not literally chance-level (~50/50) self-grading
  on ordinary tasks. **Recommended fix** (not made in this pass — this document is read-only
  research): reword `operating-model.md:57` to state the bias without the unsourced "near chance"
  magnitude claim, or add a citation if a harder number is wanted.

**Conclusion for 2a:** the underlying principle is not stale — if anything, 2026 research
reconfirms it more concretely than this repo's own internal doctrine ever cited. The specific
wording has an honesty gap (uncited magnitude claim), which is a small doc fix, not a reason to
revisit the decision itself.

### 2b. Has Claude Code, across its version updates, shipped anything that crosses the actual line?

The invariant's precise boundary (`operating-model.md:100`, corrected 2026-09-28 — cited as `:98`
when this Finding was written, before an unrelated edit to `operating-model.md` shifted it): *"No
autonomous loop: the model never
starts work on its own; every wave begins with a human."* This is scoped to **self-start**, not
to "no loop machinery at all" — confirmed against ADR 0006's own original wording (quoted inside
`adr-0009-bounded-review-fix-auto-loop.md`): *"The model cannot self-start the improvement loop.
(The launchd self-start is gone with the L4 machinery; there is no OS-scheduler self-start
either now.)"* — a process-lifecycle scope (launchd/cron/detached self-launch from zero), not a
per-round-continue scope.

Checked what Claude Code has actually shipped since ADR 0006 (2026-06-26) that touches this
boundary, using this repo's own change history as the record (it tracks CC version drift
actively, not passively):

- **`/goal`** — added to this doctrine 2026-09-06 (`c0324f48`, v1.1.16). A session-scoped,
  prompt-based Stop hook on a small fast model; reads only the transcript, calls no tools,
  requires the operator to type it. Already integrated into doctrine text as compatible with the
  invariant, explicitly noted as *not* replacing the Rule 13 fresh-context validator.
- **`/loop` / `ScheduleWakeup`** (the mechanism running *this very session*) — same treatment,
  same doc line: *"`/goal` and `/loop` are the operator's to type."* `ScheduleWakeup` lets a
  session self-pace its own next wake-up, but only inside a session the operator already started
  by typing `/loop` — it cannot originate a new session, and the operator can end it at any time.
  This is the same shape ADR 0009 already litigated and bounded (continuing work a human started
  is not self-*starting* it) — not a new capability crossing the line, a Claude-Code-native
  instance of the exact pattern already ruled on.
- **`gate:agent:subagent-verdict-check-handback`** — built specifically to track a CC ≥2.1.271
  behavior change (GH #160, "auto-mode delivery path"). This is direct evidence the repo does not
  let CC version drift go unexamined; when a new CC mechanic touched verdict-delivery behavior, a
  gate was built for it within the same version-tracking cadence as everything else here.
- **No CC feature found, at any version through the current session (CC line ~2.1.28x), that lets
  the model schedule or trigger a **new** session/process without an operator action starting
  it.** The self-launch boundary (OS-level cron/launchd, or a human typing a command) is still
  drawn by the operator or the OS, never by the model, in every mechanism checked.

> **Correction (2026-09-28, later same day):** the bulleted claim above is wrong. **Claude Code's
> Routines feature** (CLI ≥2.1.225, created via `/schedule` or the `RemoteTrigger` tool) is exactly
> the counter-example this pass missed — a cloud-hosted session the model can trigger on a
> schedule, an HTTP fire, or a GitHub PR/release event, with **no operator present at trigger
> time**. It runs as a fresh main session (no `agent_id`), so mh's subagent-scoped gates never
> apply to it, and mh's hooks almost certainly don't run in that cloud environment at all — a
> materially different enforcement surface than anything this Finding checked. It is restricted to
> pushing only `claude/`-prefixed branches and is rejected on protected branches (relevant now that
> `develop` carries branch protection, Phase B of the SDLC-playbook reversal). This does **not**
> reopen the invariant on its own — ADR 0006 already forecloses reopening on a capability argument,
> and this is exactly that: a capability existing is not a reason to use it. It does mean Finding
> 2b's own evidence was incomplete, not that its conclusion was safe. Full context:
> `docs/adr/0004-operator-authorized-routine-self-launch.md` (the operator-authorized reversal this
> correction feeds into — a decision belonging to the operator, not to this doc having found a gap).

**Conclusion for 2b:** Claude Code's version updates have been tracked, and the two most
autonomy-adjacent features it has actually shipped (`/goal`, `/loop`) were examined and found to
sit on the human-started side of the line the doctrine draws — not proof the line needs to move.
**Superseded in part by the correction above**: a third feature (Routines) exists and does cross
the self-launch line mechanically; whether to use it is now the operator's own decision, tracked
in `docs/adr/0004-*`, not resolved by this Finding either way.

## Finding 3: the one precedent that *did* carve out a bounded exception is no longer live code

ADR 0009 (2026-08-14) is the one time the operator accepted a bounded per-round auto-continue
loop (review→fix, own-branch only, deterministic ceiling, no self-launch) — after 5 fresh-context
reviewers and 2 rounds of cross-ADR adversarial review, the most scrutiny any single decision in
this lineage received. Its implementation (`skills/review-pr/scripts/should-continue-loop.sh`,
audit check 59) **no longer exists** — deleted by `b31eaa13` ("retire the review pipeline, route
to mattpocock-skills:code-review"), a deliberate, documented decision unrelated to the autonomy
question (routing code review to an installed plugin instead of maintaining a native one, per
this repo's own composer-not-creator doctrine). ADR 0009's own document still says "✅ Accepted
and Implemented," which is now stale relative to the live tree — the *decision* to accept bounded
auto-continue still stands as a precedent, but there is currently **zero live auto-continue
mechanism of any kind in this repo**, bounded or not. The invariant is enforced with more purity
today than ADR 0009 itself ever required.

ADR 0011 (2026-08-28) — a proposal for a local, read-only, scheduled `recursive-improve` Observe
pass — was rejected specifically because it would be the *first* proposal to actually cross the
retained self-launch invariant (ADR 0009's own carve-out explicitly excluded `recursive-improve`
and kept "no model self-**launch**" unmodified). Its revisit trigger is explicit: *"If the
underlying trade-off changes materially — e.g. the no-model-self-launch invariant itself is
revisited at the ADR 0006/0009 level... this ADR can be reopened."* No such change has happened.

## Finding 4: the recurring pattern, for context

The same proposal shape — a model-driven governance/confidence loop reconsidering its own
constraints — was independently proposed and declined **4 times in a single day** (2026-07-01,
memory `rgs-pushback-descope-2026-07-01`), each under a different generic framework name (RAF →
RGS → RVSEF → "verifier as first-class runtime"), each colliding with the same two arguments:
(1) classifying "decision criticality" or "confidence" at runtime needs either an LLM doing the
classifying (circular) or deterministic understanding of free text (not buildable) — no third
option; (2) confidence-based gating uses the model's own self-report as the trigger signal, the
same "two optimists agreeing" problem. The playbook's Stage 6 (σ-band / confidence-gated
autonomous invocation) is structurally the same shape as recurrence #4 — a governance runtime
generalizing gates from "irreversible actions" to "every reasoning event," justified as safe
because a human isn't needed for the qualifying signal itself. It was declined for the same two
reasons, not a new one invented for this playbook specifically.

## Deliberately not shipped (reaffirmed, this pass)

- **Stage 6's autonomous σ-band-triggered invocation** — `docs/reference/operating-model.md:100`
  (corrected 2026-09-28; was `:98`, see the line-number note under Finding 2b) + ADR
  0006/0009/0011, all citing the same no-autonomous-launch invariant. **Declined on
  evidence, reconfirmed by independent 2026 external research on self-preference bias, not
  weakened by it.**
- **Reopening ADR 0011's scheduled `recursive-improve`** — no material change to the underlying
  trade-off has occurred; its own revisit trigger (an ADR-0006/0009-level reversal) has not fired.

## Open questions / recommended small fixes (not made in this read-only pass)

> **Status (2026-09-28, later same day):** all three items below were fixed in commit `d4d9c4e1`
> ("docs: fix phantom crux citation + uncited overclaim + ADR-0009 stale header") — left as-written
> below for the historical record of what this pass recommended, not because they're still open.

- **Fix the phantom citation**: replace `agent-loop-verifier-crux.md` with
  `docs/reference/operating-model.md` ("The maker never grades its own work") across the ~10
  `docs/research/*.md` files that cite it — these are frozen research docs (CLAUDE.md's own
  hygiene-sweep exemption), so this is an in-place dated correction note per file, not a rewrite,
  matching the repo's existing frozen-dir correction convention.
- **Fix the uncited magnitude claim**: reword `operating-model.md:57`'s "tops out near chance" to
  drop the specific (unsupported) number, or cite a real source if a hard number is wanted.
- **ADR 0009's stale status header**: it still reads "✅ Accepted and Implemented" though the
  implementation was deleted by a later, unrelated commit. Worth a one-line dated addendum noting
  the code path no longer exists, without touching the historical decision text itself.
- **Revisit only if**: Anthropic or Claude Code ships a feature that lets a model originate a new
  session/process without a prior operator action (not `/goal`/`/loop`, which stay session-scoped
  and operator-started), or the operator explicitly decides to reverse the no-model-self-launch
  invariant itself at the ADR 0006/0009 level. Neither has happened; re-reading the same playbook
  article again without one of these two triggers would be re-litigating a settled question, not
  drilling into new evidence.

> **Correction (2026-09-28, later same day):** the second trigger fired. The operator explicitly
> decided to reverse the no-model-self-launch invariant, and `docs/adr/0004-operator-authorized-
> routine-self-launch.md` is that reversal — drafted per this doc's own Method going through
> ADR 0006/0009's actual precedent rather than a capability argument, and gated on the same
> mandatory multi-reviewer adversarial pass ADR 0009 and ADR 0011's revisit trigger both require
> before any implementation. This correction note exists so a future reader of this "neither has
> happened" line isn't misled; it does not change anything else this document concluded.

<!-- Reserved: a later pass appends a dated correction here, never rewrites the sections above. -->
