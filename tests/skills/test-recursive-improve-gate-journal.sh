#!/usr/bin/env bash
# Regression test for skills/meta/recursive-improve/scripts/gate-journal-summary.sh
# (candidate 1 from docs/research/warp-self-improving-agents-article-audit-2026-08-28.md
# -- feeds the gate-verdict journal into recursive-improve's Observe step). Points HOME
# at a synthetic dir so it never touches the real
# ~/.local/share/kbg/metrics/gate-decisions.jsonl.
# Run standalone: bash tests/skills/test-recursive-improve-gate-journal.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/skills/meta/recursive-improve/scripts/gate-journal-summary.sh"

pass=0
fail=0
check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

echo "=== recursive-improve gate-journal-summary ==="

# Case 1: no journal file yet -- must not error, must say so plainly.
tmp_missing="$(mktemp -d)"
out=$(HOME="$tmp_missing" bash "$SCRIPT" 2>&1)
rc=$?
ok=1; [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q "no gate-verdict journal yet" && ok=0
check "missing journal -> exits 0, says so plainly" "$ok"

# Case 2: populated journal -- aggregates by (id, decision), sorted by count desc.
tmp_populated="$(mktemp -d)"
mkdir -p "$tmp_populated/.local/share/kbg/metrics"
cat > "$tmp_populated/.local/share/kbg/metrics/gate-decisions.jsonl" <<'EOF'
{"ts": "2026-08-28T13:10:39Z", "id": "gate:bash:irrecoverable", "tool_name": "Bash", "decision": "deny"}
{"ts": "2026-08-28T13:10:43Z", "id": "gate:bash:irrecoverable", "tool_name": "Bash", "decision": "deny"}
{"ts": "2026-08-28T13:25:14Z", "id": "gate:write:verifier-protect", "tool_name": "Edit", "decision": "ask"}
EOF
out=$(HOME="$tmp_populated" bash "$SCRIPT" 2>&1)
rc=$?
ok=1
[ "$rc" -eq 0 ] || ok=1
echo "$out" | /usr/bin/grep -q "3 non-allow verdicts" && \
  echo "$out" | /usr/bin/grep -q "   2  deny    gate:bash:irrecoverable" && \
  echo "$out" | /usr/bin/grep -q "   1  ask     gate:write:verifier-protect" && ok=0
check "populated journal -> counts aggregated and sorted by frequency" "$ok"

# Case 3: malformed line in the journal is skipped, not fatal.
tmp_malformed="$(mktemp -d)"
mkdir -p "$tmp_malformed/.local/share/kbg/metrics"
cat > "$tmp_malformed/.local/share/kbg/metrics/gate-decisions.jsonl" <<'EOF'
not valid json
{"ts": "2026-08-28T13:10:39Z", "id": "gate:bash:irrecoverable", "tool_name": "Bash", "decision": "deny"}
EOF
out=$(HOME="$tmp_malformed" bash "$SCRIPT" 2>&1)
rc=$?
ok=1; [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q "1 non-allow verdicts" && ok=0
check "malformed line is skipped, real row still counted" "$ok"

trash "$tmp_missing" "$tmp_populated" "$tmp_malformed" 2>/dev/null || true

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
