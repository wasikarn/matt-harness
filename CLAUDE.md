# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Validation (run before committing)

```bash
claude plugin validate . --strict
```

Plugin manifest is the primary validation gate. `scripts/run-gauntlet.sh` runs plugin-validate + full shell-lint + JSON lint + harness-audit + the hook behavioral suite (`hooks/tests/test-gates.sh` + `test-flow-nudge.sh` + `test-session-stop.sh` — deny-gate + advisory-sensor + session/stop-hook unit tests) in parallel. The broader fleet critical-hooks suite and the eval dataset gate are pending rebuild.

## Adding or removing a surface

Auto-discovered directories: `agents/`, `skills/`, `commands/`, `hooks/`, `output-styles/`, `themes/`. See `skills/add-surface/SKILL.md` for the step-by-step (manifest bump, validation, BOUNDARY.md regen).

## Git hooks

Hooks live in `git-hooks/` (not `.git/hooks/`). Wire once per clone:

```bash
git config core.hooksPath git-hooks
```

pre-commit: fast gate — syntax/lint (`bash -n` + shellcheck), JSON validation, CRITICAL harness-audit (graceful-skip if absent).
pre-push: full gauntlet (all validation layers in parallel).

## Composer-not-creator doctrine

Before writing a new skill, command, or agent from scratch, check sources in this order: **(1)**
`mattpocock/skills` first — `claude plugin list` / the Skill tool's own available-skills list for
what's already installed under the `mattpocock-skills` plugin, plus the local clone at
`/Users/kobig/Codes/Personals/mattpocock-skills` for what's upstream-available but not yet
installed. This is a **Matt-Pocock-first harness** (his skills installed as the
`mattpocock-skills@mattpocock` plugin, namespaced `mattpocock-skills:<name>` — see README.md Quick
Start; migrated off the earlier unnamespaced `gh skill` installs 2026-07-17); checking
ECC/superpowers before matt's own repo gets the priority backwards. **(2)** the upstream ECC repo
at `/Users/kobig/Codes/Personals/ECC` and
the vendored superpowers checkout at `/Users/kobig/Codes/Personals/superpowers`. **(3)** sibling
harnesses under `/Users/kobig/Codes/Personals/` worth a structural-pattern check even when they're
not kbg's primary composer sources (e.g. `oh-my-claudecode` — cherry-picked before, ask if
unsure which repos currently qualify). Cherry-pick and adapt from whichever source fits; create
kbg-native surfaces only when none do. Confirmed gap (2026-07-17): `code-implementer`/`/implement`
were built checking only (2), skipping (1) — collided with matt's own `engineering/implement`
skill, caught by the user, not by this checklist. (A hand-pinned HEAD hash is structurally doomed
to re-stale; the path is the stable anchor — run `git rev-parse HEAD` there when you need the
current commit.)

## Architecture

The plugin ships as `kbg@kobig` from the `wasikarn/kbg-harness` GitHub repo. Claude Code loads all surfaces from `~/.claude/plugins/cache/kobig/kbg/<version>/` at startup. Nothing is symlinked.

**Doctrine injection:** `hooks/session/doctrine-bootstrap.sh` fires on SessionStart and injects `docs/METHODOLOGY.md` (decision-sizing triad + reasoning scaffold) into session context via `$CLAUDE_PLUGIN_ROOT` (the plugin install dir; the older `$CLAUDE_PLUGIN_DIR` name is not a real CC variable and expands empty).

**Operating model:** deny the irrecoverable set computationally (gates in `hooks/gates/`), advise on the rest (sensors in `hooks/advisory/`). Advisory sensors never emit `permissionDecision`. The L2–L5 autonomy ladder is retired.

