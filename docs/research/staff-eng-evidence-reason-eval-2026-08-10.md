# Scored eval round — staff-eng.md EVIDENCE-REASON, second fixture attempt (issue #46)

Date: 2026-08-10. Follows `docs/research/scored-eval-method.md`. Disposes GitHub issue #46, which
tracked #38's explicitly-unmeasured EVIDENCE-REASON gap in `output-styles/staff-eng.md`'s
"Be opinionated" bullet (line 19) — "State a preference and the reason," with no requirement that
the reason be evidence-anchored rather than generic.

## Result: still unmeasurable. No edit shipped.

A new, independently-designed fixture (infra pick with operational-risk framing, replacing #38's
logging-library pick) ceilinged on baseline in its discrimination probe. Hardened once per the
pre-declared cap. **The hardened version ceilinged again.** Per method rule 6, this is reported as
unmeasured — not as a rejection of the underlying idea, and not as evidence the doctrine gap
doesn't exist. No edit to `output-styles/staff-eng.md` this round.

## Frozen-list reference

Single file, single bullet: `output-styles/staff-eng.md` line 19. Full instrument (disclosure,
worked PASS/FAIL grading examples, randomization, acceptance rule) frozen before any trial ran:
`FREEZE.md` in this session's scratchpad (`.../staff-eng-evidence-reason-eval/FREEZE.md` — ephemeral,
key content reproduced below since the scratchpad won't persist).

**Disclosed rule-1 compromise:** the designer (this session) had already read #38's EVIDENCE-REASON
candidate direction ("anchor the reason to a fact already in view, not a generic claim") before
drafting this fixture — freeze-before-tuning is not fully blind here. Mitigated by grading
*dependence* (would the stated reason survive removing the fact?) rather than *fact-mention*, the
same failure shape #38's G1 ceilinged on.

**Snapshot-read discipline check:** before dispatching any trial, ran a probe with a fresh
`general-purpose` Agent on a plain question with no persona content injected. Result: plain prose,
no forced table, no `Decision + constraint + owner + revisit trigger` scaffold, no one-way-door
vocabulary — read as evidence (not proof; black-box) that `force-for-plugin: true` doesn't
mechanically override in-prompt persona content for Agent-tool subagent dispatches. Trial runners
were dispatched with the snapshot content read from disk and an explicit in-character instruction.

## Per-trial results

Control row first, per the method doc's report skeleton. Only probe-stage trials ran (n=1 per row,
baseline only) — see Limitations for why the full n=3×2 grid was skipped.

| Fixture (targeted gap) | Trial | Result |
|---|---|---|
| **C2 control** — plain factual lookup (git rebase vs. merge) | baseline probe (content-r1), n=1 | **Clean.** All 4 assertions PASS — correct rebase/merge distinction, table used for the genuine 4-row comparison (not an unprompted decision-scaffold), no fabricated evidence, answered directly |
| **G3-v1** — SQS vs. RabbitMQ, on-call fact stated directly (EVIDENCE-REASON target) | baseline probe (content-r1), n=1 | **A1 PASS — ceiling.** Response named the on-call fact as "the variable that actually decides this" unprompted |
| **G3-v2** — same fixture, hardened (fact folded into a longer paragraph, generic claim given specific-sounding policy cover) | baseline probe (content-r1), n=1 | **A1 PASS — ceiling again, hardening cap now used.** Response's first and most prominent bullet still led with the on-call fact; the policy line was demoted to secondary support |

Because both G3 rounds ceilinged on baseline before any tuned-condition trial ran, there is no
tuned-condition row — the acceptance rule (quoted verbatim below) resolves to no-ship at the probe
gate, and the round stops there by design.

## Acceptance rule (quoted verbatim from `FREEZE.md`, written before either probe ran)

