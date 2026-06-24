# ADR 0005 — Addendum: waive the N≥20-cycle precondition for MANUAL-armed-push

- **Status**: Accepted (extends [ADR 0005](0005-l5-auto-push.md); crosses
  [ADR 0004](0004-l4-autonomy.md))
- **Date**: 2026-06-24
- **Decider**: Owner
- **Operating point**: Enable L5 auto-push **for manual armed pushes** (`KBG_AUTONOMY=1`
  in a human-driven session) now, **without** ADR 0005 §Acceptance criterion 2's
  "L4 ran N≥20 unattended cycles with zero bad ships" precondition. The unattended
  (launchd L4 loop) case **keeps** the precondition — the L4 self-launch stays paused.
- **Scope**: Waives precondition (i) for the manual-armed-push subset only. Does **not**
  waive any ADR 0005 floor item — the computational ship-gate, the pre-push cross-repo
  CRIT, and the post-push tripwire are **built** (this addendum's companion change), not
  waived. The deepest invariant ("the gate that authorizes a ship stays computational,
  never a model; the model is veto-only") is untouched.

## The symptom

Under an armed run, `git push` is push-gated behind a **human-review** gate:
`KBG_REVIEW_DONE=1` AND a `review_finding` in the recent journal (the Gate-2
strengthening). That gate is the source of the armed-push ceremony the owner finds
clunky — `kbg:review-pr` → journal → set `KBG_REVIEW_DONE` (out-of-band script, because
the flag won't propagate mid-session) → `git push --no-verify` → remove flag → restart.
The owner's report: *น่ารำคาญใช้งานไม่คล่องตัวเลย*. The prior ADR 0002 addendum
(`0002-addendum-push-gate-create-not-ship.md`) un-gated `gh pr create`/`ready`; this one
finishes the job for `git push` — by replacing the human-review gate with the
**computational** gauntlet gate ADR 0005 already specified.

## The reclassification

| Push path under `KBG_AUTONOMY=1` | Before this addendum | After |
|---|---|---|
| `git push` (manual armed) | denied unless `KBG_REVIEW_DONE=1` + `review_finding` (human-review gate) | allowed when **green-gauntlet-for-HEAD** + allowlisted dest + no security-gate loosening (computational gate) |
| `gh pr merge` / `gh repo sync` | denied unless `KBG_REVIEW_DONE=1` + `review_finding` | **unchanged** — still human-review-gated (merge/sync are the irreversible server-side ships; the owner stays in that loop) |
| `gh pr create` / `gh pr ready` | ungated (ADR 0002 addendum) | unchanged |

The L5 leg in `hooks/gates/push-gate.sh` already sketched this (`KBG_L5_SHIP_ALLOWLIST` +
a green check), but it was a dormant skeleton: no emitter ever wrote a green event, the
green check was not SHA-bound (stale-green gap), the allowlist was empty, and the
cross-repo CRIT lived in the skippable git hook. This addendum's companion change builds
the real gate:

1. **`scripts/run-gauntlet.sh` emits a `gauntlet_run` journal event** stamped with the
   HEAD SHA it validated + `outcome: green|red` — the computational ship-gate evidence.
2. **The L5 leg is SHA-bound**: a push is allowed only if a `gauntlet_run` event with
   `sha == <HEAD being pushed>` + `outcome: green` exists. Stale green for a different
   commit does NOT authorize this push. The model cannot self-bless — it must run the
   deterministic gauntlet, which journals the verdict.
3. **`KBG_L5_SHIP_ALLOWLIST=github.com:wasikarn`** (per-repo `.claude/settings.local.json`,
   gitignored — the owner's opt-in, like `KBG_AUTONOMY` itself; the plugin ships with the
   default empty so an un-configured install pushes nowhere).
4. **The pre-push cross-repo CRIT moves inside `push-gate.sh`** (the `--no-verify`-immune
   Claude PreToolUse hook) and keys on the three ADR-named security gates
   (`secret-scan`, `block-dangerous-git`, `db-write-gate`): a push whose range **deletes**
   one of them or **removes a deny line** from one is denied. "Touches a gate" is NOT the
   trigger (the owner legitimately edits gates — including this very change); "loosens a
   brake" is.
5. **A post-push tripwire** (`hooks/post-tool/post-push-tripwire.sh`) re-runs the
   cross-repo security check against `origin/develop` after a successful push — the
   outside-the-cage witness (advisory; post-push can only detect + journal, not block).
6. **Audit #44 inverts** from "Gate 2 human-gated" to "deny unless gauntlet-passed;
   never on model verdict alone" (ADR 0005 §floor 3).

## Why an addendum, not a superseding ADR

No autonomy axis moves beyond what ADR 0005 already adopted. ADR 0005 **adopted** L5
auto-push (relaxation #2) and **specified** the computational gauntlet ship-gate as what
replaces the human. What it did **not** do is enable it — it set a precondition
(§Acceptance criterion 2: L4 runs N≥20 unattended clean cycles first). This addendum
waives that precondition **for the manual-armed-push subset**, on the basis that the
safety mechanism the precondition was proxying for (proof the gauntlet catches bad ships
before the human leaves the loop) is now **built directly** as the ship-gate itself, and
the manual case keeps the owner at the keyboard (who ran the gauntlet and saw the green).
The unattended case keeps the precondition — the L4 self-launch stays paused, so an
unattended auto-push remains blocked until the cycles run. A standalone superseding ADR
is not consumed because no axis moves; this is a precondition-scope correction to ADR
0005's enable gate, recorded because it loosens what the armed loop can do without the
human (a ratchet-adjacent turn the invariant says must be recorded).

## The precondition being waived, and why for manual only

ADR 0005 §Acceptance criterion 2 (carrying ADR 0004 §Sub-decision 2) requires, to enable:
"L4 shipped, ran N≥20 clean cycles across ≥2 weeks with zero bad ships, F1/F2/F3 closed,
cumulative cap exists." Today: the machinery is shipped and gauntlet-green, F1/F2/F3 are
built, the cumulative cap exists — but **0 unattended cycles have run** (the L4
self-launch is paused via kill-file). The precondition's intent (ADR 0005 Red-team #1,
ADR 0004 §Red-team #1) was to prove the gauntlet catches bad-but-green ships **while a
human still backstops**, before removing the human from the loop. That proof was
designed for the **unattended** loop, where no human sees the push. For a **manual**
armed push, the owner is the human at the keyboard — they ran `run-gauntlet.sh`, saw the
green, and push. The residual (green ≠ safe) is smaller (the owner can eyeball the diff)
but not zero. The owner accepts the residual for the manual case; the unattended case
keeps the full precondition.

## Riskiest assumption (stated + verified)

**Assumption:** a SHA-bound green-gauntlet event is a real computational ship-gate — the
model cannot authorize a ship without running the deterministic gauntlet for the exact
HEAD.
**Verification:** `run-gauntlet.sh` is deterministic (6 fixed layers, exit = failed
count); the event's `sha` field binds the verdict to one commit; the L5 leg requires
`sha == HEAD`; a push with no green-for-HEAD (or stale green, or model-verdict-only) is
denied. The model's only path to a green event is running the gauntlet, which it does not
control the outcome of.
**Failure mode if wrong:** a bad-but-green commit ships to `origin` with no human catch.
Contained — `git revert` recovers (single-revert, ADR 0005 exit-condition (b)); the
allowlist scopes the dest to `github.com:wasikarn`; the cross-repo CRIT blocks the worst
class (a loosened brake); the post-push tripwire witnesses. This is the ADR 0005
Red-team #1 residual, accepted.

## What stays (the floor is unchanged)

- The cage (`scripts/cage.txt`), the computational kill-switch, per-cycle reversibility
  tags, the cumulative cap (R4) — unchanged.
- `docs/adr/**` in the cage — the loop still cannot author/edit/accept its own ADR; this
  addendum is human-authored in a manual session.
- `gh pr merge` / `gh repo sync` — still human-review-gated (the irreversible
  server-side ships; the owner stays in that loop).
- The unattended L5 auto-push (launchd L4 loop) — still blocked by the N≥20-cycle
  precondition; the self-launch stays paused.

## Test

`tests/hooks/runners/test-ch-l3.sh` L5 path: `gauntlet_run` green-for-HEAD + allowlisted
dest → `none` (allow); no green event → `deny`; stale green (different sha) → `deny`;
model-verdict-only (`quality_gate` green, no `gauntlet_run` green) → `deny`; security-gate
loosening in the push range → `deny`; empty allowlist → `deny`. Locks the contract so a
regression fails loud.