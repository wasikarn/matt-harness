#!/usr/bin/env bash
# Gate: the TOP-LEVEL session plans, dispatches, verifies, decides -- it does
# not edit files, run mutating commands, or commit. Reads the PreToolUse JSON
# payload from stdin; exits 2 (+ stderr reason) to deny. Two legs, one script
# (same shape as agent-recursion-guard.sh): tool_name in Write/Edit/MultiEdit/
# NotebookEdit denies any main-session file edit outside three carve-outs
# (~/.claude/plans/, ~/.claude/projects/*/memory/, the session scratchpad);
# tool_name == Bash allows only a read-only allowlist and denies everything
# else, including anything it cannot parse.
#
# Why: operator decision 2026-09-02, replacing the volume-based ask-nudge
# (main-write-budget.sh, retired the same day). An ask is useless in this
# operator's --dangerously-skip-permissions sessions (it silently becomes
# allow), so this is a deny gate.
#
# DISCRIMINANT: `agent_id` present in the payload == subagent == exit 0,
# untouched. NEVER key on `agent_type` -- a top-level `claude --agent <name>`
# session also sets agent_type (task-complete-separation.sh header, same
# security-review finding on agent-recursion-guard.sh, 2026-08-31).
#
# OPT-IN via MH_MAIN_EXEC_GUARD (a Bash `export` inside a session does NOT
# reach this hook -- relaunch with the var set, or use settings.json env):
#   unset / anything else -> gate off, exit 0 before stdin is read
#   log                   -> evaluate everything, never deny, append a row
#                            per call to ~/.local/share/kbg/metrics/
#                            main-exec-guard.jsonl (calibration mode)
#   1                     -> enforce (exit 2 on a would-deny)
#
# FAIL DIRECTION -- a deliberate asymmetry:
#   python3 missing / payload unparseable / not a dict / no tool_name
#     -> ALLOW with a stderr notice. A malformed-payload lockout on the
#        operator's OWN session is worse than one bad allowlist decision:
#        irrecoverable.sh fails closed because a false ALLOW there is
#        catastrophic and irreversible; here a false DENY costs the whole
#        session with no recovery path, while the rule being enforced is a
#        reversible workflow rule.
#   Bash command that fails to tokenize, or carries any construct the
#   classifier does not recognize (odd operator, redirect, substitution)
#     -> DENY. A false positive costs one blocked command -- dispatch a
#        subagent instead.
#
# MH_GUARDED_WORKSPACE needs no special-case here (unlike the retired
# main-write-budget.sh): this gate only verdicts main's own calls, and
# worktree-guard's updatedInput redirect applies to a subagent's write in a
# separate PreToolUse call where this gate exits 0.
#
# sync-seam: the Bash tokenizer below (_newlines_to_seps, the shlex
# punctuation_chars split, the window split on operators, the env/nice/
# command/nohup/time wrapper unwrap) is hand-copied from irrecoverable.sh,
# not sourced from a shared helper -- same reasoning as irrecoverable.sh /
# verifier-protect.sh: these gates govern their own edits, and a shared-
# helper bug would lock out every gate at once. Deliberately NOT copied from
# irrecoverable.sh: _strip_heredocs (a `<<` is itself a denied redirect here,
# so a heredoc body is never reached and stripping could only mask a
# verdict, never change it), the sudo bundled-flag parser (sudo is simply
# not allowlisted -- fail-closed is smaller than modelling it), the xargs and
# docker-exec unwraps (both argv0s are denied outright, so what they wrap is
# irrelevant).
set -uo pipefail

# 1. Hottest-path fast bail: gate off unless explicitly enabled. Before
#    stdin, before spawning anything.
_mode="${MH_MAIN_EXEC_GUARD:-}"
case "$_mode" in 1|log) : ;; *) exit 0 ;; esac

# 2. Portability guard (#93): announced fail-open when python3 is missing.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found -- main-exec-guard gate cannot run; allowing (install python3 to restore the main-session no-exec rule)" >&2
  exit 0
fi

_input="$(cat)"

# 3. Enforcing mode: subagent -> allow before paying the python3 cold-start.
#    A real JSON extraction via jq, NOT a substring grep -- a Write whose
#    file CONTENT merely contains the text "agent_id" must not read as a
#    subagent call. jq missing or payload not JSON -> fall through; the
#    python body re-checks agent_id and fails open on a malformed payload
#    anyway. `log` mode skips this bail on purpose: it has to see every call
#    to log it.
if [[ "$_mode" == "1" ]] && command -v jq >/dev/null 2>&1; then
  [[ -z "$(jq -r '.agent_id // empty' <<<"$_input" 2>/dev/null)" ]] || exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
