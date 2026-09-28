---
status: proposed
---

# Operator-authorized Routine self-launch (narrow reversal of the no-model-self-launch invariant)

`docs/adr/` restarted numbering below the legacy `docs/research/adr-0006/0009/0011-*.md` records
(the pre-rebuild set; cite those by full path, never by a bare "ADR 0006" that could be confused
with a file under this directory). This ADR is the fourth attempt to touch the no-model-
self-launch invariant those three establish, and the third rejection's own revisit trigger names
exactly the condition that licenses trying again: *"a multi-reviewer adversarial pass before any
implementation, not a single drafting session's say-so"* (`adr-0011-scheduled-recursive-improve-
invocation.md`). This document is that draft; the adversarial pass it requires (§6) has not yet
run, so `status: proposed` is not a formality here — nothing downstream of this ADR may treat it
as decided.

## 1. Decision and basis

**The operator has explicitly, directly instructed this reversal** — not a capability argument,
not a plausibility argument, not this document independently concluding the invariant should
move. `docs/research/autonomous-loop-doctrine-drilldown-2026-09-28.md` traced the full history of
why the invariant exists and found it structurally sound as of 2026 external research; that
conclusion is unchanged by this ADR. What changed is that the person who owns the decision said
to reverse it anyway, for reasons outside this repo's own evidence base (matching the article this
session originated from, "the AI-Native SDLC playbook"'s Stage 6 framing) — and `ADR 0006`
(`docs/research/`, pre-rebuild) already states plainly that reopening this invariant **on a
capability argument is still foreclosed**. Claude Code's Routines feature (§3) is named below only
as *mechanism* — what becomes possible once the operator's decision is implemented — never as the
*reason* for the decision. If this ADR is ever cited as "Routines exists, therefore reversed," that
citation is wrong; the correct citation is "the operator said so."

## 2. Superseded / retained

**Superseded, narrowly:** `ADR 0006`/`ADR 0009`/`ADR 0011`'s self-launch clause is superseded
*only* for the specific Routine path described in §3 below — a deterministically-triggered,
investigate-and-PR-only cloud session. Nothing else about those three decisions moves.

**Retained, explicitly, unchanged:**
- **Maker ≠ checker** (`docs/reference/operating-model.md` §2) — a Routine's own output is never
  self-graded; whatever review gate a PR normally goes through (`mattpocock-skills:code-review`,
  the gauntlet/harness-audit CI checks) applies to a Routine-opened PR identically to a
  human-opened one.
- **No model-confidence-as-trigger** — the same "two optimists agreeing" argument
  `docs/research/autonomous-loop-doctrine-drilldown-2026-09-28.md` Finding 4 documents (4
  independent same-day rejections of confidence/criticality-gated runtimes, 2026-07-01) applies
  with full force to any Routine trigger design. §3 names only deterministic triggers for exactly
  this reason.
- **No auto-merge** — a Routine may open a PR; it may never merge one. This is retained from
  Phase B's own design (`docs/reference/branching-model.md`), not newly invented here.
- **No push to `develop`** — Routines are mechanically restricted to `claude/`-prefixed branches
  and rejected on protected branches by the platform itself (not an mh-side control — see §4), and
  `develop` now carries branch protection (Phase B).
- **No custom launchd/cron self-start machinery** — composer-not-creator
  (`docs/reference/composer-not-creator.md`) still applies; a Routine is a platform-native,
  already-installed mechanism, not a bespoke one this repo builds and maintains. The retired L4
  autonomy-ladder machinery (`docs/reference/repo-gotchas.md`'s reference to
  `l4-machinery-design.md`, archived memory) stays dead — this ADR does not resurrect it or
  anything shaped like it.

## 3. Mechanism, stated honestly

**Trigger:** deterministic only, never a model-computed aggregate or self-report. Candidate
triggers, each already a real, already-emitted signal in this repo: `harness-audit`'s CRIT count
crossing zero, the gauntlet's own exit code, an eval suite's pass rate crossing a fixed threshold,
the gate-verdict journal's `ask`-count over a window. None of these require an LLM to classify
"is this significant" — the boundary condition doctrine research already found for the article's
own σ-band/confidence-gate design (`docs/research/` sessions on grader/scoring mechanisms and
judgment/decision-making mechanisms, dispatched earlier this session specifically to check this):
the article's own gates are fully deterministic threshold crossings or a *separate* adversarial
agent's verdict, never the acting model's own confidence report. That finding is what makes this
mechanism section defensible at all — if the article's gates had turned out to be self-report-
gated, this ADR would not be written this way.

**Two building blocks this repo does not have today, named plainly, not glossed over:**
1. **No rolling-baseline/control-band math exists anywhere in this repo.** A σ-band trigger (mean
   ± N standard deviations over a rolling window) is new subsystem work — a metrics-history store,
   a baseline computation, a drift/threshold check — not a wire-up of something already built.
2. **The metrics that would feed a trigger are local-only** (`~/.local/share/kbg/metrics/
   gate-decisions.jsonl`, `costs.jsonl`, and this repo's own gauntlet/audit exit codes, all on the
   operator's machine). A cloud Routine session cannot read them as they stand today. Either the
   trigger fires from a mechanism a cloud session *can* observe (a scheduled interval, a GitHub
   webhook on a release/PR event — both natively supported by Routines), or this repo's local
   metrics need their own export/sync design before a metrics-driven trigger is buildable at all.
   This ADR does not resolve which; it is a prerequisite for choosing a metrics-driven trigger,
   named so it isn't silently assumed solved.

**Output, unconditionally:** investigate → push to `claude/<slug>` → open a PR → **never merge**.
The PR sits exactly where any other PR sits: subject to the checks Phase B wired (required status
checks on `develop`) and to human review before anyone — human or Routine — merges it.

**Push-confirmation carve-out, named explicitly:** the global "confirm before every push" rule
(`~/.claude/CLAUDE.md`, `# Git`) is written for an interactive session with an operator present to
ask. A Routine session has no operator present by construction — confirmation is structurally
impossible, not merely inconvenient. This ADR carves out exactly one exception: a Routine session
may push unconfirmed, but *only* to a `claude/`-prefixed branch, never to `develop` or any other
branch. This carve-out is the ADR's own explicit grant, not a silent gap in the global rule.

