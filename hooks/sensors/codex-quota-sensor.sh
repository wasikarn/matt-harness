#!/usr/bin/env bash
# Sensor: on a Codex CLI Bash command failing with a usage-limit/rate-limit
# error, record it so codex-quota-advisory.sh can warn before the next Codex
# dispatch. Advisory-only -- never denies, never blocks; always exits 0.
# See codex-quota-sensor.py for the gap this closes.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:sensor] python3 not found — codex-quota-sensor cannot run; allowing (install python3 to restore Codex quota tracking)" >&2
  exit 0
fi

_py="$(dirname "$0")/codex-quota-sensor.py"
if [ ! -r "$_py" ]; then
  echo "[mh:sensor] internal error: sibling script codex-quota-sensor.py missing or unreadable — allowing" >&2
  exit 0
fi

python3 "$_py" "$@"
exit 0
