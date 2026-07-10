# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Validation (run before committing)

```bash
claude plugin validate --strict
```

Plugin manifest is the primary validation gate. `scripts/run-gauntlet.sh` runs plugin-validate + full shell-lint + JSON lint + harness-audit + the hook behavioral suite (`hooks/tests/test-gates.sh` + `test-flow-nudge.sh` + `test-session-stop.sh` — deny-gate + advisory-sensor + session/stop-hook unit tests) in parallel. The broader fleet critical-hooks suite and the eval dataset gate are pending rebuild.

## Adding or removing a surface

Auto-discovered directories: `agents/`, `skills/`, `commands/`, `hooks/`, `output-styles/`, `themes/`. See `.claude/skills/add-surface/SKILL.md` for the step-by-step (manifest bump, validation, BOUNDARY.md regen).

## Git hooks

Hooks live in `git-hooks/` (not `.git/hooks/`). Wire once per clone:

```bash
git config core.hooksPath git-hooks
```

pre-commit: fast gate — syntax/lint (`bash -n` + shellcheck), JSON validation, CRITICAL harness-audit (graceful-skip if absent).
pre-push: full gauntlet (all validation layers in parallel).

## Composer-not-creator doctrine

Before writing a new skill, command, or agent from scratch, check the upstream ECC repo at `/Users/kobig/Codes/Personals/ECC` and the vendored superpowers checkout at `/Users/kobig/Codes/Personals/superpowers`. Cherry-pick and adapt from there. Create kbg-native surfaces only when no upstream fit exists. (A hand-pinned HEAD hash is structurally doomed to re-stale; the path is the stable anchor — run `git rev-parse HEAD` there when you need the current commit.)

## Architecture

The plugin ships as `kbg@kobig` from the `wasikarn/kbg-harness` GitHub repo. Claude Code loads all surfaces from `~/.claude/plugins/cache/kobig/kbg/<version>/` at startup. Nothing is symlinked.

**Doctrine injection:** `hooks/session/doctrine-bootstrap.sh` fires on SessionStart and injects `docs/METHODOLOGY.md` (decision-sizing triad + reasoning scaffold) into session context via `$CLAUDE_PLUGIN_ROOT` (the plugin install dir; the older `$CLAUDE_PLUGIN_DIR` name is not a real CC variable and expands empty).

**Operating model:** deny the irrecoverable set computationally (gates in `hooks/gates/`), advise on the rest (sensors in `hooks/advisory/`). Advisory sensors never emit `permissionDecision`. The L2–L5 autonomy ladder is retired.

**Why — the unifying crux:** the gate is a *verifier* (deterministic shell returning a branchable **score**), the model is the *maker*, and the maker can never grade its own work — an LLM judging its own output is circular ("two optimists agreeing"). So advisory sensors journal but never gate, and the autonomy ladder had to retire: a model-as-gate is the maker appointing its own verifier. **Score, not feel** — every loop's stop condition must be a number a deterministic gate can branch on, never a vibe the model rationalizes. (This is the agent-loop verifier-separation principle; see `docs/research/` + the retired L2–L5 build for the proven failure it prevents.)

When hooks are wired: gates/ (deny), advisory/ (journal), session/ (inject), stop/ (cost tracking).

## Skill authoring doctrine (matt-pocock)

When creating or editing a skill under `skills/`, follow matt-pocock's `writing-great-skills` doctrine — canonical: the `writing-great-skills` skill (installed via `gh skill`, not vendored in this repo since v0.46.0 — see README.md Quick Start; leading word, ≤25-word description, completion criterion, no-op test, two-cuts, failure-mode guard).

The `docs/skill-template/SKILL.md` template carries this checklist as a `## Design checks` section. New skills that don't carry it are audit-flagged by `skills/harness-audit` on next pass.

