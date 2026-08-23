---
name: iterate-skill
description: "Bounded, human-gated improve loop for a skill/agent/command's SKILL.md-style body content, using kbg:review-fixtures as the quality signal. Use after a review-fixtures pass has target-attributable findings you want to act on. Don't use for description-only tuning (skill-creator's own run_loop.py) or a single one-off fix (just edit the file)."
argument-hint: <skill/agent/command-name> [iteration-path]
disable-model-invocation: true
disable-model-invocation-reason: mutates real, shipped skill content — user-only per CLAUDE.md's no-model-self-start invariant
model: inherit
effort: high
---

# /iterate-skill — bounded improve loop for body content

Closes the loop `kbg:review-fixtures` opens: it produces a grounded-ish quality signal for a
skill/agent/command's *body* content, but applying a fix, regenerating fixtures, and
re-reviewing has so far been done by hand across separate command invocations, with no iteration
bookkeeping or explicit stop condition. This command formalizes that cycle.

**Why this forks `kbg:recursive-improve`'s skeleton, not `skill-creator`'s `run_loop.py`:**
the signal here is reviewer judgment, not a hard grounded score — which is exactly why the ASK
gate below is mandatory, not decoration (CLAUDE.md's verifier-separation crux). Full rationale:
`references/rationale.md`.

**Cost, stated up front:** one iteration = regenerate `with_skill` + baseline fixtures for every
eval case (2 agent dispatches per case) plus 2 `review-fixtures` reviewer agents = `2N + 2`
dispatches, where N = eval case count. A typical 3-case workspace is 8 dispatches per iteration.
**Iteration cap: 3** — lower than `recursive-improve`'s 5, because each iteration here is far more
expensive than an audit re-run.

## Steps

### 1. Resolve the target and locate the workspace

Same resolution as `kbg:review-fixtures` Step 1 — reuse it, don't re-derive it: strip a leading
`kbg:`, check `skills/$1/SKILL.md`, `agents/$1.md`, `commands/$1.md`, `commands/$1/COMMAND.md`
in order; whichever exists is the target file. `$2`, if given, is the iteration path; otherwise glob `iteration-*` under
`<name>-workspace/` and pick the highest N. If the workspace root doesn't exist, stop and tell the
user to run `skill-creator`'s fixture-generation steps first — this command reviews and iterates
on fixtures that already exist, it does not create the first set.

### 2. Observe

Read `<iteration-path>/feedback.json`.

- **This iteration has fixtures but no `feedback.json` at all:** check this case first — it's more
  specific than "doesn't exist" below, and both match on the same missing-file condition. This is
  not "never reviewed" — it's the signature of an earlier `/iterate-skill` run that Acted but was
  interrupted before Verify finished. The `candidate.diff` that produced these fixtures is NOT at
  `<iteration-path>/candidate.diff` — Step 5 writes `candidate.diff` to the iteration that was
  current *before* Act created this one. If `<iteration-path>` resolved to `iteration-<N>`, check
  `iteration-<N-1>/candidate.diff` instead. If present, `Read` the live target file yourself and
  diff it against `candidate.diff` — do this check yourself even if the user already states the
  file matches; a claim isn't the check. If the file's current content already matches, an
  unverified change from an earlier session is already live. This same interrupted state is also
  what a still-live concurrent session on this repo's shared working tree would leave mid-run
  (see Step 7's manifest-bump note for a confirmed instance of this failure mode) — before
  recommending Verify, say so and confirm no other session is actively working this workspace
  right now. Tell the user the unverified change is live and offer to run Verify (Step 6) now,
  rather than silently restarting at Propose — restarting would hide that the target file already
  changed.
- **Doesn't exist, and this iteration has no fixture output either:** tell the user to run
  `/review-fixtures <name>` first. This command builds on top of that one — it does not
  reimplement reviewer dispatch.
- **Exists but has no `target_attributable` key:** it predates this feature. Say so plainly and
  offer to re-run `/review-fixtures <name>` to backfill a tallied baseline. Never guess a tally —
  an invented number defeats the entire point of a grounded-ish signal.
- **A tallied baseline exists:** that's the starting point for Step 3.

**Success criterion:** either a tallied baseline to improve on, or a clear, explicit reason why
not (missing review, missing tally, or an interrupted prior run) — never a silent assumption.

### 3. Propose

Draft ONE candidate revision to the target file's body, given the current iteration's
target-attributable findings (critical and major first — minor only if there's room) plus a
bounded history of prior candidates *from this loop run* ("previous attempts — do NOT repeat
these, try something structurally different," the same instruction shape `skill-creator`'s
`improve_description.py` uses for descriptions, applied here to body prose). Produce it as a
unified diff against the live target file — generate it by actually diffing the old and new
content rather than hand-authoring the diff text, so hunk-header line counts stay accurate.

**Success criterion:** a diff that, if applied, plausibly addresses the findings named — not a
rewrite that touches unrelated sections. Keep the change scoped to what the findings actually
name; a candidate that rewrites the whole file makes Verify's delta impossible to attribute.

### 4. ASK — the gate (mandatory)

Present: the diff, the findings it targets (with severities), the iteration count so far, and the
dispatch cost of the next step (`2N + 2`, computed from this workspace's eval-case count).
**Recommend**: state which of the three options the diff actually earns on its own merits — e.g.
"Apply and re-test: the diff directly targets both critical findings and doesn't touch unrelated
sections" — not just the general principle that a good diff should be applied.
`AskUserQuestion`, single-select. Render the stated recommendation as the literal `(Recommended)`
tag on that option, replacing its `(best when X)` clause at render time — the list below is a
template, not fixed text to paste verbatim:

- **Apply and re-test** (best when the diff looks right and the cost is acceptable)
- **Revise the candidate** (best when the direction is right but the specific wording isn't)
- **Stop here — keep the current body unchanged** (best when the findings aren't worth this
  cost, or none of the candidates are landing)

Reuse `kbg:recursive-improve`'s Step 3 gate language verbatim for the edge cases — denial ≠
approval; default to calling `AskUserQuestion` — don't self-declare it unreachable
without trying it first. Only if it's unreachable (headless, `dontAsk`, or the call
itself errors), render the same question as numbered prose and stop there, waiting for an
explicit reply in a later turn; never fail open into Act. A planning request is not authorization
to execute.

**Success criterion:** an explicit Apply, Revise (loop back to Step 3), or Stop — never an
inferred approval.

### 5. Act (only on Apply)

Before touching anything: write the shown diff to `<iteration-path>/candidate.diff`. This is the
only artifact a later "revert to iteration N" (Step 8) or a resumed-session Observe (Step 2) can
act on — nothing else in this loop keeps a prior iteration's change retrievable once a later Act
overwrites the target file again.

Apply the diff to the real target file. Regenerate `with_skill` / baseline fixtures for the same
eval cases, following `skill-creator` SKILL.md's own Step 1 fixture-spawn convention, into a new
`iteration-<N+1>/`. **Correctness requirement:** hand the fixture-regeneration agents the target's
repo file path directly — never a name-based `Skill(<name>)` / `subagent_type: <name>` reference.
Until a version bump + plugin reinstall happens, a name-based resolution silently serves the stale
cached copy (`kbg:review-fixtures` Step 8 documents this trap), and this loop edits-then-
immediately-retests within the same session, well before any such bump.

**Success criterion:** the diff is on disk in the real target file, `candidate.diff` is persisted,
and a full fixture set exists in the new iteration directory.

### 6. Verify

Run `kbg:review-fixtures`' Steps 1–7 against the new `iteration-<N+1>/` (its own Step 3.5 "does
feedback.json already exist here" check is structurally moot for this call — Act always writes a
brand-new iteration directory, so nothing has written a feedback.json there yet).

Compare the new `target_attributable` tally against the previous iteration's with a
**lexicographic comparison, most-severe tier first**: compare critical counts — any increase is a
regression regardless of major/minor; only if critical is unchanged, compare major the same way;
only if both are unchanged, compare minor. State a plain verdict: **improved / flat / regressed**.
This is the loop's one actual branchable number — flat or regressed is **not** success, mirroring
`recursive-improve`'s drift guard.

**Success criterion:** a stated verdict backed by the actual tally comparison, not a vibe read of
the reconciled prose.

### 7. Surface

Report the verdict, the before/after tallies, and the diff that produced them. Offer: **continue**
(loop back to Step 3, if under the iteration cap) or **stop**.

**Rollback policy: surface + ask, never auto-revert** (identical to `recursive-improve`). On a
flat or regressed verdict, ask: revert (apply the inverse of the relevant `candidate.diff`) /
keep as the new baseline anyway / try again. Don't silently pick one — a regression is a signal,
not a failure to hide.

**Iteration cap: 3.** If the cap is reached without the user choosing to stop earlier, say so and
stop — don't silently continue past it.

**Once the loop ends with an applied change kept** (stop-with-keep, or cap reached with the last
applied change accepted): bump `plugin.json` + `marketplace.json` **exactly once for the whole
run**, not per-iteration — bumping after every Act would race any concurrent session editing the
same manifest files, a confirmed failure mode in this repo. Run
`bash skills/inventory/scripts/sync-fleet-counts.sh` if the target itself is a counted surface
whose description change affects the fleet-count string (rare for a body-only
edit, but check). Tell the user this content fix needs `claude plugin update kbg@kobig` + restart
before it's live — a prior incident in this repo shipped a content fix without this bump and the
stale cache silently served the unfixed text.

## Output Format

```
iterate-skill — <target> — iteration <N> report
  observed:    baseline tally <c/m/mi> (iteration <N-1>) | first run | interrupted-prior-run
  proposed:    <one-line summary of the candidate diff> · targets: <finding list w/ severities>
  gate:        apply | revise | stop
  acted:       <candidate.diff written, target file patched, fixtures regenerated> | not-acted
  verified:    new tally <c/m/mi> vs previous <c/m/mi> → improved | flat | regressed
  next:        continue (iteration <N+1>, cap 3) | stop (<reason>) | cap reached
  rollback:    none | reverted | kept-as-baseline | retry-scheduled
```

## Failure Modes to Avoid + Integration Notes

`references/rationale.md` carries the full 8-item failure-mode recap (guessed tallies,
interrupted-run misreads, user-claim-as-verification, gate-skipping, per-iteration bumps,
whole-file rewrites, name-based re-testing) and the composes-with/METHODOLOGY notes — every
one of those rules is also stated at its point of use in the Steps above; read the recap when
resuming an interrupted loop or auditing a finished one.
