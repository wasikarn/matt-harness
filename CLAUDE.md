# CLAUDE.md

Map only. Each rule's history and mechanics live in `docs/reference/`; load the named file
when you need detail. `docs/METHODOLOGY.md` is injected whole at session start.

## Validation (run before committing)

```bash
claude plugin validate . --strict
bash skills/meta/harness-audit/scripts/audit.sh   # 0 CRIT required
```

`scripts/run-gauntlet.sh` runs plugin-validate, lint (shell + JSON), and `tests/hooks/*.sh` in
parallel; pre-push runs it. Skill tests: `tests/skills/harness-audit/test-harness-audit.sh`,
`python3 -m pytest tests/skills/memory-lint`, `tests/skills/test-cost-report.sh`.

## Git hooks

Hooks live in `git-hooks/`. Wire once per clone with `git config core.hooksPath git-hooks` and
keep that path relative; an absolute path silently runs zero hooks after a rename
(verify: `test -d "$(git config core.hooksPath)"`). Detail: `docs/reference/repo-gotchas.md`.

## Composer-not-creator doctrine

Before writing a new skill or agent, check in order: (1) the installed
`mattpocock-skills@mattpocock` plugin plus the local clone at `~/Codes/Personals/mattpocock-skills`
if present (`git fetch` it first); (2) `~/Codes/Personals/ECC` and `~/Codes/Personals/superpowers`
if present; (3) sibling harnesses under `~/Codes/Personals/`. Create a native surface only when
none fit. Detail: `docs/reference/composer-not-creator.md`.

## Authoring

Skills follow `mattpocock-skills:writing-for-agents`; descriptions are at most 25 words, third person
(they load on every Task spawn). Detail: `docs/reference/skill-authoring-conventions.md`,
`docs/reference/agent-authoring-conventions.md`. Routing questions: `/mattpocock-skills:ask-matt`.
Issue tracker: GitHub Issues on `wasikarn/matt-harness` via `gh`. Domain docs: root `CONTEXT.md`
plus `docs/adr/`, created lazily by `mattpocock-skills:domain-modeling`.

## Research: check qmd before web search

If a `qmd`-style MCP is configured, search its collections first (`qmd status` lists them); if
`context7` is configured, query it for library docs. Both come before `WebSearch`; neither is
bundled. Verify technical claims before shipping them into agent or skill content, not just when
asked to research. Detail: `docs/reference/repo-gotchas.md`.

## Branching model

Single branch: `develop` only. No feature branches; commit direct, confirm before push.
Concurrent sessions share one working tree: stage by explicit path after checking
`git status --porcelain`, and re-read both manifests before writing a version into a commit
message. Detail: `docs/reference/branching-model.md`.

## Architecture

Ships as `mh@wasikarn`; Claude Code loads it from `~/.claude/plugins/cache/<marketplace>/mh/<version>/`
at startup, nothing symlinked. Operating model: deny the irrecoverable set computationally
(`hooks/pretooluse-table.json`), the maker never grades its own work, score not feel. Detail:
`docs/reference/operating-model.md`. Env vars: `docs/reference/env-vars.md`.

## Non-obvious gotchas

- **Hardcoded home paths blocked** in every committed file (public repo): `$HOME` or `~`, never
  a literal `/Users/<name>`; the bare account name counts too. Frozen dirs (`docs/research/`,
  `docs/post-mortems/`, `docs/plans/`, `CHANGELOG.md`) are exempt from style sweeps, never hygiene.
- **Never `rm -rf`, `--no-verify`, or `git add -A`/`.`.** Use `trash` and stage by name.
  Enforced by `gate:bash:irrecoverable`; `git add -A` is allowed only mid-merge.
- **Same-version edits are no-ops.** Bump both manifests before `claude plugin update`; to
  re-verify a same-session edit, have the agent `Read` the repo path, never `Skill(<name>)`.
- **`grep` is aliased** to `rtk grep` in the operator's shell; use `/usr/bin/grep` or `awk` for
  counts.
