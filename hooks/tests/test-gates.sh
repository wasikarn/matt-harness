#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal \$ in test payload strings is intentional
# Gate unit tests: simulates PreToolUse JSON payloads and asserts allow/deny/ask.
# Each test_deny call expects exit 2; test_allow expects exit 0 + empty stdout;
# test_ask expects exit 0 + a permissionDecision: ask JSON on stdout.
# Run standalone: bash hooks/tests/test-gates.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IRRECOVERABLE="$ROOT/hooks/gates/irrecoverable.sh"
PATH_HARDCODE="$ROOT/hooks/gates/path-hardcode.sh"
VERIFIER_PROTECT="$ROOT/hooks/gates/verifier-protect.sh"

pass=0
fail=0

# Build a minimal Bash tool payload. Uses json.dumps (not printf %s) so
# commands containing quotes/backslashes (e.g. mysql -e "DROP TABLE...",
# find -exec ... \;) don't produce malformed JSON that silently degrades
# to an empty command downstream.
bash_payload() { python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$1"; }

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

# Expect the gate to ALLOW (exit 0 + empty stdout — no permissionDecision JSON).
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

# Expect the gate to ASK (exit 0 + permissionDecision: ask JSON on stdout).
test_ask() {
  local gate="$1" desc="$2" payload="$3"
  local out rc
  out=$(echo "$payload" | bash "$gate" 2>/dev/null); rc=$?
  if [[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"'; then
    echo "  ✅ ASK: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ ASK EXPECTED but got exit $rc out='$out': $desc" >&2
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

# 2026-07-01 constitution audit: raw-substring matching produced both false
# positives (blocked safe commands merely mentioning a pattern in quoted
# text) and bypasses (quoted/tokenization tricks slipped past the regex).
# Fixed via shlex-based tokenization; these lock the fix in place.
test_allow "$IRRECOVERABLE" "grep for rm -rf text (was a false positive)" \
  "$(bash_payload 'grep -rn "rm -rf" scripts/')"
test_allow "$IRRECOVERABLE" "commit msg mentioning rm -rf (was a false positive)" \
  "$(bash_payload 'git commit -m "docs: warn against rm -rf usage"')"
test_deny  "$IRRECOVERABLE" "quoted rm word (was a bypass)" \
  "$(bash_payload "'rm' -rf /tmp/x")"
test_deny  "$IRRECOVERABLE" "find -exec rm (was a bypass)" \
  "$(bash_payload 'find /tmp/x -exec rm {} \;')"
test_deny  "$IRRECOVERABLE" "git checkout -- discards changes (was a bypass)" \
  "$(bash_payload 'git checkout -- .')"
test_deny  "$IRRECOVERABLE" "git switch --force (was a bypass)" \
  "$(bash_payload 'git switch --force main')"
test_deny  "$IRRECOVERABLE" "git commit --amend (was a bypass)" \
  "$(bash_payload 'git commit --amend')"
test_deny  "$IRRECOVERABLE" "dd to raw device (was a bypass)" \
  "$(bash_payload 'dd if=/dev/zero of=/dev/disk2')"
test_deny  "$IRRECOVERABLE" "SQL DROP TABLE (was a bypass)" \
  "$(bash_payload 'mysql -e "DROP TABLE users"')"
test_deny  "$IRRECOVERABLE" "git add -A (was prose-only)" \
  "$(bash_payload 'git add -A')"
test_deny  "$IRRECOVERABLE" "git add . (was prose-only)" \
  "$(bash_payload 'git add .')"
test_allow "$IRRECOVERABLE" "git add named file (must not over-block)" \
  "$(bash_payload 'git add foo.txt')"
test_allow "$IRRECOVERABLE" "git checkout branch (must not over-block)" \
  "$(bash_payload 'git checkout main')"
test_allow "$IRRECOVERABLE" "git checkout -b new branch (must not over-block)" \
  "$(bash_payload 'git checkout -b new-branch')"
# 2026-07-03 audit: newline and '&' are command separators in bash but shlex
# ate newline as whitespace and '&' wasn't in OPERATORS — a dangerous command
# after either hid inside the first command's window. Also --force-with-lease
# (the safe variant) was caught by the --force prefix match.
test_deny  "$IRRECOVERABLE" "dangerous cmd after newline" \
  "$(bash_payload $'echo hi\nrm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "dangerous cmd after & (background)" \
  "$(bash_payload 'echo done & rm -rf /tmp/x')"
test_allow "$IRRECOVERABLE" "git push --force-with-lease (safe variant)" \
  "$(bash_payload 'git push --force-with-lease origin develop')"
test_allow "$IRRECOVERABLE" "git push --force-with-lease with refspec (still safe)" \
  "$(bash_payload 'git push --force-with-lease=main:12345 origin develop')"
test_allow "$IRRECOVERABLE" "git push normal (no force)" \
  "$(bash_payload 'git push origin develop')"

echo ""
echo "=== verifier-protect Bash gate (redirect/tee/sed-i writes to verifier surfaces) ==="
VP_BASH="$ROOT/hooks/gates/verifier-protect.sh"
test_ask   "$VP_BASH" "redirect > into hooks/gates/" \
  "$(bash_payload 'echo neutered > hooks/gates/irrecoverable.sh')"
test_ask   "$VP_BASH" "append >> into hooks/hooks.json" \
  "$(bash_payload 'echo x >> hooks/hooks.json')"
test_ask   "$VP_BASH" "sed -i on an audit check" \
  "$(bash_payload 'sed -i s/a/b/ skills/harness-audit/scripts/checks/01-fleet-count.sh')"
test_ask   "$VP_BASH" "tee into a gate file" \
  "$(bash_payload 'echo x | tee hooks/gates/path-hardcode.sh')"
test_ask   "$VP_BASH" "cp over an audit check (dest is verifier path)" \
  "$(bash_payload 'cp foo skills/harness-audit/scripts/checks/05-frontmatter-completeness-skills.sh')"
test_ask   "$VP_BASH" "mv into hooks/gates/ via absolute path" \
  "$(bash_payload "mv x $ROOT/hooks/gates/irrecoverable.sh")"
test_allow "$VP_BASH" "redirect into a normal source file" \
  "$(bash_payload 'echo x > skills/foo/SKILL.md')"
test_allow "$VP_BASH" "cat a gate file (read, not write)" \
  "$(bash_payload 'cat hooks/gates/irrecoverable.sh')"
test_allow "$VP_BASH" "git apply a patch to a non-verifier path" \
  "$(bash_payload 'git apply --check foo.patch')"
test_allow "$VP_BASH" "sed -i on a normal project file" \
  "$(bash_payload 'sed -i s/a/b/ src/index.ts')"
test_allow "$VP_BASH" "ls a gate file (no write)" \
  "$(bash_payload 'ls hooks/gates/irrecoverable.sh')"

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
echo "=== verifier-protect gate (tamper-resistance: human approves each verifier-surface edit) ==="
test_ask   "$VERIFIER_PROTECT" "Write to hooks/gates/irrecoverable.sh" \
  "$(write_payload 'hooks/gates/irrecoverable.sh' 'echo neutered')"
test_ask   "$VERIFIER_PROTECT" "Edit to hooks/gates/verifier-protect.sh (self)" \
  "$(edit_payload 'hooks/gates/verifier-protect.sh' 'exit 0')"
test_ask   "$VERIFIER_PROTECT" "Write to hooks/hooks.json (the wiring)" \
  "$(write_payload 'hooks/hooks.json' 'neutered-wiring')"
test_ask   "$VERIFIER_PROTECT" "Write to hooks/gates/ via absolute path" \
  "$(write_payload "$ROOT/hooks/gates/path-hardcode.sh" 'echo neutered')"
test_ask   "$VERIFIER_PROTECT" "Write to audit.sh (non-model verifier runner)" \
  "$(write_payload 'skills/harness-audit/scripts/audit.sh' 'echo neutered')"
test_ask   "$VERIFIER_PROTECT" "Edit to a check file (grading logic)" \
  "$(edit_payload 'skills/harness-audit/scripts/checks/05-frontmatter-completeness-skills.sh' 'echo neutered')"
test_ask   "$VERIFIER_PROTECT" "Write to a check via absolute path" \
  "$(write_payload "$ROOT/skills/harness-audit/scripts/checks/01-fleet-count.sh" 'echo neutered')"
test_allow "$VERIFIER_PROTECT" "Write to --health reporter (NOT a grader, out of scope)" \
  "$(write_payload 'skills/harness-audit/scripts/harness-health.py' 'print(1)')"
test_allow "$VERIFIER_PROTECT" "Write to health.sh (NOT a grader, out of scope)" \
  "$(write_payload 'skills/harness-audit/scripts/health.sh' 'echo ok')"
test_allow "$VERIFIER_PROTECT" "Write to a skill (normal work)" \
  "$(write_payload 'skills/foo/SKILL.md' '# ok')"
test_allow "$VERIFIER_PROTECT" "Write to a command (normal work)" \
  "$(write_payload 'commands/pr.md' '# ok')"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
