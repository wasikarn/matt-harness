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
There is no CI (GitHub Actions removed 2026-10-03), so a broken `core.hooksPath` means the gauntlet
never runs at all and nothing server-side notices. Run the verify command above after any rename.

## Repo and commit hygiene

- **Hardcoded home paths blocked.** This repo is public. Every committed file uses `$HOME` or
  `~`, never a literal `/Users/<name>`; the bare account name counts too (an author field, a
  `cache/<account>/` fragment in prose). pre-commit checks staged files; the gauntlet checks
  the whole tree. The frozen dirs (`docs/research/`, `docs/post-mortems/`, `docs/plans/`,
  `CHANGELOG.md`) are exempt from wording passes, never from hygiene: on 2026-08-26 a purge
  reported clean while 29 hits sat in exactly those dirs.
- **Never `rm -rf`.** Use `trash` (`trash-put` on Linux; neither installed means ask the user).
  Enforced by `gate:bash:irrecoverable`. Validate the argument is non-empty before any `trash`
  call: an empty glob result once trashed the whole repo. A template `mktemp -d "${TMPDIR:-/tmp}/x.XXXXXX"`
  prints "" when TMPDIR names a missing directory (a plain `mktemp -d` falls back on macOS), and `set -u`
  does not catch an empty variable, so a test hands such a path to `track_trash` from
  `tests/_lib/harness.sh`, never to `trash` (`tests/scripts/test-trash-empty-guard-lint.sh`).
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
- **Which mh copy runs after a restart.** `$MH_PLUGIN_ROOT` is a SessionStart snapshot, not proof.
  Read `mh_version` in this session's last row of `~/.local/share/kbg/metrics/costs.jsonl` that has
  one (a Codex row has none), or the version in the hook path Claude Code prints around a gate deny. `~/.claude/metrics/costs.jsonl` is a stale
  file with no `mh_version`. A wrong probe gave a wrong answer twice: the env var (2026-09-21) and the
  stale file (2026-09-30).
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
- **Piping a payload into a gate by hand writes to the real journal.** A denying gate appends to
  `~/.local/share/kbg/metrics/gate-decisions.jsonl` unless `MH_GATE_JOURNAL_PATH` is set, and a
  made-up `session_id` (`s`, `t`, `test-session`) passes `gate-report`'s session filter, so it is
  counted as a live event (159 of 161 `subagent-verdict-check` denies were these). Probe with
  `MH_GATE_JOURNAL_PATH=/dev/null` (or a scratch file when you want to read the row back), and
  use `scripts/gate-differential.sh` for old-vs-new comparisons, which already isolates it.

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

- **Tool:** `scripts/gate-differential.sh OLD [NEW] GATE` (GH #411; OLD a gates dir or a git ref such as
  `origin/develop`, GATE `irrecoverable`, `subagent-git-guard` or `secret-scan`) replays the committed
  fixtures, `--replay N` real commands from this project's transcripts only (secret-scan reads
  Write/Edit text) and `--fuzz-seed S` mutations through both copies. It compares exit, stdout,
  stderr and journal rows and prints diff classes with counts and 3 redacted samples, never raw
  transcript text. Both sides journal to a temp file under a temp HOME: earlier hand-built replays
  that did not isolate it left 268k session-less rows in the real journal. The fuzz is a few fixed
  rewrites; the real-shell oracle and a validator's own generator below still apply.

