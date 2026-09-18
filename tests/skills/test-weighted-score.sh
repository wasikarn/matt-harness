#!/usr/bin/env bash
# scripts/_lib/weighted-score.py: shared deep-audit/idea-audit scorer.
# Renormalization must differ from divide-by-full-weight-sum (equivalent to
# scoring a dropped dimension 0), and malformed input must fail closed.
# Run standalone: bash tests/skills/test-weighted-score.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCORER="$ROOT/scripts/_lib/weighted-score.py"

python3 "$SCORER" --selftest || { echo "FAIL: weighted-score.py selftest"; exit 1; }

# Full-rubric total via stdin, matching deep-audit's 5-dim shape.
out=$(python3 "$SCORER" <<'EOF'
{"scores": [
  {"id": "correctness", "score": 8, "max": 10, "weight": 3, "insufficient": false},
  {"id": "completeness", "score": 7, "max": 10, "weight": 2, "insufficient": false},
  {"id": "claim_accuracy", "score": 9, "max": 10, "weight": 2, "insufficient": false},
  {"id": "regression_safety", "score": 6, "max": 10, "weight": 2, "insufficient": false},
  {"id": "simplicity", "score": 8, "max": 10, "weight": 1, "insufficient": false}
], "floorPct": 0.5, "passThreshold": 7.0}
EOF
)
echo "$out" | /usr/bin/grep -q '"total": 7.6' || { echo "FAIL: stdin total, got: $out"; exit 1; }
echo "$out" | /usr/bin/grep -q '"pass": true' || { echo "FAIL: stdin pass, got: $out"; exit 1; }

# Malformed input (all insufficient) must exit non-zero and print no JSON on stdout.
bad_out=$(printf '%s' '{"scores": [{"id": "x", "score": 5, "max": 10, "weight": 1, "insufficient": true}]}' | python3 "$SCORER" 2>/dev/null)
bad_code=$?
[ "$bad_code" -ne 0 ] || { echo "FAIL: expected non-zero exit on all-insufficient input"; exit 1; }
[ -z "$bad_out" ] || { echo "FAIL: expected empty stdout on rejected input, got: $bad_out"; exit 1; }

# A duplicate id must fail closed, not silently collapse in the primaryId
# weights dict and defeat the strictly-greatest check (idea-audit's
# never-tied-for-first rule).
dup_out=$(printf '%s' '{"scores": [{"id": "a", "score": 8, "max": 10, "weight": 40, "insufficient": false}, {"id": "b", "score": 7, "max": 10, "weight": 30, "insufficient": false}, {"id": "b", "score": 7, "max": 10, "weight": 40, "insufficient": false}], "primaryId": "a"}' | python3 "$SCORER" 2>/dev/null)
dup_code=$?
[ "$dup_code" -ne 0 ] || { echo "FAIL: expected non-zero exit on duplicate id"; exit 1; }
[ -z "$dup_out" ] || { echo "FAIL: expected empty stdout on duplicate-id input, got: $dup_out"; exit 1; }

echo "PASS: test-weighted-score"
