# Non-obvious gotchas: full bodies

Moved out of the root `CLAUDE.md` 2026-09-03. `CLAUDE.md` keeps each rule as one line; the
history, evidence, and mechanics behind each rule live here. Grouped by behavior area.

## Validation & test-suite history

The plugin manifest (`claude plugin validate . --strict`) is the primary validation gate.
`scripts/run-gauntlet.sh` runs everything
in parallel: plugin-validate, full shell-lint, JSON lint, harness-audit, and the behavioral
test suite. Shell tests run via a for-loop; a handful of Python files (memory-lint,
compress-docs verify-preserved, autotrigger events) run via separate `if` blocks. The
script's `run_hook_tests()` is the authoritative file list — counts drift, so none is stated
here. The old 204-test critical-hooks suite and eval dataset gate were deleted, not rebuilt, in
the 2026-06-27 owner-authorized reset (`c452102`; recovery anchor if ever wanted: `24d7663`):
most of what they tested was L3/L4/L5 autonomy machinery retired by ADR 0006, and current
coverage already exceeds them.

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

## Repo & commit hygiene

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

## Plugin lifecycle & install

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

## Session environment quirks

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

## Research doctrine: why the qmd-first rule lives in CLAUDE.md, not a skill

kbg built exactly this qmd-first behavior
once already, vendored into a research skill — and two unrelated namespace-collision
migrations silently deleted it with nobody catching it, most recently the swap to
`mattpocock-skills:research`, which carries no qmd/context7 awareness. A skill
file is exactly the kind of surface an upstream resync can overwrite out from under you;
`CLAUDE.md` isn't. The rule lives there so it survives the next resync and applies to every
research-shaped task.

Relevant collections when `qmd` is available: `kbg-research` (this repo's own
`docs/research/`), `kbg-memory` (this repo's own memory store), `llm-wiki` (the operator's
personal knowledge vault, 1,600+ docs spanning every project, when it exists on this
machine), plus other project-specific collections. Run `qmd status` (or the `status` MCP
tool) for the full current list; scope a query to the relevant collections rather than
searching all of them blind.

**Cross-project reach:** the root `CLAUDE.md` only loads when cwd is this repo, so the operator's
own `~/.claude/CLAUDE.md` (dotfiles-owned, not shipped with this plugin) carries a thinner
mirror of the `llm-wiki` half. `/wiki-ingest` (user-invoked write path,
`disable-model-invocation`) and `wiki-scan` (read-only health check) — both relocated from
this plugin to user-scope `~/.claude/skills/` 2026-09-01, since they are one-machine vault
infrastructure a public plugin shouldn't ship — are the
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
