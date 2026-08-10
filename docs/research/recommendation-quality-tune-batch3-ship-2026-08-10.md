# Recommendation-quality tune — batch 3 (ship-* cluster)

Date: 2026-08-10. Third batch from issue #40 (Level-B backlog:
`recommendation-quality-tune-2026-08-10.md`). Follows batch 2
(`recommendation-quality-tune-batch-fixbug-reviewpr-codereviewer-2026-08-10.md`).

## Scope and rigor

Batch = the `/ship` pipeline's own cluster, explicitly named in issue #40's list (`ship-*`,
`ship/references/*`): `commands/ship-release.md`, `commands/ship/COMMAND.md`,
`commands/ship/references/classify.md`, `commands/ship/references/pre-ship-verify.md`. Same
rigor as batch 2 — **Level B only, unmeasured** (no new fixtures, no fresh-context trials). Gaps
closed against the static 9-criterion checklist from the original sweep
(`grading/levelB-commands.md`, session scratchpad), re-graded against current file content
before editing per issue #40's own instruction. All cited line numbers matched current content.

## What was changed

| File | Gap closed | Fix |
|---|---|---|
| `ship-release.md` | 5 ASK-CONSEQUENCES | Phase 1 ask options now state their effect (which phase/state each choice leads to) |
| `ship-release.md` | 7 SELF-CONSISTENCY | Guard against a hedged Recommend when Analyze found a concrete problem — explicitly does NOT skip the ask (irreversible action; this file's own `disable-model-invocation-reason`) |
| `ship-release.md` | 8 REVISIT-TRIGGER | Initial-version default (0.1.0 vs 1.0.0) now names a re-open condition |
| `ship/COMMAND.md` | 2 EVIDENCE-REASON | Phase 0 gets an Analyze step (location-signal check) before the path-classification ask |
| `ship/COMMAND.md` | 5 ASK-CONSEQUENCES | Path A/B options state their effect, not just a routing label |
| `ship/COMMAND.md` | 6 DEFAULT-BEFORE-ASK | Default (Path A) now stated beside the ask, not only ~140 lines later in Failure Modes |
| `ship/references/classify.md` | 3 HONEST-CONFIDENCE | Explicit "uncertain" fallback when keywords conflict or don't match |
| `ship/references/classify.md` | 4 ALTERNATIVE | Recommend step now names why the other two classifications lose |
| `ship/references/classify.md` | 5 ASK-CONSEQUENCES | Options carry a short routing effect |
| `ship/references/classify.md` | 7 SELF-CONSISTENCY | Skip the ask when step 1's keyword match is unambiguous — explicitly justified: downstream Phase 3/4 gates in `/fix-bug` and `ship/COMMAND.md` still confirm before code changes, so this skip doesn't remove human confirmation for the actual work |
| `ship/references/pre-ship-verify.md` | 5 ASK-CONSEQUENCES | AMBER branch states what confirming vs declining actually does |

11 of 11 gaps in scope closed. Original per-file tallies: `ship-release.md` PASS=6 GAP=3 (5, 7,
8 — all closed); `ship/COMMAND.md` PASS=6 GAP=3 (2, 5, 6 — all closed);
`ship/references/classify.md` PASS=5 GAP=4 (3, 4, 5, 7 — all closed);
`ship/references/pre-ship-verify.md` PASS=4 GAP=1 (5 — closed).

`classify.md` required renumbering steps 4→7 to insert the new self-consistency step — every
internal step-number cross-reference in the file was checked and updated in the same edit.

## Char deltas (final, post-review-fix)

| File | Before | After | Delta |
|---|---|---|---|
| `commands/ship-release.md` | 6,992 chars | 7,960 chars | +13.84% |
| `commands/ship/COMMAND.md` | 11,954 chars | 12,446 chars | +4.12% |
| `commands/ship/references/classify.md` | 1,971 chars | 3,007 chars | +52.56% |
| `commands/ship/references/pre-ship-verify.md` | 3,719 chars | 3,991 chars | +7.31% |

**Deviation named** (method rule 5): `classify.md` exceeds the 20% flag threshold at +52.56%.
This is a 22-line, ~2KB reference file where 4 distinct real gaps closed (HONEST-CONFIDENCE,
ALTERNATIVE, ASK-CONSEQUENCES, SELF-CONSISTENCY) — a file this small structurally produces a
large percentage even with terse wording, and the post-review-fix growth (from +34.65% to
+52.56%) is the exact opposite of a verbosity purchase: it's the code-review pass finding that
the *first* draft's self-consistency justification was factually wrong for the Refactor route
(see below) and required naming the real, narrower safety condition. Cutting that explanation to
hit the threshold would re-introduce the bug the review caught. Judged acceptable on the same
basis as batch 2's own deviations: correctness over the char-delta guard when the two conflict.

## Design note: self-consistency and irreversible actions

Batch 2's code-review pass caught two HIGH issues where a "skip the ask" self-consistency fix
accidentally weakened a hard confirmation gate. This batch applied that lesson directly:

- `ship-release.md`'s Phase 1 ask gates an irreversible action (tag/merge/publish — this file's
  own reason for carrying `disable-model-invocation: true`). Its self-consistency fix
  **deliberately does not skip the ask** — it only guards against a hedged Recommend when the
  evidence is actually clear. The ask fires every time, unconditionally, exactly as before.
