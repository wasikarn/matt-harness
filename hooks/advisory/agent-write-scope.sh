#!/usr/bin/env bash
# Sensor (not a gate) -- per-agent write-scope journal, issue #137, rev 4
# (log-mode). NEVER denies anything -- Write/Edit/MultiEdit/NotebookEdit and
# Bash `git commit` always proceed unmodified. Two legs, one script (same
# shape as main-exec-guard.sh and subagent-git-guard.sh), wired under two
# separate matchers -- a recorder on every subagent write and an enforcer
# that journals unrecorded paths on a subagent's `git commit`.
#
# Lives in hooks/advisory/, not hooks/gates/ (moved here from an initial
# hooks/gates/ placement, code review, issue #137): docs/reference/
# operating-model.md states the split in prose twice ("advise on the rest
# (sensors in hooks/advisory/)"; "advisory/ (journal)"), and this script's own
# header already called itself a sensor, not a gate. hooks/session/ was the
# other candidate (skill-usage-telemetry.sh is a journal-only PostToolUse
# hook that lives there) but was rejected: hooks/gates/verifier-protect.sh's
# ask-gate protects hooks/gates/** + hooks/advisory/** (tamper-resistance --
# the model cannot edit the code that judges it) and does NOT cover
# hooks/session/**. This sensor's journal is the evidence a future session
# uses to decide whether to flip write-scope to real enforcement, so losing
# that protection would let the model shape the data that later judges it --
# the same maker-can't-grade-its-own-work circularity the whole operating
# model exists to avoid. Not split into two files across two dirs: both legs
# are the same journal-only, never-denies behavior, so there is no dir split
# to make.
#
#   Recorder leg -- PostToolUse (Write|Edit|MultiEdit|NotebookEdit): records
#   the normalized repo-root-relative path of every file a subagent writes,
#   one JSONL line per call, into
#   ~/.local/share/kbg/mh-agent-writes/<safe-agent-id>.jsonl. Always exits 0.
#   No-ops when agent_id is absent (main session).
#
#   Enforcer leg -- PreToolUse (Bash): fires only on a `git commit`
#   invocation by a subagent (agent_id present). Enumerates the paths that
#   commit would actually commit (staged, plus tracked-modified paths too
#   when -a/--all is present), compares against that agent_id's recorded
#   write-set, and journals which committed paths were never recorded as
#   written by this agent -- the would-have-been-denied signal a later real
#   enforcement decision would read. Also journals write_state_file_present
#   (bool: did a write-state file exist at all for this agent_id) and
#   recorded_write_count (int: how many write events are on record) so the
#   journal itself can distinguish "this agent wrote nothing" from "the
#   recorder leg never correlated for this agent_id at all." NEVER exits
#   non-zero. Journal: ~/.local/share/kbg/metrics/agent-write-scope.jsonl,
#   same append/rotate/symlink-refuse mechanics as hooks/gates/main-exec-guard.sh's
#   own log mode (read fresh, matched here rather than inventing a new
#   format).
#
# Rev history: rev 1 (write-time allowlist) false-denied every non-F9
# subagent. Rev 2 (session-scoped ownership) was killed by an undocumented
# Agent PreToolUse field. Rev 3 (per-agent write-tracking, deny-mode) was
# rejected on review -- the agent_id-correlates-across-legs premise was
# unverified in this repo, and its escape hatch was an env var a subagent
# facing a live deny cannot set for itself. Rev 4 (this file) removes the
# deny path entirely: nothing is ever blocked, so the escape-hatch problem
# dissolves by construction -- there is nothing to escape when nothing is
# ever denied. The agent_id-correlates-across-legs premise does NOT dissolve
# the same way: it is demoted from a safety-critical unverified assumption
# (rev 3's deny path would have shipped on an unverified correlation) to an
# observable data-quality question. Every enforcer-leg journal row now
# carries write_state_file_present (bool) and recorded_write_count (int) --
# see enforce_commit() below -- so a future session can tell "this agent_id
# legitimately wrote nothing" from "the recorder leg never fired/correlated
# for this agent_id at all" directly from the journal, without a separate
# live probe. This ships a sensor, not a gate; flipping to real enforcement
# is a deliberate follow-up decision, made once the journal shows a real
# false-positive rate AND shows write_state_file_present is reliably true.
#
# Reuses _mask_quotes / _ANCHOR_RE / _skip_git_globals / clip() from
# hooks/gates/subagent-git-guard.sh, byte-for-byte (same quote-aware,
# global-flag-aware, re.MULTILINE-anchored git-invocation detection those
# fixes already earned), the STATE_DIR/sanitizer pattern from
# hooks/gates/atlassian-mcp-gate.sh (keyed on agent_id instead of
# session_id), and the journal append/rotate/symlink-refuse mechanics from
# hooks/gates/main-exec-guard.sh's own `log` mode.
#
# Bug fixes this rev makes over a naive implementation (verified live before
# shipping, same as the plan describes):
#   - `git diff --cached --name-only -z` (NOT the unquoted form): -z
#     NUL-delimits and disables path quoting, so a non-ASCII path lines up
#     byte-for-byte with the path the recorder leg stored. The quoted form
#     would never match.
#   - `-a`/`--all` detection walks the real short-flag bundling rules
#     `git commit` itself uses (value-taking flags -m/-c/-C/-F/-t consume the
#     rest of their own token, or the next token when their own token is
#     exhausted) instead of a naive per-character scan -- confirmed live in a
#     scratch repo: `git commit -am "msg"` sets -a and gives -m the next
#     token; `git commit -ma "msg"` gives -m the value "a" from the SAME
#     token and never sets -a at all ("msg" is left over as a stray
#     pathspec). -S/-u take an OPTIONAL value that, per git's own parser,
#     is only ever attached in the same token -- neither ever pulls a
#     separate following token as its value, confirmed live the same way.
#     (Also checked live: git commit has no -A short flag at all -- "unknown
#     switch" -- so it is excluded here even though an earlier draft of this
#     plan listed it.)
#   - A non-zero `git diff` exit (rc=128 on an unborn HEAD, or mid-merge/
#     mid-rebase) journals the enumeration failure (committed_paths and
#     unrecorded_paths both null) rather than reading empty stdout as
#     "nothing staged."
#
# Non-goals, named not solved (see the plan): builder-stages/main-commits
# attribution split (this keys on the COMMITTING agent_id, not the staging
# actor); a path committed that was created via Bash redirect/mv/build
# artifact rather than Write/Edit/MultiEdit/NotebookEdit always shows as
# unrecorded -- expected noise, not a bug; `git rm`/deletions show as
# unrecorded for the same reason; obfuscating the literal word "git" itself;
# non-repo-root cwd and `git commit -- <pathspec>` over-broad enumeration.
set -uo pipefail

