#!/bin/bash
# Block dangerous NON-git destructive bash commands — Bash-wide parity with
# ECC gateguard-fact-force.js isDestructiveBash. block-dangerous-git.sh is
# scoped to the Bash(git *) matcher, so it never sees rm -rf, find -exec rm,
# dd if=, or bare SQL DDL. This gate runs on the bare Bash matcher to cover
# those. Strips quoted strings and comments before pattern-matching to avoid
# false positives (quoted SQL / filenames never look like bare command tokens).
#
# Bypass (ported from ECC hook-flags pattern, same as block-dangerous-git):
#   export CLAUDE_HOOK_PROFILE=off              # disable all hooks honoring this var
#   export CLAUDE_DISABLED_HOOKS=block-dangerous-bash[,other-id...]
# Default profile is `standard` (this hook active).

set -uo pipefail

HOOK_ID="block-dangerous-bash"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
hook_guard_unreadable  # fail CLOSED (ask) if input unparseable

hook_require_jq

COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty') || {
  echo "[$HOOK_ID] ERROR: failed to parse tool_input.command" >&2
  exit 1
}
[ -z "$COMMAND" ] && exit 0

STRIPPED=$(hook_strip_quoted "$COMMAND")

SEP='(^|[[:space:];&|()`])'

# Use command grep to bypass potential ugrep/claude wrapper that breaks backtracking
_GREP="command grep"

# Never double-gate a PURE git invocation — block-dangerous-git.sh owns the
# Bash(git *) matcher. But if the command is COMPOUND (a shell operator ; & |
# joins another command), do NOT early-exit: a tail like `git push && rm -rf x`
# must be scanned here for the rm -rf (the git gate only matches git patterns
# and would miss the non-git destructive tail). A pure `git ...` (no ; & |)
# has no non-git tail, so defer to the git gate.
if printf '%s\n' "$STRIPPED" | $_GREP -qE "^[[:space:]]*git([[:space:]]|$)" \
   && ! printf '%s\n' "$STRIPPED" | $_GREP -qE "[;&|]"; then
  exit 0
fi

# --- rm with BOTH -r and -f (any flag form/order) ---------------------------
# Two independent flag checks, both required (AND). Each matches a short flag
# cluster containing the letter OR the long form, bounded by space/start/end so
# a dash-leading filename like `my-file.txt` cannot satisfy the flag check
# (the `-` there is preceded by a non-space char). Order-agnostic by
# construction: whichever order -r/-f appear, both checks still fire.
RM_TOKEN="${SEP}rm([[:space:]]|$)"
RM_REC_FLAG='(^|[[:space:]])(-[a-zA-Z]*r[a-zA-Z]*|--recursive)([[:space:]]|$)'
RM_FORCE_FLAG='(^|[[:space:]])(-[a-zA-Z]*f[a-zA-Z]*|--force)([[:space:]]|$)'
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$RM_TOKEN" \
   && printf '%s\n' "$STRIPPED" | $_GREP -qE "$RM_REC_FLAG" \
   && printf '%s\n' "$STRIPPED" | $_GREP -qE "$RM_FORCE_FLAG"; then
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "rm[^#]*" | head -1 | xargs)
  hook_decision deny "recursive+force delete: '$matched'. User policy prevents rm -rf style commands."
fi

# --- find ... -exec rm|rmdir|unlink ... -------------------------------------
# A find whose -exec first token basename is rm/rmdir/unlink. Matches -exec and
# -execdir; the destructive verb must be the FIRST token after -exec (bounded
# by space/end so `rmdir` in `rmdirfoo` cannot slip through).
FIND_EXEC_RM="${SEP}find[[:space:]][^#]*-exec[dir]?[[:space:]]+(rm|rmdir|unlink)([[:space:]]|$)"
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$FIND_EXEC_RM"; then
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "find[^#]*-exec[dir]?[[:space:]]+(rm|rmdir|unlink)[^#]*" | head -1 | xargs)
  hook_decision deny "find -exec destructive delete: '$matched'. User policy prevents find-driven rm/rmdir/unlink."
fi

# --- dd if= (dd touching a device/path) -------------------------------------
DD_IF="${SEP}dd[[:space:]][^#]*if="
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$DD_IF"; then
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "dd[^#]*" | head -1 | xargs)
  hook_decision deny "dd device read/write: '$matched'. User policy prevents dd if= commands."
fi

# --- destructive SQL DDL as bare command tokens -----------------------------
# hook_strip_quoted already neutralized quoted strings, so a `psql -c "DROP TABLE t"`
# has its quoted arg blanked and will NOT match — only bare DROP TABLE / DELETE
# FROM / TRUNCATE tokens (heredoc bodies, unquoted -e args) are denied.
SQL_DDL="${SEP}(DROP[[:space:]]+TABLE|DELETE[[:space:]]+FROM|TRUNCATE[[:space:]]+)"
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$SQL_DDL"; then
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "(DROP[[:space:]]+TABLE|DELETE[[:space:]]+FROM|TRUNCATE[[:space:]]+)[^#]*" | head -1 | xargs)
  hook_decision deny "destructive SQL DDL: '$matched'. User policy prevents bare DROP TABLE / DELETE FROM / TRUNCATE."
fi

# --- operator-supplied extra patterns ---------------------------------------
# Parity with ECC GATEGUARD_BASH_EXTRA_DESTRUCTIVE. If set, treat as an
# additional grep -E pattern to deny.
if [ -n "${KBG_EXTRA_DESTRUCTIVE:-}" ]; then
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "$KBG_EXTRA_DESTRUCTIVE"; then
    matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "$KBG_EXTRA_DESTRUCTIVE" | head -1 | xargs)
    hook_decision deny "operator-supplied destructive pattern (KBG_EXTRA_DESTRUCTIVE): '$matched'."
  fi
fi

exit 0