#!/usr/bin/env bash
# Direct unit tests for hook_wired_via_pretooluse_table() in
# skills/harness-audit/scripts/audit.sh (used by checks 03/11 to decide
# whether a hook file on disk is reachable via the PreToolUse table).
# Extracts the function's own source via sed (it only depends on
# $CLAUDE_DIR, no other audit.sh state) rather than running the whole
# audit, so this pins the function's own contract directly.
#
# Regression test for a real bug (#91 independent adversarial audit,
# 2026-08-25): the old implementation used a bash `case ... in */"$name")`
# glob, and `*` matches `/` too -- so a table entry pointing at the WRONG
# directory (e.g. "hooks/gate/irrecoverable.sh", missing the trailing "s")
# still reported the real "hooks/gates/irrecoverable.sh" as "wired", even
# though that entry's own script path resolves to nothing on disk and
# would never actually run. Fixed to require the resolved path to exist
# AND have the exact basename.
# Run standalone: bash tests/scripts/test-hook-wired-via-pretooluse-table.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIT_SH="$ROOT/skills/harness-audit/scripts/audit.sh"

pass=0
fail=0
assert() {
  local desc="$1" ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "  ✅ $desc"; pass=$((pass + 1))
  else
    echo "  ❌ $desc" >&2; fail=$((fail + 1))
  fi
}

FUNC_FILE=$(mktemp)
trap 'trash "$FUNC_FILE" 2>/dev/null || true' EXIT
sed -n '/^hook_wired_via_pretooluse_table() {/,/^}/p' "$AUDIT_SH" > "$FUNC_FILE"
if ! /usr/bin/grep -q 'hook_wired_via_pretooluse_table' "$FUNC_FILE"; then
  echo "  ❌ FATAL: could not extract hook_wired_via_pretooluse_table from audit.sh — function renamed/moved?" >&2
  exit 1
fi

echo "=== hook_wired_via_pretooluse_table (skills/harness-audit/scripts/audit.sh) ==="
echo ""

FIX=$(mktemp -d)
mkdir -p "$FIX/hooks/gates"
printf '#!/usr/bin/env bash\necho real\n' > "$FIX/hooks/gates/irrecoverable.sh"

cat > "$FIX/hooks/pretooluse-table.json" <<'EOF'
[
  {"id": "gate:bash:irrecoverable", "matcher": "Bash", "script": "hooks/gates/irrecoverable.sh"}
]
EOF
out=$(CLAUDE_DIR="$FIX" bash -c ". '$FUNC_FILE'; hook_wired_via_pretooluse_table irrecoverable.sh"; echo "RC=$?")
echo "$out" | /usr/bin/grep -q 'RC=0' && ok=1 || ok=0
assert "correct path in the table (hooks/gates/irrecoverable.sh) -> wired" "$ok"

cat > "$FIX/hooks/pretooluse-table.json" <<'EOF'
[
  {"id": "gate:bash:irrecoverable", "matcher": "Bash", "script": "hooks/gate/irrecoverable.sh"}
]
EOF
out=$(CLAUDE_DIR="$FIX" bash -c ". '$FUNC_FILE'; hook_wired_via_pretooluse_table irrecoverable.sh"; echo "RC=$?")
echo "$out" | /usr/bin/grep -q 'RC=1' && ok=1 || ok=0
assert "WRONG directory in the table (hooks/gate/ typo) -> NOT wired (the actual regression)" "$ok"

mkdir -p "$FIX/hooks/other"
printf '#!/usr/bin/env bash\necho decoy\n' > "$FIX/hooks/other/decoy-irrecoverable.sh"
cat > "$FIX/hooks/pretooluse-table.json" <<'EOF'
[
  {"id": "gate:decoy", "matcher": "Bash", "script": "hooks/other/decoy-irrecoverable.sh"}
]
EOF
out=$(CLAUDE_DIR="$FIX" bash -c ". '$FUNC_FILE'; hook_wired_via_pretooluse_table irrecoverable.sh"; echo "RC=$?")
echo "$out" | /usr/bin/grep -q 'RC=1' && ok=1 || ok=0
assert "a different real file that merely CONTAINS the basename as a substring -> NOT a false match" "$ok"

rm -f "$FIX/hooks/pretooluse-table.json"
out=$(CLAUDE_DIR="$FIX" bash -c ". '$FUNC_FILE'; hook_wired_via_pretooluse_table irrecoverable.sh"; echo "RC=$?")
echo "$out" | /usr/bin/grep -q 'RC=1' && ok=1 || ok=0
assert "no pretooluse-table.json at all -> not wired (graceful, no crash)" "$ok"

trash "$FIX" 2>/dev/null || true

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
