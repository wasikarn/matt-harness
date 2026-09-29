# Non-obvious gotchas: full bodies

`CLAUDE.md` keeps each rule as one line; the history and mechanics live here.

## Validation

`claude plugin validate . --strict` is the primary gate. `scripts/run-gauntlet.sh` runs three
layers in parallel: plugin-validate, lint (shell, Python, JSON, whole-tree home-path ban), and
every test under `tests/`. pre-push runs the gauntlet; pre-commit runs the fast subset (syntax,
shellcheck on staged `.sh`, JSON parse, the home-path ban, harness-audit CRIT only, and when a gate
is staged, `scripts/gate-canary.sh` against the index copy of `hooks/gates/`).

## Git hooks

Hooks live in `git-hooks/`, not `.git/hooks/`. Wire once per clone with
`git config core.hooksPath git-hooks` and **keep that path relative**. An absolute
`core.hooksPath` dies silently the moment the directory is renamed: git does not warn when the
path no longer exists, it runs no hooks. Confirmed 2026-08-26 when renaming this clone left one
commit and one push running zero gates. Verify with `test -d "$(git config core.hooksPath)"`.
Since GH #159 (v1.1.87), `.github/workflows/validate.yml`'s `gauntlet` job also runs
`scripts/run-gauntlet.sh` on every push/PR — a broken local `core.hooksPath` no longer means the
gauntlet silently never runs at all; CI still surfaces it, on the PR run, as a normal red
job (confirmed green on a real run 2026-09-12, no `continue-on-error` left). Since `develop`
became protected (2026-09-28, `docs/reference/branching-model.md`), that job is one of the 3
required status checks, so a red run blocks merge.

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
  2026-07-27: a false "fix confirmed" via `Skill(mh:tech-humanize)`).
- **A brand-new skill or agent no longer fails checks 02 and 03.** The plugin cache is built from
  committed state, so a component added after the commit the cache was built from cannot be in it.
  Checks 02 (skill loadability) and 03 (agent loadability) report such a component as INFO when its
  file is absent from the base commit: `gitCommitSha` in `installed_plugins.json` for the audited
  cache, else `origin/develop`; override `HARNESS_AUDIT_BASE_REF`. This holds after the PR merges
  and until the release is installed. CRIT returns only for a component that is on that commit but
  missing from the cache, and whenever the audited dir is not its own git toplevel or the base does
  not resolve. No hand-copy into the cache dir, no `~/.claude` symlink.
- **The plugin runs every hook machine-wide.** A gate crash locks out every session that has
  `mh@wasikarn` enabled, not just sessions in this repo. A missing sibling `.py` or lib module
  must fail open with a diagnostic, never exit non-zero.

## Session environment quirks

- **Bare `grep` is shadowed, for ordinary invocations, by Claude Code's own shell-snapshot shim**,
  not an rtk alias (no `rtk` reference exists in the snapshot function; a few flags like
  `--null`/`-Z` fall through to real grep). Use `/usr/bin/grep` or `awk` for count and stat
  operations.
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

## Changing a deny heuristic in a gate

Any change to how `hooks/gates/*.py` decides deny versus allow (a tokenizer step, a substitution
or redirect strip, a shell-syntax rule) needs a differential fuzz against current `develop` before
merge. Unit tests alone missed every bypass on the 2026-09-29 `irrecoverable.py` work (GH #184,
#185, #188, #189): three plans failed, PR #192 was closed after 3 validator rounds, and a
builder's self-check ("0 bypasses in 4032") was wrong each time.

- **Acceptance:** 0 commands that `develop` denies and the branch allows, apart from a category
  the PR names as intended. Over-denies are the safe direction and are reported, not blocking.
- **Oracle:** run the real shells (the system `/bin/sh`, bash 3.2, a current bash, dash, zsh, ksh)
  with argv-logging stubs, never one shell or argv0-based shell guessing: whether `{fd}>` is a
  redirect depends on the binary and version (GH #219).
- **Validator:** a fresh agent writes its own generator; the builder's generator is never reused.
- **A failing piece is dropped, not patched.** Shipping only the pieces that pass is how PR #208
  merged after PR #192 failed.
- **When the shell is ambiguous, check both readings; any deny wins** (GH #219).
- Attack strings live in files, never in Bash command text, and the gate only classifies them.
- **A word list one gate types by hand drifts from its sibling.** `subagent-git-guard.py`'s
  `_WRAPPER_WORDS` is a second copy of `irrecoverable.py`'s `PREFIX_WRAPPERS`; `rtk` reached the
  first list only after the guard let `rtk proxy git stash` through (deep-audit 4), and a glued
  `timeout=30` once broke the shared spawn regex. `tests/hooks/test-subagent-git-guard.sh` now fails
  when a `PREFIX_WRAPPERS` word is not a wrapper in the guard. A new copy of a list needs its own
  drift test, and a new word needs two awkward-shape cases per consumer: a glued `name=1`, and a
  multi-statement decoy (`<word> x && git stash && git status`), because a wider wrapper list can
  also hide the statements after it (the guard's walk ran across `;` to the last `git`).
