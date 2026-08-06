#!/usr/bin/env bash
# Gate: block irrecoverable Bash patterns before they execute.
# Reads the PreToolUse JSON payload from stdin; exits 2 to block.
set -uo pipefail

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import json, os, re, shlex, sys

try:
    d = json.load(sys.stdin)
except Exception:
    d = None

# A malformed/absent payload must fail closed, not silently become "no
# command to check" — that collapse let empty stdin, truncated JSON, and
# tool_input:null bypass every check below (found 2026-08-06).
if not isinstance(d, dict) or not isinstance(d.get("tool_input"), dict):
    print("[kbg:gate] BLOCKED: malformed PreToolUse payload — failing closed", file=sys.stderr)
    sys.exit(2)

cmd = d["tool_input"].get("command", "")

def deny(reason):
    print("[kbg:gate] BLOCKED: " + reason, file=sys.stderr)
    sys.exit(2)

# Tokenize respecting quotes. The bare token "rm" and the word rm both
# resolve to a bare rm token. Quoted free text (commit messages, grep
# patterns) stays inside one token instead of being scanned as if it
# were a command.
# ponytail: no command-substitution or eval unwrapping here. This is a
# habit-guard for a single-operator harness, not an adversarial sandbox;
# revisit if that threat model changes.
# Newlines are command separators in bash but shlex eats them as
# whitespace, so a dangerous command after a newline would otherwise
# hide inside the first command window (found 2026-07-03). Pre-split
# on newlines and tokenize each line. The "&" (background) operator is
# also a separator and is added to OPERATORS.
OPERATORS = {";", "&&", "||", "|", "&"}
windows, cur = [], []
for line in re.split(r"\r?\n", cmd):
    try:
        tokens = shlex.split(line, posix=True)
    except ValueError:
        tokens = line.split()
    for tok in tokens:
        if tok in OPERATORS:
            if cur:
                windows.append(cur)
            cur = []
        else:
            cur.append(tok)
    if cur:
        windows.append(cur)
        cur = []
if cur:
    windows.append(cur)

def basename(p):
    return p.rsplit("/", 1)[-1]