**Named Model footers:** a skill/command/agent that makes load-bearing reasoning/judgment choices may end with a `## Named Model` footer citing cc-thinking-skills lenses. Apply the 3-condition rubric from `memory/mental-models-sweep-v0302-2026-07-03.md`: (1) load-bearing reasoning gap, (2) name-a-lens benefit for the operator, (3) honesty posture preserved (footer is a scaffold + catalog pointer, never "this lens proves correctness"). The curated catalog is `docs/reference/reasoning-models.md`; the 39 raw models live under `docs/reference/thinking-skills/skills/`.

**Suggested next step footers:** a workflow surface (command or workflow skill run as a discrete step) may end its Output/Summary phase with a `Suggested next step:` marker — outcome-branched (`situation → action`), citing skills as `kbg:<name>` and commands as `/<name>`. Skills are ALWAYS cited `kbg:`-form (never `/name`) — get this right at authoring time: `harness-audit` check 40 only catches rename/deletion drift on refs already in `kbg:` form, it does **not** scan for a skill mis-cited in slash form (confirmed: this exact bug shipped twice — `commands/pr.md` and `diagnosing-bugs/SKILL.md` both cited a skill as `/name` undetected until a manual survey caught it, v0.35.0). Passive suggestion only — never "invoke X now" / auto-chain (that collides with the no-model-self-start doctrine). Skip self-contained reference/pattern/catalog surfaces (a forced footer there is the retired canonical-sections ceremony, 2026-06-16) and terminal workflows (post-mortem, ship-release terminus).

**Escalation to `AskUserQuestion`:** a branch belongs in the passive footer only while it's anticipatory — conditional on a fact not yet known (did the reviewer comment, did CI go red). If every branch is already true/decidable right now and there's no sensible default, that's a present-tense fork, not a suggestion — surface it via `AskUserQuestion` (per `output-styles/staff-eng.md`'s decision-question rule: one-line consequence per option) instead of text the user might not read. Model: obra/superpowers' `finishing-a-development-branch` skill, which ends by presenting exactly N concrete options (merge/PR/keep/discard) and blocking for the pick — not superpowers' separate (and rejected) `using-superpowers` auto-chain directive. None of kbg's shipped footers (v0.35.0/.1) currently qualify — they're all anticipatory-conditional — so this is a criterion for future surfaces, not a rewrite of what shipped.

## Branching model

Single branch: `develop` only. No feature branches. Commit and push direct.

**Computationally enforced** by `gate:worktree:develop-only` (`WorktreeCreate` event) and the `git worktree add -b` block in `gate:bash:irrecoverable` (`PreToolUse:Bash`). Both gates are opt-in per repo via the `/.kbg-no-worktree` sentinel — present in the kbg-harness repo, absent from tathep/ECC/scratch repos (which keep their existing `gate:write:worktree-guard` redirect). Detached `review-pr-<N>` worktrees in `$TMPDIR` are explicitly allowlisted so the Phase 2 PR-by-number review path keeps working.

## Non-obvious gotchas

