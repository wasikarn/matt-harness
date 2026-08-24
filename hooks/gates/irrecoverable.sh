#!/usr/bin/env bash
# Gate: block irrecoverable Bash patterns before they execute.
# Reads the PreToolUse JSON payload from stdin; exits 2 to block.
set -uo pipefail

# --- Fast path: skip the python3 cold-start on commands that cannot match a
# deny pattern. Every deny below dispatches on an argv0 in {rm, find, git, dd,
# mysql, psql, sqlite3, mariadb} (lines 186-383); a wrapper (sudo/env/nice/
# xargs/docker exec) never hides that token from the raw string, so if NONE of
# these substrings survives normalization the command is allow-safe and we exit
# 0 without spawning python. Quote/backslash stripping (tr -d) exposes the one
# shlex obfuscation the python catches -- a quote-concatenated `r""m` -> `rm`.
# ponytail: coarse pre-filter for a habit-guard, not an adversarial sandbox;
# command-substitution/eval unwrapping stays out of scope (see line 83 below).
# False positives (digit/warm/scheduling) just spawn python -- safe direction.
# sync-seam: the stdin-capture + whitespace-normalize prefix (this line +
# the next) is hand-duplicated in verifier-protect.sh's own fast-path -- not
# extracted to a shared sourced helper because these gates govern their own
# edits (a shared-helper bug would break both simultaneously; a lockout here
# already cost 2 self-inflicted recoveries in verifier-protect.sh alone,
# 2026-08-14). If either file's normalize step changes, check the other.
_input="$(cat)"
_norm="$(printf '%s' "$_input" | sed 's/\\[nt]/ /g' | tr -s '[:space:]' ' ' | tr -d "\"'\\")"
case "$_norm" in
  *rm*|*find*|*git*|*dd*|*mysql*|*psql*|*sqlite3*|*mariadb*) : ;;  # candidate -> python
  *) exit 0 ;;                                                   # no destructive token possible -> allow
esac

# Portability guard (#93): without python3 the deny logic below cannot run,
# and the rc!=0/2 tail reads the resulting 127 as "internal error — fail
# closed" — which on a python3-less machine blocks EVERY command carrying an
# rm/find/git/dd token, `git status` included. Announced fail-open is the
# lesser harm; doctrine-bootstrap.sh names the missing dep once at SessionStart.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[kbg:gate] python3 not found — irrecoverable-pattern gate cannot run; allowing (install python3 to restore deny coverage)" >&2
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
printf '%s' "$_input" | python3 -c '
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

SQ = chr(39)
_HEREDOC_RE = re.compile(r"<<(-)?\s*([" + SQ + r"\"]?)([^\s" + SQ + r"\"]+)\2")
# A heredoc feeding an interpreter is executable code, not inert data -- do
# not strip it (checked against the segment of the line BEFORE "<<", i.e.
# the command the heredoc is stdin for, not the body that follows).
_INTERPRETER_RE = re.compile(r"\b(bash|sh|zsh|dash|ksh|python3?|python2|perl|ruby|node|nodejs|osascript)\b")

def _strip_heredocs(cmd):
    # Heredoc bodies are literal data until the closing delimiter line, not
    # shell syntax to scan for dangerous subcommands -- UNLESS the heredoc
    # is stdin for an interpreter (bash <<EOF, python3 <<EOF, ...), in which
    # case the body IS executable code and must stay scannable. Without the
    # first half of this, a commit message authored via a quoted HEREDOC
    # (the documented commit convention in this repo) that merely MENTIONS
    # "git checkout X Y" or "rm -rf" in prose gets tokenized as a real
    # command and falsely denied -- reproduced live 2026-08-06. Without the
    # second half, "bash <<EOF\nrm -rf /\nEOF" silently bypasses every check
    # below -- also reproduced live 2026-08-06, by a negative-control test
    # written specifically to probe the first fix for this exact regression.
    # Ported from verifier-protect.sh (function of the same name), itself
    # ported from worktree-guard.py 2026-08-04; neither sibling makes the
    # interpreter distinction because their threat model (detecting writes
    # to specific files) does not need it the way a "catch any dangerous
    # command" gate does.
    lines = cmd.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = _HEREDOC_RE.search(line)
        i += 1
        if not m:
            continue
        if _INTERPRETER_RE.search(line[:m.start()]):
            continue
        strip_tabs, delim = bool(m.group(1)), m.group(3)
        body_start, found = i, False
        while i < len(lines):
            body_line = lines[i].lstrip("\t") if strip_tabs else lines[i]
            i += 1
            if body_line == delim:
                found = True
                break
        if not found:
            # Closing delimiter never matched. Put the scanned lines BACK
            # instead of discarding them — silently eating a real write
            # statement that followed an unmatched heredoc open is worse
            # than never stripping at all.
            out.extend(lines[body_start:i])
    return "\n".join(out)

