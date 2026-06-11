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
