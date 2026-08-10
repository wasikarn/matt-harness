# Recommendation-quality tune — batch 6 (post-mortem / recursive-improve / task-prep / pr)

Date: 2026-08-10. Sixth batch from issue #40 (Level-B backlog: `recommendation-quality-tune-2026-08-10.md`).
Follows batch 2 (fix-bug/review-pr/code-reviewer), batch 3 (`/ship` pipeline cluster), batch 4
(review-agent cluster), batch 5 (smallest skills cluster).

## Scope and rigor

Batch = the 4 remaining files with 2-3 open gaps each, excluding `skills/orchestrate/reference.md`
(5 gaps — already flagged in the batch 5 report as likely needing its own batch given the size of
the rewrite): `commands/post-mortem.md`, `skills/recursive-improve/SKILL.md`,
`skills/task-prep/SKILL.md`, `skills/pr/SKILL.md`. Same rigor as batches 2-5 — **Level B only,
unmeasured**.

**Re-grade note (method rule 5):** the original grading detail lived in the prior session's
scratchpad (`rec-tune/grading/levelB-*.md`), which is no longer in this session's scratchpad. It
was located in a *different* prior session's directory still on disk and re-read from there. All
10 cited gaps were re-verified against current file content before editing — no drift from the
original citations; line numbers and surrounding text matched exactly.

## What was changed

| File | Gap closed | Fix |
|---|---|---|
| `commands/post-mortem.md` | 1 EXPLICIT-PICK, 4 ALTERNATIVE, 6 DEFAULT-BEFORE-ASK | Phase 5's destination pick now names the specific option the analysis points to *before* the ask, and the `AskUserQuestion` renders that pick's `(best when X)` clause as `(Recommended)` at render time, naming the runner-up + the flip fact — mirrors the pattern already shipped for `address-review/COMMAND.md` |
| `skills/recursive-improve/SKILL.md` | 3 HONEST-CONFIDENCE, 7 SELF-CONSISTENCY, 8 REVISIT-TRIGGER | Blast-radius claims now require citing what's touched (both at Step 2's generation point and Step 3's rendered ask); Step 3's mandatory gate now states explicitly it never collapses even when the ranking is unambiguous (hardening the gate, not adding a skip); accept-as-new-baseline in the rollback policy now requires naming a re-open condition |
| `skills/task-prep/SKILL.md` | 4 ALTERNATIVE, 5 ASK-CONSEQUENCES | Step 5's `<reference>` auto-fill now names the runner-up candidate + why it lost when Glob finds multiple; Step 6's "interview me for edge cases" option now states its effect inline in the option text, not just as background rationale |
| `skills/pr/SKILL.md` | 4 ALTERNATIVE, 9 FALSIFIABILITY | Commit Analysis's dominant-type pick now names the runner-up type(s) + the count that decided it, and states an explicit tie-break rule (grounded in the already-fetched commit subjects, not a fabricated severity ordering) |

10 of 10 gaps in scope closed. No gap left open or deliberately skipped.

## A judgment call reconsidered mid-batch (SELF-CONSISTENCY on recursive-improve)

