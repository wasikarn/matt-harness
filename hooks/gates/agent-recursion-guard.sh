#!/usr/bin/env bash
# Gate: a subagent may not spawn another agent — only the main session dispatches.
# Reads the PreToolUse JSON payload from stdin; exits 2 to block. Two legs,
# one script (same pattern as verifier-protect.sh's Write/Edit + Bash legs):
# tool_name == "Agent" catches the structured dispatch path; tool_name ==
# "Bash" catches a subagent spawning a nested `claude -p ...` session, which
# never routes through the Agent tool at all and would otherwise reset the
# discriminant (a nested claude invocation is its own fresh main session,
# free to dispatch further agents unrestricted).
#
# Why: this repo's own dispatch doctrine already states the rule in prose
# (CLAUDE.md "Task Dispatch": "If you are a sub-agent dispatched for a scoped
# task: do not re-orchestrate... you own one well-bounded deliverable") and
# orchestrate/SKILL.md repeats it ("the lead is the clamp, every time"). Until
# this gate, nothing enforced it computationally. Confirmed exploitable
# 2026-08-31 (deep-audit finding, see mh-memory
# fork-recursive-spawn-rogue-behavior-2026-08-31.md): a rogue fork that hit
# the host's own fork->fork block ("Fork is not available inside a forked
# worker") simply switched subagent_type to general-purpose instead, which
# succeeded and spawned 4 real background agents the parent never saw. The
# host's nested-spawn block is fork-specific, not a general recursion guard —
# `general-purpose`/`claude`/`fork` all retain full tool access (including
# Agent and Bash) once dispatched, per this session's own agent listing.
#
# Native CC fires PreToolUse inside subagents with `agent_id` present
# (docs-confirmed against code.claude.com/docs/en/hooks, 2026-08-31). Keyed
# on `agent_id`, NOT `agent_type` — a same-day adversarial security review
# caught that `agent_type` is ALSO set for a top-level `claude --agent <name>`
# main session (not a subagent), which would have over-blocked that
# legitimate case. `agent_id` is present only for an actual subagent call —
# same fix applied to the sibling gate hooks/gates/task-complete-separation.sh,
# which shared the identical flaw.
#
# Rule: deny Agent(...) or a Bash-mediated `claude -p`/`--print`/`--agent`/
# `--bg` invocation whenever `agent_id` is present (any subagent, regardless
# of what subagent_type it's trying to spawn or how). The main session (no
# `agent_id`) owns dispatch. No env-var bypass — same choice as
# task-complete-separation.sh: this enforces the harness's own dispatch
# architecture, not a situational judgment call a human should override case
# by case. The Bash-command pattern is a coarse habit-guard, not an
# adversarial sandbox — same accepted scope as irrecoverable.sh's own
# command-substitution/eval non-goal; it does not attempt to defeat
# deliberate obfuscation (quote-splitting, variable indirection).
#
# Anchored on command position (a fresh adversarial pass, 2026-08-31,
# reproduced the un-anchored version denying `git commit -m "mention claude
# -p in docs"`, `echo "claude -p"`, and `grep -r "claude -p" docs/` — real,
# concrete false positives; a subagent could not even document or grep this
# gate's own regex without tripping it). Requires "claude" to sit right
# after a command-start position (string start, `|`/`;`/`&`/`(`, `&&`, `||`)
# or a `VAR=val` prefix chain, which is what a real invocation always looks
# like and what plain prose almost never does. A shlex-token rewrite was
# tried and rejected: tokenizing swallows `$(claude -p evil)` into one opaque
# token (`$(claude`), silently defeating the ONE thing this leg exists to
# catch. This anchor keeps that detection (`(` is itself an anchor char, so
# `$(claude` still matches) while clearing the false positives above.
#
# Confirmed collision, resolved as by-design (2026-09-01, issue #118):
# `mattpocock-skills:code-review` fans out its own internal sub-reviews as parallel
# sub-agents (its own SKILL.md, around lines 11 and 58). Reproduced live: Skill-calling
# it from inside a dispatched subagent has BOTH internal dispatches denied by this gate
# (caller carries agent_id), so the skill produces no report from a subagent context.
# Deliberately NOT carved out — the gate cannot distinguish a skill's documented internal
# fan-out from rogue re-orchestration (same agent_id, same Agent(...) shape), and any
# discriminant would be forgeable by model output. Standing rule: invoke
# mattpocock-skills:code-review from the main session only. Same rule covers
# mattpocock-skills:research and :grilling (2026-09-01 sweep finding) — both
# also document internal sub-agent dispatch, so both hit this same denial
# from inside a dispatched subagent.
#
# The flag search after the anchor is a quote-aware scan (deep-audit,
# 2026-08-31, "fix it all" pass), not a flat char-class exclusion — a flat
# `[^|;&]*` treated ANY `&`/`;`/`|` as end-of-invocation, including one
# sitting inside a quoted prompt argument (`claude "fix A & B" -p`), which
# silently defeated detection: a false NEGATIVE, the dangerous direction. A
# whole quoted span is consumed as one token so an in-quote separator is
# never mistaken for a real one, while a bare (unquoted) separator still
# correctly ends the scan at the next real command — verified against both
# directions (the quoted-separator evasions now deny; the commit-message/
# echo/grep false positives above still allow; cross-segment separation
# still holds, e.g. `claude --version ; othertool -p` does not match).
set -uo pipefail

