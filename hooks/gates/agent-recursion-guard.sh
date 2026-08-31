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
    # model-influenceable, unlike the host-supplied agent_id. Strip newlines
    # so a crafted value cannot forge an extra "[mh:gate] ..." line in the
    # merged multi-gate stderr the model reads back as its rejection reason,
    # and cap length so a denial cannot be used to burn arbitrary context.
    return str(s).replace("\n", " ").replace("\r", " ")[:80]

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

if re.search(r"\bclaude\b[^|;&]*(-p\b|--print\b|--agent\b|--bg\b)", cmd):
    print(f"[mh:gate] BLOCKED: subagent ({agent_type}) may not spawn a nested Claude Code "
          f"session via Bash (command: {clip(cmd)!r}) — same rule as the Agent-tool leg: "
          f"only the main session dispatches (CLAUDE.md \"Task Dispatch\")", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
'
exit $?