for w in windows:
    if not w:
        continue
    argv0, rest = basename(w[0]), w[1:]

    # Prefix wrappers unwrap one level per iteration so stacked forms like
    # "env nice rm -rf x" resolve to the real command. Found 2026-07-01:
    # "sudo rm -rf x" and "find | xargs rm -rf" bypassed every check because
    # argv0 was the wrapper, not the wrapped command — and these are
    # everyday shell idioms, not adversarial obfuscation, so they are in
    # scope for a habit-guard. env/nice take their own flags+values before
    # the wrapped command; command/nohup/time/sudo only take bare flags.
    PREFIX_WRAPPERS = {"env", "command", "nohup", "nice", "time", "sudo"}
    while rest and argv0 in PREFIX_WRAPPERS:
        if argv0 == "env":
            i = 0
            while i < len(rest):
                t = rest[i]
                if t == "-u" and i + 1 < len(rest):
                    i += 2
                elif t.startswith("-"):
                    i += 1
                elif "=" in t and t.split("=", 1)[0].isidentifier():
                    i += 1
                else:
                    break
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]
        elif argv0 == "nice":
            i = 0
            while i < len(rest) and rest[i].startswith("-"):
                t = rest[i]
                i += 1
                if t == "-n" and i < len(rest):
                    i += 1
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]
        else:  # command, nohup, time, sudo — bare flags then the wrapped command
            i = 0
            while i < len(rest) and rest[i].startswith("-"):
                i += 1
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]

    if argv0 == "xargs":
        # Unlike git, xargs args are never a free-text commit message, so
        # scanning for a known-dangerous basename anywhere in its args is
        # safe (no quoted-prose false-positive risk). "git" is included so
        # the per-argv0 git check fires on the xargs-wrapped form of git
        # commands; without it, argv0 stays as "xargs" and the worktree
        # check is silently bypassed (found 2026-07-03 when designing the
        # worktree-create-block gate).
        for j, t in enumerate(rest):
            if basename(t) in ("rm", "find", "dd", "git"):
                argv0, rest = basename(t), rest[j + 1:]
                break
    elif argv0 == "docker" and rest and rest[0] == "exec":
        # "docker exec <flags> <container> <cmd...>" re-points argv0 to the
        # inner command so the SQL check below can fire on the wrapped
        # client (feeds A6 — mysql/psql/sqlite3/mariadb run inside a
        # container is otherwise invisible to this gate).
        j = 1
        while j < len(rest) and rest[j].startswith("-"):
            j += 1
        if j < len(rest):
            j += 1  # skip the container name/id
        if j < len(rest):
            argv0, rest = basename(rest[j]), rest[j + 1:]

    if argv0 == "rm":
        # Lowercase before matching. "rm -Rf" and "rm -R -f" bypassed
        # the lowercase-only "r"/"f" substring check (found 2026-07-01).
        flags = "".join(t for t in rest if t.startswith("-")).lower()
        if "r" in flags and "f" in flags:
            deny("rm -rf detected — use trash instead")

    if argv0 == "find" and ("-exec" in rest or "-execdir" in rest) and "rm" in [basename(t) for t in rest]:
        deny("find -exec/-execdir rm detected — destructive delete, use trash or confirm with user")
    if argv0 == "find" and "-delete" in rest:
        deny("find -delete detected — destructive delete, use trash or confirm with user")

    if argv0 == "git" and rest:
        # --no-verify skips pre-commit/pre-push hooks — block it on any git
        # command, multi-line safe (checked per window, not against the
        # loop-leak `tokens` which only held the last line — found v0.36.0
        # audit: a --no-verify on an earlier line bypassed the old global
        # check). Git-specific so `echo "--no-verify"` does not false-positive.
        if "--no-verify" in w:
            deny("--no-verify bypasses safety hooks")
        # -c core.hooksPath=<path> (split "-c core.hooksPath=X" or joined
        # "-ccore.hooksPath=X") re-points git at a different hooks dir —
        # the same bypass as --no-verify, just spelled as a config
        # override. Only a non-empty value trips it: "=" with nothing after
        # is not a meaningful re-point.
        hooks_path_val = None
        for idx, t in enumerate(w):
            if t == "-c" and idx + 1 < len(w) and w[idx + 1].startswith("core.hooksPath="):
                hooks_path_val = w[idx + 1].split("=", 1)[1]
            elif t.startswith("-c") and t[2:].startswith("core.hooksPath="):
                hooks_path_val = t[2:].split("=", 1)[1]
        if hooks_path_val:
            deny("-c core.hooksPath=<path> re-points git at a different hooks dir — same bypass as --no-verify")
        # Walk past leading global flags before the subcommand so a prefix
        # like `git -C /repo push --force` (or `git -Cpath push --force`,
        # `git --no-pager push --force`) does not set sub="-C"/"--no-pager"
        # and silently bypass the push/worktree gates (found v0.36.0 audit).
        # The WorktreeCreate event does NOT fire for Bash-invoked worktree
        # creation, so this Bash-side guard is the only thing blocking
        # `git -C . worktree add -b newbranch`.
        GIT_VALUE_GLOBALS = {"-C", "-c", "--git-dir", "--work-tree", "--config-env"}
        i = 0
        while i < len(rest) and rest[i].startswith("-"):
            t = rest[i]
            if t in GIT_VALUE_GLOBALS:
                i += 2  # bare value-taking global → skip flag + its value
                continue
            # combined form carrying the value in the same token
            # (-Cpath, --git-dir=path, --config-env=name=val) → skip 1
            if (t.startswith("-C") and t != "-C") or \
               t.startswith(("--git-dir=", "--work-tree=", "--config-env=")):
                i += 1
                continue
            i += 1  # any other leading flag (non-value global: --no-pager, -p, …)
        if i >= len(rest):
            continue  # only global flags, no subcommand — safe no-op
        sub, args = rest[i], rest[i + 1:]
        # drop the value token after a free-text flag so message
        # content (e.g. "commit -m ...rm -rf...") is never pattern-
        # matched.
        scan, skip = [], False
        for t in args:
            if skip:
                skip = False
                continue
            if t in ("-m", "--message"):
                skip = True
                continue
            scan.append(t)

        if sub == "push" and any(
            t in ("-f", "--force") or (t.startswith("--force") and not t.startswith("--force-with-lease"))
            or (t.startswith("-") and not t.startswith("--") and "f" in t)
            or t.startswith("+")  # "+refspec" force-pushes without a -f/--force flag
            for t in scan
        ):
            deny("git push --force overwrites remote history — needs explicit user approval (use --force-with-lease for the safe variant)")
        if sub == "reset" and "--hard" in scan:
            deny("git reset --hard discards uncommitted work — confirm with user first")
        if sub == "clean" and any(t.startswith("-") and "f" in t for t in scan):
            deny("git clean -f deletes untracked files — confirm with user first")
        # git restore is the modern checkout -- replacement. The default mode
        # (and --worktree) targets the WORKTREE → discards changes, unrecoverable.
        # --staged (without --worktree) targets the INDEX → recoverable (re-stage
        # with git add), so it is allowed. Unlike checkout, `git restore <path>`
        # is NEVER a branch switch (no ambiguity), so a worktree-targeting
        # pathspec is always destructive.
        if sub == "restore":
            has_pathspec = ("." in scan or "--" in scan or
                            any(not t.startswith("-") for t in scan))
            targets_worktree = "--worktree" in scan or "--staged" not in scan
            if has_pathspec and targets_worktree:
                deny("git restore discards working-tree changes — confirm with user first")
        # checkout: "--"/"." = discard (existing); 2+ nonflag = tree-ish +
        # path (e.g. `git checkout HEAD~1 file`, overwrites worktree from an
        # old commit — unrecoverable). 1 nonflag stays allowed: it may be a
        # legit branch switch (found v0.36.0 audit: HEAD~1+file was missed).
        if sub == "checkout" and ("--" in scan or "." in scan or
                                    len([t for t in scan if not t.startswith("-")]) >= 2 or
                                    any(t in ("-f", "--force") for t in scan)):
            deny("git checkout -- / git checkout . / git checkout -f / git checkout <tree> <file> discards working-tree changes — confirm with user first")
        if sub == "switch" and any(t in ("-f", "--force", "--discard-changes") for t in scan):
            deny("git switch --force discards working-tree changes — confirm with user first")
        if sub == "branch" and (
            any(t == "-D" or (t.startswith("-") and not t.startswith("--") and "D" in t) for t in scan)
            or ("--delete" in scan and "--force" in scan)
        ):
            deny("git branch -D / --delete --force force-deletes a branch, discarding unmerged commits — confirm with user first")
        if sub == "stash" and args and args[0] in ("drop", "clear"):
            deny("git stash drop/clear discards stashed changes — confirm with user first")
        if sub == "commit" and "--amend" in scan:
            deny("git commit --amend rewrites history — confirm with user first")
        if sub == "add" and any(t in ("-A", "--all", ".") for t in scan):
            deny("git add -A/. stages everything — stage files by name instead")
        if sub == "worktree" and args and args[0] == "add":
            # kbg single-branch doctrine gate. This is the ONLY enforcement
            # point for the doctrine — a prior companion gate on the native
            # WorktreeCreate event (worktree-create-block.sh) was removed
            # 2026-07-31: it read tool_name/tool_input, fields that event
            # never actually sends (confirmed against code.claude.com/docs/en/hooks
            # raw HTML), so its deny logic was dead code, and independent of
            # that bug, registering ANY hook on WorktreeCreate replaces the
            # Claude Code default worktree creation and requires the hook
            # to emit the resulting path — this one never did, so it was
            # silently breaking every legitimate WorktreeCreate-triggered
            # worktree (isolation:"worktree", claude --worktree, background
            # sessions) in every repo running this plugin. See
            # docs/research/official-docs-audit-2026-07-31.md. This Bash-side
            # check is unaffected: the dedicated WorktreeCreate event never
            # fires for Bash-invoked `git worktree add` in the first place
            # (verified against the same docs), so it was never part of the
            # broken mechanism.
            #
            # Find the new-branch name. The git-worktree-add argv
            # order is flexible — the -b flag may come before or
            # after the path. Scan ALL args for the -b/-B/--branch
            # flag pair. If found, capture the value. If absent, no
            # new branch is being created (existing branch checkout
            # via positional commit-ish) — allow.
            branch_name = None
            for i, t in enumerate(args):
                if t in ("-b", "-B", "--branch") and i + 1 < len(args):
                    branch_name = args[i + 1]
                    break
                # joined forms: -bBRANCH, -BBRANCH, --branch=BRANCH
                if (t.startswith("-b") and t != "-b") or (t.startswith("-B") and t != "-B"):
                    branch_name = t[2:]
                    break
                if t.startswith("--branch="):
                    branch_name = t.split("=", 1)[1]
                    break
            if branch_name is not None and branch_name != "develop":
                # Resolve project root: CLAUDE_PROJECT_DIR env first,
                # then walk up from cwd looking for .git OR sentinel.
                root = os.environ.get("CLAUDE_PROJECT_DIR") or ""
                if not root:
                    d = os.getcwd() or "/"
                    for _ in range(16):
                        if d in ("", "/"):
                            break
                        try:
                            if os.path.isdir(os.path.join(d, ".git")) or \
                               os.path.isfile(os.path.join(d, ".kbg-no-worktree")):
                                root = d
                                break
                        except Exception:
                            pass
                        parent = os.path.dirname(d)
                        if parent == d:
                            break
                        d = parent
                sentinel = os.path.join(root, ".kbg-no-worktree") if root else ""
                if sentinel and os.path.isfile(sentinel):
                    # review-pr allowlist. Skills/review-pr/SKILL.md line
                    # 46 uses the shape "git worktree add --detach path
                    # sha" with no -b. A command that combines --detach
                    # and -b new is doctrine-breaking disguised as
                    # review-pr — deny it.
                    is_review_pr = (
                        "--detach" in args
                        and any("review-pr-" in a for a in args)
                        and branch_name is None
                    )
                    if not is_review_pr:
                        deny("git worktree add -b new-branch blocked by kbg-harness doctrine "
                             "(no new non-develop branches via worktree; single branch develop only); "
                             "use detached worktrees, develop, or an existing branch. "
                             "Remove /.kbg-no-worktree to allow")

    if argv0 == "dd" and any(t.startswith("of=/dev/") for t in rest):
        deny("dd writing to a raw device — irrecoverable disk-level destruction")

    if argv0 in ("mysql", "psql", "sqlite3", "mariadb"):
        # SQL genuinely lives inside -e/-c values, unlike git free-text
        # messages — deliberately DO scan inside those here. The check
        # is restricted to known-dangerous statements.
        if re.search(r"DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE", " ".join(rest), re.IGNORECASE):
            deny("destructive SQL (DROP TABLE/DATABASE/SCHEMA or TRUNCATE TABLE) detected — confirm with user first")

sys.exit(0)
'
rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
  echo "[kbg:gate] internal error (rc=$rc) — failing closed" >&2
  exit 2
fi
exit "$rc"