printf '%s' "$_input" | python3 -c '
import json, os, re, shlex, sys, time

MODE = os.environ.get("MH_MAIN_EXEC_GUARD", "")

def notice(msg):
    print("[mh:gate] main-exec-guard: " + msg, file=sys.stderr)

try:
    d = json.load(sys.stdin)
except Exception as e:
    notice("unparseable stdin, allowing (%s)" % e)
    sys.exit(0)
if not isinstance(d, dict):
    notice("non-object payload, allowing")
    sys.exit(0)
tool_name = d.get("tool_name")
if not isinstance(tool_name, str) or not tool_name:
    notice("no tool_name, allowing")
    sys.exit(0)
ti = d.get("tool_input")
if not isinstance(ti, dict):
    ti = {}

def clip(s):
    # Same log-injection guard as agent-recursion-guard.sh: strip control
    # chars, cap length, so a crafted path/command cannot forge or erase a
    # terminal line or burn context through the deny message.
    return re.sub(r"[^\x20-\x7e]", "?", str(s))[:80]

# ---------------------------------------------------------------- Write leg
HOME = os.path.realpath(os.path.expanduser("~"))
_PLANS = os.path.realpath(os.path.join(HOME, ".claude", "plans")) + os.sep
_MEMORY_RE = re.compile("^" + re.escape(HOME) + r"/\.claude/projects/[^/]+/memory/")
_SCRATCH_RE = re.compile(r"^(/private)?/tmp/claude-[^/]+/[^/]+/[^/]+/scratchpad/")

def check_write(path):
    # returns (would_deny, reason, attempted)
    if not isinstance(path, str) or not path:
        return False, "no target path in tool_input", ""
    # realpath after expanduser so ~, .., and symlinks cannot dodge a carve-out
    # check (or fake one).
    p = os.path.realpath(os.path.expanduser(path))
    if p.startswith(_PLANS):
        return False, "carve-out: ~/.claude/plans/", path
    if _MEMORY_RE.match(p):
        return False, "carve-out: ~/.claude/projects/*/memory/", path
    if _SCRATCH_RE.match(p):
        return False, "carve-out: session scratchpad", path
    return True, "main-session file edit outside carve-outs", path

# ----------------------------------------------------------------- Bash leg
# Newlines are command separators in bash but shlex eats them as whitespace;
# insert ";" after each real newline (a backslash-newline is a continuation,
# protected via placeholder) -- EXCEPT inside a "#" comment: a bash comment
# runs to the next literal newline full stop, so a trailing backslash there
# does not glue the next line on and does not suppress the separator. Track
# quote state too, since "#" only starts a comment when unquoted and at a
# word boundary (mid-word a# or a quoted comment marker is never a comment).
# SQ/DQ avoid a literal quote char in this source: the whole Bash-leg body
# below lives inside the outer printf|python3 -c invocation above, itself a
# single-quoted bash string -- an inline apostrophe character would end
# that string early. Same reasoning as SQ = chr(39) in irrecoverable.sh.
SQ = chr(39)
DQ = chr(34)
def _newlines_to_seps(s):
    out = []
    i, n = 0, len(s)
    squote = dquote = comment = False
    word_start = True
    while i < n:
        c = s[i]
        if comment:
            if c == "\n":
                comment = False
                out.append("\n; ")
                word_start = True
            else:
                out.append(c)
            i += 1
            continue
        if squote:
            out.append(c)
            if c == SQ:
                squote = False
                word_start = False
            i += 1
            continue
        if dquote:
            if c == "\\" and i + 1 < n and s[i + 1] == "\n":
                # real continuation inside a double-quoted string: bash
                # strips backslash-newline here too, same full removal as
                # the unquoted case below -- nothing appended.
                i += 2
                continue
            if c == "\\" and i + 1 < n:
                out.append(c); out.append(s[i + 1])
                i += 2
                continue
            out.append(c)
            if c == DQ:
                dquote = False
                word_start = False
            i += 1
            continue
        if c == "\\" and i + 1 < n and s[i + 1] == "\n":
            # real line continuation: bash removes the backslash AND the
            # newline entirely, joining the two lines with nothing between
            # them -- so nothing is appended here (word_start left
            # untouched, same as before: a continuation does not count as
            # "having typed something"). GH #123, twin of GH #122
            # (irrecoverable.sh, 33651372) -- the old pass-through left a
            # stray "\n" that shlex glued onto the very next token.
            i += 2
            continue
        if c == "\\" and i + 1 < n:
            nxt = s[i + 1]
            out.append(c); out.append(nxt)
            word_start = False
            i += 2
            continue
        if c == SQ:
            squote = True
            out.append(c)
            word_start = False
            i += 1
            continue
        if c == DQ:
            dquote = True
            out.append(c)
            word_start = False
            i += 1
            continue
        if c == "#" and word_start:
            comment = True
            out.append(c)
            i += 1
            continue
        if c == "\n":
            out.append("\n; ")
            word_start = True
            i += 1
            continue
        out.append(c)
        word_start = c in " \t;&|(){}<>"
        i += 1
    return "".join(out)

