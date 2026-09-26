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
#       this file's own location), run <command...>, restore defaultEnabled to false once
#       <command...> returns (any exit code) or the process is interrupted (INT/TERM/HUP).
#       No-op flip/restore if defaultEnabled is already true. A missing manifest, or a shell
#       other than bash (this relies on BASH_SOURCE/BASH_VERSION -- silently a no-op under
#       zsh/sh, confirmed 2026-09-26), is a hard error: refuses to run <command...> rather than
#       silently doing so with the plugin still disabled.
#
# shellcheck shell=bash

with_default_enabled_true() {
  if [ -z "${BASH_VERSION:-}" ]; then
    echo "eval-default-enabled: must run under bash (BASH_SOURCE/BASH_VERSION are unset here) -- wrap the call in 'bash -c ...', don't source this from zsh/sh directly" >&2
    return 1
  fi

  local lib_dir root manifest flipped=0 rc
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  root="$(cd "$lib_dir/../.." && pwd)"
  manifest="$root/.claude-plugin/plugin.json"

  if [ ! -f "$manifest" ]; then
    echo "eval-default-enabled: ERROR no manifest at $manifest -- not running the wrapped command" >&2
    return 1
  fi

  if /usr/bin/grep -q '"defaultEnabled": false' "$manifest"; then
    if ! python3 -c "
import re
p = '$manifest'
s = open(p).read()
s2, n = re.subn(r'\"defaultEnabled\": false', '\"defaultEnabled\": true', s)
assert n == 1, f'expected exactly one defaultEnabled: false in {p}, found {n}'
open(p, 'w').write(s2)
"; then
      echo "eval-default-enabled: ERROR failed to flip defaultEnabled in $manifest -- not running the wrapped command (would silently re-hit the no-plugin-fallback bug)" >&2
      return 1
    fi
    flipped=1
    echo "eval-default-enabled: temporarily set defaultEnabled: true in $manifest (restored once the wrapped command returns, or on INT/TERM/HUP)" >&2
  fi

  _restore_default_enabled() {
    [ "$flipped" -eq 1 ] || return 0
    flipped=0
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
  # RETURN alone only fires on normal function return -- it doesn't fire if a signal kills the
  # wrapped command mid-run, and it doesn't fire under a CALLER's `set -e` (errexit skips the
  # function's own RETURN trap and terminates the process outright). Two defenses: (1) `"$@" ||
  # rc=$?` keeps the wrapped command's own failure from ever triggering errexit, so control
  # always reaches `return "$rc"` and fires RETURN normally; (2) INT/TERM/HUP are trapped
  # separately, restore, then re-raise the same signal so the process still actually terminates
  # instead of silently surviving the interrupt. Every trap also clears all four of its own kind
  # on the way out, so nothing leaks into the caller's shell after this function returns.
  trap '_restore_default_enabled; trap - RETURN INT TERM HUP' RETURN
  trap '_restore_default_enabled; trap - RETURN INT TERM HUP; kill -INT $$' INT
  trap '_restore_default_enabled; trap - RETURN INT TERM HUP; kill -TERM $$' TERM
  trap '_restore_default_enabled; trap - RETURN INT TERM HUP; kill -HUP $$' HUP

  "$@" || rc=$?
  return "${rc:-0}"
}
