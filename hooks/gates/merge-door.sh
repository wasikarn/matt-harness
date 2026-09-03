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
# path `ship-merge` itself uses and the one operators actually type. Unlike
# irrecoverable.sh, PREFIX_WRAPPERS below has no xargs/docker-exec unwrap, so
# a wrapped form like `echo x | xargs -I{} gh pr merge {}` also isn't caught
# (deep-audit 2026-08-28) — same reasoning: not the ordinary typed path.
set -uo pipefail

# Fast path: skip the python3 cold-start unless both "gh" and "merge" survive
# a light normalize — same optimization idiom as irrecoverable.sh's own
# fast-path (a false positive here just spawns python; safe direction).
_input="$(cat)"
_norm="$(printf '%s' "$_input" | sed 's/\\[nt]/ /g' | tr -s '[:space:]' ' ' | tr -d "\"'\\")"
# A backslash-newline continuation splitting "gh" or "merge" itself (e.g.
# "g\<newline>h pr merge 123") turns the \n escape into a space above, so
# neither candidate substring survives and the case below would exit 0
# without ever reaching the python scanner that reassembles it correctly
# -- confirmed live 2026-09-03, GH #126 (same "GH #122 adjacent finding"
# shape already fixed this way in irrecoverable.sh). A second, fully
# whitespace-collapsed variant catches that shape too; a false positive
# here just costs a python spawn, same safe direction as above.
_norm_nows="$(printf '%s' "$_norm" | tr -d '[:space:]')"
case "$_norm$_norm_nows" in
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

# Insert a literal ";" after each real newline (not in place of it, so a
# following "#" comment still stops there) -- a backslash immediately
# before the newline is a real line continuation, not a separator: bash
# removes BOTH characters entirely, joining the two lines with nothing
# between them, so nothing is emitted for that pair either (2026-09-03,
# GH #126 -- mirrors the same fix already shipped in irrecoverable.sh /
# main-exec-guard.sh / worktree-guard.py / verifier-protect.sh). The
# prior version put the literal "\<newline>" back unchanged, which left
# a stray embedded newline glued onto a token when there was no
# whitespace around the continuation (e.g. "g\<newline>h pr merge 123"
# tokenized argv0 as "g\nh", never "gh") -- confirmed live, ground-truthed
# against real bash, and a genuine bypass of the exact-match argv0/token
# dispatch below. Ported from the _newlines_to_seps helper in
# worktree-guard.py (2026-08-04).
def _newlines_to_seps(s):
    s = re.sub(r"\\\n", "", s)
    return s.replace("\n", "\n; ")

# shlex.split() only recognizes ;/&&/||/|/& as separators when whitespace
# already surrounds them -- "git push;gh pr merge 123" tokenized as one
# glued word "push;gh", so the second command in the chain never had its
# own argv0 checked (deep-audit 2026-08-28). punctuation_chars=True makes
# shlex split these out as their own tokens even with no surrounding
# space, while still respecting quotes -- a genuinely-quoted ";" inside
# an argument stays inside that one token. Grouping tokens ( ) { } get
# the same treatment: without it, "(gh pr merge 123)" or "{ gh pr merge
# 123; }" left a bare "(" / "{" as argv0 instead of "gh" -- a subshell/
# brace-group bypass of the identical shape. Ported from
# verifier-protect.sh / worktree-guard.py, which already use this
# pattern for their own write-target detection.
OPERATORS = {";", "&&", "||", "|", "&", "(", ")", "{", "}"}
try:
    tokens = list(shlex.shlex(_newlines_to_seps(cmd), posix=True, punctuation_chars=True))
except ValueError:
    tokens = cmd.split()
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
        elif argv0 == "sudo":
            # sudo -u/-g (short or long) select the effective identity and
            # take a value. Handles space-joined, "="-joined long form, and
            # attached short form ("-ualice") in one pass, PLUS bundled
            # short flags where u/g sits anywhere in a combined token --
            # standard getopt short-option semantics: once a value-taking
            # character is hit, everything after it in that same token is
            # the value for that flag, and only an empty remainder falls
            # through to the next token. So "-nu alice" (n takes no value,
            # u is last in the token) reads "alice" as the value for -u,
            # taken from the next token -- but "-un alice" (u first, "n"
            # left over in the same token) reads the attached "n" as the
            # value for -u, so "alice" is the real wrapped command, not a
            # value -- both resolved correctly below (deep-audit
            # 2026-08-28, issue #115 fix only matched exact "-u"/"-g"
            # tokens and missed every bundled form, e.g. "sudo -nu alice
            # gh pr merge 123" still bypassed this gate after that fix).
            # Other sudo flags that also take a value (-p, -C, -R, -T, -U)
            # are not modeled here -- a bundle mixing one of those with
            # u/g (e.g. "-pu") is an accepted non-goal, same tier as the
            # habit-guard-not-adversarial-sandbox stance this file already
            # takes in its header comment above.
            LONG_VALUE_FLAGS = {"--user", "--group"}
            i = 0
            while i < len(rest):
                t = rest[i]
                bare = t.split("=", 1)[0]
                if bare in LONG_VALUE_FLAGS:
                    i += 1 if "=" in t else min(2, len(rest) - i)
                elif t.startswith("--"):
                    i += 1
                elif t.startswith("-") and len(t) > 1:
                    m = re.search(r"[ug]", t[1:])
                    if m:
                        attached = m.end() < len(t[1:])
                        i += 1 if attached else min(2, len(rest) - i)
                    else:
                        i += 1
                else:
                    break
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]
        else:  # command, nohup, time — bare flags then the wrapped command
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
