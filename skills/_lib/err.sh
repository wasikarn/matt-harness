#!/usr/bin/env bash
# err.sh — shared error-handling helpers for skills shell scripts.
#
# Sourced (not executed) by callers. Designed to be paired with
# `set -euo pipefail` at the top of every skill script that does I/O.
#
# Functions:
#   err_die <message> [exit_code]
#       Print "ERROR: <message>" to stderr and exit with <exit_code>
#       (default 1). Use for unrecoverable failures.
#
#   err_warn <message>
#       Print "WARN: <message>" to stderr. Does not exit.
#
#   err_usage <message>
#       Print "usage: <message>" to stderr and exit 2. Use for bad args.
#
#   require_cmd <command>
#       Exit 1 with a helpful message if <command> is not in PATH.
#       Call sites must still handle tool-specific absence semantics.
#
#   temp_register <path>
#       Append <path> to the cleanup list. Idempotent for a single run.
#
#   temp_cleanup
#       Remove all registered paths. Safe to call multiple times.
#       Registered automatically as an EXIT trap on first use.
#
# Convention:
#   - Fail fast: `set -euo pipefail` should be the first executable line.
#   - Fail readable: every early exit should say *why* on stderr.
#   - Degrade gracefully for optional dependencies; use `require_cmd` for
#     mandatory dependencies only.
#   - Temp files must be registered before the first write.

# shellcheck shell=bash

ERR_REGISTERED_TEMPS=()

err_die() {
  local msg="$1"
  local code="${2:-1}"
  printf 'ERROR: %s\n' "$msg" >&2
  exit "$code"
}

err_warn() {
  local msg="$1"
  printf 'WARN: %s\n' "$msg" >&2
}

err_usage() {
  local msg="$1"
  printf 'usage: %s\n' "$msg" >&2
  exit 2
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err_die "required command not found: $cmd"
  fi
}

temp_cleanup() {
  local p
  for p in "${ERR_REGISTERED_TEMPS[@]}"; do
    # Only clean up files/dirs we actually created; never traverse upward.
    [ -e "$p" ] || continue
    if [ -d "$p" ]; then
      rm -rf "$p"
    else
      rm -f "$p"
    fi
  done
  ERR_REGISTERED_TEMPS=()
}

temp_register() {
  local path="$1"
  ERR_REGISTERED_TEMPS+=("$path")
  # Register the trap exactly once per shell.
  if ! trap -p EXIT | grep -q temp_cleanup; then
    trap temp_cleanup EXIT
  fi
}
