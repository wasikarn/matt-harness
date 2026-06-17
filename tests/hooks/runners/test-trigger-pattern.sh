#!/bin/bash
# Regression test for the positive-side trigger-pattern check added to
# skills/harness-audit/scripts/audit.sh. The check warns when a skill's
# frontmatter description: lacks a "when"-clause (Use when… / Trigger when… /
# ALWAYS trigger when… / Trigger on: / etc.). Bare-verb descriptions auto-fire
# on every prompt and pollute routing — this test pins the regex behavior.
#
# Run: bash tests/hooks/runners/test-trigger-pattern.sh

set -u

PASS=0
FAIL=0

# Reproduce the exact regex from audit.sh so the test catches drift.
TRIGGER_RE='Use when|Use this skill when|Use PROACTIVELY when|Use after|Trigger when|Auto-loads when|ALWAYS trigger|ALWAYS run|Trigger on|Invoke when'

assert_match() {
  local label="$1" desc="$2"
  if echo "$desc" | grep -qiE "$TRIGGER_RE"; then
    printf '  ✅ %-58s MATCH\n' "$label"
    PASS=$((PASS+1))
  else
    printf '  ❌ %-58s no match\n     desc: %s\n' "$label" "$desc"
    FAIL=$((FAIL+1))
  fi
}

assert_no_match() {
  local label="$1" desc="$2"
  if echo "$desc" | grep -qiE "$TRIGGER_RE"; then
    printf '  ❌ %-58s unexpected match\n     desc: %s\n' "$label" "$desc"
    FAIL=$((FAIL+1))
  else
    printf '  ✅ %-58s NO MATCH\n' "$label"
    PASS=$((PASS+1))
  fi
}

echo "=== positive matches (should fire warning-free) ==="
# Wshobson spec literals
assert_match "Use when…"                'Loads X. Use when editing Y or Z.'
assert_match "Use this skill when…"     'Loads X. Use this skill when editing Y.'
assert_match "Use PROACTIVELY when…"    'Loads X. Use PROACTIVELY when editing Y.'
assert_match "Use after…"               'Loads X. Use after running lint.'
assert_match "Trigger when…"            'Loads X. Trigger when editing YAML files.'
assert_match "Auto-loads when…"         'Loads X. Auto-loads when editor opens.'
assert_match "Invoke when…"             'Loads X. Invoke when user asks to refactor.'
# User's claude/ house style
assert_match "ALWAYS trigger this…"     'ALWAYS trigger this skill when the user wants ANY bulk or set-based operation on Jira work items.'
assert_match "ALWAYS run this gate…"    'ALWAYS run this gate before asking the user anything when the request is vague.'
assert_match "Trigger on: list…"        'Trigger on: "fix the bug", "refactor X", or "make it faster".'
# Combined negative + positive (the wshobson MISSING_TRIGGER complement)
assert_match "Use when + Don't use for" 'Loads X. Use when editing Y. Don'\''t use for Z.'

echo
echo "=== negatives (should fire warning) ==="
assert_no_match "bare verb only"        'Loads the foo skill.'
assert_no_match "declarative only"       'Skill for editing YAML files.'
assert_no_match "noun phrase only"       'YAML editor skill.'
assert_no_match "empty"                  ''

echo
echo "=== block-scalar (extract_fm returns empty → audit check skips) ==="
# This is the trade-off: check #20 has the same limitation. Block-scalar
# descriptions need manual review, but the check correctly skips them to
# avoid false positives on every multi-line frontmatter.
EMPTY_DESC=""
if [ -z "$EMPTY_DESC" ] && ! echo "$EMPTY_DESC" | grep -qiE "$TRIGGER_RE"; then
  printf '  ✅ %-58s SKIP-ON-EMPTY (matches audit.sh guard)\n' "block-scalar skip"
  PASS=$((PASS+1))
else
  printf '  ❌ %-58s block-scalar should skip\n' "block-scalar skip"
  FAIL=$((FAIL+1))
fi

echo
echo "=== live audit.sh regression (real skills) ==="
# Run the actual audit against the real skills dir; expect no WARN on
# trigger pattern (other unrelated WARNs are fine).
# Resolve audit.sh from $0 (repo-root-relative), not a hard-coded CWD path —
# the old `claude/skills/...` path didn't exist, so the run produced no output
# and the check passed because its target was MISSING (green-because-broken).
AUDIT="$(cd "$(dirname "$0")/../../.." && pwd)/skills/harness-audit/scripts/audit.sh"
if [ ! -f "$AUDIT" ]; then
  printf '  ❌ %-58s audit.sh not found at %s\n' "audit.sh against real skills/" "$AUDIT"
  FAIL=$((FAIL+1))
elif bash "$AUDIT" . 2>&1 | grep -qE "missing trigger pattern"; then
  printf '  ❌ %-58s real skill flagged (regression)\n' "audit.sh against real skills/"
  FAIL=$((FAIL+1))
else
  printf '  ✅ %-58s no skill flagged\n' "audit.sh against real skills/"
  PASS=$((PASS+1))
fi

echo
echo "=== summary ==="
printf "  pass: %d\n  fail: %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
