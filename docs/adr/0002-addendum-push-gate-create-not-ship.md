# ADR 0002 — Addendum: `gh pr create`/`ready` are review-prep, not ship

> **Superseded by [ADR 0006](0006-ecc-aligned-operating-model.md) (2026-06-25); moot.** The L3/L4/L5 bounded-autonomy machinery is retired; see ADR 0006 for the ECC-aligned operating model.

- **Status**: Accepted (extends [ADR 0002](0002-autonomy-invariant.md); crosses
  [ADR 0003](0003-l3-bounded-autonomy.md) Gate 2 + [ADR 0004](0004-l4-autonomy.md) +
  [ADR 0005](0005-l5-auto-push.md))
- **Date**: 2026-06-24
- **Decider**: Owner
- **Operating point**: Gate-semantics narrowing — remove `gh pr create` and
  `gh pr ready` from the push-gate's denied set; keep `gh pr merge` /
  `gh repo sync` / `git push` gated.
- **Scope**: Reclassifies two GitHub CLI verbs from "ship" to "reversible review-prep"
  and removes them from `hooks/gates/push-gate.sh` `GH_PAT`. This is a one-way
  ratchet-adjacent loosening of the armed-loop gate, recorded here per the autonomy
  invariant (the ratchet turns only by a human-authored, recorded ADR — never a flag
  flip).

## The symptom

Under an armed run (`KBG_AUTONOMY=1`), the push gate denied `gh pr create` identically
to `gh pr merge`. To allow it, the gate demanded `KBG_REVIEW_DONE=1` **AND** a
`review_finding` event already in the journal (the Gate-2 strengthening, ADR 0002
addendum *push-gate-review-rigor*). That requirement is **semantically backwards** for
a PR open: you open a PR *to get* review, not *after* one. With the flag not reliably
live in the hook env mid-session (settings.local.json env is a session-start snapshot),
the model's `Bash(gh pr create …)` was denied and the only fallback was to hand the
operator a `!` command to run themselves — e.g.:

```
! KBG_REVIEW_DONE=1 gh pr create -R <org/repo> --base develop --head <feat> \
  --title "…" --body-file /tmp/…/pr-body.md
```

The operator's report: *น่ารำคาญใช้งานไม่คล่องตัวเลย* — the loop can push a commit but
cannot open the PR that presents it for review, so it offloads the PR-open to the human.
Inconsistent and clunky.

## The reclassification

| Verb | Action | Reversible? | Ships? | Gated after this ADR? |
|---|---|---|---|---|
| `gh pr create` | Open a PR (draft or public) | Yes — close it | No — submits for review, neither merges nor deploys | **No** |
| `gh pr ready` | Mark a draft PR ready-for-review | Yes — back to draft | No — publish-for-review signal | **No** |
| `gh pr merge` | Server-side merge | No (rollback only) | Yes — lands the change | Yes |
| `gh repo sync` | Sync fork↔upstream | — | Yes-ish — moves commits | Yes |
| `git push` | Push local commits | No (force/revert only) | Yes | Yes |

The gate's stated purpose (ADR 0003) is to "DENY any command that would **ship** the
work." `create`/`ready` do not ship — they are the **review loop**, not the ship loop.
Gating them conflated "publishes work to an external surface" with "ships," and the
review_finding precondition made the conflation operationally backwards.

## Why this is an ADR 0002 addendum, not a superseding ADR

No architectural axis of the autonomy invariant moves: no new autonomy level, no
model-authorizing ship, no cage removal, the ship-gate stays **computational**. The
deepest invariant — *the gate that authorizes a ship stays computational, never a
model* — is untouched: `merge`/`push`/`sync` (the actual ships) remain gated behind
flag + review_finding. Only the **classification of two reversible verbs** changes,
narrowing the gate's scope from "ship + review-prep" to "ship only." A standalone
superseding ADR is not consumed because no axis moves; this is a scope correction to
the Gate-2 pattern set, recorded because it loosens what the armed loop can do without
the human (a ratchet-adjacent turn the invariant says must be recorded).

## What stays (the floor is unchanged)

- `gh pr merge`, `gh repo sync`, `git push` — still denied unless `KBG_REVIEW_DONE=1`
  + a `review_finding` in the last 500 journal lines (Gate-2 strengthening unchanged).
- The tamper check (inline `KBG_REVIEW_DONE=` in the command string) — unchanged.
- The maker≠checker bar (memory `armed-push-review-path` step 2, fresh-context
  `kbg:review-pr`) — unchanged; it governs the *ship*, which is still gated.
- The rubber-stamp observability check #52 — unchanged; it still flags non-reviewer
  `review_finding` agents, but now only the ship verbs require a review_finding at all.

## Riskiest assumption (stated + verified)

**Assumption:** `gh pr create` and `gh pr ready` are reversible review-prep, not ship.
**Verification:** a PR closes immediately (`gh pr close` / GitHub UI); `ready`→`draft`
is reversible (`gh pr ready --undo`); neither merges a branch nor triggers deploy.
The gate's own purpose ("deny commands that ship the work") therefore excludes them.
**Failure mode if wrong:** the loop opens a PR the operator did not intend to expose
externally. Contained — the PR is closable, no code lands, no deploy fires; and the
operator is in the loop for the actual ship (`merge`/`push`) which stays gated.

## Test

`tests/hooks/runners/test-ch-l3.sh` asserts the new semantics: `gh pr create` and
`gh pr ready` return `none` (allowed) under `$ARMED_ENV` with no review; `gh pr merge`
and `git push` stay `deny`. Locks the reclassification so a regression fails loud.