# Step Rationale — Elaboration Moved Out of SKILL.md

Non-operative rationale for Steps 2 and 5's named bias guards, kept here so SKILL.md stays under
the fleet's char-count standard. The operative instruction in each guard stays inline in
SKILL.md — this file only expands the *why* and the escalation options.

## Step 2 — Named bias guard: anchoring (escalation options)

For a numeric, traceable verdict instead of an ordinal rank, apply the `kbg:score-decision`
rubric (METHODOLOGY Rule 14) inline — the skill is `disable-model-invocation: true`, so it can't
be invoked mid-loop; tell the operator to run `/kbg:score-decision` directly if a formal artifact
is what's needed. For a candidate set >3, ranking is still a same-context, same-pass judgment (the
anchoring risk isn't fully closed by a prose reminder) — optionally dispatch a fresh-context agent
with only the candidate list (no Observe-phase narrative) to independently re-rank before
presenting at Step 3, mirroring `agents/ideate-critic.md`'s pattern.

## Step 2 — Cross-iteration evasion guard (why it exists)

The scope guard's ≤5-file/≤200-line count bounds a single Propose pass — it does not by itself
stop the same root-cause finding from being smuggled through piecemeal across several
separately-approved iterations (e.g. 4 files this iteration, 4 the next, 4 after). That's why the
guard checks new candidates against Step 6's routed-to-`/ship` memory entries for root-cause
overlap.

## Step 3 — Why the ASK gate never self-consistency-skips

Unlike a self-consistency skip elsewhere in the fleet (e.g. `incident/SKILL.md`'s
mitigation-confirm), Step 3's gate is authorization, not information-gathering — an
unambiguous ranking answers "what's best," not "do you approve," so the two questions don't
collapse into one just because the ranking is obvious.

## Step 2 — Scope guard: file count is a proxy, not the risk

File count is a proxy for the real risk (correlated content-judgment across many files), not the
risk itself — a mechanical, low-risk edit spanning many files can fail this guard unnecessarily,
while a small, high-judgment edit inside `hooks/gates/**` can clear it easily. Clearing the count
is not a substitute for actually weighing what the candidate touches. This is a caveat for how you
*describe and prioritize* a routed candidate — never an exception procedure (SKILL.md's closing
prohibition sentence holds regardless).

## Step 6 — Accept-as-new-baseline re-open condition (second example)

Besides "revisit if this `file:line` resurfaces in a later Observe pass," a re-open condition can
also be metric-shaped: "revisit if the accepted regression's metric moves further in the same
direction."

## Step 6 — Rollback policy precedent

"A regression is a signal, not a silent failure" is the qmd-reindex precedent: an earlier harness
regression that got auto-suppressed rather than surfaced, which is the incident this policy exists
to prevent.

## Integration Notes — full detail

- **METHODOLOGY:** Rule 4 (this skill *is* the loop-until-verified instrument for the harness) ·
  surface conflicts, don't average (drift guard picks the measured audit delta over the optimistic
  claim) · fail loud (surface flat/negative deltas and regressions, never bury them) · Rule 13
  (decompose → route → verify → combine, inline).
- **Composes:** `orchestrate` (the decompose/route/verify pattern, inlined) · `harness-audit`
  (both the candidate-detail signal and the deterministic verification metric — its exit count is
  the loop's branchable score) · the witness scripts under `inventory/` (pre/post attestation) ·
  `/ship` (escrow for over-scope candidates) · the harness-decay cadence
  (`docs/harness-decay-cadence.md`, the build-to-delete counterpart to this add/fix loop, and its
  `## Permission re-audit` section for tool-grant decay candidates).
- **Reads, never writes, the journal.** This skill does not emit a journal event. Iteration
  evidence is the witness BOUNDARY diff + a memory entry, not a journal stream (kept minimal per
  Rule 2 — revisit only if a durable per-iteration history is actually needed).