# Portability guard (#93): announced fail-open when python3 is missing.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — agent-recursion-guard gate cannot run; allowing (install python3 to restore the dispatch-only-from-main-session rule)" >&2
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import json, re, sys

try:
    d = json.load(sys.stdin)
except Exception as e:
    # Fail-safe = ALLOW. A parse error must not stall every agent dispatch —
    # same choice as task-complete-separation.sh for the same reason.
    print(f"[mh:gate] agent-recursion-guard: unparseable stdin, allowing ({e})", file=sys.stderr)
    sys.exit(0)

if not isinstance(d, dict):
    print("[mh:gate] agent-recursion-guard: non-object payload, allowing", file=sys.stderr)
    sys.exit(0)

tool_name = d.get("tool_name")
if tool_name not in ("Agent", "Bash"):
    sys.exit(0)

# agent_id is present ONLY when the hook fires inside a subagent call.
# Absent => main session (--agent or not) => allowed to dispatch however it likes.
agent_id = d.get("agent_id")
if not agent_id:
    sys.exit(0)

def clip(s):
    # Log-injection guard (security review, 2026-08-31): both agent_type and
    # tool_input values below can originate from a subagent'"'"'s own tool call —
    # model-influenceable, unlike the host-supplied agent_id. Strip control
    # chars (not just \n/\r — a fresh adversarial pass, 2026-08-31, confirmed
    # ANSI cursor codes and U+2028/U+0085 line separators survive a
    # newline-only strip, letting a crafted subagent_type overwrite a
    # preceding terminal line) so a crafted value cannot forge an extra
    # "[mh:gate] ..." line or erase this one, and cap length so a denial
    # cannot be used to burn arbitrary context.
    s = re.sub(r"[^\x20-\x7e]", "?", str(s))
    return s[:80]

agent_type = clip(d.get("agent_type") or "unknown")

if tool_name == "Agent":
    ti = d.get("tool_input")
    requested = ti.get("subagent_type") if isinstance(ti, dict) else None
    requested = clip(requested or "general-purpose")
    print(f"[mh:gate] BLOCKED: subagent ({agent_type}) may not spawn another agent "
          f"(requested subagent_type={requested}) — only the main session dispatches; "
          f"a subagent'"'"'s job is one bounded deliverable, not further orchestration "
          f"(CLAUDE.md \"Task Dispatch\")", file=sys.stderr)
    sys.exit(2)

# tool_name == "Bash": catch a nested `claude -p ...` spawn, which bypasses
# the Agent-tool leg entirely and would run as a fresh, unrestricted main
# session (its own PreToolUse payloads would carry no agent_id at all).
ti = d.get("tool_input")
cmd = ti.get("command") if isinstance(ti, dict) else None
if not isinstance(cmd, str):
    sys.exit(0)

# --- Heredoc-body stripping (GH #121, 2026-09-04) -------------------------
# _nested_spawn below scans the raw command string. Without this step, a
# commit authored via the heredoc convention already documented in this
# repo (`git commit -m "$(cat <<'"'"'EOF'"'"' ... EOF)"`) that merely
# MENTIONS "claude -p" or "--bg" in prose -- e.g. a sentence describing
# this very gate -- gets scanned as if it were real shell syntax and
# falsely denied. A heredoc body is literal data until its closing
# delimiter, not a command to scan for a nested spawn, UNLESS the heredoc
# feeds an interpreter (bash <<EOF, python3 <<EOF, ...) -- that body IS
# executable code, and a rogue subagent could hide a real `claude -p`
# invocation inside one to slip past this gate if bodies were stripped
# unconditionally. Ported from the `_strip_heredocs` function in
# irrecoverable.sh (same fix, same shape, applied there 2026-08-06 for its
# own destructive-command scan) rather than shared via a new cross-file
# import -- the convention in this repo is that each gate carries its own
# adapted copy (see the comment in that file: "Ported from
# verifier-protect.sh... itself ported from worktree-guard.py").
#
# _DQ/_SQ hoisted here (needed by _HEREDOC_RE below; _TOKEN_RE further
# down still uses them fine, Python does not care about definition order
# within one script as long as it is before first use) instead of defined
# twice.
_DQ = chr(34)
_SQ = chr(39)

_HEREDOC_RE = re.compile(r"<<(-)?\s*([" + _SQ + r"\"]?)([^\s" + _SQ + r"\"]+)\2")
_INTERPRETER_RE = re.compile(r"\b(bash|sh|zsh|dash|ksh|python3?|python2|perl|ruby|node|nodejs|osascript)\b")

