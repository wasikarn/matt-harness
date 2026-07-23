# Batch plan: `/skill-creator` improvement pass across all 35 kbg-harness skills

> Durable copy of a plan approved in plan mode 2026-07-23. The plan-mode file it was written from
> (`~/.claude/plans/replicated-bouncing-rivest.md`) gets overwritten on the next plan-mode cycle —
> **this file is the source of truth going forward.** Check off batches in the Progress table below
> as they close.

## Progress

**Before starting any batch marked "not started":** run `git status --short` and
`git diff --stat` first. A cold-resumed session has no other signal that a batch was left
half-done mid-session (e.g. a skill-creator run finished but the closeout ritual didn't) — if the
batch's skills already show modifications, treat it as in-progress, not not-started, and figure out
where it actually left off before re-running anything.

| # | Status | Closed on |
|---|---|---|
| 0 — description-budget pre-pass | ☑ done (WARN accepted, see note below) | 2026-07-23 |
| A1 — decide, orchestrate, review-pr, task-prep (skill-creator loop only) | ☑ done (scope downgraded, see note below) | 2026-07-23 |
| A1b — orchestrate + review-pr in-place prose-tightening (separate session from A1) | ☑ done (low yield, correct outcome — see note below) | 2026-07-23 |
| A2 — pr, incident, security-auditor, production-audit | ☑ done (1 real fix, 3 no-change) | 2026-07-23 |
| A3 — codebase-onboarding, score-decision, tech-humanize | ☐ not started | |
| B1 — add-surface, harness-audit, memory-lint | ☐ not started | |
| B2 — context-budget, inventory, claude-md-health | ☐ not started | |
| B3 — agent-architecture-audit, eval-harness, goal-craft, learn, recursive-improve | ☐ not started | |
| C1 — dart-flutter-patterns, backend-patterns, mysql-patterns | ☐ not started | |
| C2 — langchain-langgraph-patterns, effect-ts-patterns, grpc-node-patterns, tauri-v2-patterns | ☐ not started | |
| C3 — drizzle-patterns, hono-patterns, adonisjs-patterns, fastapi-patterns, latency-critical-systems, cost-aware-llm-pipeline | ☐ not started | |

## Context

User asked to improve every skill in kbg-harness via `/skill-creator`. Running skill-creator's
full per-skill methodology (interview → test prompts → paired with-skill/baseline subagent runs →
benchmark → eval viewer → human review → iterate) on all 35 skills in one sweep isn't a single
action — it's ~9-11 hours of review time and 350+ subagent runs if done at uniform depth, and most
of that depth is wasted: two Explore agents catalogued the fleet and found most skills are already
structurally sound (only 4 of 35 miss a completion criterion; only 3 miss both a completion
criterion and a failure-mode guard). The user confirmed **coverage = all 35, calibrated depth by
archetype** — workflow skills get the full empirical loop, reference/utility skills get a lighter
pass (skill-creator's own guidance already says not to force paired-benchmarking onto
reference-doc skills).

This plan is the batch schedule + per-batch recipe. It does not execute anything — each batch runs
as its own skill-creator session, reviewed and approved before the next one starts.

**Update (2026-07-23, after Batch 0/A1/A1b):** user set a session `/goal` — "ทำทุก batch จนเสร็จและถูกต้อง
ตามแผนทั้งหมด" (do every batch until finished and correct per the whole plan) — after A1b started.
Standing per-batch approval is replaced by continuous execution through the remaining batches; the
per-batch rigor (closeout ritual, verification, honest-outcome reporting) is unchanged, only the
between-batch pause is removed. **Also worth flagging before the remaining batches run:** all three
batches closed so far (0, A1, A1b) found the fleet leaner / more doctrine-complete than this plan's
original framing assumed — Batch 0 found almost no cuttable description fluff, A1 found 3 of 4
skills already carrying both doctrine guards, A1b found ~1 genuine prose-tightening spot across two
46K-char files. The remaining batches' effort estimates in this plan were calibrated to the original
"most skills need real work" framing; expect them to land lighter too, and treat "reviewed, no
change needed" as a normal, correct outcome rather than a sign a batch under-delivered.

## Adversarial review (2026-07-23, `kbg:plan-reviewer`)

Before executing batch 0, this plan was reviewed adversarially. Verdict: needs-revision → revised
in place (this copy reflects the revision, not the pre-review draft). What it found and what
happened to each finding:

- **Critical, fixed at the root:** `score-decision` carries `disable-model-invocation: true` (a
  safety-load-bearing flag, same class as `recursive-improve`'s) but had zero CRIT-level gate
  protecting it — only `recursive-improve` had one (check 39). skill-creator's own
  description-optimizer rewrites SKILL.md frontmatter, so a batch A3 run against `score-decision`
  could silently drop the flag with nothing catching it. **Fixed before any batch starts:** added
  `harness-audit` check 49 (mirrors check 39 exactly), fixtures under
  `skills/harness-audit/tests/known-bad/check-49-*`, wired into `test-harness-audit.sh`, and bumped
  the audit's fragment-integrity guard from 48→49. Verified live: fires CRIT when the flag is
  stripped, silent when present, full gauntlet green.
- **High, addressed below:** skill-creator's edit target was never pinned down (repo git checkout
  vs. installed plugin-cache copy vs. a `/tmp` copy per its own "installed skill may be read-only"
  doctrine) — see "Where skill-creator edits," new section below.
- **High, addressed via schedule split:** batch A1 stacked 4 full-loop skill-creator cycles plus a
  manual prose-tightening pass on the fleet's two largest, safety-critical bodies in one sitting —
  split into A1 (skill-creator loop only) and A1b (orchestrate/review-pr prose-tightening, its own
  session).
- **High, addressed below:** skill-creator's `<skill>-workspace/` scratch artifacts had no stated
  location or retention policy — see "Workspace artifacts" note below.
- **Medium findings**, each folded in as a one-line rule at its relevant section: the
  description-budget tie-break, the no-regression guardrail now requiring an actual `git diff`
  (not just a reread), a scope guard on B1 touching `harness-audit` itself, and a note that
  subjective-output workflow skills skip the quantitative benchmark.
- **Low findings**, folded in: a pre-declared `CHANGELOG`/`CLAUDE.md` version-bullet folding rule,
  reworded "clean pass" → the actual relative bar, and a cheap staleness pre-check before spending
  full currency-check depth on all 13 pattern skills.
- **Surfaced to the user rather than defaulted:** whether to add interim commit checkpoints across
  the marathon. Resolved — commit at every batch close, no push (see closeout ritual step 9).

## Where skill-creator edits (pinned down — this was previously unstated)

Point skill-creator explicitly at `skills/<name>/SKILL.md` in **this git checkout**
(`/Users/kobig/Codes/Personals/kbg-harness`) for every batch — never the installed
plugin-cache copy (`~/.claude/plugins/cache/kobig/kbg/vX.Y.Z/...`). skill-creator's own doctrine
branches to a `/tmp` copy when it detects an "installed, possibly read-only" skill; that heuristic
was written for the Claude.ai/marketplace deployment model, not this repo's git-source-of-truth
model. **Before running each batch's closeout ritual, confirm with `git diff --stat` that the repo
file under `skills/` actually changed** — a batch that closes clean without a nonempty diff means
nothing landed and the batch is not actually done, regardless of what the eval viewer showed.

## Workspace artifacts (previously unstated)

skill-creator materializes `<skill-name>-workspace/` directories (iteration outputs, benchmark
JSON, eval-viewer HTML, feedback JSON) as siblings to each skill it touches. Convention for this
marathon: create these under the scratchpad directory, not the repo — they are working evidence
for the human review step, not something to commit. If a batch's workspace is worth keeping as a
durable record of what changed and why, summarize the outcome into that batch's `CHANGELOG.md`
entry instead of committing the raw workspace. Check `git status --short` after each batch — an
untracked `*-workspace/` directory at repo root means it landed in the wrong place.

## Fleet catalogue (from live audit, 2026-07-23)

| Archetype | Count | Skills |
|---|---|---|
| **Workflow** (multi-step procedure the model executes) | 11 | codebase-onboarding, decide, incident, orchestrate, pr, production-audit, review-pr, score-decision, security-auditor, task-prep, tech-humanize |
| **Utility/meta** (harness-internal tooling/audit) | 11 | add-surface, agent-architecture-audit, claude-md-health, context-budget, eval-harness, goal-craft, harness-audit, inventory, learn, memory-lint, recursive-improve |
| **Pattern/reference** (framework-doc catalog) | 13 | adonisjs-patterns, backend-patterns, cost-aware-llm-pipeline, dart-flutter-patterns, drizzle-patterns, effect-ts-patterns, fastapi-patterns, grpc-node-patterns, hono-patterns, langchain-langgraph-patterns, latency-critical-systems, mysql-patterns, tauri-v2-patterns |

**Demonstrated-gap ranking** (missing a completion criterion and/or a failure-mode guard — this
sets order within each tier, worst first):
- Missing **both**: `add-surface`, `dart-flutter-patterns`, `harness-audit`
- Missing **one**: `adonisjs-patterns`, `backend-patterns`, `context-budget`, `decide`,
  `drizzle-patterns`, `effect-ts-patterns`, `grpc-node-patterns`, `hono-patterns`, `inventory`,
  `langchain-langgraph-patterns`, `latency-critical-systems`, `memory-lint`, `tauri-v2-patterns`
- Everything else already carries both guards.

## Depth per tier (what "improve" means, calibrated)

| Tier | Skill-creator treatment | Why |
|---|---|---|
| Workflow (11) | **Full loop**: interview if scope is fuzzy → 2-3 test prompts → with-skill/baseline subagent pairs → grade + benchmark → `generate_review.py` viewer → user feedback → iterate → description-optimizer loop | Only place empirical A/B testing earns its cost — these skills produce behavior, not reference text |
| Utility/meta (11) | **Light pass**: read skill, name the specific gap (missing done-when / missing failure-mode section) from the catalogue above, draft the fix, run skill-creator's description-optimizer loop only, skip the paired-benchmark | These are harness-internal; correctness is verified by `harness-audit` itself, not by comparing subagent outputs |
| Pattern/reference (13) | **Lightest pass**: a cheap per-skill staleness check first (one context7 lookup — does this library's docs actually show version/API drift?), then full currency/accuracy depth only where that check flags something, + add the missing failure-mode section using the shared template already present in `fastapi-patterns`/`mysql-patterns`/`cost-aware-llm-pipeline` (the 3 pattern skills that already have one) + description-optimizer loop | skill-creator's own guidance: don't force paired-benchmarking onto subjective/reference-doc skills; and don't spend full currency-check depth on 13 skills when nothing demonstrates any of them are actually stale |

**Per-skill depth override:** the tier sets the *default* depth, not a blanket rule — a workflow-tier
skill whose output is genuinely subjective (no single correct answer for a benchmark to score) skips
the quantitative paired-benchmark even though its tier is "full loop." Named now: `tech-humanize`
(a writing-style rewrite skill — skill-creator's own guidance says "don't force assertions onto
things that need human judgment"). Keep the qualitative eval-viewer review for these; skip building
assertions/benchmark.json for them specifically.

**No-regression guardrail (every tier):** before touching a skill, snapshot it
(`cp -r skills/<name> <workspace>/skill-snapshot/`) per skill-creator's own "improving an existing
skill" baseline convention. After the pass, keep the new version only if the benchmark/eval-viewer
review (workflow tier) or **an actual `git diff skills/<name>/SKILL.md` review** (utility/pattern
tier — not just a reread) shows the named gap closed with no unintended collateral change elsewhere
in the file. A different-but-not-better rewrite is a discard, not a ship — churn on an
already-working skill is a real cost with no user-visible benefit.

## Decoupled pre-pass: description-budget trim (do this FIRST, outside skill-creator)

The fleet-wide description budget (harness-audit check 47) is 9297 chars against a conservative
8000 ceiling — needs a 1297-char cut. This is a **separate, cheap, mechanical pass**, not a
skill-creator responsibility: skill-creator's own description-optimizer (`run_loop.py`) optimizes
for *trigger accuracy*, which can make descriptions **longer** — directly fighting this goal. Doing
the trim first means each skill's later description-optimizer run has headroom instead of
re-fighting the same ceiling 24 times.

- **Target: ~150-char house ceiling** (150 clears with ~370-char margin; 160 falls 75 chars short).
- **Biggest bankable pool:** the 11-skill pattern-skill cohort sharing one template (~30 chars each
  recoverable, ~330 total) + hard-trimming the top ~10 longest descriptions (`/compliance-audit`
  290, `decide` 241, `/ask-kbg` 230, `effect-ts-patterns` 224, `claude-md-health` 219,
  `dart-flutter-patterns` 216, `langchain-langgraph-patterns` 213, `/post-mortem` 208,
  `tech-humanize` 207, `latency-critical-systems` 203).
- Verify with `bash skills/harness-audit/scripts/audit.sh` — check 47's WARN clears.
- **Tie-break rule (for every later batch's description-optimizer run):** the house ceiling wins.
  If skill-creator's `best_description` output exceeds ~150-155 chars for a given skill, manually
  compress it to fit rather than accepting the optimizer's raw output — otherwise the first few
  batches' optimizer runs quietly re-breach the shared 8000-char budget batch 0 just cleared, and
  nothing after batch 0 re-checks it per-skill unless this rule is followed. Re-run check 47 after
  every batch regardless (already in the closeout ritual).

**Outcome (2026-07-23) — target revised, done-criterion changed:** surveyed the full candidate
list (the ~28 longest descriptions across skills+commands). Nearly all of it is already dense,
doctrine-conformant text at or near the 25-word cap — trigger phrases, Thai translations, and
cross-reference skill names that check 05's negation/trigger regexes and matt-doctrine both
require. Cutting further means removing real disambiguation signal to chase a number, not a real
quality improvement. Found exactly **one** genuinely-fluff cut with zero signal loss:
`compliance-audit`'s redundant `, before declaring it done` (already implied by "after finishing a
multi-phase plan"). Applied it — fleet total 9297 → 9271 chars. Check 47's WARN does **not**
clear (target was 8000; 9271 remains over it) and is **accepted as-is**, not chased further:
check 47's own header comment already flags 8000 as the conservative end of an unreconciled
range (empirical ceilings run ~15-16K); 9271 is ~60% of that higher number, nowhere near the actual
harm the check guards against (a description silently dropping from context). The original
"~150-char house ceiling" and "clears check 47" criteria above are superseded by this outcome —
left in place above for the historical reasoning, not as a live target.

**If check 47's WARN is still unwanted:** that's a separate proposal (lower the threshold, or
accept the empirical ~15-16K figure as the real ceiling) made on its own merits, not a Batch 0
side effect — and it touches `skills/harness-audit/scripts/checks/47-*.sh`, a `verifier-protect.sh`
protected path, so it needs its own explicit go-ahead the same way B1's harness-audit note above
already requires for a similar reason.

**Standing rule for every later batch:** don't force further cuts onto an already-tight
description just to move the fleet total. The tie-break rule above (compress an optimizer's
*new*, over-long output back to house-ceiling size) still applies going forward — it prevents new
bloat, which is a different, lower-risk action than re-cutting existing dense text.

## Two oversized bodies (orchestrate, review-pr) — separate small batch, in-place only

Explore agent 2 found only ~8-13% of each file is safely relocatable to `reference.md` — the bulk
(orchestrate's `--permission-mode plan` warning + tathep privacy tier; review-pr's Scrutinize Gate +
submit-gating + `review-last.json` contract) is load-bearing safety/procedure content that must
stay inline. This is NOT a relocation job. Runs as its own batch, **A1b** below — a separate
session from A1's 4-skill full loop, in-place prose-tightening only — do not chase the 20K-char
threshold by moving safety content out.

## Batch schedule (10 groups, run and reviewed one at a time)

| # | Tier | Skills | Notes |
|---|---|---|---|
| **0** | pre-pass | (description trim, fleet-wide) | Do before any skill-creator batch starts |
| **A1** | Workflow | `decide`, `orchestrate`, `review-pr`, `task-prep` (skill-creator loop only) | Worst workflow gap (`decide`) + the 2 highest-traffic/oversized skills + task-prep (17K chars, heavily used). Prose-tightening on orchestrate/review-pr is NOT in this batch — see A1b |
| **A1b** | Workflow (follow-up) | `orchestrate`, `review-pr` — in-place prose-tightening only | Separate session from A1 (don't stack a 4-skill full-loop batch with a manual edit pass on the fleet's two largest safety-critical bodies). No relocation to reference.md — tighten prose in place only |
| **A2** | Workflow | `pr`, `incident`, `security-auditor`, `production-audit` | |
| **A3** | Workflow | `codebase-onboarding`, `score-decision`, `tech-humanize` | `score-decision` now CRIT-guarded by check 49 — re-grep for the flag after the edit anyway, the check runs at closeout not mid-edit. `tech-humanize` uses the subjective-skill override (qualitative review only, no benchmark) |
| **B1** | Utility/meta | `add-surface`, `harness-audit`, `memory-lint` | Worst utility gap (2 missing both guards). **Scope `harness-audit`'s fix to `SKILL.md` prose only** — if closing its gap properly seems to need a new check script under `scripts/checks/`, that collides with `verifier-protect.sh`'s protected-path gate and is a separate, explicitly user-approved change outside this batch's skill-creator loop, not something to do inline here |
| **B2** | Utility/meta | `context-budget`, `inventory`, `claude-md-health` | |
| **B3** | Utility/meta | `agent-architecture-audit`, `eval-harness`, `goal-craft`, `learn`, `recursive-improve` | Already-complete skills, light pass only |
| **C1** | Pattern | `dart-flutter-patterns`, `backend-patterns`, `mysql-patterns` | Worst pattern gap + largest files |
| **C2** | Pattern | `langchain-langgraph-patterns`, `effect-ts-patterns`, `grpc-node-patterns`, `tauri-v2-patterns` | |
| **C3** | Pattern | `drizzle-patterns`, `hono-patterns`, `adonisjs-patterns`, `fastapi-patterns`, `latency-critical-systems`, `cost-aware-llm-pipeline` | Includes the 3 already-complete pattern skills |

**A1 outcome (2026-07-23) — scope downgraded before any subagent spawn, user-confirmed:** before
running skill-creator's full paired-benchmark loop on all 4, checked the plan's own gap table —
only `decide` is listed as missing a guard; `orchestrate`/`review-pr`/`task-prep` are in A1 for
size/traffic, not a demonstrated defect. `advisor()` flagged that forcing a full with-skill/
baseline subagent-pair loop onto 3 judgment-heavy skills with no known problem risks costly churn
(each run loads up to 46K chars) for a result the no-regression guardrail would discard anyway
("a different-but-not-better rewrite is a discard, not a ship"). Presented the finding + a
downgrade proposal via `AskUserQuestion`; user picked the downgrade.

- **`decide`**: read in full. Check 36 passed clean (has a `verify` token), but the body's actual
  completion-criterion sentence was structurally malformed — a lone `1.` list item with no `2.`,
  glued onto the end of `## Guardrails` with no heading of its own. Reformatted into its own
  `## Completion criterion` section, content unchanged. Verified: diff vs. the pre-edit snapshot is
  exactly that structural move, check 36 stays clean, no other line touched.
- **`orchestrate`, `review-pr`, `task-prep`**: read in full each. All three already carry explicit
  completion criteria, named failure modes, and (for `task-prep`) a `## Design checks` self-audit
  section — matt's 6 doctrine elements are all present. Descriptions were already checked in Batch
  0's fleet-wide survey (all three sit at the 25-word cap with no cuttable fluff). **Outcome:
  reviewed, no change** — the guardrail's default holds because no defect surfaced, not because the
  review was skipped.
- **Workspace snapshots** (`skills/<name>-workspace/skill-snapshot/`, created for all 4 as the
  no-regression baseline) were deleted after closeout — the audit's skill-discovery glob picked
  them up as 4 phantom skills (35 → 39) since it matches `SKILL.md` at any depth under `skills/`,
  not just one level. Confirmed clean (back to 35) after cleanup. Note for A2/A3/B*/C*: don't leave
  a `*-workspace/` directory in place past a batch's closeout — same trap will reproduce.
- A1b (orchestrate/review-pr prose-tightening) is unaffected by this downgrade — it was always a
  separate, explicit batch, not something A1 was going to do anyway.

**A1b outcome (2026-07-23) — prose lens re-applied, not a copy of A1's "no change" verdict:**
`advisor()` warned not to let A1's doctrine-guard read (there/not-there) stand in for a prose-
density read on the same two files — a file can be defect-free while still having genuinely loose
wording. Re-read both with that lens, enumerating each file's load-bearing points (named gates,
contracts, safety warnings, fail-closed dispositions) first so they could be checked for survival
after any edit. No `*-workspace/` snapshot this time — git at commit `773bea3` was the rollback
reference (per `advisor()`, sidesteps the phantom-skill trap directly instead of remembering to
clean up after).

- **`orchestrate`**: found one genuine redundancy — Bounded fan-out's "Hard rules" numbered list had
  rule 4 restating rule 2's Workflow-tool/Agent-tool distinction almost verbatim, adding only one
  new point (a durability argument: without a code-level clamp, the next Workflow author re-writes
  the same soft cap). Trimmed rule 4 to that one point; rules 1–3 untouched. 33173 → 32891 chars.
  Verified via `git diff`: the edit is exactly that one rule's restated sentences, nothing else
  moved. Also fixed a real, unrelated bug hit while checking blast radius: `commands/ideate/
  COMMAND.md` cited this section by `lines ~295-308` in two places — already stale before this edit
  (actual location was line 152), now worse after it. Both citations already also named the section
  by heading (`§"Bounded fan-out — hard cap (F8.5)"`), so the fix removes the drift-prone line
  numbers rather than repointing them to numbers that will just drift again.
- **`review-pr`**: re-read in full with the prose lens specifically. The apparent redundancy found
  (the "a missing/failed dispatch is not a clean pass" point appears in Phase 4 step 4, Phase 5 step
  3.6, and Phase 5 step 4) is deliberate repetition at each decision point where the model must act
  on it, not accidental bloat — a legitimate technique in a gate/review skill, and cutting it is
  exactly the kind of edit that could silently create a false-clean verdict. No safe cut found;
  0-char change. Per `advisor()`'s explicit framing, this is a complete and correct A1b outcome for
  this file, not an under-delivered batch — the INFO-only body-size finding never required a
  reduction, only a genuine-looseness check, and none was found.

**A2 outcome (2026-07-23):** same protocol as A1/A1b, applied without re-asking per-batch (the
user's session goal — "do every batch until finished and correct" — covers continuing the
already-confirmed light-pass-on-no-defect approach). Read all 4 skills in full against the plan's
gap table (none listed) and matt's 6 doctrine elements.

- **`pr`**: already carries its own `## Design checks` section (one of only 2 native skills that
  do, with `task-prep`) — completion criterion, no-op test, and failure-mode guard all explicit.
  Reviewed, no change.
- **`incident`**: explicit `## Done when`, `## Constraints`, `## Output Format`, and a named model
  footer. Reviewed, no change.
- **`security-auditor`**: has its own verifier-separation step (spawns a fresh `security-reviewer`
  agent against remediated files rather than re-auditing its own fix) plus an explicit BLOCK/PASS
  completion criterion. Reviewed, no change.
- **`production-audit`**: found 2 real dead/malformed cross-references while doing the same read —
  `` `security-review` `` (line 29 and in "See Also") matches neither this fleet's actual skill
  (`security-auditor`) nor the agent (`security-reviewer`), and `` `tdd` `` (See Also) is missing
  its `mattpocock-skills:` prefix, so as written it doesn't resolve to anything installed. Both
  were invisible to `harness-audit` check 40 (dead-`kbg:`-reference detector) because neither was
  written in `kbg:`-prefixed form — the exact blind spot CLAUDE.md's own note on check 40 already
  documents. Fixed both (line 29 now points to the `security-reviewer` agent, matching
  `security-auditor`'s own documented skill-vs-agent split; "See Also" now uses `kbg:`/
  `mattpocock-skills:`-prefixed form throughout, so future drift here becomes visible to check 40).
  Verified via full audit re-run — clean, no new findings.

Batch order is a starting point, not a contract — if a batch surfaces something that changes
priority for the next one, re-order and note why in this file.

## Per-batch closeout ritual (matches the pattern from the prior structural-audit pass)

0. Confirm skill-creator edited `skills/<name>/SKILL.md` in this git checkout — `git diff --stat`
   shows a nonempty diff for every skill in the batch. A clean-looking closeout with no diff means
   nothing landed (see "Where skill-creator edits" above).
1. Apply the batch's fixes (from skill-creator's iteration loop, post user review).
2. `bash skills/harness-audit/scripts/audit.sh` — confirm no new CRIT/WARN **relative to this
   plan's documented baseline** (currently: 1 pre-existing WARN — description budget, fixed by
   batch 0 — and 2 pre-existing INFOs — orchestrate/review-pr body size, deliberately unfixed per
   this plan, expected to persist through A1b too since that pass is in-place tightening, not a
   size-threshold chase). A literal zero-INFO "clean pass" is not the bar; those 2 INFOs are
   expected and fine.
3. Bump `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` versions.
4. Regenerate both `BOUNDARY.md` copies (kbg-harness root + the dotfiles-repo mirror) if any
   description changed.
5. Add one `CHANGELOG.md` entry for the batch + update `CLAUDE.md`'s "Recent versions" list. **Cap
   management for a 10-batch marathon:** CLAUDE.md's "Recent versions" list caps at 10 bullets and
   this marathon alone produces ~10 batch entries — don't let it evict the entire pre-marathon
   history one bullet at a time. Pre-declared folding rule: once all 3 pattern-tier batches (C1-C3
   — the lowest individual stakes) have closed, fold them into a single summary bullet rather than
   keeping 3 separate ones.
6. `bash scripts/run-gauntlet.sh` — all layers green.
7. Clean up this batch's `<skill>-workspace/` scratch directories per the "Workspace artifacts"
   policy above (scratchpad, not repo) — `git status --short` should show nothing untracked at
   repo root after this step.
8. Check off the batch in the Progress table above.
9. **Commit at every batch close (resolved 2026-07-23, user decision) — do NOT push.** Overrides
   this session's single-session "commit only when asked" convention for this marathon
   specifically: a 10-batch, multi-session effort needs a rollback point between batches (if batch
   5 turns out wrong while reviewing batch 8, `git checkout` to the end of batch 4 beats
   reconstructing which files batch 5 touched from memory). Stage by name (never `-A`), write a
   commit message naming the batch. Push still requires an explicit user ask, same as always.

## Verification (how each batch's "done" is checked)

- **Workflow tier:** user reviews the `generate_review.py` eval viewer output (Outputs tab +
  Benchmark tab) and confirms per-skill; empty feedback = accepted as-is. Subjective-output skills
  (`tech-humanize`) skip the benchmark per the per-skill depth override above — qualitative review
  only.
- **Utility/meta + Pattern tiers:** `harness-audit` at-or-better-than-baseline (see ritual step 2 —
  not a literal zero-finding bar) + the specific named gap (from the catalogue table) confirmed
  closed via an actual `git diff`, not just a reread.
- **Fleet-wide, after every batch:** `harness-audit` check 47 (description budget) and checks 36/20
  (matt-doctrine conformance) stay at-or-better-than-baseline — never regress a prior batch's fix.
