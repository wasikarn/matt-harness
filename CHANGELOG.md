# Changelog

All notable changes to `kbg` are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

Pre-`1.0.0`: breaking changes may land in any `0.x` release.

## [0.1.2] — 2026-06-11

Patch release — surfaces two post-`0.1.1` fixes as a clean release line. No new features, no
breaking changes.

### Fixed

- **G15 (P0): harness-audit cache-version hardcode.** `audit.sh:70` hardcoded `0.1.0` as the
  default plugin-cache path. When the cache bumped to `0.1.1/` (or any future `0.x.y/`), the
  hardcoded default pointed at a missing directory, silently setting `PLUGIN_ACTIVE=0` and
  disabling the F1 plugin-aware bypass — surfacing **61 false-positive CRITs** on `audit.sh`
  (the very thing the F1 rework in `0.1.1` was meant to fix). Now resolves the cache version
  dynamically via `ls | sort -V | tail -1`. (`846452a`)

### Added

- **CI: `.github/workflows/validate.yml`** — runs `claude plugin validate --strict .` on every
  push and PR to `main` and `develop`. Catches schema / manifest drift before publish; pairs
  with the existing pre-commit harness-audit + critical-hooks gates. (`9f704f0`)

### Patched (2026-06-11, post-release)

Three commits landed after `0.1.2` was tagged. They are non-functional (no runtime change, no
manifest drift, no version bump) — included here for archaeology and so a future reader of
`orchestrate` / `critical-eval` / `article-mine` / `acli` can trace why the descriptions differ
from the pattern in earlier versions. The auto-trigger re-measure (window 2026-05-25→now,
scope `kobig`) confirmed **no regression**: custom auto-rate flat at 38% (76/199), all-skills
auto-rate flat at 46% (131/286).

- **Description trim cycle (4 skills).** All 26/26 kbg-harness skills now under the 700-char
  UI truncation threshold. Body content byte-identical; only `description:` lines touched.
  - `orchestrate`: 978 → 685 chars (`38c1c40`)
  - `critical-eval`: 802 → 686 chars (`38c1c40`)
  - `article-mine`: 713 → 642 chars (`3d03444`)
  - `acli`: 703 → 628 chars (`3d03444`)
  - All sibling cross-refs + all quoted trigger phrases + all negative-scope examples
    preserved verbatim. Watch-out: `acli`'s "ALWAYS trigger" + "ANY" are load-bearing safety
    signals for bulk-mutation — do not strip in any future trim.

- **measure-autotrigger: opt-in plugin-cache fallback.** Post-cutover (commit `962bfce`),
  `kbg-harness/skills` and `kbg-harness/commands` no longer live under a `claude/` subdir,
  so the `--repo-root` lookup misses. Added `--use-plugin-cache-fallback` flag (default off,
  explicit opt-in to avoid silent data drift for unrelated repos) that walks
  `~/.claude/plugins/cache/kobig/kbg/<latest>/` and loads the latest semver directory.
  Closes the 5-line-patch TODO from `project_skill_autotrigger_remeasure_2026_06_11`. (`9080f0a`)

## [Unreleased]

Entries are listed in chronological order (oldest commit first within each subsection), so a
reader can trace the audit + fix chain end-to-end without re-sorting. Grouped by Keep-a-Changelog
category (Added / Changed / Fixed) within each phase.

### Phase 1 — Post-0.1.2 patches (pre-Loop-Engineering)

#### Changed

- **Delivery model: symlink farm → persistent plugin-enable.** The owner now installs `kbg` via
  `claude plugin install` + `enabledPlugins["kbg@kobig"]: true` and dogfoods exactly what an
  external installer gets — **superseding** the 0.1.0 "bare-name symlink farm, plugin disabled
  locally" model below. `install.sh`'s component-symlink steps are neutered and the in-`~/.claude`
  symlink farm removed, so the plugin is the single delivery path. (`dotfiles` `962bfce`)
