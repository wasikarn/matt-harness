# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Validation (run before committing)

```bash
claude plugin validate . --strict
```

The plugin manifest is the primary validation gate. `scripts/run-gauntlet.sh` runs everything
in parallel: plugin-validate, full shell-lint, JSON lint, harness-audit, and the behavioral
test suite. Shell tests run via a for-loop; 2 Python files (memory-lint, compress-docs
verify-preserved) and 1 node file (tiered-pipeline) run via separate `if` blocks. The
script's `run_hook_tests()` is the authoritative file list — counts drift, so none is stated
here. The old 204-test critical-hooks suite and eval dataset gate were deleted, not rebuilt, in
the 2026-06-27 owner-authorized reset (`c452102`; recovery anchor if ever wanted: `24d7663`):
most of what they tested was L3/L4/L5 autonomy machinery retired by ADR 0006, and current
coverage already exceeds them.

## Adding or removing a surface

Auto-discovered directories this plugin currently uses: `agents/`, `skills/`, `hooks/`,
`output-styles/`, `themes/` (`commands/` retired as a surface type 2026-08-25, #112) — this is
"the 5 this plugin ships," not an exhaustive list of what Claude Code plugins support more
broadly (`workflows/`, `.mcp.json`, `.lsp.json`, `monitors/monitors.json`, `bin/`, and a
plugin-root `settings.json` are also real, just unused here — confirmed against
`code.claude.com/docs/en/plugins-reference.md`, 2026-08-29). Drafting a brand-new skill's
content from scratch (the interview → draft SKILL.md → eval → iterate loop) is what the
installed `skill-creator:skill-creator` skill is for — run that first, then continue with
step 1 below for the file's placement and step 3 onward for shipping it; skill-creator has
no awareness of this repo's own manifest/version-bump/BOUNDARY.md ritual. The step-by-step
(inlined from the removed `add-surface` skill, 2026-08-24 #80):

1. Create/remove the file(s), following the pattern of an existing component in the same
   directory. **Skills and agents bucket differently — don't apply one rule to both.** A
   **skill** buckets by folder placement (`skills/<bucket>/<name>/SKILL.md`); an **agent** needs
   `bucket:` frontmatter instead (`agents/*.md` stays flat). Full bucket lists, the harness-audit
   checks that enforce each (check 05 for skills, check 04 for agents), and the brand-new-
   top-level-bucket `plugin.json` gotcha: `docs/reference/surface-buckets.md`.
2. Hooks: register/deregister in `hooks/hooks.json`; add tests for any gate. After removing
   a hook's test section, grep the ENTIRE test file (not just the deleted section) for every
   shared helper function's name and remove any with zero remaining callers.
3. Bump both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions.
   Same-version edits to a cached plugin are silent no-ops.
4. Run `bash skills/inventory/scripts/sync-fleet-counts.sh` to patch the "N skills · M
   agents" pair into `plugin.json`/`marketplace.json`/`README.md`. A new **agent** also
   needs two hand edits the script can't reach: `skills/workflow/orchestrate/reference.md`'s
   named routing table + "N-agent survivor set" count, and the count mention in
   `docs/agent-voice-extension.md`.
5. Run `claude plugin validate . --strict`, then `bash
   skills/meta/harness-audit/scripts/audit.sh` and fix any WARN. A CRIT F1 ("not loadable")
   for a brand-new component is expected here; it clears at step 6.
6. `claude plugin update mh@wasikarn` **before** committing. The pre-commit hook's
   harness-audit F1 check only sees the latest *cached* plugin version, so a brand-new file
   blocks as CRIT F1 until this refreshes the cache.
7. Regenerate `BOUNDARY.md` (see the regen gotcha under "Plugin lifecycle & install" below),
   commit, push, restart Claude Code.

## Finding a surface

Read `BOUNDARY.md` first: the generated, always-current index of every agent, skill,
command, and hook, grouped by `bucket:` (skills and agents) since schema v5. Then the
specific `SKILL.md`/agent file for detail. Routing questions go to
`/mattpocock-skills:ask-matt`. The former kbg router layers (`/kbg-help`, `/kbg:ask-kbg`)
were removed 2026-08-24 (#80).

## Git hooks

Hooks live in `git-hooks/` (not `.git/hooks/`). Wire once per clone:

```bash
git config core.hooksPath git-hooks
```

**Keep that path RELATIVE.** An absolute `core.hooksPath` dies silently the moment the working
directory is renamed or the repo is re-cloned elsewhere: git does not warn when `core.hooksPath`
points at a directory that no longer exists — it just runs no hooks. Confirmed 2026-08-26, when
renaming this clone `kbg-harness` → `matt-harness` left the config pointing at the old absolute
path; one commit and one push then completed with **zero** gates (both happened to be clean, and
the gauntlet re-run afterwards confirmed it, but nothing would have caught a bad one). A relative
`git-hooks` resolves from the repo root and survives any rename. Verify with
`test -d "$(git config core.hooksPath)"` — the check is cheap and the failure mode is invisible.

pre-commit is the fast gate: syntax/lint (`bash -n` + shellcheck), JSON validation, CRITICAL
harness-audit (graceful-skip if absent), and the new-file LOC gate. That gate hard-blocks a
brand-new `agents/*.md` or `skills/*/SKILL.md` over 200 lines; editing an existing one past
the cap stays WARN-only via harness-audit check 55. `MH_SKIP_LOC_GATE=1` is the rescue
valve.
pre-push runs the full gauntlet (all validation layers in parallel).

## Composer-not-creator doctrine

Before writing a new skill, command, or agent from scratch, check sources in this order:

1. **`mattpocock/skills` first.** What's installed under the `mattpocock-skills@mattpocock`
   plugin (`claude plugin list` / the Skill tool's listing, namespaced
   `mattpocock-skills:<name>`), plus — if this machine has it — the local clone at
   `~/Codes/Personals/mattpocock-skills` for what's upstream but not yet installed. This is
   a **Matt-Pocock-first harness**; checking ECC/superpowers before matt's own repo gets the
   priority backwards. If the clone exists, `git fetch` it before trusting it: the installed
   plugin can be *newer* than the clone, inverting the "upstream but not yet installed"
   framing — confirmed the hard way once, when the clone silently lagged `origin/main` by a
   full minor release before anyone caught it. On a machine without these clones, the
   installed plugin alone is the available source — skip straight to it.
2. If present on this machine: the upstream ECC repo at `~/Codes/Personals/ECC` and the
   vendored superpowers checkout at `~/Codes/Personals/superpowers`.
3. If present: sibling harnesses under `~/Codes/Personals/` for structural patterns (e.g.
   `oh-my-claudecode`; ask if unsure which qualify).

Cherry-pick and adapt from whichever source fits; create kbg-native surfaces only when none
do. Skipping straight to (2) or (3) risks colliding with a skill matt already built — confirmed
2026-07-17, when `code-implementer`/`/implement` were built checking only (2) and (3), skipping
(1), and collided with matt's own `engineering/implement` skill (caught by the user, not by this
checklist). Paths are the stable anchor, not pinned hashes — run `git rev-parse HEAD` there when
you need the current commit. None of these clones is bundled with the plugin. On a machine
without them, (1)'s installed plugin is the only available source; build kbg-native only after
checking what it already offers.

**A clone reached via `claude --add-dir` instead of `cd` loads none of its own CLAUDE.md
instructions by default** — `--add-dir` grants file access only. Set
`CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` before the command if you need that clone's
own CLAUDE.md/rules read into context, not just its files.

### Vetting a new third-party plugin/skill before relying on it

Treat installing a skill like installing software — a skill gives Claude new capabilities
through instructions and code, so a malicious or careless one can direct tool/Bash use that
doesn't match its stated purpose (Anthropic's own Agent Skills security guidance). Before
relying on a **new** third-party plugin, MCP server, or skill for real work: read its
SKILL.md/scripts once for what network calls, file writes, or Bash commands it can actually
trigger. Full practice, scope, and the 2026-08-29 retroactive pass's findings:
`docs/reference/third-party-vetting.md`.

## Agent skills

### Issue tracker

GitHub Issues on `wasikarn/matt-harness` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary kept as-is. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — root `CONTEXT.md` + `docs/adr/` (neither exists yet; created lazily by
`mattpocock-skills:domain-modeling`). See `docs/agents/domain.md`.

## Research: check qmd before web search

Before starting primary-source research (fact-checking a claim, investigating a library/API,
verifying a citation): if a `qmd`-style MCP is configured, search the local `qmd` collections
first; if a `context7`-style MCP is configured, query it for any library/framework doc
lookup. Both come before `WebSearch`. Neither is bundled with this plugin — skip straight to
`WebSearch` when not configured.

Relevant collections when `qmd` is available: `kbg-research` (this repo's own
`docs/research/`), `kbg-memory` (this repo's own memory store), `llm-wiki` (the operator's
personal knowledge vault, 1,600+ docs spanning every project, when it exists on this
machine), plus other project-specific collections. Run `qmd status` (or the `status` MCP
tool) for the full current list; scope a query to the relevant collections rather than
searching all of them blind.

**Why this rule lives here, not in a skill:** kbg built exactly this qmd-first behavior
once already, vendored into a `research` skill — and two unrelated namespace-collision
migrations silently deleted it with nobody catching it, most recently the swap to
`mattpocock-skills:research`, which carries no qmd/context7 awareness. A skill
file is exactly the kind of surface an upstream resync can overwrite out from under you;
`CLAUDE.md` isn't. The rule lives here so it survives the next resync and applies to every
research-shaped task.

**Cross-project reach:** this file only loads when cwd is `kbg-harness`, so the operator's
own `~/.claude/CLAUDE.md` (dotfiles-owned, not shipped with this plugin) carries a thinner
mirror of the `llm-wiki` half. `/mh:wiki-ingest` (user-invoked write path,
`disable-model-invocation`) and `mh:wiki-scan` (read-only health check) are the
vault-touching surfaces; doctrine reasoning lives in their own files. Live-fire confirmed
2026-07-30: a foreign-project session reached for `qmd` scoped to `llm-wiki` unprompted — the
one part of this design no grep or script could verify on its own.

**Verify technical claims before shipping them into agent/skill content, not just when asked
to "research."** A confidently-worded complexity, security-mechanism, or framework-behavior
claim can read as correct and still be wrong — plausibility isn't verification. Before
treating that kind of addition as done: deep-read the relevant `qmd`/`llm-wiki` content
first if either is configured on this machine, then `WebSearch` (or the `deep-research`
workflow for a claim worth a multi-source adversarial pass). Claims that look obviously
correct on read have shipped wrong before, confirmed load-bearing 2026-08-05 by 3 caught
errors: `performance-optimizer.md`'s two-pointer "O(n) 3-sum" (it's O(n²)), `drizzle-patterns`'
"one query per relation depth" for Drizzle's nested `with` (always exactly one query total), and
a CWE-1333/CWE-400 pairing contradicting MITRE's own page. Each needed an actual source check
to catch it.

