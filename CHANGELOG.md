# Changelog

All notable changes to `kbg` are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

Pre-`1.0.0`: breaking changes may land in any `0.x` release.

## [0.3.10] — 2026-06-22

First real L3 `--auto` dry-run (ADR 0003 Slice-1 acceptance) found the in-loop gate was never
runnable under the flag — the prior "gauntlet-green" was only ever measured flag-OFF. Two blocking fixes.

### Fixed

- **`tests/hooks/runners/test-critical-hooks.sh`** — scrub `KBG_AUTONOMY_L3` / `KBG_L3_REVIEW_DONE`
  for a hermetic baseline. Under the flag, `_lib.sh` L3-immunity neutralizes the disable mechanisms,
  so 5 disable/flag-off assertions (gates, orphaned-runners, l3) failed → the in-loop gauntlet gate
  went red every cycle → the loop could never keep a commit. Now **433/0 under the flag**; flag-ON
  cases set the flag per-test.
- **`hooks/gates/block-dangerous-git.sh`** — full-anchored, flag-scoped carve-out allowing the loop's
  `git reset --hard <l3-precycle-* tag>` rollback (previously blanket-denied, blocking the loop's own
  red-cycle rollback). No compound command can ride the early exit; every other `git reset --hard`
  stays denied. +4 tests in `test-ch-l3.sh`.

## [0.3.9] — 2026-06-21

Passive learning-capture is now **default-ON** (opt out with `KBG_LEARN_CAPTURE=0`). Owner request.

### Changed

- **`hooks/session/learn-capture.sh`** — gate flipped from opt-in (`KBG_LEARN_CAPTURE=1`) to
  opt-out (`KBG_LEARN_CAPTURE=0`). Does **not** touch the autonomy invariant: APPLY stays
  human-gated (`kbg:learn`); CAPTURE was designed automatic from the start — OFF was rollout
  conservatism. More coherent with the feature's purpose (you forget `kbg:learn`, so you'd forget
  the flag too). **Scope:** default-ON applies to **all projects** the plugin is active in;
  captures are secret-scrubbed, out-of-repo, apply-gated. Per-shell opt-out `KBG_LEARN_CAPTURE=0`;
  per-hook `CLAUDE_DISABLED_HOOKS=learn-capture`. See
  [ADR 0002 addendum](docs/adr/0002-addendum-passive-capture.md) "Default flip".
- `test-ch-learn-capture.sh` gains a default-ON capture case; the off case now sets `=0` explicitly.

## [0.3.8] — 2026-06-21

Passive learning-capture **Phase 2** — fold two L3-loop guards into
`recursive-improve --auto` (within ADR 0003: human-launched, push-gated, computational).
Owner-scoped: build the goal-advancing pieces, **drop** the runaway-guard (active-hours/idle/
cooldown) as a category mismatch — those guard a *self-launching daemon*; kbg's loop is
human-launched and already bounded by `--max-runs` / `--max-duration` / `--fail-streak`.

### Added

- **No-progress cap (`--max-flat`, default 2)** in `scripts/l3-loop-guard.py` — ends an `--auto`
  run after K consecutive **green-but-flat** cycles (gauntlet passes but no audit/`gaps` metric
  moved). Distinct from `--fail-streak` (which counts reds). The `flat?` decision is a numeric
  delta the loop computes; the guard only counts (computational, never a model verdict). Covered
  by `test-ch-l3.sh` (no-progress STOP + improved-green reset).
- **Route B — learning-candidate queue read** in `scripts/pr/recursive-improve-observe.py`: a
  read-only "learning-candidate queue" section (shells out to `read-candidates.sh`, the single
  reader). In `--auto`, a high-confidence captured correction/preference is an eligible candidate
  (one per cycle, applied **gated at push**); the loop **reads, never writes** the queue — the
  human drains it via `kbg:learn`. `l3_cycle` journal gains an optional `source: queue` field.

### Changed

- **`skills/recursive-improve/SKILL.md`** — documents the no-progress cap + Route B in the `--auto`
  cycle; disambiguates the learning-candidate queue from the comprehension-debt "drain the queue".

## [0.3.7] — 2026-06-21

Passive learning-capture (Phase 1) — the "เรียนรู้เองอัตโนมัติ" pillar at the owner-chosen
**Maximal-bounded** point: adopt ECC's continuous-learning **capture half** (observe → queue),
human-gate the **apply half**. Owner answered the §9.3 build-vs-hold call ("I forget to run
kbg:learn") → BUILD. Governance: [ADR 0002 addendum](docs/adr/0002-addendum-passive-capture.md)
(not a superseding ADR — the advisory-sensor architecture is unchanged).

### Added

- **`hooks/session/learn-capture.sh`** — SessionEnd advisory sensor (computational-FB),
  **default-OFF** (`KBG_LEARN_CAPTURE=1`). Harvests operator corrections/preferences from the
  transcript (role==user only, word-boundary patterns, quote/tag stripped) and **appends** JSONL
  candidate rows to an **out-of-repo** queue. Never mutates the repo, never emits a
  `permissionDecision`, secret-scrubs with whole-row drop, always exits 0.
- **`hooks/session/learn-drain-nudge.sh`** — SessionStart hook that closes the loop: a one-line
  nudge when ≥5 candidates have aged ≥7 days, hash-gated so it never re-nags the same set.
- **`scripts/read-candidates.sh`** — shared reader: merges rows across sessions, computes an
  **ordering-only** confidence, lists open candidates; `--archive` disposes + caps/rotates (keeps
  all unreviewed rows).
- **`skills/learn/CANDIDATE-SCHEMA.md`** — the writer/reader contract (queue path, row shape,
  confidence formula, secret-scrub deny-list).
- **`docs/adr/0002-addendum-passive-capture.md`**, **audit check #47** (CRIT: no
  `permissionDecision`, no confidence-gate), 2 eval fixtures, `test-ch-learn-capture.sh` (12 tests).

### Changed

- **`skills/learn/SKILL.md`** — new **Step 0** drains the candidate queue before mining; the
  "no SessionEnd auto-mining" autonomy-posture block was consciously relaxed (capture is passive +
  opt-in; APPLY stays `AskUserQuestion`-gated here). Counts: 46→48 hook scripts, 61→63
  registrations, 36→38 sensors.

## [0.3.6] — 2026-06-21

Thinking-catalog on-demand discoverability — surface the 9 orphan mental-model frames on the
path that's designed to be opened, after a 3-agent grilling debate + Team-Lead zoom-out ruled
against building a new surface.

### Changed

- **`harness-nav` §6 now lists the 9 orphan thinking-frames** (regret-minimization, kepner-tregoe,
  fermi-estimation, triz, archetypes, effectuation, dual-process, lindy-effect, leverage-points)
  with a one-line "reach for it when…" + the `cat` recipe to their vendored SKILL.md. These are
  the models no kbg skill embeds — previously reachable only by reading all 39 catalog rows. The
  other ~30 stay reachable via their host skills + the v0.3.5 METHODOLOGY scaffold menu.
  Reference-only scaffolds, not an accuracy boost (the catalog's honesty caveat still governs).
- **`reasoning-models.md` "How to use"** now names the canonical "which scaffold when" router (the
  v0.3.5 METHODOLOGY menu) and marks this catalog + its tables as *reference*, not a competing
  situation-router — anti-drift against the three-overlapping-tables smell.

### Not done (recorded)

- **`kbg:think` apply-engine skill — rejected.** A skill whose job is "pick the framework for you"
  is a model-as-router (ADR 0002 — the line is *who picks the lens*, not *who presses go*); its
  description would collide with probe/decide/ideate/critical-eval (the v0.3.5 trigger-collision
  smell); and the upstream eval gives it no accuracy to gain.
- **A new "situation → framework" table — rejected** as redundant: `harness-nav` already routes to
  the catalog on-demand, and a third table in a "do not open unprompted" file doesn't raise the
  consult rate.
- **Consolidating the thinking + decide surfaces — rejected.** They're layered by axis
  (person / scaffold / model-name / discovery), not redundant; merging loses useful distinctions.

## [0.3.5] — 2026-06-21

Decision-doctrine clarity — the thinking/deciding surface was structurally sound,
but the always-resident menu that points into it was incomplete and one trigger
collided. Two surgical fixes; no refactor (an inventory pass + an adversarial
clarity-critic agreed the scaffolds themselves are clean).

### Changed

- **Scaffold "reach for" menu relocated + completed.** The only always-resident
  decision menu lived in the global `~/.claude/CLAUDE.md` as a 4-item line that
  tagged `probe` as "(decision)" while omitting the purpose-built decision skills
  (`decide`/`strategize`). Moved the complete, **reversibility-split** menu into
  `METHODOLOGY.md` (kbg L1, co-located with the agent-routing index, loaded exactly
  when those skills exist); the global line is now generic and points to it (no
  longer dangles in non-kbg projects). Closes the discovery gap for free — the L1
  menu is the discovery path the harness's own data shows works.
- **`probe` no longer collides with `decide` on a Thai trigger.** Both fired on
  `'วิเคราะห์ตัดสินใจ'` ("analyze-decide") with no tiebreak → coin-flip routing
  between read-only analysis and the full Judgment Ladder. Dropped the token from
  `probe` (it keeps `'probe'`/`'ถาม why'`/`'what if'`); `decide` owns the decision verb.

### Not done (recorded)

- **Audit trigger-token collision guard — rejected after verification.** A check for
  surfaces sharing a trigger token can't be made precise without an allowlist of
  intentional pairs: `team-plan`/`team-build` and the `deep-dive`/`researcher`/
  `research-brief` tier legitimately share Thai triggers with dissimilar
  descriptions, so a similarity gate flags them too. An allowlist is the speculative
  config the harness rejects (Rule 2); the one real accidental collision is fixed
  directly above. Other shared triggers flagged to the owner, not auto-changed.

## [0.3.4] — 2026-06-21

Observability + learning — three ECC concept-gaps closed within kbg's invariants
(an adversarial gap-hunt found them; all three are mandated or enabled by kbg's own
doctrine, not imported wholesale).

### Added

- **`kbg:learn` — human-gated session-pattern capture.** Mines the current session
  transcript for durable, reusable learnings (operator corrections, stated
  conventions, repeated workflows, decisions + rationale), filters out what the
  repo/memory already records, and writes only operator-approved ones as `memory/`
  files via an `AskUserQuestion` gate. The propose-only counterpart of
  `recursive-improve` (that closes the loop on harness health; this one on what you
  taught it this session). Operator-initiated only — **no** SessionEnd auto-mining;
  unflagged so the model can reach it on "remember how we did this", with the gate
  (not a user-only lockout) as the safety. **Skill count 39 → 40.**
- **`cost-capture` SessionEnd hook + `kbg:harness-health --cost`.** Sums per-message
  token usage from the transcript (deduped by message id) and journals a
  `cost_capture` event; `--cost` reports per-session totals. Honest TOKEN counts
  only — no dollar estimate (no honest local price signal, same reasoning as the L3
  `--max-cost` deferral). The measurement half of METHODOLOGY Rule 6 + the Böckeler
  2×2's "feedforward needs feedback" — kbg preached token discipline but never
  measured spend (usage-monitor tried and failed on a wrong jq path). Count fields
  are named to dodge the journal's secret-redactor (no "token" substring). **Hook
  scripts 45 → 46; sensors 35 → 36; registrations 60 → 61.** Covered by
  `test-ch-cost-capture.sh`.
- **MCP inventory — `auth-health-check.py --mcp`.** Read-only list of configured MCP
  servers (name, transport, env-var KEY NAMES — never values; HTTP host only). Also
  fixes `_load_mcp_config`'s blindness to `~/.claude.json` (the common home for user
  `mcpServers`), which improves the existing reachability probe too. A regression
  eval guards the security contract (an env value must never leak into output).

## [0.3.3] — 2026-06-21

Fix the stale `sensors.json` `_provenance` hook counts — the root cause of the
README count drift. A `jq` census + harness-audit established the real numbers.

### Fixed

- **`sensors.json` `_provenance` corrected: "42 unique / 57 total" → "45 / 60".**
  The field is hand-curated with no machine-check, so it drifted from `hooks.json`
  as hooks were added — and it had propagated the wrong "42" into the README and
  misled a verification agent into reporting "57". Verified authoritative counts:
  **45 unique hook scripts**, **60 registrations** across 14 lifecycle events,
  **35 tracked as sensors** (PreToolUse gates, `_lib` helpers, and capture scripts
  are intentionally untracked — no staleness contract). Added a `recounted` note.
  Metadata-only — no runtime-behavior change.

## [0.3.2] — 2026-06-21

ECC structure comparison → two clarity renames. A 6-agent workflow drilled
`affaan-m/ECC` live via `gh` and ran an advocate/skeptic/synthesizer debate on
adopting ECC's 12-category layout. Verdict: **reject the restructure** (ECC's
taxonomy is built for a ~270-skill, 9-harness, multi-author repo; kbg already
homes every concern at its single-harness scale, and 6 dirs are loader-fixed),
**adopt 2 file renames** that fix real confusion, reject 3 that were churn
without a proven navigational failure.

### Changed

- **`hooks/advisory/hypothesis-precommit.sh` → `hypothesis-gate.sh`.** The old
  name was a false cognate with the real `git-hooks/pre-commit` lifecycle hook —
  but this one fires on `UserPromptSubmit` for investigation prompts, not on git
  commit. It already self-identified as `[hypothesis-gate]` in its output and
  `hypothesis_gate_fired` in its journal events; the filename and `HOOK_ID` now
  match. Updated `hooks.json`, `sensors.json`, and the manifest descriptions.
- **`skills/_lib/fm.sh` → `frontmatter-helpers.sh`.** `source ../../_lib/fm.sh`
  was opaque at the call site; the full name is self-documenting (`err.sh` stays —
  it maps to a universal shell convention `fm` lacks). Updated the `source` lines
  + `shellcheck source=` directives in `audit.sh`, `inventory.sh`, and
  `inventory-boundary.sh`. Function names (`fm_get`/`fm_has`/…) unchanged.

### Added

- **CLAUDE.md "Where each concern lives" map.** Documents `contexts/` as a
  first-class category (previously undocumented) and records why kbg does not
  restructure into a generic category tree — the documentation-over-restructure
  takeaway from the ECC comparison.

## [0.3.1] — 2026-06-21

Post-L3 cleanup bundle: kill one dead feature, guard one duplication seam, fix
stale script paths. Reviewed by a 3-lens senior panel before ship.

### Removed

- **`usage-monitor` feature deleted (build-to-delete).** Its capture hook never
  worked — it ran `jq '.messages[]'` against a JSONL transcript, so it always
  returned `[]` (the sibling ideate hooks fixed this exact bug in `b449e9d`;
  usage-monitor missed the batch). Opt-in and off by default, it never delivered
  data, so it was never missed. Removed the skill, the `usage-monitor-capture.sh`
  SessionEnd hook, the `sensors.json` entry, the eval dataset + test, and the prose
  references. **Skill count 40 → 39**; hook event count unchanged at 14 (the
  SessionEnd event retains its other hooks).

### Added

- **Audit check #46 — `task-board-lib.sh` sync-seam guard.** Three skills
  (`orchestrate`, `types-first`, `progressive-refine`) ship a byte-identical copy
  of `scripts/task-board-lib.sh` (a skill's `scripts/` must be self-contained in
  the plugin cache — no cross-skill sourcing). They were synced by hand with no
  machine-check, so one could drift silently. #46 compares every copy against the
  first with `cmp` (POSIX, no BSD/GNU hash split) and WARNs on divergence — same
  class as the #37-#40 sync-seam checks. Covered by `test-ch-task-board-lib.sh`.

### Fixed

- **3 stale `$HOME/.claude/scripts/pr/` path references** → `${KBG_PLUGIN_ROOT}/scripts/pr/`
  in `recursive-improve/SKILL.md` (L3 Observe reader) and `review-pr/SKILL.md`
  (journal validator + writer). The v0.2.68 portability sweep missed these; they
  pointed at the pre-plugin-extraction home-dir location.

