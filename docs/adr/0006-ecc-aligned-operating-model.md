# ADR 0006: ECC-aligned operating model — scoped denials, advisory review, operator-as-authority (retires the L2-L5 bounded-autonomy ratchet of 0003/0004/0005)

- **Status**: Accepted
- **Date**: 2026-06-25
- **Decider**: Owner
- **Supersedes**: ADR 0003 (L3 bounded autonomy), ADR 0004 (L4 self-driving), ADR 0005 (L5 auto-push) — for architecture AND operating model. **Preserves (append-only)**: ADR 0002's judgment-preservation principle (the model never authorizes a ship; the operator is the authority at every irreversible boundary), the cage, and `disable-model-invocation: true` on `recursive-improve` (no model self-start).

## Context

ADRs 0003 → 0004 → 0005 built a ratchet: each notch moved the human gate further out (per-mutation → per-run → per-push → removed from push) behind a single opt-in `KBG_AUTONOMY` flag, a computational ship-gate (the gauntlet / `push-gate.sh`), a cage-denylist, and `autonomy_on()` as the shared arming predicate. Step 1 of the retirement (commit 7cabcea, 2026-06-25) already deleted `push-gate.sh` (the blanket-Bash-deny footgun), added `advisory-push-reminder.sh` (ECC-aligned non-blocking review reminder), ported `core.hooksPath` deny into `block-dangerous-git.sh`, and retired ADR 0004's Gate-2 + ADR 0005's L5 ship-gate leg — but explicitly **deferred** the `autonomy_on` predicate, the L4 self-launch machinery, and the L3 `loop-guard` enforcer to "step-2 autonomy-model territory." This ADR IS step 2.

Two facts forced the move:

1. **The ratchet's hard walls were the wrong shape.** `push-gate.sh` blanket-denied ALL Bash during an armed run — a footgun that blocked safe operator tools (`--force-with-lease`, the ECC-allowed safety-checked force) behind the same wall as genuinely destructive commands. ECC's stance is **friction, not a hard wall**: the operator is the authority; the harness *denies* the irrecoverable set computationally and *advises* on the rest. The ratchet's per-level env keys, Gate-2 enforcement, and "telos vs capability" framing justified each notch but produced a gate whose cost (blanket deny, cross-repo CRIT, `gauntlet_run` SHA-bound contract) exceeded its value for a single-operator personal harness that never ran the launchd loop live.