## graphify: architecture/relationship questions, not a qmd replacement

`graphify` (`~/.claude/skills/graphify/SKILL.md`, installed separately — not bundled with
this plugin) builds a knowledge graph from a corpus via AST + LLM semantic extraction, then
answers structural questions with `graphify query`/`path`/`explain`: who calls what, how
concept X connects to file Y, what code enforces a given doctrine. Head-to-head testing
against `qmd` on this repo (2026-08-31, 5-agent drill-down) found the two complementary, not
substitutes: qmd wins "why"/causal/historical questions (it retrieves prose that already
states the reasoning) and anything touching `llm-wiki` or the memory store, which graphify's
graph never covers; graphify wins "where does X live in code and what enforces it" —
extraction labels double as direct structural answers, uniquely bridging docs to code that
qmd's snippet search can't. Neither is a live index: qmd needs a manual `qmd update`/`embed`;
graphify needs a full or `--update` rebuild that dispatches LLM subagents for any changed
doc/paper/image — this repo's actual commit cadence is ~27 doc-type file changes/day, so
keeping the graph current recurs a real per-day token cost, not a one-time build.

**Gotcha:** if `graphify-out/graph.json` is missing, the next `/graphify` invocation
silently falls through to a full corpus rebuild instead of answering from cache — this
session's first full run cost ~4.6M output tokens across 31 parallel subagents (the
platform's 10-concurrent-agent cap forced 4 dispatch waves). Check the file exists before
invoking `/graphify` expecting a cheap query.