`recursive-improve/SKILL.md`'s Step 3 is a CRIT-guarded (harness-audit check 39),
`disable-model-invocation: true` mandatory approval gate — its own frontmatter says "LOAD-BEARING
safety invariant... do not weaken," and its Failure Modes section explicitly bans "Treating the
gate as a formality." My first-pass reading of the SELF-CONSISTENCY gap was that the only safe
resolution was to **reject** it with a documented reason (the same shape as the master doc's
precedent: `task-prep-checker.md`'s DEFAULT-BEFORE-ASK gap, rejected because "the guardrail
forbids inventing defaults by design").

Called `advisor()` before implementing. The correction: the gap's cited text — "no rule against
asking when the ranked list already settles the order" — asks whether the file has a **stated
rule about redundancy**, not whether it adds a skip. A file that explicitly reasons "this ask is
never redundant, because it's authorization, not information-gathering" satisfies the criterion
by reaching the opposite (and correct) conclusion from the fleet's usual redundancy-skip pattern.
Closed by adding an explicit non-skippable rule directly at the gate — strictly hardening,
pre-empting a future editor applying the fleet-wide self-consistency-skip pattern (already shipped
once, correctly, on `incident/SKILL.md`'s mitigation-confirm) to a gate where it doesn't belong.
10/10 closed, zero rejected — a revision from the initial 9-closed/1-rejected plan.

## Char deltas

| File | Before | After | Delta |
|---|---|---|---|
| `commands/post-mortem.md` | 14,166 chars | 14,554 chars | +2.74% |
| `skills/recursive-improve/SKILL.md` | 14,540 chars | 15,606 chars | +7.33% |
| `skills/task-prep/SKILL.md` | 19,888 chars | 20,306 chars | +2.10% |
| `skills/pr/SKILL.md` | 10,468 chars | 10,994 chars | +5.02% |

All under the 20% flag threshold — no deviation to name.

## Post-edit code-review pass

A `kbg:code-reviewer` pass ran on the diff before commit, specifically briefed to scrutinize
`recursive-improve/SKILL.md` hardest and to verify the new Step 3 bullet introduces no bypass path
when read as literally as a future editor might (not as intended), plus that `pr/SKILL.md`'s new
tie-break rule doesn't assert a fabricated conventional-commit severity ordering. Found 1 MEDIUM +
1 LOW; the requested safety check on recursive-improve's Step 3 gate itself came back clean:

- **MEDIUM** — the HONEST-CONFIDENCE fix's first draft added an `insufficient evidence` value for
  blast radius, but Step 2's own success criterion is a closed binary ("within the scope guard
  **or** explicitly flagged as too big — route to `/ship`"). A candidate whose touched surface is
  genuinely unclear could hit the new, unhandled third state and reach the Step 3 approval gate
  without ever having actually cleared Step 2 — reachable, not hypothetical, since Step 1's own
  success criterion allows a candidate anchored only to a MEMORY.md entry with no file set
  identified yet. Fixed: folded the unclear-surface case into the existing "too big — route to
  `/ship`" branch instead of adding a new state; removed the now-orphaned `insufficient evidence`
  reference from Step 3's rendered ask template.
- **LOW** — `pr/SKILL.md`'s tie-break rule's first draft resolved a tie by "match[ing] what the
  Summary says," but "Change summary" is the *next* bullet in the same Determine list — a forward
  reference to an artifact not yet built at that point in a top-down read. Fixed: grounded the
  tie-break in the commit subjects already fetched earlier in the same Commit Analysis section
  instead.

The reviewer explicitly confirmed: the Step 3 gate bullet is "purely prohibitive... with no
conditional clause a future editor could misread as a skip trigger," correctly resolves to the
file's own operating invariant, and does not contradict the Failure Modes section — **no bypass of
the mandatory `AskUserQuestion` gate was found.** `commands/post-mortem.md` and
`skills/task-prep/SKILL.md` came back clean — no findings.

## Verification

- `harness-audit` + full gauntlet: green (see commit).
- Inventory cross-check (method rule 8): all 4 file paths resolved, all 10 pre-edit citations
  verified against current content before editing — no drift from the original sweep. Char counts
  computed via `wc -c` against `git show HEAD:<path>`.
- Both MEDIUM/LOW fixes were independently re-verified by a second fresh-context agent (not the
  same reviewer that found them) before commit — confirmed the `insufficient evidence` value has
  zero remaining references anywhere in the file (`grep` returned no hits), Step 2's success
  criterion is back to a clean binary, the `pr/SKILL.md` tie-break now resolves using
  already-available data with no forward reference, and independently fact-checked the underlying
  claim that Conventional Commits v1.0.0 defines no severity ordering between arbitrary commit
  types (confirmed against the live spec: it ties `fix`→PATCH and `feat`→MINOR to SemVer only,
  with all other types explicitly "not mandated... and have no implicit effect in Semantic
  Versioning").

## Limitations

- **No Level A evidence** — same explicit-choice basis as batches 2-5.
- **Simulated static grading** — same as prior batches.
- **No second full code-review round** after the MEDIUM/LOW fixes — the targeted re-verification
  above (a fresh-context read specifically checking both fixes plus the underlying factual claim)
  substitutes for a full second reviewer dispatch.
- **The re-grading source (method rule 5) came from a different prior session's scratchpad**, not
  a fresh independent re-derivation of the 9-criterion rubric against these 4 files. Citations
  were verified to still match current content (no drift), but the underlying grading judgment
  itself (e.g. whether a criterion genuinely applies, N/A vs GAP) was not re-derived from scratch
  in this batch — inherited from the original sweep, same as every prior batch in this backlog.
