#!/usr/bin/env bash
# Regression test for the mh:gate-report skill's script,
# skills/meta/gate-report/scripts/gate-report.py. Points it at a synthetic
# MH_GATE_JOURNAL_PATH so it never touches the real
# ~/.local/share/kbg/metrics/gate-decisions.jsonl, and checks the ask-count math
# plus the missing-file and malformed-line paths.
# Run standalone: bash tests/skills/test-gate-report.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_PY="$ROOT/skills/meta/gate-report/scripts/gate-report.py"
SKILL_MD="$ROOT/skills/meta/gate-report/SKILL.md"

pass=0
fail=0

assert() {
  local desc="$1" ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "  ✅ $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ $desc" >&2
    fail=$((fail + 1))
  fi
}

[[ -f "$REPORT_PY" ]] || { echo "FATAL: $REPORT_PY not found — the gate-report skill's script moved without updating this test" >&2; exit 1; }
[[ -f "$SKILL_MD" ]] || { echo "FATAL: $SKILL_MD not found — the skill moved without updating this test" >&2; exit 1; }

TMPDIR_TEST="$(mktemp -d)"
trap 'trash "$TMPDIR_TEST" 2>/dev/null || rm -rf "$TMPDIR_TEST"' EXIT

echo "=== gate-report ==="

# Wiring guard: the skill must invoke this exact script, not a copy.
assert "SKILL.md references scripts/gate-report.py" \
  "$(grep -c 'scripts/gate-report.py' "$SKILL_MD" | grep -qv '^0$' && echo 1 || echo 0)"

JOURNAL="$TMPDIR_TEST/gate-decisions.jsonl"
cat > "$JOURNAL" <<'EOF'
{"ts": "2026-09-27T10:00:00Z", "id": "gate:write:secret-scan", "tool_name": "Write", "decision": "ask", "session_id": "s1"}
{"ts": "2026-09-27T10:05:00Z", "id": "gate:write:secret-scan", "tool_name": "Edit", "decision": "ask", "session_id": "s1"}
{"ts": "2026-09-28T09:00:00Z", "id": "gate:bash:irrecoverable", "tool_name": "Bash", "decision": "deny", "session_id": "s2"}
{"ts": "2026-09-28T09:10:00Z", "id": "gate:write:secret-scan", "tool_name": "Write", "decision": "allow-suppressed", "session_id": "s2"}
not-json-garbage
EOF

out="$(MH_GATE_JOURNAL_PATH="$JOURNAL" python3 "$REPORT_PY")"
rc=$?
assert "exits 0 on a populated journal" "$([[ $rc -eq 0 ]] && echo 1 || echo 0)"
assert "counts 4 events, skips the 1 garbage line" \
  "$(grep -q '^Gate journal: 4 ask/deny event(s), 1 unparsable line(s) skipped$' <<<"$out" && echo 1 || echo 0)"
assert "secret-scan ask count is 2, not double-counted across tools" \
  "$(grep -qE '^ *2  gate:write:secret-scan  ask$' <<<"$out" && echo 1 || echo 0)"
assert "irrecoverable deny counted separately from secret-scan" \
  "$(grep -qE '^ *1  gate:bash:irrecoverable  deny$' <<<"$out" && echo 1 || echo 0)"
assert "allow-suppressed kept as its own decision bucket, not folded into ask" \
  "$(grep -qE '^ *1  gate:write:secret-scan  allow-suppressed$' <<<"$out" && echo 1 || echo 0)"
assert "range line uses the earliest and latest ts" \
  "$(grep -q '^Range: 2026-09-27T10:00:00Z .. 2026-09-28T09:10:00Z$' <<<"$out" && echo 1 || echo 0)"

MISSING="$TMPDIR_TEST/does-not-exist.jsonl"
out_missing="$(MH_GATE_JOURNAL_PATH="$MISSING" python3 "$REPORT_PY")"
rc_missing=$?
assert "missing journal exits 0" "$([[ $rc_missing -eq 0 ]] && echo 1 || echo 0)"
assert "missing journal prints the documented line, not a traceback" \
  "$([[ "$out_missing" == "Gate journal not set up." ]] && echo 1 || echo 0)"

