# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Validation (run before committing)

```bash
claude plugin validate . --strict
```

Plugin manifest is the primary validation gate. `scripts/run-gauntlet.sh` runs plugin-validate + full shell-lint + JSON lint + harness-audit + the 13-file behavioral test suite (deny-gate, advisory-sensor, session/stop-hook, harness-audit, review-pr convergence-state, and slash-command-script unit tests — see the script for the file list) in parallel. The old 204-test critical-hooks suite and eval dataset gate were deleted, not rebuilt, in the 2026-06-27 owner-authorized reset (`c452102`): most of what they tested was L3/L4/L5 autonomy machinery retired by ADR 0006, and current coverage already exceeds them. Recovery anchor if ever wanted: `24d7663`.

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
`mattpocock/skills` first — what's installed under the `mattpocock-skills@mattpocock` plugin
(`claude plugin list` / the Skill tool's listing, namespaced `mattpocock-skills:<name>`), plus the
local clone at `~/Codes/Personals/mattpocock-skills` for what's upstream but not yet
installed. This is a **Matt-Pocock-first harness**; checking ECC/superpowers before matt's own repo
gets the priority backwards. `git fetch` the local clone before trusting it — it silently lagged
origin/main by 104 commits (a whole minor release) until caught 2026-08-10; the installed plugin
can be *newer* than the clone, inverting this section's "upstream but not yet installed" framing. **(2)** the upstream ECC repo at `~/Codes/Personals/ECC`
and the vendored superpowers checkout at `~/Codes/Personals/superpowers`. **(3)** sibling
harnesses under `~/Codes/Personals/` for structural patterns (e.g. `oh-my-claudecode`;
ask if unsure which qualify). Cherry-pick and adapt from whichever source fits; create kbg-native
surfaces only when none do. Confirmed gap (2026-07-17): `code-implementer`/`/implement` were built
checking only (2), skipping (1) — collided with matt's own `engineering/implement` skill, caught by
the user, not by this checklist. (Paths are the stable anchor, not pinned hashes — run
`git rev-parse HEAD` there when you need the current commit.)

## Agent skills

### Issue tracker

GitHub Issues on `wasikarn/kbg-harness` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary kept as-is. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — root `CONTEXT.md` + `docs/adr/` (neither exists yet; created lazily by `mattpocock-skills:domain-modeling`). See `docs/agents/domain.md`.

## Research: check qmd before web search

Before starting primary-source research — fact-checking a claim, investigating a library/API,
verifying a citation — search the local `qmd` collections first, then query `context7` for any
library/framework doc lookup, before reaching for `WebSearch`. Relevant collections: `kbg-research`
(this repo's own `docs/research/`), `kbg-memory` (this repo's own memory store), `llm-wiki` (the
operator's personal knowledge vault, 1,600+ docs spanning every project), plus other project-specific
collections. Run `qmd status` (or the `status` MCP tool) for the full current list; scope a query
to the relevant collections rather than searching all of them blind.

**Why this line lives here, not in a skill:** kbg built exactly this qmd-first behavior once
already, vendored into a `research` skill — and two unrelated namespace-collision migrations
(`d99ccf3`, then v0.58.11's swap to `mattpocock-skills:engineering/research`, which carries no
qmd/context7 awareness) silently deleted it with nobody catching it. A skill file is exactly the
kind of surface an upstream resync can overwrite out from under you; `CLAUDE.md` isn't. The rule
lives here so it survives the next resync and applies to every research-shaped task.

**Cross-project reach (v0.68.106):** this file only loads when cwd is `kbg-harness`, so the
operator's own `~/.claude/CLAUDE.md` (dotfiles-owned, not shipped with this plugin) carries a
thinner mirror of the `llm-wiki` half — live-fire confirmed 2026-07-30: a foreign-project session
reached for `qmd` scoped to `llm-wiki` unprompted, the one part of the design no grep or script
could verify. `/kbg:wiki-ingest` (user-invoked write path, `disable-model-invocation`) and
`kbg:wiki-scan` (read-only health check) are the vault-touching surfaces; doctrine reasoning lives
in their own files.

**Verify technical claims before shipping them into agent/skill content, not just when asked to
"research."** A confidently-worded complexity, security-mechanism, or framework-behavior claim can
read as correct and still be wrong — plausibility isn't verification. Before treating that kind of
addition as done: deep-read the relevant `qmd`/`llm-wiki` content first, then `WebSearch` (or the
`deep-research` workflow for a claim worth a multi-source adversarial pass). Confirmed load-bearing
2026-08-05 — caught 3 shipped, plausible-reading errors: `performance-optimizer.md`'s two-pointer
"O(n) 3-sum" (it's O(n²)), `drizzle-patterns`' "one query per relation depth" for Drizzle's nested
`with` (always exactly one query total), and a CWE-1333/CWE-400 pairing contradicting MITRE's own
page. None looked wrong on read; each needed an actual source check.

## Architecture

The plugin ships as `kbg@kobig` from the `wasikarn/kbg-harness` GitHub repo. Claude Code loads all surfaces from `~/.claude/plugins/cache/kobig/kbg/<version>/` at startup. Nothing is symlinked.

**Doctrine injection:** `hooks/session/doctrine-bootstrap.sh` fires on SessionStart and injects `docs/METHODOLOGY.md` (decision-sizing triad + reasoning scaffold) into session context via `$CLAUDE_PLUGIN_ROOT` (the plugin install dir; the older `$CLAUDE_PLUGIN_DIR` name is not a real CC variable and expands empty).

**Operating model:** deny the irrecoverable set computationally (gates in `hooks/gates/`), advise on the rest (sensors in `hooks/advisory/`). Advisory sensors never emit `permissionDecision`. The L2–L5 autonomy ladder is retired.

**Why — the unifying crux:** the gate is a *verifier* (deterministic shell returning a branchable **score**), the model is the *maker*, and the maker can never grade its own work — an LLM judging its own output is circular ("two optimists agreeing"). So advisory sensors journal but never gate, and the autonomy ladder had to retire: a model-as-gate is the maker appointing its own verifier. **Score, not feel** — every loop's stop condition must be a number a deterministic gate can branch on, never a vibe the model rationalizes. (This is the agent-loop verifier-separation principle; see `docs/research/` + the retired L2–L5 build for the proven failure it prevents.)

When hooks are wired: gates/ (deny), advisory/ (journal), session/ (inject), stop/ (cost tracking).

## Skill authoring doctrine (matt-pocock)

When creating or editing a skill under `skills/`, follow matt-pocock's `writing-for-agents` doctrine (leading words, one trigger per branch, completion criterion + demand, no-op test, progressive disclosure across the two loads) — canonical: the `mattpocock-skills:writing-for-agents` skill (model-invocable; renamed from `writing-great-skills` in matt v1.2.0, no alias — the old "two-cuts" and "failure-mode guard" labels no longer exist as named terms; their content dissolved into the rewrite's prose). The ≤25-word description cap is kbg's own token-budget rule ("Skill descriptions load on every Task spawn" below), not matt's — it was misattributed to matt here until 2026-08-10. See `docs/skill-authoring-conventions.md` for the kbg-specific additions on top of that (harness-audit check 36's proxy coverage, Named Model footers, Suggested next step footers, AskUserQuestion-escalation criteria) — only load it when actually authoring or editing a skill/command/agent's content.

## Branching model

Single branch: `develop` only. No feature branches. Commit and push direct — "direct" means no
PR/feature-branch flow; *when* to push still follows the global confirm-before-push policy
(`~/.claude/CLAUDE.md` § Background Session Git Discipline).

**Computationally enforced** by the `git worktree add -b` block in `gate:bash:irrecoverable` (`PreToolUse:Bash`). Opt-in per repo via the `/.kbg-no-worktree` sentinel — present in the kbg-harness repo, absent from other client/ECC/scratch repos (which keep their existing `gate:write:worktree-guard` redirect). Detached `review-pr-<N>` worktrees in `$TMPDIR` are explicitly allowlisted so the Phase 2 PR-by-number review path keeps working.

A prior companion gate on the native `WorktreeCreate`/`WorktreeRemove` events was removed
2026-07-31: those events never send `tool_name`/`tool_input` (its deny logic was dead code), and a
registered `WorktreeCreate` hook that doesn't emit the resulting path silently breaks every
legitimate worktree creation in every repo running this plugin. The Bash-side check above is
unaffected. Full writeup: `docs/research/official-docs-audit-2026-07-31.md`.

**Never run `mattpocock-skills:git-guardrails-claude-code`'s setup in this repo (prose-only — no check blocks it).** It wires a PreToolUse hook blocking *all* `git push` unconditionally (not just `--force`) — direct conflict with this section's workflow. Not installed here (verified 2026-08-01); a standing caveat, not an active problem.

### Concurrent sessions

The single-branch, no-worktree design above means concurrent Claude Code sessions on this repo share one working tree — there's no isolation to fall back on, so discipline has to substitute for it:

- **Stage by explicit path only**, never `git add -A`/`git add .` (already required by the "Stage by name" rule below) — before staging, run `git status --porcelain` and confirm every listed file is one you actually touched this session. A file you don't recognize is probably another session's in-progress work, not junk.
- **Re-read `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` immediately before writing a commit message that references the version** — another session may have bumped it since you last checked, and a stale version number in a commit message is worse than no version number.
- **A scratch/workspace dir reappearing after you thought it was cleaned up** (e.g. a fixture workspace, `skills/pr-workspace/`) is a signal another session owns it right now — leave it alone rather than deleting or restaging over it.

## Non-obvious gotchas

Grouped by behavior area (not a flat bucket — find the group first, then the line).

### Repo & commit hygiene

- **Hardcoded home paths blocked:** `.sh`/`.py` files must use `$HOME` or `~`, never `/Users/<name>`. This repo is **public** — committed text files (`.md`/`.json`/`.yaml`/`.txt`) must not carry this machine's literal home path either (use `~`; `/Users/<name>` placeholder text is fine). Enforced twice: staged files by the pre-commit gate (`git-hooks/pre-commit` Layer 1), all tracked files by the gauntlet's path-hygiene layer (pre-push). Paths that are operator-layout-specific (like the composer-source clones) are fine in operator-facing files but don't present them as universal in reader-facing docs.
- **Never `rm -rf`:** use `trash` for deletions. Enforced by `hooks/gates/irrecoverable.sh`.
- **Never `--no-verify`** on commits or pushes. Enforced by `hooks/gates/irrecoverable.sh`.
- **Stage by name:** never `git add -A` or `git add .`. Enforced by `hooks/gates/irrecoverable.sh`.

### Plugin lifecycle & install

- **`defaultEnabled: false`:** plugin ships disabled. After install, add `"kbg@kobig": true` to Claude Code `settings.json`, then restart.
- **Cache-invalidation:** same-version edits are no-ops. Always bump both manifests before `claude plugin update` (enforced since 2026-08-09 by `git-hooks/pre-commit`'s version-bump layer: shipped-surface files staged ⇒ `plugin.json` version must change in the same commit, and both manifests' versions must agree — deletions count too). CLAUDE.md-only edits skip the bump — it's dev-facing repo guidance, not runtime-loaded plugin content. Runtime-loaded means the 6 surface dirs (`agents/`/`skills/`/`commands/`/`hooks/`/`output-styles/`/`themes/`) **plus** `docs/METHODOLOGY.md` and `docs/reference/**` — doctrine-bootstrap and decide/score-decision read those from the versioned cache at runtime, so the gate covers them too; other `docs/` content is cached but only ever read from the repo.
- **Re-verifying a same-session edit to any surface:** don't hand a re-verification agent a name-based reference — `Skill(<name>)`, `subagent_type: <name>`, or the slash command — to test an edit that hasn't been bumped/reinstalled yet. `agents/`, `commands/`, and `skills/` all ship in the same versioned bundle, so any of those resolutions silently tests stale cached content with no error. Confirmed 2026-07-27 (tech-humanize v0.68.59: a false "fix confirmed" via `Skill(kbg:tech-humanize)`); instruct the agent to `Read` the repo path directly instead.
- **`BOUNDARY.md` regen:** the script writes to STDOUT, not the file. The `> BOUNDARY.md` redirect is required every time — drift is caught (not prevented) by harness-audit check 16 (`16-boundary-md-drift-committed-capability-m.sh`), which WARNs.
- **The same-version stale trap applies to third-party plugins too, not just kbg's own.** Confirmed 2026-08-01: `mattpocock-skills` was 3 commits behind its own upstream while `claude plugin update` reported "already at the latest version" — upstream hadn't bumped its `plugin.json` version string, so the version-keyed update correctly saw nothing to do. Fix: `claude plugin uninstall` → `trash ~/.claude/plugins/cache/<publisher>/<plugin>/<version>` → `claude plugin install` (verify `gitCommitSha` in `installed_plugins.json` against the local clone's `git rev-parse HEAD`). Worth running periodically for any plugin whose upstream doesn't reliably bump versions on content changes.
- **Output style:** `output-styles/staff-eng.md` is the sole live-response register — its internal "Calibrate to stakes" rule self-calibrates terse vs full decision-framing (the old two-file split was collapsed 2026-07-02). `force-for-plugin: true` auto-activates it whenever `kbg@kobig` is enabled, overriding the user's own `outputStyle` setting — you can't run a different style while this plugin is on without disabling it first.

### Session environment quirks

- **Working frames:** `contexts/` holds `dev.md`, `review.md`, `research.md` — loaded by `/frame` to set session posture.
- **`grep` is aliased** to `rtk grep` in this environment. Use `/usr/bin/grep` or `awk` for count/stat operations.

### Skill/agent/command mechanics & routing

- **Skill descriptions load on every Task spawn** (~words×1.3 tokens). Keep descriptions ≤25 words.
- **Thinking models:** default is the triad + `advisor()` inline (METHODOLOGY Rule 1) — `kbg:decide` is on-demand only, for genuinely hard/contested-diagnosis choices (de-scoped 2026-07-02: 0 real-world invocations vs 55 `advisor()` calls across 182 sessions). The 39 on-demand mental-model files live in `docs/reference/thinking-skills/skills/` — never move them to `skills/` (breaks fleet count; WARNed by harness-audit check 41).
- **`disable-model-invocation: true`:** carried by 2 skills (`recursive-improve`, `score-decision`) **+ 10 commands** currently (`ask-kbg`, `compliance-audit`, `ideate-search`, `iterate-skill`, `post-mortem`, `ship-merge`, `ship-release`, `wiki-ingest`, `address-review/COMMAND.md`, `ship/COMMAND.md`). Re-check **both surface types together** — this line drifted once by tracking only skills (caught 2026-07-22, not folded back here until 2026-08-04) — via the frontmatter-scoped sweep (a bare `grep -rl` misreports: surfaces that only *mention* another one's flag in prose also match): `for f in skills/*/SKILL.md commands/*.md commands/*/COMMAND.md; do [ -f "$f" ] && head -20 "$f" | grep -qF 'disable-model-invocation: true' && echo "$f"; done`. 3 of the 12 carriers are **CRIT**-guarded against a rewrite silently dropping the flag: `recursive-improve/SKILL.md` (check 39), `score-decision/SKILL.md` (check 49), `ship-merge.md` (check 44); the other 9 commands have no equivalent guard yet. Check 30 only WARNs that a `-reason` field exists — it's the presence-of-reason check, not the flag-survives-a-rewrite check; the three CRIT checks are what close that gap.
  - **`fix-bug` de-flagged 2026-08-05:** the flag made `address-review` Phase 4's documented routing to `/fix-bug` unexecutable mid-run, `fix-bug` already has a real in-flow gate (Phase 4 `AskUserQuestion` — code mutation is unreachable without it), and its stated reason quoted a criterion retired 2026-06-19. Distinct from the 2026-07-01 precedent (flags kept to block *ambient-chat prose-triggering*, e.g. "merge pr" firing `ship-merge`) — that risk doesn't apply to a documented command-to-command delegation from an already user-invoked parent. `address-review` itself stays flagged (external GitHub write, no in-flow undo).
- **`review_mode` in `ship-merge`:** `review-pr` tags its state write `pr-by-number` (isolated worktree) or `own-branch` (self-review). `ship-merge` caps the Critical-findings score at the fatal-weakness floor on sensitive-path diffs reviewed `own-branch` — an automation-bias guard against trusting a same-session self-review's severity tiering. "Sensitive-path" covers both auth/secret/credential/payment/billing/token AND the harness's own verifier/gate code (`hooks/gates/**`, `hooks/hooks.json`, `skills/harness-audit/scripts/{audit.sh,checks/**}` — the same list `hooks/gates/verifier-protect.sh` protects).
- **`orchestrate` vs `kbg:decide`:** orchestrate decides whether/how to spend effort on an ask (inline/parallel/sequential/drop, which surface receives it) *before* it's understood as a bounded decision; `decide` reasons through a bounded question once you're already committed to answering it. A pile of competing asks routes through `orchestrate` first; a single reversible-choice question goes straight to `decide`.
- **`SKILL.md` frontmatter ≠ `agents/*.md` frontmatter:** the real skill-file field for tool control is `allowed-tools` (pre-approves without asking; skills have no hard-restriction field), not `tools:` — that's the `agents/*.md` subagent field (hard-restricts to a fixed set). Confirmed against the official `skills.md` reference and the CLI binary's compiled schema keys. `metadata` / `metadata.origin` / `disable-model-invocation-reason` are non-standard-but-harmless kbg conventions — unrecognized frontmatter keys warn, never error, and carry zero behavioral effect.
- **`/goal` vs `goal-craft`:** `/goal` is Claude Code's own native completion-condition loop (v2.1.139+, judged each turn by a separate small model). kbg never wraps or auto-invokes `/goal` — the user always types it themselves, no exceptions (prose-only; holds because no fleet surface is written to call it). `skills/goal-craft` only composes a paste-ready condition string (one-way-door screen + turn bound); model-invocable since 2026-07-08, but the string is inert until the user pastes it after `/goal`. Auto-dispatch (`claude -p "/goal ..."`) stays a deliberate non-goal — it reopens the retired "no model self-start" invariant.
