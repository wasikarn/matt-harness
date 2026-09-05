#!/usr/bin/env bash
# Gate: ask before a model-invoked `Skill(codex:setup)` call carrying
# `--enable-review-gate`.
#
# The paired Codex plugin's own `/codex:setup --enable-review-gate` toggle
# turns on a Stop-time LLM-judgment review that can block a Claude Code
# session from ending -- exactly the shape the operating model keeps out of
# mh's deny/ask set (see CONTEXT.md's "review gate" entry). Two of the eight
# `/codex:*` commands ship without `disable-model-invocation: true` --
# `codex:setup` and `codex:rescue` -- so nothing stops the model from calling
# either one itself. ADR-0001 records the split: this gate closes the
# `codex:setup` half (a one-line flag match, same shape as
# config-write-guard.sh); the `codex:rescue` half stays documented-only,
# since gating an Agent-tool dispatch by subagent_type has no precedent in
# this plugin.
#
# ASK, not DENY: the toggle is trivially reversible
# (`/codex:setup --disable-review-gate`), and a deliberate operator call to
# the same skill should not be hard-blocked -- same tier as
# config-write-guard.sh's settings-file edits.
#
# Scope: the Skill tool only. A Bash-mediated call into the codex plugin's
# own scripts (`node .../codex-companion.mjs setup --enable-review-gate`)
# bypasses this gate entirely -- accepted gap, matching
# config-write-guard.sh's own documented Bash-mediated-write gap.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found -- codex-setup-guard cannot run; allowing" >&2
  exit 0
fi

python3 -c '
import sys, json

def emit_ask(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "ask",
                                             "permissionDecisionReason": reason}}))

try:
    d = json.load(sys.stdin)
    if d.get("tool_name") != "Skill":
        sys.exit(0)
    ti = d.get("tool_input")
    if not isinstance(ti, dict):
        sys.exit(0)
    if ti.get("skill") != "codex:setup":
        sys.exit(0)
    args = ti.get("args")
    if not isinstance(args, str) or "--enable-review-gate" not in args:
        sys.exit(0)

    emit_ask(
        "codex-setup-guard: this call to codex:setup would enable the paired Codex "
        "plugin review gate, an LLM-judgment Stop-time check mh keeps off by design "
        "(see CONTEXT.md, ADR-0001). Confirm this is intentional."
    )
except Exception:
    sys.exit(0)
'