## Architecture

The plugin ships as `mh@wasikarn` from the `wasikarn/matt-harness` GitHub repo. Claude Code
loads all surfaces from `~/.claude/plugins/cache/wasikarn/mh/<version>/` at startup. Nothing is
symlinked.

**On a dev machine, the marketplace is often registered as a local directory, not the GitHub
repo** — which means `claude plugin update` can copy gitignored files (fixture workspaces,
`.DS_Store`) into the cache alongside shipped surfaces, and makes the cache look git-derived even
when it isn't. Full mechanics, the two consequences worth knowing, and why this never reaches
anyone installing from GitHub: `docs/reference/plugin-cache-mechanics.md`.

**Operating model:** deny the irrecoverable set computationally (gates in `hooks/gates/`),
advise on the rest (sensors in `hooks/advisory/`) — no autonomy flag, no maker-checker ship-gate,
no model self-start (the **no-model-self-start rule**).

**Why — the unifying crux:** the gate is a *verifier*, the model is the *maker*, and the maker
can never grade its own work — an LLM judging its own output is circular. **Score, not feel**:
every loop's stop condition must be a number a deterministic gate can branch on, never a vibe the
model rationalizes.

**Same crux, N-worker fan-in:** the same problem applies when parallel subagent outputs feed one
synthesis call — dropping malformed entries and surfacing agreement/conflict is deterministic
code's job, never the synthesizing model's.

