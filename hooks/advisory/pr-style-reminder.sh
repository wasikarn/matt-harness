#!/usr/bin/env bash
# PostToolUse:Bash advisory — fires after git commit / gh pr create / gh pr edit.
# Emits anti-AI-flavor checklist to stderr. Never blocks (advisory only, exit 0).
# shellcheck disable=SC2034
HOOK_HONOR_PROFILE_OFF=1
HOOK_ID="pr-style-reminder"
source "$(dirname "$0")/../_lib.sh" || exit 0
hook_init "$HOOK_ID" || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Only fire on git commit or gh pr create/edit
if ! printf '%s' "$CMD" | /usr/bin/grep -qE '(git[[:space:]]+commit|gh[[:space:]]+pr[[:space:]]+(create|edit))'; then
  exit 0
fi

printf '\n[pr-style-reminder] Anti-AI-flavor checklist:\n' >&2
printf '  • No bold tag structure (**Root cause:** / **Summary:** etc.)\n' >&2
printf '  • No "Co-Authored-By: Claude" trailer\n' >&2
printf '  • Proof of work must be command-reproducible (include actual output)\n' >&2
printf '  • Commit message: imperative mood, under 72 chars, no "this commit"\n\n' >&2

CMD_PREFIX=$(printf '%s' "$CMD" | cut -c1-60)
( journal_append "$HOOK_ID" "pr_style_reminder_fired" \
    "$(printf '{"cmd_prefix":"%s"}' "$CMD_PREFIX")" \
    >/dev/null ) || true
exit 0