**Why — the unifying crux:** the gate is a *verifier* (deterministic shell returning a branchable **score**), the model is the *maker*, and the maker can never grade its own work — an LLM judging its own output is circular ("two optimists agreeing"). So advisory sensors journal but never gate, and the autonomy ladder had to retire: a model-as-gate is the maker appointing its own verifier. **Score, not feel** — every loop's stop condition must be a number a deterministic gate can branch on, never a vibe the model rationalizes. (This is the agent-loop verifier-separation principle; see `docs/research/` + the retired L2–L5 build for the proven failure it prevents.)

When hooks are wired: gates/ (deny), advisory/ (journal), session/ (inject), stop/ (cost tracking).

## Skill authoring doctrine (matt-pocock)

When creating or editing a skill under `skills/`, follow matt-pocock's `writing-great-skills` doctrine — canonical: the `mattpocock-skills:writing-great-skills` skill (installed as the `mattpocock-skills` plugin, not vendored in this repo since v0.46.0 — see README.md Quick Start; leading word, ≤25-word description, completion criterion, no-op test, two-cuts, failure-mode guard).

The `docs/skill-template/SKILL.md` template carries this checklist as a `## Design checks` section — but `harness-audit` check 36 does **not** check for that heading's presence. It checks 4 of the 6 doctrine elements via INFO-only regex proxies against each skill's live description/body (leading-word vocabulary, ≤25-word count, completion-criterion phrasing, a no-op-test line-count heuristic); "two-cuts" and "failure-mode guard" have no shell check — a failure-mode regex proxy was tried and retired 2026-07-16 (vacuous before a reset-bug fix, 5/5 false-positive after: every flagged skill already named its failure mode in a prose section or bullet list the numbered-window proxy couldn't see). INFO findings never fail the gate. Confirmed 2026-07-22: only 2/35 native skills (`pr`, `task-prep`) actually carry a `## Design checks` section — the template's checklist is documentation, not an enforced requirement.

**Named Model footers:** a skill/command/agent that makes load-bearing reasoning/judgment choices may end with a `## Named Model` footer citing cc-thinking-skills lenses. Apply the 3-condition rubric from `memory/mental-models-sweep-v0302-2026-07-03.md`: (1) load-bearing reasoning gap, (2) name-a-lens benefit for the operator, (3) honesty posture preserved (footer is a scaffold + catalog pointer, never "this lens proves correctness"). The curated catalog is `docs/reference/reasoning-models.md`; the 39 raw models live under `docs/reference/thinking-skills/skills/`.

**Suggested next step footers:** a workflow surface (command or workflow skill run as a discrete step) may end its Output/Summary phase with a `Suggested next step:` marker — outcome-branched (`situation → action`), citing skills as `kbg:<name>` and commands as `/<name>`. Skills are ALWAYS cited `kbg:`-form (never `/name`) — get this right at authoring time: `harness-audit` check 40 only catches rename/deletion drift on refs already in `kbg:` form, it does **not** scan for a skill mis-cited in slash form (confirmed: this exact bug shipped twice — `commands/pr.md` and `diagnosing-bugs/SKILL.md` both cited a skill as `/name` undetected until a manual survey caught it, v0.35.0). Passive suggestion only — never "invoke X now" / auto-chain (that collides with the no-model-self-start doctrine). Skip self-contained reference/pattern/catalog surfaces (a forced footer there is the retired canonical-sections ceremony, 2026-06-16) and terminal workflows (post-mortem, ship-release terminus).

**Escalation to `AskUserQuestion`:** a branch belongs in the passive footer only while it's anticipatory — conditional on a fact not yet known (did the reviewer comment, did CI go red). If every branch is already true/decidable right now and there's no sensible default, that's a present-tense fork, not a suggestion — surface it via `AskUserQuestion` (per `output-styles/staff-eng.md`'s decision-question rule: one-line consequence per option) instead of text the user might not read. Model: obra/superpowers' `finishing-a-development-branch` skill, which ends by presenting exactly N concrete options (merge/PR/keep/discard) and blocking for the pick — not superpowers' separate (and rejected) `using-superpowers` auto-chain directive. None of kbg's shipped footers (v0.35.0/.1) currently qualify — they're all anticipatory-conditional — so this is a criterion for future surfaces, not a rewrite of what shipped.

