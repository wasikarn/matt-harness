# Non-obvious gotchas: full bodies

`CLAUDE.md` keeps each rule as one line; the history and mechanics live here.

## Validation

`claude plugin validate . --strict` is the primary gate. `scripts/run-gauntlet.sh` runs three
layers in parallel: plugin-validate, lint (shell + JSON), and the hook tests under
`tests/hooks/*.sh`. pre-push runs the gauntlet; pre-commit runs the fast subset (syntax,
shellcheck on staged `.sh`, JSON parse, the home-path ban, harness-audit CRIT only).

## Git hooks

Hooks live in `git-hooks/`, not `.git/hooks/`. Wire once per clone with
`git config core.hooksPath git-hooks` and **keep that path relative**. An absolute
`core.hooksPath` dies silently the moment the directory is renamed: git does not warn when the
path no longer exists, it runs no hooks. Confirmed 2026-08-26 when renaming this clone left one
commit and one push running zero gates. Verify with `test -d "$(git config core.hooksPath)"`.

## Repo and commit hygiene

- **Hardcoded home paths blocked.** This repo is public. Every committed file uses `$HOME` or
  `~`, never a literal `/Users/<name>`; the bare account name counts too (an author field, a
  `cache/<account>/` fragment in prose). pre-commit checks staged files; the gauntlet checks
  the whole tree. The frozen dirs (`docs/research/`, `docs/post-mortems/`, `docs/plans/`,
  `CHANGELOG.md`) are exempt from wording passes, never from hygiene: on 2026-08-26 a purge
  reported clean while 29 hits sat in exactly those dirs.
- **Never `rm -rf`.** Use `trash` (`trash-put` on Linux; neither installed means ask the user).
  Enforced by `gate:bash:irrecoverable`. Validate the argument is non-empty before any `trash`
  call: an empty glob result once trashed the whole repo.
- **Never `--no-verify`.** Enforced by `gate:bash:irrecoverable`.
- **Stage by name.** Never `git add -A` or `git add .` outside a mid-merge state. Enforced by
  `gate:bash:irrecoverable`.

## Plugin lifecycle and install

- **`defaultEnabled: false`.** After install, add `"mh@wasikarn": true` to Claude Code
  `settings.json` and restart.
- **Same-version edits are no-ops.** Claude Code loads the plugin from
  `~/.claude/plugins/cache/<marketplace>/mh/<version>/` at startup; `claude plugin update`
  copies nothing unless `plugin.json`'s version changed. Bump both manifests before updating.
  This applies to third-party plugins too: `mattpocock-skills` once sat 3 commits behind
  upstream while `update` reported "already latest". Fix: uninstall, `trash` the cache dir,
  reinstall.
- **Re-verifying a same-session edit.** Have the agent `Read` the repo path; `Skill(<name>)`,
  `subagent_type`, or a slash command silently tests the stale cached version (confirmed
  2026-07-27: a false "fix confirmed" via `Skill(kbg:tech-humanize)`).
- **The plugin runs every hook machine-wide.** A gate crash locks out every session that has
  `mh@wasikarn` enabled, not just sessions in this repo. A missing sibling `.py` or lib module
  must fail open with a diagnostic, never exit non-zero.

## Session environment quirks

- **`grep` is aliased** to `rtk grep` in the operator's shell. Use `/usr/bin/grep` or `awk`
  for count and stat operations.
- **`/context` verifies what actually loaded.** Check the Memory files list before reasoning
  about whether a CLAUDE.md or rule file is in context.
- **Two user-level rules load every session:** `~/.claude/rules/{test-honesty,code-review-graph}.md`
  (dotfiles-owned). `test-honesty.md` fires on any `.py` read, not just tests.

## Research: check qmd before web search

The qmd-first rule lives in `CLAUDE.md`, not a skill, because a skill was the surface that two
namespace migrations silently deleted it from. Before primary-source research: search the local
`qmd` collections (`qmd status` lists them), then `context7` for library docs, then `WebSearch`.
Neither is bundled; skip straight to `WebSearch` when not configured.

**Verify technical claims before shipping them into agent or skill content.** Plausibility is
not verification. Three confidently wrong claims shipped and were caught only by a source check
(2026-08-05): a two-pointer "O(n) 3-sum" (it is O(n^2)), Drizzle nested `with` as "one query per
relation depth" (always one query), and a CWE-1333/CWE-400 pairing that contradicts MITRE's page.
