# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Validation (run before committing)

```bash
claude plugin validate . --strict
```

Plugin manifest is the primary validation gate. `scripts/run-gauntlet.sh` runs plugin-validate + full shell-lint + JSON lint + harness-audit + the behavioral test suite (shell files via a for-loop, plus 2 Python files — memory-lint and compress-docs verify-preserved — and 1 node file — tiered-pipeline — via separate `if` blocks: deny-gate, advisory-sensor, session/stop-hook, harness-audit, pre-commit version-gate, pre-commit loc-gate, inventory-witness canonical-mode, gauntlet test-wiring, and slash-command-script unit tests — the script's `run_hook_tests()` is the authoritative file list; no count stated here, counts drift) in parallel. The old 204-test critical-hooks suite and eval dataset gate were deleted, not rebuilt: most of what they tested was L3/L4/L5 autonomy machinery retired by ADR 0006, and current coverage already exceeds them.

<!-- Deleted in the 2026-06-27 owner-authorized reset (`c452102`). Recovery anchor if ever wanted: `24d7663`. -->

## Adding or removing a surface

Auto-discovered directories: `agents/`, `skills/`, `hooks/`, `output-styles/`, `themes/` (`commands/` retired as a surface type 2026-08-25, #112). The step-by-step (inlined from the removed `add-surface` skill, 2026-08-24 #80):

1. Create/remove the file(s), following the pattern of an existing component in the same directory. A new skill/agent needs `bucket:` frontmatter (top-level key, right after `description:`) — skills: `meta`/`review`/`patterns`/`agent-support`/`design`/`workflow`; agents: `design`/`review`/`build`/`analysis`/`utility`. It groups the `BOUNDARY.md` tables; harness-audit checks 04/05 WARN if missing.
2. Hooks: register/deregister in `hooks/hooks.json`; add tests for any gate. After removing a hook's test section, grep the ENTIRE test file (not just the deleted section) for every shared helper function's name and remove any with zero remaining callers.
3. Bump both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions — same-version edits to a cached plugin are silent no-ops.
4. Run `bash skills/inventory/scripts/sync-fleet-counts.sh` to patch the "N skills · M agents" pair into `plugin.json`/`marketplace.json`/`README.md`. A new **agent** also needs two hand edits the script can't reach: `skills/workflow/orchestrate/reference.md`'s named routing table + "N-agent survivor set" count, and the count mention in `docs/agent-voice-extension.md`.
5. Run `claude plugin validate . --strict`, then `bash skills/meta/harness-audit/scripts/audit.sh` and fix any WARN — a CRIT F1 ("not loadable") for a brand-new component is expected here and clears at step 6.
6. `claude plugin update mh@kobig` **before** committing — the pre-commit hook's harness-audit F1 check only sees the latest *cached* plugin version, so a brand-new file blocks as CRIT F1 until this refreshes the cache.
7. Regenerate `BOUNDARY.md` (see the regen gotcha under "Plugin lifecycle & install" below), commit, push, restart Claude Code.

## Finding a surface

Read `BOUNDARY.md` first — the generated, always-current index of every agent, skill, command, and hook, grouped by `bucket:` (skills and agents) since schema v5. Then the specific `SKILL.md`/agent file for detail. Routing questions go to `/mattpocock-skills:ask-matt` — the former kbg router layers (`/kbg-help`, `/kbg:ask-kbg`) were removed 2026-08-24 (#80).

## Git hooks

Hooks live in `git-hooks/` (not `.git/hooks/`). Wire once per clone:

```bash
git config core.hooksPath git-hooks
```

pre-commit: fast gate — syntax/lint (`bash -n` + shellcheck), JSON validation, CRITICAL harness-audit (graceful-skip if absent), new-file LOC gate (hard-blocks a brand-new `agents/*.md` or `skills/*/SKILL.md` over 200 lines — editing an existing one past the cap stays WARN-only via harness-audit check 55; `MH_SKIP_LOC_GATE=1` is the rescue valve).
pre-push: full gauntlet (all validation layers in parallel).

## Composer-not-creator doctrine

Before writing a new skill, command, or agent from scratch, check sources in this order: **(1)**
`mattpocock/skills` first — what's installed under the `mattpocock-skills@mattpocock` plugin
(`claude plugin list` / the Skill tool's listing, namespaced `mattpocock-skills:<name>`), plus —
if this machine has it — the local clone at `~/Codes/Personals/mattpocock-skills` for what's
upstream but not yet installed. This is a **Matt-Pocock-first harness**; checking ECC/superpowers
before matt's own repo gets the priority backwards. If the clone exists, `git fetch` it before
trusting it — the installed plugin can be *newer* than the clone, inverting this section's
"upstream but not yet installed" framing. On a machine without these clones, the installed plugin
alone is the available source — skip straight to it.

**If any of these clones is reached via `claude --add-dir` instead of `cd`, none of its own
CLAUDE.md instructions load by default** — `--add-dir` grants file access only. Set
`CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` before the command if you need that clone's own
CLAUDE.md/rules read into context, not just its files.

**(2)** if present on this machine, the upstream ECC repo at `~/Codes/Personals/ECC`
and the vendored superpowers checkout at `~/Codes/Personals/superpowers`. **(3)** if present,
sibling harnesses under `~/Codes/Personals/` for structural patterns (e.g. `oh-my-claudecode`;
ask if unsure which qualify). Cherry-pick and adapt from whichever source fits; create kbg-native
surfaces only when none do. Skipping straight to (2) or (3) risks colliding with a skill matt
already built. (Paths are the stable anchor, not pinned hashes — run
`git rev-parse HEAD` there when you need the current commit.) None of these clones is bundled with
the plugin — on a machine without them, (1)'s installed `mattpocock-skills@mattpocock` plugin is
the only available source; build kbg-native only after checking what that plugin already offers.

<!-- The clone silently lagged origin/main by a full minor release before being caught. Confirmed
gap (2026-07-17): `code-implementer`/`/implement` were built checking only (2), skipping (1) —
collided with matt's own `engineering/implement` skill, caught by the user, not by this checklist. -->

## Agent skills

### Issue tracker

GitHub Issues on `wasikarn/matt-harness` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary kept as-is. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — root `CONTEXT.md` + `docs/adr/` (neither exists yet; created lazily by `mattpocock-skills:domain-modeling`). See `docs/agents/domain.md`.

## Research: check qmd before web search

Before starting primary-source research — fact-checking a claim, investigating a library/API,
verifying a citation — if a `qmd`-style MCP is configured, search the local `qmd` collections
first; if a `context7`-style MCP is configured, query it for any library/framework doc lookup —
both before reaching for `WebSearch`. Neither is bundled with this plugin; skip straight to
`WebSearch` when not configured. Relevant collections when `qmd` is available: `kbg-research`
(this repo's own `docs/research/`), `kbg-memory` (this repo's own memory store), `llm-wiki` (the
operator's personal knowledge vault, 1,600+ docs spanning every project, when it exists on this
machine), plus other project-specific collections. Run `qmd status` (or the `status` MCP tool) for
the full current list; scope a query to the relevant collections rather than searching all of them
blind.

**Why this line lives here, not in a skill:** kbg built exactly this qmd-first behavior once
already, vendored into a `research` skill — and two unrelated namespace-collision migrations
silently deleted it with nobody catching it — most recently the swap to
`mattpocock-skills:engineering/research`, which carries no qmd/context7 awareness. A skill file is exactly the
kind of surface an upstream resync can overwrite out from under you; `CLAUDE.md` isn't. The rule
lives here so it survives the next resync and applies to every research-shaped task.

**Cross-project reach:** this file only loads when cwd is `kbg-harness`, so the
operator's own `~/.claude/CLAUDE.md` (dotfiles-owned, not shipped with this plugin) carries a
thinner mirror of the `llm-wiki` half. `/mh:wiki-ingest` (user-invoked write path, `disable-model-invocation`) and
`mh:wiki-scan` (read-only health check) are the vault-touching surfaces; doctrine reasoning lives
in their own files.

<!-- Added v0.68.106. Live-fire confirmed 2026-07-30: a foreign-project session reached for `qmd`
scoped to `llm-wiki` unprompted — the one part of the design no grep or script could verify. -->

**Verify technical claims before shipping them into agent/skill content, not just when asked to
"research."** A confidently-worded complexity, security-mechanism, or framework-behavior claim can
read as correct and still be wrong — plausibility isn't verification. Before treating that kind of
addition as done: deep-read the relevant `qmd`/`llm-wiki` content first if either is configured on
this machine, then `WebSearch` (or the `deep-research` workflow for a claim worth a multi-source
adversarial pass). Claims that look obviously correct on read have shipped wrong before; each
needed an actual source check to catch it.

<!-- Confirmed load-bearing 2026-08-05 — caught 3 shipped, plausible-reading errors:
`performance-optimizer.md`'s two-pointer "O(n) 3-sum" (it's O(n²)), `drizzle-patterns`' "one query
per relation depth" for Drizzle's nested `with` (always exactly one query total), and a
CWE-1333/CWE-400 pairing contradicting MITRE's own page. -->

## Architecture

The plugin ships as `mh@kobig` from the `wasikarn/matt-harness` GitHub repo. Claude Code loads all surfaces from `~/.claude/plugins/cache/kobig/mh/<version>/` at startup. Nothing is symlinked.

The doctrine paragraphs below ("Doctrine injection" through "When hooks are wired") are also copied verbatim into `docs/reference/operating-model.md` — a self-contained, operator-path-free excerpt that runtime surfaces (`recursive-improve`, `orchestrate/reference.md`, `reasoning-models.md`) `cat` instead of this whole file (ticket 94, spec 75). No machine check enforces the two staying identical — keep them in sync by hand if either changes.

**Doctrine injection:** `hooks/session/doctrine-bootstrap.sh` fires on SessionStart and injects `docs/METHODOLOGY.md` (decision-sizing triad + reasoning scaffold) into session context via `$CLAUDE_PLUGIN_ROOT` (the plugin install dir; the older `$CLAUDE_PLUGIN_DIR` name is not a real CC variable and expands empty).

**Operating model:** deny the irrecoverable set computationally (gates in `hooks/gates/`), advise on the rest (sensors in `hooks/advisory/`). Advisory sensors never emit `permissionDecision`. The L2–L5 autonomy ladder is retired. Anthropic states this same deny-vs-advise split as platform guidance, not just kbg's own doctrine: *"To block an action regardless of what Claude decides, use a PreToolUse hook instead"* (`code.claude.com/docs/en/memory.md`, confirmed 2026-08-20) — CLAUDE.md/memory are context the model can weigh; a hook is the only layer that can't be argued with.

**Why — the unifying crux:** the gate is a *verifier* (deterministic shell returning a branchable **score**), the model is the *maker*, and the maker can never grade its own work — an LLM judging its own output is circular ("two optimists agreeing"). So advisory sensors journal but never gate, and the autonomy ladder had to retire: a model-as-gate is the maker appointing its own verifier. **Score, not feel** — every loop's stop condition must be a number a deterministic gate can branch on, never a vibe the model rationalizes. (This is the agent-loop verifier-separation principle; see `docs/research/` + the retired L2–L5 build for the proven failure it prevents.)

**Same crux, N-worker fan-in:** when parallel subagent outputs feed one synthesis/judge call, the merge is the same problem — dropping malformed entries and surfacing agreement/conflict is deterministic code's job, not the synthesizing model's. A fixed instruction is a fallback only where no code layer exists to hold a real reducer (a markdown-only skill like `bug-sweep`/`ideate` has no backing script — the dispatching model's own step-by-step discipline is the only mechanism available there); it is not an equivalent-strength substitute for code where a script already exists, and doctrine text should say plainly which one a given fix actually is. Default: never silently blend or drop overlap. `memory-lint`'s pattern-cluster mode and `deep-research.js`'s claim-dedup step (both pure code, zero LLM calls inside the reduction itself) are the real reference implementations. `skills/workflow/orchestrate/reference.md`'s `fan-out-and-synthesize` row enforces the same discipline via prompt instruction instead — real and load-bearing, but a weaker mechanism than code, and should be named as such rather than blurred together with it. The context-economy cost of a synthesis call reading unfiltered fan-out output is covered by `docs/METHODOLOGY.md` Rule 13's context-economy block.

<!-- Gap confirmed 2026-08-17: `bug-sweep`'s Consolidate step and `deep-research.js`'s Synthesize step
both silently blended before the first fix; a follow-up audit found that fix was itself mostly
prompt-only and had missed cutting what a downstream synthesis call has to read. -->

When hooks are wired: gates/ (deny), advisory/ (journal), session/ (inject), stop/ (cost tracking).

## Skill authoring doctrine (matt-pocock)

When creating or editing a skill under `skills/`, follow matt-pocock's `writing-for-agents` doctrine (leading words, one trigger per branch, completion criterion + demand, no-op test, progressive disclosure across the two loads) — canonical: the `mattpocock-skills:writing-for-agents` skill (model-invocable; renamed from `writing-great-skills` in matt v1.2.0, no alias — the old "two-cuts" and "failure-mode guard" labels no longer exist as named terms; their content dissolved into the rewrite's prose). The ≤25-word description cap is kbg's own token-budget rule ("Skill descriptions load on every Task spawn" below), not matt's.

<!-- Misattributed to matt here until 2026-08-10. -->

See `docs/skill-authoring-conventions.md` for the kbg-specific additions on top of that (harness-audit check 34's proxy coverage, Named Model footers, Suggested next step footers, AskUserQuestion-escalation criteria) — only load it when actually authoring or editing a skill/command/agent's content.

## Branching model

Single branch: `develop` only. No feature branches. Commit and push direct — "direct" means no
PR/feature-branch flow; *when* to push still follows the global confirm-before-push policy
(`~/.claude/CLAUDE.md` § Background Session Git Discipline).

**Computationally enforced for the Bash entry point only** by the `git worktree add -b` block in
`gate:bash:irrecoverable` (`PreToolUse:Bash`). Opt-in per repo via a `/.kbg-no-worktree` or
`/.mh-no-worktree` sentinel (the gate accepts either name — expand, not rename, so a sentinel
file already dropped into some other repo under the old name keeps working) — present in the
matt-harness repo, absent from other client/ECC/scratch repos (which keep their existing
`gate:write:worktree-guard` redirect). (The former allowlist for detached `review-pr-<N>`
worktrees was removed with the review pipeline, 2026-08-24 #82.)

**Not covered: the native `claude --worktree <name>` CLI flag**
(`code.claude.com/docs/en/common-workflows.md`, confirmed 2026-08-20 — the doc's own recommended way
to run a parallel session). It never routes through the Bash tool, so the gate above never sees it. A
prior companion gate on the native `WorktreeCreate`/`WorktreeRemove` events was removed 2026-07-31 —
its deny logic was dead code (those events never send `tool_name`/`tool_input`) and would have
silently broken every legitimate worktree creation if left registered, so removing it was correct;
but it means this doctrine's coverage was never — and still isn't — anything more than the literal
`git worktree add -b` typed into Bash. Full writeup: `docs/research/official-docs-audit-2026-07-31.md`.

**Also not covered: the PowerShell tool.** `irrecoverable.sh` (this gate, plus the other 2
`PreToolUse (Bash)` deny/ask gates — `verifier-protect.sh`'s Bash leg,
`worktree-guard.py`'s Bash branch) matches on the `Bash` tool only. `tools-reference.md:361`
(confirmed 2026-08-20) prescribes matching `Bash|PowerShell` for any hook inspecting shell
commands — deliberately not done here, since a matcher-only fix would claim coverage this repo's
POSIX-specific deny logic doesn't have and can't be tested on this dev box. See
`docs/reference/hook-lifecycle-contracts.md` for the full note.

**`/branch` and `claude --continue --fork-session` are session branches, not git branches** —
they fork the conversation (try a different approach, keep the original session intact) without
touching the filesystem's single-`develop`-branch model above. Neither interacts with the
worktree gate; both are safe to reach for when you want to try something without losing your
place, and neither is a substitute for the git-branch discipline this section enforces.

**Never run `mattpocock-skills:git-guardrails-claude-code`'s setup in this repo (prose-only — no check blocks it).** It wires a PreToolUse hook blocking *all* `git push` unconditionally (not just `--force`) — direct conflict with this section's workflow. Not installed here — a standing caveat, not an active problem.

<!-- Verified 2026-08-01. -->

### Concurrent sessions

The single-branch, no-worktree design above means concurrent Claude Code sessions on this repo share one working tree — there's no isolation to fall back on, so discipline has to substitute for it:

- **Stage by explicit path only** (see "Stage by name" below) — before staging, run `git status --porcelain` and confirm every listed file is one you actually touched this session. A file you don't recognize is probably another session's in-progress work, not junk.
- **Re-read `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` immediately before writing a commit message that references the version** — another session may have bumped it since you last checked, and a stale version number in a commit message is worse than no version number. This works because Claude reads files fresh on every tool call, so a `Read` here always sees whatever the other session last wrote (`code.claude.com/docs/en/common-workflows.md`, confirmed 2026-08-20) — the mechanism this whole bullet list quietly depends on.
- **A scratch/workspace dir reappearing after you thought it was cleaned up** (e.g. a fixture workspace, `skills/pr-workspace/`) is a signal another session owns it right now — leave it alone rather than deleting or restaging over it.
- **`/rewind` can revert another session's work, not just your own** — if two sessions edit the same file, a Restore-code in one can silently undo the other's in-flight changes. It's the one operation nobody here treats as destructive; check `git status` before trusting it in a shared-working-tree session, and recover through git if it did.

## Non-obvious gotchas

Grouped by behavior area (not a flat bucket — find the group first, then the line).

### Repo & commit hygiene

- **Hardcoded home paths blocked:** `.sh`/`.py` files must use `$HOME` or `~`, never `/Users/<name>`. This repo is **public** — committed text files (`.md`/`.json`/`.yaml`/`.txt`) must not carry this machine's literal home path either (use `~`; `/Users/<name>` placeholder text is fine). Enforced twice: staged files by the pre-commit gate (`git-hooks/pre-commit` Layer 1), all tracked files by the gauntlet's path-hygiene layer (pre-push). Paths that are operator-layout-specific (like the composer-source clones) are fine in operator-facing files but don't present them as universal in reader-facing docs.
- **Never `rm -rf`:** use `trash` (or `trash-put` on Linux; neither installed → ask the user) for deletions. Enforced by `hooks/gates/irrecoverable.sh`, whose deny message names whichever CLI the machine actually has.
- **Never `--no-verify`** on commits or pushes. Enforced by `hooks/gates/irrecoverable.sh`.
- **Stage by name:** never `git add -A` or `git add .`. Enforced by `hooks/gates/irrecoverable.sh`.

### Plugin lifecycle & install

- **`defaultEnabled: false`:** plugin ships disabled. After install, add `"mh@kobig": true` to Claude Code `settings.json`, then restart.
- **Cache-invalidation:** same-version edits are no-ops. Always bump both manifests before `claude plugin update` (enforced by `git-hooks/pre-commit`'s version-bump layer: shipped-surface files staged ⇒ `plugin.json` version must change in the same commit, and both manifests' versions must agree — deletions count too). CLAUDE.md-only edits skip the bump — dev-facing repo guidance, **deliberately outside the gate even though** two shipped skills do cat it from the cache (`recursive-improve/SKILL.md`, `orchestrate/reference.md`), so their cached copy can lag the repo; that staleness window is the accepted trade for not bumping on every guidance edit (documented 2026-08-21, compliance-audit finding). Runtime-loaded means the 5 surface dirs (`agents/`/`skills/`/`hooks/`/`output-styles/`/`themes/`) **plus** `scripts/**`, `contexts/`, `docs/METHODOLOGY.md`, and `docs/reference/**` — doctrine-bootstrap and decide/score-decision read the docs from the versioned cache at runtime, shipped skill scripts source `scripts/_lib/*.sh` relative out of the cache, workflow runners under `scripts/workflows/` are invoked by cache path from other projects, and `frame.md` cats `contexts/*.md` via `${MH_PLUGIN_ROOT}` — so the gate covers all of them (scripts/+contexts/ added 2026-08-21 after three scripts/-only commits silently never reached the installed cache); other cached content sits outside the gate with the same accepted staleness window: `BOUNDARY.md` (its former cache-readers, `kbg-help` and `inventory`'s wrapper docs, were removed 2026-08-24 #80) and `docs/research/kbg-vs-adhd.md` (cache-read by `ideate`'s provenance references) — known gap, widen the gate only as a deliberate policy change, not silently.

<!-- Gate enforced since 2026-08-09. -->

- **Re-verifying a same-session edit to any surface:** don't hand a re-verification agent a name-based reference — `Skill(<name>)`, `subagent_type: <name>`, or the slash command — to test an edit that hasn't been bumped/reinstalled yet. `agents/` and `skills/` all ship in the same versioned bundle, so any of those resolutions silently tests stale cached content with no error. Instruct the agent to `Read` the repo path directly instead.

<!-- Confirmed 2026-07-27 (tech-humanize v0.68.59: a false "fix confirmed" via `Skill(kbg:tech-humanize)`). -->

- **`BOUNDARY.md` regen:** `bash skills/inventory/scripts/inventory-witness.sh [<output-path>]` — it writes the snapshot directly to `<output-path>` (default `claude/BOUNDARY.md`, relative to cwd); only status messages go to its own stdout. Pass the real target path explicitly (e.g. `... inventory-witness.sh BOUNDARY.md` from repo root) — don't redirect stdout, that captures only the status lines, not the boundary content. Drift is caught (not prevented) by harness-audit check 16 (`16-boundary-md-drift-committed-capability-m.sh`), which WARNs.
- **The same-version stale trap applies to third-party plugins too, not just kbg's own.** Confirmed 2026-08-01: `mattpocock-skills` was 3 commits behind its own upstream while `claude plugin update` reported "already at the latest version" — upstream hadn't bumped its `plugin.json` version string, so the version-keyed update correctly saw nothing to do. Fix: `claude plugin uninstall` → `trash ~/.claude/plugins/cache/<publisher>/<plugin>/<version>` → `claude plugin install` (verify `gitCommitSha` in `installed_plugins.json` against the local clone's `git rev-parse HEAD`). Worth running periodically for any plugin whose upstream doesn't reliably bump versions on content changes.
- **Output style:** `output-styles/staff-eng.md` is the sole live-response register — its internal "Calibrate to stakes" rule self-calibrates terse vs full decision-framing (the old two-file split was collapsed 2026-07-02). `force-for-plugin: true` auto-activates it whenever `mh@kobig` is enabled, overriding the user's own `outputStyle` setting — you can't run a different style while this plugin is on without disabling it first.

### Session environment quirks

- **Working frames:** `contexts/` holds `dev.md`, `review.md`, `research.md` — loaded by `mh:frame` to set session posture.
- **`grep` is aliased** to `rtk grep` in this environment. Use `/usr/bin/grep` or `awk` for count/stat operations.
- **`/context` verifies what actually loaded** — run it and check the **Memory files** list to confirm a CLAUDE.md, rule, or nested instruction file loaded at all. Cheaper than reasoning about it from the doc: use it whenever a load is in doubt (a new `paths:` rule, a nested-directory CLAUDE.md, the two user-level rules below). `hooks/session/instructions-loaded-journal.sh` (`InstructionsLoaded` event) is the persistent, queryable version of the same fact — `~/.local/share/kbg/metrics/instructions-loaded.jsonl` — for when you need history, not just the current session's snapshot.
- **Two user-level Claude Code rules load into every session here, not just this repo:** `~/.claude/rules/{test-honesty,code-review-graph}.md` (symlinked from dotfiles, not tracked in this repo). Per `code.claude.com/docs/en/memory.md` (confirmed 2026-08-20), user-scope rules load before project rules and this repo has zero project rules to outrank them — a project `.claude/rules/` file added later would take priority automatically. `test-honesty.md`'s `paths:` includes `"**/*.py"` (all Python, not just tests), so it injects a test-honesty checklist whenever an agent reads any `.py` file in this repo, including non-test scripts like `hooks/gates/worktree-guard.py` or `memory-lint.py`. Harness-audit check 27 is that rule's commit-time backstop.

### Skill/agent/command mechanics & routing

- **Skill descriptions load on every Task spawn** (~words×1.3 tokens). Keep descriptions ≤25 words.
- **Thinking models:** default is the triad + `advisor()` inline (METHODOLOGY Rule 1); `mattpocock-skills:grilling` is the on-demand escalation for genuinely hard/contested-diagnosis choices (the former `decide` skill was de-scoped 2026-07-02 — 0 real-world invocations vs 55 `advisor()` calls across 182 sessions — and deleted 2026-08-24, #79). The 39 named mental models are cataloged in `docs/reference/reasoning-models.md`, which points to the upstream cc-thinking-skills repo for full write-ups — the 42-file vendored local copy under `docs/reference/thinking-skills/` was removed 2026-08-24 (ticket 94, operator-only reference surface); the harness-audit check that used to guard against re-vendoring it into `skills/` (formerly check 41, ticket 94's stub) was deleted 2026-08-25 as part of ticket 87's ghost-check cleanup, since there's no local tree left to promote from.
- **`disable-model-invocation: true`:** carried by 10 skills (`recursive-improve`, `score-decision`, `ship-merge`, `ideate-search`, `tiered-pipeline`, `wiki-ingest`, `address-review`, `post-mortem`, `ship-release`, `compliance-audit`) — no commands carry it any more. `ask-kbg` and `iterate-skill/COMMAND.md` were deleted 2026-08-24 (#80); `ship/COMMAND.md` was deleted 2026-08-24 (#86, matt-harness migration — `/mattpocock-skills:implement` covers the job now); `ship-merge` (#103), `ideate-search` (#105), `tiered-pipeline` and `wiki-ingest` (#107), `address-review` (#108), `post-mortem` (#109), `ship-release` (#110) all converted 2026-08-25, commands→skills convergence, spec #101. `compliance-audit` was also deleted 2026-08-24 (#80) and restored 2026-08-25 as a skill alongside `agents/plan-reviewer.md` — both were judged wrongly removed on the mistaken premise that two other installed skills covered the same job (see the "Plan → implement" / "Implementation → verify" rows of `docs/reference/decision-doctrine-map.md` for which ones and why they don't). Re-check via the frontmatter-scoped sweep (a bare `grep -rl` misreports: surfaces that only *mention* another one's flag in prose also match): `for f in skills/*/*/SKILL.md; do [ -f "$f" ] && head -20 "$f" | grep -qF 'disable-model-invocation: true' && echo "$f"; done`. 3 of the 10 carriers are **CRIT**-guarded against a rewrite silently dropping the flag: `recursive-improve/SKILL.md` (check 36), `score-decision/SKILL.md` (check 45), `ship-merge/SKILL.md` (check 40); the other 7 carriers have no equivalent guard yet. Check 30 only WARNs that a `-reason` field exists — it's the presence-of-reason check, not the flag-survives-a-rewrite check; the three CRIT checks are what close that gap.

<!-- The both-surface-types line caught 2026-07-22, not folded back here until 2026-08-04. -->
- **`orchestrate` vs deciding:** orchestrate decides whether/how to spend effort on an ask (inline/parallel/sequential/drop, which surface receives it) *before* it's understood as a bounded decision; a bounded question you're already committed to answering is reasoned through directly under METHODOLOGY Rule 1 (triad + `advisor()`, `mattpocock-skills:grilling` for hard/contested calls). A pile of competing asks routes through `orchestrate` first.
- **`SKILL.md` frontmatter ≠ `agents/*.md` frontmatter:** the real skill-file field for tool control is `allowed-tools` (pre-approves without asking; skills have no hard-restriction field), not `tools:` — that's the `agents/*.md` subagent field (hard-restricts to a fixed set). Confirmed against the official `skills.md` reference and the CLI binary's compiled schema keys. `metadata` / `metadata.origin` / `disable-model-invocation-reason` are non-standard-but-harmless kbg conventions — unrecognized frontmatter keys warn, never error, and carry zero behavioral effect.
- **`/goal` vs `goal-craft`:** `/goal` is Claude Code's own native completion-condition loop (v2.1.139+, judged each turn by a separate small model). kbg never wraps or auto-invokes `/goal` — the user always types it themselves, no exceptions (prose-only; holds because no fleet surface is written to call it). `skills/goal-craft` only composes a paste-ready condition string (one-way-door screen + turn bound); model-invocable since 2026-07-08, but the string is inert until the user pastes it after `/goal`. Auto-dispatch (`claude -p "/goal ..."`) stays a deliberate non-goal — it reopens the retired "no model self-start" invariant.

# Compact instructions

When compacting, preserve: which files are staged/committed vs. still pending this session, the
current plugin version state (bumped or not since the last shipped-surface edit), any open
plan-mode approval, and file:line citations already independently verified this session. Drop
resolved tool-call output and superseded draft text.