- **Hardcoded home paths blocked:** `.sh`/`.py` files must use `$HOME` or `~`, never `/Users/<name>`. The pre-commit gate will reject the commit.
- **`defaultEnabled: false`:** plugin ships disabled. After install, add `"kbg@kobig": true` to Claude Code `settings.json`, then restart.
- **Output style:** `output-styles/staff-eng.md` is the sole live-response register — self-calibrates terse vs full decision-framing by stakes, not by switching files (the old `senior-eng.md`/`staff-eng.md` two-file split was collapsed 2026-07-02; the internal "Calibrate to stakes" rule replaces the escalation/fallback dance). `force-for-plugin: true` auto-activates it whenever `kbg@kobig` is enabled, overriding the user's own `outputStyle` setting — no `/output-style` selection needed, but it also means you can't run a different style while this plugin is on without disabling it first.
- **Working frames:** `contexts/` holds `dev.md`, `review.md`, `research.md` — loaded by `/frame` to set session posture.
- **`grep` is aliased** to `rtk grep` in this environment. Use `/usr/bin/grep` or `awk` for count/stat operations.
- **Cache-invalidation:** same-version edits are no-ops. Always bump both manifests before `claude plugin update`. CLAUDE.md-only edits skip the bump — it's dev-facing repo guidance, not cached plugin content (only `agents/`/`skills/`/`commands/`/`hooks/`/`output-styles/`/`themes/` ship per-version).
- **`BOUNDARY.md` regen:** the script writes to STDOUT, not the file. The `> BOUNDARY.md` redirect is required every time.
- **Never `rm -rf`:** use `trash` for deletions.
- **Never `--no-verify`** on commits or pushes.
- **Stage by name:** never `git add -A` or `git add .`.
- **Skill descriptions load on every Task spawn** (~words×1.3 tokens). Keep descriptions ≤25 words.
- **Thinking models:** default is the triad + `advisor()` inline (METHODOLOGY Rule 1) — `kbg:decide` is on-demand only, for genuinely hard/contested-diagnosis choices (de-scoped 2026-07-02, v0.21.4: 0 real-world invocations vs 55 `advisor()` calls across 182 sessions). The 39 on-demand mental-model files live in `docs/reference/thinking-skills/skills/` (never move to `skills/` — would break fleet count).
- **`disable-model-invocation: true`:** carried by 12 skills currently — each skill's own `disable-model-invocation-reason` frontmatter field states why (`grep -rl "disable-model-invocation: true" skills/` for the current list). Only `recursive-improve/SKILL.md` is **CRIT**-guarded against the flag being silently dropped (`harness-audit` check 39, hardcoded to that one file — the highest-blast-radius surface, an unattended repair loop). Check 30 only WARNs that a `-reason` field exists on whichever skills currently carry the flag; it does not catch the flag itself disappearing from the other 11.
- **`review_mode` in `ship-merge`:** `review-pr` tags its state write `pr-by-number` (isolated worktree) or `own-branch` (self-review). `ship-merge` caps the Critical-findings score at the fatal-weakness floor on sensitive-path diffs reviewed `own-branch` — an automation-bias guard against trusting a same-session self-review's severity tiering. "Sensitive-path" covers both auth/secret/credential/payment/billing/token AND the harness's own verifier/gate code (`hooks/gates/**`, `hooks/hooks.json`, `skills/harness-audit/scripts/{audit.sh,checks/**}` — the same list `hooks/gates/verifier-protect.sh` protects).
- **`orchestrate` vs `kbg:decide`:** orchestrate decides whether/how to spend effort on an ask (inline/parallel/sequential/drop, which surface receives it) *before* it's understood as a bounded decision; `decide` reasons through a bounded question once you're already committed to answering it. A pile of competing asks routes through `orchestrate` first; a single reversible-choice question goes straight to `decide`.
- **`SKILL.md` frontmatter ≠ `agents/*.md` frontmatter:** the real skill-file field for tool control is `allowed-tools` (pre-approves without asking; there's no hard-restriction field for skills), not `tools:` — that's the `agents/*.md` subagent field (hard-restricts to a fixed set). Confirmed against the official 16-field `skills.md` reference and the shipped CLI binary's own compiled schema key list. `metadata` / `metadata.origin` / `disable-model-invocation-reason` are non-standard-but-harmless kbg conventions — Claude Code tolerates unrecognized frontmatter keys (confirmed via changelog + `plugin.json`'s own documented "unrecognized fields → warning, not error" policy), they just carry zero behavioral effect.
- **`/goal` vs `goal-craft`:** `/goal` is Claude Code's own native completion-condition loop (v2.1.139+, session-scoped, judged each turn by a separate small model that reads only the transcript). kbg never wraps or auto-invokes `/goal` itself — the user always types `/goal` themselves, no exceptions. `skills/goal-craft/SKILL.md` only composes a paste-ready condition string (mandatory one-way-door screen + turn bound) and, as of 2026-07-08, is model-invocable (its `disable-model-invocation` flag was removed on user request) — the model may draft a condition unprompted, but the string is inert until the user pastes it after `/goal`. Auto-dispatch of `/goal` itself (`claude -p "/goal ..."`) is still a deliberate non-goal — it forks a separate headless session and reopens the retired L4/L5 "no model self-start" invariant.

## Recent versions

