#!/usr/bin/env bash
# Shared early-exit prelude for gate:write:worktree-guard and gate:bash:worktree-guard.
# Both hooks.json entries pointed the same inline `bash -c` one-liner at worktree-guard.py --
# extracted here so the two matchers (Write|Edit|NotebookEdit vs Bash) stay separate
# registrations with their own descriptions (redirect vs deny is a real behavioral
# difference, decided inside worktree-guard.py by tool_name), while the identical
# no-op-unless-guarded check isn't duplicated as a JSON string literal twice.
w="${MH_GUARDED_WORKSPACE:-}"
p="${CLAUDE_PROJECT_DIR:-$PWD}"
if [[ -z "$w" || ( "$w" == /* && -n "$p" && "$p" != "$w" && "$p" != "$w/"* ) ]]; then
  exit 0
fi
# Portability guard (#93): announced fail-open when python3 is missing;
# doctrine-bootstrap.sh names the missing dep once at SessionStart.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — worktree-guard cannot run; allowing (install python3 to restore workspace-guard redirects)" >&2
  exit 0
fi
exec python3 "${CLAUDE_PLUGIN_ROOT}/hooks/gates/worktree-guard.py"
