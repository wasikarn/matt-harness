# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Rules here are the ones that change behavior in the moment. The history, evidence, and
mechanics behind each live in `docs/reference/` — load the named file when you need detail.

## Validation (run before committing)

```bash
claude plugin validate . --strict
```

The plugin manifest is the primary validation gate. `scripts/run-gauntlet.sh` runs every
layer in parallel (plugin-validate, shell-lint, JSON lint, harness-audit, behavioral tests);
its `run_hook_tests()` is the authoritative test-file list. History of the retired suites:
`docs/reference/repo-gotchas.md`.

## Adding, removing, or finding a surface

Full 7-step ritual (file placement, `hooks.json`, manifest bump, fleet counts, audit,
`claude plugin update mh@wasikarn` **before** committing, `BOUNDARY.md` regen):
`docs/reference/adding-a-surface.md`. Skills bucket by folder, agents by `bucket:`
frontmatter: `docs/reference/surface-buckets.md`. To find a surface, read `BOUNDARY.md`
first (generated index of every agent/skill/hook), then the specific file. Routing
questions: `/mattpocock-skills:ask-matt`.

## Git hooks

Hooks live in `git-hooks/`. Wire once per clone with `git config core.hooksPath git-hooks`
and **keep that path relative** — an absolute path silently runs zero hooks after a rename
(verify: `test -d "$(git config core.hooksPath)"`). pre-commit = fast gate (lint, JSON,
CRITICAL harness-audit, new-file 200-LOC gate; `MH_SKIP_LOC_GATE=1` is the rescue valve).
pre-push = full gauntlet. Detail: `docs/reference/repo-gotchas.md`.

## Composer-not-creator doctrine

Before writing a new skill, command, or agent from scratch, check sources in this order:
(1) `mattpocock/skills` — the installed `mattpocock-skills@mattpocock` plugin, plus the local
clone at `~/Codes/Personals/mattpocock-skills` if present (`git fetch` it first; the installed
plugin can be newer); (2) `~/Codes/Personals/ECC` and `~/Codes/Personals/superpowers` if
present; (3) sibling harnesses under `~/Codes/Personals/`. Create kbg-native surfaces only
when none fit. Skipping (1) has collided with matt's own skills before. History, the
`--add-dir` CLAUDE.md-loading gotcha, and third-party vetting practice:
`docs/reference/composer-not-creator.md`, `docs/reference/third-party-vetting.md`.

## Agent skills

- **Issue tracker:** GitHub Issues on `wasikarn/matt-harness` via `gh`. See `docs/agents/issue-tracker.md`.
- **Triage labels:** default vocabulary kept as-is. See `docs/agents/triage-labels.md`.
- **Domain docs:** single-context — root `CONTEXT.md` + `docs/adr/` (neither exists yet;
  created lazily by `mattpocock-skills:domain-modeling`). See `docs/agents/domain.md`.

## Research: check qmd before web search

Before primary-source research (fact-checking, library/API investigation, citation
verification): if a `qmd`-style MCP is configured, search the local `qmd` collections first;
if a `context7`-style MCP is configured, query it for library/framework docs. Both come
before `WebSearch`. Neither is bundled — skip straight to `WebSearch` when not configured.
Run `qmd status` for the collection list and scope queries to the relevant ones.

**Verify technical claims before shipping them into agent/skill content**, not just when
asked to "research" — plausibility isn't verification. qmd/`llm-wiki` first, then
`WebSearch`. Why this rule lives here rather than in a skill (it was silently deleted twice by
resyncs), cross-project reach, and the 3 caught-wrong claims: `docs/reference/repo-gotchas.md`.

`graphify` (installed separately) answers "where does X live in code and what enforces it";
qmd answers "why." Check `graphify-out/graph.json` exists before invoking `/graphify` — a
missing file triggers a full multi-million-token rebuild. Detail:
`docs/reference/graphify-vs-qmd.md`.

## Architecture

The plugin ships as `mh@wasikarn` from the `wasikarn/matt-harness` GitHub repo. Claude Code
loads all surfaces from `~/.claude/plugins/cache/wasikarn/mh/<version>/` at startup. Nothing is
symlinked. On a dev machine the marketplace is often registered as a local directory, so
`claude plugin update` copies gitignored files into the cache:
`docs/reference/plugin-cache-mechanics.md`.

**Operating model:** deny the irrecoverable set computationally (gates in `hooks/gates/`),
advise on the rest (sensors in `hooks/advisory/`) — no autonomy flag, no maker-checker
ship-gate, no model self-start (the **no-model-self-start rule**). The gate is a *verifier*,
the model is the *maker*, and the maker never grades its own work; every loop's stop
condition is a number a deterministic gate can branch on (**score, not feel**). Same rule
for N-worker fan-in: dropping malformed entries and surfacing agreement/conflict is
deterministic code's job. Canonical source in full: `docs/reference/operating-model.md`.

