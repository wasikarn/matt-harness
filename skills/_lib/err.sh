#!/usr/bin/env bash
# err.sh — shared error-handling helper for skills shell scripts.
#
# Sourced (not executed) by callers. Designed to be paired with
# `set -euo pipefail` at the top of every skill script that does I/O.
#
# Functions:
#   err_die <message> [exit_code]
#       Print "ERROR: <message>" to stderr and exit with <exit_code>
#       (default 1). Use for unrecoverable failures.
#
# Convention:
#   - Fail fast: `set -euo pipefail` should be the first executable line.
#   - Fail readable: every early exit should say *why* on stderr.

# shellcheck shell=bash

err_die() {
  local msg="$1"
  local code="${2:-1}"
  printf 'ERROR: %s\n' "$msg" >&2
  exit "$code"
}