`docs/reference/operating-model.md` is the canonical source for all three paragraphs above in
full (doctrine injection, the complete reasoning, the code-vs-prompt reference implementations)
— they used to be hand-copied here too with no machine check keeping the two in sync, and this
consolidation removes that duplication. Runtime surfaces (`recursive-improve`,
`orchestrate/reference.md`, `reasoning-models.md`) `cat` it directly via `${MH_PLUGIN_ROOT}`
(ticket 94, spec 75).

When hooks are wired: gates/ (deny), advisory/ (journal), session/ (inject), stop/ (cost tracking).

## Skill authoring doctrine (matt-pocock)

When creating or editing a skill under `skills/`, follow matt-pocock's `writing-for-agents`
doctrine: leading words, one trigger per branch, completion criterion + demand, no-op test,
progressive disclosure across the two loads. Canonical source: the
`mattpocock-skills:writing-for-agents` skill (model-invocable; renamed from
`writing-great-skills` in matt v1.2.0, no alias — the old "two-cuts" and "failure-mode
guard" labels no longer exist as named terms; their content dissolved into the rewrite's
prose). The ≤25-word description cap is kbg's own token-budget rule ("Skill descriptions
load on every Task spawn" below), not matt's.

See `docs/skill-authoring-conventions.md` for the kbg-specific additions on top of that
(harness-audit check 34's proxy coverage, Named Model footers, Suggested next step footers,
AskUserQuestion-escalation criteria). Load it only when actually authoring or editing a
skill/command/agent's content.

## Branching model