When hooks are wired: gates/ (deny), advisory/ (journal), session/ (inject), stop/ (cost tracking).

## Skill authoring doctrine (matt-pocock)

When creating or editing a skill under `skills/`, follow `mattpocock-skills:writing-for-agents`
(leading words, one trigger per branch, completion criterion + demand, no-op test, progressive
disclosure). The ≤25-word description cap is kbg's own token-budget rule (**skill descriptions
load on every Task spawn**), not matt's. kbg-specific additions (harness-audit check 34 proxy
coverage, Named Model footers, Suggested next step footers, AskUserQuestion-escalation
criteria): `docs/skill-authoring-conventions.md`, load only when authoring. Frontmatter fields,
`disable-model-invocation` carriers, routing distinctions: `docs/reference/skill-agent-mechanics.md`.

## Branching model

Single branch: `develop` only. No feature branches. Commit direct; *when* to push follows the
global confirm-before-push policy. Enforced only for `git worktree add -b` typed into Bash
(`gate:bash:irrecoverable`; opt-in per repo via `/.kbg-no-worktree` or `/.mh-no-worktree`).
Not covered: native `claude --worktree`, the PowerShell tool. `/branch` and
`--fork-session` are session branches, not git branches. **Never run
`mattpocock-skills:git-guardrails-claude-code`'s setup here** (blocks all `git push`).

**Concurrent sessions share one working tree.** Stage by explicit path only after checking
`git status --porcelain` for files you don't recognize; re-read both manifests right before
writing a version into a commit message; a reappearing scratch dir belongs to another
session; `/rewind` can revert another session's work. Full coverage notes and discipline:
`docs/reference/branching-model.md`.

## Non-obvious gotchas

One line each; bodies in `docs/reference/repo-gotchas.md`.

### Repo & commit hygiene

- **Hardcoded home paths blocked** in every committed file (repo is public): use `$HOME`/`~`,
  never a literal `/Users/<name>`; the bare account name counts too. Frozen dirs
  (`docs/research/`, `docs/post-mortems/`, `docs/plans/`, `CHANGELOG.md`) are exempt from style
  sweeps, never from hygiene.
- **Never `rm -rf`:** use `trash` (or `trash-put` on Linux; neither installed → ask the user).
  Enforced by `hooks/gates/irrecoverable.sh`.
- **Never `--no-verify`** on commits or pushes. Enforced by `hooks/gates/irrecoverable.sh`.
- **Stage by name:** never `git add -A` or `git add .`. Enforced by `hooks/gates/irrecoverable.sh`.

### Plugin lifecycle & install

- **`defaultEnabled: false`:** after install, add `"mh@wasikarn": true` to `settings.json`, restart.
- **Cache-invalidation:** same-version edits are no-ops. Bump both manifests before
  `claude plugin update`; the pre-commit version-bump layer enforces it for the 5 surface dirs
  plus `scripts/**`, `contexts/`, `docs/METHODOLOGY.md`, `docs/reference/**`, `docs/diagrams/*`.
  CLAUDE.md-only edits skip the bump (no shipped surface reads it from the cache).
- **Re-verifying a same-session edit:** have the agent `Read` the repo path, never
  `Skill(<name>)`/`subagent_type`/slash — those silently test the stale cached version.
- **`BOUNDARY.md` regen:** `bash skills/inventory/scripts/inventory-witness.sh BOUNDARY.md`
  from repo root (it writes the file itself — don't redirect stdout).
- **Same-version stale trap applies to third-party plugins too:** uninstall → `trash` the
  cache dir → reinstall when upstream changes content without bumping.
- **Output style:** `output-styles/crisp.md` is the sole live-response register;
  `force-for-plugin: true` overrides the user's `outputStyle` while `mh@wasikarn` is enabled.

### Session environment quirks

- **Working frames:** `contexts/` holds `dev.md`, `review.md`, `research.md`, loaded by `mh:frame`.
- **`grep` is aliased** to `rtk grep`. Use `/usr/bin/grep` or `awk` for count/stat operations.
- **`/context` verifies what actually loaded** (check the Memory files list);
  `hooks/session/instructions-loaded-journal.sh` is the persistent version.
- **Two user-level rules load every session:** `~/.claude/rules/{test-honesty,code-review-graph}.md`;
  `test-honesty.md` fires on any `.py` read, not just tests.

# Compact instructions

When compacting, preserve: which files are staged/committed vs. still pending this session,
the current plugin version state (bumped or not since the last shipped-surface edit), any
open plan-mode approval, file:line citations already independently verified this session,
approaches or options raised, tried, or set aside and why, and anything the user asked for,
decided, ruled out, or set as a constraint, in their exact wording. Weight the two sides
differently: keep the user's words close to verbatim; condense the assistant's own reasoning
to what it concluded. Drop resolved tool-call output and superseded draft text.
