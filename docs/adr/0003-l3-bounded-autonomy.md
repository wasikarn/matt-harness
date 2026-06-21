# ADR 0003: L3 bounded autonomy — human-gated by run + push, not by mutation

- **Status**: Accepted — supersedes the *L2-only architectural decision* of [ADR 0002](0002-autonomy-invariant.md). ADR 0002 remains the canonical record of the L2 era and its reasoning; this ADR does not delete or rewrite it.
- **Date**: 2026-06-21
- **Decider**: Owner

## Context

[ADR 0002](0002-autonomy-invariant.md) adopted **L2** (hooked, human gate per
mutation) as the harness's *only* loop architecture and recorded that decision
as **irreversible** — "will not be reopened on a capability argument." This ADR
is the owner consciously superseding that architectural decision.

**Not on a capability argument.** The models did not "get good enough" — ADR
0002 forecloses that path and this ADR honors the foreclosure. This is a
**telos change**: the owner now wants the harness to do as much as possible
unattended *within an approved run*, with the human stepping out of the
per-mutation loop. ADR 0002's judgment-preservation thesis assumed the owner
*wanted* per-mutation control; the owner is now choosing a different operating
point, with eyes open and with compensating controls.

ADR 0002 anticipated this exact move — a standing consent that covers multiple
future mutations — and rejected it (§Rejected, "Mid-session system-message as
standing consent"). This ADR does not pretend that rejection away. §Reconciliation
below quotes it verbatim and answers it. Per the owner's instruction, ADR 0002
stays in place **append-only**; this ADR is the canonical record for L3.

> **Note — two different "L"s.** This ADR concerns **autonomy levels**
> (L1/L2/L3/L4 = how far the human is from the mutation loop). That is a
> *different axis* from the **context tiers** (L1/L2/L3 = doctrine resident /
> on-demand / escape-hatch) in `CLAUDE.md`. Same letters, unrelated meanings.

## Decision

Adopt **L3 bounded autonomy** as an **opt-in** loop architecture, gated behind
`KBG_AUTONOMY_L3=1` (**default OFF** — with the flag unset, the harness behaves
exactly as the L2 record describes, and `recursive-improve --auto` refuses to
run). **L4** (no human gate at all) remains rejected on ADR 0002's
principle-bound grounds.

Under L3, the human gate moves from **per-mutation** to **two gates per run**:

- **Gate 1 — launch approval (human).** The human approves a plan + caps, sets
  `KBG_AUTONOMY_L3=1`, and starts `recursive-improve --auto`. This *is* the
  per-run standing consent ADR 0002 rejected; §Reconciliation records why it is
  now safe to accept.
- **In-loop check — computational, not a gate-by-a-mind.** Each cycle's check is
  the **gauntlet** (`scripts/run-gauntlet.sh`: plugin-validate + audit 0C/0W +
  critical-hooks + eval-gate) — deterministic code, **not** a model and **not**
  a human. Green → keep the local commit; red → `git reset --hard` to the
  pre-cycle tag. This is deliberately **not** the model-as-gate ADR 0002
  rejected: no LLM decides "done enough."
- **Gate 2 — pre-push review (human).** The loop stops at a cap with N **local**
  commits and **never pushes**. The human reviews the batch (the
  `session-audit-trail.md` artifact + a maker≠checker `kbg:review-pr` pass), then
  pushes. A computational **push-gate** denies `git push` / `gh pr (create|merge)`
  / `git config *hooksPath` while a run has unreviewed commits, until
  `KBG_L3_REVIEW_DONE=1`.

### The one real relaxation (stated honestly)

L3 trades away the **per-mutation** judgment check. Under L2 the operator
inspected *every* mutation for alignment-with-intent before it landed. Under L3
a **green-but-misaligned** change can land in a *local* commit and is caught
only at Gate 2. We accept this **only because the relaxed boundary is fully
reversible**: local commits never left the machine and are recoverable
(`git reset` to the pre-cycle tag). The judgment gate is **preserved intact at
the boundary that is not reversible** — the push. ADR 0002's thesis ("the
operator's judgment is the load-bearing input") is kept where it is load-bearing
(outward/irreversible acts) and relaxed only where reversibility makes
per-mutation inspection recoverable after the fact.

### Three rails replace the per-mutation gate

1. **Push stays human-gated** (computational push-gate; Gate 2). The
   irreversible/outward boundary keeps a human.
2. **Cage-denylist** (enforced in code **at pre-Act check time**, every Act). The
   loop may never edit its own safety surface — the gates, the gauntlet, the
   audit, the doctrine, `.git/config`, **and the cage denylist + guard
   themselves**. The denylist is checked *before* a candidate is applied, so an
   Act targeting any cage path (the denylist or the guard included) is **denied
   before it lands** — the loop cannot edit the cage to escape the cage. Touch one
   → abort the cycle. **Deny-by-default**; a new CRIT audit check verifies the
   cage covers the whole safety surface (not a hand-maintained allowlist).
3. **Model can't self-start.** `recursive-improve` keeps
   `disable-model-invocation: true` (audit #32). L3 is unattended *within* a
   human-started run, **never self-launching**.

Caps are enforced **in code** (`scripts/l3-loop-guard.py`), not prose:
`--max-runs` (**default 3**), `--max-duration`, `--fail-streak`, `--dirty-abort`.
`KBG_AUTONOMY_L3` is captured at process start and **immutable for the run** (the
loop cannot self-elevate scope mid-run).

> **`--max-cost` — deferred to Slice 2 (conscious deviation, 2026-06-21).** The
> build plan listed `--max-cost` as a Slice-1 cap, but a plain script has no honest
> local token-cost signal and fabricating one would violate METHODOLOGY (no fake
> metrics). `--max-runs` + `--max-duration` are the hard, locally-observable bounds
> and bound a run regardless of cost; real cost-drift estimation ships with the
> Slice-2 learning engine, where the plan's cost-drift PORT already lives.
> `scripts/l3-loop-guard.py` records this rationale in-file.

### Implementation status (flag OFF == L2 until the ship slice)

This ADR records an **accepted decision**. The enforcement machinery was built in a
**separate, gauntlet-gated slice** (Slice 1) *after* this doctrine slice, and is
**committed locally and gauntlet-green** (2026-06-21): `scripts/l3-loop-guard.py`,
the cage-denylist, the computational push-gate, the `--auto` body, and audit checks
**#43/#44** (plus **#45**, reviewer read-only). It is **not yet shipped to the
plugin cache**.

> **Slice-1 live dry-run (2026-06-22) — found + fixed at v0.3.10.** The
> "gauntlet-green" above was only ever measured with the flag **OFF**. The first
> real `--auto` dry-run (flag ON) surfaced two blocking defects: (1) the in-loop
> gauntlet gate **failed under `KBG_AUTONOMY_L3=1`** — disable-mechanism tests
> broke on `_lib.sh` L3 immunity, so every cycle went red and the loop could never
> keep a commit; (2) the loop's `git reset --hard <l3-precycle>` rollback was
> denied by `block-dangerous-git`. Both fixed at v0.3.10 (hermetic test baseline in
> `test-critical-hooks.sh` + a full-anchored, flag-scoped rollback carve-out in
> `block-dangerous-git.sh`); critical-hooks is now **433/0 under the flag**.

- `KBG_AUTONOMY_L3` stays **unset** by default, so `recursive-improve --auto`
  **refuses to run** and the harness behaves exactly as the L2 record describes —
  the flag is inert until the operator sets it on a shipped, green cage.
- Enforcement points: audit **#32** (model-can't-self-start), **#41** (doctrine-gate
  seam), and the L3 checks **#43/#44**.

**Hardening-before-enable:** the entire cage (denylist + guard + push-gate +
profile-off immunity + flag immutability + all new audit checks + tests) must be
committed and gauntlet-green **before** the first `KBG_AUTONOMY_L3=1` run. The
flag is never set on a half-built cage.

## Reconciliation with ADR 0002 §Rejected — "standing consent"

ADR 0002 rejected the exact mechanism L3 relies on. Quoted verbatim:

> **Mid-session system-message as standing consent.** Some prompting guides
> suggest a mid-session `system` message that refreshes the operator's intent or
> grants standing consent to continue iterating. Rejected: it would function as
> a deferred human gate, allowing a single approval to cover multiple future
> mutations. The invariant requires a human gate *per mutation*, not per session
> launch.

We now accept per-run standing consent. The rejection was **correct for L2's
assumptions** and is *answered*, not overruled, by three things ADR 0002's L2
design did not have:

1. **A reversibility envelope.** ADR 0002 treated all mutations alike. L3
   distinguishes *local commit* (reversible) from *push* (not). Standing consent
   is granted **only over the reversible set**; the per-mutation gate is
   **retained** over the irreversible one (Gate 2). "A single approval covering
   multiple future mutations" is acceptable precisely when every one of those
   mutations is recoverable and the batch faces a real review before it leaves
   the machine.
2. **A non-model in-loop gate.** ADR 0002's L3 rejection was specifically of
   *model-as-gate* ("plausibility of completion" substituting for
   "alignment with intent"). L3-kbg's in-loop gate is the **computational
   gauntlet**, not a model. Alignment-with-intent is still judged by the
   operator — *relocated* to Gate 2, not *delegated* to a model.
3. **A bounded, reviewable batch.** `--max-runs` defaults to **3** so the
   standing consent covers a batch the operator can still hold in working memory
   at Gate 2. This is a reviewability bound, not an operational-comfort knob.

**Residual risk, stated plainly:** a green-but-misaligned change survives until
Gate 2. The compensating control is the maker≠checker review at Gate 2 (fresh
context, nothing to defend) plus the small batch size. If that residual is
unacceptable for a given run, **don't set the flag** — L2 is the default and the
per-mutation gate is one keystroke away.

### Reversibility boundary — what "reversible" does and does not cover

The reversibility envelope covers the **git tree**: local commits are recovered
by `git reset --hard` to the pre-cycle tag. It does **not** automatically cover
**side effects** — a candidate that runs `npm install`, writes outside the repo,
mutates `.env`, starts a process, or makes a network call leaves residue
`git reset` will not undo. Two things keep the claim honest:

- **The loop's Act is scoped to harness-file edits.** `recursive-improve`
  candidates are bounded to ≤ 5 files / ≤ 200 lines of harness config / doctrine /
  scripts (the skill's existing scope guard) — not running services. A candidate
  that needs to exec a stateful, irreversible command is *out of scope* for the
  loop: it is surfaced for the human, not auto-applied.
- **Side-effect reversal is operator judgment at Gate 2, not a code claim.** The
  harness cannot detect arbitrary side effects after the fact, so the honest
  statement is narrow: *git-tree* mutations are reversible; anything a cycle did
  outside the tree is the operator's to confirm clean before pushing.

### Crash / partial-cycle robustness

L3 has **no auto-resume** — auto-resume would be a self-start, which the invariant
forbids. Cycles are **independent**: each is observe → act → gauntlet →
keep-or-reset, with no cross-cycle in-memory state. If a cycle dies mid-flight
(laptop closed, network drop) the process simply stops; the next *human* launch
starts fresh, and `--dirty-abort` refuses to start on a non-clean tree (outside
`.scratch/`). A half-written cycle leaves either nothing (reset to the pre-cycle
tag) or a clean local commit — never a resumable in-memory batch.

## L3 evolution of the 5 enforcement surfaces

ADR 0002 §Decision named 5 surfaces. **None is deleted.** Each gains an explicit
"L2 default / L3 when flag set" distinction:

| # | Surface | L2 (default) | L3 (flag set) |
|---|---|---|---|
| 1 | Canonical home | ADR 0002 | **ADR 0003** (this doc); 0002 stays the L2 record |
| 2 | METHODOLOGY Rule 4 | gate per mutation | "every loop terminates at a human gate" still holds — the loop terminates at the cap; the human reviews + pushes (Gate 2). Per-batch, not per-mutation. |
| 3 | recursive-improve skill | Step 3 ASK per mutation | `disable-model-invocation: true` **unchanged** (model can't self-start). `--auto` runs cycles inside the Gate-1 plan; Step 3 becomes "propose within the approved plan," not a per-mutation ASK. Default (non-`--auto`) keeps the per-mutation ASK. |
| 4 | Decay-cadence hard guard | never auto-prune | **unchanged** — the loop never auto-prunes components (the cage forbids touching the decay surface). |
| 5 | Deterministic audit | #32 (flag present) | #32 **unchanged + hardened** (line-independent grep). New CRIT checks #43+ guard the cage, push-gate, flag-respect, and gate profile-immunity. |

## Two-gate model (summary)

```
Gate 1 (human)            in-loop (computational)             Gate 2 (human)
approve plan + caps    →  cycle: observe → act → gauntlet  →  review batch
set KBG_AUTONOMY_L3=1      green: keep local commit            (audit-trail + kbg:review-pr)
run --auto                red:   reset --hard to pre-tag       set KBG_L3_REVIEW_DONE=1
                          stop at cap (commits LOCAL only)     push
```

There is **no per-cycle human gate** and **no model gate** anywhere in this
picture. maker≠checker (`kbg:review-pr`) is a **Gate-2 post-run** activity on the
assembled batch — fresh context, after the loop ends, never inside a cycle.
(Inside a cycle it would be a model judging the model's own work — the
LLM-judge-circularity failure `CLAUDE.md` warns about.)

## What stays rejected

- **L4 (model is its own gate / verifier / stopper).** Rejected on ADR 0002's
  principle-bound grounds, unchanged. L3's Gate 2 is the line.
- **Model-as-gate inside the loop.** The in-loop gate is computational, never
  inferential. An LLM "done enough" judge would be L4 by the back door.
- **Auto-push / auto-merge.** The push-gate is the hard boundary; no run pushes
  itself.
- **Timer / cron self-launch** (`/loop`, `CronCreate`, Evo meta-loop). L3 is
  human-*kicked*; it does not schedule itself.
- **The loop self-editing doctrine or ADRs.** The cage forbids it. The loop may
  *propose* a new ADR or doctrine change via its Step-3 output (a candidate for
  the human at Gate 2); it may never write one itself.

## Reversibility of this ADR

Unlike ADR 0002's "irreversible" self-description, **ADR 0003 is explicitly
reversible by the same mechanism that created it**: an owner-authored,
human-gated ADR. Moving to L4 would require an **ADR 0004** superseding this one
— it cannot be reached by setting a flag, and it cannot be reached by the loop
amending this file (the cage forbids that). The autonomy *ratchet* turns only by
a deliberate, recorded, human decision.

## Verification

**Today (this doctrine slice):**
- Audit **#32 / #34 / #41 green**; `recursive-improve` keeps
  `disable-model-invocation: true`; `--auto` is not yet wired and the flag is
  inert. Behavior identical to the L2 record.
- **Doctrine coherence (verified):** CONTEXT.md, CLAUDE.md, METHODOLOGY.md §4,
  `recursive-improve/SKILL.md`, `docs/harness-decay-cadence.md`, and README.md
  all name ADR 0003 with the L2/L3 distinction; no dangling cross-reference.

**Slice 1 (when the machinery ships — acceptance criteria):**
- **Flag OFF (default):** behavior identical to the L2 record; `--auto` refuses
  to run.
- **Flag ON, dry run:** local commits land with **no push**; a cap stops the run;
  a candidate touching a cage path **aborts the cycle at the pre-Act check**; the
  push-gate denies `git push` until `KBG_L3_REVIEW_DONE=1`; the run-id appears in
  the journal and in `session-audit-trail.md`.
- **Cage completeness (new CRIT audit check #43+):** fails if the denylist does
  not cover the full safety surface (`hooks/`, `tests/hooks/runners/`,
  `audit.sh`, `skills/_lib/`, the gauntlet's transitive sources, `eval/datasets/`,
  all doctrine, `.git/config`, **and the cage denylist + guard themselves**).

This ADR supersedes ADR 0002's **architectural** decision (L2-only). It does
**not** supersede ADR 0002's **principle** — operator judgment is the
load-bearing input — which L3 preserves at the push boundary and in the
no-model-gate / no-self-start rails.