OPERATORS = {";", "&&", "||", "|", "&", "(", ")", "{", "}"}
PUNCT = set("();<>|&")
ALLOWED = set("""
ls cat head tail wc grep egrep fgrep rg awk jq sed diff stat file which type
pwd echo printf true false test [ tr cut sort uniq column tree du df date env
printenv realpath basename dirname readlink ps lsof uname shasum md5 nl comm
seq base64 xxd find git gh rtk claude
""".split())
PREFIX_WRAPPERS = {"env", "command", "nohup", "nice", "time", "rtk"}
ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

def basename(p):
    return p.rsplit("/", 1)[-1]

class Deny(Exception):
    pass

def deny(reason):
    raise Deny(reason)

def _inner_cmds(tok):
    # Text of every $(...) / `...` inside one token (a quoted token keeps its
    # substitution glued; an unquoted one is already split apart by shlex so
    # the inner command forms its own window). Unbalanced -> Deny.
    out, i, n = [], 0, len(tok)
    while i < n:
        if tok.startswith("$(", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if tok[j] == "(":
                    depth += 1
                elif tok[j] == ")":
                    depth -= 1
                j += 1
            if depth:
                deny("unbalanced $( in token")
            out.append(tok[i + 2:j - 1])
            i = j
        elif tok[i] == "`":
            j = tok.find("`", i + 1)
            if j < 0:
                deny("unbalanced backtick in token")
            out.append(tok[i + 1:j])
            i = j + 1
        else:
            i += 1
    return out

def _sed_prog_unsafe(p):
    # True if the sed program can touch the filesystem or a shell: the w/W
    # (write file) and e (exec) commands, or the w/e flags on s///. Address
    # prefixes (N, $, first~step, /re/, \cREc, ranges) are skipped and
    # regex/replacement bodies consumed, so a w INSIDE /re/ or s/w/x/ never
    # counts. a/i/c text runs to end of line; r/R/b/t/T/: labels run to ; or
    # newline.
    n = len(p)
    def skip_delim(i, dl):
        while i < n:
            if p[i] == "\\":
                i += 2
                continue
            if p[i] == dl:
                return i + 1
            i += 1
        return n
    i = 0
    while i < n:
        c = p[i]
        if c in " \t\n;{}!,$+~" or c.isdigit():
            i += 1
            continue
        if c == "/":
            i = skip_delim(i + 1, "/")
            continue
        if c == "\\" and i + 1 < n:
            i = skip_delim(i + 2, p[i + 1])
            continue
        if c in "wWe":
            return True
        if c in "sy":
            if i + 1 >= n:
                return False
            dl = p[i + 1]
            j = skip_delim(skip_delim(i + 2, dl), dl)
            while j < n and p[j] not in ";\n}":
                if p[j] in "we":
                    return True
                j += 1
            i = j
            continue
        if c in "aic":
            j = p.find("\n", i)
            i = n if j < 0 else j + 1
            continue
        if c in "rRbtT:":
            j = i + 1
            while j < n and p[j] not in ";\n":
                j += 1
            i = j
            continue
        i += 1
    return False

def _short_flag_has(t, chars):
    return t.startswith("-") and not t.startswith("--") and any(ch in t[1:] for ch in chars)

def check_find(rest):
    for t in rest:
        if t.startswith("-") and any(x in t for x in ("-delete", "-exec", "-ok", "-fprint")):
            deny("find with a mutating/executing action (%s)" % clip(t))

def check_sed(rest):
    progs, pos, i = [], [], 0
    while i < len(rest):
        t = rest[i]
        i += 1
        if t == "--":
            pos.extend(rest[i:])
            break
        if t.startswith("--"):
            name, has_eq, val = t.partition("=")
            if name in ("--in-place", "--file"):
                deny("sed %s" % name)
            if name == "--expression":
                progs.append(val if has_eq else (rest[i] if i < len(rest) else ""))
                i += 0 if has_eq else 1
            elif name == "--line-length" and not has_eq:
                i += 1
            continue
        if t.startswith("-") and len(t) > 1:
            for k, ch in enumerate(t[1:]):
                if ch in "if":
                    deny("sed -%s (in-place edit / script file)" % ch)
                if ch in "el":  # value-taking: rest of this token, else the next token
                    attached = t[k + 2:]
                    val = attached or (rest[i] if i < len(rest) else "")
                    if not attached:
                        i += 1
                    if ch == "e":
                        progs.append(val)
                    break
            continue
        pos.append(t)
    if not progs and pos:
        progs = [pos[0]]
    for p in progs:
        if _sed_prog_unsafe(p):
            deny("sed program writes a file or runs a command (%s)" % clip(p))

def check_awk(rest):
    for t in rest:
        if t.startswith(("-f", "--file", "-i", "--include", "-l", "--load", "-E", "--exec")):
            deny("awk %s (external program / library / in-place)" % clip(t))
    text = " ".join(rest)
    for x in ("system(", ">", "close(", "|", "@load", "@include"):
        if x in text:
            deny("awk program text contains %r" % x)

def check_sort(rest):
    for t in rest:
        if t.startswith("--output") or _short_flag_has(t, "o"):
            deny("sort -o writes a file")

GIT_READ = {"status", "log", "diff", "show", "blame", "describe", "ls-files", "cat-file", "grep", "rev-parse"}
GIT_BRANCH_FLAGS = {"--list", "-l", "-a", "--all", "-r", "--remotes", "-v", "-vv", "--verbose",
                    "--show-current", "--contains", "--no-contains", "--merged", "--no-merged",
                    "--points-at", "--sort", "--format", "--column", "--no-column", "--color", "--no-color"}
GIT_BRANCH_POS_OK = {"--list", "-l", "--contains", "--no-contains", "--merged", "--no-merged", "--points-at"}
GIT_CONFIG_WRITE = {"--add", "--unset", "--unset-all", "--replace-all", "--edit", "-e",
                    "--rename-section", "--remove-section"}

def check_git(rest):
    # Walk past leading globals (same shape as irrecoverable.sh). -c / --config-env
    # inject config that can run code (core.pager, core.editor) -> denied outright.
    i = 0
    while i < len(rest) and rest[i].startswith("-"):
        t = rest[i]
        if t.startswith(("-c", "--config-env")):
            deny("git -c/--config-env config injection")
        if t in ("-C", "--git-dir", "--work-tree"):
            i += 2
            continue
        i += 1
    if i >= len(rest):
        return  # bare `git` / `git --version`: help text, harmless
    sub, args = rest[i], rest[i + 1:]
    if any(a.startswith("--output") for a in args):
        deny("git %s --output writes a file" % sub)
    pos = [a for a in args if not a.startswith("-")]
    flags = [a for a in args if a.startswith("-")]
    if sub in GIT_READ:
        return
    if sub == "hash-object":
        if any(_short_flag_has(a, "w") for a in flags) or "--write" in flags:
            deny("git hash-object -w writes the object store")
        return
    if sub == "branch":
        for f in flags:
            bare = f.partition("=")[0]
            if bare in GIT_BRANCH_FLAGS:
                continue
            if _short_flag_has(f, "arvl") and set(f[1:]) <= set("arvl"):
                continue
            deny("git branch %s (not a read-only listing flag)" % clip(f))
        if pos and not any(f.partition("=")[0] in GIT_BRANCH_POS_OK or (f.startswith("-") and not f.startswith("--") and "l" in f) for f in flags):
            deny("git branch <name> creates/moves a branch")
        return
    if sub == "tag":
        if pos and not any(f in ("-l", "--list") or _short_flag_has(f, "l") for f in flags):
            deny("git tag <name> creates/deletes a tag")
        return
    if sub == "remote":
        if not pos or pos[0] in ("show", "get-url"):
            return
        deny("git remote %s mutates remotes" % clip(pos[0]))
    if sub == "stash":
        if pos and pos[0] in ("list", "show"):
            return
        deny("git stash (only list/show are read-only)")
    if sub == "worktree":
        if pos and pos[0] == "list":
            return
        deny("git worktree (only list is read-only)")
    if sub == "config":
        for f in flags:
            if f.partition("=")[0] in GIT_CONFIG_WRITE:
                deny("git config %s writes config" % f)
        if pos and pos[0] in ("set", "unset", "edit", "rename-section", "remove-section"):
            deny("git config %s writes config" % pos[0])
        if len(pos) >= 2:
            deny("git config <key> <value> writes config")
        return
    deny("git %s is not read-only" % clip(sub))

GH_READ = {("pr", "view"), ("pr", "list"), ("pr", "diff"), ("pr", "checks"), ("issue", "view"), ("issue", "list"),
           ("run", "list"), ("run", "watch")}
GH_API_MUTATE = ("-X", "--method", "-f", "-F", "--field", "--raw-field", "--input")

def check_gh(rest):
    pos, i = [], 0
    while i < len(rest):
        t = rest[i]
        i += 1
        if t in ("-R", "--repo"):
            i += 1
            continue
        if t.startswith("-"):
            continue
        pos.append(t)
    if not pos:
        return  # `gh`, `gh --version`
    if pos[0] == "api":
        for t in rest:
            if t.startswith(GH_API_MUTATE):
                deny("gh api with a mutating flag (%s)" % clip(t))
        return
    if len(pos) >= 2 and (pos[0], pos[1]) in GH_READ:
        return
    deny("gh %s is not on the read-only list" % clip(" ".join(pos[:2])))

def check_claude(rest):
    if rest in (["--version"], ["-v"], ["plugin", "list"]):
        return
    deny("claude %s (only --version / plugin list are allowed)" % clip(" ".join(rest)))

PER_CMD = {"find": check_find, "sed": check_sed, "awk": check_awk, "sort": check_sort,
           "git": check_git, "gh": check_gh, "claude": check_claude}

def _redirect_ok(tok, nxt):
    # Only >/dev/null, 2>/dev/null, 2>&1 (and >&2) are harmless; everything
    # else that reads or writes a file/process is denied.
    if tok == ">" and nxt == "/dev/null":
        return True
    if tok == ">&" and nxt in ("1", "2"):
        return True
    return False

def check_window(w, depth):
    # 1. Pull out redirects; leftover punctuation is an unrecognized construct.
    argv, i = [], 0
    while i < len(w):
        t = w[i]
        if t and set(t) <= PUNCT:
            nxt = w[i + 1] if i + 1 < len(w) else ""
            if _redirect_ok(t, nxt):
                i += 2
                continue
            deny("redirect/operator %r is not allowed" % t)
        argv.append(t)
        i += 1
    # 2. Command substitutions inside (quoted) tokens: classify each inner
    #    command as its own command line, same rules.
    for t in argv:
        for inner in _inner_cmds(t):
            check_command(inner, depth + 1)
    # 3. Leading VAR=val assignments scope to this command only -- harmless.
    while argv and ASSIGN_RE.match(argv[0]):
        argv.pop(0)
    if not argv:
        return
    if argv[0] == "#":
        return  # comment line
    argv0, rest = basename(argv[0]), argv[1:]
    # 4. Prefix wrappers unwrap one level per iteration (env/nice/command/
    #    nohup/time copied from irrecoverable.sh; rtk added: it is the
    #    parallel PreToolUse(Bash) rewriter in this environment and the model
    #    may type `rtk <cmd>` / `rtk proxy <cmd>` itself). rtk meta commands
    #    (gain/discover/flags) stay as argv0=rtk, which is allowlisted.
    while rest and argv0 in PREFIX_WRAPPERS:
        if argv0 == "env":
            i = 0
            while i < len(rest):
                t = rest[i]
                if t == "-u" and i + 1 < len(rest):
                    i += 2
                elif t.startswith("-"):
                    i += 1
                elif ASSIGN_RE.match(t):
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
        elif argv0 == "rtk":
            if rest[0] == "proxy":
                rest = rest[1:]
            if not rest or rest[0].startswith("-") or rest[0] in ("gain", "discover"):
                break
            argv0, rest = basename(rest[0]), rest[1:]
        else:  # command, nohup, time -- bare flags then the wrapped command
            i = 0
            while i < len(rest) and rest[i].startswith("-"):
                i += 1
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]
    # 5. Deny by default: interpreters (bash/sh/python/perl/node/eval/source/
    #    exec/xargs/...), sudo, tee, rm, mkdir, cp, mv, trash, npm, shellcheck
    #    -- anything not on the read-only allowlist -- all land here.
    if argv0 not in ALLOWED:
        deny("%r is not on the main-session read-only allowlist" % clip(argv0))
    chk = PER_CMD.get(argv0)
    if chk:
        chk(rest)

