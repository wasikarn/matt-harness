#!/usr/bin/env bash
# scripts/_lib/transcript-user-turns.py: filters a session .jsonl transcript
# down to its own human-typed turns, skipping tool-result turns.
# Run standalone: bash tests/scripts/test-transcript-user-turns.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/_lib/transcript-user-turns.py"

python3 "$SCRIPT" --selftest || { echo "FAIL: transcript-user-turns.py selftest"; exit 1; }
echo "PASS: test-transcript-user-turns"