## Branching model

Single branch: `develop` only. No feature branches. Commit and push direct.

**Computationally enforced** by `gate:worktree:develop-only` (`WorktreeCreate` event) and the `git worktree add -b` block in `gate:bash:irrecoverable` (`PreToolUse:Bash`). Both gates are opt-in per repo via the `/.kbg-no-worktree` sentinel — present in the kbg-harness repo, absent from tathep/ECC/scratch repos (which keep their existing `gate:write:worktree-guard` redirect). Detached `review-pr-<N>` worktrees in `$TMPDIR` are explicitly allowlisted so the Phase 2 PR-by-number review path keeps working.

## Non-obvious gotchas

Grouped by behavior area (not a flat bucket — find the group first, then the line).

### Repo & commit hygiene

- **Hardcoded home paths blocked:** `.sh`/`.py` files must use `$HOME` or `~`, never `/Users/<name>`. The pre-commit gate will reject the commit.
- **Never `rm -rf`:** use `trash` for deletions.
- **Never `--no-verify`** on commits or pushes.
- **Stage by name:** never `git add -A` or `git add .`.

### Plugin lifecycle & install

- **`defaultEnabled: false`:** plugin ships disabled. After install, add `"kbg@kobig": true` to Claude Code `settings.json`, then restart.
- **Cache-invalidation:** same-version edits are no-ops. Always bump both manifests before `claude plugin update`. CLAUDE.md-only edits skip the bump — it's dev-facing repo guidance, not cached plugin content (only `agents/`/`skills/`/`commands/`/`hooks/`/`output-styles/`/`themes/` ship per-version).
- **`BOUNDARY.md` regen:** the script writes to STDOUT, not the file. The `> BOUNDARY.md` redirect is required every time.
- **Output style:** `output-styles/staff-eng.md` is the sole live-response register — self-calibrates terse vs full decision-framing by stakes, not by switching files (the old `senior-eng.md`/`staff-eng.md` two-file split was collapsed 2026-07-02; the internal "Calibrate to stakes" rule replaces the escalation/fallback dance). `force-for-plugin: true` auto-activates it whenever `kbg@kobig` is enabled, overriding the user's own `outputStyle` setting — no `/output-style` selection needed, but it also means you can't run a different style while this plugin is on without disabling it first.

### Session environment quirks

- **Working frames:** `contexts/` holds `dev.md`, `review.md`, `research.md` — loaded by `/frame` to set session posture.
- **`grep` is aliased** to `rtk grep` in this environment. Use `/usr/bin/grep` or `awk` for count/stat operations.

### Skill/agent/command mechanics & routing

