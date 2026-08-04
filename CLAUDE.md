# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Validation (run before committing)

```bash
claude plugin validate . --strict
```

Plugin manifest is the primary validation gate. `scripts/run-gauntlet.sh` runs plugin-validate + full shell-lint + JSON lint + harness-audit + the 9-file hook behavioral suite (`hooks/tests/test-gates.sh`, `test-worktree-guard.sh`, `test-flow-nudge.sh`, `test-jira-route-nudge.sh`, `test-session-stop.sh`, `test-learn-nudge.sh`, `test-plan-review-nudge.sh`, `test-compliance-audit-nudge.sh`, `skills/harness-audit/tests/test-harness-audit.sh` — deny-gate + advisory-sensor + session/stop-hook + harness-audit unit tests) in parallel. The old 204-test critical-hooks suite and eval dataset gate were deleted, not rebuilt, in the 2026-06-27 owner-authorized reset (`c452102`) — most of what they tested was the L3/L4/L5 autonomy machinery retired by ADR 0006, and current coverage (harness-audit's 52 checks + the suite above) already exceeds what they checked. Recovery anchor if ever wanted: `24d7663`.

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

## Agent skills

### Issue tracker

GitHub Issues on `wasikarn/kbg-harness` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary kept as-is. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — root `CONTEXT.md` + `docs/adr/` (neither exists yet; created lazily by `/domain-modeling`). See `docs/agents/domain.md`.

## Research: check qmd before web search

Before starting primary-source research — fact-checking a claim, investigating a library/API,
verifying a citation — search the local `qmd` collections first, then query `context7` for any
library/framework doc lookup, before reaching for `WebSearch`. Relevant collections: `kbg-research`
(this repo's own `docs/research/`), `kbg-memory` (this repo's own memory store), `llm-wiki` (the
operator's personal knowledge vault, 1,600+ docs spanning every project), plus other project-specific
collections. Run `qmd status` (or the `status` MCP tool) for the full current list; scope a query
to the relevant collections rather than searching all of them blind.

**Why this line lives here, not in a skill:** kbg built exactly this qmd-first behavior once
already, wired into a vendored `research` skill (v0.44.0, explicitly kept vendored so "a bare
install would lose" the qmd/context7 fold-in). It was deleted anyway — commit `d99ccf3` swapped it
for a bare `gh skill` copy, then v0.58.11 swapped that for the upstream `mattpocock-skills:
engineering/research` plugin skill, which carries no qmd or context7 awareness (confirmed by grep,
2026-07-30). Two unrelated migrations, both aimed at fixing namespace collisions, silently dropped
this value with nobody catching it. A skill file is exactly the kind of surface an upstream resync
can overwrite out from under you; `CLAUDE.md` isn't. The rule lives here so it survives the next
resync and applies to every research-shaped task, not just the ones that happen to route through
one particular skill.

**Cross-project reach (v0.68.106):** this file only loads when cwd is `kbg-harness` — a
foreign-project session never sees this rule. The operator's own `~/.claude/CLAUDE.md`
(dotfiles-owned, not shipped with this plugin) now carries a short mirror of the `llm-wiki`
half of this rule, so the vault stays reachable from any project. That mirror doesn't replace
this section — it's a thinner pointer for a context this file can't reach. `/kbg:wiki-ingest`
and `kbg:wiki-scan` (this repo) give the vault a user-invoked write path and a read-only health
check, respectively; see their own files for the doctrine reasoning (public-plugin-touching-
private-vault, graceful-skip when `~/llm-wiki` is absent, `disable-model-invocation` on the
mutating command).

**Live-fire confirmed (2026-07-30):** a fresh session in a genuinely different project (not
kbg-harness) spontaneously reached for `qmd` scoped to `collection: "llm-wiki"` on a research
question, unprompted — the mirror rule above reaches a foreign session as designed. This was
the one part of the design that couldn't be verified by grep or script (a prompt-only routing
rule either triggers in the wild or it doesn't); it does.

## Architecture

The plugin ships as `kbg@kobig` from the `wasikarn/kbg-harness` GitHub repo. Claude Code loads all surfaces from `~/.claude/plugins/cache/kobig/kbg/<version>/` at startup. Nothing is symlinked.

**Doctrine injection:** `hooks/session/doctrine-bootstrap.sh` fires on SessionStart and injects `docs/METHODOLOGY.md` (decision-sizing triad + reasoning scaffold) into session context via `$CLAUDE_PLUGIN_ROOT` (the plugin install dir; the older `$CLAUDE_PLUGIN_DIR` name is not a real CC variable and expands empty).

**Operating model:** deny the irrecoverable set computationally (gates in `hooks/gates/`), advise on the rest (sensors in `hooks/advisory/`). Advisory sensors never emit `permissionDecision`. The L2–L5 autonomy ladder is retired.

**Why — the unifying crux:** the gate is a *verifier* (deterministic shell returning a branchable **score**), the model is the *maker*, and the maker can never grade its own work — an LLM judging its own output is circular ("two optimists agreeing"). So advisory sensors journal but never gate, and the autonomy ladder had to retire: a model-as-gate is the maker appointing its own verifier. **Score, not feel** — every loop's stop condition must be a number a deterministic gate can branch on, never a vibe the model rationalizes. (This is the agent-loop verifier-separation principle; see `docs/research/` + the retired L2–L5 build for the proven failure it prevents.)

When hooks are wired: gates/ (deny), advisory/ (journal), session/ (inject), stop/ (cost tracking + turn-completion format gate — the one Stop hook, `thai-summary-gate.sh`, that blocks; kept in stop/ rather than gates/ since it's a response-format check, not an irrecoverable-action deny).

## Skill authoring doctrine (matt-pocock)

When creating or editing a skill under `skills/`, follow matt-pocock's `writing-great-skills` doctrine (leading word, ≤25-word description, completion criterion, no-op test, two-cuts, failure-mode guard) — canonical: the `mattpocock-skills:writing-great-skills` skill. See `docs/skill-authoring-conventions.md` for the kbg-specific additions on top of that (harness-audit check 36's proxy coverage, Named Model footers, Suggested next step footers, AskUserQuestion-escalation criteria) — only load it when actually authoring or editing a skill/command/agent's content.

## Branching model

Single branch: `develop` only. No feature branches. Commit and push direct.

**Computationally enforced** by the `git worktree add -b` block in `gate:bash:irrecoverable` (`PreToolUse:Bash`). Opt-in per repo via the `/.kbg-no-worktree` sentinel — present in the kbg-harness repo, absent from other client/ECC/scratch repos (which keep their existing `gate:write:worktree-guard` redirect). Detached `review-pr-<N>` worktrees in `$TMPDIR` are explicitly allowlisted so the Phase 2 PR-by-number review path keeps working.

A prior companion gate on the native `WorktreeCreate`/`WorktreeRemove` events (`gate:worktree:develop-only`, `hooks/gates/worktree-create-block.sh`) was removed 2026-07-31 — confirmed against raw Claude Code doc HTML that those events never send `tool_name`/`tool_input` at all, so its deny logic was dead code, and independent of that bug, registering any hook on `WorktreeCreate` replaces Claude Code's default worktree creation and requires the hook to emit the resulting path on success, which this one never did — so it was silently breaking every legitimate `WorktreeCreate`-triggered worktree (`isolation: "worktree"` agents/workflows, `claude --worktree`, background sessions) in every repo running this plugin, not just this one. The Bash-side check above is unaffected — `WorktreeCreate` never fires for Bash-invoked `git worktree add` in the first place. Full writeup: `docs/research/official-docs-audit-2026-07-31.md`.

**Never run `mattpocock-skills:git-guardrails-claude-code`'s setup in this repo.** That skill wires a PreToolUse hook blocking *all* `git push` unconditionally (not just `--force`) — direct conflict with this section's "commit and push direct" workflow. Not currently installed here (verified 2026-08-01: no `.claude/settings.json` in this repo, no match in the global one) — this is a standing caveat against ever running it here, not a fix for an active problem.

### Concurrent sessions

The single-branch, no-worktree design above means concurrent Claude Code sessions on this repo share one working tree — there's no isolation to fall back on, so discipline has to substitute for it:

- **Stage by explicit path only**, never `git add -A`/`git add .` (already required by the "Stage by name" rule below) — before staging, run `git status --porcelain` and confirm every listed file is one you actually touched this session. A file you don't recognize is probably another session's in-progress work, not junk.
- **Re-read `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` immediately before writing a commit message that references the version** — another session may have bumped it since you last checked, and a stale version number in a commit message is worse than no version number.
- **A scratch/workspace dir reappearing after you thought it was cleaned up** (e.g. a fixture workspace, `skills/pr-workspace/`) is a signal another session owns it right now — leave it alone rather than deleting or restaging over it.

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
- **Re-verifying a same-session edit to any surface:** don't hand a fixture-loop re-verification agent a name-based reference to test an edit that hasn't been bumped/reinstalled yet — not `Skill(<name>)`, not `subagent_type: <name>` for a plugin-scoped Agent, and not the slash-command itself for a Command. `agents/`, `commands/`, and `skills/` all ship inside the same single versioned bundle (`~/.claude/plugins/cache/kobig/kbg/<version>/` — confirmed identical layout across all three, 2026-07-27), so any of those resolutions silently tests stale cached content with no error, regardless of which surface type was edited. Confirmed 2026-07-27 (tech-humanize v0.68.59): one re-verification agent got a false "fix confirmed" this way via `Skill(kbg:tech-humanize)`; instruct the agent to `Read` the repo path directly instead.
- **`BOUNDARY.md` regen:** the script writes to STDOUT, not the file. The `> BOUNDARY.md` redirect is required every time.
- **The same-version stale trap applies to third-party plugins too, not just kbg's own.** Confirmed 2026-08-01: `mattpocock-skills@mattpocock` was 3 commits behind its own upstream `main` (a `to-tickets` content refactor + a docs split) while `claude plugin update mattpocock-skills@mattpocock` reported "already at the latest version" — the marketplace mirror had synced (`known_marketplaces.json`'s `lastUpdated` was current), but mattpocock/skills hadn't bumped its own `plugin.json` version string for those commits, so the version-keyed `update` command correctly saw nothing to do. Fixed the same way as kbg's own instance of this trap: `claude plugin uninstall mattpocock-skills@mattpocock` → `trash ~/.claude/plugins/cache/mattpocock/mattpocock-skills/<version>` → `claude plugin install mattpocock-skills@mattpocock` (verify via `gitCommitSha` in `installed_plugins.json` matching the local clone's `git rev-parse HEAD`). Worth this same uninstall-trash-reinstall check periodically for any plugin whose upstream doesn't reliably bump its version on every content change, not just after an edit made through this repo.
- **Output style:** `output-styles/staff-eng.md` is the sole live-response register — self-calibrates terse vs full decision-framing by stakes, not by switching files (the old `senior-eng.md`/`staff-eng.md` two-file split was collapsed 2026-07-02; the internal "Calibrate to stakes" rule replaces the escalation/fallback dance). `force-for-plugin: true` auto-activates it whenever `kbg@kobig` is enabled, overriding the user's own `outputStyle` setting — no `/output-style` selection needed, but it also means you can't run a different style while this plugin is on without disabling it first.

### Session environment quirks

- **Working frames:** `contexts/` holds `dev.md`, `review.md`, `research.md` — loaded by `/frame` to set session posture.
- **`grep` is aliased** to `rtk grep` in this environment. Use `/usr/bin/grep` or `awk` for count/stat operations.

### Skill/agent/command mechanics & routing

- **Skill descriptions load on every Task spawn** (~words×1.3 tokens). Keep descriptions ≤25 words.
- **Thinking models:** default is the triad + `advisor()` inline (METHODOLOGY Rule 1) — `kbg:decide` is on-demand only, for genuinely hard/contested-diagnosis choices (de-scoped 2026-07-02, v0.21.4: 0 real-world invocations vs 55 `advisor()` calls across 182 sessions). The 39 on-demand mental-model files live in `docs/reference/thinking-skills/skills/` (never move to `skills/` — would break fleet count).
- **`disable-model-invocation: true`:** carried by 2 skills currently — `recursive-improve` and `score-decision` (re-check via `for f in skills/*/SKILL.md; do head -20 "$f" | grep -qF 'disable-model-invocation: true' && echo "$f"; done` — frontmatter-scoped, not a bare `grep -rl`, which also matches skills that only *mention* another skill's flag in prose (e.g. `decide`/`orchestrate` cite `score-decision`/`wayfinder`'s flags without carrying one themselves) and would misreport the count; the count drifted hard after v0.46.0 moved 17 flag-carrying matt-origin skills out of this repo, and nobody updated this line). Both are now **CRIT**-guarded against the flag being silently dropped: `recursive-improve/SKILL.md` by check 39, `score-decision/SKILL.md` by check 49 (added 2026-07-23 after a `kbg:plan-reviewer` pass on a skill-improvement batch plan flagged that skill-creator's own description-optimizer rewrites SKILL.md frontmatter, and only recursive-improve had a real gate). Check 30 still only WARNs that a `-reason` field exists on whichever skills currently carry the flag — it's the presence-of-reason check, not the flag-survives-a-rewrite check; the two CRIT checks above are what actually close that gap now.
- **`review_mode` in `ship-merge`:** `review-pr` tags its state write `pr-by-number` (isolated worktree) or `own-branch` (self-review). `ship-merge` caps the Critical-findings score at the fatal-weakness floor on sensitive-path diffs reviewed `own-branch` — an automation-bias guard against trusting a same-session self-review's severity tiering. "Sensitive-path" covers both auth/secret/credential/payment/billing/token AND the harness's own verifier/gate code (`hooks/gates/**`, `hooks/hooks.json`, `skills/harness-audit/scripts/{audit.sh,checks/**}` — the same list `hooks/gates/verifier-protect.sh` protects).
- **`orchestrate` vs `kbg:decide`:** orchestrate decides whether/how to spend effort on an ask (inline/parallel/sequential/drop, which surface receives it) *before* it's understood as a bounded decision; `decide` reasons through a bounded question once you're already committed to answering it. A pile of competing asks routes through `orchestrate` first; a single reversible-choice question goes straight to `decide`.
- **`SKILL.md` frontmatter ≠ `agents/*.md` frontmatter:** the real skill-file field for tool control is `allowed-tools` (pre-approves without asking; there's no hard-restriction field for skills), not `tools:` — that's the `agents/*.md` subagent field (hard-restricts to a fixed set). Confirmed against the official 16-field `skills.md` reference and the shipped CLI binary's own compiled schema key list. `metadata` / `metadata.origin` / `disable-model-invocation-reason` are non-standard-but-harmless kbg conventions — Claude Code tolerates unrecognized frontmatter keys (confirmed via changelog + `plugin.json`'s own documented "unrecognized fields → warning, not error" policy), they just carry zero behavioral effect.
- **`/goal` vs `goal-craft`:** `/goal` is Claude Code's own native completion-condition loop (v2.1.139+, session-scoped, judged each turn by a separate small model that reads only the transcript). kbg never wraps or auto-invokes `/goal` itself — the user always types `/goal` themselves, no exceptions. `skills/goal-craft/SKILL.md` only composes a paste-ready condition string (mandatory one-way-door screen + turn bound) and, as of 2026-07-08, is model-invocable (its `disable-model-invocation` flag was removed on user request) — the model may draft a condition unprompted, but the string is inert until the user pastes it after `/goal`. Auto-dispatch of `/goal` itself (`claude -p "/goal ..."`) is still a deliberate non-goal — it forks a separate headless session and reopens the retired L4/L5 "no model self-start" invariant.
