#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal \$ in test payload strings is intentional
# Gate unit tests: simulates PreToolUse JSON payloads and asserts allow/deny.
# Each test_deny call expects exit 2; test_allow expects exit 0.
# Run standalone: bash hooks/tests/test-gates.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IRRECOVERABLE="$ROOT/hooks/gates/irrecoverable.sh"
PATH_HARDCODE="$ROOT/hooks/gates/path-hardcode.sh"

pass=0
fail=0

# Build a minimal Bash tool payload.
bash_payload() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }

# Build a Write tool payload.
write_payload() {
  local path="$1" content="$2"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"}}' "$path" "$content"
}

# Build an Edit tool payload.
edit_payload() {
  local path="$1" new="$2"
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","new_string":"%s"}}' "$path" "$new"
}

# Expect the gate to BLOCK (exit 2).
test_deny() {
  local gate="$1" desc="$2" payload="$3"
  local rc
  rc=$(echo "$payload" | bash "$gate" 2>/dev/null; echo $?)
  if [[ "$rc" == "2" ]]; then
    echo "  ✅ DENY: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ DENY EXPECTED but got exit $rc: $desc" >&2
    fail=$((fail + 1))
  fi
}

# Expect the gate to ALLOW (exit 0).
test_allow() {
  local gate="$1" desc="$2" payload="$3"
  local rc
  rc=$(echo "$payload" | bash "$gate" 2>/dev/null; echo $?)
  if [[ "$rc" == "0" ]]; then
    echo "  ✅ ALLOW: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ ALLOW EXPECTED but got exit $rc: $desc" >&2
    fail=$((fail + 1))
  fi
}

echo "=== irrecoverable gate ==="
test_deny  "$IRRECOVERABLE" "rm -rf"                    "$(bash_payload 'rm -rf /tmp/test')"
test_deny  "$IRRECOVERABLE" "rm -fr variant"            "$(bash_payload 'rm -fr /tmp/test')"
test_deny  "$IRRECOVERABLE" "git push --force"          "$(bash_payload 'git push --force origin develop')"
test_deny  "$IRRECOVERABLE" "git push -f"               "$(bash_payload 'git push -f origin develop')"
test_deny  "$IRRECOVERABLE" "--no-verify"               "$(bash_payload 'git commit --no-verify -m msg')"
test_deny  "$IRRECOVERABLE" "git reset --hard"          "$(bash_payload 'git reset --hard HEAD~1')"
test_deny  "$IRRECOVERABLE" "git clean -f"              "$(bash_payload 'git clean -f')"
test_deny  "$IRRECOVERABLE" "git clean -fd"             "$(bash_payload 'git clean -fd')"
test_allow "$IRRECOVERABLE" "safe rm (no -rf)"          "$(bash_payload 'rm /tmp/file.txt')"
test_allow "$IRRECOVERABLE" "git push no force"         "$(bash_payload 'git push origin develop')"
test_allow "$IRRECOVERABLE" "git reset soft"            "$(bash_payload 'git reset --soft HEAD~1')"
test_allow "$IRRECOVERABLE" "normal bash command"       "$(bash_payload 'ls -la')"

echo ""
echo "=== path-hardcode gate ==="
# ponytail: split to avoid triggering the pre-commit /Users/<name>/ grep on test source
_UP="/Users" _UN="testuser" _UD="$_UP/$_UN"
test_deny  "$PATH_HARDCODE" "hardcoded /Users/ in .sh" \
  "$(write_payload 'script.sh' "export PATH=$_UD/bin:\$PATH")"
test_deny  "$PATH_HARDCODE" "hardcoded /Users/ in .py" \
  "$(write_payload 'setup.py' "BASE = $_UD/data")"
test_deny  "$PATH_HARDCODE" "Edit new_string with /Users/ in .sh" \
  "$(edit_payload 'deploy.sh' "cd $_UD/app")"
test_allow "$PATH_HARDCODE" "\$HOME reference in .sh" \
  "$(write_payload 'script.sh' 'export PATH=$HOME/bin:$PATH')"
test_allow "$PATH_HARDCODE" "~ reference in .sh" \
  "$(write_payload 'script.sh' 'cd ~/projects')"
test_allow "$PATH_HARDCODE" "/Users/ in .md file (not gated)" \
  "$(write_payload 'README.md' 'see /Users/kobig for example')"
test_allow "$PATH_HARDCODE" "/Users/ in .json file (not gated)" \
  "$(write_payload 'config.json' '{\"path\":\"/Users/kobig\"}')"
test_allow "$PATH_HARDCODE" "normal .sh content" \
  "$(write_payload 'run.sh' 'set -uo pipefail\necho hello')"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