- **Skill descriptions load on every Task spawn** (~words×1.3 tokens). Keep descriptions ≤25 words.
- **Thinking models:** default is the triad + `advisor()` inline (METHODOLOGY Rule 1) — `kbg:decide` is on-demand only, for genuinely hard/contested-diagnosis choices (de-scoped 2026-07-02, v0.21.4: 0 real-world invocations vs 55 `advisor()` calls across 182 sessions). The 39 on-demand mental-model files live in `docs/reference/thinking-skills/skills/` (never move to `skills/` — would break fleet count).
- **`disable-model-invocation: true`:** carried by 2 skills currently — `recursive-improve` and `score-decision` (re-check via `grep -rl "disable-model-invocation: true" skills/*/SKILL.md`; the count drifted hard after v0.46.0 moved 17 flag-carrying matt-origin skills out of this repo, and nobody updated this line). Both are now **CRIT**-guarded against the flag being silently dropped: `recursive-improve/SKILL.md` by check 39, `score-decision/SKILL.md` by check 49 (added 2026-07-23 after a `kbg:plan-reviewer` pass on a skill-improvement batch plan flagged that skill-creator's own description-optimizer rewrites SKILL.md frontmatter, and only recursive-improve had a real gate). Check 30 still only WARNs that a `-reason` field exists on whichever skills currently carry the flag — it's the presence-of-reason check, not the flag-survives-a-rewrite check; the two CRIT checks above are what actually close that gap now.
- **`review_mode` in `ship-merge`:** `review-pr` tags its state write `pr-by-number` (isolated worktree) or `own-branch` (self-review). `ship-merge` caps the Critical-findings score at the fatal-weakness floor on sensitive-path diffs reviewed `own-branch` — an automation-bias guard against trusting a same-session self-review's severity tiering. "Sensitive-path" covers both auth/secret/credential/payment/billing/token AND the harness's own verifier/gate code (`hooks/gates/**`, `hooks/hooks.json`, `skills/harness-audit/scripts/{audit.sh,checks/**}` — the same list `hooks/gates/verifier-protect.sh` protects).
- **`orchestrate` vs `kbg:decide`:** orchestrate decides whether/how to spend effort on an ask (inline/parallel/sequential/drop, which surface receives it) *before* it's understood as a bounded decision; `decide` reasons through a bounded question once you're already committed to answering it. A pile of competing asks routes through `orchestrate` first; a single reversible-choice question goes straight to `decide`.
- **`SKILL.md` frontmatter ≠ `agents/*.md` frontmatter:** the real skill-file field for tool control is `allowed-tools` (pre-approves without asking; there's no hard-restriction field for skills), not `tools:` — that's the `agents/*.md` subagent field (hard-restricts to a fixed set). Confirmed against the official 16-field `skills.md` reference and the shipped CLI binary's own compiled schema key list. `metadata` / `metadata.origin` / `disable-model-invocation-reason` are non-standard-but-harmless kbg conventions — Claude Code tolerates unrecognized frontmatter keys (confirmed via changelog + `plugin.json`'s own documented "unrecognized fields → warning, not error" policy), they just carry zero behavioral effect.
- **`/goal` vs `goal-craft`:** `/goal` is Claude Code's own native completion-condition loop (v2.1.139+, session-scoped, judged each turn by a separate small model that reads only the transcript). kbg never wraps or auto-invokes `/goal` itself — the user always types `/goal` themselves, no exceptions. `skills/goal-craft/SKILL.md` only composes a paste-ready condition string (mandatory one-way-door screen + turn bound) and, as of 2026-07-08, is model-invocable (its `disable-model-invocation` flag was removed on user request) — the model may draft a condition unprompted, but the string is inert until the user pastes it after `/goal`. Auto-dispatch of `/goal` itself (`claude -p "/goal ..."`) is still a deliberate non-goal — it forks a separate headless session and reopens the retired L4/L5 "no model self-start" invariant.

## Recent versions

Quick orientation for the last few releases. For full notes see `CHANGELOG.md`.

Cap this list at 10 bullets. Keep the last 3-5 releases as individual entries; fold older ones into version-range bullets (`vX.Y.a–vX.Y.b` or `vX.Y.x`) by theme. Adding an 11th bullet means dropping the oldest — `CHANGELOG.md` is the full record, this section is orientation only.

- **v0.68.23** — `/kbg:compliance-audit` on the skill-improvement marathon (`docs/plans/skill-improvement-batches.md` vs. its shipped diff). 5 fresh-context verifiers, 26 requirements, all CONFORM. One real fix required by the audit's own adversarial-completeness mandate: checks 39/49 (the CRIT guards on `recursive-improve`'s/`score-decision`'s `disable-model-invocation: true` flag) used a raw substring grep instead of a frontmatter-scoped lookup — a verifier built a fixture where the real key is absent but the literal string appears in `description:` prose, and the old check stayed silent instead of firing CRIT. Fixed both to use the existing `fm_get` helper; added a regression fixture proving the fix (`test-harness-audit.sh` now 7/7). Also fixed a stale `1..48` comment in `audit.sh`.
- **v0.68.22** — Second context7 currency-check pass, closing the honesty gap v0.68.21 left open: checked the remaining 10 not-yet-verified pattern skills. Found one real drift: `dart-flutter-patterns`' Freezed example used the bare `class User with _$User` form; Freezed 3.x (confirmed 3.2.5 is genuinely pub.dev's current stable, not an RC) requires `abstract`/`sealed` on the class, so the bare form no longer compiles. Fixed the example + added a one-line note. This skill has no `tathep_projects` pin, so context7+pub.dev was the only verification path. The other 9 (`drizzle-patterns`, `hono-patterns`, `fastapi-patterns`, `backend-patterns`, `mysql-patterns`, `cost-aware-llm-pipeline`, `grpc-node-patterns`, `langchain-langgraph-patterns`, `latency-critical-systems`) verified clean — notably `drizzle-patterns`' `relations()` reconfirmed correct (still npm `latest`) and `langchain-langgraph-patterns`' HITL section already uses the current `interrupt()`/`Command()` pattern. All 13 of 13 pattern-tier skills are now checked against real, current docs, not just reread against training knowledge.
- **v0.68.21** — Post-plan follow-up on the skill-improvement marathon, prompted by `advisor()` before declaring it done: the pattern-tier "currency check" the plan's own recipe named (verify against context7/real docs) never actually ran during C1–C3 — each skill was reread against training knowledge instead, which is the maker grading its own work. Ran it for real against the 3 highest-drift candidates. Found one genuine gap: `adonisjs-patterns`' "VineJS Validation" section taught `@vinejs/vine`, but neither real target repo (both pinned `@adonisjs/core@^5.9.0`) has it installed — both use the legacy built-in `@ioc:Adonis/Core/Validator`, confirmed by grepping real `app/Validators/*.ts` files. VineJS is a v6+ default, not a v5 drop-in. Fixed the section + description keyword. `effect-ts-patterns`/`tauri-v2-patterns` verified clean against context7 and real pinned versions — no drift. Also confirmed `` `mattpocock-skills:tdd` `` (flagged as possibly-dead) is a real, resolvable skill, closing the advisor's second item. Honestly scoped: only 3 of the pattern tier's 13 skills got the real check; the other 10 (including 7 the plan's own currency-check step nominally covered) remain unverified against context7, documented as such rather than implied done.
- **v0.68.20** — Batch C3, final batch — closes the entire skill-improvement plan (10 batches: 0, A1, A1b, A2, A3, A3-fmt, B1, B2, B3, C1, C2, C3): `drizzle-patterns`, `hono-patterns`, `adonisjs-patterns`, `fastapi-patterns`, `latency-critical-systems`, `cost-aware-llm-pipeline`. `latency-critical-systems` already had its completion criterion from A3-fmt; the first 4 of the remaining 5 were already doctrine-complete with no cross-reference surface. `cost-aware-llm-pipeline` cited a dead `claude-api` skill twice (doesn't exist anywhere in this fleet or any installed plugin) — fixed both to point at a real source. Across the whole marathon: 5 malformed-completion-criterion-heading fixes, 3 missing-doctrine-element additions, 1 prose trim, 1 stale-line-number fix, 7 dead-reference fixes, and the description-budget pre-pass. Modal outcome throughout: "reviewed, no change" — most of the fleet was already doctrine-complete.
- **v0.68.19** — Batch C1, first pattern-tier batch: `dart-flutter-patterns`, `backend-patterns`, `mysql-patterns`. Lightest pass, continued autonomously. `dart-flutter-patterns` matched the "missing both" gap ranking — genuinely had no `## Verify before use` section; added it plus fixed 2 dead references (`flutter-dart-code-review` → real `flutter-reviewer` agent; a nonexistent `rules/dart/` path, removed). `backend-patterns`/`mysql-patterns` were already doctrine-complete; both had the same dead `` `security-review` `` reference (real target: `kbg:security-auditor`) — 3rd fix of that exact reference this plan (1st: `production-audit`, A2). Fleet-wide grep confirmed no remaining instances after the 3rd fix.
- **v0.68.18** — Batch B3, closing the utility/meta tier (B1+B2+B3): `agent-architecture-audit`, `eval-harness`, `goal-craft`, `learn`, `recursive-improve`. Light pass, continued autonomously. All 5 matched the plan's catalogue (none gap-listed); reread confirmed 4 of 5 accurately (each already has completion-criterion/failure-mode content, sometimes under a differently-named but equivalent heading — `eval-harness`'s anti-patterns section, `goal-craft`'s per-step pairs, `learn`'s "Filter hard" step, `recursive-improve`'s explicit `## Failure Modes to Avoid`). `agent-architecture-audit` was the one real gap: had a failure-mode guardrail but no completion criterion at all — added one grounded in the file's own finding-format/code-first-fix content.
- **v0.68.17** — Batch B1 (`add-surface`, `harness-audit`, `memory-lint`), first utility/meta-tier batch (light pass: name the gap, draft the fix, skip the paired benchmark), continued autonomously per the session goal. Scope guard honored: `harness-audit`'s fix stayed to `SKILL.md` prose only, no new check script. `add-surface`/`harness-audit`: both genuinely missing a completion criterion and failure-mode section entirely — dense reference-table bodies with no "done when"/"what goes wrong" content at all. Added both, grounded in mechanics each file already documents (version-bump no-op semantics, plugin-cache auto-detection, exit-code-as-finding-count). `memory-lint`: already had both elements' substance, just scattered inline (a drift-to-apply warning buried in `--trim`, a slug-vs-filename note, the links-are-memory-only rule) — consolidated into one `## Failure modes` section restating existing content; no completion criterion added since `exit code = finding count; 0 = clean` already covers it for a deterministic linter.
- **v0.68.16** — Fleet-wide completion-criterion format pass, spun out of A3 and tracked as its own version per `advisor()` (13 of 14 candidates belong to later batches B2/C3 — bundling into A3's commit would misrepresent what A3 touched). `codebase-onboarding`'s defect (v0.68.15) matching `decide`'s (A1) raised the question of whether it was systemic; a coarse grep across all 35 skills surfaced 14 candidates, each read individually before any fix per `advisor()`'s caution that the grep only proves "a line starting with `1.` near EOF." Result: 3 genuine defects (`context-budget`, `inventory`, `latency-critical-systems` — orphaned `1.` item, no heading, glued onto an unrelated prior section) fixed the same way as `decide`; 10 false positives (the pattern-skill cohort sharing a deliberate `## Verify before use` template) left untouched. Pure formatting fix, content unchanged. Batch table reconciled so B2/C3 don't re-discover this.
- **v0.68.15** — Batch A3 (`codebase-onboarding`, `score-decision`, `tech-humanize`), continuing under the session goal without re-asking per batch. `score-decision`/`tech-humanize`: reviewed, no change — both already carry explicit completion criteria and failure-mode guards. `codebase-onboarding`: found the same structural defect `decide` had in A1 — a trailing orphaned `1.` list item glued onto "### Example 3" with no heading — fixed by promoting into `## Completion criterion`, content unchanged. This finding is what prompted the fleet-wide sweep in v0.68.16.
- **v0.68.14** — Batch A2 (`pr`, `incident`, `security-auditor`, `production-audit`), continuing under the user's session goal ("do every batch until finished and correct") without re-asking per batch. `pr`/`incident`/`security-auditor`: reviewed, no change — all already carry explicit completion criteria (`pr` has its own `## Design checks` section, 1 of only 2 native skills that do). `production-audit`: found 2 real dead references — `` `security-review` `` matches neither `security-auditor` (skill) nor `security-reviewer` (agent), and `` `tdd` `` is missing its `mattpocock-skills:` prefix — both invisible to check 40's dead-`kbg:`-reference detector because neither was written in `kbg:`-prefixed form. Fixed both, converted to prefixed form so future drift is visible to the existing check.
Older releases: see `CHANGELOG.md` for the full record.