## [0.3.0] — 2026-06-21

L3 bounded autonomy. A deliberate **telos change**, not a capability argument:
the human gate moves from *per-mutation* to *per-run-approval + per-push*, so a
self-improvement loop can run unattended *within an owner-approved run*. Minor
bump for the milestone. **`KBG_AUTONOMY_L3` is OFF by default → behavior is
identical to L2 today**; the flag is inert until the operator opts in. ADR 0003
supersedes ADR 0002's L2-only architecture (append-only; ADR 0002 stays the
canonical L2 record). L4 (no human gate) stays rejected — changing the autonomy
architecture requires a new superseding ADR, never a flag flip or a loop
self-edit. Surface counts unchanged (29 agents / 40 skills / 22 commands /
14 hook events). Commits `01dea6f`…`8f9eea1`.

### Added

- **ADR 0003 (`docs/adr/0003-l3-bounded-autonomy.md`)** — records the conscious
  override of ADR 0002, the preserved principle (operator judgment is
  load-bearing), the one real relaxation (gate per-batch + per-push, not per
  mutation), the **two-gate model** (Gate 1 = launch approval; Gate 2 = pre-push
  review; no per-cycle gate), and that ADR 0003 is itself reversible. ADR 0002
  gains a top supersession banner (not a silent violation).
- **The cage** — `scripts/l3-cage.txt` (deny-by-default path list the loop may
  never edit: all gates, `audit.sh`, doctrine, `.git/config`, the cage itself) +
  `scripts/l3-loop-guard.py` (the single code-level enforcer: caps + cage check,
  fail-closed, flag captured immutable for the run, return contract
  `{CONTINUE, SKIP, REVERT, STOP}`). Caps are enforced in code, not prose:
  `--max-runs` (default 3, a reviewability bound), `--max-duration`,
  `--fail-streak`, `--dirty-abort`.
- **Gate 2 push gate** (`hooks/gates/l3-push-gate.sh`, flag-scoped) — under an
  active L3 run with unreviewed commits, denies `git push` / `gh pr` /
  `core.hooksPath` tampering; override only via explicit `KBG_L3_REVIEW_DONE=1`.
  `_lib.sh` gains **L3 immunity**: profile-off / disabled-hooks can't disarm the
  safety gates while the flag is set.
- **`recursive-improve --auto` bounded-loop body** — Observe → Propose → Act →
  in-loop gauntlet (computational, never model-as-gate) → keep-if-green /
  `git reset` if-red → journal(run_id) → next. Commits **local, never pushes**.
- **Audit checks #43 / #44 (CRIT)** cage-integrity + push-gate/hooksPath wiring,
  **#45 (CRIT)** reviewer read-only invariant (maker≠checker regression guard),
  and **#43b** cage-completeness against the full anchor set; **#32 hardened** to
  frontmatter-anchored `fm_get` (prose-proof) so a SKILL.md docstring rewrite
  can't silently disarm the "model can't self-start the loop" guard. New tests
  `test-ch-l3.sh` (25 checks) + `test-ch-agent-readonly.sh`.
- **Run-id audit trail** — `run_id` / `l3_cycle` correlation in the governance
  journal (`hooks/JOURNAL-SCHEMA.md`) + `scripts/l3-run-report.sh` read-only
  query view.

### Changed

