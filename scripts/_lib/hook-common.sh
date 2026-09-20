#!/usr/bin/env bash
# hook-common.sh — sourceable lib pulled in by scripts/_lib/fragments-state.sh,
# shared by hooks/sensors/fragments-arm.sh, hooks/sensors/fragments-capture.sh,
# and hooks/session/fragments-surface.sh (the mh:handoff skill and its
# handoff-nudge.sh/handoff-surface.sh hooks that used to share this file were
# removed; see git history for that consumer set), so the symlink/ownership
# defense, snapshot derivation, and git-root resolution these all need can't
# drift apart between copies the way owner_ok() and the stat-fallback
# direction already had (docs/adr/0003-writing-fragments-pointer-capture.md).
# Not a CLI -- source it, don't execute it.

# hook_owner_ok <path>: true iff <path>'s owner uid matches ours. Fails
# closed on any stat/id failure.
# GNU tried first, BSD as fallback -- not the reverse -- on every stat call
# in this file (deep-audit finding, live-reproduced with a real GNU stat):
# GNU's `-f` is a boolean flag ("show filesystem status"), not an
# option-with-argument, so `stat -f '%u' "$path"` on GNU is parsed as two
# file operands; the first ('%u') fails but the second ($path) succeeds and
# prints a multi-line filesystem-info block to stdout before the command
# exits nonzero -- `A || B` still captures A's stdout, corrupting every
# caller here. BSD's `-c` is a clean illegal-option failure (exit 1, no
# stdout), so trying it first costs nothing on BSD and closes the GNU bug.
hook_owner_ok() {
  local path="$1" uid
  uid=$(stat -c '%u' "$path" 2>/dev/null || stat -f '%u' "$path" 2>/dev/null) || return 1
  [ "$uid" = "$(id -u 2>/dev/null)" ]
}

# hook_safe_dir <path>: mkdir -p, then reject if it's a symlink or
# foreign-owned. <path> must carry no trailing slash -- a trailing slash
# resolves through a symlink before -L ever runs, silently defeating the
# check (found on the now-removed handoff-nudge.sh, reproduced live there;
# the fragments hooks above inherit the fix).
hook_safe_dir() {
  local path="$1"
  mkdir -p "$path" 2>/dev/null
  [ -d "$path" ] || return 1
  [ ! -L "$path" ] || return 1
  hook_owner_ok "$path" || return 1
  chmod 700 "$path" 2>/dev/null
  return 0
}

# hook_snapshot <path> <label>: size+mtime, GNU tried first (see
# hook_owner_ok's comment for why). Each caller MUST pass a DISTINCT <label> -- two independent stat failures at
# different call sites must never compare equal (found on the now-removed
# handoff-surface.sh's own deep-audit finding: a shared "" fallback let a
# missing `stat` binary fail the guard open). <label> has no default: an
# omitted label is a caller bug, not something to paper over with a shared
# fallback value that would silently reintroduce the exact hazard this
# function exists to close.
hook_snapshot() {
  local path="$1" label="${2:?hook_snapshot requires a distinct label}"
  stat -c '%s %Y' "$path" 2>/dev/null || stat -f '%z %m' "$path" 2>/dev/null || printf 'stat-unavailable-%s\n' "$label"
}

# hook_entry_age <path> <now>: age in seconds via mtime, GNU tried first
# (see hook_owner_ok's comment for why). Prints nothing and returns 1 on stat failure -- it never
# guesses an age, so a caller must have a defined, non-destructive behavior
# for "unknown" (skip this pass, don't assume stale and don't assume fresh).
hook_entry_age() {
  local path="$1" now="$2" mtime
  mtime=$(stat -c '%Y' "$path" 2>/dev/null || stat -f '%m' "$path" 2>/dev/null) || return 1
  printf '%s\n' "$((now - mtime))"
}

# hook_md_title <path>: first line of <path>, stripped of a leading "# ",
# else the literal "untitled". Never fails -- prints "untitled" on any read
# error.
hook_md_title() {
  local path="$1" title
  title=$(head -c 200 -- "$path" 2>/dev/null | head -n 1)
  case "$title" in
    '# '*) printf '%s\n' "${title#\# }" ;;
    *) printf 'untitled\n' ;;
  esac
}

# hook_repo_root [<anchor-dir>]: the git repo root, physical-cwd fallback.
# With an argument, resolves anchored at that directory (for a hook payload
# that carries its own cwd, which may differ from this process's ambient
# cwd). Without one, resolves from this process's own ambient cwd (for a
# SessionStart hook that never reads stdin, or a CLI). Prints nothing and
# returns 1 only if the anchor itself doesn't resolve to any directory.
hook_repo_root() {
  local anchor="${1:-}" root
  if [ -n "$anchor" ]; then
    root=$(cd -- "$anchor" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) \
      || root=$(cd -P -- "$anchor" 2>/dev/null && pwd)
  else
    root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$(pwd -P)
  fi
  [ -n "$root" ] || return 1
  printf '%s\n' "$root"
}