# GH #378: secret-scan journals its suppressed matches as one row with "count": N. The report counts
# matches, as it did when each match had its own row; a count that is not a positive int counts 1.
COUNTED="$TMPDIR_TEST/counted.jsonl"
cat > "$COUNTED" <<'EOF'
{"ts": "2026-10-03T10:00:00Z", "id": "gate:write:secret-scan", "tool_name": "Write", "decision": "allow-suppressed", "session_id": "s1"}
{"ts": "2026-10-03T10:01:00Z", "id": "gate:write:secret-scan", "tool_name": "Write", "decision": "allow-suppressed", "session_id": "s1", "count": 3}
{"ts": "2026-10-03T10:01:00Z", "id": "gate:write:secret-scan", "tool_name": "Write", "decision": "ask", "session_id": "s1"}
{"ts": "2026-10-03T10:02:00Z", "id": "gate:write:secret-scan", "tool_name": "Edit", "decision": "allow-suppressed", "session_id": "s1", "count": "x"}
{"ts": "2026-10-03T10:03:00Z", "id": "gate:write:secret-scan", "tool_name": "Edit", "decision": "allow-suppressed", "session_id": "s1", "count": true}
{"ts": "2026-10-03T10:04:00Z", "id": "gate:write:secret-scan", "tool_name": "Edit", "decision": "allow-suppressed", "session_id": "s1", "count": 0}
EOF
out_counted="$(MH_GATE_JOURNAL_PATH="$COUNTED" python3 "$REPORT_PY")"
assert "a count row adds its count: 1 + 3 + three malformed counts at 1 each = 7 allow-suppressed" \
  "$(grep -qE '^ *7  gate:write:secret-scan  allow-suppressed$' <<<"$out_counted" && echo 1 || echo 0)"
assert "the header total and the per-tool counts weigh by count too (8 events; Write 5, Edit 3)" \
  "$(grep -q '^Gate journal: 8 ask/deny event(s)$' <<<"$out_counted" && grep -qE '^ *5  Write$' <<<"$out_counted" && grep -qE '^ *3  Edit$' <<<"$out_counted" && echo 1 || echo 0)"

EMPTY="$TMPDIR_TEST/empty.jsonl"
: > "$EMPTY"
out_empty="$(MH_GATE_JOURNAL_PATH="$EMPTY" python3 "$REPORT_PY")"
assert "empty journal reports empty, not a divide-by-zero" \
  "$(grep -q '^Gate journal is empty' <<<"$out_empty" && echo 1 || echo 0)"

# GH #337: a shadow rule's would_deny rows are listed per rule with sample commands.
SHADOW="$TMPDIR_TEST/shadow.jsonl"
cat > "$SHADOW" <<'EOF'
{"ts": "2026-10-01T10:00:00Z", "id": "gate:bash:irrecoverable", "tool_name": "Bash", "decision": "would_deny", "session_id": "s1", "rule": "mkfs", "command": "mkfs.ext4 /dev/sdz1"}
{"ts": "2026-10-01T10:01:00Z", "id": "gate:bash:irrecoverable", "tool_name": "Bash", "decision": "would_deny", "session_id": "s2", "rule": "mkfs", "command": "mkfs.vfat /dev/sdz2"}
{"ts": "2026-10-01T10:02:00Z", "id": "gate:bash:irrecoverable", "tool_name": "Bash", "decision": "would_ask", "session_id": "s2", "rule": "opaque-verb", "command": "$RUNNER build"}
{"ts": "2026-10-01T10:03:00Z", "id": "gate:bash:irrecoverable", "tool_name": "Bash", "decision": "deny", "session_id": "s2", "rule": "rm-rf"}
EOF
out_shadow="$(MH_GATE_JOURNAL_PATH="$SHADOW" python3 "$REPORT_PY")"
assert "shadow section lists the mkfs rule with 2 hits over 2 sessions" \
  "$(grep -qE '^ *2  gate:bash:irrecoverable  mkfs  \(2 session\(s\)\)$' <<<"$out_shadow" && echo 1 || echo 0)"
assert "shadow section shows a sample command per rule" \
  "$(grep -qF 'e.g. mkfs.vfat /dev/sdz2' <<<"$out_shadow" && echo 1 || echo 0)"
assert "a would_ask rule is listed too" \
  "$(grep -qE '^ *1  gate:bash:irrecoverable  opaque-verb  \(1 session\(s\)\)$' <<<"$out_shadow" && echo 1 || echo 0)"
assert "an enforced deny with a rule id is not listed as a shadow rule" \
  "$(grep -qE '  rm-rf  \(' <<<"$out_shadow" && echo 0 || echo 1)"
assert "no shadow section when the journal has no would_* row" \
  "$(grep -q '^Shadow rules' <<<"$out" && echo 0 || echo 1)"

echo
echo "=== $pass passed, $fail failed ==="
[[ $fail -eq 0 ]]