- **The autonomy invariant relaxed for L3 only** — the per-mutation human gate
  becomes per-batch + per-push. `recursive-improve` keeps
  `disable-model-invocation: true` (guarded by audit #32), so the model still
  cannot *self-start* the loop; the human launches `--auto` with
  `KBG_AUTONOMY_L3=1`. Still out of scope by design: a self-*launching* loop
  (cron / `/loop` / `CronCreate` / Evo meta-loop), a model-as-gate, and L4.
  The 5 verbatim invariant copies (CONTEXT / CLAUDE.md / recursive-improve /
  decay-cadence / README) updated together to the L2-default / L3-when-flagged
  distinction.

### Deferred

- **`--max-cost`** to Slice 2 (the learning engine) — a plain script has no
  honest local token-cost signal, and faking one violates the no-fake-metrics
  rule. Slice-1 hard caps are `--max-runs` + `--max-duration`.

## [0.2.118] — 2026-06-20

### Added

- **`/context` working-frame loader + `contexts/` dir.** Loads a dev / review /
  research working-frame on demand so a session can adopt a role's lens without
  hand-assembling the context each time.

## [0.2.117] — 2026-06-20

### Added

- **Lifecycle agent-lens in `/kbg-help`.** The 29-agent fleet is now presented
  organized by engineering stage, so the right specialist is discoverable from
  where you are in the workflow rather than from an alphabetical list.

## [0.2.116] — 2026-06-20

### Added

- **Optional `## Why` slot on the F9 dispatch template** (BMAD article-mine,
  MINE 1). BMAD's "story = context package" framing surfaced one missing element:
  a place to state *why* a dispatched task matters. The other 4 context-package
  elements were already in F9. Optional, not mandated.

## [0.2.115] — 2026-06-20

### Changed

- **`code-reviewer` routing deduped** into a single Cross-role boundaries section
  (agent spec 216 → 200 lines). Same routing, stated once.

## [0.2.114] — 2026-06-20

### Changed

- **`debug-debate` spawn fences collapsed** — 4 near-identical agent-spawn blocks
  folded into one template + a table (command 338 → 255 lines).

## [0.2.113] — 2026-06-20

### Changed

- **`ideate` frames table extracted** to `references/frames.md`, bringing
  `SKILL.md` 512 → 496 lines (back under the official 500-line skill cap).

## [0.2.112] — 2026-06-20

### Fixed

- **XML-tag-shaped placeholders stripped** from 3 skill descriptions (surfaced by
  a skill-creator audit) — they could be misread as literal markup by the router.

## [0.2.111] — 2026-06-20

### Changed

- **Best-practices sweep of the skill fleet** (48-agent review of all 40 skills;
  narrow yield — most were already optimal). The two structural outliers fixed:
  `progressive-refine/SKILL.md` 754 → 174 lines (progressive-disclosure split) and
  `task-sizing` logic moved from inline Python into `scripts/`. Plus 10 correctness
  one-liners across descriptions, including a `ship-change` description↔eval
  mismatch.

## [0.2.110] — 2026-06-20

### Fixed

- **METHODOLOGY §13 teardown rule was imprecise** — it said "stop the subagent"
  without noting that `TaskStop` only stops a *still-running* task. A foreground
  `Agent` spawn returns synchronously and has already reaped when you read it, so
  `TaskStop` on its `agentId` errors `No task found` (harmless, but recurring
  noise). Added a "Stop only what is still running" clause: teardown applies to
  `run_in_background` / teammate-mode agents that persist; check `TaskList` first
  and never `TaskStop` an agent that already returned. No surface count change.

## [0.2.109] — 2026-06-20

Refactored `kbg:tech-humanize` to official Claude Code skill best practices, and
fixed the "output still reads AI" effectiveness gap found by a maker≠checker test.

### Changed

- **`kbg:tech-humanize` progressive-disclosure refactor.** SKILL.md slimmed
  **596 → 119 lines** to clear the official ≤500-line cap
  (code.claude.com/docs/en/skills line 313: "Keep `SKILL.md` under 500 lines.
  Move detailed reference material to separate files"). The 30 universal patterns
  (full problem + worked before/after) and the detection guidance moved to a new
  bundled `patterns-universal.md`; SKILL.md keeps a compact 30-row scan cue-sheet
  and a "load when" pointer to the catalog. Net always-loaded context for the skill
  drops ~40KB → ~14KB; the full catalog loads only when a fix needs the worked
  example. `patterns-thai.md` / `examples.md` / `references.md` unchanged.

### Added

- **The Grit Gate (`kbg:tech-humanize`).** A mandatory gate, placed before the
  pattern scan: deletion alone lands text in the "safe middle," which a skeptical
  reader still scores ~30/100 AI. Every rewrite must also (1) surface concrete
  grit (ticket/PR refs, file names, the real cause, real numbers) and (2) commit
  to a point of view where the genre allows. Hard boundary: never fabricate grit,
  and never polish a hollow source into a confidently-empty paragraph — say so or
  ask for the specifics instead. Closes the gap surfaced by a maker≠checker test
  (a fresh humanizer + a fresh critic) where cleaned output still read machine-written.

Fine-tuned the `kbg:decide` and `kbg:strategize` skills and their reference docs for
Slingshot-label fidelity, official-docs surface hygiene, and practical coding use.

### Changed

- **`kbg:decide` and `docs/reference/judgment-ladder.md`.**
  - Slingshot Thai bias labels: Sunk Cost Bias = `อคติจากสิ่งที่ลงทุนไปแล้ว`;
    Confirmation Bias corrected to `อคติจากการมีธงในใจ` (the idiomatic "flag in
    mind" = a predetermined answer — the prior `รังในใจ` was a mis-transcription).
  - Replaced references to non-loadable `thinking-*` surfaces with explicit notes
    that Cynefin, OODA, pre-mortem, debiasing, and bounded-rationality are vendored
    thinking references under `docs/reference/thinking-skills/`, not kbg surfaces —
    and corrected the cited paths to the real `thinking-<topic>/` dir names.
  - Added a coding-application section mapping the Judgment Ladder to library
    choices, API/data-model decisions, deploy strategies, refactor scopes, and
    hotfix handling.

- **`kbg:strategize` and `docs/reference/strategic-judgment.md`.**
  - Replaced `thinking-ooda` / `thinking-*` references with kbg surfaces and vendored
    reference notes, matching the loadable-surface contract — including the
    frontmatter `description` and the "kbg surface" table, which had pointed the
    model at the non-loadable `thinking-ooda` (now `kbg:incident` / `kbg:hotfix`).
  - Added a coding-application section with architecture/platform/team-topology
    examples (monolith→services, database choice, build vs. buy, language/runtime,
    team topology) and a clear flow: `strategize` → `decide` → `adr`.

- **Thai-text correctness sweep (plugin-wide).** `agents/technical-writer.md`
  trigger `รันเวิก` → `รันบุ๊ก` (the runbook transliteration was garbled);
  `skills/tech-humanize/SKILL.md` `แคว้นกatalunya` → `แคว้น Catalunya` (Thai/Latin
  mojibake, in both the before and after example).

- **Plugin manifests and README.** Version badge and newest-additions callout
  updated; no new component counts.

## [0.2.108] — 2026-06-20

### Fixed

- **`kbg:decide` / `kbg:strategize` reference correctness** — corrected
  vendored-path and non-loadable-surface references, plus a plugin-wide Thai
  typo sweep.

## [0.2.107] — 2026-06-19

Added a dedicated strategic-judgment skill and reference doc for irreversible
commitments under ambiguity, keeping `kbg:decide` focused on analyzable choices.

### Added

- **`kbg:strategize` skill.** Applies a six-step strategic-judgment loop: diagnose
  the situation (Rumelt), choose a guiding policy, design coherent actions, map
  irreversibilities and real options, red-team the strategy, and commit to a
  strategy loop. Includes Thai trigger phrasing for "วางกลยุทธ์" / "กลยุทธ์" /
  "strategic judgment" / "ตัดสินใจเชิงกลยุทธ์".
- **`docs/reference/strategic-judgment.md`.** Standalone reference covering
  Rumelt's kernel, Lafley/Martin's five strategic choices, integrative thinking,
  real options / adaptive commitment, strategic red-team, and superforecasting
  discipline, plus a comparison table for when to use `kbg:strategize` vs.
  `kbg:decide`.
- **`docs/reference/reasoning-models.md` scaffold pointer.** New row in the
  kbg-native reasoning scaffolds table for `strategic-judgment` → `kbg:strategize`,
  and updated the `judgment-ladder` row to mention follow-through.

### Changed

- **README and plugin manifest counts.** Skill count refreshed 39 → 40.
- **Manifest description.** Notes the new `strategize` skill in the skill summary.

## [0.2.106] — 2026-06-19

Hardened the `kbg:decide` Judgment Ladder skill and reference doc with insights
from the Slingshot Group training material: explicit follow-through and a focused
four-bias guard.

### Changed

- **`kbg:decide` Rung 5 now reads “Decide, commit, and follow through.”** Adds
  progress measurement, tracking, and check-in questions to prevent “soft
  commitment” and decision decay.
- **`kbg:decide` four-bias guard.** Cross-checks the Slingshot Decision Bias set
  at their natural rungs: Framing/Anchoring at Frame, Confirmation at Test
  Assumptions, Sunk Cost at Decide & Commit. Includes Thai phrasing from the
  source slides.
- **`docs/reference/judgment-ladder.md`.** Updated rung 5, decision-record
  template, and added a dedicated “Slingshot four-bias guard” section with Thai
  labels and English counters.
- **Manifest description.** Notes the follow-through and four-bias guard in
  the `decide` skill summary.

## [0.2.105] — 2026-06-19

Added a structured decision-making skill and reference doc to help the harness and
its users walk consequential choices before committing.

### Added

- **`kbg:decide` skill.** Applies the Judgment Ladder — a compressed Decision
  Quality process — across five rungs: recognize the decision, frame the problem,
  gather and test assumptions, estimate risk and uncertainties, decide and commit.
  Includes a proportionality rule so low-stakes reversible choices don't get
  over-climbed, and explicit redirection to `kbg:adr`, `kbg:probe`, `thinking-cynefin`,
  and `thinking-ooda` when those lenses fit better.
- **`docs/reference/judgment-ladder.md`.** Standalone reference with rung-by-rung
  checkpoints, failure modes, a decision record template, and connections to the
  Decision Quality chain and kbg thinking skills.
- **`docs/reference/reasoning-models.md` scaffold pointer.** New "kbg-native
  reasoning scaffolds" section pointing to `kbg:decide` and the judgment-ladder
  reference.

### Changed

- **README and plugin manifest counts.** Skill count refreshed 38 → 39.

## [0.2.104] — 2026-06-19

Two guards against recurring friction surfaced by a `/insights` usage review: wrong-worktree review application and hardcoded home paths in committed scripts.

### Added

- **`git-hooks/pre-commit` hardcoded-path guard.** Staged `*.sh`/`*.py` files are rejected if they contain a literal `/Users/<name>/` home path (use `$HOME`/`~`). Config (`*.json`, plists, rc files) and docs stay exempt — absolute paths are legitimate there. 0 existing script violations, so it adds clean. Mirrored in the dotfiles repo's pre-commit.

### Fixed

- **`/address-review` wrong-branch application.** Phase 1 now asserts `git rev-parse --abbrev-ref HEAD == headRefName` and STOPs on mismatch, preventing review fixes from landing on the wrong worktree (the `fix/TP-582`-while-addressing-`feature/TP-650` failure mode).

## [0.2.103] — 2026-06-19

Official-docs conformance pass on the hook layer (5-agent read-only audit of the 47 hook files + 52 scripts). No new surfaces; manifest hook count unchanged at 45.

### Fixed

- **`hooks/hooks.json` MCP matcher.** `mcp__*` → `mcp__.*`. Per the [official hook docs](https://code.claude.com/docs/en/hooks), a matcher containing a special char is an unanchored JS regex and the `.*` is required to match `mcp__<server>__<tool>`; the old `mcp__*` matched only by accident of unanchored search and would break silently if matchers were ever anchored.
- **`set -e` → `set -uo pipefail` in `hooks/gates/agent-spawn-gate.sh` and `hooks/lifecycle/task-lifecycle.sh`.** These were the last two hooks violating the documented hook convention (CLAUDE.md § error-handling). In `task-lifecycle.sh`, `set -e` was a latent footgun: a bare-command failure (log append, board write) could abort before the F7 `exit 2` enforcement and skip `kbg_lock_release`, leaking a lock.
- **`hooks/session/doctrine-bootstrap.sh` trailing `exit 0`.** Explicit `exit 0` after the final `additionalContext` printf so a transient printf failure can't discard doctrine injection.

### Docs

- **`README.md` refresh.** Version badge → 0.2.103; corrected hook count 44 → 45 (stale since `agent-spawn-gate` landed at v0.2.100); newest-additions callout updated for v0.2.101–103.

---

## [0.2.102] — 2026-06-19

Dropped a vestigial `skills:` scaffold field from the three read-only reviewer agents. No new surfaces; manifest counts unchanged.

### Fixed

- **Removed `skills:` frontmatter from `code-reviewer`, `security-reviewer`, and `type-design-analyzer`.** The field was uniform scaffold residue (`code-reviewer`/`type-design-analyzer` pointed at their own parent orchestrator `review-pr`). Per official CC docs, `skills:` preloads skill content into the subagent at startup — it does NOT grant tools — so read-only enforcement was never affected (the `tools:` allowlist is the wall); removing it also clears a cosmetic `Write, Edit` registry display that correlated with the preload link.

---

## [0.2.101] — 2026-06-19

Trimmed an over-broad tool grant on the `code-reviewer` agent and named the self-grading bias in doctrine. No new surfaces; manifest counts unchanged.

### Fixed

- **`agents/code-reviewer.md` tool allowlist.** `Glob, Grep, Read, WebFetch, WebSearch, Bash` → `Glob, Grep, Read, Bash` — dropped the unused web tools to match the 4-tool read-only set already specified in `docs/agent-tool-patterns.md`.

### Changed

- **`CLAUDE.md` § LLM-judge-circularity.** Added the human-facing framing of self-confirming verdicts: a session asked to grade its own work is invested and leans *yes*, while a fresh-context reviewer has nothing to defend — the reason maker≠checker runs in a separate context, not as a politely-worded self-check.

---

## [0.2.100] — 2026-06-19

PreToolUse enforcement gate to stop ad-hoc one-shot Agent spawns from blocking session exit. One new hook + tests + doctrine/doc/memory updates.

### Added

- **`hooks/gates/agent-spawn-gate.sh`.** PreToolUse gate on the `Agent` tool. Allows team workflows (`/team-build`, `/team-plan`, orchestrate with `plan_slug:` / `task_id:`) to pass through. Asks for confirmation on bounded read-only patterns ("blueprint", "audit", "research", "map", "read and summarize", "check this", etc.), backgrounded agents, and generic ad-hoc spawns. Bypass: `export CLAUDE_DISABLED_HOOKS=agent-spawn-gate`.
- **`tests/hooks/runners/test-ch-gates.sh` coverage.** Ten new assertions for the gate: allow-list for team workflows, ask-list for one-shot patterns, background-agent default, and generic-spawn default.

### Changed

- **`METHODOLOGY.md` §13 hard rule.** Added: "If you cannot deterministically stop the subagent in the same turn, do not spawn it. Use inline Read, Bash, or python3 instead."
- **`docs/agent-teams-setup-notes.md` teardown note.** Added a "Hard rule: do not spawn without a stop plan" subsection explaining the gate and the **Exit anyway** escape hatch.

---

## [0.2.99] — 2026-06-19

Regression eval fixtures to lock the v0.2.97 surface-description quality contract. No new plugin surfaces; manifest description counts unchanged.

### Added

- **`eval/scripts/check-description-quality.py`.** Deterministic grader that scans all 88 `agents/*.md`, `commands/*.md`, and `skills/*/SKILL.md` files, parses YAML frontmatter, and verifies: description length ≤ 1,024 characters; at least one Thai trigger token; a positive trigger clause (`Use when`, `Trigger when`, etc.); a negative scope clause (`Don't use for`, etc.); and a non-empty `disable-model-invocation-reason` whenever `disable-model-invocation: true`.
- **`eval/datasets/description-quality.json`.** Three assertion evals wired into `run-eval.py` as `skill: description-quality`, gating the grader script's per-category `RESULT:` lines.
- **`eval/run-eval.py` description-quality handler.** Runs the grader script, matches each success criterion against the explicit `RESULT: <criterion>: PASS` output, and treats exit code 0 as a clean run.

---

## [0.2.98] — 2026-06-19

Staff-eng doctrine patch: close the one-shot subagent teardown gap. No new surfaces; only METHODOLOGY.md + docs/agent-teams-setup-notes.md + memory.

### Added

- **`METHODOLOGY.md` §13 teardown rule.** Any ad-hoc `Agent` spawn for a bounded read-only pass (blueprint, audit, research map) must be stopped by the parent session after consuming the result. `/team-build` Step 8 already covers multi-agent builds; this rule covers one-off subagent dispatches.
- **`docs/agent-teams-setup-notes.md` teardown note.** Explains that persistent teammates do not self-terminate, and that idle one-shot agents block session exit with "Background work is running".

---

## [0.2.97] — 2026-06-19

Staff-eng + official-docs-verified fine-tune across all agent, command, and skill surfaces. Frontmatter `description:` changes only; no body edits, no agent tool/model/effort/color changes, no `disable-model-invocation` changes.

### Changed

- **Thai trigger tokens added to all 29 agents.** Every agent description now includes single-quoted Thai tokens (e.g., `ออกแบบระบบ`, `รีวิวโค้ด`, `ตรวจความปลอดภัย`, `ประสบการณ์ผู้ใช้`) alongside English trigger phrases, so Thai requests route to kbg agents instead of bypassing them.
- **Thai trigger tokens added to all 21 commands.** Every command description now includes Thai tokens (e.g., `สร้างทีม`, `แก้บั๊ก`, `ปล่อยเวอร์ชัน`, `ตรวจก่อนส่ง`) alongside English triggers.
- **Thai trigger tokens added to the remaining skills.** `kbg:ideate`, `kbg:progressive-refine`, and `kbg:recursive-improve` descriptions now carry Thai tokens.
- **Agent positive trigger phrasing standardized.** Descriptions use `Use when … / Use before … / Use after …` clauses so they satisfy the same positive-side trigger-pattern contract as skills.

### Fixed

- **`recursive-improve` placeholder description** replaced with a real routed description that explains the bounded human-gated harness-improvement loop; `disable-model-invocation: true` and its recorded ADR-0002 reason are preserved.
- **`kbg:harness-audit` description** now carries an explicit `Use when …` positive trigger clause instead of only `Also fires on …`.
- **Regenerated `BOUNDARY.md`** to match the current fleet state.

## [0.2.96] — 2026-06-19

Staff-eng + official-docs-verified fine-tune of the remaining skill fleet. Frontmatter-only changes; no body edits, no agent/tool changes, no `disable-model-invocation` changes. No auto-prepend; no new machinery.

### Changed

- **Rewrote 9 placeholder skill descriptions.** `kbg:adr`, `kbg:assert-presence`, `kbg:decommission`, `kbg:harness-audit`, `kbg:inventory`, `kbg:memory-lint`, `kbg:memory-trim`, `kbg:probe`, and `kbg:semantic-code` now carry real, routed descriptions with positive-side trigger clauses and negation clauses instead of single-word placeholders.
- **Thai triggers added to 20 more skills.** `kbg:clarify-first`, `kbg:incident`, `kbg:hotfix`, `kbg:triage`, `kbg:backend-dev`, `kbg:accept-task`, `kbg:article-mine`, `kbg:critical-eval`, `kbg:migrate`, `kbg:perf`, `kbg:research-brief`, `kbg:review-pr`, `kbg:security-auditor`, `kbg:ship-change`, `kbg:task-sizing`, `kbg:types-first`, plus the read-only reporters `kbg:harness-coverage`, `kbg:harness-health`, `kbg:harness-nav`, and `kbg:usage-monitor`. All descriptions remain under 1,024 characters.
- **`kbg:backend-dev` description trimmed** to match the actual TDD body workflow (no invented agents or workflows).

### Fixed

- **Regenerated `BOUNDARY.md`** so the inventory snapshot matches the current fleet.

## [0.2.95] — 2026-06-19

Staff-eng + official-docs-verified fine-tune of team/orchestration surfaces. Thai triggers added; model-selection contradiction resolved; `disable-model-invocation` criterion applied per surface; no auto-prepend; no new machinery.

### Changed

- **All team/orchestration surfaces now carry Thai trigger phrases.** `/team-plan`, `/team-build`, `/team-cleanup`, `/validate-and-fix`, `/pre-flight-plan-linter`, `/wave-status`, `/debug-debate`, `kbg:orchestrate`, and `kbg:7-agent-pattern` descriptions now include Thai tokens (`สร้างทีม`, `รันแผนทีม`, `ล้างทีม`, `ตรวจงาน`, `ตรวจแผน`, `wave ไหนแล้ว`, `ถกเถียง`, `จัดสรรงาน`, `ทีม 7 คน`, …) alongside English, so Thai team/orchestrate requests route to the kbg surfaces instead of bypassing them.
- **Single source of truth for teammate model selection.** `agents/{backend-engineer,code-architect,frontend-engineer,security-reviewer}.md` now declare `model: sonnet`, matching the F8 cost-split doctrine and the command spawn prompts. The redundant `model: "sonnet"` lines were removed from `/team-build`, `/validate-and-fix`, and `/debug-debate` body spawn instructions.
- **`disable-model-invocation` applied per surface, not as a blanket.** Removed the flag from `/team-plan`, `/team-build`, `/validate-and-fix`, and `/pre-flight-plan-linter` — they are confirmation-gated in-flow and the model should reach them on explicit Thai/English requests. Kept the flag on `/team-cleanup` (destructive teardown, matches the recorded criterion). `recursive-improve` untouched (ADR 0002).
- **`/wave-status` description fixed.** It now notes the temporary `.scratch/` helper write instead of claiming strict read-only.

### Fixed

- **`scripts/orchestrate-dispatch.py` docstring** referenced non-existent `_orchestrate_loader.py` / `_orchestrate_planner.py` / `_orchestrate_executor.py`; now points to the real `orchestrate/{loader,planner,executor}` modules.
- **`scripts/orchestrate/planner.py` dead code removed.** The `wave_overflow` branch in `build_plan()` was unreachable because `resolve_waves()` already clamps top-level waves to `max_per_wave`.

## [0.2.94] — 2026-06-19

Staff-eng + official-docs-verified fine-tune of the three Atlassian skills (`acli`, `create-jira-bug`, `create-jira-story`). MCP tool references checked against the live Atlassian MCP schema; AC default reconciled with the canonical wording authority. No auto-prepend; no new machinery.

### Fixed

- **MCP fallback examples were under-specified.** `editJiraIssue` examples in `skills/acli/SKILL.md` + `REFERENCE.md` showed only `fields:{…}`, omitting the schema-required `cloudId` + `issueIdOrKey`; `lookupJiraAccountId` was referenced without its required `cloudId` + `searchString`. All now show the required args (verified against the loaded MCP schemas). The create-jira tables also connect the lookup step to the `assignee_account_id` field it feeds.
- **`versions` vs `fixVersions` footgun.** Added a one-line clarifier in `create-jira-bug` that the MCP `versions` field is Affects Version/s (intended) — NOT `fixVersions` (Fix Version/s) — so the two correct-but-distinct Jira fields aren't "harmonized" into a bug later. (No field change — the existing value was correct.)
- **`skills/acli/ISSUES.md`** Issue 1 (md2adf nested-list flattening) was mislabeled "Medium bug" while the script docstring + eval treat the flattening as by-design; reclassified to "By design (documented limitation)" with the H3-subheading workaround. Stale reporter `BIG-TATHEP` → `wasikarn`.

### Changed

- **AC default is now a plain checklist** in both create-jira templates (Given/When/Then kept as the escape hatch for genuinely complex behavior). The templates previously hardcoded GWT, contradicting `skills/acli/examples/README.md` — the AC-wording authority both skills cite, which states the checklist is the default. Descriptions updated to match. (Owner-confirmed direction.)

 — no auto-prepend, verified against official Claude Code docs (skill bodies load only on invocation; `docs/` is not auto-discovered; the catalog stays a Bash-recipe reference).

### Changed

- Standardized the "Named models" footers in `skills/{perf,orchestrate,adr}/SKILL.md` and `commands/fix-bug.md` to carry the honesty-caveat nod ("Catalog + honesty caveat: …") — all 6 footers now point at the catalog *and* its caveat (was 2/6). `probe`/`critical-eval` were already canonical.
- Added honest "Named model" footers to `skills/decommission/SKILL.md` + `skills/memory-trim/SKILL.md` (*via-negativa*) and `skills/incident/SKILL.md` (*ooda*) — skills that already embody the frame but never named it. Flipped those rows in `docs/reference/reasoning-models.md` from "considered" to "applied" to match the catalog's own status definition (the model name now appears in-surface).

### Deliberately not done

- **No footer repositioning.** The whole skill body loads on invocation (official docs), so moving a footer up buys zero visibility — only churn. Surfacing was strengthened via caveat-consistency + honest coverage instead.
- **Skipped** hotfix (OODA framing lives in its `reference.md`, not SKILL.md), triage (cynefin fit is hedged by the catalog itself), clarify-first (socratic already named inline), and ideate (inversion already named inline as 1 of 15 frames) — to avoid the "name a model on every skill" anti-pattern.

## [0.2.93] — 2026-06-19

### Changed

- **Strengthened passive surfacing of the vendored thinking-skills** in skill
  docs — discoverable on demand without auto-loading them into context.

## [0.2.92] — 2026-06-19

Atlassian skills get Thai trigger phrases so Thai requests route to the Thai PO/QA templates.

### Changed

- `skills/create-jira-bug/SKILL.md`, `skills/create-jira-story/SKILL.md`, and `skills/acli/SKILL.md` descriptions now carry Thai trigger phrases (`สร้างบั๊ก`, `แจ้งบั๊ก`, `เปิดบั๊ก`, `สร้าง story`, `เปิด story`, `ย้ายสถานะหลายตัว`, …) alongside the English ones, so a Thai request matches the Thai-template skill instead of an English-triggered `atlassian:*` plugin skill or a raw MCP `createJiraIssue` call. Skill bodies unchanged (already mature). Regenerated BOUNDARY.md.

## [0.2.91] — 2026-06-19

Removed `disable-model-invocation` from every skill except `recursive-improve`, so the model can route to the Jira-creation templates instead of bypassing them.

### Changed

- Dropped `disable-model-invocation: true` from `adr`, `article-mine`, `assert-presence`, `create-jira-bug`, `create-jira-story`, `decommission`, `migrate`, and `ship-change`. The flag also drops a skill's `description` from model context, so the create-jira skills were invisible to the model — it bypassed the Thai PO/QA templates and called raw MCP `createJiraIssue` directly. Single-ticket creation now relies on its in-flow preview-and-confirm step as the safeguard.
- `recursive-improve` keeps the flag (autonomy invariant, audit #32 / ADR 0002); `ideate` stays `disable-model-invocation: false` (audit-required).
- Updated now-stale prose in the affected skills and the `acli` cross-reference; regenerated BOUNDARY.md (8 skills `manual` → `auto`).

## [0.2.90] — 2026-06-18

Fifth sweep: use official `${CLAUDE_PLUGIN_ROOT}` inside hook contexts, drop unofficial skill/command frontmatter fields, and regenerate BOUNDARY.md.

### Fixed

- `hooks/maintenance/mcp-session-watchdog.sh:27`, `hooks/maintenance/notify-sensor-staleness.sh:172`, and `hooks/session/ideate-memory-capture.sh:10` now reference `${CLAUDE_PLUGIN_ROOT}` instead of `${KBG_PLUGIN_ROOT}` in user-facing hook output. `${KBG_PLUGIN_ROOT}` is exported by `command-root-anchor.sh` into `CLAUDE_ENV_FILE` for the Bash tool; `${CLAUDE_PLUGIN_ROOT}` is the official variable available in hook environment.
- `skills/assert-presence/SKILL.md` standalone example now uses `${CLAUDE_SKILL_DIR}` (the official intra-skill variable) and drops the misleading "requires KBG_PLUGIN_ROOT" note.

### Changed

- Removed unofficial frontmatter fields that passed validation but are not in the vendor schema: `user-invocable: false` from `skills/assert-presence/SKILL.md` and `skills/decommission/SKILL.md`; `context: fork` + `agent: backend-engineer` from `skills/backend-dev/SKILL.md`; `context: fork` + `agent: researcher` from `skills/research-brief/SKILL.md`; `license: MIT` from `skills/ideate/SKILL.md`; `version: 3.0.0` / `license: MIT` / `compatibility: claude-code opencode` / `allowed-tools:` from `skills/tech-humanize/SKILL.md`.
- Regenerated `BOUNDARY.md` from current fleet.

## [0.2.89] — 2026-06-18

Fourth cross-component path-sweep: correct stale hook subdir references, outdated script examples, and CHANGELOG paths after the flat-layout cutover.

### Fixed

- `skills/semantic-code/SKILL.md` and `skills/semantic-code/reference.md` now point to `hooks/gates/secret-read-guard.sh::function::is_secret_path` (was `claude/hooks/secret-read-guard.sh...`, then `hooks/secret-read-guard.sh...`).
- `docs/harness-decay-cadence.md`, `docs/onboarding.md`, and `docs/adr/0002-addendum-deferred-items.md` now reference gate hooks under `hooks/gates/` and the advisory logger under `hooks/advisory/` instead of the old flat `hooks/` paths.
- `docs/agents/verification-trail.md` now references `hooks/session/verification-gate.sh`.
- `scripts/orchestrate-dispatch.py` and `scripts/evals/run-acceptance.py` docstring usage examples use `python3` instead of `python`.
- `CHANGELOG.md` historical references updated: `hooks/tests/test-critical-hooks.sh` → `tests/hooks/runners/test-critical-hooks.sh`, `scripts/verification-tier-audit.py` → `scripts/governance/verification-tier-audit.py`, `scripts/review-pr-journal-pre-emit-validator.py` → `scripts/pr/review-pr-journal-pre-emit-validator.py`, `scripts/governance-summary.py` → `scripts/governance/governance-summary.py`.

## [0.2.88] — 2026-06-18

### Fixed

- **Third foreign-CWD portability sweep** — stale cross-component refs,
  foreign-CWD doc examples, memory-dependent evals, and the verification-tier
  path corrected.

## [0.2.87] — 2026-06-18

### Fixed

- **Foreign-CWD sweep continued** — added the missing `merge-review-reports.py`
  and corrected manifest counts.

## [0.2.86] — 2026-06-18

### Fixed

- **Foreign-CWD recipe portability completed** — quoting normalized; README
  newest-additions refreshed.

## [0.2.85] — 2026-06-18

### Changed

- **Internal doc recipes converted to `${KBG_PLUGIN_ROOT}`** for foreign-CWD
  portability; fixed stale review-pr hook paths.

## [0.2.84] — 2026-06-18

### Changed

- **Reasoning-models reference hardened** for discoverability + foreign-CWD
  portability (reference / audit / eval / help surfaces).

## [0.2.83] — 2026-06-18

### Changed

- **Output styles renamed** `SENIOR-ENGINEER` / `STAFF-ENGINEER` →
  `senior-eng` / `staff-eng`.

## [0.2.82] — 2026-06-18

### Changed

- **Cache-invalidation bump** (no functional change) — force-refresh a stale
  plugin cache.

## [0.2.81] — 2026-06-18

Harden the reasoning-models reference path with machine checks and L3 discovery.

### Added

- **`skills/harness-nav/scripts/nav.py` now indexes `docs/reference/`**. Queries like `"mental models"` or `"reasoning"` surface `docs/reference/reasoning-models.md` and `docs/reference/thinking-skills/README.md` as `reference` kind matches.
- **`skills/harness-audit/scripts/audit.sh` check #42** detects drift between the 39-model table in `docs/reference/reasoning-models.md` and the actual count of vendored `thinking-*/SKILL.md` files.
- **`eval/regressions/reasoning-models-portability.json`** runs the access-path recipe from a foreign CWD (`KBG_PLUGIN_ROOT=.`), asserts 39 vendored models, reads a sample model, and confirms `nav.py` returns a `reference` hit for `"mental models"`.
- **`eval/run-eval.py` gains a `script` skill strategy** for deterministic bash-recipe regression fixtures.

### Changed

- **`skills/harness-nav/SKILL.md`** section 6 now notes that `nav.py "mental models"` also surfaces the reference library.

## [0.2.80] — 2026-06-18

Polish the vendored cc-thinking-skills reference library so external installers can discover and read it without hitting path/variable traps, plus output-style register improvements.

### Changed

- **Default live-response register is now SENIOR-DEV; STAFF-ENGINEER is opt-in for cross-boundary decisions.** See `output-styles/senior-dev.md` and `output-styles/staff-engineer.md` for the escalation rules.

### Fixed (reference docs)

- **`docs/reference/reasoning-models.md`** now warns explicitly that `${KBG_PLUGIN_ROOT}` expands only in shell context — never paste it into the `Read` tool.
- **`docs/reference/reasoning-models.md`** recipes now guard against an unset `KBG_PLUGIN_ROOT` and note that the catalog row name (e.g. `systems-thinking`) may differ from the upstream directory name (e.g. `thinking-systems`).
- **`docs/reference/reasoning-models.md`** and **`docs/reference/thinking-skills/README.md`** no longer use relative markdown links that break from a foreign project CWD.
- **`skills/harness-nav/SKILL.md`** reasoning-models recipe section repeats the Read-tool warning and the KBG_PLUGIN_ROOT guard.
- **`commands/kbg-help.md`** now lists the reasoning-models reference library in the discovery table and updates the L1 context tier to include the doctrine pointer.
- **`README.md`** adds `docs/reference/reasoning-models.md` to the Documentation section.
- **`hooks/session/command-root-anchor.sh`** now quotes the exported path so spaces/special characters do not break tokenization.
- **`hooks/session/doctrine-bootstrap.sh`** pointer explicitly tells the model to use Bash (not `Read`) to access the catalog, since the path contains a shell-only variable.
- **`BOUNDARY.md`** regenerated to match the latest XREF content.

## [0.2.79] — 2026-06-18

### Added

- **Unified 39-model reasoning index**, reachable from any CWD.

## [0.2.78] — 2026-06-18

### Changed

- **`staff-eng` register guards added** from the output-style drill-down.

## [0.2.77] — 2026-06-18

### Added

- **`staff-eng` output style added and made the default** live-response register.

## [0.2.76] — 2026-06-18

Fix an existing `audit.sh` repo-root auto-detection bug that only surfaced when the script was invoked from a foreign project CWD without an explicit repo-root argument.

### Fixed

- **`skills/harness-audit/scripts/audit.sh`** was resolving its own directory 4 levels up (`.../.../.../..`) instead of 3, landing one directory above the kbg-harness root. It worked only because callers historically passed an explicit repo root. Now defaults correctly to the plugin root.
- **`commands/kbg-help.md`** removed the trailing `.` from the self-audit shortcut so it does not pass the foreign CWD as the repo root.

### Verified

- End-to-end smoke tests from `/tmp/kbg-foreign-test-...` pass for `/wave-status`, `/pre-ship-verify`, `/ship-task`, `/pre-flight-plan-linter`, `/ideate-search`, `/team-cleanup`, `/validate-and-fix`, `/dismiss-stale`, `/kbg-help` validation shortcuts, and same-skill surfaces (`harness-nav`, `harness-coverage`, `harness-health`, `recursive-improve`, `inventory`, `memory-lint`, `usage-monitor`).

## [0.2.75] — 2026-06-18

Default per-skill audit wrappers to the plugin root when called without arguments, and remove the trailing `.` repo-root convention from skill prose.

### Fixed

- **`skills/{harness-health,harness-nav,recursive-improve}/scripts/audit.sh`** now default to the plugin root if called with no arguments, instead of passing through `.` and resolving against the operator's CWD.
- **`skills/harness-health/SKILL.md`** and **`skills/harness-nav/SKILL.md`** no longer tell the operator to pass `.` to the audit wrapper.

## [0.2.74] — 2026-06-18

Full same-skill portability sweep: every in-skill executable reference now resolves from `${CLAUDE_SKILL_DIR}`, and cross-skill / top-level helpers route through per-skill wrappers.

### Fixed

- **In-skill script references no longer assume repo-root CWD.** `skills/{harness-audit,harness-coverage,harness-health,harness-nav,inventory,memory-lint,memory-trim,recursive-improve,usage-monitor}` and `skills/inventory/reference.md` previously told the operator to run `skills/<name>/scripts/...` directly. All same-skill invocations now use `${CLAUDE_SKILL_DIR}/scripts/<script>`.
- **Cross-skill / top-level helpers in skill bodies now use per-skill wrappers.** New wrappers: `skills/harness-coverage/scripts/harness-coverage.sh` → `scripts/evals/harness-coverage.py`; `skills/harness-health/scripts/audit.sh` and `skills/harness-nav/scripts/audit.sh` → `skills/harness-audit/scripts/audit.sh`; `skills/memory-trim/scripts/memory-lint.sh` → `skills/memory-lint/scripts/memory-lint.py`; `skills/recursive-improve/scripts/audit.sh` and `skills/recursive-improve/scripts/inventory-witness.sh` → sibling audit/inventory scripts.
- **`skills/harness-nav/SKILL.md` source-tree mining works from any CWD.** The manual `ls` / `grep` / `head` recipes over `commands/`, `agents/`, and `BOUNDARY.md` now use `${KBG_PLUGIN_ROOT}`. `nav.py` invocations stay under `${CLAUDE_SKILL_DIR}`.
- **Standalone repo-clone block left repo-relative.** The "run from the repo clone" examples in `skills/assert-presence/SKILL.md` intentionally remain bare paths for raw-terminal use outside Claude Code.

## [0.2.73] — 2026-06-18

Normalize `KBG_PLUGIN_ROOT` to remove its trailing slash so command references render cleanly as `${KBG_PLUGIN_ROOT}/scripts/...`.

### Fixed

- **`hooks/session/command-root-anchor.sh`** now strips the trailing `/` from `${CLAUDE_PLUGIN_ROOT}` before exporting `KBG_PLUGIN_ROOT`. Prevents double slashes in command paths.

## [0.2.72] — 2026-06-18

Qualify the remaining command prose references to bundled scripts with `${KBG_PLUGIN_ROOT}` so no command file implies a repo-root CWD.

### Fixed

- **`commands/{pre-flight-plan-linter,pre-ship-verify,team-build,team-cleanup}`** now mention `${KBG_PLUGIN_ROOT}/scripts/...` in prose instead of bare repo-relative paths.

## [0.2.71] — 2026-06-18

Make command-level bundled-script references portable when the plugin runs in a foreign project. Commands have no official `${CLAUDE_COMMAND_DIR}` variable, so this release adds a SessionStart hook that exports `${KBG_PLUGIN_ROOT}` into the session via `CLAUDE_ENV_FILE`.

### Fixed

- **Command bash blocks no longer rely on repo-relative script paths.** `/wave-status`, `/team-cleanup`, `/validate-and-fix`, `/pre-ship-verify`, `/ship-task`, `/pre-flight-plan-linter`, `/ideate-search`, `/kbg-help`, and `/dismiss-stale` now reference bundled helpers through `${KBG_PLUGIN_ROOT}`.
- **`/wave-status` switched from `${CLAUDE_PLUGIN_ROOT}` to `${KBG_PLUGIN_ROOT}`.** The new variable is the dedicated, session-exported bridge; command prose should not depend on the hook-only `${CLAUDE_PLUGIN_ROOT}` expansion.
- **`/dismiss-stale` no longer requires `cd <repo-root>`.** The stale-set computation reads `hooks/sensors.json` and `skills/harness-audit/scripts/audit.sh` from `${KBG_PLUGIN_ROOT}`.
- **`/kbg-help` validation shortcuts are now CWD-agnostic.** All `git-hooks/`, `scripts/`, `tests/`, `skills/`, and `eval/` invocations use `${KBG_PLUGIN_ROOT}`-qualified paths.

### Added

- **`hooks/session/command-root-anchor.sh`** — matcher-less SessionStart hook that appends `export KBG_PLUGIN_ROOT=<plugin-cache>` to `CLAUDE_ENV_FILE`. Registered in `hooks/hooks.json`.

## [0.2.70] — 2026-06-18

Make skill-body bundled-script references strictly official-compliant: eliminate the last cross-sibling `${CLAUDE_SKILL_DIR}/../` traversals and all `${CLAUDE_PLUGIN_ROOT}` references in skill-body prose by routing every skill through its own per-skill wrapper script.

### Fixed

- **Cross-sibling skill script references now resolve without traversing sibling directories.** Skills that executed helpers owned by other skills (`skills/{create-jira-bug,create-jira-story}` → `skills/acli/scripts/md2adf.py`; `skills/assert-presence` → `skills/decommission/scripts/witness.sh`) previously told the model to use `${CLAUDE_SKILL_DIR}/../acli/...` or `${CLAUDE_SKILL_DIR}/../decommission/...`. Each consuming skill now ships its own wrapper under `scripts/` that resolves the plugin root from the wrapper's own path and delegates to the sibling script. The skill body only ever references `${CLAUDE_SKILL_DIR}/scripts/<wrapper>`.
- **Top-level `scripts/` helpers are no longer referenced directly from skill-body prose.** `skills/{types-first,orchestrate,progressive-refine}` now source `${CLAUDE_SKILL_DIR}/scripts/task-board-lib.sh`; `skills/orchestrate` runs `${CLAUDE_SKILL_DIR}/scripts/dispatch.sh`; `skills/ideate` runs `${CLAUDE_SKILL_DIR}/scripts/convergence.sh`; `skills/{ship-change,review-pr}` run `${CLAUDE_SKILL_DIR}/scripts/run-acceptance.sh`; `skills/article-mine` runs `${CLAUDE_SKILL_DIR}/scripts/memory-lint.sh`. Each wrapper resolves the real script via `BASH_SOURCE[0]:-$0` path computation, so it works whether the wrapper is executed or sourced and whether the shell is bash or zsh.
- **Removed the remaining `${CLAUDE_PLUGIN_ROOT}` references from skill-body prose.** The variable is documented to expand in hook shell commands and command bash-injection contexts, not in plain skill-body prose. `skills/harness-audit/SKILL.md` now describes plugin resolution without naming the variable.

### Why not just use `${CLAUDE_PLUGIN_ROOT}` everywhere?

Official docs do not guarantee `${CLAUDE_PLUGIN_ROOT}` expansion in skill-body markdown or in skill-body bash blocks. The wrapper approach keeps every skill self-contained under `${CLAUDE_SKILL_DIR}` (which *is* documented to expand in skill bodies) and removes any assumption about which runtime contexts expand which variable.

## [0.2.69] — 2026-06-18

Second full-fleet portability sweep: clean up the remaining runtime surfaces that still referenced repo-relative paths or sibling markdown links, which break when the plugin runs **in another project**.

### Fixed

- **Re-sweep caught and fixed additional foreign-CWD breaks.** The adversarial pass found: a double `${CLAUDE_SKILL_DIR}` typo in `skills/acli/SKILL.md`; the `/wave-status` Python helper importing `scripts/task_board_lib` from a user-project-relative repo root; sibling `[reference.md](reference.md)` markdown links in `skills/{hotfix,ship-change,clarify-first,inventory,semantic-code}`; cross-file markdown links in `skills/{ideate,orchestrate/orchestrate/reference,harness-nav}` plus `agents/inferential-structural-judge.md`; `skills/{types-first,orchestrate,progressive-refine}` telling the operator to use repo-relative `scripts/task_board_lib.sh`; `skills/article-mine` invoking `skills/memory-lint/scripts/memory-lint.py` by repo-relative path; and `skills/usage-monitor` cross-references that pointed at `.scratch/`, `docs/`, and `hooks/` files. All converted to `${CLAUDE_PLUGIN_ROOT}`- or `${CLAUDE_SKILL_DIR}`-relative code spans / commands, or demoted to non-clickable location prose where no portable expansion exists.

## [0.2.68] — 2026-06-18

Make the vendored `thinking-skills` / `reasoning-models` references actually resolvable when the plugin runs **in another project**. A workflow (parallel official-docs verification + full repo reference inventory + adversarial skeptic) confirmed the root cause: `${CLAUDE_PLUGIN_ROOT}` expands **only in hook shell commands** — never in skill/command/doctrine prose the model reads — and the `Read` tool resolves relative paths against the *user's* CWD, not the plugin cache. So every `../../docs/reference/reasoning-models.md` link (and the bare path in `METHODOLOGY.md`) was a broken `Read` target for anyone but the owner dogfooding inside the repo. The cache path is version-pinned (`.../kbg/<version>/`), so hardcoding an absolute path is not an option either.

### Fixed

- **`doctrine-bootstrap.sh` now injects the resolved absolute catalog path each session (keystone).** `${CLAUDE_PLUGIN_ROOT}` does expand in the hook shell, so the hook appends one pointer line carrying the concrete absolute path to `docs/reference/reasoning-models.md` and the `docs/reference/thinking-skills/` tree. This is the one always-on reference that resolves from any CWD and survives every version bump. Verified end-to-end: a foreign-CWD hook run injects a `Read`-able absolute path. The pointer now includes an explicit "open only when a task calls for one of these frames" guard so the model treats the catalog as a reference to reach for, not ambient context to lean on.
- **Demoted 6 broken markdown links to honest in-repo location prose** in `METHODOLOGY.md` and `skills/{adr,critical-eval,orchestrate,perf,probe}/SKILL.md` + `commands/fix-bug.md`. The mental-model names were already stated inline, so the clickable `../../docs/...` link (which never resolved when installed elsewhere) is replaced with the bare `docs/reference/reasoning-models.md` code-span; the always-injected absolute path is how the model actually opens it.
- **Fixed `${CLAUDE_SKILL_DIR}`-relative bundled-script calls across 10 user-facing skill surfaces.** A full sweep found the same portability defect in executable paths: `skills/{create-jira-bug,create-jira-story,acli,decommission,assert-presence,orchestrate,ideate,review-pr,ship-change/reference}` and `skills/acli/{REFERENCE,examples}`. The skill body now uses `${CLAUDE_SKILL_DIR}` (and `../` / `../../` where the script lives in a sibling skill or top-level `scripts/`) so `python3`/`bash` invocations resolve against the installed plugin cache from any project CWD. The standalone "run from the repo clone" blocks in `decommission` and `assert-presence` are intentionally left repo-relative for raw-terminal use outside Claude Code.
- **Documented the command/harness-maintenance class as by-design.** Commands and harness-maintenance surfaces (e.g. `/kbg-help`, `/team-cleanup`, `/pre-ship-verify`, `kbg:harness-audit`) still use repo-relative paths because there is no official portable expansion in command prose (`${CLAUDE_PLUGIN_ROOT}` is hook-shell-only, and no `${CLAUDE_COMMAND_DIR}` exists). They are intended to operate with the working tree set to the `kbg` repo root, so their relative references are correct, not bugs.

### Rejected

- **Flattening the 39 `SKILL.md` files to plain `.md`** — churns the verbatim-vendored tree and destroys the clean re-sync / MIT-license-hygiene property (pinned commit `0313ee0`) to "fix" a reference-resolution problem that has nothing to do with file format.
- **A thin index skill** — adds a fleet surface for reference text the upstream's own eval shows gives zero accuracy benefit, re-introducing the "looks invokable" confusion the deliberate `docs/` placement avoids.

## [0.2.67] — 2026-06-18

Final pass of the count-drift sweep: refresh the last stale current-fleet snapshots and stop the `harness-audit` sample output from re-drifting.

### Fixed

- **Three stale current-fleet snapshots refreshed.** `docs/onboarding.md` (27/26/8 → 29/38/21) and `docs/agent-teams-setup-notes.md` (28/37/18 → 29/38/21) stated outdated agent/skill/command counts.
- **`harness-audit` sample output no longer hardcodes a fleet snapshot.** The skill's `## Output` example read `Fleet: 27 agents, 26 skills, ...`; replaced with `<n>` placeholders, since the skill computes the real counts live and a hardcoded snapshot in its own doc only re-drifts. (Same fix class as the softened volatile annotations in `v0.2.66`.) Left untouched: `CHANGELOG`, ADR/voice point-in-time records, eval fixtures, and prose examples — those are history or different meanings, not current-fleet claims.

## [0.2.66] — 2026-06-18

Surface consolidation to cut adopter cognitive load **without** adding a router. A two-workflow analysis (redundancy map + routing-technique research, each with an adversarial doctrine review) confirmed the "middle surface that routes" already exists as a flat tier (`orchestrate` / `triage` / `harness-nav` / `/kbg-help`); the work was to unify and de-duplicate, not build a dispatcher. An explicit routing tree / BST / router-agent was rejected (90 surfaces, not the ~1,000 where flat description-routing degrades; a model that routes-then-acts edges into the ADR 0002 self-gate).

### Removed

- **Deleted the duplicate `kbg-help` skill.** `skills/kbg-help/SKILL.md` was a same-name content twin of the `/kbg-help` command (both a read-only "reference card", differing only "Detailed" vs "Quick" — a distinction no natural-language trigger encodes). The command survives as the user-typed front door. Skill count 39 → 38.

### Added

- **Audit check #20.5 — duplicate-surface detector.** Flags two surfaces that share a `name:` and a near-identical description (≥ 0.85 ratio or a ≥ 60-char identical run) — the recurrence guard for the `kbg-help`-style dup. False-positive-free on intentional skill↔command twins like `ideate`, whose descriptions differ (ratio 0.06). The 1,536-char description-truncation check already existed (`audit.sh` `DESC_MAX`), so it was not re-added.

### Changed

- **`/kbg-help` rewritten as a 6-stage entry-point card.** Replaced the hand-maintained (already-stale) surface tables with a DEFINE / PLAN / BUILD / VERIFY / REVIEW / SHIP entry-point map that points at the auto-generated `BOUNDARY.md` tables, so the card can no longer drift from the real fleet.
- **Sharpened 12 description collisions that mis-route.** `security-auditor` skill vs `security-reviewer` agent (standalone audit vs in-`review-pr` panel flag); the four name-only skills (`7-agent-pattern`, `task-sizing`, `types-first`, `progressive-refine`) lifted body triggers into frontmatter; `research-brief` vs `/deep-dive`; `technical-writer` "API docs" → narrative usage guides (OpenAPI/SDK reference defers to `api-doc-specialist`, including the body section); `harness-health` vs `harness-coverage` staleness split; `critical-eval` vs `silent-failure-hunter`; jira `create-*` → `atlassian:*` pointers; and the `ship-change` vs `/ship-task` fork contradiction. No surfaces merged — these are genuine layer / twin / aspect distinctions.
- **Recorded a `noun-verb` naming rule for new `harness-*` surfaces** in `CLAUDE.md` (reuse an existing verb before coining one; new surfaces only — no fleet rename).
- **Refreshed `BOUNDARY.md` and `README.md` counts; softened volatile annotations.** Module Boundaries counts synced to the live fleet (29 agents / 38 skills / 21 commands / 43 hooks); README skills 39 → 38; and hardcoded `plugin.json v0.1.3` / `201/0 expected` / `26 I` annotations replaced with source-of-truth pointers and non-numeric expectations so they stop re-drifting.

## [0.2.65] — 2026-06-18

Machine-check a doctrine-gate sync seam and fix a latent audit abort.

### Added

- **Audit #41 — doctrine-gate seam check.** `block-bash-doctrine-write.sh` and `doctrine-edit-gate.sh` hardcode the same doctrine-file set in two encodings (a factored regex vs a flat case-glob) joined only by a comment; drift would reopen the Bash-redirect bypass for any file guarded by one gate but not the other. The check normalizes both to a sorted basename set and WARNs on drift; the `doctrine-seam-repo` fixture goes red if it is reverted.

### Fixed

- **Latent `set -e` + `diff` abort in audit #37/#41.** `$(diff …)` exits 1 on differences, aborting the check before its `warn` fires; guarded with `|| true`. (#38/#40 run their diffs in `if` conditions and were never at risk.)

## [0.2.64] — 2026-06-18

Make the SessionEnd `ideate` hooks and memory capture parse JSONL transcripts correctly.

### Fixed

- **JSONL transcript parsing in SessionEnd ideate hooks.** Replaced jq-only `.messages[]` filters with a Python parser that handles JSONL event streams and nested `message.content` arrays, counting both `ideate` / `kbg:ideate` Skill calls and `/ideate` slash commands.
- **Convergence no longer forces an Ollama call on every SessionEnd.** The broken counter mis-fired on sessions with no ideate calls; the early-exit now works.
- **Memory capture falls back to the parent assistant message**, so slash-triggered ideate runs still extract a problem statement.

### Added

- **Dynamic critical-hooks tests** for JSONL `ideate` and `kbg:ideate` transcripts.

## [0.2.63] — 2026-06-18

`SENIOR-DEV` output-style polish from a panel review.

### Changed

- **Reframed negative voice rules as positive directives**, relaxed the one-reason rule, and added rules for owning uncertainty, disagreeing on the idea (not the person), and stating assumptions over multi-question intake. Kept the silent pre-send self-check.

### Removed

- **Dropped the unsupported `force-for-plugin` flag** from `output-styles/SENIOR-DEV.md` (added in `v0.2.59`, not a recognized output-style field).

## [0.2.62] — 2026-06-18

`SENIOR-DEV` warmth and direct-address calibration.

### Changed

- **Tightened the opening role and added direct-address + warmth-calibration rules** (neutral for errors and bad news, concise for success, no forced enthusiasm), keeping the anti-AI-tell guidance and the self-check.

## [0.2.61] — 2026-06-18

Fix SessionEnd hook cancellations by capping unbounded I/O inside `ideate-convergence-capture` and moving `ideate-memory-capture` reindex off the SessionEnd critical path.

### Fixed

- **`ideate-convergence-capture.sh` no longer blocks SessionEnd on Ollama.** The Ollama embedding call now uses an 8-second timeout (override via `KBG_IDEATE_OLLAMA_TIMEOUT`) and still appends the record with a null embedding on failure.
- **`ideate-memory-capture.sh` reindexes qmd asynchronously.** The cheap `capture` step stays synchronous; the potentially slow `qmd update` + `qmd embed` now runs via `nohup` in the background so SessionEnd returns immediately.
- **`hooks/hooks.json` declares a 25-second SessionEnd budget for both hooks.** This makes the Claude CLI hook timeout contract explicit and gives the internal caps headroom.

## [0.2.60] — 2026-06-18

Harden `SENIOR-DEV` output style against official best practices. Adds explicit format rules, scope boundaries, and a model-facing description while keeping the senior lead register.

### Changed

- **`SENIOR-DEV` description is now model-facing.** States the style's job as a register directive: lead with conclusions, state tradeoffs, prefer plain English, structure only when it carries information.
- **Added `Format` section.** Table-driven rules for one-line answers, two-option comparisons, ≥3-item tables, numbered sequences, bold caveats, and nested bullets. Structure must carry information, not fill space.
- **Added `Scope` section.** Clarifies that this file governs voice/register only and does not override METHODOLOGY, CLAUDE.md, or agent-specific instructions.

## [0.2.59] — 2026-06-18

Output-style hardening + audit alignment. Renames `TECH-LEAD-THAI` to `SENIOR-DEV`, makes it the plugin-default output style, and aligns the audit suite with the official Claude Code hook/tool schemas.

### Changed

- **Output style renamed and refactored.** `output-styles/TECH-LEAD-THAI.md` → `output-styles/SENIOR-DEV.md`. Dropped the Thai code-switched register section; kept the senior engineering lead voice, readability≠brevity rule, and working-posture cross-reference. (`v0.2.57`)
- **`SENIOR-DEV` is now plugin-default.** Added `force-for-plugin: true` to `output-styles/SENIOR-DEV.md` so enabling the plugin applies the style automatically; updated `README.md` caveats and plugin manifest descriptions. (`v0.2.59`)

### Fixed

- **Audit counted only 4 of 6 auto-discovery dirs.** Fleet header now reports `output-styles` and `themes`. (`v0.2.58`)
- **Audit `VALID_TOOLS` was stale.** Replaced the hardcoded allowlist with the grantable agent tool surface from the official docs and removed deprecated/internal-only tokens (`MultiEdit`, `BashOutput`, `KillShell`, `SlashCommand`, `TodoWrite`, `Task` alias). (`v0.2.58`)
- **Audit `hooks.json` schema was type-naive.** Check #31.4 now branches required-field validation by hook type (`command`/`http`/`mcp`/`agent`/`prompt`) and warns on unknown types. (`v0.2.58`)

## [0.2.58] — 2026-06-18

### Fixed

- **`audit.sh` aligned with the official Claude Code docs.**

## [0.2.57] — 2026-06-17

### Changed

- **Output style `TECH-LEAD-THAI` renamed → `SENIOR-DEV`**; Thai register dropped.

## [0.2.56] — 2026-06-17

### Added

- **6 model-era doctrine follow-ups** shipped from the Fable 5 / Opus 4.8
  prompting drill-down.

## [0.2.55] — 2026-06-17

### Fixed

- **Escalation-mirror doc-vs-reality gap closed** + a latent block-scalar parse
  bug fixed.

## [0.2.54] — 2026-06-17

### Added

- **2 more sync-seam guards** — dismiss-stale Q3 thresholds + the fan-out band.

## [0.2.53] — 2026-06-17

### Added

- **3 sync-seam guards** against silent drift; fixed live DOMAINS.md drift.

## [0.2.52] — 2026-06-17

### Fixed

- **dismiss-stale Q3 `is_stale` mirror** synced with the observable guard.

## [0.2.51] — 2026-06-17

### Added

- **4 legacy TSV loggers mirrored** into the governance journal.

## [0.2.50] — 2026-06-17

### Fixed

- **False 'silent never' staleness alarms stopped** for non-journaling sensors.

## [0.2.49] — 2026-06-17

### Fixed

- **`kbg:article-mine` SKILL.md localized** to the kbg layout.

## [0.2.48] — 2026-06-17

### Fixed

- **task-lifecycle F7 stderr** stale user-facing path corrected.

## [0.2.47] — 2026-06-17

### Fixed

- **Stale flat hook-path citations swept** (docs / scripts / eval) + team-build
  B3 hardening.

## [0.2.46] — 2026-06-17

### Added

- **Vendored cc-thinking-skills** as common-references + a cross-ref hygiene
  refactor.

## [0.2.45] — 2026-06-17

### Added

- **Sydney Runkle "Loop Engineering" cataloged**; the L3/L4 rejection locked into
  BOUNDARY.md + a regression fixture.

## [0.2.44] — 2026-06-17

### Fixed

- **Audit guarded against a missing `~/.claude/skills`** in the command-group
  pipeline, so `set -e` reaches the Summary.

## [0.2.43] — 2026-06-17

### Fixed

- **`set -e` safety on audit process substitutions** so the audit reaches its
  Summary under CI.

## [0.2.42] — 2026-06-17

### Added

- **0xCodez harness-roadmap memory** + a BOUNDARY XREF block +
  harness-vs-loop-autonomy regression fixture.

## [0.2.41] — 2026-06-17

Reliability + safety sweep. Closes findings from the 2026-06-17 multi-agent audit.

### Fixed

- **PreToolUse fail-open on missing `jq` (P0).** `hooks/_lib.sh` set `INPUT_PARSE_ERROR=0`
  when `jq` was missing, so security gates reached their own `exit 1` blocks and
  discarded the `permissionDecision`, failing open. Now non-empty input without `jq`
  is treated as a parse failure; `hook_guard_unreadable` emits `ask` and exits 0.
  All PreToolUse gates now use the shared `hook_require_jq` helper instead of
  inline `exit 1` checks. (`v0.2.41`)
- **Undefined `kbg_lock_release` (P0).** `hooks/lifecycle/task-lifecycle.sh` called
  `kbg_lock_release` at lines 161 and 282, but `scripts/task_board_lib.sh` only defined
  `kbg_lock_acquire`. Added `kbg_lock_release` with safe double-release handling. (`v0.2.41`)
- **`acli-set-desc.sh` Python injection.** A Jira key containing a single quote broke
  the Python one-liner (or worse). Pass the key via `sys.argv[1]` instead of interpolating
  it into a string literal. (`v0.2.41`)
- **`review-pr-marker.sh` GNU `stat` portability.** `stat -f %m || stat -c %Y` accepted
  GNU's `--file-system` output as mtime. Reversed the order so GNU's `-c %Y` wins on Linux
  and BSD's `-f %m` is the fallback. (`v0.2.41`)
- **`lock-claim.sh` temp-file leak.** Added an `EXIT` trap to clean up the temporary
  claim JSON, and updated `ERR` traps to remove it on failure paths. (`v0.2.41`)
- **`precompact-backup.sh` hook convention violation.** Removed `set -e` so the advisory
  PreCompact hook matches the hook-wide `set -uo pipefail` convention. (`v0.2.41`)
- **`usage-summarize.sh` totals rendering.** Removed a placeholder table row that was never
  replaced, and replaced the brittle single-comma thousands formatter with a recursive
  `fmt` helper that handles numbers of any size. (`v0.2.41`)
- **Stale `orchestrator-nudge.sh` path patterns.** PATH_PATTERNS used `claude/...` prefixes
  from the pre-cutover layout and referenced a missing `DOMAINS.md`. Added `DOMAINS.md`
  with a bounded-context table and updated PATH_PATTERNS to root-relative paths and the
  actual skill/command names. (`v0.2.41`)
- **Stale provenance docs.** Updated `README.md` version badge and newest-additions blurb,
  regenerated `BOUNDARY.md`, corrected `hooks/sensors.json` provenance to 43 unique scripts
  / 58 registrations, and bumped both plugin manifests to 0.2.41. (`v0.2.41`)

## [0.2.40] — 2026-06-17

### Added

- **Shared error-handling contract (`err.sh`)** adopted + inventory/usage-monitor scripts migrated to it; `audit.sh` set-e safety + empty-dir fleet counts; actionable inferential-FB journals; smarter harness-nav L3 miner.

## [0.2.39] — 2026-06-17

### Added

- **`skills/_lib/err.sh` shared error-handling contract** introduced; first inventory/usage-monitor scripts migrated onto it.

## [0.2.38] — 2026-06-17

### Changed

- **Official-docs audit drift fixes** in `audit.sh`.

## [0.2.37] — 2026-06-17

### Changed

- **Relocated test / eval / benchmark artifacts** into the `tests/` tree.

## [0.2.36] — 2026-06-17

### Changed

- **Moved harness-audit test fixtures out of component dirs** so fake files stop shipping into the plugin cache.

## [0.2.35] — 2026-06-17

### Added

- **`/ideate-search`** — qmd-backed recall of past ideate runs.

## [0.2.34] — 2026-06-17

### Fixed

- **ideate-convergence** switched to local Ollama `all-minilm` embeddings; fixed the jq invocation count.

## [0.2.33] — 2026-06-17

### Changed

- **Cache-invalidation bump** for the `/ideate` command + convergence hook.

## [0.2.32] — 2026-06-17

### Changed

- **Cache-invalidation bump** after the ideate-rotate backtick fix.

## [0.2.31] — 2026-06-17

### Added

- **ideate ADHD fine-tunes** — SessionStart frame rotation, daily budget counter, standalone CLI.

## [0.2.30] — 2026-06-17

### Added

- **`ideate-critic` fresh-context agent** + ideate-quality eval dataset + regression contract.

## [0.2.29] — 2026-06-17

### Added

- **`kbg-help` skill + `/kbg-help` command** as the quick-reference surface.

## [0.2.28] — 2026-06-17

### Added

- **`kbg:ideate`** — 15-frame parallel divergent-ideation L2 skill (ported from ADHD).

## [0.2.27] — 2026-06-17

### Changed

- **Dedicated CI job for the critical-hooks suite** + halved journal minting.

## [0.2.26] — 2026-06-16

### Fixed

- **Missing teammate-teardown step added** — `/team-build` no longer leaves idle teammates after a build.

## [0.2.25] — 2026-06-16

### Changed

- **5-surface ceremony/blanket dig — 11 fixes**, including a governance check that had gone dark (audit globs missed relocated hook subdirs).

## [0.2.24] — 2026-06-16

### Changed

- **Demoted the always-on plugin-cache I1** to a context line + un-rotted 2 orphaned fixture tests.

## [0.2.23] — 2026-06-16

### Changed

- **Retired ceremony + blanket patterns** found in the 4-agent dig (incl. the #31.1 canonical-sections boilerplate trap).

## [0.2.22] — 2026-06-16

### Changed

- **Acted on the grill-with-docs challenge** of the disable-model-invocation criterion.

## [0.2.21] — 2026-06-16

### Changed

- **`disable-model-invocation` made a per-surface criterion**, not a blanket flag.

## [0.2.20] — 2026-06-16

### Fixed

- **De-escalated `acli` + `security-auditor` descriptions** (cleared #33 I2/I3).

## [0.2.19] — 2026-06-16

### Fixed

- **Cleared all 5 residual backlog items** from the whole-repo dig.

## [0.2.18] — 2026-06-16

### Fixed

- **Closed 3 unguarded autonomy-invariant surfaces** + the #32 deleted-skill hole.

## [0.2.17] — 2026-06-16

### Fixed

- **WARN-tier cleanup** from the whole-repo dig.

## [0.2.16] — 2026-06-16

### Fixed

- **Closed 5 CRIT enforcement-gate bypasses** found in the whole-repo adversarial dig (git global-opt, db comment+newline, validator quote-glue, jq fail-open, run-acceptance file-skip).

## [0.2.15] — 2026-06-16

### Fixed

- **Resolved all 4 flagged items from the fan-out audit** — F8.4 advisory, panel opt-out, fixtures, '3-5 teammates' clarified as peak concurrent.

## [0.2.14] — 2026-06-16

### Fixed

- **4 real defects in the min-3/max-5 dispatcher** (adversarial audit).

## [0.2.13] — 2026-06-16

### Fixed

- **F8.4 min-3 floor** — panel opt-out + wave-band clarification.

## [0.2.12] — 2026-06-16

### Added

- **Collapsed the fan-out band to min 3 / max 5** (F8.4 + F8.5).

## [0.2.11] — 2026-06-16

### Changed

- **Reconciled METHODOLOGY Rule 6 for the model era** + audit #33 flags over-forceful skill imperatives.

## [0.2.10] — 2026-06-16

### Changed

- **Trimmed 4 skill descriptions** under the 500-char injection-audit threshold.

## [0.2.9] — 2026-06-16

### Changed

- **Async bypass-audit-log + mtime cache** for memory-lint-check (perf).

## [0.2.8] — 2026-06-16

### Changed

- **Restored `+x` perms, fixed Pyright** findings.

## [0.2.7] — 2026-06-16

### Changed

- **Reorganized the flat `hooks/` dir into 6 categorical subdirs.**

## [0.2.6] — 2026-06-16

### Added

- **Extended `_sensor_heartbeat`** to computational-FB + inferential-FF always-on hooks.

## [0.2.5] — 2026-06-16

### Added

- **`_sensor_heartbeat`** for active-coverage journal events.

## [0.2.4] — 2026-06-16

### Added

- **Wave-3 gap closure** — doctrine, advisory hooks, `harness-coverage` 12-cell grid + `inferential-structural-judge`.

## [0.2.2] — 2026-06-15

### Added

- **Vertical Agent L1/L2/L3 gap closure** applied (the context-tier model).

## [0.2.1] — 2026-06-15

### Added

- **9-step-loop gaps closed** — post-edit-test hook + review-state gate + `/ship-task`.

## [0.2.0] — 2026-06-15

### Added

- **Silent-sensors gap closed** via the SessionStart staleness notifier.

## [0.1.18] — 2026-06-15

### Fixed

- **`clarify-first` trigger rewritten** to fire on pre-dispatch ambiguity.

## [0.1.17] — 2026-06-15

### Fixed

- **create-jira: acli-first + MCP fallback**, aligned with ACLI.md doctrine.

## [0.1.16] — 2026-06-15

### Added

- **`create-jira-bug` + `create-jira-story`** templates (Thai PO/QA format).

## [0.1.15] — 2026-06-15

### Changed

- **Trimmed 8 watchlist skills under 120 tok**; agent `tools:` kept as a comma scalar per official docs.

## [0.1.14] — 2026-06-15

### Fixed

- **Option-2 drill-down** — trimmed skills, fixed cross-refs, hardened YAML, aligned CLAUDE.md with official docs.

## [0.1.13] — 2026-06-15

### Fixed

- **Restored routing accuracy** + command-frontmatter audit hardening.

## [0.1.12] — 2026-06-15

### Changed

- **Converted 6 skills to name-only** (recursive-improve, adr, task-sizing, probe, progressive-refine, semantic-code).

## [0.1.11] — 2026-06-15

### Changed

- **Trimmed 23 agent + 5 command descriptions to ≤480 chars**; converted 8 skills to name-only.

## [0.1.10] — 2026-06-15

### Changed

- **Trimmed 14 skill descriptions to ≤120 tok.**

## [0.1.9] — 2026-06-12

Patch release — security + reliability sweep (Wave 8). Closes all remaining P0–P2 findings from the 2026-06-12 drill-down audit: echo-injection, TOCTOU race, subdirectory bypass, backslash-quote bypass, sha256sum portability, mktemp atomicity, audit/journal silent drops, and schema-rot closure.

### Fixed

- **Echo flag injection (P0).** 18 hook scripts used `echo "$VAR" |` which is vulnerable to `-n` / `-e` flag injection when `$VAR` starts with a hyphen. Replaced all standalone piped `echo` patterns with `printf '%s\n' "$VAR" |`. (`wave-8`)
- **Audit / journal silent drops (P0).** `hooks/_lib.sh` `hook_audit_log` and `journal_append` appended to TSV / JSON files without checking exit status. A full disk or permission error would silently lose audit records. Added fail-loud wrappers (`exit 2` + stderr) around both append operations. (`wave-8`)
- **Doctrine-bootstrap TOCTOU + `set -e` crash (P0).** `doctrine-bootstrap.sh` had a time-of-check-to-time-of-use race (`[ -r file ]` then `grep file`) and `set -e` caused abort on `grep` miss. Removed `set -e`; added atomic `cat` into variable before grep. (`wave-8`)
- **Doctrine-edit-gate subdirectory bypass (P0).** `case "$DIR" in */claude)` only matched direct children, allowing nested paths like `/tmp/project/claude/foo` to bypass. Added `*/claude/*` and `*/.claude/*` depth patterns. (`wave-8`)
- **Block-bash-doctrine-write nested-path bypass (P0).** Regex only matched direct `/claude/` children. Changed `DOCTRINE_PATH_RE` to `(/claude/.*|/\\.claude/.*|/kbg-harness/.*)`. (`wave-8`)
- **Secret-read-guard backslash-quote bypass (P0).** `tr -d '"'\''\\'` removed quotes but not backslashes, allowing `\\"foo.pem\\"` to evade detection. Added `\\\\` to the `tr -d` set. (`wave-8`)
- **Config-change-log portability + atomicity (P1).** Hash computation used GNU-only `sha256sum`; added `shasum -a 256` fallback chain for BSD / macOS. Atomic update used predictable `$HASHES.tmp`; replaced with `mktemp` to close symlink-race. (`wave-8`)
- **Usage-monitor-capture silent failures (P1).** `mkdir` and `jq` write failures were unlogged. Added error messages to stderr (still exits 0 to avoid blocking session end). (`wave-8`)
- **Session-summary echo injection (P1).** Replaced standalone `echo "$STATUS"` and `echo "$COMMITS"` with `printf '%s\n'` equivalents. (`wave-8`)

### Added

- **Schema-rot closure — 29 SKILL.md canonical sections.** Added `## Input Contract`, `## Output Format`, and `## Failure Modes` to 29 skills previously missing them. (`wave-8`)
- **Schema-rot closure — 10 evals.json fixtures.** Created `evals/evals.json` for 10 skills: `7-agent-pattern`, `accept-task`, `article-mine`, `memory-trim`, `progressive-refine`, `recursive-improve`, `task-sizing`, `triage`, `types-first`, `usage-monitor`. (`wave-8`)

### Changed

- **Harness-audit eval criteria updated.** `eval/datasets/harness-audit.json` now expects clean audit output ("Critical: 0", "Warnings: 0") instead of expecting schema-rot findings. (`wave-8`)
- **BOUNDARY.md regenerated.** Regenerated via `inventory-boundary.sh` after skill count and path corrections. (`wave-8`)

**Green bar:** audit `0C / 0W / 1I exit 0`; eval `14 passed / 0 failed / 27 skipped / 0 regressions`; critical-hooks `204/0`; `claude plugin validate --strict .` ✔.

## [0.1.8] — 2026-06-12

Patch release — eval fixture expansion + BSD grep portability + hook reliability fixes.

### Added

- **Eval fixtures for 10 skills + commands dataset.** `eval/datasets/` now covers
  skills previously missing regression coverage: `7-agent-pattern`, `accept-task`,
  `article-mine`, `memory-trim`, `progressive-refine`, `recursive-improve`,
  `task-sizing`, `triage`, `types-first`, `usage-monitor`, plus a `commands.json`
  schema-compliance dataset. (`3a41132`)

### Fixed

- **BSD grep `\b` portability (P0).** Five hooks (`iron-rule-reminder`,
  `auto-review-nudge`, `skill-nudge`, `orchestrator-nudge`, `db-write-gate`)
  used GNU-specific `\b` word boundaries in `grep -E` patterns, which silently
  fail on macOS (BSD grep). Replaced with portable `(^|[^[:alnum:]])` …
  `([^[:alnum:]]|$)` anchors. (`wave-7`)
- **Hook `set -e` + `jq` crash (P0).** `task-lifecycle.sh` aborted on malformed
  JSON stdin because `jq` exits non-zero under `set -e`. Added `|| echo ""`
  fallback guards to all jq extractions. (`wave-7`)
- **PreCompact backup crash (P0).** `precompact-backup.sh` used `ls` glob +
  `pipefail` which aborts when zero backups match. Replaced with `find` +
  `sort` pipeline. (`wave-7`)
- **Skill count drift (P1).** README, `plugin.json`, and `marketplace.json`
  claimed 31 skills; actual count is 32 (including `7-agent-pattern`).
  Updated all three locations. (`wave-7`)
- **Skill-nudge stale command name (P1).** `skill-nudge.sh` emitted
  `/resolve-review` but the actual command is `/address-review`. Updated
  emission and trigger regex. (`wave-7`)

## [0.1.7] — 2026-06-12

Patch release — real plugin delivery declaration + symlink retirement completion.

### Fixed

- **Symlink retirement (Wave 6).** All `~/.claude/skills/` and
  `~/.claude/commands/` symlink assumptions removed. Skills docs, evals, and
  hooks now reference repo-relative paths. Plugin cache (`~/.claude/plugins/cache/`)
  is the sole delivery path. (`7026717`)
- **Hook reliability.** `task-lifecycle.sh` F7 test-claim gate hardened:
  anchored regex, `set -e` safety, `python3` failure propagation, lock timeout
  warnings, and source/log-dir fail-loud. (`ed55d2b`, `99f7b52`, `3aada87`)
- **Validator bash guard.** Removed `python3 -c`, `node -p`, `go build` from
  allow-list; added double deny-list check; broadened `cp`/`mv`/`tee` patterns.
  (`ed55d2b`)

## [0.1.6] — 2026-06-12

Patch release — closes the last 25-skill schema-rot INFO gap by extending
the audit's `last_reviewed_reason:` deferral convention (already used at
#30 for eval-target freshness and #31.2 for plugin.json) to #31.1
(skill SKILL.md canonical-sections). No runtime behavior change; no
surface-area change.

### Added

- **#31.1 honors `last_reviewed_reason:`** — a skill missing `## Input
  Contract` / `## Output Format` / `## Failure Modes` is no longer
  flagged if its SKILL.md frontmatter OR its sibling `evals/evals.json`
  carries a `last_reviewed_reason:` marker. Decay-cadence
  (`docs/harness-decay-cadence.md`) owns the quarterly human sweep that
  revisits these. The audit is sensor only, sensor-with-documented-
  deferral is preferred over stubbing (a stub would silently defeat the
  check).

### Fixed

- **#30 + #31.1 `REASON_RE` regex** — was
  `^[\s#/*-]*last_reviewed_reason:\s*\S+`. That pattern only matched YAML
  frontmatter and `# comment` forms; the JSON form
  `"last_reviewed_reason": "…"` (which all 20 `evals/evals.json` files
  use) had a literal `"` between the leading whitespace and the token,
  so the 7 skills stamped in the 2026-06-11 epic were never actually
  being honored by the eval-target check. Fixed to
  `^[\s#/*'"]*last_reviewed_reason["']?\s*:\s*\S+` — matches JSON / YAML
  / comment. The class anchor pins the match to the right key
  (`blast_reviewed_reason` / `skill_name` do not match).

### Tests

- **#31.1 deferral regression guard** — 2 new hermetic fixture tests in
  `tests/hooks/runners/test-critical-hooks.sh`: (NN2) suppression via SKILL.md
  frontmatter marker, (NN3) suppression via `evals/evals.json` JSON-key
  marker. The (NN3) test is the load-bearing one — it guards the regex
  fix. Test count: 202 → 204.

### Eval side effects

- **`harness-audit-passing-plugin`** "No missing symlinks for existing
  commands" was passing at 0.1.5 by accidental lexical overlap with the
  25 schema-rot findings (the word "missing" appeared 25× in stdout,
  which the runner's synonym-aware keyword counter credited). With the
  schema-rot findings now suppressed, that false-positive unmasked the
  test's real defect (the criterion was checking for absence of a
  problem, which a positive-presence substring check cannot do
  semantically). Rewrote to a runner-supported pattern: "Critical: 0"
  (which the audit's summary footer actually emits).
- **`harness-audit-missing-symlink`** — pre-existing 1/3 failure not
  closed in the F1-F5 sweep. The audit's F1 plugin-aware bypass treats
  plugin-delivered commands (cache 0.1.3) as symlink-equivalent, so the
  test setup cannot trigger a CRIT in the current runtime. Applied the
  same `tags: ["manual"]` + `manual_reason:` convention as F5.

### State

- audit: 0C / 0W / 1I exit 0 (the 1 INFO is the plugin-version freshness
  on `.claude-plugin/marketplace.json`, which will age naturally on the
  next regen).
- eval: 19/24 pass + 0 fail + 5 skipped + 0 regressions. `--gate` exit 0.
- 25 skills now carry a documented `last_reviewed_reason:` deferral
  pointing at the quarterly cadence in `docs/harness-decay-cadence.md`
  (first sweep 2026-09).

## [0.1.5] — 2026-06-12

Patch release — closes the 5 carry-over eval-fidelity gaps triaged in
`.scratch/eval-fidelity-triage-2026-06-12.md`. Eval suite goes from
16/24 pass + 5 fail to 20/24 pass + 0 fail + 4 skipped (1 manual +
3 warning). `--gate` mode now exits 0. The Pyright diagnostics that
were flagging 3 unused locals in `eval/run-eval.py` are gone as a
side effect of the runner edits.

### Fixed

- **F2 `review-pr-acceptance-cross-check`** — rewrote the 3 prose
  criteria to use runner-supported patterns (file-exists + results.json
  + "At least 1 criteria passed"). Was 2/3 heuristic-miss.
- **F3 `ship-change-acceptance-exists`** — same rewrite as F2.
- **F4 `ship-change-no-contract`** — added "not found" + "skips" to
  criterion strings so the no-contract branch matches. Was 1/3.
- **F1 `harness-audit-eval-freshness`** — added a
  `context.kbg_eval_max_age_days` knob to the eval runner (subprocess
  env override) and rewrote the 2 criteria to use phrases the audit
  actually emits ("eval-target freshness" + "last reviewed"). The knob
  is what makes the freshness check testable in a known state.

### Added

- **`tags: ["manual"]` + `manual_reason:` eval convention.** Evals
  marked with this are skipped at runner time with a clear "no
  automated grader; behavior tested via sibling regressions + human
  review" note. Skipped evals are counted in the `skipped` summary
  bucket (not `failed`) and don't trigger `--gate` non-zero. Applied
  to F5 `loop-overshoot-workflow-cap` (cross-agent fan-out counting
  needs sub-agent transcript parsing, which Claude Code does not
  expose to plugins).

### Side effects

- The 3 Pyright diagnostics ("verbose" / "phrases" / "expected_rc" not
  accessed in `run-eval.py`) are gone — the recent runner edits
  collapsed those unused locals into the surrounding logic.

### Not changed

- `BOUNDARY.md` — no surface-area change (still 27 skills / 11
  commands / 27 agents / 35 hooks).
- `docs/onboarding.md`, `README.md` — no edits needed.
- Autonomy invariant (ADR 0002) — preserved; all 5 fixes are
  doc/eval-only, no behavioral changes to runtime.

## [0.1.4] — 2026-06-12

Minor release — closes the 2026-06-12 loop-engineering closure epic: 10
SYNTHESIS items promoted Partial → Present, 1 defer-documentation pattern
shipped, autonomy invariant (ADR 0002) preserved throughout. No breaking
changes; old components keep their contracts; new ones are additive.

This is the first release that ships the formal eval harness, the
recurring-cadence (decay/audit) tooling, and the autonomy-invariant
defer-documentation pattern as stable plugins. See the **Audit summary
(2026-06-12 closure epic)** table near the bottom of this entry for the
per-phase commit log.

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
    `verification-gate.sh`, `tests/hooks/runners/test-critical-hooks.sh`, `scripts/governance/verification-tier-audit.py`,
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
  cases** in `tests/hooks/runners/test-critical-hooks.sh`. The revert chain (`5ecdac8`) was transient —
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

- **Validator stderr wording** (`69a4f84`, F1) — `scripts/pr/review-pr-journal-pre-emit-validator.py:188-189`
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
  consumer can add them later without breaking the contract); `scripts/governance/governance-summary.py`
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
- **17 new test cases in `tests/hooks/runners/test-critical-hooks.sh`** — 6 AC cases for
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

- `bash tests/hooks/runners/test-critical-hooks.sh` → 176 passed, 0 failed (was 172)
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

### Phase 1.2 — formal eval harness (D6 from loop-audit, 2026-06-12, 1 commit `35ead10`)

Closes `dataset-eval-before-ship` (SYNTHESIS row #42) from
`.scratch/harness-loop-audit-2026-06-12/SYNTHESIS.md`. Promotes the
row from `Partial` to `Present` — held-out dataset + regression
fixture + CI gate shipped.

- 1 new directory: `eval/` with 4 subdirs — `datasets/` (3 JSON:
  `harness-audit`, `ship-change`, `review-pr`), `regressions/`
  (1 fixture: `loop-overshoot`), `fixtures/` (1 acceptance fixture),
  and the runner.
- 1 new script: `eval/run-eval.py` (342 lines) — entry point with
  `--dataset`, `--regression`, and `--gate` flags. Schema-validates
  input, computes pass/fail per item, emits machine-readable JSON.
- 1 CI gate: `.github/workflows/validate.yml:32-46` (`eval-harness`
  job) — runs `eval/run-eval.py --gate` on every PR. Fails the
  build on regression.
- Verification: `python eval/run-eval.py` green; CI workflow
  valid; no existing test broken.
- Promotes SYNTHESIS row #42 from `Partial` → `Present` (audit
  re-baselined in `.scratch/harness-loop-audit-2026-06-12/SYNTHESIS-REAUDIT.md`).

### Phase 1.3 — done-means-verified-with-proof (2026-06-12, 1 commit `b7054b6`)

Closes `done-means-verified-with-proof` (SYNTHESIS row #14, **Core
weight**) from `.scratch/harness-loop-audit-2026-06-12/SYNTHESIS.md`.
Promotes the row from `Partial` to `Present` — "Done" now means
"verified with proof from this session, not merely 'written'."

- `METHODOLOGY.md:69-75` — Rule 4 "Goal-Driven Execution" gets an
  explicit "Independent proof" sub-rule: a task is not done until
  it carries its own verification artifact (test result, exit
  code, fresh-context adversarial pass). Never the implementer
  agreeing with their own work.
- `skills/ship-change/reference.md:69-93` — Phase 5 "Verify + Merge"
  promoted proof collection to a **blocking gate** (was previously
  optional). The runner collects proof artifacts, asserts they
  exist, and refuses to advance the task to "merged" without them.
- `skills/review-pr/SKILL.md:160-162` — `[verification-gap]` tag
  enforcement: PRs claiming completion without a proof artifact
  get a `must-fix` flag in the review output.
- `commands/pre-ship-verify.md` (122 lines) — deterministic runner
  that materializes the proof requirement: runs the `ACCEPTANCE.md`
  contract + eval-harness gate, emits a single PASS/FAIL signal.
  Wired into `/review-pr` Phase 6 and `/ship-merge` Phase 1.
- Verification: `pre-ship-verify` exercises a known-good and a
  known-bad acceptance contract; `[verification-gap]` triggers on
  the bad one.
- Promotes SYNTHESIS row #14 from `Partial` → `Present` (Core
  weight — highest-leverage of the 3 reclassifications in the
  re-audit; audit re-baselined in `SYNTHESIS-REAUDIT.md`).

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
- **F7 test coverage (+9 cases) in `tests/hooks/runners/test-critical-hooks.sh`** — F7a
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
- `bash tests/hooks/runners/test-critical-hooks.sh` → 201/0 (no regression).

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
  `skills/harness-audit/scripts/audit.sh` check #32 + `tests/hooks/runners/test-critical-hooks.sh`
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
2. Unknown-`exit_reason` warning in `scripts/governance/governance-summary.py:271`.
3. "schedule" disambiguation late in `orchestrate/reference.md:12` vs `:40`.
4. 24 SKILL_MISSING skills lacking the 3 canonical sections
   (`## Input Contract` / `## Output Format` / `## Failure Modes`).
5. 3/5 honest exit reasons (`blocked` / `stalled` / `timeout`) still
   un-emitted in `verification-gate.sh:74-89`.
6. Issue #15 WARNING→block trade-off (closed at `39587ac` with Q3=a
   = validator=ask-gate, journaler=best-effort).

Green bar after this batch: 158/0 tests, audit `0C/0W/26I exit 0` (no new
findings, no new check firing), `claude plugin validate --strict .` ✔.

### Phase 2.3 — TaskCompleted opt-OUT escape hatch (SYNTHESIS #13, 1 commit)

Closes the opt-IN/OUT contract gap surfaced by SYNTHESIS row #13 (`stop/PostToolUse
enforcement option`). Operators may opt **out** of the F7 TaskCompleted test-claim
gate on a per-session basis by setting `KBG_ENFORCE_TASK_COMPLETED=0` — the
default is ON (preserves the 12 F7 tests in `tests/hooks/runners/test-critical-hooks.sh`).
This is **opt-OUT, not opt-IN**: the gate is a load-bearing safety check that
blocks test-claim-without-validation; the escape hatch is a documented way to
downgrade F7 to log-only for sessions where the operator trusts the teammate
chain to surface test-claim gaps another way. ADR 0002 L2/L3 boundary
preserved — the L2 default is the safety-checked one; the L3 mode is the
opt-out.

- `hooks/task-lifecycle.sh` — `ENFORCE_TASK_COMPLETED=1` default; flipped to
  `0` only when `KBG_ENFORCE_TASK_COMPLETED=0` is set. The TaskCompleted
  enforcement branch is now guarded by `[ "$ENFORCE_TASK_COMPLETED" = 1 ]`.
  Any other value (unset, "", "1", "false") keeps enforcement ON. Pure additive
  change — no behavior delta for sessions that don't set the env var.
- `eval/run-eval.py` — `hook-script` grader gains 3 fields:
  - `expected_exit_code` (int) — asserts on `result.returncode`
  - `expected_stderr` (list of substrings) — used for both positive
    ("stderr contains X") and negative ("stderr does not contain X") checks;
    the negation check runs first to avoid `contains` substring-routing
    ambiguity
  - `env` (dict) — env vars merged over `os.environ` for the hook invocation
- `eval/regressions/task-completed-enforcement.json` — new 2-eval regression
  fixture. Eval #1 verifies default-ON behavior (claim-without-validation →
  exit 2 + TASK-GATE stderr). Eval #2 verifies the escape hatch
  (`KBG_ENFORCE_TASK_COMPLETED=0` → exit 0, no TASK-GATE stderr). Both must
  pass; the pair guards both directions of the toggle.
- `METHODOLOGY.md:84-100` — Rule 4 "Goal-Driven Execution" gains a
  "TaskCompleted enforcement is opt-OUT, not opt-IN" sub-rule parallel to
  the existing "Comprehension debt ceiling" sub-rule. Names the asymmetry
  (ceiling = hard upper bound; enforcement toggle = default-on safety check)
  so future readers do not treat the two as the same shape.
- Verification: 202/0 critical-hooks tests pass (12 F7 tests + 190 others;
  no regression), `python3 eval/run-eval.py --regression --tag task-completed`
  2/2 pass, `python3 -c "import ast; ast.parse(...)"` on the modified
  `run-eval.py` clean, `claude plugin validate --strict .` not re-run
  (no plugin.json/marketplace.json/hooks.json deltas).
- **0 hook.json / settings.json / agent / skill changes** — escape hatch is
  pure env-var; no new surface to audit, no new selector wiring, no new
  schema-rot risk.

### Phase 2.4 — Coordination-as-Code: orchestrate-dispatch.py (SYNTHESIS #49, 1 commit)

Closes the "orchestration logic lives in markdown/context, not in
executable code" gap (SYNTHESIS row #49 / P2.4 / spec §4.5). The
dispatcher is the **deterministic rendering** half of the coordination
contract; the lead (`/team-build`, this skill) is the **judgment** half.
Without the dispatcher, the wave structure lives in the lead's model
memory — a context-clearing session restart loses the plan, a different
lead picks it up cold, and a 30-stage fan-out overshoots because the LLM
forgot the F8.5 cap mid-spawn. With the dispatcher, the spec is on disk,
the wave plan is machine-rendered, and a fresh session can resume from
the same plan file. **The model does judgment; the code does
coordination.** ADR 0002 boundary preserved: the dispatcher does NOT
spawn LLM agents; agent-typed stages are emitted as "would-spawn" lines
that the lead dispatches per the F9 template. Putting LLM dispatch
inside the dispatcher would be a covert L4 loop, which the autonomy
invariant forbids.

- `scripts/orchestrate-dispatch.py` — new. Reads a workflow spec
  (JSON or YAML), validates the schema (no cycles / no bad refs / no
  missing fields / no unknown stage types), resolves the DAG into
  waves, flags F8.5 fan-out overflow on top-level waves + parallel
  sub-fan-outs + loop body, and emits a plan. 5 exit codes: 0=PASS/PLAN,
  1=command-stage FAIL, 2=bad invocation, 3=parse error, 4=schema
  error (cycle/bad ref/missing field) — distinct so "schema broken"
  doesn't masquerade as "build broken" in CI. 4 stage types:
  `command` (subprocess.run, default), `agent` (would-spawn only),
  `parallel` (inline sub-stages), `loop` (loop_until + body). Three
  modes: default (human-readable plan), `--emit-plan` (machine-readable
  JSON for future `/team-build --spec`), `--execute` (runs `command`
  stages in wave order; agent stages reported only).
- `skills/orchestrate/examples/ship-merge.yml` — minimal "build → fan-out
  lint+typecheck → test → ship" workflow. 4 stages, 4 waves, exercises
  all 4 stage types. Use as the "hello world" example.
- `skills/orchestrate/examples/review-pr.yml` — multi-lens PR review
  pipeline. 3 stages, 3 waves; demonstrates the fan-in (4 parallel
  validators → merge-reports command) + fix-loop pattern from METHODOLOGY
  Rule 13's "judge panel" composition.
- `skills/orchestrate/examples/harness-audit.yml` — the harness's
  self-audit pipeline. 3 stages, 3 waves; uses the harness's own tools
  (`audit.sh` + `eval/run-eval.py`) so the spec itself is a smoke test
  for the dispatcher.
- `eval/run-eval.py` — new `script-cli` grader (~80 LOC, general-purpose
  "does this CLI behave correctly?" checker). Reads `command` /
  `expected_exit_code` / `timeout` from context; per-criterion routes
  on `rc=N` (anchored to avoid false-matching `rc=4` inside
  `stdout contains rc=4` literals) + `exits N` / `exit code N` /
  `returns N` + `stdout contains <literal>` + `stderr contains
  <literal>`. Anchored `^rc=` regex replaces the prior over-greedy
  `rc=|exits?` alternation, which would false-match the `rc=4` substring
  inside a contains-check criterion.
- `eval/regressions/orchestrate-dispatch-schema.json` — new 4-eval
  regression fixture. #1 `pycompile` + exists check; #2 ship-merge spec
  resolves to 4 waves / 4 stages / name=ship-merge; #3 cycle detection
  returns `rc=4` (NOT 0 or 1); #4 F8.5 warning surfaces on a 17-sub-
  stage parallel with `--max-per-wave 16`.
- `skills/orchestrate/SKILL.md` — new "Coordination-as-code" section
  (~30 lines) under the existing rule structure. Names the model/ code
  split explicitly, links the 3 example specs, and states the
  "dispatcher does NOT spawn agents" boundary (ADR 0002). The plan
  acceptance criteria said "≥3 example workflow specs in
  `skills/orchestrate/examples/`" + "SKILL.md references the dispatcher"
  — both delivered.
- `commands/team-build.md` — Step 5 gains an "Optional `--spec`
  shortcut" note pointing to the dispatcher's `--emit-plan` as the
  future consumer path. v1 of `/team-build` still expects the
  hand-written plan file; the note is the future-work wiring without
  a hidden dependency.
- Verification: 4/4 new regression evals pass, all 3 example specs
  render cleanly (4/3/3 wave counts as designed), 5/5 error paths
  return the right exit codes (missing/empty → 2, cycle → 4, unknown
  ref → 4, unknown type → 4, missing command → 4), F8.5 cap surfaces
  warnings on a 30-parallel spec (default 16) and on a 17-parallel
  with `--max-per-wave 5`. Pre-existing failures (harness-audit-missing-
  symlink, harness-audit-eval-freshness, review-pr-acceptance-cross-check,
  ship-change-acceptance-exists, ship-change-no-contract) unchanged
  (verified by `git stash` + re-run: 10 fails before, 6 fails after my
  changes — 4 new passing tests, 0 new failures). `bash skills/harness-
  audit/scripts/audit.sh .` exits 0 (0C / 0W / 26I, no new findings
  from the dispatcher or examples).

### Phase 2.5 — Auth / MCP / Plugin Health Probe (SYNTHESIS #38)

Closes the "expired tokens surface as 'the agent is stupid today'" gap
(SYNTHESIS row #38 / P2.5 / spec §4.2). The script gives the operator
a single command that probes the auth/MCP/plugin surface and returns
a structured verdict with concrete remediation, BEFORE the session
spends tokens discovering the failure mid-task.

#### Added

- `scripts/auth-health-check.py` — new (~470 LOC). Probes 3 surfaces and
  aggregates a 3-state verdict:
  1. **GitHub CLI auth** (`gh auth status`) — healthy when `gh` returns
     0; degraded when rc≠0 BUT a `GITHUB_TOKEN`/`GH_TOKEN` env var is
     set (keyring may be stale, recoverable); broken when rc≠0 AND no
     env token (operator must `gh auth login` before any gh work).
     Includes explicit `FileNotFoundError` and `TimeoutExpired` handling
     for the "gh hangs on a network call" failure mode.
  2. **MCP server reachability** (stdio + HTTP/SSE). Reads
     `~/.claude/settings.json` (global) and `.mcp.json` (project-local),
     probes each: stdio servers get `<command> <args> --help` with a
     timeout (binary-exists-and-runs is the reachability signal, exit
     code is ignored); HTTP/SSE servers get a raw `socket.connect()`
     probe. `not_applicable` is reported when NO MCP servers are
     configured (distinct from `healthy` — the absence of MCP config
     is a fact, not a positive health signal).
  3. **Plugin cache validity**. Walks `~/.claude/plugins/installed_plugins.json`
     (version-2 shape: `{"plugins": {"<plugin>@<marketplace>": [...]}}`),
     verifies each `installPath/.claude-plugin/plugin.json` exists,
     parses, and matches the version + name from the manifest. Healthy
     when all match; degraded when a manifest is missing/empty
     (recoverable via `claude plugin update`); broken when installPath
     doesn't exist or the manifest is malformed.

  3-state exit contract: `0=healthy`, `1=degraded` (remediation
  optional, work can continue), `2=broken` (remediation required,
  work should pause). Distinct from `run-acceptance.py`'s 5-code
  contract (acceptance runs test-shaped code, auth-health runs
  state-shaped probes). Supports `--json` for hook consumption,
  `--no-{gh,mcp,plugins}` for partial runs, custom `--mcp-timeout`
  and `--gh-timeout`. The script's docstring covers the wiring
  pattern for a SessionStart hook (`session-load.sh` enhancement or
  a new `hooks/auth-bootstrap.sh`) but does NOT modify the hook
  layer — that's P3 (defer documentation) territory.

- `eval/regressions/auth-health.json` — new 2-eval regression fixture:
  1. `auth-health-script-pycompiles` — `py_compile` + `ls` smoke test.
  2. `auth-health-exit-code-2-on-broken-plugin` — sets `HOME` to an
     isolated temp dir with a fake plugin manifest pointing at a
     non-existent install path, runs the script with `--no-gh --no-mcp
     --json`, asserts `rc=2` AND `contains_path_error=True` (the
     specific "install path does not exist" message surfaces).

#### Verification

- Script runs cleanly against the current repo: `gh_auth=healthy`,
  `mcp_servers=not_applicable` (no MCP configured), `plugin_cache=
  degraded` (12 installed plugins; 2 healthy, 10 degraded — most of
  the degraded entries are real-but-cosmetic: the `claude-plugins-
  official` marketplace ships with `version: "unknown"` and the
  `qmd` plugin's manifest is one level deeper than the default
  location; this is operator state, not a script bug).
- 2/2 new regression evals pass.
- The full eval suite: 24 total, 15 passed, 6 failed, 3 skipped.
  The 6 pre-existing failures (`harness-audit-missing-symlink`,
  `harness-audit-eval-freshness`, `review-pr-acceptance-cross-check`,
  `ship-change-acceptance-exists`, `ship-change-no-contract`,
  `loop-overshoot-workflow-cap`) are unchanged from P2.4.
- Pyright diagnostic that flagged `socket` as possibly-unbound (the
  previous in-function `import socket` pattern) is fixed by moving
  the import to module level alongside the other stdlib imports.
- BOUNDARY.md unchanged (script additions don't change routable
  surfaces: still 27 skills / 11 commands / 27 agents / 38 hooks).
- Autonomy invariant (ADR 0002) preserved: the script is a SENSOR
  that returns a verdict; it does not auto-fix, auto-mutate, or
  block session start. The CALLER (a hook, `/pre-ship-verify`, or
  the operator) decides what to do with the verdict.

### Phase 3 — Defer documentation + ADR 0002 addendum (2026-06-12, 2 commits)

Captures the **why** behind the 10 SYNTHESIS items that will never ship
as their own components (L3/L4 territory, vendor primitives, or
ADR 0002 collisions), and what the L2 alternative is for each. The
addendum is the **one-stop reference** for "why is X absent?" so the
next audit doesn't waste cycles re-debating decided-closed decisions.

#### Added

- `docs/adr/0002-addendum-deferred-items.md` — new ADR addendum mapping
  10 SYNTHESIS rows to their shipped L2 alternatives:
  - **#5** `goal-primitive-stop-condition` → `ACCEPTANCE.md` stop-condition contract
  - **#21** `machine-readable-feature-list` → `docs/agents/verification-trail.md` schema
  - **#32** `worktree-isolation-parallel-agents` → F8.5 bounded-fan-out in `commands/team-build.md` + per-wave contract chain in `skills/orchestrate/SKILL.md`
  - **#34** `typed-tool-registry` → agent `tools:` frontmatter allowlists
  - **#35** `mcp-connectors-act-in-real-tools` → `hooks/db-write-gate.sh` for the one plugin-owned path
  - **#40** `loop-edits-own-shape-as-data` → `recursive-improve` skill (human-gated single-cycle)
  - **#44** `minimize-tool-surface` → agent `tools:` allowlists (host can't shrink at plugin layer)
  - **#45** `build-to-delete-thin-harness` → `docs/harness-decay-cadence.md` quarterly review
  - **#47** `durable-checkpointed-state-recovery` → `.scratch/<slug>/` journaled events (session-scoped by design)
  - **#50** `self-improving-harness-via-prs` → `recursive-improve` skill (proposal-then-ASK-then-act)

  Rationale for the addendum (vs a section in ADR 0002): ADR 0002 is
  the canonical invariant record (don't dilute the "judgment preservation"
  thesis); the addendum is the derived mapping (changes over time);
  cross-link is unidirectional (ADR 0002 → addendum).

- `.scratch/harness-loop-audit-2026-06-12/GAP-CLOSURE-SPEC.md` — added
  inline `> AUTONOMY-DEFER` / `> VENDOR-DEFER` callouts at the 3 spec
  sections where the defer items land (#5, #32, #46), pointing to the
  addendum. Inline callouts survive the spec becoming the source of
  truth in a future round.

- `docs/adr/README.md` — added index row for the addendum (Accepted
  status, 2026-06-12 date).

### Phase 5 — Onboarding integration + closure milestone (2026-06-12, 1 commit)

Closes the 2026-06-12 loop-engineering closure work. P4 (SYNTHESIS
re-baseline) is intentionally a local-only update: `.scratch/`
is gitignored per `.gitignore:13`, so the audit artifact is
operator-local; the shipped state is reflected in the docs
(addendum + onboarding + this entry), not in the audit table on
the remote.

#### Added

- `docs/onboarding.md` — new section **"What we've shipped recently
  (2026-06-12)"** with a 7-line quick map of the closure work (the
  components most likely to be the answer to "where do I find X?").
  File size: 442 words ≈ 580 tokens (was 380 words ≈ 500 tokens; the
  new section adds ~60 words, well under the 1-commit budget).

- `README.md` — Documentation index gets 1 new entry:
  `docs/adr/0002-addendum-deferred-items.md`. The 2-entry delta in
  the P5 plan became a 1-entry delta because `docs/onboarding.md`
  was already indexed in P1.3 (line 87).

#### Verification (closure milestone, 2026-06-12)

- **`harness-audit`** (formal plugin audit, the closest thing to a
  pre-ship gate when there's no task-scoped `ACCEPTANCE.md`):
  `0C / 1W / 26I exit 1`. The 1 warning is the pre-existing
  BOUNDARY.md-stale regen signal (operator state, not a code defect).
  The 26 info entries are pre-existing schema-rot notices
  (skills missing the `## Input Contract` / `## Output Format` /
  `## Failure Modes` canonical sections; doctrine drift tracked in
  the decay-cadence doc, not a regression).

- **`eval/run-eval.py`** (full suite, default datasets + 15 regression
  fixtures = 24 evals):
  `16 passed / 5 failed / 3 warning / 0 regressions / 3 skipped-summary`.
  The 5 failed and 3 warning are unchanged from P2.5 (pre-existing
  gaps: `harness-audit-eval-freshness`, `review-pr-acceptance-cross-check`,
  `ship-change-acceptance-exists`, `ship-change-no-contract`,
  `loop-overshoot-workflow-cap`, plus the 3 route-by-aspect/tier/blocks
  warnings). The 2 new `auth-health-*` regression evals pass.

- **SYNTHESIS audit (re-baselined, 50 items)**:
  `17 Present / 18 Partial / 3 Deferred / 10 Absent / 2 Vendor-only`
  (was `7 / 29 / 0 / 11 / 2` on 2026-06-11). Honest assessment: ~34%
  present, ~36% partial, ~20% absent, ~4% vendor-only, plus 3 deferred
  per the addendum. The 3-deferred status is new (was folded into
  Partial before); the 10 promotions (Partial → Present) are
  #11, #13, #15, #22, #24, #33, #38, #39, #41, #49.

- **ADR 0002 addendum conformance**: `claude plugin validate --strict .`
  passes (doc-only change, not manifest-affecting).

- **Autonomy invariant (ADR 0002) preserved throughout**:
  - P2.3 `KBG_ENFORCE_TASK_COMPLETED` is opt-OUT (default ON, breaks
    nothing), not opt-IN (would require amendment).
  - P2.5 `auth-health-check.py` is a sensor; it does not auto-block
    session start. The CALLER decides.
  - P3 defer documentation is descriptive, not enforcement; the
    enforcement is the invariant itself + audit check #32
    (recursive-improve `disable-model-invocation`).

### Audit summary (2026-06-12 closure epic)

| Phase | Work | Commit count | Status |
|---|---|---|---|
| P0 | SYNTHESIS re-baseline (#33, #42 already-shipped reclass) | (audit-only) | done |
| P1.1 | #15 anti-cheat: split `run-acceptance.py` exit codes | 1 | done |
| P1.2 | #22 learning memory: `audit-to-memory.py` + `memory-lint` | 1 | done |
| P1.3 | #24 onboarding: `docs/onboarding.md` (10-min cold-start) | 1 | done |
| P1.4 | #33 lift to PRESENT: METHODOLOGY Rule 7 cite usage-monitor | 1 | done |
| P1.5 | #39 regression lock: 2nd + 3rd regression fixtures | 1 | done |
| P2.1 | #11 stall detection: loop-status → observe step | 1 | done |
| P2.2 | #41 comprehension-debt ceiling: debt-count ledger | 1 | done |
| P2.3 | #13 `KBG_ENFORCE_TASK_COMPLETED` opt-OUT escape hatch | 1 | done |
| P2.4 | #49 coordination-as-code: `orchestrate-dispatch.py` + 3 specs | 1 | done |
| P2.5 | #38 auth/MCP/plugin health probe (`auth-health-check.py` + 2 evals) | 1 | done |
| P3 | Defer docs: 3 spec callouts + ADR 0002 addendum | 1 | done |
| P4 | SYNTHESIS re-baseline (local, `.scratch/` gitignored) | (local-only) | done |
| P5 | Onboarding integration + closure milestone (this entry) | 1 | done |
| **Total** | **13 commits + 1 local-only audit update** | **14** | **done** |

The 13-commit delta is small for the surface area covered because most
work is config + doc + script (no large refactors; no new agents or
skills added in P2.x — they re-use the existing `recursive-improve`
and `orchestrate` skills as the seam for new discipline).

## [0.1.3] — 2026-06-12

### Changed

- **Cache-invalidation bump** (0.1.2 → 0.1.3) to ship `/pre-ship-verify`.

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

## [0.1.1] — 2026-06-11

### Fixed

- **Bumped skill count 25 → 26** + version 0.1.0 → 0.1.1.

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
