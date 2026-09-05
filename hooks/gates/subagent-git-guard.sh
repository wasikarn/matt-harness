#!/usr/bin/env bash
# Gate: a subagent (agent_id in the PreToolUse payload) may not run a bare
# `git stash|reset|clean` -- repo-wide mutation races peers on a shared tree
# (issue #135). Main session (no agent_id) is untouched; `claude --agent` main
# sessions also lack agent_id, so agent_type is NOT the discriminant.
# irrecoverable.sh already denies the destructive forms (reset --hard, clean -f,
# checkout --, restore <path>) for every session; this gate only adds the three
# non-force verbs, for subagents. Coarse pattern match, not a sandbox: quote-
# splitting or substitution of the word "git" itself is a non-goal, and a
# heredoc BODY line starting with "git stash" over-blocks (no heredoc parsing).
set -uo pipefail

# Portability guard (#93): announced fail-open when python3 is missing.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — subagent-git-guard gate cannot run; allowing (install python3 to restore the subagent git-guard rule)" >&2
  exit 0
fi

# Fast path: main-session calls (no agent_id) never reach python.
_input=$(cat)
case "$_input" in *'"agent_id"'*) ;; *) exit 0 ;; esac

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
printf '%s' "$_input" | python3 -c '
import json, re, sys

try:
    d = json.load(sys.stdin)
except Exception as e:
    # Fail-safe = ALLOW: a parse error must not stall every subagent Bash call.
    print(f"[mh:gate] subagent-git-guard: unparseable stdin, allowing ({e})", file=sys.stderr)
    sys.exit(0)

if not isinstance(d, dict):
    print("[mh:gate] subagent-git-guard: non-object payload, allowing", file=sys.stderr)
    sys.exit(0)

if d.get("tool_name") != "Bash":
    sys.exit(0)

# agent_id is present ONLY inside a subagent call.
agent_id = d.get("agent_id")
if not agent_id:
    sys.exit(0)

ti = d.get("tool_input")
cmd = ti.get("command") if isinstance(ti, dict) else None
if not isinstance(cmd, str):
    sys.exit(0)

def clip(s):
    # Log-injection guard: a crafted command cannot forge/erase a [mh:gate] line.
    s = re.sub(r"[^\x20-\x7e]", "?", str(s))
    return s[:120]

agent_type = clip(d.get("agent_type") or "unknown")

# Quote-aware masking: every char inside a quoted span (quotes included) becomes
# a placeholder that matches neither a separator, "git", nor a flag; output
# length equals input so match positions still line up with cmd. Single-quote
# spans are literal, double-quote spans honor backslash escapes, as in bash.
# chr() for the quote chars: this block sits inside a bash single-quoted string.
# ponytail: no handling for a backslash-escaped quote OUTSIDE a span; add a
# one-char lookback if a real false positive/negative traces to it.
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

masked = _mask_quotes(cmd)

# Anchor: "git" must sit at a real command-start (string/line start, |;&(, &&,
# ||, optional VAR=val chain, optional sudo/xargs wrapper, or a /path/git).
# re.MULTILINE so each line of a multi-line command anchors. Runs on the masked
# string, so `git commit -m "fix; git reset was wrong"` never anchors inside
# the quotes.
_ANCHOR_RE = re.compile(
    r"(?:^|[|;&(]|&&|\|\|)\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*"
    r"(?:sudo\s+(?:\S+\s+)*|xargs\s+(?:\S+\s+)*)?(?:\S*/)?git\b",
    re.MULTILINE,
)
# Only stash/reset/clean (see header); read-only `stash list|show` carved out.
_DENY_SUBCMD_RE = re.compile(r"\A\s+(stash(?!\s+(list|show)\b)|reset|clean)\b")

# Git global flags walked past before the subcommand check, so `git -C /repo
# stash` / `git --no-pager clean` do not land the check on sub="-C".
_GIT_VALUE_GLOBALS = ("-C", "-c", "--git-dir", "--work-tree", "--config-env")

def _skip_git_globals(tail):
    # tail starts right after the "git" anchor on the masked string. Returns the
    # suffix from the first non-flag token, leading whitespace intact for \A\s+.
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
        i += m.end()  # any other flag, bare or combined: --git-dir=X, --no-pager, -p, ...

def _violation(masked_cmd):
    for m in _ANCHOR_RE.finditer(masked_cmd):
        dm = _DENY_SUBCMD_RE.match(_skip_git_globals(masked_cmd[m.end():]))
        if dm:
            return dm.group(1)
    return None

hit = _violation(masked)
if hit:
    print(f"[mh:gate] BLOCKED: subagent ({agent_type}) may not run `git {hit}` "
          f"(command: {clip(cmd)!r}) -- no repo-wide git in a concurrent wave "
          f"(docs/METHODOLOGY.md Rule 13); scope every git command to files you own. "
          f"(git checkout -- / git restore are already denied unconditionally, "
          f"for every session, by gate:bash:irrecoverable when they would "
          f"discard working-tree changes -- not this gate'"'"'s job.)", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
'
exit $?