Quick orientation for the last few releases. For full notes see `CHANGELOG.md`.

Cap this list at 10 bullets. Keep the last 3-5 releases as individual entries; fold older ones into version-range bullets (`vX.Y.a–vX.Y.b` or `vX.Y.x`) by theme. Adding an 11th bullet means dropping the oldest — `CHANGELOG.md` is the full record, this section is orientation only.

- **v0.46.0** — Migrated all 17 remaining matt-origin skills (fleet 50→33) — `ask-matt`, `code-review`, `codebase-design`, `diagnosing-bugs`, `domain-modeling`, `grilling`, `handoff`, `improve-codebase-architecture`, `research`, `setup-matt-pocock-skills`, `tdd`, `teach`, `to-spec`, `to-tickets`, `triage`, `wayfinder`, `writing-great-skills` — out of kbg's vendored tree to `gh skill install`, on explicit user directive to remove all matt-duplicate skills regardless of kbg's local value-adds. Also installed `grill-with-docs` (new — matt splits `grilling`'s stateful mode into a separate skill; kbg's old single-skill `--with-docs` flag had no matt equivalent, so this is required to preserve `ask-matt`'s promised with-docs mode); skipped `grill-me` (thin alias, no value over `ask-matt` as entry point). Jira-acli routing for `to-spec`/`to-tickets` now relies solely on the always-loaded global CLAUDE.md rule — no local reinforcement, a known risk accepted on user directive (this is the same configuration that preceded the TP-809/TP-806 incident). Rewired ~30 live cross-references across `hooks/hooks.json`, `hooks/advisory/flow-nudge.sh`, `README.md`, 5 `docs/reference/*.md` files, 4 `commands/*.md` files, `skills/decide`, `skills/orchestrate` (×2), `skills/task-prep`, 2 `agents/*.md` files, and `skills/pr` — historical files (`CHANGELOG.md`, `.scratch/**`, dated `docs/research/*.md`) left untouched. README.md now documents the `gh skill install` calls as a required (not optional) setup step. A follow-up correctness pass (commit `37ad188`, same version, no manifest bump) found and fixed 2 dead file-path references the deletion left behind (`CLAUDE.md`'s own skill-authoring doctrine pointing at the deleted `skills/writing-great-skills/SKILL.md`; `docs/agent-voice-extension.md` pointing at the deleted `skills/diagnosing-bugs/SKILL.md`) plus 1 stale attribution count in `README.md` (17→20 skills, reframed as installed-verbatim-not-vendored, 0 kbg-modified). Also confirmed zero leftovers from matt's 4 deprecated skills (`design-an-interface`, `qa`, `request-refactor-plan`, `ubiquitous-language`) — both absorbed into matt's current `codebase-design`/`domain-modeling` (migrated this round) or never adopted by kbg.
- **v0.44.0** — Matt-first alignment vs upstream `mattpocock-skills` v1.1.0. Audited all 15 matt-origin skills: kbg was already a superset on 9 (left untouched). +4 new skills (fleet 48→52): `resolving-merge-conflicts`, `research` (replaces `/deep-dive`, commands 15→14), `code-review` (Standards+Spec two-axis review + Fowler-12 baseline, also grafted into `agents/code-reviewer.md`), `wayfinder` (multi-session investigation map + tracker plumbing in the 3 `issue-tracker-*.md` seed docs). Renamed `to-prd`→`to-spec`, `to-issues`→`to-tickets` (grafted only matt's genuine new steps, preserved kbg's jira-acli handoffs/done-when gates); rewired `ask-matt`. Reshaped `tdd` to matt's reference-only Seams/Rules-of-the-loop structure (dropped Refactor phase — now a `code-review` concern — folded kbg's RED-verification rule + codebase-design cross-ref forward). `grilling` gained the explicit enactment stop-gate. `prototype` dropped `disable-model-invocation` (now model-invocable); net flag count unchanged (`wayfinder` newly carries it). Also fixed a pre-existing, unrelated manifest drift (claimed 17 commands, real count was 15).

Older releases: see `CHANGELOG.md` for the full record.
