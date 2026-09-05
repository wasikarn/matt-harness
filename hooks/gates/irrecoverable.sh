#!/usr/bin/env bash
# Gate: block irrecoverable Bash patterns. PreToolUse JSON on stdin; exit 2 blocks.
set -uo pipefail

# Fast path: skip the python3 cold-start when no deny can match. Every deny in
# irrecoverable.py dispatches on an argv0 in the case list below; wrappers never
# hide it. Quote/backslash stripping exposes r""m -> rm, the whitespace-collapsed
# variant a backslash-newline split argv0, and any bare $ or backtick may be a
# zero-width splice (gi$(true)t) so it defers to python on its own. False
# positives just spawn python (safe direction). GH #134: CC never \u-escapes $.
_input="$(cat)"
_norm="$(printf '%s' "$_input" | sed 's/\\[nt]/ /g' | tr -s '[:space:]' ' ' | tr -d "\"'\\")"
_norm_nows="$(printf '%s' "$_norm" | tr -d '[:space:]')"
_has_subst=0
case "$_input" in *'`'*|*'$'*) _has_subst=1 ;; esac
case "$_norm$_norm_nows" in
  *rm*|*find*|*git*|*dd*|*mysql*|*psql*|*sqlite3*|*mariadb*|*claude*) : ;;  # candidate -> python
  *) [ "$_has_subst" -eq 1 ] || exit 0 ;;                          # no destructive token possible -> allow (unless obfuscated)
esac

# Portability guard (#93): announced fail-open without python3 (rc=127 would otherwise block every git/rm).
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — irrecoverable-pattern gate cannot run; allowing (install python3 to restore deny coverage)" >&2
  exit 0
fi

_py="$(dirname "$0")/irrecoverable.py"
# Missing sibling: same fail-closed exit 2 python3 would give, cleaner diagnostic.
if [ ! -r "$_py" ]; then
  echo "[mh:gate] internal error: sibling script irrecoverable.py missing or unreadable — failing closed" >&2
  exit 2
fi

printf '%s' "$_input" | python3 "$_py"
rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
  echo "[mh:gate] internal error (rc=$rc) — failing closed" >&2
  exit 2
fi
exit "$rc"