def check_command(cmd, depth=0):
    if depth > 5:
        deny("command substitution nested too deep")
    lex = shlex.shlex(_newlines_to_seps(cmd), posix=True, punctuation_chars=True)
    # `#` is never a comment to the tokenizer: bash only treats it as one at
    # word start, and letting shlex eat "a#; rm x" would hide the rm (false
    # negative). A window whose argv0 is `#` is skipped instead (see above).
    lex.commenters = ""
    # Chars bash treats as ordinary word chars but shlex would split off,
    # so `1,5p`, `+%Y`, `--format=%H` stay one token each.
    lex.wordchars += ",+%@:^"
    try:
        tokens = list(lex)
    except ValueError as e:
        deny("could not tokenize command (%s)" % e)
    windows, cur = [], []
    for tok in tokens:
        if tok in OPERATORS:
            if cur:
                windows.append(cur)
            cur = []
        else:
            cur.append(tok)
    if cur:
        windows.append(cur)
    for w in windows:
        check_window(w, depth)

def check_bash(cmd):
    if not isinstance(cmd, str):
        return False, "no command in tool_input", ""
    try:
        check_command(cmd)
    except Deny as e:
        return True, str(e), cmd
    except Exception as e:
        # A classifier bug is an unrecognized construct, not a malformed
        # payload: fail closed on the Bash leg.
        return True, "classifier error (%s: %s)" % (type(e).__name__, e), cmd
    return False, "read-only allowlist", cmd

