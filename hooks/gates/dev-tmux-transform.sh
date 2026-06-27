#!/bin/bash
# Dev-server tmux transform — ECC auto-tmux-dev.js port (CLAUDE.md §Hook architecture (current profile ladder design)). Rewrites a
# Bash command that starts a dev server (npm run dev / next dev / vite / rails
# s / uvicorn …) into a detached tmux session so the agent doesn't block on a
# long-running foreground process. Passes the rewritten JSON back to CC by
# printing it and exiting 0 — NO hookSpecificOutput, no decision.
#
# Parity with ECC: detect dev-server command patterns; replace tool_input.command
# with `tmux new-session -d -s <name> '<cmd>'`; pass through everything else.
# Skip when tmux is absent or the session name is taken (let the original run).
#
# Off-switches:
#   export CLAUDE_HOOK_PROFILE=minimal   (off under minimal)
#   export CLAUDE_DISABLED_HOOKS=dev-tmux-transform
#   export KBG_DEV_TMUX_DISABLED=1

set -uo pipefail

HOOK_ID="dev-tmux-transform"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
hook_guard_unreadable
hook_require_jq

[ "${KBG_DEV_TMUX_DISABLED:-0}" = "1" ] && exit 0
[ "$TOOL" = "Bash" ] || exit 0

command -v tmux >/dev/null 2>&1 || exit 0  # no tmux → pass through untouched

# Pull the raw command string.
cmd=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Dev-server detection (parity with ECC patterns). Match the command head,
# tolerate leading env assignments (`PORT=3000 npm run dev`) and `cd x &&`.
# Strip env-prefix + cd-prefix so the matcher sees the real verb.
stripped=$cmd
# strip leading VAR=val tokens
stripped=$(printf '%s' "$stripped" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]+ +)*//')
# strip leading `cd <dir> && `
stripped=$(printf '%s' "$stripped" | sed -E 's/^cd [^&]+&& *//')

is_dev_server=0
case "$stripped" in
  npm\ run\ dev*|npm\ run\ start*|yarn\ dev*|yarn\ start*|pnpm\ dev*|pnpm\ start*|\
  bun\ run\ dev*|npx\ next\ dev*|next\ dev*|npx\ vite*|vite*|\
  npx\ astro\ dev*|astro\ dev*|ng\ serve*|\
  python\ -m\ http.server*|python*\ manage.py\ runserver*|\
  uvicorn*|gunicorn*|flask\ run*|rails\ s*|\
  bundle\ exec\ rails\ s*|go\ run\ *main.go*|cargo\ run*) is_dev_server=1 ;;
esac
# package-manager script form: `npm run <script>` where <script> contains dev/serve/start
if [ "$is_dev_server" = 0 ]; then
  case "$stripped" in
    npm\ run\ *|yarn\ *|pnpm\ run\ *|bun\ run\ *)
      script=$(printf '%s' "$stripped" | awk '{print $3}')
      case "$script" in
        dev*|serve*|start*|*dev|*serve) is_dev_server=1 ;;
      esac
      ;;
  esac
fi
[ "$is_dev_server" = 0 ] && exit 0

# Session name: kbg-dev-<pid> (stable enough; collisions handled below).
sess="kbg-dev-$$"
# If a session with that name already exists, let the original command run as-is
# rather than clobbering the running dev server.
tmux has-session -t "$sess" 2>/dev/null && exit 0

# Single-quote the command for the inner shell. Escape any single quotes.
escaped=$(printf '%s' "$cmd" | sed "s/'/'\\\\''/g")
new_cmd="tmux new-session -d -s $sess '$escaped'"

# ECC's JS port printed modified top-level JSON + exit 0 → SILENTLY NO-OPS in
# current CC: tool-input mutation requires hookSpecificOutput.updatedInput
# (verified against code.claude.com/docs/en/hooks, 2026-06-26). Emit that
# structured field; CC replaces .command before running the Bash call.
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"command":%s}}}\n' \
  "$(printf '%s' "$new_cmd" | jq -Rs . 2>/dev/null)"
exit 0