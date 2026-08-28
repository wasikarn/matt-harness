#!/usr/bin/env bash
# Gate: ask before a raw `gh pr merge` runs outside the `ship-merge` skill flow.
# `convergence-merge-gate.sh` used to cover this and was retired 2026-08-24
# with the review pipeline (#82) — ship-merge/SKILL.md's own text admits its
# in-flow gates are "now the only merge-door protection", but those only fire
# when the model goes through the Skill call; a raw Bash `gh pr merge` had
# zero hook coverage until this file. Reads the PreToolUse JSON payload from
# stdin; emits `permissionDecision: ask` (exit 0) on a match, never a hard
# deny — a human can still approve a legitimate emergency merge in the
# moment, same tier `verifier-protect.sh` uses for tamper-sensitive edits.
#
# Known, deliberate non-goal: the REST equivalent (`gh api ... /pulls/N/merge`)
# is NOT covered. Catching every way to reach that endpoint is an arms race
# this gate does not try to win — `gh pr merge` is the documented, ordinary
# path `ship-merge` itself uses and the one operators actually type.
set -uo pipefail

# Fast path: skip the python3 cold-start unless both "gh" and "merge" survive
# a light normalize — same optimization idiom as irrecoverable.sh's own
# fast-path (a false positive here just spawns python; safe direction).
_input="$(cat)"
_norm="$(printf '%s' "$_input" | sed 's/\\[nt]/ /g' | tr -s '[:space:]' ' ' | tr -d "\"'\\")"
case "$_norm" in
  *gh*merge*) : ;;  # candidate -> python
  *) exit 0 ;;      # neither token present -> allow
esac

# Portability guard (#93): announced fail-open when python3 is missing;
# doctrine-bootstrap.sh names the missing dep once at SessionStart.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — merge-door gate cannot run; allowing (install python3 to restore the gh pr merge ask)" >&2
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
printf '%s' "$_input" | python3 -c '
import json, re, shlex, sys

sys.path.insert(0, sys.argv[1])
from _hook_output import emit_ask

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)  # malformed payload — nothing to classify, allow (this is ask-tier, not deny)

if not isinstance(d, dict) or not isinstance(d.get("tool_input"), dict):
    sys.exit(0)

SQ = chr(39)
_HEREDOC_RE = re.compile(r"<<(-)?\s*([" + SQ + r"\"]?)([^\s" + SQ + r"\"]+)\2")
_INTERPRETER_RE = re.compile(r"\b(bash|sh|zsh|dash|ksh|python3?|python2|perl|ruby|node|nodejs|osascript)\b")

def _strip_heredocs(cmd):
    # Ported from irrecoverable.sh (function of the same name — that file
    # ported it from verifier-protect.sh, itself from worktree-guard.py
    # 2026-08-04). Without this, a HEREDOC commit message that merely
    # MENTIONS "gh pr merge" in prose (this repo commits that way by
    # convention) would tokenize as a real command and false-positive the
    # ask — reproduced as a live bug in irrecoverable.sh 2026-08-06 for the
    # exact same shape.
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
            out.extend(lines[body_start:i])
    return "\n".join(out)

cmd = _strip_heredocs(d["tool_input"].get("command", ""))

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

PREFIX_WRAPPERS = {"env", "command", "nohup", "nice", "time", "sudo"}

for w in windows:
    if not w:
        continue
    argv0, rest = basename(w[0]), w[1:]

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

    if argv0 == "gh" and len(rest) >= 2 and rest[0] == "pr" and rest[1] == "merge":
        emit_ask(
            "merge-door: a raw `gh pr merge` was about to run outside the "
            "ship-merge skill flow. Use mh:ship-merge for the reviewed path, "
            "or approve this specific merge now."
        )
        sys.exit(0)

sys.exit(0)
' "$(dirname "$0")/lib"
