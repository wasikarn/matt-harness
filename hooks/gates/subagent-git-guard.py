#!/usr/bin/env python3
import json, re, sys

# GH #156: raise the int-string digit limit before parsing so an oversized
# unquoted int literal doesn't crash json.load() into this gate's fail-open
# except below (full rationale: codex-setup-guard.py). hasattr-guarded: the
# method doesn't exist before Python 3.11.
if hasattr(sys, "set_int_max_str_digits"):
    sys.set_int_max_str_digits(0)

try:
    from _journal import journal
except Exception:
    def journal(*a, **k):
        pass

GATE_ID = "gate:bash:subagent-git-guard"

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
# chr() for the quote chars keeps this masking logic free of literal quote
# characters in its own source.
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
          f"(docs/METHODOLOGY.md Rule 13); scope every git command to files you own.", file=sys.stderr)
    journal(GATE_ID, "Bash", "deny", d.get("session_id"))
    sys.exit(2)
sys.exit(0)
