#!/usr/bin/env bash
# The single PreToolUse registration in hooks.json. Fans out (in parallel) to
# every gate whose matcher matches this tool call, via dispatch-pretooluse.py
# -- see that file for the merge rules, verified against Claude Code's own
# hooks documentation (2026-08-25, ticket #91), not invented.
#
# All 9 entries in pretooluse-table.json are gate:* -- immune to any profile
# or kill-switch by construction (this repo's gate/advisory-sensor doctrine
# keeps advisory logic off PreToolUse entirely; there is no tiering concept
# here at all, unlike dispatch-single.sh's non-PreToolUse wrapper).
#
# Portability guard (#93): every one of the 9 underlying gate scripts already
# fails open (allow, with its own stderr note) when python3 is missing --
# confirmed by reading each one's own guard, not assumed from pattern
# similarity. Failing open here once, before any fan-out, replicates that
# same net behavior with a single stderr note instead of up to 9 duplicate
# ones.
set -uo pipefail
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:dispatch] python3 not found — every PreToolUse gate needs it and already fails open individually; skipping the whole fan-out (install python3 to restore gate coverage)" >&2
  exit 0
fi

_input="$(cat)"
printf '%s' "$_input" | python3 "$_here/dispatch-pretooluse.py" "$_here/pretooluse-table.json" "$_here/.."
exit $?