## 4. Enforcement reality

**Stated plainly, not softened:** mh's own PreToolUse/Stop hooks (`hooks/gates/*.py`,
`hooks/hooks.json`) almost certainly do not run inside a cloud Routine session at all. Routines
are a Claude-hosted execution environment, not a local Claude Code CLI invocation with this
repo's plugin loaded the way an interactive session or a `claude --worktree` session is. Every
gate this repo has built — `gate:bash:irrecoverable`'s new `gh pr merge` ask-tier rule (Phase B),
`gate:agent:subagent-spawn-guard`, all of it — assumes a Claude Code session with mh's hooks
wired in. **None of it constrains a Routine.**

What *does* constrain a Routine is the platform's own restriction (Routines push only to
`claude/`-prefixed branches, rejected on protected branches) plus whatever the Routine's own
GitHub credential is scoped to do — which is §5's job, not this section's. Branch protection on
`develop` (Phase B's B5, `enforce_admins: true`, required status checks) blocks a direct push from
*any* credential, Routine or human, admin included short of editing the protection rule itself —
but it does not, and cannot, stop a sufficiently-scoped credential from calling the merge API on a
PR that already passed its checks. That gap is exactly what §5 must close before this ADR could
ever move past `proposed`.

## 5. Credential-scoping design (required before any implementation)

**No implementation may ship until this section's empirical test has actually run and passed.**
Naming an intended scope is not evidence it holds — GitHub's actual API permission semantics are
the ground truth, not this document's expectation of them.

**Recommended default: fork-based flow.** The Routine authenticates as an identity that pushes to
its *own fork* of this repo and opens a PR back to `wasikarn/matt-harness`, the same shape any
external contributor without write access uses. This is structurally different from a scoped
token with write access to the main repo: a fork-based credential never holds write access to
`wasikarn/matt-harness` at all, so it cannot merge into it, full stop — not "is scoped not to,"
but "cannot, because it was never granted write access to this repository in the first place."

**Why a fine-grained PAT scoped to `contents:write` + `pull-requests:write` is not (yet) a viable
alternative:** GitHub's fine-grained PAT permission model does not cleanly separate "can open/push
to a PR branch" from "can merge a PR" the way this design would want — `pull-requests:write`
covers PR-related actions more broadly than this ADR's threat model wants to grant. Until someone
verifies empirically, with a real token of that exact scope, that it genuinely cannot call the
merge endpoint, it stays a rejected candidate, not a pending one.

**Mandatory before `status: accepted`:**
1. Stand up the actual credential (fork-based, or the scoped-PAT alternative if someone later
   proves it safe) and, with a real token of that exact scope, attempt to call the merge endpoint
   against a disposable test PR. Record the result (denied with what error, or — if it
   unexpectedly succeeds — this ADR is not ready and that finding blocks acceptance outright).
2. A budget cap and rate limit on Routine invocations — none exists today in any form.
3. A kill switch: a documented, fast way for the operator to disable every scheduled/triggered
   Routine immediately (at minimum: `/schedule` list + delete, or revoking the Routine's
   credential — whichever is faster to execute under pressure).
4. Alerting on a fired Routine — the operator should learn a Routine ran without having to go
   looking for it.
5. An incident runbook — what to do if a Routine's PR is wrong, if its credential leaks, or if it
   fires more often than intended.

None of items 2-5 ship with this ADR. They are named here as what the eventual implementation
must include, not built now — Phase C is explicitly ADR-drafting and review-scheduling only.

## 6. Cost

Routines are recurring, paid, cloud-hosted sessions — a different cost shape from an interactive
session's usage. This repo has an existing, closely analogous precedent: the earlier decision to
skip `claude-code-action` automated PR review in CI specifically because it needs a paid Anthropic
API secret this repo doesn't carry (Phase B's B4/B5 notes, `docs/reference/codex-integration-map.md`).
**Left open, deliberately** — this is exactly the kind of criterion the adversarial review in §7
should weigh with real numbers (expected trigger frequency × per-invocation cost), not something
this drafting pass pre-decides by assertion.