# Portability guard (#93): announced fail-open when python3 is missing.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:sensor] python3 not found -- agent-write-scope sensor cannot run; no-op (install python3 to restore write-scope journaling)" >&2
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import json, os, re, subprocess, sys, time

def notice(msg):
    print("[mh:sensor] agent-write-scope: " + msg, file=sys.stderr)

def clip(s):
    # Same log-injection guard as the sibling gates: strip non-printable
    # bytes and cap length so a crafted path/command cannot forge or erase a
    # preceding stderr line.
    s = re.sub(r"[^\x20-\x7e]", "?", str(s))
    return s[:120]

_SQ = chr(39)
_DQ = chr(34)

def _mask_quotes(s):
    out = []
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == _SQ:
            out.append(" "); i += 1
            while i < n and s[i] != _SQ:
                out.append("Q"); i += 1
            if i < n:
                out.append(" "); i += 1
        elif c == _DQ:
            out.append(" "); i += 1
            while i < n and s[i] != _DQ:
                if s[i] == "\\" and i + 1 < n:
                    out.append("Q"); out.append("Q"); i += 2
                else:
                    out.append("Q"); i += 1
            if i < n:
                out.append(" "); i += 1
        else:
            out.append(c); i += 1
    return "".join(out)

_ANCHOR_RE = re.compile(
    r"(?:^|[|;&(]|&&|\|\|)\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*"
    r"(?:sudo\s+(?:\S+\s+)*|xargs\s+(?:\S+\s+)*)?(?:\S*/)?git\b",
    re.MULTILINE,
)
_GIT_VALUE_GLOBALS = ("-C", "-c", "--git-dir", "--work-tree", "--config-env")

def _skip_git_globals(tail):
    i = 0
    while True:
        m = re.match(r"\s+(\S+)", tail[i:])
        if not m:
            return tail[i:]
        tok = m.group(1)
        if not tok.startswith("-"):
            return tail[i:]
        if tok in _GIT_VALUE_GLOBALS:
            i += m.end()
            m2 = re.match(r"\s+\S+", tail[i:])
            if m2:
                i += m2.end()
            continue
        i += m.end()