- **Manifest accuracy** — `marketplace.json` description aligned with `plugin.json` ("governance
  hooks across 14 lifecycle events"); `.code-review-graph/` gitignored so no stale local SQLite
  cache ships; `version` retained (omitting it fails `claude plugin validate --strict`). (`c50710b`)

#### Fixed

- **Doctrine loads on every session start, not just fresh start.** `doctrine-bootstrap.sh` moved
  from the `startup` matcher into a no-matcher SessionStart group, so METHODOLOGY/RTK/ACLI/DBGATE
  inject on **resume** and **clear** too — matching the old `@import` behavior (`CLAUDE.md` was read
  on every session). Previously a resumed session got no doctrine once the dotfiles `@import` glue
  was removed. (`cc9bee8`)

### Phase 2 — Loop Engineering adoption (PRs #11–#14)

#### Changed

- **Loop Engineering adoption — stop-signals, anti-cheat, and the autonomy invariant's canonical
  home** (`c58e02d`, PR #11). Surgical doc-edits adopting the harness-engineering corpus, each
  terminating at an existing human gate (no new agents/hooks/state):
  - `METHODOLOGY.md` Rule 4 gains one sentence — a verification stop-signal must reduce to an
    objective check (test / exit code / fresh-context adversarial pass), and a verifying agent must
    get fresh context, not the implementer's transcript; scoped so it does not loosen the human
    approval gates.
  - `CONTEXT.md` §Invariants now **canonically homes the autonomy invariant** (+ judgment-
    preservation rationale), repointed from a phantom `HARNESS.md` citation that git confirms never
    existed — also removed from `doctrine-edit-gate.sh`, `block-bash-doctrine-write.sh`,
    `verification-gate.sh`, `hooks/tests/test-critical-hooks.sh`, `scripts/verification-tier-audit.py`,
    and `recursive-improve`. The stale "no plugin validation CI" non-goal corrected.
  - Stop-signal / anti-cheat edits to four workflows + two surfaces: `recursive-improve` (candidate
    executor escalates on repeated failure — Rule 13, no counter), `fix-bug` (Phase-3 no-progress
    halts), `address-review` (per-cluster cap + reclassify + author-aware dedup), `ship-merge`
    (zero-Critical / acceptance-gap checklist), `/accept-task` wiring into `feature-dev`/`fix-bug`,
    and a weakened-to-pass gap class in `pr-test-analyzer`.
- **Post-cutover doctrine rewrite** (`e8a1c95`) — `CONTEXT.md` + `docs/adr/0001-plugin-as-delivery.md`
  rewritten to describe the persistent-plugin-enable state. Inverts the no-double-fire invariant:
  the load-bearing guard is the `install.sh` neutering of the 6 `install_claude_*` symlink-farm
  calls (the symlink farm no longer exists; `doctrine-edit-gate.sh` is belt-and-braces, not primary).
  Adds `docs/adr/README.md` index. Documents the `.scratch/<slug>/` convention in `issue-tracker.md`.
- **Inventory labels dehardcoded** (`b03a556`) — `inventory-boundary.sh` no longer hardcodes
  `/Users/kobig/...` in `print_source` and `print_boundary` (mirrors the `audit.sh` repo-root-aware
  pattern from G15). `BOUNDARY.md` regenerated; host-portable labels (`Personals/kbg-harness`,
  not absolute path). **Activates harness-audit check #16 (fleet-drift detection, advisory)** —
  deactivating by deleting `BOUNDARY.md` reverts to the W1 state.
- **4 pre-existing defects flagged by the epic audit** (`d9a1b2e`, PR #14) — `ARCHITECTURE.md`
  ref-repoint (README→`CONTEXT.md`, CHANGELOG→ADR 0001), created `docs/adr/README.md` index,
  documented `.scratch/<slug>/` convention in `issue-tracker.md`, fixed `inventory-boundary.sh`
  (hardcoded `GIT_ROOT/claude` → repo-root-aware post-cutover map) + committed a real
  `BOUNDARY.md` so check #16 (fleet-drift) can fire. Repo at **0C / 0W / 22I exit 0** after the
  regeneration.

#### Added

- **`docs/harness-decay-cadence.md`** (`bcc594f`, PR #12) — names the human-run build-to-delete
  review cadence (record each component's model-limitation assumption; disable-and-measure on model
  upgrades; delete via a `decommission` witness; never auto-delete maker≠checker). The
  `## Permission re-audit` section (added later in `34cd064` / `61e335b`, see Phase 3) covers
  per-agent `tools:` frontmatter grants + `dotfiles/claude/settings.json` allowlist, with a
  copy-pasteable `git diff` snippet and quarterly cadence.
- **`docs/agents/verification-trail.md`** (`bcc594f`, PR #12) — documents the
  `.scratch/<feature>/verification-trail.md` schema that `verification-gate.sh` referenced but
  that never existed.

#### Fixed

- manifest: bump skill count 25 → 26 (memory-trim added) — (`9f0723f`, pre-0.1.2; surfaced here
  for cross-reference)

### Phase 3 — Loop-Engineer audit (3 med gaps closed; Q3=a surfaced as #15)

#### Added

- **`hooks/db-write-gate.sh`** (`34cd064` → `5ecdac8` → `61e335b`, PR #16 closed-superseded) —
  deterministic PreToolUse gate for `mcp__*__execute_sql_*` (and `mcp__*__db_write|db_query`).
  Closes the enforcement asymmetry: `rm` and doctrine-file edits already had gates, but a
  non-SELECT `execute_sql_production` had none. Allow-through: `SELECT`/`EXPLAIN`/`WITH…SELECT`/
  `information_schema`/comment-only. Ask: `INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`/`ALTER`/`DROP`/
  `CREATE`. Bypass: `CLAUDE_DISABLED_HOOKS=db-write-gate`. jq-missing → fail loud. **14 new test
  cases** in `hooks/tests/test-critical-hooks.sh`. The revert chain (`5ecdac8`) was transient —
  the fix landed on develop as `61e335b` "Reapply" the same content. PR #16 was then closed-
  superseded (work is on develop; the PR was a workaround for an earlier GitHub "no commits"
  rejection).
- **Audit check #30 — eval-target freshness** (`34cd064` / `61e335b`) — scans `**/evals.json` and
  `scripts/run-baseline-eval.py` for a `last_reviewed:` ISO date. Older than
  `KBG_EVAL_MAX_AGE_DAYS` (default 180) without a `last_reviewed_reason:` → emit `info`. The 2
  targets this PR owns (`skills/harness-audit/evals/evals.json` + `scripts/run-baseline-eval.py`)
  are stamped `last_reviewed: 2026-06-11`; the other 21 `evals.json` files surface as advisory
  info findings.

#### Fixed

- **Check #30 honor `last_reviewed_reason:` on the missing branch** (`57f6041`) — the original
  check #30 only suppressed the freshness info on the path where the JSON was parsed but the
  `last_reviewed:` key was missing. The branch where the JSON itself was missing (e.g. a
  partial-write) silently re-fired. Both paths now consult `last_reviewed_reason:` and skip
  the advisory when present. Audit dropped from 22 I1s to 0 with the `582bef7` deferral.
- **Inventory linter fix** (`9700242`) — sibling drift with `b03a556`: `print_source` + `print_boundary`
  labels in `inventory-boundary.sh` were using a hardcoded host path; dehardcoded to relative
  `Personals/kbg-harness` form (matches the `audit.sh` repo-root pattern).

#### Changed

- **Permission re-audit section in `docs/harness-decay-cadence.md`** (`34cd064` / `61e335b`) —
  appended after the build-to-delete cadence. Covers per-agent `tools:` frontmatter grants +
  `dotfiles/claude/settings.json` allowlist, with cadence (quarterly / on model upgrade / on agent
  merge) and a copy-pasteable `git diff` snippet that surfaces newly-added tool grants since the
  last review. `last_reviewed: 2026-06-11` stamp at the section top.
- **BOUNDARY.md regen post-linter** (`f30cec9`) — `inventory-boundary.sh` after the `9700242` label
  fix produced a fresh `BOUNDARY.md` with host-portable labels; closes the W1 audit warning.

### Phase 4 — Quarterly cadence + Layer 2 ask-gate (Q3=a resolution)

#### Changed

- **Bulk deferral of 21 `evals.json` to the 2026-09 quarterly cadence** (`582bef7`) — adds
  `last_reviewed_reason: "not reviewed in 2026-06-11 epic; deferred to quarterly cadence in
  docs/harness-decay-cadence.md (first sweep 2026-09)"` to 21 skills (acli, adr, assert-presence,
  backend-dev, clarify-first, critical-eval, decommission, hotfix, incident, inventory,
  memory-lint, migrate, orchestrate, perf, probe, research-brief, review-pr, security-auditor,
  semantic-code, ship-change, tech-humanize). Audit **0C / 0W / 1I exit 0** (1 = plugin cache,
  by-design). Per `docs/harness-decay-cadence.md`, the first sweep is 2026-09; this commit makes
  the suppression honest (the prior state would have been 22 stale-I1s that the check
  #30 fix in `57f6041` could not have helped with).
- **Pre-emit validator (Layer 2 ask-gate, additive)** (`39587ac`) — `scripts/review-pr-journal-
  pre-emit-validator.py` (new, 215 lines) is a CLI preflight that `/review-pr` SKILL.md step 4
  calls BEFORE the journaler. It re-imports the journaler's enum regexes
  (`TIER_OK` / `DISPOSITION_OK` / `DECISION_OK`) via `importlib` — **lockstep contract**, do not
  redeclare the enums in the validator. Reads `findings.jsonl`, skips `local_id`s in the
  `.journaled` manifest (same dedup as the journaler), surfaces enum-misses on stderr with
  per-finding detail (`local_id=X: tier='CRITICAL_TYPO'`). Exit 0 clean / exit 2 on miss / exit
  2 on missing-or-corrupt input. **Read-only — never writes the journal or the manifest.** On
  exit 2, `/review-pr` surfaces the validator's summary via `AskUserQuestion` (proceed / pause
  / cancel). The validator is an **ask gate, not a deny gate** — preserves the autonomy
  invariant. Q3=a is preserved verbatim: the journaler still WARNINGs and emits, the validator
  is the new ask-gate. Closes issue #15 (Option C, the split-concerns resolution). 4 new test
  cases (CC / DD / EE / FF) in `test-critical-hooks.sh`. `hooks/JOURNAL-SCHEMA.md` gains a
  "Two-layer design" section documenting both layers and the autonomy-invariant alignment.
  Green bar: 150/0 tests pass (was 146/0; +4 new), audit 0C/0W/1I exit 0, `claude plugin
  validate --strict` ✔.

### Phase 5 — Round-2 audit fixes (F1–F6 + reconcile)

Round-2 fresh-context audit (2026-06-11, 5-agent pipeline: 4 parallel corpus readers + 1
reconcile) re-surveyed the harness against the full `raw/ai-agents/harness-engineering/`
corpus (now 16 files / 221 concepts, up from 14/221 at round-1). Verdict: **harness is
healthy; round-1 conclusions hold across production / self-repair / loop-engineering
sub-corpuses**. The autonomy invariant and Q3=a remain intact. 6 deduplicated findings
shipped in 7 commits; the user accepted all 6 (`do_now` / `file_issue` / `reject` → enrich).

#### Changed

- **Validator stderr wording** (`69a4f84`, F1) — `scripts/review-pr-journal-pre-emit-validator.py:188-189`
  renames `"BLOCK: … journaler MUST NOT run until cleared:"` → `"ASK-GATE: … AskUserQuestion
  will surface the choice (proceed/pause/cancel):"`. Behavior unchanged (Layer 2 ask-gate
  per Q3=a; the `AskUserQuestion` in `/review-pr` SKILL.md:233 preserves the human's
  choice). The old wording leaked deny-gate framing into an ask-gate surface; the new
  wording names the mechanism correctly. The autonomy invariant (CONTEXT.md §Invariants)
  is load-bearing; the validator's text now matches its actual mechanism. 2 test grep
  assertions in `test-critical-hooks.sh` updated (the brief estimated 10; the actual
  count was 2 — the other 8 were test-local variable names that the brief said to leave
  alone).
- **Comprehension debt / cognitive surrender as autonomy-invariant corollaries**
  (`ab3508e`, F5) — `METHODOLOGY.md §4` gains a 2-sentence corollary: a working loop whose
  human has not personally read is **comprehension debt at compound interest**; the pull
  to accept the loop's output without forming an opinion is **cognitive surrender**. The
  autonomy invariant protects against both by ensuring every loop terminates at a human
  gate. Doctrine only — no behavior change, no mechanism added.
- **Irreversible-action class section** (`83b866b`, F6) — `docs/harness-decay-cadence.md`
  gains a new "Irreversible-action class (gates the harness already has)" section that
  (a) names the class, (b) maps each of the 4 existing class-shaped gates (DB writes,
  secret reads, config edits, doctrine edits — verified against `hooks/hooks.json` line
  numbers), and (c) records the precedent so a future `deploy-gate` / `external-api-gate`
  can find the right pattern. No mechanism added; this is a map of existing territory.
- **`model_limitation:` optional frontmatter field** (`f940729`, F3) — `docs/skill-template/SKILL.md`
  frontmatter gains an optional `model_limitation:` field authors can opt into, plus a
  "Model Limitation Assumption" body section with a worked example. Template-only — no
  actual skills/agents/hooks received the field (the Q3-a 2026-09 quarterly sweep will
  surface opt-ins for the human to re-verify). Per the autonomy invariant, no automation
  walks the field; the human does.

#### Added

- **`exit_reason` field on `verification_summary` journal event** (`1079cc4`, F4) —
  `hooks/verification-gate.sh` adds a 2-case `exit_reason` derivation to the journaled
  JSON (`gaps > 0` → `"degrading"`; otherwise → `"complete"`); `hooks/JOURNAL-SCHEMA.md`
  documents the new field and the 5-value enum vocabulary (complete / blocked / stalled
  / degrading / timeout — `blocked` and `timeout` are deferred; they require per-trail
  status markers and wall-clock correlation out of scope for this fix; the journal
  consumer can add them later without breaking the contract); `scripts/governance-summary.py`
  prints a `Counter` breakdown of sessions by `exit_reason`. 2 new test cases (cases 10,
  11) in `test-critical-hooks.sh` use the existing `VGROOT` fixture (gaps) + a new
  `vgroot5-clean` fixture (clean). Q3=a preserved: the journaler remains best-effort,
  this adds a field; it does not block.
- **Audit check #31 — schema-rot detector** (`89ad9c3` + `953523f` reconcile, F2) — `skills/harness-audit/scripts/audit.sh`
  gains check #31 with 4 sub-checks: (1) skill `SKILL.md` canonical sections (## Input
  Contract, ## Output Format, ## Failure Modes) — info, one per skill; (2) `plugin.json`
  / `marketplace.json` `version` validity + 30-day cadence with `last_reviewed_reason:`
  justification — info when stale, crit when missing/unparseable; (3) `docs/harness-decay-cadence.md`
  `last_permission_review:` marker — info when missing/stale/malformed; (4) `hooks.json`
  shape — **crit** (structural) on non-string matcher, missing `type`, empty `command`,
  top-level shape. 2 new test cases in `test-critical-hooks.sh` (MM clean fixture, NN
  violating fixture with integer matcher + missing-type entry). 1 OO regression guard
  test (added at reconcile) verifies the empty-matcher refinement. Implementation
  notes: the original F2 spec said "matcher must be non-empty" but the real `hooks/hooks.json:415`
  uses empty matcher intentionally per `hooks/config-change-log.sh` header — refined at
  reconcile to require only that the value be a string. The check surfaces 26 advisory
  I1 on the current state: 24 skills missing canonical sections (pre-existing doc drift),
  1 PERM_BOOKMARK_MISSING in `docs/harness-decay-cadence.md` (pre-existing), 1
  plugin-cache (by-design). All advisory; not blocking; the 24 SKILL_MISSING findings
  are flagged for a separate sweep.

### Audit + Spec (2026-06-12, post-Phase-1-patches)

One-off audit of 27 agents, 27 skills, 8 commands, 33 hook scripts, 8 hook event types
against 16 claudefa.st articles (`.scratch/audit-2026-06-12/REPORT.md` v2, 644 lines).
6 v1 factual errors corrected during the audit — root cause was the `grep` shell alias
mapping to `rtk grep` (compact output unsuitable for stat queries); workaround documented
in project memory. Top finding re-ranked: **F1 — validator `Bash` constraint** is the
only safety gap (REPORT.md § 7 correction #6: validators are convention-only read-only,
gated only by `orchestrate`'s `AskUserQuestion`); all other findings are capability or
polish.

#### Added

- **Spec for closing the 7 audit findings + 3 drift items** (`.scratch/audit-2026-06-12/SPEC.md`)
  — 3 phases (T1 safety / T2 capability / T3 polish), ~17-28 hours total, per-phase
  `ACCEPTANCE.md` at phase start in `.scratch/phase-N-.../`. 5 open questions logged
  at the bottom of the spec for owner review before Phase 1 starts.

### Phase 1 — T1 safety fixes (F1 + F2 + F4 + F11 + F12 + D5, 2026-06-12, 1 commit)

Closes the 4 T1-safety items from `.scratch/audit-2026-06-12/SPEC.md` Phase 1 plus
2 revalidation extensions from the 16-article parallel re-read (`.scratch/article-
revalidation-2026-06-12/delta-vs-REPORT-v2.md` — F11, F12, D5). 6 fixes, 247
insertions, 7 files.

#### Added

- **`hooks/validator-bash-guard.sh` (F1)** — new PreToolUse Bash hook that gates
  the 7 validator-class agents (`code-reviewer`, `code-explorer`, `code-architect`,
  `comment-analyzer`, `pr-test-analyzer`, `silent-failure-hunter`, `security-reviewer`)
  against 11 mutation patterns (`git push|reset --hard|clean -fd`, `rm`, `sed -i`,
  `>file`, `mv → /`, `chmod`, `chown`, fork-bomb, `curl -X POST|PUT|DELETE|PATCH`,
  `npm publish|uninstall`, `pip uninstall`). Reads `agent_type` from stdin JSON per
  vendor spec (code.claude.com/docs/en/hooks); fail-open for non-validators and
  main-thread (no `agent_type`). 7 allow-prefixes preserve read-only inspection
  (`git diff|log|show|status`, `ls|cat|head|tail|wc|grep|rg|find|jq`, `node -p`,
  `python3 -c`, `npm test`, `pytest`, `cargo test`, `go test`).
- **`## Validation chain (TaskCreate + addBlockedBy)` in `skills/orchestrate/SKILL.md`
  (F2)** — worked example for the builder → validator → fix → re-validator DAG
  with `TaskUpdate(addBlockedBy=[...])` wiring between Procedure and Fast Path Gate.
- **`### Consolidation (4-step merge)` (F11)** — Reports → Conflict Resolution →
  Priority Ranking → Action Plan subsection in the F2 chain section, closing the
  post-parallel-fan-in reconciliation gap.
- **`## Anti-patterns (distribution mistakes)` in `skills/orchestrate/reference.md`
  (F12)** — 4-mistake taxonomy (over-fragmentation, under-specification, resource
  conflicts, context duplication) sourced from 4 articles + 6 named anti-patterns
  (over-parallelizing, under-parallelizing, output-format-mismatch, overlapping-
  roles, F2-chain-without-merge, anti-pattern-in-this-list).
- **`## Nest-down pattern` in `agents/code-explorer.md` (F4)** — push noisy tool
  calls down to layer-2/3 agents, return only verdicts. Per nested-subagents
  article (vendor v2.1.172, 2026-06-09). Hard cap depth=5; build in 1 layer of
  margin.
- **`## Nest-down pattern` in `agents/researcher.md` (D5)** — same pattern with
  research-specific guidance (claim verification, WebSearch-cluster delegation,
  depth=3 absolute budget due to high-token WebSearch calls).
- **17 new test cases in `hooks/tests/test-critical-hooks.sh`** — 6 AC cases for
  F1 + 8 extra robustness (curl, chmod, mv, npm publish, read-only allow, main-
  thread fail-open) + 3 fork-bomb variants (caught a regex regression in the
  adversarial verify pass — no AC test covered the fork-bomb case; locked in
  with these tests).

#### Changed

- **`hooks/hooks.json`** — `validator-bash-guard.sh` appended to the PreToolUse
  Bash matcher (after `block-alias-shadowing`; preserves existing matcher order).
- **`skills/orchestrate/SKILL.md`** — Validation chain + Consolidation sections
  between "Procedure" and "Fast Path Gate".
- **`skills/orchestrate/reference.md`** — L4 cross-reference to SKILL.md's
  Validation chain; new Anti-patterns section at end.

#### Green bar

- `bash hooks/tests/test-critical-hooks.sh` → 176 passed, 0 failed (was 172)
- `bash skills/harness-audit/scripts/audit.sh` → 0 Critical (was 1), 1 Warning
  (pre-existing), 26 Info (baseline)
- `claude plugin validate --strict .` → passed

#### Verification

- 6 fresh-context adversarial verifiers (1 per fix + 1 spec-consistency). 5 PASS;
  1 F1 verifier FAIL caught a fork-bomb regex regression — fixed and locked in
  with 3 new fork-bomb test cases.

#### Out of scope (deferred to Phase 2 / 3 / 4)

- F3, F7, D1, D2 (Phase 2 capability) — separate phase
- F5, F6, D3 (Phase 3 polish) — separate phase
- D6, D9 (Phase 4 deferred) — `usage-monitor/` skill + personality-injection
  commands not in this epic
- D4, D8, D10 (Phase 2 doc adds) — ship with Phase 2 spec
- 5 open questions from SPEC.md — owner review pending

### Phase 2 — T2 capability fixes (F3 + F7 + F8 + F9 + F10 + D1 + D2 + D4 + D8 + D10, 2026-06-12, 1 commit)

Closes the 7 T2-capability + 3 doc items from `.scratch/audit-2026-06-12/SPEC.md` Phase 2
scope (one big phase per 2026-06-12 owner resolution; 22-30h estimated). Folds F8/F10/
D8/D10 into the F3 command files rather than shipping them as separate skills (per
the spec's "compactness rule"). Acceptance contract at
`.scratch/phase-2-capability-2026-06-12/ACCEPTANCE.md`.

#### Added

- **`commands/team-plan.md` (F3 step 1-3)** — first half of the agent-teams workflow.
  Walks user through `## Brain dump` → `## Q&A log` (≥ 10 answered questions, hard
  requirement, refuse if < 10) → `## Structured plan` with `## Team Members` (3-5
  members, F8 sweet spot, refuse if outside range), `## Step by Step Tasks` table
  with `Depends On` / `Assigned To` / `Files` / `Criteria` / `Constraints` columns,
  `## Acceptance Criteria` (machine-checkable), `## Validation Commands`. Emits the
  plan file at `.claude/tasks/<slug>.md` — the **D10 plan-file interface** (session-
  resettable, lead-handoffable decoupling; a fresh session, a different lead, or a
  partial resumption all work from this single artifact). Adds `INT-N` integration
  validator task with `addBlockedBy=[all-builders]` for the **D8 cross-component
  seam check**. `disable-model-invocation: true` (per the autonomy invariant —
  humans invoke, not models).
- **`commands/team-build.md` (F3 step 4-7)** — second half. Step 4 = soft-warn
  fresh-session gate (AskUserQuestion with 2 options; if denied in non-interactive
  mode, **refuse to dispatch** and log the refusal — no silent fall-through). Step 5
  = **F10 plan approval filter** (pre-execution gate; rejects plans that violate
  schema-without-migration / auth-without-security-reviewer / external-service-
  without-fallback / overlapping-file-ownership / no-integration-validator). Step 6
  = wave execution with the **F9 spawn-prompt template** injected into every
  spawn (What/Where/Focus/Deliverable/FILES YOU OWN/UPSTREAM CONTRACTS/Files+Criteria
  +Constraints/Done-when). **F8 model split**: `model: "sonnet"` for teammates by
  default; lead stays on Opus. Step 7 = per-criterion validation, integration
  validator verdict, leftover risks surfaced (rule 12 fail-loud).
- **F9 spawn-prompt template in `skills/orchestrate/SKILL.md`** — 4-slot prompt
  (What/Where/Focus/Deliverable) + FILES YOU OWN + UPSTREAM CONTRACTS + Files+
  Criteria+Constraints + Done-when, plus 4 anti-patterns ("Implement feature X"
  with no slots, topic as deliverable, implicit file ownership, missing upstream
  contracts in Wave 2+). The template is the rendering format; the plan file is
  the data source. Gates F3 step 6.
- **F8 lead-coordinator doctrine in `skills/orchestrate/SKILL.md`** — 4 rules:
  (1) Shift+Tab delegate mode is the default for the lead (the lead does not write
  code); (2) Opus-lead + Sonnet-teammate cost split (largest token-cost lever in
  agent-team mode); (3) plan-mode lifetime is fixed by the plan, not the session;
  (4) 3-5 teammates is the empirical sweet spot. Doctrine, not preference — each
  rule exists because the failure mode (silent conflict, cost cliff, chain break,
  coordination-drown) is real and observable.
- **F7 TaskCompleted test-claim gate in `hooks/task-lifecycle.sh`** — new branch
  blocks a teammate from completing if the event payload contains a test-claim
  keyword (`tests pass`, `pytest`, `npm test`, `cargo test`, `go test`, `tsc
  --noEmit`, `pnpm test`, `yarn test`, `jest`) without a `validation_command:`
  field. **Critical convention distinction**: TaskCompleted uses **exit 2 + stderr
  feedback** per vendor spec at `code.claude.com/docs/en/hooks` § TaskCompleted
  — NOT exit 0 + JSON `permissionDecision` like PreToolUse gates. Exit 2 sends
  stderr as feedback to the teammate; exit 1 is non-blocking. False-positive
  guards: bare keywords (`pytest`, `jest`, `tsc`) are anchored at non-word
  boundaries via the `[^a-zA-Z0-9_]` character class, with `CLAIM_TEXT` pre-padded
  with spaces so the boundary matches at the start/end of subject/description
  strings (BSD `grep -E` has no `\b` word-boundary; the pad + non-word class is
  the portable equivalent). **F7 is the post-execution half of the quality
  pipeline; F10 is the pre-execution half.** 2 distinct layers, 1 goal.
- **F7 test coverage (+9 cases) in `hooks/tests/test-critical-hooks.sh`** — F7a
  positive (test-claim + validation_command → exit 0), F7b block (test-claim
  without validation_command → exit 2 with stderr feedback), F7c multi-word
  patterns (`pytest -v`, `npm test --coverage`), F7d edge case (uppercase
  `PYTEST` / mixed `Npm Test`), F7e no-claim (subject/description clean → exit 0),
  F7f claim with non-test context (`tests we wrote` + validation_command present
  → exit 0), F7g false-positive regression guards (`majestic`, `jesting`,
  `jestful`, `pitsc`, `sppytest` — must NOT block), F7h positive boundary-class
  regression guards (standalone `jest`, `jest green`, standalone `tsc`, `pytest
  as a word` — must block). Uses a new `check_task` helper that asserts on exit
  code + stderr substring (NOT stdout JSON — TaskCompleted convention is
  different from PreToolUse).

#### Fixed

- **Plugin manifest drift (D1 + D2)** — `.claude-plugin/plugin.json` description
  updated from "26 workflow skills" to "27 workflow skills" and from "8 commands"
  to "10 commands" (D2 drift), plus adds mention of `/team-plan` + `/team-build`
  and Agent Teams opt-in flag (D1, since the `agentTeams` field is not in the
  vendor schema — surfaced via the `keywords` array extension instead, adding
  `"agent-teams"`, `"team-plan"`, `"team-build"`). The 27-skills count
  (`accept-task`, `acli`, `adr`, `article-mine`, `assert-presence`, `backend-dev`,
  `clarify-first`, `critical-eval`, `decommission`, `harness-audit`, `hotfix`,
  `incident`, `inventory`, `memory-lint`, `memory-trim`, `migrate`, `orchestrate`,
  `perf`, `probe`, `research-brief`, `review-pr`, `security-auditor`,
  `semantic-code`, `ship-change`, `tech-humanize`, plus the 2 added in this
  phase) reconciles against `ls -d skills/*/`. The 10-commands count
  reconciles against `ls -d commands/*.md`. **The BOUNDARY.md regenerator
  outputs `Skills (26)` due to a pre-existing multi-line-description parse bug
  on `tech-humanize` (uses `description: |` block scalar)** — accepted as
  out-of-scope for this phase; tracked for a separate regenerator-fix follow-up.
- **`skills/orchestrate/SKILL.md` back-reference (F3-2)** — F9 template cross-
  reference corrected from "Step 3" to "Step 6" (the F9 injection happens at
  team-build Step 6, not Step 3).
- **`commands/team-build.md` + `commands/team-plan.md` heading de-dup
  (F3-3)** — second `## Step 7` heading renamed to `## Step 7 done-when (final)`;
  same fix for `## Step 3` in team-plan.md. Prevents auto-linker / TOC
  collisions.
- **`docs/adr/0002-autonomy-invariant.md` "Mapping to Harness-Engineering
  Corpus Prescriptions" section** — 16-article corpus map (10 loop-engineering
  + 5 production-harness + 1 self-repair) with explicit "Harness Alternative"
  and "Divergence Rationale" columns for each L3/L4 prescription. Records the
  principled rejection of L3/L4 autonomy as a **deliberate divergence**, not a
  backlog gap. Gap-closure spec distinguishes "Blocked by ADR 0002" (L3/L4
  items, not backlog) from "Eligible for closure" (items that can be promoted
  without violating the invariant). This makes the autonomy invariant's
  reach explicit so future readers do not mistake a rejection for an oversight.

#### Out of scope (deferred to Phase 3 / 4 / 5)

- F5, F6, D3 (Phase 3 polish) — separate phase
- D6, D9 (Phase 4 deferred) — `usage-monitor/` skill + personality-injection
  commands not in this epic
- BOUNDARY.md regenerator `description: |` multi-line parse bug — pre-existing,
  surfaces as `Skills (26)` instead of `27`; tracked for a regenerator-fix
  follow-up phase

#### Verification

- 6 fresh-context adversarial verifiers + 1 spec-consistency verifier. 5 PASS;
  1 verifier FAIL caught the F7 false-positive regression (`jest` matching
  inside `majestic`) — fixed in 3 iterations and locked in with 9 new test
  cases (F7g negative, F7h positive boundary-class). Final state: 201/0 tests
  pass (was 192/0; +9 new). `audit.sh` green bar: `0C/0W/26I exit 0` (matches
  the 26-I1 baseline from ADR 0002 §Verification).
- 5 of 6 open SPEC.md questions resolved (sweet spot, 5-vs-3 teammates,
  model split, plan-file location, fresh-session gate handling); 1
  deferred (INT-N pre-task lock — answered with "validate after all builders
  complete" per the article).
- Plugin cache sync: 2 new commands copied to
  `~/.claude/plugins/cache/kobig/kbg/0.1.2/commands/`. Audit re-run on cache:
  `0C/0W/49I exit 0` (49 vs 26 because the cache lacks `docs/`, surfacing
  the by-design PERM_BOOKMARK info).

### Phase 3 — T3 polish fixes (F5 + F6 + D3 + D7, 2026-06-12, 1 commit)

Closes the 3 T3-polish items from `.scratch/audit-2026-06-12/SPEC.md` Phase 3 plus
D7 (TECH-LEAD-THAI × F5 conflict, surfaced by the 16-article parallel re-read
at `.scratch/article-revalidation-2026-06-12/delta-vs-REPORT-v2.md`).
F5 sample-review question #5 was resolved in Phase 1 ("no 3-agent sample
requested; ship in bulk"). Acceptance contract at
`.scratch/phase-3-polish-2026-06-12/ACCEPTANCE.md`.

#### Added

- **`## Voice` blocks in 26/27 agents (F5)** — per `human-like-agents` article
  (`claudefa.st` corpus) + REPORT.md § 2.15. Each voice block is 4-6 lines,
  inserted between `## Why this role exists` and `## Domain focus`, with the
  4 spec patterns: (1) uncertainty acknowledgment, (2) tradeoff naming,
  (3) reasoning out loud, (4) pattern recognition with a domain-specific
  example. Customized per role — `backend-engineer`'s pattern-recognition
  example is "I've seen this race condition in Postgres before — the fix is
  SELECT FOR UPDATE on the parent row"; `security-reviewer`'s is "I've seen
  this 'internal-only' assumption lead to a real breach before — the fix is
  a threat model." `code-reviewer` skipped (already has Two-Axis Triage at
  line 41). `<commentary>` blocks (meta-trigger) NOT touched — kept as-is
  per the spec's anti-pattern. Implementation: Python script
  (`.scratch/phase-3-polish-2026-06-12/inject_voice_blocks.py`) with a JSON
  lookup table (`.scratch/phase-3-polish-2026-06-12/voice-blocks.json`) and
  atomic temp-file-then-rename writes. Idempotent: re-running is a no-op.
- **`docs/agent-tool-patterns.md` (F6)** — 80-120 line convention reference
  for `tools:` (allowlist, the kbg-harness default — 27/27 agents) vs
  `disallowedTools:` (denylist, vendor alternative — used when the
  allowlist would exceed 6-7 tools or the team explicitly opts into
  implicit-inheritance). 5 sections: (1) allowlist pattern + what it
  excludes, (2) denylist pattern + when to consider it, (3) our convention
  (default allowlist; reserve denylist; review on Permission re-audit
  cadence), (4) examples from this harness (4 agents, with `tools:` line
  + rationale), (5) cross-references to ADR 0002, harness-decay-cadence
  Permission re-audit, F1 Bash-gate pattern, BOUNDARY.md Mutates column.
- **3 cross-references to `docs/agent-tool-patterns.md` (F6)** — `BOUNDARY.md`
  gains a 1-paragraph "Cross-references" section linking to the new doc;
  `skills/orchestrate/SKILL.md` Step 3 (dispatch decision) gains a 1-line
  note that "agent holds Bash" is reading the `tools:` line, not the
  runtime default; `docs/harness-decay-cadence.md` Permission re-audit
  section gains a 1-line convention reminder.

#### Fixed

- **TECH-LEAD-THAI × F5 voice block conflict (D7)** — D7 was a 16-article
  revalidation finding (delta-vs-REPORT-v2.md). Resolution: voice blocks
  open with a conditional line — "When the active output style is
  TECH-LEAD-THAI, this voice is suppressed in favor of the output style's
  directness." When the active style is `TECH-LEAD-THAI` (or any other
  no-narration style), the voice defers; otherwise the voice is in full
  effect. The autonomy invariant is preserved (no L3/L4 autonomy added;
  the conditional is a presentation switch, not a behavior change). The
  conditional line is the first content line of all 26 voice blocks;
  `output-styles/TECH-LEAD-THAI.md` retains its "no narration" rule as
  the active style when the conditional fires.

#### Out of scope (deferred)

- D6 (personality-injection command category) — Phase 4
- D9 (OTEL/usage-monitor for nested agent teams) — Phase 4
- BOUNDARY.md regenerator `description: |` multi-line parse bug
  (pre-existing, surfaces as `Skills (26)` instead of `27`) — regenerator-
  fix follow-up
- F3-1 (argument-hint bracket drift) — cosmetic, future commit

#### Verification

- All 26 target agents visually sample-checked (3 spot-checks: `backend-
  engineer`, `security-reviewer`, `ux-reviewer`) — voice is in-character,
  not boilerplate, customized to the domain.
- D7 conditional line appears as the first content line of all 26 voice
  blocks. `code-reviewer` skipped (no D7 line; Two-Axis Triage stands).
- `harness-audit` green bar: `0C/0W/26I exit 0` (no schema-rot regression
  from the new `## Voice` section).
- `claude plugin validate --strict .` ✔.
- `bash hooks/tests/test-critical-hooks.sh` → 201/0 (no regression).

### Phase 4 (D6) — Personality-injection commands folded into F5 extension (2026-06-12, 1 commit)

D6 from `.scratch/audit-2026-06-12/SPEC.md` considered shipping 3
personality-injection slash commands (`/debug`, `/architect`,
`/perspectives`) as a new command category. F5 voice blocks shipped
in Phase 3 (commit `4d2ad91`) made those commands thin wrappers over
existing `agents/*.md` voice blocks — the spec's own caveat
("not orthogonal to F5; fold into a future F5-extension if it ships")
now applies. Owner chose to **fold into an F5 extension doc** rather
than ship commands.

- 1 new file: `docs/agent-voice-extension.md` (146 lines) — covers
  the personality-wrapper pattern: when NOT to build a personality
  command (default), when one IS worth shipping (3 cases: ritual,
  context pre-load, output shape), the recipe for building one
  right (frontmatter + body contracts + anti-patterns), and worked
  examples for the 3 spec-named commands mapped to kbg-harness
  agents/skills.
- 0 commands shipped — F5 stays the single source of truth for
  "what does this agent sound like." The 3 worked examples in
  § 4 are recipes, not deliverables.
- 0 hook changes, 0 SKILL.md changes, 0 settings.json changes.
- `.scratch/phase-4-deferred-2026-06-12/ACCEPTANCE.md` locked at
  start-SHA `4d2ad91`; 3 open questions resolved (D6 → B, D9 → A,
  scope → 2 commits).
- Verification: `harness-audit` 0C/0W/26I (no new surface), plugin
  validate ✔, hook tests 201/0 (no regression).
- D9 (OTEL/usage-monitor) deferred to the next Phase 4 commit per
  the locked contract.

### Phase 4b — D9 OTEL/usage-monitor for nested teams (2026-06-12, 1 commit)

D9 from `.scratch/audit-2026-06-12/SPEC.md` flagged "~7x token cost
warning unaddressed" — vendor v2.1.139/145 emits `claude_code.llm_request`
and `claude_code.tool` OTEL spans with `agent_id` / `parent_agent_id`
attributes, but kbg-harness had zero OTEL config and zero cost-monitoring
skill. Owner resolved 2026-06-12 to ship **passive monitor only** (option
A), accepting the late-warning tradeoff to preserve the L2 invariant
(ADR 0002).

- 1 new skill: `skills/usage-monitor/` (SKILL.md 6.0K, scripts/usage-summarize.sh
  4.0K) — read-only cost + sub-agent usage summary, opt-in via `KBG_USAGE_MONITOR=1`.
  Surfaces stats from `~/.claude/usage/<slug>.jsonl`; no enforcement, no
  threshold gates, no L3/L4 actions.
- 1 new hook: `hooks/usage-monitor-capture.sh` (3.5K) — SessionEnd capture
  that reads the session transcript, extracts `agent_id` / `parent_agent_id`
  + token counts, appends one JSONL line per session. Best-effort, always
  exit 0, mirrors `session-summary.sh` posture.
- `hooks/hooks.json`: added the new hook to the SessionEnd list (between
  `verification-gate.sh` and `superset-notify-wrapper.sh`).
- 1 symlink: `~/.claude/skills/usage-monitor` → repo (for harness-audit
  F1 satisfaction and Claude Code loadability).
- 0 changes to `settings.local.json` — capture is fully opt-in via env var.
- 0 changes to doctrine, ADRs, or any gate hooks. ADR 0002 (L2 only)
  honored strictly.
- CHANGELOG: this subsection.
- SPEC.md (gitignored): D9 marked `RESOLVED 2026-06-12 (passive monitor
  shipped; no enforcement per ADR 0002)`.
- BOUNDARY.md regenerated: Skills count 26 → 27; the pre-existing
  regenerator `description: \|` parse bug resolved by the new skill's
  single-quoted `description: '...'` YAML.
- Verification: `harness-audit` 0C/0W/27I exit 0 (+1 I for new skill's
  canonical-sections schema-rot, same as 26 pre-existing siblings),
  hook tests 202/0 (+1 new critical-hook test), `claude plugin
  validate --strict` ✔.
- 3 smoke tests pass on `usage-monitor-capture.sh` (opt-out exit 0,
  opt-in no-input exit 0, bad-transcript exit 0).

**Phase 4 complete** (D6 in commit `f0d59a7`, D9 in this commit).
**Audit epic fully closed** — F1-F12, D1-D10 all shipped.

### Audit epic polish (2026-06-12, 1 commit)

Closes the 2 follow-on items the audit epic itself flagged but
deferred: F3-1 (Phase 2 doc-nit, cosmetic bracket-drift in
`argument-hint:`) and the `last_permission_review:` marker gap
(missing from `docs/harness-decay-cadence.md` since 2026-06-11).

- 5 `commands/*.md` normalized: `argument-hint:` rewritten from
  literal-bracket form (`"[topic or question]"`) to plain English
  (`Optional topic or question`) to match the convention used by
  4 other commands. Affected: `deep-dive`, `post-mortem`,
  `ship-merge`, `ship-release`, `status-update`.
- 1 `docs/harness-decay-cadence.md` edit: added
  `last_permission_review: 2026-06-12` marker (machine-checkable
  per `skills/harness-audit/scripts/audit.sh` check #31.3) with
  a one-line summary of what the re-audit covered. Marker is at
  start of a clean line (no backtick prefix — the audit's regex
  `^[\s#/*-]*` doesn't allow backticks).
- 0 hook / settings.json / agent / skill changes.
- Verification: `harness-audit` I-count 27 → 26 (the marker-info
  fired before the fix, the per-skill schema-rot count is back to
  the pre-D9 baseline of 26). Hook tests 202/0 unchanged, plugin
  validate ✔.

### Decay sweep + follow-on fixes (2026-06-12, 1 commit)

First quarterly decay-cadence survey (per `docs/harness-decay-cadence.md`),
read-only — followed by 2 owner-approved fixes (survey → decide → act).

**Survey** (3-agent workflow `wf_4b766bde-637`, 1096s, 138K tokens):

- F5 spot-check: 5-agent sample flagged `code-reviewer.md` as
  missing the `## Voice` + D7 TECH-LEAD-THAI conditional that
  Phase 3 commit `4d2ad91` was meant to introduce. Root cause:
  the Phase 3 spec skipped code-reviewer ("already has Two-Axis
  Triage at line 41") but the skip was over-broad — the D7
  conditional was meant to be added regardless, not skipped.
- F5 fleet-wide sweep (post-fix): 27/27 agents now have both
  `## Voice` block and TECH-LEAD-THAI conditional. F5 closed in
  spirit, not just in commit.
- Permission re-audit: `git diff 2d3c743..HEAD` for `tools:` or
  `"allow"` deltas → **0 matches**. All 26 agent `tools:`
  frontmatter lines byte-identical pre-/post-epic. Hook
  → agent tool alignment verified for F1 (7 validators
  correctly hold `Bash`+`Read`+`Grep`+`Glob`) and D9
  (SessionEnd, no agent grant needed). `last_permission_review:
  2026-06-12` marker is honest.
- Decay candidate sweep: 10 candidates surfaced, 1
  decomm-ready (DECAY-001: `commands/deep-dive.md` ↔
  `skills/research-brief` overlap), 9 keep-with-record for
  2026-06-25 recheck (14-day fair window). Hard guard
  preserved (no verifier candidate).

**Owner-approved fixes (this commit):**

- `agents/code-reviewer.md`: added `## Voice` block (defer-to-
  Two-Axis-Triage pattern) + D7 conditional at the same line
  offset as the other 26 agents. Post-fix fleet-wide grep
  confirms 27/27 compliance.
- `commands/deep-dive.md`: rewritten as a **thin user-invoked
  wrapper** around `skills/research-brief` (which has
  `context: fork` + `agent: researcher`). Same 5-phase UX
  (Scope → Local → External → Synthesize → Archive) preserved;
  body now documents the skill delegation explicitly. All 7
  cross-references from `skills/perf/SKILL.md`,
  `skills/migrate/SKILL.md`, `skills/adr/SKILL.md`,
  `commands/team-plan.md`, `hooks/orchestrator-nudge.sh`,
  `hooks/session-load.sh` remain valid.

**0 hook / settings.json / new-skill / new-agent changes.**

- Verification: `harness-audit` 0C/0W/26I exit 0 (baseline
  matched), 27/27 agents have Voice + D7 (grep-verified),
  hook tests 202/0 unchanged, `claude plugin validate --strict`
  ✔.

### Phase 6 — Round-2 drill-down + gap-closure (3 commits, 2026-06-12)

Round-2's fresh-context drill-down (5-agent pipeline: autonomy invariant, 5 honest exit
reasons, schema-rot detector, irreversible-action class, two-layer observability) found
the load-bearing concepts were 4/5 FULL and 1/5 PARTIAL — no enforcement gaps, but
**2 process gaps** in the autonomy invariant surface (no deterministic audit check, no
ADR) and **4 documentary drifts** that mislabel or hide harness semantics. This phase
closes all 6 with 3 commits (1 per concern), preserving the autonomy invariant's
5-surface shape while adding the missing deterministic guard + canonical record +
honest docs.

#### Added

- **Deterministic guardrail for the autonomy invariant** (`1d60b00`,
  `skills/harness-audit/scripts/audit.sh` check #32 + `hooks/tests/test-critical-hooks.sh`
  tests PP/QQ/RR) — `crit`-severity check that fails any audit run on a repo where
  `skills/recursive-improve/SKILL.md` is missing `disable-model-invocation: true` in
  frontmatter. Exact-match (regression-guarded against truthy typos like `: True`).
  Hermetic (single file read, no transitive dependencies). Pairs with the existing
  5 surfaces as the 6th — the deterministic pillar of the invariant's 3-pillar
  verification. `recursive-improve` stays the only harness-internal loop primitive
  and the only place the invariant's guard lives; the check does not pretend
  future skills need the same property.

- **ADR 0002 — Autonomy invariant** (`dd38247`, `docs/adr/0002-autonomy-invariant.md`,
  251 lines) — the canonical record of the irreversible decision. Mirrors ADR 0001's
  5-H2 structure (Context / Decision / Consequences / Rejected alternatives /
  Verification). Status: Accepted, **irreversible on the capability-bounding
  argument** ("a model that can verify its own work still cannot vouch for the
  operator's intent"). 5 implementation surfaces named (canonical home in
  CONTEXT.md, doctrinal reinforcement in METHODOLOGY, skill self-binding, decay
  hard guard, deterministic audit). 6 rejected alternatives catalogued
  (L3/L4 architectures, Evo meta-loop, Opik Ollie flywheel, Ralph Wiggum cadence,
  "lifting the invariant when models improve"). Cross-referenced from
  CONTEXT.md:46-56, `docs/harness-decay-cadence.md:54-67`, and the ADR index.

#### Fixed

- **4 documentary drifts from round-2 audit** (`957d597`, 3 files, +20 net lines) —
  honest-fixable doc-only changes that don't alter behavior:
  - L5 vocabulary cross-reference at `skills/orchestrate/reference.md:76` —
    first CONTEXT.md cross-ref in that file, names the autonomy invariant
    (CONTEXT.md §Invariants + ADR 0002) and clarifies L5 vendor primitives
    (`/schedule`, `/loop`, `CronCreate`) are for user-external tasks only.
  - config-change-log mislabel at `docs/harness-decay-cadence.md:80` —
    previously said "config-change-log + config-protection (gates Edit/Write
    on config files)", conflating a gate (`config-protection.sh`,
    `hook_decision ask`) with a logger (`config-change-log.sh`, append-only
    audit trail, no `permissionDecision`). Now names the actual role of
    each hook.
  - ask-vs-deny split acknowledgment at `docs/harness-decay-cadence.md:95` —
    `ask` is the default for human-supervised irreversible mutations;
    `deny` is reserved for actions the model should never be trusted to
    do even with human in-the-loop confirmation (secret-reads,
    doctrine-via-Bash). Cites the precedent files
    (`secret-read-guard.sh:36-41`, `block-bash-doctrine-write.sh:3-4`).
  - audit.sh 31.3 doc-code drift at `skills/harness-audit/scripts/audit.sh:920` —
    doc-comment claimed the check looks for `last_permission_review_sha`
    in plugin.json OR a `## Permission re-audit` section in
    harness-decay-cadence.md; the actual implementation (lines ~1008-1039)
    only checks harness-decay-cadence.md. Trimmed to match what the code
    does; names plugin.json equivalent as "not yet implemented" — honest
    over aspirational.

#### Out of scope (deferred to 2026-09 quarterly sweep per owner pick)

6 items flagged in the plan for future work, **not committed in this batch** —
matches the 2026-09 quarterly cadence for deferred items already in
`ACCEPTANCE.md`:

1. `next_id` subshell bug in `audit.sh:115-122` (every finding label is `I1`/`F1`/`W1`).
2. Unknown-`exit_reason` warning in `scripts/governance-summary.py:271`.
3. "schedule" disambiguation late in `orchestrate/reference.md:12` vs `:40`.
4. 24 SKILL_MISSING skills lacking the 3 canonical sections
   (`## Input Contract` / `## Output Format` / `## Failure Modes`).
5. 3/5 honest exit reasons (`blocked` / `stalled` / `timeout`) still
   un-emitted in `verification-gate.sh:74-89`.
6. Issue #15 WARNING→block trade-off (closed at `39587ac` with Q3=a
   = validator=ask-gate, journaler=best-effort).

Green bar after this batch: 158/0 tests, audit `0C/0W/26I exit 0` (no new
findings, no new check firing), `claude plugin validate --strict .` ✔.

## [0.1.0] — 2026-06-10

Initial packaged release. `kbg` was extracted from the owner's `dotfiles` harness into a
standalone, self-contained Claude Code plugin (`.claude-plugin/{plugin,marketplace}.json`,
`${CLAUDE_PLUGIN_ROOT}`-portable hooks).

### Added

- **27 senior-specialist agents** — `code-architect`, `backend-engineer`, `frontend-engineer`,
  `security-reviewer`, `devops-engineer`, `test-engineer`, `code-reviewer`, `code-explorer`,
  `silent-failure-hunter`, `type-design-analyzer`, and others (full list: `claude plugin details kbg`).
- **25 workflow skills** (now 26 in `0.1.1`; `memory-trim` added) — `orchestrate`, `clarify-first`,
  `harness-audit`, `recursive-improve`, `article-mine`, `decommission`, `migrate`, `research-brief`,
  `tech-humanize`, `memory-trim`, … (`skills/_lib/` holds shared shell helpers and is not a skill).
- **8 slash commands** — `address-review`, `deep-dive`, `feature-dev`, `fix-bug`, `post-mortem`,
  `ship-merge`, `ship-release`, `status-update`.
- **Governance hooks across 14 lifecycle events** — SessionStart, PreToolUse, PostToolUse,
  UserPromptSubmit, PermissionRequest/Denied, Stop, SessionEnd, PreCompact, and others. All hook
  commands resolve via `${CLAUDE_PLUGIN_ROOT}` (no hardcoded paths).
- **Always-on doctrine injection** — `METHODOLOGY.md`, `RTK.md`, `ACLI.md`, `DBGATE.md` injected at
  SessionStart via `doctrine-bootstrap.sh`.
- **TECH-LEAD-THAI output style** and the **catppuccin-mocha** theme.

### Design

- **Personal-harness-as-plugin (the deliberate model).** `kbg` is the owner's single source of
  truth, shipped as a plugin artifact. The owner installs it via a bare-name symlink farm
  (`install.sh`), **not** via plugin-install; the plugin is disabled locally
  (`settings.json: "kbg@kobig": false`) so its hooks never double-fire against the symlinked copy.
  See `docs/adr/0001-personal-harness-as-plugin.md`.
- **Doctrine is mandatory, not opt-in.** A stranger who installs and enables `kbg` inherits the
  owner's METHODOLOGY/RTK/ACLI/DBGATE conventions as-is. This is intentional for a personal harness;
  see `README.md` → "For external installers" for how to disable or adapt.
- **No bundled MCP/LSP servers** (`MCP servers (0)`, `LSP servers (0)`). Hooks that shell out to
  external tools (`rtk`, `qmd`, `memory-lint`, `code-review-graph`) degrade gracefully when those
  tools are absent.
- **Cost:** ~12.3k tokens always-on per session (doctrine + skill/agent descriptions), per
  `claude plugin details kbg`.

### Notes

- Not published to a public marketplace. Distribution is private (`wasikarn/kbg-harness`).
- Best-effort maintenance; no support SLA or backwards-compatibility guarantee pre-`1.0.0`. Fork to
  customize.
