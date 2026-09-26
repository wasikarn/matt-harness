#!/usr/bin/env bash
# eval-default-enabled.sh — run a command with this repo's own defaultEnabled forced true.
#
# Sourced (not executed) by callers. `claude plugin eval` sandboxes load no user settings
# (docs/en/plugin-evals.md "how runs are isolated"), so this repo's own
# .claude-plugin/plugin.json defaultEnabled: false (a deliberate opt-in choice for real
# installs) means the sandbox never loads mh's agents/skills at all -- every case silently
# scores a no-plugin fallback instead of the real ones, with no error (confirmed empirically
# 2026-09-26: identical with/without scores, plus the CLI's own runtime warning).
#
# Functions:
#   with_default_enabled_true <command...>
#       Flip defaultEnabled to true in .claude-plugin/plugin.json (repo root inferred from
#       this file's own location), run <command...>, restore defaultEnabled to false
#       afterward via a trap -- so it's restored even if <command...> fails or the shell is
#       interrupted. No-op flip/restore if defaultEnabled is already true or the manifest is
#       missing (e.g. a caller running against a different repo layout).
#
# shellcheck shell=bash

with_default_enabled_true() {
  local lib_dir root manifest flipped=0
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  root="$(cd "$lib_dir/../.." && pwd)"
  manifest="$root/.claude-plugin/plugin.json"

  if [ -f "$manifest" ] && /usr/bin/grep -q '"defaultEnabled": false' "$manifest"; then
    python3 -c "
import re
p = '$manifest'
s = open(p).read()
s2, n = re.subn(r'\"defaultEnabled\": false', '\"defaultEnabled\": true', s)
assert n == 1, f'expected exactly one defaultEnabled: false in {p}, found {n}'
open(p, 'w').write(s2)
"
    flipped=1
    echo "eval-default-enabled: temporarily set defaultEnabled: true in $manifest (restored on exit)" >&2
  fi

  _restore_default_enabled() {
    [ "$flipped" -eq 1 ] || return 0
    python3 -c "
import re, sys
p = '$manifest'
s = open(p).read()
s2, n = re.subn(r'\"defaultEnabled\": true', '\"defaultEnabled\": false', s)
if n == 1:
    open(p, 'w').write(s2)
else:
    print(f'eval-default-enabled: WARNING could not restore defaultEnabled: false in {p} (found {n} matches) -- fix manually', file=sys.stderr)
"
  }
  trap _restore_default_enabled RETURN

  "$@"
}