try:
    d = json.load(sys.stdin)
except Exception as e:
    notice("unparseable stdin, no-op (%s)" % e)
    sys.exit(0)

if not isinstance(d, dict):
    sys.exit(0)

agent_id = d.get("agent_id")
if not agent_id:
    sys.exit(0)  # main session -- both legs are subagent-only by design

agent_type = clip(d.get("agent_type") or "unknown")
tool_name = d.get("tool_name")

def _safe_id(raw):
    return re.sub(r"[^a-zA-Z0-9_-]", "_", str(raw))

WRITE_DIR = os.path.expanduser("~/.local/share/kbg/mh-agent-writes")
JOURNAL = os.path.expanduser("~/.local/share/kbg/metrics/agent-write-scope.jsonl")

# --------------------------------------------------------------- recorder leg
def _repo_root():
    # Same resolution order as hooks/gates/irrecoverable.sh: CLAUDE_PROJECT_DIR
    # env first, then `git rev-parse --show-toplevel` -- git resolves this
    # correctly for linked worktrees (where .git is a file, not a dir -- a
    # hand-rolled isdir(.git) ancestry walk misses those) and for any cwd
    # depth. Fail-open on any failure, same as before: fall back to cwd.
    root = os.environ.get("CLAUDE_PROJECT_DIR") or ""
    if root and os.path.isdir(root):
        return os.path.realpath(root)
    try:
        p = subprocess.run(
            ["git", "-C", os.getcwd(), "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
        if p.returncode == 0 and p.stdout.strip():
            return os.path.realpath(p.stdout.strip())
    except Exception:
        pass
    return os.path.realpath(os.getcwd())

def _normalize(raw_path, root):
    p = os.path.realpath(os.path.expanduser(raw_path))
    prefix = root + os.sep
    if p.startswith(prefix):
        return p[len(prefix):]
    return p  # outside repo root: kept absolute, will read as unrecorded noise

def record_write():
    ti = d.get("tool_input")
    ti = ti if isinstance(ti, dict) else {}
    raw = ti.get("notebook_path") if tool_name == "NotebookEdit" else ti.get("file_path")
    if not isinstance(raw, str) or not raw:
        return
    rel = _normalize(raw, _repo_root())
    row = json.dumps({
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "tool_name": tool_name,
        "path": rel,
    })
    path = os.path.join(WRITE_DIR, _safe_id(agent_id) + ".jsonl")
    try:
        os.makedirs(WRITE_DIR, exist_ok=True)
        if not os.path.islink(path):
            with open(path, "a", encoding="utf-8") as fh:
                fh.write(row + "\n")
    except Exception as e:
        notice("could not append write-record (%s)" % e)

# --------------------------------------------------------------- enforcer leg
# git commit short flags that take a MANDATORY value: the rest of their own
# token if non-empty, else the whole next token. Confirmed live 2026-09-04
# against `git commit -h` and a scratch repo -- no -A short flag exists at
# all ("unknown switch"), and -o/-u are NOT in this set (-o is bare, -u only
# ever takes an attached optional value, see below).
_VALUE_FLAGS = set("mcCFt")
# git commit short flags whose value, if given, is ONLY ever attached in the
# same token -- they never pull a separate following token.
_OPT_VALUE_FLAGS = set("Su")

def _commit_has_all_flag(tokens):
    has_all = False
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t == "--":
            break
        if t == "--all":
            has_all = True
            i += 1
            continue
        if t.startswith("--") or not t.startswith("-") or len(t) < 2:
            i += 1
            continue
        j = 1
        consumed_next = False
        while j < len(t):
            c = t[j]
            if c == "a":
                has_all = True
                j += 1
                continue
            if c in _VALUE_FLAGS:
                if j + 1 >= len(t):
                    consumed_next = True
                break
            if c in _OPT_VALUE_FLAGS:
                break
            j += 1
        i += 2 if consumed_next else 1
    return has_all

def _find_commit_windows(masked_cmd):
    windows = []
    for m in _ANCHOR_RE.finditer(masked_cmd):
        tail = masked_cmd[m.end():]
        skipped = _skip_git_globals(tail)
        sub_m = re.match(r"\A\s+(\S+)", skipped)
        if not sub_m or sub_m.group(1) != "commit":
            continue
        consumed = len(tail) - len(skipped)
        args_start = m.end() + consumed + sub_m.end()
        sep_m = re.search(r"[;&|()\n]", masked_cmd[args_start:])
        args_end = args_start + sep_m.start() if sep_m else len(masked_cmd)
        windows.append((args_start, args_end))
    return windows

def _git_diff(args):
    try:
        p = subprocess.run(
            ["git", "--no-pager", "diff"] + args,
            capture_output=True, timeout=10,
        )
    except Exception as e:
        return False, None, clip(str(e))
    if p.returncode != 0:
        return False, None, clip((p.stderr or b"").decode("utf-8", "replace"))
    out = p.stdout.decode("utf-8", "replace")
    return True, [x for x in out.split("\x00") if x], None

def _write_set():
    # Returns (file_present, seen_paths, recorded_write_count).
    #
    # file_present distinguishes the two situations an empty `seen` set used
    # to conflate: (a) this agent_id legitimately never wrote anything, vs.
    # (b) the recorder leg never fired/correlated for this agent_id at all
    # (e.g. agent_id not actually populated on PostToolUse in this Claude
    # Code version -- the open, unverified correlation question this whole
    # sensor exists to answer). Without this field the journal cannot tell
    # "clean" from "broken", which defeats the whole point of the sensor.
    #
    # recorded_write_count is the number of individual write EVENTS on
    # record (JSONL lines with a valid string path) -- deliberately NOT
    # len(seen_paths), which collapses repeat writes to the same path into
    # one entry and would understate how much recorder activity exists.
    path = os.path.join(WRITE_DIR, _safe_id(agent_id) + ".jsonl")
    seen = set()
    count = 0
    file_present = os.path.exists(path)
    if not file_present:
        return file_present, seen, count
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except Exception:
                    continue
                p_ = row.get("path") if isinstance(row, dict) else None
                if isinstance(p_, str):
                    seen.add(p_)
                    count += 1
    except Exception:
        pass
    return file_present, seen, count

def _append_journal(row):
    try:
        os.makedirs(os.path.dirname(JOURNAL), exist_ok=True)
        if os.path.islink(JOURNAL):
            return
        if os.path.exists(JOURNAL):
            with open(JOURNAL, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
            if len(lines) > 25000:
                tmp = JOURNAL + ".tmp"
                with open(tmp, "w", encoding="utf-8") as fh:
                    fh.writelines(lines[-20000:])
                os.replace(tmp, JOURNAL)
        with open(JOURNAL, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(row) + "\n")
    except Exception as e:
        notice("could not append journal row (%s)" % e)

def enforce_commit(cmd):
    masked = _mask_quotes(cmd)
    for args_start, args_end in _find_commit_windows(masked):
        tokens = masked[args_start:args_end].split()
        has_all = _commit_has_all_flag(tokens)
        ok, staged, _err = _git_diff(["--cached", "--name-only", "-z"])
        unstaged = []
        if ok and has_all:
            ok2, unstaged2, _err2 = _git_diff(["--name-only", "-z", "HEAD"])
            if not ok2:
                ok = False
            else:
                unstaged = unstaged2
        # Computed unconditionally, independent of whether git enumeration
        # (below) succeeded -- these two are facts about the recorder leg,
        # not about the diff. An enumeration failure (unborn HEAD etc.) still
        # journals whether the recorder ever fired for this agent_id, so
        # "git diff failed AND the recorder never correlated" stays
        # distinguishable from "git diff failed but correlation is fine."
        wfile_present, wset, wcount = _write_set()
        if not ok:
            committed_paths = None
            unrecorded_paths = None
        else:
            merged = []
            for p_ in staged + unstaged:
                if p_ not in merged:
                    merged.append(p_)
            committed_paths = merged
            unrecorded_paths = [p_ for p_ in merged if p_ not in wset]
        _append_journal({
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "agent_id": clip(agent_id),
            "agent_type": agent_type,
            "cmd": clip(cmd),
            "committed_paths": committed_paths,
            "unrecorded_paths": unrecorded_paths,
            "write_state_file_present": wfile_present,
            "recorded_write_count": wcount,
        })

# ------------------------------------------------------------------- dispatch
try:
    if tool_name in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        record_write()
    elif tool_name == "Bash":
        ti = d.get("tool_input")
        cmd = ti.get("command") if isinstance(ti, dict) else None
        if isinstance(cmd, str):
            enforce_commit(cmd)
except Exception as e:
    # Sensor contract: NEVER exits non-zero, no matter what breaks.
    notice("internal error, no-op (%s: %s)" % (type(e).__name__, e))

sys.exit(0)
'
# Sensor contract for both legs: never signal failure via exit code, no
# matter what the python body above did internally.
exit 0