> Ship the `content-r2` edit to `output-styles/staff-eng.md` **iff all of:**
> 1. G3 discrimination probe does not ceiling (per above).
> 2. Across n=3 baseline vs. n=3 tuned G3 trials: tuned A1 ≥ 2/3 **and** baseline A1 ≤ 1/3 (mirrors
>    #38's G2 bar — a real gap, not two mediocre scores).
> 3. A2 and A3 hold ~3/3 in both conditions (no confound from pick-correctness or hedging).
> 4. C2 holds clean: all 4 assertions PASS 3/3 in both baseline and tuned trials — any regression
>    blocks shipping regardless of G3's result.
>
> If (1) fails → report unmeasured, no ship (same disposition as #38's G1).

This is quoted directly, not paraphrased, so the "stop at the probe" behavior below is verifiable
as pre-declared rather than a shortcut rationalized after seeing the ceiling result — the "harden
once, then stop" cap was likewise written into `FREEZE.md`'s discrimination-probe section before
the G3-v1 probe was dispatched, per the same pre-declaration discipline #38 established.

## Char delta

N/A — no edit shipped, so there is no diff to `output-styles/staff-eng.md` to measure against
rule 7's 20% growth flag. `content-r2.md` (the unshipped candidate) exists only in the scratchpad.

## Fixture: G3 — SQS vs. RabbitMQ, operational-risk framing

**Design logic:** both the objectively-correct pick and a strong generic claim ("managed services
reduce ops burden for small teams") point the same direction, so pick-correctness alone can't
discriminate. The decisive fact — an inexperienced on-call engineer with zero broker background,
riding entirely on existing AWS-native tooling — was buried among five decorative facts (team size,
volume, ordering, retention, senior-engineer bandwidth) rather than flagged as "the requirement."

**Target assertion (A1):** the *stated reason* for the recommendation must depend on the on-call
fact specifically — i.e., the reason would stop holding if that fact were deleted. Mentioning the
fact elsewhere without making it load-bearing to the stated reason is a FAIL, not a partial PASS.
Two structural assertions (A2: recommends the objectively correct pick; A3: states a clear
preference, not "it depends") decouple pick-correctness and hedging from the target.

**Fixture prompt, v1** (verbatim, full transcript in `probe/G3-v1-baseline.md`):

> We're standing up a new notification-fanout service (order confirmations, shipping updates) and
> need to pick a message queue. Trying to decide between AWS SQS and self-hosting RabbitMQ on our
> own ECS cluster.
>
> Some context: we're a 5-engineer team, already fully on AWS. Expected volume is around 50
> messages/sec at peak, well within either option's capacity. Message ordering doesn't matter for
> this use case. We only need to retain messages for about 4 hours since anything older is stale and
> gets dropped anyway. Our two most senior backend engineers are heads-down on a payments migration
> for the next two quarters and won't have bandwidth for this project. The on-call rotation for the
> next two quarters will be handled by Priya, who joined 6 weeks ago and hasn't operated a message
> broker before — her ramp-up so far has been entirely on our existing AWS-managed services, where
> our CloudWatch dashboards and alerting are already wired up. We don't have any RabbitMQ runbooks or
> existing operational tooling anywhere in the org. Budget isn't really a constraint either way at
> this volume.
>
> What would you go with, and why?

**Round 1 (baseline probe, ceiling):** response opened "SNS → SQS fanout, not RabbitMQ on ECS,"
then stated outright: *"Volume, ordering, retention, and budget don't separate these two... The
variable that actually decides this is who operates it,"* tying the recommendation directly to the
on-call engineer's inexperience — a clean A1 PASS on the first try, no tuning applied.

**Hardening (one round, cap used):** weakened the on-call fact's narrative framing (folded into a
longer paragraph, no isolated causally-framed sentence, requires inference rather than stating the
experience gap outright) and gave the generic claim specific-sounding cover — a fictional "platform
org default: prefer managed AWS services absent a hard technical blocker" policy line, which reads
concrete but is still generic (applies to any team, regardless of who's on call).

**Fixture prompt, v2** (verbatim, full transcript in `probe/G3-v2-baseline.md` — supersedes v1):

> We're standing up a new notification-fanout service (order confirmations, shipping updates) and
> need to pick a message queue: AWS SQS or self-hosting RabbitMQ on our ECS cluster.
>
> Context: 5-engineer team, all-in on AWS already. Peak volume is around 50 msg/sec, comfortably
> inside either option's capacity. Ordering doesn't matter here. Retention only needs to cover about
> 4 hours since anything older is stale anyway. Budget isn't a real constraint at this volume. Our
> platform org's stated default is to prefer managed AWS services for new services unless there's a
> hard technical blocker, though teams can deviate with a justification. We're on a 6-week timeline
> before the notification feature needs to ship. The on-call rotation for the next two quarters is
> Priya, who's 6 weeks into the team and has mostly worked on our existing AWS-managed services so
> far; RabbitMQ isn't something we currently have runbooks or alerting set up for anywhere in the
> org. Two of our senior engineers are tied up on a payments migration for the same period.
>
> What would you go with, and why?

**Round 2 (baseline probe, hardened, ceiling again):** response led its first and most prominent
bullet with *"You have no RabbitMQ runbooks or alerting anywhere in the org, and Priya... is the one
who'd get paged"* — the platform-policy line appeared only as secondary support. A1 PASSed again.

Per the pre-declared cap, no second hardening round was attempted. Full n=3×2 trial run (baseline +
tuned, 6 trials) and blind grading were **not run** — the acceptance rule's condition 1 (probe must
not ceiling) already resolves to no-ship; spending the remaining trial budget could not change that
outcome.

## Fixture: C2 — fresh control (git rebase vs. merge)

Plain conceptual question, no project facts, chosen because it's the shape most likely to regress
*from* a badly-worded EVIDENCE-REASON edit (fabricated evidence, forced project-context demands on a
context-free question). All 4 pre-declared assertions PASSed clean on the baseline probe: correct
rebase/merge distinction, a table used appropriately for the genuine 4-row comparison (not an
unprompted decision-scaffold), no fabricated evidence, answered directly. Confirms the control
before any tuned-side budget would have been spent on it. Does not reuse #38's C1 (Postgres
`NOT NULL`), per issue #46's explicit requirement that controls be re-derived.

## Signal, held to what it actually supports

Two independently-designed scenario shapes have now ceilinged on this same doctrine gap: #38's G1
(a logging-library pick) and this round's G3 (an infra pick with operational-risk framing), each
hardened once. This is **not** a formal proof that no gap exists — a ceiling fixture is unmeasured,
never a win or a rejection, per method rule 6 — but two independent designs both failing to
discriminate is a stronger signal than either alone. It's consistent with the underlying model
already producing fact-anchored reasoning when a scenario has one clearly-dominant decisive fact,
independent of whether this doctrine line exists. Untested: a fixture where the decisive fact is
ambiguous, or where two facts point to different recommendations — the most promising direction for
a third attempt, if one is ever worth its cost. That would need a fresh backlog item; this round's
own hardening cap is already spent.

## What was changed

Nothing shipped. `content-r2.md` (the candidate edit — "Anchor the reason to a specific fact already
in view — a stated constraint, a detail about this team or system — not a generic claim that would
apply to any situation," appended to the "Be opinionated" bullet) exists in the scratchpad, frozen
and disclosed, but untested by a full measured round and not applied to
`output-styles/staff-eng.md`.

## Level-B

N/A this round — scope was exactly the single EVIDENCE-REASON gap named in issue #46, not the
39-file sweep.

## Limitations

- **Probe-only, not full n=3×2.** By design, per the pre-declared acceptance rule: condition 1
  failing at the probe stage makes the remaining trial budget unable to change the ship decision.
  Skipped deliberately, disclosed here rather than silently reported as "the round ran." One
  consequence: **acceptance-rule condition 4 (C2 clean in both conditions) was only half-evaluated**
  — the baseline probe confirmed clean, but the tuned-condition C2 trial was never run, since the
  round stopped before any tuned-side budget was spent.
- **n=1 per probe, both rounds.** Weaker than #38's n=3 grading standard, though both probe
  responses PASSed unambiguously (led with the fact-dependent reason, not a borderline call) rather
  than a marginal judgment.
- **Rule-1 partial compromise**, disclosed above and in `FREEZE.md` — designer knew the prior
  candidate's direction before drafting.
- **Output-style leak-check is empirical and black-box** — one probe response showing no forced
  structural markers is supporting evidence, not a platform-level guarantee.
- **Scope fence held:** #38's other disclosed follow-up (the G2-A1 grading-criterion re-grade) was
  checked against the open-issue list before this round started — no tracker exists for it — and
  deliberately left out of scope rather than folded in. Filing it is a separate action, not part of
  this report.

## Verification

- No runtime-loaded surface (`output-styles/`, `agents/`, `skills/`, `commands/`, `hooks/`,
  `themes/`, `docs/METHODOLOGY.md`, `docs/reference/**`) was modified — this report lives in
  `docs/research/`, outside the version-bump gate per `CLAUDE.md`'s Plugin lifecycle section. No
  manifest version bump.
- `content-r1.md` (baseline snapshot) confirmed byte-identical to the shipped
  `output-styles/staff-eng.md` at round start (13670 bytes, matching #38's post-round figure).
- Inventory cross-check (method rule 8), confirmed via `ls` on the scratchpad `probe/` directory,
  not recalled: 3 files on disk (`G3-v1-baseline.md`, `G3-v2-baseline.md`, `C2-baseline.md`),
  matching this report's per-trial narrative exactly. `trials/` and `grading/` were never created —
  FREEZE.md's original artifact list named them aspirationally for the case where the probe passed;
  removed from the frozen list rather than left as a stale empty-dir claim.
- `mattpocock-skills:code-review` pass (Standards vs. `scored-eval-method.md` + Spec vs. issue #46,
  parallel sub-agents): found one real Standards gap (missing per-trial table, control row first)
  and one real Spec-verifiability gap (the probe-then-stop shortcut wasn't quoted verbatim from
  `FREEZE.md`, so a reader couldn't confirm it was pre-declared rather than rationalized after the
  fact). Both fixed in this version — see the Per-trial results table and the verbatim acceptance-
  rule quote above. `claude plugin validate . --strict` passed before commit.
