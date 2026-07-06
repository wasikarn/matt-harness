# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Validation (run before committing)

```bash
claude plugin validate --strict
```

Plugin manifest is the primary validation gate. `scripts/run-gauntlet.sh` runs plugin-validate + full shell-lint + JSON lint + harness-audit + the hook behavioral suite (`hooks/tests/test-gates.sh` + `test-flow-nudge.sh` + `test-session-stop.sh` — deny-gate + advisory-sensor + session/stop-hook unit tests) in parallel. The broader fleet critical-hooks suite and the eval dataset gate are pending rebuild.

## Adding or removing a surface

**Auto-discovered directories:** `agents/`, `skills/`, `commands/`, `hooks/`, `output-styles/`, `themes/`.

1. Create the file(s) following the pattern of an existing component in the same directory.
2. For hooks: register in `hooks/hooks.json` and add tests for any gate.
3. **Bump both** `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (the `version` field). Same-version edits to a cached plugin are silent no-ops.
4. Run validation.
5. Commit and push.
6. `claude plugin update kbg@kobig` → restart Claude Code.

When `skills/inventory/` is present, regenerate the capability map with:
`bash skills/inventory/scripts/inventory-boundary.sh --repo-only > BOUNDARY.md`
(STDOUT-only — `>` redirect mandatory. Run `bash skills/inventory/scripts/inventory.sh` first for the unified cross-layer listing; see `skills/inventory/reference.md` for witness + boundary details.)

## Git hooks

Hooks live in `git-hooks/` (not `.git/hooks/`). Wire once per clone:

```bash
git config core.hooksPath git-hooks
```

pre-commit: fast gate — syntax/lint (`bash -n` + shellcheck), JSON validation, CRITICAL harness-audit (graceful-skip if absent).
pre-push: full gauntlet (all validation layers in parallel).

## Composer-not-creator doctrine

Before writing a new skill, command, or agent from scratch, check the upstream ECC repo at `/Users/kobig/Codes/Personals/ECC`. Cherry-pick and adapt from there. Create kbg-native surfaces only when no upstream fit exists. (A hand-pinned HEAD hash is structurally doomed to re-stale; the path is the stable anchor — run `git rev-parse HEAD` there when you need the current commit.)

## Architecture

The plugin ships as `kbg@kobig` from the `wasikarn/kbg-harness` GitHub repo. Claude Code loads all surfaces from `~/.claude/plugins/cache/kobig/kbg/<version>/` at startup. Nothing is symlinked.

**Doctrine injection:** `hooks/session/doctrine-bootstrap.sh` fires on SessionStart and injects `docs/METHODOLOGY.md` (decision-sizing triad + reasoning scaffold) into session context via `$CLAUDE_PLUGIN_ROOT` (the plugin install dir; the older `$CLAUDE_PLUGIN_DIR` name is not a real CC variable and expands empty).

**Operating model:** deny the irrecoverable set computationally (gates in `hooks/gates/`), advise on the rest (sensors in `hooks/advisory/`). Advisory sensors never emit `permissionDecision`. The L2–L5 autonomy ladder is retired.

**Why — the unifying crux:** the gate is a *verifier* (deterministic shell returning a branchable **score**), the model is the *maker*, and the maker can never grade its own work — an LLM judging its own output is circular ("two optimists agreeing"). So advisory sensors journal but never gate, and the autonomy ladder had to retire: a model-as-gate is the maker appointing its own verifier. **Score, not feel** — every loop's stop condition must be a number a deterministic gate can branch on, never a vibe the model rationalizes. (This is the agent-loop verifier-separation principle; see `docs/research/` + the retired L2–L5 build for the proven failure it prevents.)

When hooks are wired: gates/ (deny), advisory/ (journal), session/ (inject), stop/ (cost tracking).

## Skill authoring doctrine (matt-pocock)

When creating or editing a skill under `skills/`, follow matt-pocock's `writing-great-skills` doctrine — canonical: `skills/writing-great-skills/SKILL.md` (leading word, ≤25-word description, completion criterion, no-op test, two-cuts, failure-mode guard).

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
- **Cache-invalidation:** same-version edits are no-ops. Always bump both manifests before `claude plugin update`.
- **`BOUNDARY.md` regen:** the script writes to STDOUT, not the file. The `> BOUNDARY.md` redirect is required every time.
- **Never `rm -rf`:** use `trash` for deletions.
- **Never `--no-verify`** on commits or pushes.
- **Stage by name:** never `git add -A` or `git add .`.
- **Skill descriptions load on every Task spawn** (~words×1.3 tokens). Keep descriptions ≤25 words.
- **Thinking models:** default is the triad + `advisor()` inline (METHODOLOGY Rule 1) — `kbg:decide` is on-demand only, for genuinely hard/contested-diagnosis choices (de-scoped 2026-07-02, v0.21.4: 0 real-world invocations vs 55 `advisor()` calls across 182 sessions). The 39 on-demand mental-model files live in `docs/reference/thinking-skills/skills/` (never move to `skills/` — would break fleet count).
- **`disable-model-invocation: true`:** `recursive-improve/SKILL.md`'s frontmatter is the one safety-load-bearing instance of this flag (no-model-self-start invariant). CRIT-guarded by `harness-audit` check 39 — dropping it fails the gate.
- **`review_mode` in `ship-merge`:** `review-pr` tags its state write `pr-by-number` (isolated worktree) or `own-branch` (self-review). `ship-merge` caps the Critical-findings score at the fatal-weakness floor on sensitive-path diffs reviewed `own-branch` — an automation-bias guard against trusting a same-session self-review's severity tiering. "Sensitive-path" covers both auth/secret/credential/payment/billing/token AND the harness's own verifier/gate code (`hooks/gates/**`, `hooks/hooks.json`, `skills/harness-audit/scripts/{audit.sh,checks/**}` — the same list `hooks/gates/verifier-protect.sh` protects).
- **`orchestrate` vs `kbg:decide`:** orchestrate decides whether/how to spend effort on an ask (inline/parallel/sequential/drop, which surface receives it) *before* it's understood as a bounded decision; `decide` reasons through a bounded question once you're already committed to answering it. A pile of competing asks routes through `orchestrate` first; a single reversible-choice question goes straight to `decide`.
- **`SKILL.md` frontmatter ≠ `agents/*.md` frontmatter:** the real skill-file field for tool control is `allowed-tools` (pre-approves without asking; there's no hard-restriction field for skills), not `tools:` — that's the `agents/*.md` subagent field (hard-restricts to a fixed set). Confirmed against the official 16-field `skills.md` reference and the shipped CLI binary's own compiled schema key list. `metadata` / `metadata.origin` / `disable-model-invocation-reason` are non-standard-but-harmless kbg conventions — Claude Code tolerates unrecognized frontmatter keys (confirmed via changelog + `plugin.json`'s own documented "unrecognized fields → warning, not error" policy), they just carry zero behavioral effect.
- **`/goal` vs `goal-craft`:** `/goal` is Claude Code's own native completion-condition loop (v2.1.139+, session-scoped, judged each turn by a separate small model that reads only the transcript). kbg never wraps or auto-invokes it — `skills/goal-craft/SKILL.md` only composes a paste-ready condition string (mandatory one-way-door screen + turn bound); the user always types `/goal` themselves. Auto-dispatch (`claude -p "/goal ..."`) is a deliberate non-goal — it forks a separate headless session and reopens the retired L4/L5 "no model self-start" invariant.

## Recent versions

Quick orientation for the last few releases. For full notes see `CHANGELOG.md`.

- **v0.35.1** — Adversarial re-review of v0.35.0 (fresh-context, not self-review) found 4 more issues: a 3rd `subtask: true` command (`security-scan`) miscategorized as self-contained; `fix-bug.md` (cited as "already good") had its own internal bare-vs-`kbg:`-prefix citation drift; `build-fix.md`'s two next-step items weren't mutually exclusive; `pr.md` mimicked CLI-arg syntax on a model-routed skill citation. All fixed.
- **v0.35.0** — `Suggested next step:` convention: outcome-branched (`situation → action`), passive-only (never auto-chained). Fixed 2 live dangling next-step pointers (`/code-review`, `/improve-codebase-architecture` mis-cited in slash form); normalized 2 divergent surfaces; backfilled 4 workflow-terminal dead-ends. No new audit check — rewriting the 2 pointers to `kbg:` form put them under check 40's existing coverage.
- **v0.34.5** — Second-pass superpowers survey (adversarial re-check) added `diagnosing-bugs/scripts/find-polluter.sh` — test-file pollution bisection, a different axis from the existing commit/version bisection harness. Genericized runner detection (npm/cargo/go/flutter/pytest); no doctrine conflict.
- **v0.34.4** — Dropped dead `tools:` frontmatter key from 4 ECC-imported skills (cargo-culted subagent field, silently ignored by Claude Code; not renamed to `allowed-tools` since that auto-approves tools — a permission-loosening nobody asked for).
- **v0.34.0–v0.34.3** — Advisory learn-nudge on `SessionEnd`; `review-pr`/`ship-merge` real-world fixes (per-PR review-state keying, verified-N/A disposition for CI/approval gates on solo/no-CI repos); `to-prd` hands off Jira publishing to `jira-acli`'s canonical template.
- **v0.33.0** — `review-pr`: language-reviewer routing (typescript/python/flutter) + independent adversarial verifier per finding.
- **v0.32.x** — Harness-wide content-accuracy audit (16 fixes across 6 surfaces); performance-correctness distillations synthesis; hook shell-form→exec-form perf conversion.
- **v0.31.x** — Hot-path + gauntlet + token-load perf refactor; corrected a stale "shellcheck is the gauntlet long-pole" claim.
- **v0.30.x** — Named Model footer sweep across skills/commands/agents using the 3-condition rubric; `diagnosing-bugs` Phase 2/3/4/5.5 gap fills; audit cleanup of footer placement/format, stale links, and exec-bit drift.