Single branch: `develop` only. No feature branches. Commit and push direct — "direct" means
no PR/feature-branch flow; *when* to push still follows the global confirm-before-push
policy (`~/.claude/CLAUDE.md`'s Background Session Git Discipline section).

**Computationally enforced for the Bash entry point only** by the `git worktree add -b`
block in `gate:bash:irrecoverable` (`PreToolUse:Bash`). Opt-in per repo via a
`/.kbg-no-worktree` or `/.mh-no-worktree` sentinel — the gate accepts either name (expand,
not rename, so a sentinel already dropped into some other repo under the old name keeps
working). Present in the matt-harness repo; absent from other client/ECC/scratch repos,
which keep their existing `gate:write:worktree-guard` redirect. The former allowlist for
detached `review-pr-<N>` worktrees was removed with the review pipeline, 2026-08-24 #82.

**Not covered: the native `claude --worktree <name>` CLI flag**
(`code.claude.com/docs/en/common-workflows.md`, confirmed 2026-08-20 — the doc's own
recommended way to run a parallel session). It never routes through the Bash tool, so the
gate above never sees it. A prior companion gate on the native
`WorktreeCreate`/`WorktreeRemove` events was removed 2026-07-31: its deny logic was dead
code (those events never send `tool_name`/`tool_input`) and would have silently broken every
legitimate worktree creation if left registered, so removing it was correct. But it means
this doctrine's coverage was never — and still isn't — anything more than the literal
`git worktree add -b` typed into Bash. Full writeup:
`docs/research/official-docs-audit-2026-07-31.md`.

**Also not covered: the PowerShell tool.** `irrecoverable.sh` (this gate, plus the other 2
`PreToolUse (Bash)` deny/ask gates — `verifier-protect.sh`'s Bash leg, `worktree-guard.py`'s
Bash branch) matches on the `Bash` tool only. `tools-reference.md:361` (confirmed
2026-08-20) prescribes matching `Bash|PowerShell` for any hook inspecting shell commands.
Deliberately not done here: a matcher-only fix would claim coverage this repo's
POSIX-specific deny logic doesn't have and can't be tested on this dev box. See
`docs/reference/hook-lifecycle-contracts.md` for the full note.

**`/branch` and `claude --continue --fork-session` are session branches, not git branches.**
They fork the conversation (try a different approach, keep the original session intact)
without touching the filesystem's single-`develop`-branch model above. Neither interacts
with the worktree gate; both are safe to reach for when you want to try something without
losing your place. Neither is a substitute for the git-branch discipline this section
enforces.

**Never run `mattpocock-skills:git-guardrails-claude-code`'s setup in this repo.** It wires a
PreToolUse hook blocking *all* `git push` unconditionally, not just `--force` — a direct
conflict with this section's workflow. Not installed here; a standing caveat, not an active
problem. The skill's install step is a Write/Edit to an existing `.claude/settings.json`
merging a new entry into `hooks.PreToolUse` — `config-write-guard.sh` (#98) now asks on
exactly that edit shape (any change to the `hooks` or `enabledPlugins` keys), so the mechanism
has a backstop; the instruction itself still stands regardless — the gate covers this one edit
shape, it doesn't make the workflow a fit for this repo's own hook architecture.

### Concurrent sessions

The single-branch, no-worktree design above means concurrent Claude Code sessions on this
repo share one working tree. There's no isolation to fall back on, so discipline substitutes
for it:

- **Stage by explicit path only** (see "Stage by name" below). Before staging, run
  `git status --porcelain` and confirm every listed file is one you actually touched this
  session. A file you don't recognize is probably another session's in-progress work, not
  junk.
- **Re-read `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` immediately
  before writing a commit message that references the version.** Another session may have
  bumped it since you last checked, and a stale version number in a commit message is worse
  than no version number. This works because Claude reads files fresh on every tool call, so
  a `Read` here always sees whatever the other session last wrote
  (`code.claude.com/docs/en/common-workflows.md`, confirmed 2026-08-20) — the mechanism this
  whole bullet list quietly depends on.
- **A scratch/workspace dir reappearing after you thought it was cleaned up** (e.g. a
  fixture workspace, `skills/pr-workspace/`) is a signal another session owns it right now.
  Leave it alone rather than deleting or restaging over it.
- **`/rewind` can revert another session's work, not just your own.** If two sessions edit
  the same file, a Restore-code in one can silently undo the other's in-flight changes. It's
  the one operation nobody here treats as destructive; check `git status` before trusting it
  in a shared-working-tree session, and recover through git if it did.

## Non-obvious gotchas

Grouped by behavior area (not a flat bucket — find the group first, then the line).

### Repo & commit hygiene

- **Hardcoded home paths blocked:** `.sh`/`.py` files must use `$HOME` or `~`, never
  `/Users/<name>`. This repo is **public** — committed text files
  (`.md`/`.json`/`.yaml`/`.txt`) must not carry this machine's literal home path either
  (use `~`; `/Users/<name>` placeholder text is fine). Enforced twice: staged files by the
  pre-commit gate (`git-hooks/pre-commit` Layer 1), all tracked files by the gauntlet's
  path-hygiene layer (pre-push). Both layers check three forms: the slash path, the
  dash-encoded path (`-Users-<name>-...`, how Claude Code keys a project dir), and the
  **bare account name** with no path around it — an author field, an `@<account>` doc
  owner, a `cache/<account>/` fragment written inside prose. The bare-name sweep is
  word-boundary and runs only when the account token is distinctive (at least 5 chars and
  not a common word like `dev` or `ubuntu`); when it cannot run safely it says so out loud
  rather than passing quietly, because a silent skip reads exactly like a clean repo.
  Operator-layout-specific paths (like the composer-source
  clones) are fine in operator-facing files, but don't present them as universal in
  reader-facing docs.
- **The frozen dirs are exempt from style sweeps, never from hygiene.** `docs/research/`,
  `docs/post-mortems/`, `docs/plans/` and `CHANGELOG.md` are left alone by wording passes
  because they are historical records. That carve-out does not extend to path or identity
  hygiene. On 2026-08-26 an account-name purge reported the repo clean while 29 occurrences
  sat in exactly those four places — the style carve-out had been read, silently and
  wrongly, as a hygiene carve-out too. A privacy constraint on a public repo has no frozen
  dirs.
- **Never `rm -rf`:** use `trash` (or `trash-put` on Linux; neither installed → ask the
  user) for deletions. Enforced by `hooks/gates/irrecoverable.sh`, whose deny message names
  whichever CLI the machine actually has.
- **Never `--no-verify`** on commits or pushes. Enforced by `hooks/gates/irrecoverable.sh`.
- **Stage by name:** never `git add -A` or `git add .`. Enforced by
  `hooks/gates/irrecoverable.sh`.

### Plugin lifecycle & install

- **`defaultEnabled: false`:** plugin ships disabled. After install, add `"mh@wasikarn": true`
  to Claude Code `settings.json`, then restart.
- **Cache-invalidation:** same-version edits are no-ops. Always bump both manifests before
  `claude plugin update`. The pre-commit version-bump layer enforces it: shipped-surface
  files staged ⇒ `plugin.json` version must change in the same commit, both manifests'
  versions must agree, and deletions count too. "Runtime-loaded" means the 5 surface dirs
  (`agents/`/`skills/`/`hooks/`/`output-styles/`/`themes/`) **plus** `scripts/**`,
  `contexts/`, `docs/METHODOLOGY.md`, and `docs/reference/**` — doctrine-bootstrap and
  decide/score-decision read the docs from the versioned cache at runtime, shipped skill
  scripts source `scripts/_lib/*.sh` relative out of the cache, workflow runners under
  `scripts/workflows/` are invoked by cache path from other projects, and `frame.md` cats
  `contexts/*.md` via `${MH_PLUGIN_ROOT}`. The gate covers all of them (scripts/+contexts/
  added 2026-08-21 after three scripts/-only commits silently never reached the installed
  cache). It also covers `docs/diagrams/*` (and the now-dead, glob-only `docs/diagrams/src/*`
  — that build-pipeline directory was removed in the 2026-08-28 diagram overhaul) —
  deliberately added in 949fcf44/97132587 (v0.68.512-513), but for a different reason than
  everything else on this list: nothing reads diagram content from the cache at runtime, this
  just keeps shipped documentation assets bumping the cache in step with executable surfaces.
  Confirmed live 2026-08-31: a `docs/diagrams/*`-only commit correctly blocked on an unchanged
  version. CLAUDE.md-only edits skip the bump, and that costs nothing at
  runtime: **no shipped surface reads CLAUDE.md from the cache.** Verified 2026-08-26 by
  grepping every surface dir for a `${MH_PLUGIN_ROOT}`/cache path ending in `CLAUDE.md`;
  zero hits. `recursive-improve/SKILL.md` and `orchestrate/reference.md` cat
  `docs/reference/operating-model.md` directly (the canonical source per the Architecture
  section's Operating model paragraph), and `docs/reference/**` already puts that file inside
  the gate. `BOUNDARY.md` also has no cache-readers left (`kbg-help` and `inventory`'s wrapper
  docs were removed 2026-08-24 #80). The one real staleness window is
  `docs/research/kbg-vs-adhd.md`, which `ideate/references/provenance.md` cats from the cache
  in three places while `docs/research/**` sits outside the gate. Known gap — widen the gate
  only as a deliberate policy change, not silently.

- **Re-verifying a same-session edit to any surface:** don't hand a re-verification agent a
  name-based reference — `Skill(<name>)`, `subagent_type: <name>`, or the slash command — to
  test an edit that hasn't been bumped/reinstalled yet. `agents/` and `skills/` all ship in
  the same versioned bundle, so any of those resolutions silently tests stale cached content
  with no error. Instruct the agent to `Read` the repo path directly instead. Confirmed
  2026-07-27: `tech-humanize` v0.68.59 got a false "fix confirmed" via
  `Skill(kbg:tech-humanize)`, which silently re-ran the stale cached version.

- **`BOUNDARY.md` regen:** `bash skills/inventory/scripts/inventory-witness.sh
  [<output-path>]` writes the snapshot directly to `<output-path>` (default
  `claude/BOUNDARY.md`, relative to cwd); only status messages go to its own stdout. Pass
  the real target path explicitly (e.g. `... inventory-witness.sh BOUNDARY.md` from repo
  root). Don't redirect stdout — that captures only the status lines, not the boundary
  content. Drift is caught (not prevented) by harness-audit check 16
  (`16-boundary-md-drift-committed-capability-m.sh`), which WARNs.
- **The same-version stale trap applies to third-party plugins too, not just kbg's own.**
  Confirmed 2026-08-01: `mattpocock-skills` was 3 commits behind its own upstream while
  `claude plugin update` reported "already at the latest version" — upstream hadn't bumped
  its `plugin.json` version string, so the version-keyed update correctly saw nothing to do.
  Fix: `claude plugin uninstall` → `trash ~/.claude/plugins/cache/<publisher>/<plugin>/<version>`
  → `claude plugin install` (verify `gitCommitSha` in `installed_plugins.json` against the
  local clone's `git rev-parse HEAD`). Worth running periodically for any plugin whose
  upstream doesn't reliably bump versions on content changes.
- **Output style:** `output-styles/crisp.md` is the sole live-response register — Claude
  Code's Concise contract as the base, staff-engineer decision-framing switched on by its
  "Calibrate to stakes" rule (renamed from `staff-eng.md` 2026-08-26; the old two-file split
  was collapsed 2026-07-02). `force-for-plugin: true` auto-activates it whenever `mh@wasikarn`
  is enabled, overriding the user's own `outputStyle` setting. You can't run a different
  style while this plugin is on without disabling it first.

### Session environment quirks

- **Working frames:** `contexts/` holds `dev.md`, `review.md`, `research.md`, loaded by
  `mh:frame` to set session posture.
- **`grep` is aliased** to `rtk grep` in this environment. Use `/usr/bin/grep` or `awk` for
  count/stat operations.
- **`/context` verifies what actually loaded.** Run it and check the **Memory files** list
  to confirm a CLAUDE.md, rule, or nested instruction file loaded at all. Cheaper than
  reasoning about it from the doc — use it whenever a load is in doubt (a new `paths:` rule,
  a nested-directory CLAUDE.md, the two user-level rules below).
  `hooks/session/instructions-loaded-journal.sh` (`InstructionsLoaded` event) is the
  persistent, queryable version of the same fact
  (`~/.local/share/kbg/metrics/instructions-loaded.jsonl`), for when you need history rather
  than the current session's snapshot.
- **Two user-level Claude Code rules load into every session here, not just this repo:**
  `~/.claude/rules/{test-honesty,code-review-graph}.md` (symlinked from dotfiles, not
  tracked in this repo). Per `code.claude.com/docs/en/memory.md` (confirmed 2026-08-20),
  user-scope rules load before project rules, and this repo has zero project rules to
  outrank them — a project `.claude/rules/` file added later would take priority
  automatically. `test-honesty.md`'s `paths:` includes `"**/*.py"` (all Python, not just
  tests), so it injects a test-honesty checklist whenever an agent reads any `.py` file in
  this repo, including non-test scripts like `hooks/gates/worktree-guard.py` or
  `memory-lint.py`. Harness-audit check 27 is that rule's commit-time backstop.

### Skill/agent/command mechanics & routing

Frontmatter field reference, `disable-model-invocation` carrier list, and routing distinctions
(`orchestrate` vs a bounded decision, `SKILL.md` vs `agents/*.md` frontmatter, `/goal` vs
`goal-craft`) moved to `docs/reference/skill-agent-mechanics.md` — pure lookup material, load it
when authoring/dispatching a skill or agent. One rule from it is load-bearing enough to keep
ambient: **Skill descriptions load on every Task spawn** (~words×1.3 tokens) — keep them
≤25 words.

# Compact instructions

When compacting, preserve: which files are staged/committed vs. still pending this session,
the current plugin version state (bumped or not since the last shipped-surface edit), any
open plan-mode approval, and file:line citations already independently verified this
session. Drop resolved tool-call output and superseded draft text.