- **Acceptance:** 0 commands that `develop` denies and the branch allows, apart from a category
  the PR names as intended. Over-denies are the safe direction and are reported, not blocking.
  A timeout counts as allow: a hook past its `hooks.json` timeout (8 s) lets the call through, so
  a command `develop` denies in time and the branch does not finish in time is a regression. Time
  padded shapes (thousands of statements, 20-150 KB) with the target early and late (GH #245: a
  new scan placed before the fast denies turned a 0.03 s deny into a timeout). Any exit other than
  0 or 2 from the `.py` is a finding too, even where the `.sh` wrapper fails it closed.
  GH #340: `_AMBIG_NARROW_AFTER` had no `switch` piece, so a narrow ambiguity shape holding `git switch`
  raised KeyError (exit 1, an "internal error" deny). A sub word with no piece now counts as a hit, and a
  test checks the keys against `_AMBIG_GIT_SUB_RE`. A narrow piece is the only check that sees a
  substitution body, and its view reads `$'-f'` as `$-f` (no blank before the dash): a flag piece for
  switch let 14 fuzzed `$'-f'` commands through, so switch takes any form, like clean and restore.
  GH #349: the same `$-f` reading hid a quoted flag from push, reset, checkout, branch, stash and rm, so
  the check now also reads a fourth view with `$'..'` decoded and `$".."` read as `".."` (only when the
  command holds one). Its fuzz also found three pieces narrower than the main parser: reset now takes
  `--h`/`--har`, push a `+refspec`, and checkout a `.` that ends at `` ` `` or `)`. Fuzz, 4000 cases:
  false-allows 473 to 48, false-denies 66 to 111 (a `stash list ... drop` or a bare trailing `checkout --`
  in these shapes now denies). The 48 left are `checkout ./` and `branch -d -f`, which the main parser
  allows too.
  GH #274: `subagent-git-guard.py` also scans the raw command for `$(...)` / backtick bodies
  (`_substitution_bodies`, one linear pass) because the quote mask hides them. That pass reads a
  case pattern's `)`, `#` comments, `${x:-)}`, backslash escapes in backticks, `$'..'`, an
  apostrophe inside `"..."`, and heredocs. Every body copy and heredoc lookup charges the same
  budget. Its quote tracker must follow the shell's rules exactly: it once let an apostrophe inside
  `"..."` open a fake single-quote span that hid every later substitution. A heredoc it cannot
  read (odd delimiter, no terminator, `X)` where bash and a lenient reading disagree) is DENIED
  (`_Unparsed`), never scanned as code, because prose fed to the tracker as code desyncs it.
  Verify with a real-shell differential (sh/bash/zsh against a shim `git`), not by reading the
  code: 5 rounds each missed shapes the next found. The 27 real-shell cases that survived are
  committed (`tests/hooks/fixtures/subagent-git-guard-substitution-cases.txt`, replayed by
  `test-subagent-git-guard.sh`). Known residue: an `eval`/`sh -c` of a command's OUTPUT (data
  flow, undecidable), `bash -c 'sh -c ...'` (two shell levels, never covered), a quoted heredoc
  nested under a wrapper inside a quoted substitution (denied, a false positive), and a
  redirection before `git` (`<f git stash`, `$(<<a git stash)`), which `develop` also allows.
  Differential against `develop` (2026-10-01, #274/#280): a replay of 109,500 distinct Bash
  commands from local transcripts gave 0 newly denied, 0 exits other than 0/2 and a worst case of
  1.0 s. 20 commands were denied by `develop` and allowed by the branch: all are heredoc body text
  (commit messages, PR bodies, scripts) that `develop` denied for lack of heredoc parsing; with
  the bodies stripped `develop` allows every one. That is the named intended category. One shape
  inside it is a real change: `eval "$(cat <<'EOF' ... EOF)"` runs the body, so `develop` denied it
  only by accident and the branch allows it (data flow, undecidable). A replay finds shapes real
  commands already have: it caught a `"${x}"` counter bug, a too-broad terminator rule and a
  budget over-deny that the generated fuzz missed.
  Anchor regexes are quadratic (command starts x length): `subagent-git-guard.py` charges that
  bound to a shared budget and denies past it (GH #246: 30 KB of `env ; ` before a `git stash`
  timed out into allow). Only 3 of 2,581 replayed real commands (20-28 KB scripts) hit it.
  GH #248 added a third, lazy-walk pass (`*?` finds the FIRST target after a wrapper, where the
  greedy walk lands on the last), `{` + blank as a command start (GH #318: also a glued `{` that
  starts a word, since zsh runs `{git stash;}`; GH #317: the anchor scans read a backslash before
  an ordinary character as dropped, `g\it stash`, padding the word's front so offsets hold), and `xargs` in the spawn
  anchor's wrapper list only. Each pass charges the budget, so the guard's rose to 60M; a padded
  benign command of ~3,000 blank lines (spawn scan) or ~2,100-2,200 `{ ` units (both gates) is now refused.
  GH #276: the lazy pass can land on a wrapper argument spelled `git` (`sudo -u git env git stash`),
  so it keeps scanning forward for later `git` words in the same statement, one linear walk (a
  lookahead from every `git` re-read `git -C ` runs and took 11 s). Lazy pass only, so an unquoted
  `git log x git stash` now denies; deny-biased, accepted.
  Starts x length is not the whole cost: the guard's chain prefix (eval/builtin/command/exec/rtk)
  re-reads a chain run from every walk position, so each run also charges its length squared per
  start (deep-audit 5: `command ` x 8000 after one `;` took 9 s). GH #273 added one leading chain run (eval/builtin/rtk, only when a wrapper word follows), so a
  start such as `eval sudo ` now walks to the end of the string like a bare `sudo ` start does; the starts x length
  charge covers that, not the per-run one. Slowest allowed shape (`eval sudo ` + 1000 args + `;` x 70, then `ls`):
  5.1 s on the branch at the old 60M budget, 0.09 s on `develop` (M3 Pro). The guard's budget is now 45M
  (worst measured 4.2 s, about 1.9x under the 8 s timeout; a padded benign command over roughly 16-23 KB is
  refused); lower it again if a slower runner flakes `test-subagent-git-guard.sh`. `eval` takes
  assignments (`eval A=1 env git stash` runs git) and `doas` is a wrapper word, both GH #273 follow-ups. A chain/wrapper loop was
  exponential (`sudo eval ` x 250 never finished), so keep it to one leading run, limited to the non-wrapper words (eval, builtin, rtk) and ended by a
  lookahead for a wrapper word: a run that also took `command`/`exec` doubled every split (deep-audit
  checker, `command ` x 700 + `eval "git stash"` took 8 s). A new regex piece needs its own
  worst case measured, not assumed to fit the existing charge.
  GH #339: the lookahead's step also takes exec's `-a NAME` and rtk runs after a command/exec word
  (`eval command rtk proxy nohup git stash`), and `_SHELL_PASS`'s exec takes `-c`/`-l`/`-a NAME`
  (`eval exec -a x git stash`). Each flag reads one way only: a flag holding an `a` takes the next word,
  one without takes none. Letting `-a` read both ways was exponential (`eval exec ` + `-a ` x 30 took
  16 s). The spawn anchor takes one leading run of `builtin`, only when a wrapper word follows
  (`builtin command claude --agent x`); a run that could read `builtin ` two ways took 15 s at 24 words.
  A `builtin ...` timing row must name `claude` or `git`: the `.sh` fast path never starts python for `ls`.
  A chain run with `exec -a x` units now charges the budget, so `eval ` + `exec -a x ` x 500 (5 KB) is
  refused as too dense, as `command rtk proxy ` x 200 already was.
- **A broad new rule ships shadow first** (GH #337). Give its `deny()`/`ask()` call a `rule="<id>"` and
  list the id in `irrecoverable.py`'s `SHADOW_RULES`: a match then journals `would_deny`/`would_ask` with
  the id and the command, and the call goes through. `/mh:gate-report` lists the hits per rule with
  sample commands; delete the id to enforce once they hold no false positive. The list is source, not an
  env var, so a project `settings.json` cannot shadow an enforced rule. A structural deny (length cap,
  unparsable text, budget, depth) takes no id: returning from it would run the code it guards. A rule
  that denies commands from a replay of real transcripts ships shadow, not enforcing.
  GH #336 added `mkfs`, `chmod-world` (777 / a+rwx with -R or on / or ~), `rm-no-preserve-root` and two
  views, each a second reading of the whole command checked by every rule: `ifs-split` ($IFS read as a
  blank) and `var-verb` (`$NAME` read back where the command assigns NAME a plain value). A view runs
  after the command passed, up to 20 KB, and a structural deny inside one only ends that view. Replay of
  55,000 real commands with every new rule shadowed: 0 verdict diffs against develop; 0 hits for the
  first four, 1 for `var-verb` (a real `git -C $R checkout -- <file>`, a discard develop misses, GH #375), 63
  `opaque-var-verb` asks and 98 `source-file` asks. Those three ship shadow. Residue: zsh does not split
  $IFS (bash and dash do); `. file` with no candidate word never reaches python; `mk$(true)fs` matches,
  `${X}` as argv0 does not read as mkfs.
- **shlex cuts one shell word into several tokens** (GH #375). With `punctuation_chars` and no
  `whitespace_split`, a character outside its wordchars ends the token: `$PWD` is `$`, `PWD`, and `a:b`,
  `a@b.c` and a Thai path split too. A check that takes "the next token" as one word misreads it: the git
  global walk took `PWD` in `git -C $PWD reset --hard` for the subcommand. `_tokens` now returns a token
  cut from the one before it, with no blank between, as `_Glued` (an equal `str`), and the git block
  re-reads its global flags as joined words in a window of its own; the token reading stays, so a deny in
  either wins. Replay of 115,308 real commands (main and agent): 3 newly denied, two
  that run `reset --hard` / `checkout --` and one `git -C $PCR add .` (git-add-all, not data loss).
  GH #382: every other walk had the same fault (sudo/doas/env/timeout/nice values, a `X=$Y` prefix, a
  wrapper's dash words, docker's container, `$HOME/bin/git` as argv0), and `_split_ops("")` dropped an
  empty word, so `git -C "" reset` read `reset` as -C's value. Each statement is now also read as shell
  words (`_readings`: glued runs joined, `""` kept), queued and checked after every token window, so a
  develop deny keeps its message. The token reading still drops `""`: keeping it there would allow
  `"" rm -rf x`, which develop denies. Git ignores an empty argument in its rules (git rejects it).
  A joined word holds more text, so in a word window a substitution word only stands for the names
  its literal text allows (`_candidates`: `g$(..)t` may be git, `x:$(date)` names nothing); before
  that, prose read as shell (python heredocs, a PR body) denied 8 replayed commands as `git restore`.
  `scripts/gate-differential.sh` against develop (2026-10-04, after #405/#409): 20,000 and 40,000
  replayed commands plus fixtures and fuzz; every exit change is a fixture or fuzz row, and the real
  commands gained only 2 shadow asks (`PATH=/a:/b command -v $t`: opaque-var-verb;
  `X=$F bash -c '. x.sh'`: source-file), each what develop already says without the split prefix.
- **Oracle:** run the real shells (the system `/bin/sh`, bash 3.2, a current bash, dash, zsh, ksh)
  with argv-logging stubs, never one shell or argv0-based shell guessing: whether `{fd}>` is a
  redirect depends on the binary and version (GH #219).
- **Validator:** a fresh agent writes its own generator; the builder's generator is never reused.
- **A piece that still fails after one patch round is dropped.** PR #208's redirect fix took one
  patch (validator round 1) and merged; validator round 2 then found an sh/dash residue, and its
  fix (PR #218) was the piece dropped, with the residue tracked in GH #219. Shipping only the
  pieces that pass is how #208 merged after PR #192 failed.
- **When the shell is ambiguous, check both readings; any deny wins** (GH #219). Shipped for named-fd
  `{var}>f`: `_blank_redirections(s, named_fd)` is run as redirect (bash 4+/ksh), literal word (sh,
  bash 3.2, dash) and zsh (`{var}&>f` too), and every window is checked. Fuzz, 4000 cases against real
  shells: false-allows 84 to 0, false-denies 545 to 602 (a branch switch or restore with `{fd}>x` now
  denies; accepted, the safe direction). A check by argv0 stays unsound (`exec -a sh bash`).
- Attack strings live in files, never in Bash command text, and the gate only classifies them.
- **A word list one gate types by hand drifts from its sibling.** `subagent-git-guard.py`'s
  `_WRAPPER_WORDS` is a second copy of `irrecoverable.py`'s `PREFIX_WRAPPERS`; `rtk` reached the
  first list only after the guard let `rtk proxy git stash` through (deep-audit 4), and a glued
  `timeout=30` once broke the shared spawn regex. `tests/hooks/test-subagent-git-guard.sh` now fails
  when a `PREFIX_WRAPPERS` word is not a wrapper in the guard. A new copy of a list needs its own
  drift test, and a new word needs two awkward-shape cases per consumer: a glued `name=1`, and a
  multi-statement decoy (`<word> x && git stash && git status`), because a wider wrapper list can
  also hide the statements after it (the guard's walk ran across `;` to the last `git`).
  GH #320: each word may also be written as a path (`/usr/bin/env git stash`), so every copy takes a
  directory prefix, and the drift test checks `/usr/bin/<word>` too. The prefix is one plain word that
  never starts with `-` and holds no `=`, `<` or `>`. The git word's `\S*/` was tried first and was
  exponential: a token such as `-/command` or `2>/x/env` then reads two ways (flag or path command,
  redirection or path wrapper), and the chain loops try every split (`eval command ` + `-/command ` x 40
  ran past 15 s, and a timed-out hook allows).
  GH #322: `irrecoverable.py`'s spawn anchor got the guard's #317 and #318 fixes (`cl\aude -p x`,
  `{claude -p x;}`). It reads raw text, so a glued `{` inside quotes after a blank now denies too
  (`git commit -m "fix {claude -p x;}"`), the same over-deny develop already makes for `"fix; claude -p x"`.
  Its glued `{` alternative carries `(?!\s)` so it never matches the same `{` as `{` + blank: with both,
  every `{ env ` unit was walked twice (2.4 s against 1.2 s at 2000 units).
  GH #344: a shell removes the quotes inside a word (`"git" stash`, `g'i't stash`, `git "stash"`,
  `"claude" -p x`). Both gates join a word made only of command-word characters (`[\w./-]`, an escaped
  one too) and quoted runs of them back to its letters (`_QWORD_RE` / `_SPAWN_QWORD_RE`, one pattern, a
  drift test). The guard joins only where its quote mask shows the word outside every quote, so a
  message stays masked. A `$'..'`/`$".."` piece reads differently per shell (`$'list'` is `$list` in
  dash, `$"show"` is `$show` in dash and zsh), which matters for the `stash list|show` carve-out, so the
  guard runs up to three readings. The spawn anchor also scans the unjoined text when a join changed it
  (`claude -p"x"` is `-px`). Its residue, a second parse level (`eval \"git\" stash`, `eval "git " stash`,
  an escaped quote inside a `bash -c "..."` body), is GH #327's fix below.
  GH #327: eval and `sh -c` hand their argument text to a second parse, so a pair that is a literal
  backslash after the first parse is an escape in the second (`eval g\\\it stash`, `bash -c "g\\it stash"`).
  The guard's `_read_words` does the first parse's quote removal (one word after `-c`, every word to the
  statement end after eval, joined with blanks) and checks the result as one more body; the raw quoted body
  is still checked, so any deny wins. `$'..'` is decoded the bash way and `$".."` read as `".."`; a `$(..)` or
  backtick span is copied as it is. Fuzz, 4000 cases, two seeds: false-allows 641 and 552 to 0, no new
  false-deny. A known over-deny: `eval sudo echo "git stash"` now reads as `sudo echo git stash`, which the
  wrapper walk denies like the plain text (a GH #273 control changed from allow to deny). The copied spans
  made every substitution body scan twice, so the substitution pass now checks each body string once; that
  also fixed a develop timeout: `eval ` + 2 million backticks + a late `"$(git stash)"` took 8.3 s (allow),
  now 3 s. The second-parse body joins the substitution pass only when a `$` or backtick came out of a quote
  or an escape (`` eval echo '`git' 'stash`' ``), since a copied span is one the raw scan already read. Residue, which `develop` also allows: a substitution that expands to nothing
  before the word (`eval $(true) g\\\it stash`, like `$(true) git stash`) and a third parse level.