2. **The L4/L5 machinery never ran live.** `scripts/l4/launch.sh` + the launchd plist + `scheduler.conf` were built (Slices 0-4) but the launchd loop was never activated. The entire L3 `loop-guard.py` / cage / `autonomy_on` stack existed to *bound a run that was never unattended*. Retiring the machinery loses no live behavior; it removes dead weight that still costs an audit surface (#31/#32/#43/#44/#48/#49), a test surface (test-ch-l3.sh's 6 unguarded L4 legs), and a prose surface (12+ docs carrying the invariant verbatim).

## Decision

Adopt the **ECC-aligned operating model**: the harness is a **friction layer, not a hard wall**; the operator is the authority at every boundary.

### What dies (retired by this ADR)

- **The ratchet metaphor** — L2/L3/L4/L5 "levels", "Gate 1/2", "telos vs capability", "bounded autonomy", "cage floor" as autonomy concepts.
- **The autonomy flag** — `KBG_AUTONOMY` (and the collapsed `_L3`/`_L4`/`_L5`/`KBG_REVIEW_DONE`/`KBG_L5_SHIP_ALLOWLIST`/`KBG_L3_REVIEW_DONE` keys) retire. There is **no autonomy flag**. The per-repo `.claude/settings.local.json` `env.KBG_AUTONOMY` entry is removed.
- **The arming predicate** — `autonomy_on()` in `hooks/_lib.sh` and `scripts/loop-guard.py` retires (stubbed to `return 1` / deleted). The L3/L4 immunity block in `_lib.sh` (which forced `PROFILE=standard`/`DISABLED=""` while armed) is removed — `CLAUDE_HOOK_PROFILE`/`CLAUDE_DISABLED_HOOKS` honor normally again.
- **The L4 self-launch machinery** — `scripts/l4/**` (launch.sh, launchd plist, scheduler.conf, l4-quality-gate.sh, l4-quality-trial.txt, l4-auto-keep.py, cage-intact.sh, exit-tripwire.sh) is deleted. The launchd loop is decommissioned (it never ran live; the plist is a dark-restart hazard if `KBG_AUTONOMY` were ever set, which it no longer can be).
- **The L3 enforcer** — `scripts/loop-guard.py` is deleted (pure L3; no non-autonomy consumer; `l4-auto-keep.py` imports it and is deleted in the same slice).
- **The L4 defense gates** — `hooks/gates/l4-act-gate.sh` (guarded the launchd plist/kill-file from the L4 loop) and `hooks/post-tool/post-push-tripwire.sh` (witnessed L4-authored pushes that slipped the human Gate-2) are deleted + unwired from `hooks/hooks.json`.
- **The L3 carve-out** — `block-dangerous-git.sh`'s `git reset --hard l3-precycle-*` autonomy carve-out is removed; `git reset --hard` falls through to the blanket deny like any other.
- **The enforced maker≠checker ship-gate** — there is **no computational ship-gate that blocks an owner push**. Ship authorization lives in `block-dangerous-git.sh` **scoped denials** (force-push-to-main, `reset --hard`, `clean -f`, `branch -D`, `--no-verify`, `core.hooksPath`, `commit --amend`, `git rm -r`, `switch --force`) plus `advisory-push-reminder.sh` (non-blocking review reminder). Review is **advisory**, not enforced.
- **The `gauntlet_run` SHA-bound push-leg contract** — `run-gauntlet.sh`'s `gauntlet_run` journal emission is neutralized; its only consumer (`push-gate.sh`) is already gone. `run-gauntlet.sh` itself is RETAINED as the harness's general validation runner (CI + operator + gauntlet).
- **The audit checks** — #31 (autonomy-invariant guardrail, ADR-0002 legs), #32 (ADR-0002 legs + #32b ADR-0004 leg), #43 (L3 cage integrity), #48 (L4 F1-floor), #49 (L4 model-gate) are no-op'd (return 0, header kept for ncheck stability). #44's autonomy legs are re-gated on `run-gauntlet.sh`/`hooks.json` presence (not ADR 0003/0005) so the retained gauntlet's `gauntlet_run`-emit + `core.hooksPath` guards stay live. #50 was already no-op'd in 7cabcea. #52 (review-rigor INFO) retires with its now-moot addendum ADR.

### What lives (preserved by this ADR)

- **Judgment preservation (ADR 0002's principle)** — the model **never** authorizes a ship. It never could; the gate was always computational for the *denial* set and stays so. The model remains veto-only (it can force a rollback; it cannot bless). This is ADR 0002's load-bearing principle, preserved append-only.
- **The cage** — `scripts/cage.txt` is RETAINED as a general **consequential-safety-surface manifest** (drop the L3 framing in comments). `decision-provenance-nudge.sh` keeps reading it as the single source for "caged path" provenance classification — a non-autonomy consumer that would silently degrade if cage.txt were deleted.
- **No model self-start** — `recursive-improve/SKILL.md` keeps `disable-model-invocation: true` (audit #32 surface-3 stays live and passing). The model cannot self-start the improvement loop. (The launchd self-start is gone with the L4 machinery; there is no OS-scheduler self-start either now.)
- **The L2 human-gated improvement ritual** — `recursive-improve` survives as the Observe → Propose → `AskUserQuestion` gate loop (every iteration stops at a human gate before any mutation). The `--auto` (L3) section, the autonomy-invariant preamble's L3/L4 language, the `L4-authored: yes` trailer instruction, and the `launch.sh` reference are stripped.
- **Scoped denials as computational feedforward** — `block-dangerous-git.sh` stays (force-push-to-main/master deny, develop ask, fix/feat allow, `reset --hard` deny, `clean -f` deny, `branch -D` deny, `checkout .`/`restore .` deny, `core.hooksPath` deny, remote-mutation ask) and is **widened to ECC parity** (see Consequences).
- **`advisory-push-reminder.sh`** — the ECC-aligned non-blocking review reminder (added 7cabcea) stays.
- **The gauntlet** — `run-gauntlet.sh` stays as the general validation runner; only the `gauntlet_run` ship-gate emission is dropped.
- **#34 (inferential-FB sensors must not emit permissionDecision)** — hermetic, NOT ADR-gated, KEEPS RUNNING. A real guard against covert-L4 sensor regressions; not autonomy machinery.
- **#45 (reviewer read-only / maker≠checker)** — hermetic, universal, KEEPS RUNNING.
- **#47 (learn-capture advisory-only)** — hermetic; #47b self-retires with `l4-auto-keep.py`.

### The new principle (single sentence)

The harness **denies the irrecoverable set computationally and advises on the rest**; the operator is the authority at every irreversible boundary; there is no autonomy flag, no enforced maker≠checker ship-gate, and no model self-start. The maker≠checker bar stays a **human judgment matched to stakes**, never a hard-coded gate.

## Alternatives weighed

- **Keep the ratchet, just drop the flag default** — rejected: the dead L4 machinery + 6 audit checks + 12 prose copies + 6 unguarded test legs remain a maintenance tax for a loop that never ran.
- **Delete ADRs 0002-0005 outright** — rejected: ADR 0002 is the cited rationale for `disable-model-invocation: true` (audit #32 surface-3 CRITs on its text); deleting orphans #32 and loses the L3/L4/L5 provenance the journal schema + loop-guard cite. ADRs stay append-only with "Superseded by ADR 0006" banners; the *checks* are no-op'd directly (the real master lever, since checks gate on ADR file presence and the files stay).
- **Retire `autonomy_on` but keep the launchd plist as a paused carve-out enabler** — rejected: a scheduled job that could re-arm if `KBG_AUTONOMY` were ever set is a dark-restart hazard, and there is no `KBG_AUTONOMY` to set anymore. Decommission the plist fully.
- **Delete `cage.txt`** — rejected: `decision-provenance-nudge.sh` silently degrades to "nothing is caged" (no `class="caged"` nudge for hooks/adr/ edits). Keep as a safety-surface manifest.

## Consequences

- **Positive:** ~8 deleted files + 6 no-op'd checks + 6 self-skipped test legs + 12 docs swept; one operating model replaces a 4-level ratchet; `--force-with-lease` (the safe operator force) is allowed again; the blanket-Bash-deny footgun class is gone for good.
- **Negative:** the cross-repo CRIT (loosened-brake detection across repos, the one unique protection the L5 push-gate leg provided) is lost; flagged as a candidate pre-commit advisory (carry-forward). The `l3_cycle` / `gauntlet_run` journal events become advisory evidence, not ship-gate inputs (JOURNAL-SCHEMA.md updated).
- **ECC parity gaps closed by this ADR:** (1) a Bash-WIDE destructive gate (`block-dangerous-bash.sh`) for the non-git destructive surface (rm -rf all flag forms, find -exec rm, dd, SQL DDL); (2) `--force-with-lease` allowed (dropped from `FORCE_FLAG_PAT`); (3) git destructive set widened (`commit --amend`, `git rm -r`, `switch --force`, `checkout --force`); (4) `--no-verify`/`-n` hook-bypass blocked on commit/push/merge/rebase/cherry-pick/am; (5) advisory `tmux-reminder` + `commit-quality-reminder` added. (GAP 6 — PostToolUse observe-capture + context-monitor — is optional polish, deferred.)
- **Non-goals (still out of scope):** model self-starting the loop (the launchd self-start is now gone too; there is NO sanctioned self-start), model-authorizing a ship, loop-authored ADRs (cage forbids `docs/adr/**`), cage removal. These four survive from ADR 0002 and remain principle-bounded, not capability-bounded — reopening them on a capability argument is still foreclosed.