cmd = _strip_heredocs(d["tool_input"].get("command", ""))

def deny(reason):
    print("[kbg:gate] BLOCKED: " + reason, file=sys.stderr)
    sys.exit(2)

def delete_hint():
    # trash is not stock on macOS or Linux (#93) — offer whichever CLI exists,
    # else route the model to the user. Lazy shutil import: only paid on a deny.
    import shutil
    t = next((c for c in ("trash", "trash-put") if shutil.which(c)), None)
    if t:
        return "use " + t + " instead"
    return ("no trash CLI on this machine — ask the user before a destructive "
            "delete, or install one (macOS: brew install trash; Linux: trash-cli)")

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
            deny("rm -rf detected — " + delete_hint())

    if argv0 == "find" and ("-exec" in rest or "-execdir" in rest) and "rm" in [basename(t) for t in rest]:
        deny("find -exec/-execdir rm detected — destructive delete; " + delete_hint())
    if argv0 == "find" and "-delete" in rest:
        deny("find -delete detected — destructive delete; " + delete_hint())

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
        # Bundled short flags: "-qf" means -q -f, and an exact-token check like
        # `t in ("-f", "--force")` misses it (2026-08-17 bug sweep, live-verified
        # bypass). Stop scanning a cluster at a value-taking flag letter
        # (checkout -b/-B, switch -c/-C) so "-bfoo"/"-cfoo" is not misread as
        # -f hiding inside the branch-name argument. No apostrophes in this
        # block: it lives inside the bash single-quoted python3 -c wrapper
        # below, and a literal apostrophe closes that string early.
        def _bundled_force(t, stop_chars):
            if not (t.startswith("-") and not t.startswith("--")):
                return False
            for ch in t[1:]:
                if ch in stop_chars:
                    return False
                if ch == "f":
                    return True
            return False
        # checkout: "--"/"." = discard (existing); 2+ nonflag = tree-ish +
        # path (e.g. `git checkout HEAD~1 file`, overwrites worktree from an
        # old commit — unrecoverable). 1 nonflag stays allowed: it may be a
        # legit branch switch (found v0.36.0 audit: HEAD~1+file was missed).
        if sub == "checkout" and ("--" in scan or "." in scan or
                                    len([t for t in scan if not t.startswith("-")]) >= 2 or
                                    any(t in ("-f", "--force") or _bundled_force(t, ("b", "B")) for t in scan)):
            deny("git checkout -- / git checkout . / git checkout -f / git checkout <tree> <file> discards working-tree changes — confirm with user first")
        if sub == "switch" and any(t in ("-f", "--force", "--discard-changes") or _bundled_force(t, ("c", "C")) for t in scan):
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
                    # review-pr allowlist. skills/review-pr/SKILL.md
                    # Phase 2 (PR-by-number path) uses the shape "git
                    # worktree add --detach path sha" with no -b. A
                    # command that combines --detach and -b new is
                    # doctrine-breaking disguised as review-pr — deny it.
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
        # TABLE is optional in TRUNCATE grammar (MySQL/MariaDB/Postgres all
        # accept bare "TRUNCATE tbl_name") — matching only "TRUNCATE TABLE"
        # let a fully destructive bare TRUNCATE through undetected.
        if re.search(r"DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+(TABLE\s+)?\w",
                     " ".join(rest), re.IGNORECASE):
            deny("destructive SQL (DROP TABLE/DATABASE/SCHEMA or TRUNCATE) detected — confirm with user first")

sys.exit(0)
'
rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
  echo "[kbg:gate] internal error (rc=$rc) — failing closed" >&2
  exit 2
fi
exit "$rc"