- `classify.md`'s ask only picks a *routing* target (bug/feature/refactor) — the actual
  code-mutating work always passes through its own downstream gate regardless of which route was
  taken (`/fix-bug`'s Phase 3/4, or `ship/COMMAND.md`'s Phase 4 approval for the inline feature
  path). Skipping *this* ask when unambiguous does not remove human confirmation from the
  pipeline — it removes one redundant early confirm whose answer downstream gates re-verify
  anyway. The fix states this reasoning explicitly in-file so a future reader (or editor) can
  judge whether the premise still holds, rather than asserting the skip is safe by fiat.

## Post-edit code-review pass

A `kbg:code-reviewer` pass ran on the diff before commit, specifically briefed to scrutinize for
batch 2's exact failure shape (a self-consistency addition quietly weakening an existing hard
gate) and to verify `classify.md`'s renumbering. Found 1 HIGH + 1 LOW, both real, both fixed:

- **HIGH — third confirmed instance of the same failure class.** `classify.md`'s self-consistency
  skip (step 3, as first drafted) justified itself by naming the downstream gates that still
  confirm before code changes — but only named 2 of the 3 routing destinations (`/fix-bug`'s
  Phase 3/4, the feature path's Phase 4 approval). The third, Refactor → `/refactor-clean` →
  `agents/refactor-cleaner.md`, has **no pre-edit confirmation gate at all** — its own safety
  model is stage-without-committing, reviewed *after* the edit lands, not before. Skipping
  classify.md's own ask on an unambiguous "refactor"/"clean up" request would have removed the
  *only* pre-mutation human touchpoint on that route. Fixed: the skip condition now excludes
  Refactor explicitly, with the reasoning stated in-file (`agents/refactor-cleaner.md` §3 cited
  directly) so a future editor can see why that route is different, not just that it is.
- **LOW** — the AMBER branch's new consequence clause told the model to "note it in the audit
  trail," but the audit-trail JSON schema three sections later had no field for that. Fixed:
  added an optional `note` field to the schema.

This is the **third** confirmed instance of the same defect class across 2 batches (batch 2 had
2 instances: review-pr's zero-tier skip missing 3 must-fix conditions, fix-bug's Phase 4 wording
reading as gate-skippable). Pattern: a self-consistency fix that skips an ask needs to verify
*every* branch the ask routes to still has an equivalent confirmation somewhere downstream —
naming 2 of 3 and assuming the third matches is the recurring mistake, not a one-off.

## Verification

- `harness-audit` before this batch's edits: 0 CRIT / 0 WARN / 5 INFO (the prior batch's stale
  README warning had cleared — a concurrent session's commit updated the plugin version the
  badge check compares against).
- `harness-audit` after (final, post-review-fix): identical (0 CRIT / 0 WARN / 5 INFO) — no new
  findings from this batch's edits.
- Inventory cross-check (method rule 8): all 4 file paths resolved, all 11 pre-edit citations
  verified against current content before editing — no drift from the original sweep. Char
  counts computed via `wc -c` against `git show HEAD:<path>`.
- A second code-review round was not re-run after the HIGH/LOW fixes — the fixes are narrow,
  targeted additions to the exact lines flagged, verified by re-reading the full renumbered file
  (step cross-references all still consistent) rather than a second agent dispatch.