# ------------------------------------------------------------------ verdict
agent_id = d.get("agent_id")
if agent_id:
    would_deny, reason, attempted = False, "subagent (agent_id present)", ""
elif tool_name in ("Write", "Edit", "MultiEdit"):
    would_deny, reason, attempted = check_write(ti.get("file_path"))
elif tool_name == "NotebookEdit":
    would_deny, reason, attempted = check_write(ti.get("notebook_path"))
elif tool_name == "Bash":
    would_deny, reason, attempted = check_bash(ti.get("command"))
else:
    would_deny, reason, attempted = False, "tool not covered", ""

if MODE == "log":
    # Calibration mode: never deny, append one row per evaluated call.
    row = json.dumps({
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "session_id": d.get("session_id"),
        "tool_name": tool_name,
        "agent_id_present": bool(agent_id),
        "agent_type": d.get("agent_type"),
        "would_deny": would_deny,
        "reason": reason,
    })
    log = os.path.join(HOME, ".local", "share", "kbg", "metrics", "main-exec-guard.jsonl")
    try:
        os.makedirs(os.path.dirname(log), exist_ok=True)
        # Refuse to write through a symlink (same guard as
        # nudge-compliance-tracker.sh / cost-tracker.sh).
        if not os.path.islink(log):
            # ponytail: unconditional line count on every call; a 25k-line file
            # is a few ms and this is calibration mode, not the enforcing path.
            if os.path.exists(log):
                with open(log, encoding="utf-8", errors="replace") as fh:
                    lines = fh.readlines()
                if len(lines) > 25000:
                    tmp = log + ".tmp"
                    with open(tmp, "w", encoding="utf-8") as fh:
                        fh.writelines(lines[-20000:])
                    os.replace(tmp, log)
            with open(log, "a", encoding="utf-8") as fh:
                fh.write(row + "\n")
    except Exception as e:
        notice("could not append log row (%s)" % e)
    sys.exit(0)

if not would_deny:
    sys.exit(0)

print("[mh:gate] BLOCKED: main-exec-guard — the top-level session plans and dispatches; "
      "it does not edit files, run mutating commands, or run tests. Dispatch a subagent "
      "(Agent tool, F9 template in skills/workflow/orchestrate/reference.md) to do this "
      "— including any config edit. Attempted: " + clip(attempted) + ". "
      "Off for one session: relaunch with MH_MAIN_EXEC_GUARD=0 in the environment.",
      file=sys.stderr)
print("[mh:gate] main-exec-guard reason: " + reason, file=sys.stderr)
sys.exit(2)
'
exit $?