## 7. Mandatory adversarial review (this repo's own established reversal protocol)

Matches `ADR 0009`'s precedent (5 fresh-context reviewers + 2 rounds of cross-ADR adversarial
review — the most scrutiny any single decision in this lineage has received) and satisfies
`ADR 0011`'s own revisit trigger verbatim.

**Wave 1 — 5 fresh-context reviewers, main-session-dispatched only** (Rule 13's 5-per-wave cap),
each a distinct lens:
1. **Doctrine-fidelity** — does this ADR actually retain everything §2 claims it retains, checked
   against the live repo, not against this document's own assertions?
2. **Steelman-against** — the strongest case this ADR should not be accepted at all, argued in
   good faith.
3. **Implementation-feasibility** — is §3's mechanism (deterministic triggers, the two named
   missing building blocks) actually buildable as described, or does it hide a third missing
   piece?
4. **Bypass/incident** — concretely, how could a Routine (or its credential, or its trigger) be
   made to do something this ADR forbids, despite §4/§5's stated controls?
5. **Gate-sufficiency** — do Phase B's existing gates (branch protection, `gh pr merge` ask-tier)
   plus §5's credential design actually add up to "cannot merge its own PR," or is there a gap
   none of them individually cover?

**Waves 2-3 — cross-ADR adversarial passes** against `ADR 0006`/`ADR 0009`/`ADR 0011` specifically:
does this ADR's narrow supersession in §2 actually hold up against each of those three documents'
own stated reasoning, not just against a summary of them?

**Acceptance criteria:**
- No unresolved REJECT verdict from any wave.
- A REJECT must cite a specific file/behavior/line, not a general objection — an evidence
  standard, not a veto by assertion.
- **Owner and timeout, so this cannot deadlock:** the operator is the named owner for breaking any
  stalemate a REJECT creates; a review wave that has not converged within a reasonable, explicitly
  time-boxed window escalates to the operator for a direct decision rather than looping
  indefinitely.
- Only once every wave's REJECTs are resolved *and* the operator gives explicit sign-off does
  `status: proposed` move to `status: accepted`.

**Explicitly out of scope even after acceptance:** building the actual Routine, its trigger
wiring, or the credential itself is a separate, later, independently-gated piece of work — this
ADR's acceptance authorizes starting that work, it does not constitute having done it.