def _strip_heredocs(cmd):
    # Walk line by line. On a heredoc-open line, check the segment BEFORE
    # "<<" for an interpreter word. Not found -> the body is inert data (a
    # quoted commit message, a prompt string, ...): consume lines up to the
    # closing delimiter and drop them from the output. If the delimiter
    # never closes, put the scanned lines back rather than silently
    # discarding a real trailing command. Found -> the body is executable
    # code the interpreter will run: keep it in the output untouched AND
    # collect it separately into live_bodies, so the caller can anchor-scan
    # it on its own (see the note on live_bodies below for why a separate
    # scan, not a shared one).
    lines = cmd.split("\n")
    out, live_bodies, i = [], [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = _HEREDOC_RE.search(line)
        i += 1
        if not m:
            continue
        is_interpreter = bool(_INTERPRETER_RE.search(line[:m.start()]))
        strip_tabs, delim = bool(m.group(1)), m.group(3)
        body_start, found = i, False
        while i < len(lines):
            body_line = lines[i].lstrip("\t") if strip_tabs else lines[i]
            i += 1
            if body_line == delim:
                found = True
                break
        if is_interpreter:
            out.extend(lines[body_start:i])
            script = lines[body_start:i - 1] if found else lines[body_start:i]
            if script:
                live_bodies.append("\n".join(script))
        elif not found:
            out.extend(lines[body_start:i])
    return "\n".join(out), live_bodies

cmd, _live_bodies = _strip_heredocs(cmd)
# --- end heredoc-body stripping --------------------------------------------

_ANCHOR_RE = re.compile(
    r"(?:^|[|;&(]|&&|\|\|)\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:\S*/)?claude\b"
)
# live_bodies (GH #121, 2026-09-04) get their own anchor, with re.MULTILINE:
# inside an interpreter-fed heredoc body every line IS a fresh bash
# statement by construction (that is the whole point of the interpreter
# check above), so `^` should match after each embedded newline there, not
# only at the start of the body itself. Scoping MULTILINE to _ANCHOR_RE_BODY instead
# of applying it to the outer _ANCHOR_RE matters: an earlier version of this
# fix put re.MULTILINE on the outer scan and it correctly caught the
# heredoc-hidden case, but ALSO started denying an ordinary, non-heredoc
# multi-line commit message like `git commit -m "feat: X\nclaude -p is not
# allowed\n"` -- a real embedded newline in a quoted argument is not a
# statement boundary the way one is inside a live heredoc body, and the
# outer scan has no way to tell those apart. Caught before ship by an
# adversarial review pass; this split keeps the outer scan byte-for-byte
# identical to its pre-#121 behavior and confines the new anchor rule to
# exactly the text it is true for.
_ANCHOR_RE_BODY = re.compile(
    r"(?:^|[|;&(]|&&|\|\|)\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:\S*/)?claude\b",
    re.MULTILINE,
)
_FLAG_RE = re.compile(r"-p\b|--print\b|--agent\b|--bg\b")
# Quote-aware tail scan (deep-audit, 2026-08-31): a flat char-class exclusion
# treats ANY &/;/| as end-of-invocation, including one sitting inside a
# quoted prompt argument (claude "fix A & B" -p) -- a false NEGATIVE, the
# dangerous direction, since that argument is ordinary prompt text, not a
# real shell separator. _DQ/_SQ (defined above; chr() rather than literal
# quote characters, since this whole block already sits inside a bash
# single-quoted `python3 -c` wrapper) feed the token regex below.
_TOKEN_RE = re.compile(
    _DQ + r"(?:[^" + _DQ + r"\\]|\\.)*" + _DQ + "|" + _SQ + "[^" + _SQ + "]*" + _SQ + "|.",
    re.DOTALL,
)

def _nested_spawn(cmd, anchor_re=_ANCHOR_RE):
    # A whole quoted span is consumed as ONE token, so an in-quote &/;/|
    # never reaches the bare-separator check below; only an UNQUOTED one
    # ends the scan, which keeps real command boundaries intact (does not
    # let a later, unrelated command'"'"'s flag get credited to this claude
    # invocation).
    for m in anchor_re.finditer(cmd):
        buf = []
        for tok in _TOKEN_RE.finditer(cmd[m.end():]):
            t = tok.group()
            if len(t) == 1 and t in "&;|":
                break
            buf.append(t)
        if _FLAG_RE.search("".join(buf)):
            return True
    return False

_spawn_found = _nested_spawn(cmd) or any(
    _nested_spawn(body, _ANCHOR_RE_BODY) for body in _live_bodies
)
if _spawn_found:
    print(f"[mh:gate] BLOCKED: subagent ({agent_type}) may not spawn a nested Claude Code "
          f"session via Bash (command: {clip(cmd)!r}) — same rule as the Agent-tool leg: "
          f"only the main session dispatches (CLAUDE.md \"Task Dispatch\")", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
'
exit $?
