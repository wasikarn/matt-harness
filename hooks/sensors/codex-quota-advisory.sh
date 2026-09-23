#!/usr/bin/env bash
# Sensor: before a Codex CLI Bash command runs, warn (additionalContext) if
# codex-quota-sensor.sh recently recorded a usage-limit/rate-limit failure.
# Advisory-only -- never denies, never blocks; always exits 0.
# See codex-quota-advisory.py for the gap this closes.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:sensor] python3 not found — codex-quota-advisory cannot run; allowing (install python3 to restore Codex quota tracking)" >&2
  exit 0
fi

_py="$(dirname "$0")/codex-quota-advisory.py"
if [ ! -r "$_py" ]; then
  echo "[mh:sensor] internal error: sibling script codex-quota-advisory.py missing or unreadable — allowing" >&2
  exit 0
fi

python3 "$_py" "$@"
exit 0
