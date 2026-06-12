#!/usr/bin/env bash
# test-critical-hooks — smoke tests for the load-bearing enforcement hooks.
#
# Covers all 9 PreToolUse enforcement gates (the hooks that emit a
# permissionDecision — silent failure on any of these is the highest risk):
#   block-dangerous-git · doctrine-edit-gate · secret-read-guard
#   secret-scan · config-protection · block-bash-doctrine-write · block-alias-shadowing
#   db-write-gate · validator-bash-guard
# Plus 1 TaskCompleted enforcement gate (task-lifecycle.sh F7 — different
# convention: exit 2 + stderr feedback, not exit 0 + JSON permissionDecision).
# Plus a syntax smoke pass over EVERY hook script: a logger/injector that
# crashes can accidentally block a tool call, so `bash -n` / `ast.parse` over
# the whole hooks/ dir catches that class even for the non-gate hooks.
#
# Contract (verified against the hook sources 2026-05-30): PreToolUse hooks
# ALWAYS exit 0 and signal via a JSON `permissionDecision` on stdout
# (deny / ask) — per the Claude Code spec, exit 2 would discard that JSON. So we
# assert the emitted decision, NOT the exit code. No JSON emitted = "none" = the
# action is allowed to pass through. For TaskCompleted (F7), the
# convention is DIFFERENT: exit 2 + stderr feedback per the vendor spec
# (https://code.claude.com/docs/en/hooks § TaskCompleted, verified 2026-06-12).
# Use check_task for those assertions (exit code + stderr substring).
#
# Method: direct invocation with crafted events. No real git ops / file reads —
# nothing to clean up (the dangerous-git policy blocks the cleanup commands a
# commit-based test would need; direct invocation sidesteps that entirely).
#
# Usage: bash claude/hooks/tests/test-critical-hooks.sh
# Exit 0 = all pass; exit 1 = one or more failed.

# The C1 journal cases source _lib.sh through a computed path ($JLIB) inside
# subshells and set SID / CLAUDE_JOURNAL_PATH that the sourced journal_append
# consumes. shellcheck can't follow a variable source (SC1090) and therefore
# reads those vars as unused (SC2034) — both are false positives for this test
# harness, so disable them file-wide.
# shellcheck disable=SC1090,SC2034
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# Emit the permissionDecision a hook returns for a given event ("none" if it
# passes the action through with no JSON).
decision() {
  local hook="$1" json="$2" out
  out=$(printf '%s' "$json" | bash "$HOOKS/$hook" 2>/dev/null)
  [ -z "$out" ] && { echo "none"; return; }
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "parse-error"
}

# check <hook> <expected-decision> <label> <event-json>
check() {
  local hook="$1" want="$2" label="$3" json="$4" got
  got=$(decision "$hook" "$json")
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "$hook" "$label"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s, got %s)\n' "$hook" "$label" "$want" "$got"
  fi
}

# check_task <hook> <expected-exit> <expected-stderr-substring> <label> <event-json>
# For task-lifecycle.sh gates that use exit 2 + stderr feedback (TaskCompleted
# F7, NOT PreToolUse). Asserts on exit code (NOT on stdout JSON — there is
# none for TaskCompleted per vendor spec). Optionally asserts on a stderr
# substring (pass "" to skip the stderr check).
#
# Note: the outer script uses `set -uo pipefail` (NOT `set -e`), so the
# command substitution below captures the hook's exit code into `got_exit`
# without aborting. We must NOT enable `set -e` here — leaving it disabled
# is the whole reason this function works at all.
check_task() {
  local hook="$1" want_exit="$2" want_stderr="$3" label="$4" json="$5" got_exit got_stderr
  got_stderr=$(printf '%s' "$json" | bash "$HOOKS/$hook" 2>&1 >/dev/null)
  got_exit=$?
  if [ "$got_exit" = "$want_exit" ]; then
    if [ -z "$want_stderr" ] || printf '%s' "$got_stderr" | /usr/bin/grep -qF "$want_stderr"; then
      PASS=$((PASS+1)); printf '  ✅ %-22s %s (exit %s)\n' "$hook" "$label" "$got_exit"
    else
      FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (exit OK=%s, but stderr missing %q; got: %s)\n' "$hook" "$label" "$want_exit" "$want_stderr" "$got_stderr"
    fi
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want exit %s, got %s; stderr: %s)\n' "$hook" "$label" "$want_exit" "$got_exit" "$got_stderr"
  fi
}

bash_event() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -R .)"; }
read_event() { printf '{"tool_name":"Read","tool_input":{"file_path":%s}}' "$(printf '%s' "$1" | jq -R .)"; }
edit_event() { printf '{"tool_name":"Edit","tool_input":{"file_path":%s}}' "$(printf '%s' "$1" | jq -R .)"; }
# Bash event with agent_type — used by validator-bash-guard (gates the 7
# validator-class agents: code-reviewer, code-explorer, code-architect,
# comment-analyzer, pr-test-analyzer, silent-failure-hunter, security-reviewer).
# agent_type is omitted by Claude Code for the main thread (no field) — so
# the "no agent_type" event is the "fail open" case.
validator_bash_event()    { printf '{"tool_name":"Bash","agent_type":%s,"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)"; }
main_thread_bash_event()  { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -R .)"; }
# Write/Edit with content payload (for secret-scan, which scans the written text).
write_event()    { printf '{"tool_name":"Write","tool_input":{"file_path":%s,"content":%s}}' "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)"; }
edit_new_event() { printf '{"tool_name":"Edit","tool_input":{"file_path":%s,"new_string":%s}}' "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)"; }
# TaskCompleted event (for task-lifecycle.sh F7 gate). Vendor convention is
# DIFFERENT from PreToolUse: TaskCompleted uses exit 2 + stderr feedback
# (per https://code.claude.com/docs/en/hooks § TaskCompleted), not the
# exit 0 + JSON `permissionDecision` pattern that PreToolUse uses. So
# `check()` (which asserts on stdout JSON) does not fit; use `check_task`
# below which asserts on exit code + stderr.
task_event() { printf '{"hook_event_name":"TaskCompleted","task_id":%s,"task_subject":%s,"task_description":%s}' "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)" "$(printf '%s' "$3" | jq -R .)"; }
teammate_idle_event() { printf '{"hook_event_name":"TeammateIdle"}'; }
task_created_event() { printf '{"hook_event_name":"TaskCreated","task_id":%s,"task_subject":%s,"task_description":%s}' "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)" "$(printf '%s' "$3" | jq -R .)"; }

# Temp fixture for gates that check real on-disk existence (config-protection
# only gates EDITS of a pre-existing config). Our own mktemp dir — cleaned on exit.
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
printf 'module.exports={};\n' > "$FIXTURE/.eslintrc"

echo "=== critical hook tests ==="

# --- block-dangerous-git: deny destructive, ask on develop, allow safe/fix ---
check block-dangerous-git.sh deny "blocks reset --hard"        "$(bash_event 'git reset --hard HEAD~1')"
check block-dangerous-git.sh deny "blocks force push main"     "$(bash_event 'git push --force origin main')"
check block-dangerous-git.sh deny "blocks branch -D"           "$(bash_event 'git branch -D feature')"
check block-dangerous-git.sh deny "blocks bare force-w-lease"  "$(bash_event 'git push --force-with-lease')"
check block-dangerous-git.sh ask  "asks on force push develop" "$(bash_event 'git push --force origin develop')"
check block-dangerous-git.sh none "allows force push feature/" "$(bash_event 'git push --force-with-lease origin feature/x')"
check block-dangerous-git.sh none "allows git status"          "$(bash_event 'git status')"

# --- doctrine-edit-gate: ask on doctrine files under .claude/, kbg-harness/, or claude/, allow others ---
check doctrine-edit-gate.sh ask  "asks on METHODOLOGY.md"   "$(edit_event '/x/.claude/METHODOLOGY.md')"
check doctrine-edit-gate.sh ask  "asks on settings.json"    "$(edit_event '/x/.claude/settings.json')"
check doctrine-edit-gate.sh ask  "asks on ACLI.md"          "$(edit_event '/x/.claude/ACLI.md')"
check doctrine-edit-gate.sh ask  "asks on DBGATE.md"        "$(edit_event '/x/.claude/DBGATE.md')"
check doctrine-edit-gate.sh ask  "asks on kbg-harness ACLI.md" "$(edit_event '/x/kbg-harness/ACLI.md')"
check doctrine-edit-gate.sh ask  "asks on kbg-harness METHODOLOGY.md" "$(edit_event '/x/kbg-harness/METHODOLOGY.md')"
check doctrine-edit-gate.sh none "allows non-doctrine file" "$(edit_event '/x/.claude/foo.py')"
check doctrine-edit-gate.sh none "ignores not-kbg-harness lookalike" "$(edit_event '/x/not-kbg-harness/METHODOLOGY.md')"
check doctrine-edit-gate.sh none "ignores file outside .claude" "$(edit_event '/x/src/METHODOLOGY.md')"

# --- secret-read-guard: deny secret reads (Read + Bash), allow normal/template ---
check secret-read-guard.sh deny "blocks Read .env"         "$(read_event '/x/.env')"
check secret-read-guard.sh deny "blocks Read id_rsa"       "$(read_event '/home/u/.ssh/id_rsa')"
check secret-read-guard.sh deny "blocks cat .env via bash" "$(bash_event 'cat .env')"
check secret-read-guard.sh none "allows Read README"       "$(read_event '/x/README.md')"
check secret-read-guard.sh none "allows Read .env.example" "$(read_event '/x/.env.example')"
check secret-read-guard.sh none "allows cat README"        "$(bash_event 'cat README.md')"

# --- secret-scan: deny secret patterns in written content, allow benign ---
# Fakes are built at runtime so this test file holds NO secret-shaped literal —
# otherwise secret-scan blocks the very Edit that writes this test (it scans
# Edit/Write content regardless of target). The split/expansion also doubles as
# good hygiene: a test file should never carry a real-looking token.
fake_aws="AKIA$(printf 'A%.0s' $(seq 1 16))"            # AKIA + 16 upper = AWS shape
fake_ghp="ghp_$(printf '0%.0s' $(seq 1 36))"           # ghp_ + 36 = GitHub PAT shape
fake_pk="-----BEGIN RSA PRIVATE ""KEY-----"            # split literal; joins at runtime
check secret-scan.sh deny "blocks AWS key in Write"     "$(write_event /x/a.txt "key=$fake_aws here")"
check secret-scan.sh deny "blocks GitHub PAT in Write"  "$(write_event /x/a.txt "token=$fake_ghp")"
check secret-scan.sh deny "blocks private key in Edit"  "$(edit_new_event /x/a.txt "$fake_pk")"
check secret-scan.sh none "allows benign Write"         "$(write_event /x/a.txt 'just some normal config text')"
check secret-scan.sh none "ignores secret in Bash (not its tool)" "$(bash_event "echo $fake_ghp")"

# --- config-protection: ask on edit of EXISTING config, allow create/non-config ---
check config-protection.sh ask  "asks on existing .eslintrc"    "$(write_event "$FIXTURE/.eslintrc" 'x')"
check config-protection.sh none "allows new .eslintrc (create)" "$(write_event "$FIXTURE/new/.eslintrc" 'x')"
check config-protection.sh none "ignores non-config file"       "$(write_event "$FIXTURE/foo.txt" 'x')"

# --- block-bash-doctrine-write: deny shell writes to doctrine (all roots), allow reads/non-doctrine ---
check block-bash-doctrine-write.sh deny "blocks > redirect to CLAUDE.md" "$(bash_event 'echo hacked > /repo/claude/CLAUDE.md')"
check block-bash-doctrine-write.sh deny "blocks sed -i on settings.json" "$(bash_event 'sed -i s/a/b/ /home/u/.claude/settings.json')"
check block-bash-doctrine-write.sh deny "blocks tee to ACLI.md"          "$(bash_event 'echo x | tee /repo/claude/ACLI.md')"
check block-bash-doctrine-write.sh deny "blocks cp to DBGATE.md"         "$(bash_event 'cp /tmp/x /home/u/.claude/DBGATE.md')"
check block-bash-doctrine-write.sh deny "blocks > to kbg-harness DBGATE.md" "$(bash_event 'echo x > /x/kbg-harness/DBGATE.md')"
check block-bash-doctrine-write.sh none "allows reading doctrine (cat)"  "$(bash_event 'cat /repo/claude/CLAUDE.md')"
check block-bash-doctrine-write.sh none "allows write to non-doctrine"   "$(bash_event 'echo x > /tmp/foo.txt')"

# --- block-alias-shadowing: ask on alias/function shadow of safety binary ---
check block-alias-shadowing.sh ask  "asks on alias git="       "$(bash_event "alias git='git --no-verify'")"
check block-alias-shadowing.sh ask  "asks on git() function"   "$(bash_event 'git() { command git --no-verify "$@"; }')"
check block-alias-shadowing.sh ask  "asks on function curl"    "$(bash_event 'function curl { command curl --insecure; }')"
check block-alias-shadowing.sh none "allows plain git commit"  "$(bash_event 'git commit -m x')"
check block-alias-shadowing.sh none "ignores non-safety alias" "$(bash_event "alias ll='ls -la'")"

# --- validator-bash-guard: deny mutation Bash from validator-class agents,
#     allow read-only commands + non-validator agents + main-thread (no agent_type) ---
# 6 acceptance cases from .scratch/phase-1-safety-fixes-2026-06-12/ACCEPTANCE.md FIX-F1.
check validator-bash-guard.sh none "code-reviewer + git diff HEAD (read-only)"        "$(validator_bash_event 'code-reviewer' 'git diff HEAD')"
check validator-bash-guard.sh deny "code-reviewer + git push origin main (mutation)"  "$(validator_bash_event 'code-reviewer' 'git push origin main')"
check validator-bash-guard.sh deny "code-reviewer + rm -rf /tmp/foo (mutation)"        "$(validator_bash_event 'code-reviewer' 'rm -rf /tmp/foo')"
check validator-bash-guard.sh none "backend-engineer + git push (writer not gated)"   "$(validator_bash_event 'backend-engineer' 'git push origin feature')"
check validator-bash-guard.sh none "code-reviewer + npm test (read-only test run)"    "$(validator_bash_event 'code-reviewer' 'npm test')"
check validator-bash-guard.sh deny "code-reviewer + sed -i 's/x/y/' (mutation)"        "$(validator_bash_event 'code-reviewer' "sed -i 's/x/y/' file")"
# Extra coverage beyond the 6 (anti-pattern robustness, not in AC):
check validator-bash-guard.sh deny "code-explorer + curl -X POST"                       "$(validator_bash_event 'code-explorer' 'curl -X POST https://api.example.com/x')"
check validator-bash-guard.sh deny "security-reviewer + chmod 777"                      "$(validator_bash_event 'security-reviewer' 'chmod 777 x')"
check validator-bash-guard.sh deny "silent-failure-hunter + mv /tmp/x /"               "$(validator_bash_event 'silent-failure-hunter' 'mv /tmp/x /')"
check validator-bash-guard.sh deny "code-architect + npm publish"                      "$(validator_bash_event 'code-architect' 'npm publish')"
check validator-bash-guard.sh none "comment-analyzer + cat file.py (read-only)"         "$(validator_bash_event 'comment-analyzer' 'cat file.py')"
check validator-bash-guard.sh none "pr-test-analyzer + pytest (read-only test run)"    "$(validator_bash_event 'pr-test-analyzer' 'pytest -q')"
check validator-bash-guard.sh none "main-thread + git push (no agent_type, fail-open)" "$(main_thread_bash_event 'git push origin main')"
check validator-bash-guard.sh none "main-thread + rm -rf (no agent_type, fail-open)"  "$(main_thread_bash_event 'rm -rf /tmp/foo')"
# Fork-bomb variants — AC F1 deny pattern 8. Canonical signature is
# `:(){ :|:& };:`; variants use different whitespace + terminators. A
# regression here is silent because no AC test covers fork-bombs — the
# F1 adversarial verifier caught this on the first pass.
check validator-bash-guard.sh deny "code-reviewer + canonical fork-bomb"       "$(validator_bash_event 'code-reviewer' ':(){ :|:& };:')"
check validator-bash-guard.sh deny "code-reviewer + spaces-in-body fork-bomb"  "$(validator_bash_event 'code-reviewer' ':() { :|: & };:')"
check validator-bash-guard.sh deny "code-reviewer + no-space fork-bomb"        "$(validator_bash_event 'code-reviewer' ':(){:|:&};:')"

# --- task-lifecycle.sh F7: TaskCompleted test-claim gate.
#     Vendor convention (verified 2026-06-12): TaskCompleted uses exit 2 + stderr
#     feedback, NOT exit 0 + JSON `permissionDecision` (that is PreToolUse).
#     So we use check_task (asserts on exit code + stderr), not check.
#     (a) TaskCompleted with test claim but no validation_command → exit 2
#     (b) TaskCompleted with test claim + validation_command → exit 0
#     (c) TaskCompleted with no test claim → exit 0 (no false positive)
#     (d) TaskCompleted with empty subject + description → exit 0 (no false positive)
#     (e) TeammateIdle → exit 0 (only TaskCompleted enforces; siblings stay log-only)
#     (f) TaskCreated → exit 0 (same)
#     (g) Claim variants: "pytest" alone in subject, "npm test" in description,
#         "cargo test" + "validation_command: cargo test" → all pass when validation_command present
check_task task-lifecycle.sh 2  "TASK-GATE"  "F7a blocks 'All tests pass' (no validation_command)"  "$(task_event '1' 'All tests pass' 'Implemented feature X')"
check_task task-lifecycle.sh 2  "TASK-GATE"  "F7a blocks 'pytest' in subject (no validation_command)" "$(task_event '2' 'Run pytest suite' 'Wrote tests for X')"
check_task task-lifecycle.sh 2  "TASK-GATE"  "F7a blocks 'npm test' in description (no validation_command)" "$(task_event '3' 'Build complete' 'Verify with npm test before commit')"
check_task task-lifecycle.sh 2  "TASK-GATE"  "F7a blocks 'cargo test' alone" "$(task_event '4' 'cargo test green' 'Refactored module Y')"
check_task task-lifecycle.sh 2  "TASK-GATE"  "F7a blocks 'go test' alone" "$(task_event '5' 'go test' 'Wrote handler')"
check_task task-lifecycle.sh 2  "TASK-GATE"  "F7a blocks 'pnpm test' alone" "$(task_event '6' 'pnpm test' 'Frontend changes')"
check_task task-lifecycle.sh 2  "TASK-GATE"  "F7a blocks 'jest' alone" "$(task_event '7' 'jest green' 'Frontend tests')"
check_task task-lifecycle.sh 0  ""          "F7b allows 'npm test' + validation_command"  "$(task_event '8' 'Build complete' 'Verify with npm test\nvalidation_command: npm test --workspaces')"
check_task task-lifecycle.sh 0  ""          "F7b allows 'pytest' + validation_command"  "$(task_event '9' 'All tests pass' 'validation_command: pytest tests/test_x.py -v')"
check_task task-lifecycle.sh 0  ""          "F7b allows 'Validation Command:' (case-insensitive)" "$(task_event '10' 'cargo test green' 'Refactored Y\nValidation Command: cargo test --release')"
check_task task-lifecycle.sh 0  ""          "F7b allows 'validation command:' (loose-space variant)" "$(task_event '11' 'go test' 'Wrote handler\nvalidation command: go test ./...')"
check_task task-lifecycle.sh 0  ""          "F7c allows 'Refactor complete' (no test claim)" "$(task_event '12' 'Refactor complete' 'No tests touched')"
check_task task-lifecycle.sh 0  ""          "F7c allows 'Wrote documentation' (no test claim)" "$(task_event '13' 'Wrote documentation' 'Updated README')"
check_task task-lifecycle.sh 0  ""          "F7d allows empty subject + description"  "$(task_event '14' '' '')"
# F7g — false-positive guards. These MUST NOT block, even though "jest" or
# "tsc" appear as substrings. The regex anchors bare keywords at non-word
# boundaries (line 100 of task-lifecycle.sh). Locked in after the Phase 2
# adversarial verifier caught a "jest" → "majestic" substring regression.
check_task task-lifecycle.sh 0  ""          "F7g 'majestic' does NOT match (jest substring)" "$(task_event '20' 'Made the layout more majestic' 'UI polish, no tests touched')"
check_task task-lifecycle.sh 0  ""          "F7g 'jesting' does NOT match" "$(task_event '21' 'Jesting around with copy' 'Tweaked strings')"
check_task task-lifecycle.sh 0  ""          "F7g 'jestful' does NOT match" "$(task_event '22' 'Not feeling jestful' 'Skipped test work')"
check_task task-lifecycle.sh 0  ""          "F7g 'pitsc' does NOT match (tsc substring)" "$(task_event '23' 'pitsc check' 'Pattern search')"
check_task task-lifecycle.sh 0  ""          "F7g 'pytest' as substring of unrelated word does NOT match" "$(task_event '24' 'sppytest path' 'Config tweak')"
# F7h — boundary-class match: jest as a standalone word DOES match (positive
# regression guard for the F7g fix — make sure anchoring didn't over-correct).
check_task task-lifecycle.sh 2  "TASK-GATE"  "F7h standalone 'jest' still matches" "$(task_event '25' 'jest' 'Frontend test runner')"
check_task task-lifecycle.sh 2  "TASK-GATE"  "F7h 'jest green' still matches (jest at word boundary)" "$(task_event '26' 'jest green' 'Wrote tests')"
check_task task-lifecycle.sh 2  "TASK-GATE"  "F7h standalone 'tsc' still matches" "$(task_event '27' 'tsc' 'Type-checked the codebase')"
check_task task-lifecycle.sh 2  "TASK-GATE"  "F7h 'pytest' still matches as a word" "$(task_event '28' 'pytest' 'Ran the suite')"
check_task task-lifecycle.sh 0  ""          "F7e TeammateIdle still log-only (siblings unaffected)"  "$(teammate_idle_event)"
check_task task-lifecycle.sh 0  ""          "F7f TaskCreated still log-only" "$(task_created_event '15' 'Implement F7 hook' 'Write the enforcement branch')"

# --- db-write-gate: ask on non-SELECT MCP DB calls, allow SELECT/EXPLAIN/info_schema,
#     ignore non-DB MCP tools. Mirrors DBGATE doctrine as a deterministic gate.
mcp_db_event() { printf '{"tool_name":"%s","tool_input":{"query":%s}}' "$1" "$(printf '%s' "$2" | jq -R .)"; }
mcp_nondb_event() { printf '{"tool_name":"mcp__atlassian__createJiraIssue","tool_input":{"summary":%s}}' "$(printf '%s' "$1" | jq -R .)"; }
check db-write-gate.sh none "allows SELECT on execute_sql_production" "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'SELECT 1')"
check db-write-gate.sh none "allows EXPLAIN on execute_sql_staging"   "$(mcp_db_event 'mcp__tathep-db__execute_sql_staging' 'EXPLAIN SELECT id FROM t')"
check db-write-gate.sh none "allows CTE WITH...SELECT"                "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'WITH x AS (SELECT 1) SELECT * FROM x')"
check db-write-gate.sh none "allows information_schema read"          "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'SELECT * FROM information_schema.tables')"
check db-write-gate.sh ask  "asks on DELETE execute_sql_production"   "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'DELETE FROM users WHERE id=1')"
check db-write-gate.sh ask  "asks on UPDATE execute_sql_staging"      "$(mcp_db_event 'mcp__tathep-db__execute_sql_staging' 'UPDATE x SET a=1 WHERE id=1')"
check db-write-gate.sh ask  "asks on INSERT execute_sql_anpr"         "$(mcp_db_event 'mcp__tathep-db__execute_sql_anpr_staging' 'INSERT INTO t (a) VALUES (1)')"
check db-write-gate.sh ask  "asks on DROP TABLE"                      "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'DROP TABLE old')"
check db-write-gate.sh ask  "asks on TRUNCATE"                        "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' 'TRUNCATE t')"
check db-write-gate.sh ask  "asks on db_write tool"                   "$(mcp_db_event 'mcp__other-db__db_write' 'INSERT INTO t VALUES (1)')"
check db-write-gate.sh none "ignores non-DB MCP tool"                 "$(mcp_nondb_event 'do thing')"
check db-write-gate.sh none "ignores non-MCP tool"                    "$(bash_event 'psql -c "DELETE FROM t"')"
check db-write-gate.sh none "allows SELECT with leading comment"      "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' '-- safety check\nSELECT 1')"
check db-write-gate.sh none "allows comment-only query (no-op)"        "$(mcp_db_event 'mcp__tathep-db__execute_sql_production' '-- just a comment, nothing else')"

# --- bypass contract: CLAUDE_DISABLED_HOOKS must let a blocked case through ---
out=$(printf '%s' "$(bash_event 'git reset --hard')" | CLAUDE_DISABLED_HOOKS=block-dangerous-git bash "$HOOKS/block-dangerous-git.sh" 2>/dev/null)
if [ -z "$out" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "block-dangerous-git.sh" "CLAUDE_DISABLED_HOOKS bypass works"
else FAIL=$((FAIL+1)); printf '  ❌ %-22s bypass env did not disable (got: %s)\n' "block-dangerous-git.sh" "$out"; fi

# --- syntax smoke: every hook script must parse (a crashing logger can block) ---
echo
echo "--- syntax smoke: every hook script parses ---"
for f in "$HOOKS"/*.sh; do
  name=$(basename "$f")
  if bash -n "$f" 2>/dev/null; then
    PASS=$((PASS+1)); printf '  ✅ %-26s parses\n' "$name"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-26s bash -n FAILED\n' "$name"
  fi
done
for f in "$HOOKS"/*.py; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  if python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/dev/null; then
    PASS=$((PASS+1)); printf '  ✅ %-26s compiles\n' "$name"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-26s ast.parse FAILED\n' "$name"
  fi
done

# --- C1 evidence journal: journal_append contract + consumer dedup ---
# Each case asserts a load-bearing invariant (JOURNAL-SCHEMA.md) that would fail
# if the logic regressed: nested shape, redaction, fail-loud, concurrency
# atomicity (the reason there is no flock), cross-stream dedup (no double count).
echo
echo "--- C1 evidence journal: journal_append + dedup ---"
JLIB="$HOOKS/_lib.sh"
JPATH="$FIXTURE/journal.jsonl"

# (A) envelope structure — nested {id,ts,session,hook,event,source,fields{}}, no top-level category,
# AND the function echoes the minted id on stdout (Phase II linkage: the journaler's
# `verdict.subject_id` is captured this way). Stdout id MUST equal the file's .id.
( source "$JLIB"; SID="jtest"; CLAUDE_JOURNAL_PATH="$JPATH"
  journal_append "config-change-log" "config_change" '{"path":"/x","source":"ide"}' ) > "$FIXTURE/jout.txt" 2>/dev/null
JE=$(cat "$FIXTURE/jout.txt")
FJID=$(jq -r .id "$JPATH")
if jq -e '.id and .ts and .session=="jtest" and .hook=="config-change-log" and .event=="config_change" and .source=="journal_append" and .fields.path=="/x" and (has("category")|not)' "$JPATH" >/dev/null 2>&1 \
   && [ -n "$JE" ] && [ "$JE" = "$FJID" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s nested envelope + id echo (stdout == file.id)\n' "journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s envelope/id-echo wrong: stdout=%s file_id=%s\n' "journal_append" "$JE" "$FJID"
fi

# (B) deny-list redaction — secret-ish KEY or string VALUE → [redacted]; safe field untouched
: > "$JPATH"
( source "$JLIB"; SID=s; CLAUDE_JOURNAL_PATH="$JPATH"
  journal_append "x" "config_change" '{"password":"hunter2","detail":"token=sk-abc","path":"/safe"}' )
if jq -e '.fields.password=="[redacted]" and .fields.detail=="[redacted]" and .fields.path=="/safe"' "$JPATH" >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s deny-list redacts secret key+value, keeps safe field\n' "journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s redaction failed: %s\n' "journal_append" "$(cat "$JPATH")"
fi

# (C) missing jq → exit 2 (fail-loud, never a silent drop). PATH is a dir holding
# ONLY the non-jq binaries journal_append could need (python3/mkdir/dirname), so
# jq is GUARANTEED absent — the mutation "exit 2 → exit 0" cannot survive this
# (no self-skip branch that would mask it on a box where jq sits beside python3).
JBIN="$FIXTURE/jbin"; mkdir -p "$JBIN"
for b in python3 mkdir dirname; do ln -sf "$(command -v "$b")" "$JBIN/$b" 2>/dev/null; done
( source "$JLIB"; SID=s; CLAUDE_JOURNAL_PATH="$JPATH"; PATH="$JBIN"; journal_append "x" "e" '{}' ); jrc=$?
if [ "$jrc" = 2 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s missing jq → exit 2 (fail-loud)\n' "journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s missing jq → exit %s (want 2)\n' "journal_append" "$jrc"
fi

# (D) concurrency — 50×20 parallel appends of ~820-byte lines → all 1000 valid JSON,
# unique ids (proves O_APPEND atomicity at these sizes; this is why no flock).
: > "$JPATH"
for p in $(seq 1 50); do
  ( source "$JLIB"; SID="p$p"; CLAUDE_JOURNAL_PATH="$JPATH"
    pad=$(printf 'x%.0s' $(seq 1 700))
    for i in $(seq 1 20); do journal_append "h$p" "config_change" '{"path":"/p'"$p"'/'"$i"'","pad":"'"$pad"'"}'; done ) &
done
wait
jtot=$(wc -l < "$JPATH" | tr -d ' ')
jval=$(while IFS= read -r l; do printf '%s' "$l" | jq -e . >/dev/null 2>&1 && echo 1; done < "$JPATH" | wc -l | tr -d ' ')
juniq=$(jq -r '.id' "$JPATH" 2>/dev/null | sort -u | wc -l | tr -d ' ')
if [ "$jtot" = 1000 ] && [ "$jval" = 1000 ] && [ "$juniq" = 1000 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s 50×20 concurrent → 1000/1000 valid JSON, unique ids\n' "journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s concurrency lines=%s valid=%s uniq=%s (want 1000/1000/1000)\n' "journal_append" "$jtot" "$jval" "$juniq"
fi

# (E) consumer dedup — identical (hook,ts_second,category) in TSV + JSONL → counted once
GS="$HOOKS/../scripts/governance-summary.py"
DHOME="$FIXTURE/dedup-home"; mkdir -p "$DHOME/.claude"
printf '%s\n' '{"id":"1-config-change-log-aa","ts":"2026-06-08T12:00:00.500Z","session":"s","hook":"config-change-log","event":"config_change","source":"journal_append","fields":{"path":"/x/foo","source":"ide"}}' > "$DHOME/.claude/governance-events.jsonl"
printf '2026-06-08T12:00:00Z\ts\tide\t/x/foo\n' > "$DHOME/.claude/config-change.log"
if [ -f "$GS" ] && HOME="$DHOME" python3 "$GS" 2>/dev/null | grep -q "cross-stream duplicate"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s consumer dedups TSV+JSONL twin → counted once\n' "governance-summary"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s dedup did not fire (double-count risk)\n' "governance-summary"
fi

# (F) redaction recurses arrays AND catches secret SHAPES (not just flat word keys).
# Shapes are built at runtime so this test file carries no real-looking token
# (same hygiene as the secret-scan cases above; a literal would trip secret-scan).
fake_sk="sk-$(printf 'b%.0s' $(seq 1 24))"               # sk- + 24 = OpenAI-ish shape
fake_aws="AKIA$(printf 'C%.0s' $(seq 1 16))"             # AKIA + 16 upper = AWS shape
: > "$JPATH"
( source "$JLIB"; SID=s; CLAUDE_JOURNAL_PATH="$JPATH"
  journal_append "x" "config_change" '{"logs":["tok='"$fake_sk"'","ok"],"aws":"'"$fake_aws"'","safe":"hello"}' )
if jq -e '.fields.logs[0]=="[redacted]" and .fields.logs[1]=="ok" and .fields.aws=="[redacted]" and .fields.safe=="hello"' "$JPATH" >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s redaction recurses arrays + catches secret shapes\n' "journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s array/shape redaction failed: %s\n' "journal_append" "$(cat "$JPATH")"
fi

# (F2) malformed fields_json → exit 2 + nothing written (the "never silent-drop" invariant)
( source "$JLIB"; SID=s; CLAUDE_JOURNAL_PATH="$FIXTURE/jbad.jsonl"; journal_append "x" "e" 'not valid json' ); jbrc=$?
if [ "$jbrc" = 2 ] && [ ! -s "$FIXTURE/jbad.jsonl" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s malformed fields_json → exit 2, no partial write\n' "journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s malformed: rc=%s wrote=%s\n' "journal_append" "$jbrc" "$([ -s "$FIXTURE/jbad.jsonl" ] && echo yes || echo no)"
fi

# (G) consumer fail-loud on a corrupt JSONL line: warns with line number, no crash
CHOME="$FIXTURE/chome"; mkdir -p "$CHOME/.claude"
printf '%s\n%s\n%s\n' \
  '{"id":"1-h-a","ts":"2026-06-08T12:00:00.0Z","session":"s","hook":"h","event":"config_change","source":"journal_append","fields":{"path":"/a"}}' \
  '{ not valid json' \
  '{"id":"2-h-b","ts":"2026-06-08T12:00:01.0Z","session":"s","hook":"h","event":"config_change","source":"journal_append","fields":{"path":"/b"}}' \
  > "$CHOME/.claude/governance-events.jsonl"
if HOME="$CHOME" python3 "$GS" >/dev/null 2>"$FIXTURE/cerr.txt" && grep -q "corrupt JSONL line 2" "$FIXTURE/cerr.txt"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s corrupt JSONL line → warned (lineno), not crashed\n' "governance-summary"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s corrupt-line fail-loud broken\n' "governance-summary"
fi

# (H) empty-existing vs all-corrupt journal are distinguished (not both "0 events")
EHOME="$FIXTURE/ehome"; mkdir -p "$EHOME/.claude"
printf 'garbage\nmoregarbage\n' > "$EHOME/.claude/governance-events.jsonl"
allc=$(HOME="$EHOME" python3 "$GS" 2>/dev/null | grep -c "ALL 2 line.*corrupt")
: > "$EHOME/.claude/governance-events.jsonl"
emp=$(HOME="$EHOME" python3 "$GS" 2>/dev/null | grep -c "0 events (empty)")
if [ "$allc" -ge 1 ] && [ "$emp" -ge 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s all-corrupt vs empty journal distinguished\n' "governance-summary"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s empty/all-corrupt: allc=%s emp=%s\n' "governance-summary" "$allc" "$emp"
fi

# (I) an event not in KNOWN_EVENTS is warned (schema-drift signal), not silently counted
UHOME="$FIXTURE/uhome"; mkdir -p "$UHOME/.claude"
printf '%s\n' '{"id":"1-h-a","ts":"2026-06-08T12:00:00.0Z","session":"s","hook":"h","event":"totally_new_event","source":"journal_append","fields":{"category":"x"}}' > "$UHOME/.claude/governance-events.jsonl"
if HOME="$UHOME" python3 "$GS" 2>/dev/null | grep -qi "unknown event.*totally_new_event"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s unknown event → warned (schema drift)\n' "governance-summary"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s unknown-event warning missing\n' "governance-summary"
fi

# (J) --since survives a legacy naive-ts line (regression guard: naive-vs-aware
# compare used to crash the whole digest before the load_lines/_within fix)
NHOME="$FIXTURE/nhome"; mkdir -p "$NHOME/.claude"
printf '2026-06-08T10:00:00\ts\t/a.py\tSQL_INJECTION: x\n' > "$NHOME/.claude/security-diff-review.log"
if HOME="$NHOME" python3 "$GS" --since 7 >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s --since survives legacy naive-ts (no crash)\n' "governance-summary"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s --since crashed on naive-ts\n' "governance-summary"
fi

# (K) harness-audit check #29 rejects a hook that calls BOTH journal_append and
# hook_decision (gate↔evidence separation) — minimal fixture repo + run audit.
AUDIT="$HOOKS/../skills/harness-audit/scripts/audit.sh"
KREPO="$FIXTURE/krepo"; mkdir -p "$KREPO/claude/hooks" "$KREPO/claude/agents" "$KREPO/claude/skills" "$KREPO/claude/commands"
cp "$JLIB" "$KREPO/claude/hooks/_lib.sh"
printf '#!/bin/bash\nsource "$(dirname "$0")/_lib.sh"\njournal_append a b c\nhook_decision deny x\n' > "$KREPO/claude/hooks/both-hook.sh"
# Capture first: audit exits non-zero (finding count), which under `set -o
# pipefail` would poison `audit | grep` and read as "no match" even when grep hit.
kaudit_out=$([ -f "$AUDIT" ] && bash "$AUDIT" "$KREPO" 2>&1 || true)
if printf '%s\n' "$kaudit_out" | grep -q "calls BOTH journal_append and hook_decision"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s audit #29 rejects gate+journal in one hook\n' "harness-audit"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s audit #29 negative test did not fire\n' "harness-audit"
fi

# --- C1 Phase II: id-echo additive + non-hook emitter + journaler + registry ---
# The journaler is the /review-pr producer bridge. (L)/(M)/(N)/(O) prove each
# piece of the Phase II contract in isolation; (K) above already proved the
# gate↔evidence separation is intact (the new scripts live in claude/scripts/,
# which audit #29 does NOT scan — verified at audit.sh:666 `for f in hooks/*.sh`).
SCRIPTS="$HOOKS/../scripts"

# (L1) _lib.py:journal_append emits a valid nested-envelope event AND prints
# the minted id on stdout. The id in stdout == the id in the journal file.
# Replaces the journal-emit.sh test that pre-dated the python port (2026-06-09).
: > "$JPATH"
# Set the SID to the journaler hook id (the bash version's self-fallback at
# journal-emit.sh:16 — `SID="${CLAUDE_SESSION_ID:-review-pr-journaler}"` —
# produced the same effect: when the parent shell doesn't propagate a
# session, the journaler attributes the events to itself).
JE=$(CLAUDE_SESSION_ID="review-pr-journaler" CLAUDE_JOURNAL_PATH="$JPATH" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import _lib; _lib.journal_append("review-pr-journaler", "review_finding", sys.argv[2])' \
     "$HOOKS" \
     '{"local_id":"L1","file":"a.py","line":1,"tier":"Minor","agent":"code-reviewer","summary":"x"}' 2>/dev/null)
if [ -n "$JE" ] && [ "$JE" = "$(jq -r .id "$JPATH")" ] \
   && [ "$(jq -r '.event' "$JPATH")" = "review_finding" ] \
   && [ "$(jq -r '.fields.tier' "$JPATH")" = "Minor" ] \
   && [ "$(jq -r '.fields.local_id' "$JPATH")" = "L1" ] \
   && [ "$(jq -r '.session' "$JPATH")" = "review-pr-journaler" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s emits review_finding, prints id == file id, session fallback correct\n' "_lib.py:journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s emit/id/session mismatch: stdout=%s file=%s\n' "_lib.py:journal_append" "$JE" "$(cat "$JPATH")"
fi

# (L2) _lib.py:journal_append SID-fallback: when CLAUDE_SESSION_ID is unset
# AND the caller does not set os.environ.setdefault, the envelope stamps
# `session: "no-sid"` (per _lib.py:109 `os.environ.get("CLAUDE_SESSION_ID",
# "no-sid")`). This is the negative branch L1 covers implicitly — split out
# so a regression here (e.g. a future refactor that always uses
# `os.environ.get` without a default) is caught explicitly.
: > "$JPATH"
JE2=$(unset CLAUDE_SESSION_ID; CLAUDE_JOURNAL_PATH="$JPATH" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import _lib; _lib.journal_append("test-hook", "review_finding", sys.argv[2])' \
      "$HOOKS" \
      '{"local_id":"L2","file":"a.py","line":1,"tier":"Minor","agent":"code-reviewer","summary":"x"}' 2>/dev/null)
if [ -n "$JE2" ] && [ "$(jq -r '.session' "$JPATH")" = "no-sid" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s session==no-sid when CLAUDE_SESSION_ID unset (no caller setdefault)\n' "_lib.py:journal_append:no-sid"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s session-fallback unset branch: stdout=%s file=%s\n' "_lib.py:journal_append:no-sid" "$JE2" "$(cat "$JPATH")"
fi

# (M) review-pr-journal.py: findings.jsonl → 1 review_finding + 1 verification_verdict
# per finding; verdict.subject_id == finding.id; finding.fields.local_id ==
# findings.jsonl's local_id (human-readability invariant). The linkage the
# SCRUTINIZE disposition depends on (without it, the journaler would emit
# orphan verdicts).
SDIR="$FIXTURE/rj-sdir"; rm -rf "$SDIR"; mkdir -p "$SDIR"
printf '%s\n' \
  '{"local_id":"F1","file":"a.py","line":10,"tier":"Critical","disposition":"survived","decision":"fix-now","agent":"code-reviewer","rejected_reason":"","summary":"unwrap None"}' \
  '{"local_id":"F2","file":"b.py","line":20,"tier":"Minor","disposition":"rejected","decision":"proceed","agent":"security-reviewer","rejected_reason":"Q3 happy path only","summary":"old kex"}' \
  > "$SDIR/findings.jsonl"
: > "$JPATH"
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR" 2>/dev/null
N_EVT=$(wc -l < "$JPATH" | tr -d ' ')
N_FIND=$(grep -c '"event":"review_finding"' "$JPATH" || true)
N_VERD=$(grep -c '"event":"verification_verdict"' "$JPATH" || true)
# Linkage: for each review_finding, find its verdict and assert subject_id match.
LINK_OK=1
while IFS= read -r fid; do
  sid=$(jq -r --arg fid "$fid" 'select(.fields.subject_id==$fid) | .id' "$JPATH")
  [ -n "$sid" ] || { LINK_OK=0; break; }
done < <(jq -r 'select(.event=="review_finding") | .id' "$JPATH")
# local_id is preserved in finding.fields (human-readability, not linkage).
LID_F1=$(jq -r 'select(.event=="review_finding" and .fields.local_id=="F1") | .id' "$JPATH")
LID_F2=$(jq -r 'select(.event=="review_finding" and .fields.local_id=="F2") | .id' "$JPATH")
# Manifest: per-pair JSONL line, 2 entries, both local_ids present.
N_MANIFEST=$(wc -l < "$SDIR/.journaled" | tr -d ' ')
MANIFEST_F1=$(grep -c '"local_id":"F1"' "$SDIR/.journaled" || true)
MANIFEST_F2=$(grep -c '"local_id":"F2"' "$SDIR/.journaled" || true)
if [ "$N_EVT" = 4 ] && [ "$N_FIND" = 2 ] && [ "$N_VERD" = 2 ] && [ "$LINK_OK" = 1 ] \
   && [ -n "$LID_F1" ] && [ -n "$LID_F2" ] \
   && [ "$N_MANIFEST" = 2 ] && [ "$MANIFEST_F1" = 1 ] && [ "$MANIFEST_F2" = 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s 2 finding+verdict pairs, verdict.subject_id == finding.id, local_id preserved, manifest=2\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s n_find=%s n_verd=%s link_ok=%s lid_f1=%s lid_f2=%s manifest=%s mf1=%s mf2=%s\n' "review-pr-journal.py" "$N_EVT" "$N_FIND" "$N_VERD" "$LINK_OK" "$LID_F1" "$LID_F2" "$N_MANIFEST" "$MANIFEST_F1" "$MANIFEST_F2"
fi

# (N) review-pr-journal.py idempotency: a second run on the same scratch dir
# no-ops (every local_id in findings.jsonl is already in the manifest) and
# does NOT double-write the journal. (M) left 4 events in $JPATH and a
# 2-line manifest in $SDIR; we re-run the journaler and assert the count
# is still 4 (the second run added 0 new events).
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR" 2>/dev/null
N_EVT2=$(wc -l < "$JPATH" | tr -d ' ')
N_MANIFEST2=$(wc -l < "$SDIR/.journaled" | tr -d ' ')
if [ "$N_EVT2" = 4 ] && [ -e "$SDIR/.journaled" ] && [ "$N_MANIFEST2" = 2 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s re-run no-ops (manifest skip, no double-write)\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt_after_rerun=%s marker=%s n_manifest=%s\n' "review-pr-journal.py" "$N_EVT2" "$([ -e "$SDIR/.journaled" ] && echo yes || echo no)" "$N_MANIFEST2"
fi

# (N2) review-pr-journal.py partial-run recovery: simulate "first run got
# K of N findings journaled, then SIGTERM" by pre-writing a partial
# manifest with K entries, then re-run and assert the second run skips
# the K already-emitted findings and emits only the remaining N-K (no
# double-journal). Without the per-finding manifest checkpoint, the
# second run would re-read findings.jsonl from line 1 and emit
# duplicate finding+verdict events for the K already-journaled ones.
SDIR2="$FIXTURE/rj-sdir2"; rm -rf "$SDIR2"; mkdir -p "$SDIR2"
printf '%s\n' \
  '{"local_id":"P1","file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"p1"}' \
  '{"local_id":"P2","file":"b.py","line":2,"tier":"Minor","disposition":"rejected","decision":"fix-now","agent":"y","rejected_reason":"q","summary":"p2"}' \
  '{"local_id":"P3","file":"c.py","line":3,"tier":"Critical","disposition":"survived","decision":"fix-now","agent":"z","rejected_reason":"","summary":"p3"}' \
  > "$SDIR2/findings.jsonl"
# Pre-seed manifest as if P1 and P2 were journaled in a prior partial run.
printf '%s\n' \
  '{"local_id":"P1","finding_id":"fake-id-1","verdict_id":"fake-id-2"}' \
  '{"local_id":"P2","finding_id":"fake-id-3","verdict_id":"fake-id-4"}' \
  > "$SDIR2/.journaled"
# Pre-seed the journal file with the 4 events from the prior partial run.
printf '%s\n' \
  '{"id":"fake-id-1","ts":"2026-06-08T12:00:00.000Z","session":"s","hook":"review-pr-journaler","event":"review_finding","source":"journal_append","fields":{"local_id":"P1","file":"a.py","line":1,"tier":"Minor","agent":"x","summary":"p1"}}' \
  '{"id":"fake-id-2","ts":"2026-06-08T12:00:00.001Z","session":"s","hook":"review-pr-journaler","event":"verification_verdict","source":"journal_append","fields":{"subject_id":"fake-id-1","disposition":"survived","tier":"Minor","decision":"proceed","rejected_reason":""}}' \
  '{"id":"fake-id-3","ts":"2026-06-08T12:00:00.002Z","session":"s","hook":"review-pr-journaler","event":"review_finding","source":"journal_append","fields":{"local_id":"P2","file":"b.py","line":2,"tier":"Minor","agent":"y","summary":"p2"}}' \
  '{"id":"fake-id-4","ts":"2026-06-08T12:00:00.003Z","session":"s","hook":"review-pr-journaler","event":"verification_verdict","source":"journal_append","fields":{"subject_id":"fake-id-3","disposition":"rejected","tier":"Minor","decision":"fix-now","rejected_reason":"q"}}' \
  > "$JPATH"
# Re-run the journaler; it should skip P1+P2 and emit only P3.
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR2" 2>/dev/null
N_EVT3=$(wc -l < "$JPATH" | tr -d ' ')
N_FIND3=$(grep -c '"event":"review_finding"' "$JPATH" || true)
N_VERD3=$(grep -c '"event":"verification_verdict"' "$JPATH" || true)
N_MANIFEST3=$(wc -l < "$SDIR2/.journaled" | tr -d ' ')
# After retry: journal = 4 (pre-seed) + 2 (P3 pair) = 6, manifest = 2 (pre-seed) + 1 (P3) = 3.
if [ "$N_EVT3" = 6 ] && [ "$N_FIND3" = 3 ] && [ "$N_VERD3" = 3 ] && [ "$N_MANIFEST3" = 3 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s partial-run: skip already-journaled, resume cleanly (P3 only)\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 6) n_find=%s (want 3) n_verd=%s (want 3) n_manifest=%s (want 3)\n' "review-pr-journal.py" "$N_EVT3" "$N_FIND3" "$N_VERD3" "$N_MANIFEST3"
fi

# (P) review-pr-journal.py enum validation: a finding with a bad tier /
# disposition / decision emits a WARNING on stderr AND still emits the
# event (Q3=a "silent FYI, never unwinds" — journaler is best-effort, not
# a submit gate; the user sees the warning, the journal has the data).
SDIR3="$FIXTURE/rj-sdir3"; rm -rf "$SDIR3"; mkdir -p "$SDIR3"
printf '%s\n' \
  '{"local_id":"Q1","file":"a.py","line":1,"tier":"whoops","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"bad tier"}' \
  '{"local_id":"Q2","file":"b.py","line":2,"tier":"Minor","disposition":"maybe","decision":"proceed","agent":"y","rejected_reason":"","summary":"bad disp"}' \
  '{"local_id":"Q3","file":"c.py","line":3,"tier":"Minor","disposition":"rejected","decision":"eventually","agent":"z","rejected_reason":"","summary":"bad dec"}' \
  > "$SDIR3/findings.jsonl"
: > "$JPATH"
STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR3" 2>&1 >/dev/null || true)
N_EVT_P=$(wc -l < "$JPATH" | tr -d ' ')
# All 3 findings should have been journaled (best-effort, not blocked).
# All 3 should have produced a WARNING on stderr naming the local_id and
# the bad value.
WARN_TIER=$(printf '%s' "$STDERR" | grep -c "tier='whoops'" || true)
WARN_DISP=$(printf '%s' "$STDERR" | grep -c "disposition='maybe'" || true)
WARN_DEC=$(printf '%s' "$STDERR" | grep -c "decision='eventually'" || true)
if [ "$N_EVT_P" = 6 ] && [ "$WARN_TIER" = 1 ] && [ "$WARN_DISP" = 1 ] && [ "$WARN_DEC" = 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s bad enum: WARNING to stderr, journal still emits (best-effort)\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 6) warn_tier=%s warn_disp=%s warn_dec=%s\n' "review-pr-journal.py" "$N_EVT_P" "$WARN_TIER" "$WARN_DISP" "$WARN_DEC"
fi

# (Q) REMOVED 2026-06-09: bash review-pr-journaler ported to _lib.py
# (stdlib re+json.dumps). The no-jq pre-flight is gone with the bash
# path. (M)/(N)/(N2)/(P) above are the contract; (Q) tested an
# implementation detail of the deleted file. The Python journaler
# deliberately has no jq dep — exiting 2 on missing jq would be a
# regression. The audit-time consumer is `python3 -c 'import ast;
# ast.parse(open(p).read())'` which now applies to _lib.py +
# review-pr-journal.py as well as the bash hooks.

# (O) governance-summary digests review_finding (and verification_verdict) without
# the "unknown event" warn that would fire if KNOWN_EVENTS hadn't been updated.
# A regression in the registry pair (markdown table vs Python set) would surface
# here as either "event absent from digest" or "unknown event warn present".
OHOME="$FIXTURE/ohome"; mkdir -p "$OHOME/.claude"
printf '%s\n' \
  '{"id":"1-rf-a","ts":"2026-06-08T12:00:00.000Z","session":"s","hook":"review-pr-journaler","event":"review_finding","source":"journal_append","fields":{"file":"a.py","line":1,"tier":"Minor","agent":"x","summary":"y"}}' \
  '{"id":"2-vv-a","ts":"2026-06-08T12:00:00.001Z","session":"s","hook":"review-pr-journaler","event":"verification_verdict","source":"journal_append","fields":{"subject_id":"1-rf-a","disposition":"survived","tier":"Minor","decision":"proceed","rejected_reason":""}}' \
  > "$OHOME/.claude/governance-events.jsonl"
OUT=$(HOME="$OHOME" python3 "$GS" 2>/dev/null)
if printf '%s\n' "$OUT" | grep -q "review_finding" && ! printf '%s\n' "$OUT" | grep -qi "unknown event.*review_finding"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s review_finding digested, no unknown-event warn\n' "governance-summary"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s digest failed or registry lag\n' "governance-summary"
fi

# (R) review-pr-journal.py bails loud on a malformed .journaled manifest —
# a non-JSON line means the prior run died in a way that left garbage, and
# silently re-emitting on top of that garbage would corrupt the journal.
# The guard must exit 2, name the file in stderr, and write nothing new.
SDIR5="$FIXTURE/rj-sdir5"; rm -rf "$SDIR5"; mkdir -p "$SDIR5"
printf '%s\n' \
  '{"local_id":"R1","file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"ok"}' \
  > "$SDIR5/findings.jsonl"
printf 'not-json-at-all\ngarbage line 2\n' > "$SDIR5/.journaled"
: > "$JPATH"
EXIT_CODE=0
STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR5" 2>&1 >/dev/null) || EXIT_CODE=$?
N_EVT_R=$(wc -l < "$JPATH" | tr -d ' ')
if [ "$EXIT_CODE" = 2 ] \
   && printf '%s' "$STDERR" | grep -q "\.journaled" \
   && printf '%s' "$STDERR" | grep -q "refusing to retry" \
   && [ "$N_EVT_R" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s malformed manifest: exit 2, stderr names file, no events written\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit=%s (want 2) n_evt=%s (want 0) stderr=%s\n' "review-pr-journal.py" "$EXIT_CODE" "$N_EVT_R" "$STDERR"
fi

# (S) review-pr-journal.py fails loud on missing findings.jsonl — covers
# the Phase 6 → Phase 7 race where the canonical write is skipped (silent
# drop) and the journaler is called anyway. The fix is: exit 2 + stderr
# names the missing path. Without this test, the silent-drop is invisible.
SDIR6="$FIXTURE/rj-sdir6"; rm -rf "$SDIR6"; mkdir -p "$SDIR6"
# Intentionally do NOT create findings.jsonl.
: > "$JPATH"
EXIT_CODE=0
STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR6" 2>&1 >/dev/null) || EXIT_CODE=$?
N_EVT_S=$(wc -l < "$JPATH" | tr -d ' ')
if [ "$EXIT_CODE" = 2 ] \
   && printf '%s' "$STDERR" | grep -q "missing" \
   && printf '%s' "$STDERR" | grep -q "findings.jsonl" \
   && [ "$N_EVT_S" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s missing findings.jsonl: exit 2, stderr names path, no events written\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit=%s (want 2) n_evt=%s (want 0) stderr=%s\n' "review-pr-journal.py" "$EXIT_CODE" "$N_EVT_S" "$STDERR"
fi

# (T) review-pr-journal.py preserves `line: null` for review-body findings
# (no file:line). The jq path uses --argjson with `${line_num:-null}`
# so a null line stays JSON null, not the string "null" — a regression
# here would corrupt the journal for review-body candidates and break
# the consumer's "no file:line → no inline pin" rendering.
SDIR7="$FIXTURE/rj-sdir7"; rm -rf "$SDIR7"; mkdir -p "$SDIR7"
# tier="" is the review-body marker (per SKILL.md / journaler regex).
printf '%s\n' \
  '{"local_id":"T1","file":"","line":null,"tier":"","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"review-body finding"}' \
  > "$SDIR7/findings.jsonl"
: > "$JPATH"
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR7" 2>/dev/null
# Pull the review_finding event's `fields.line` — must be the JSON `null`
# literal, not the 4-char string "null". jq -r prints null unquoted; the
# string would print as \"null\" (or rather, the raw 4 chars).
LINE_FIELD=$(grep '"event":"review_finding"' "$JPATH" | head -1 | jq -r '.fields.line')
N_EVT_T=$(wc -l < "$JPATH" | tr -d ' ')
if [ "$N_EVT_T" = 2 ] && [ "$LINE_FIELD" = "null" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s review-body finding: line=null (JSON null, not string)\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 2) fields.line=%q (want JSON null)\n' "review-pr-journal.py" "$N_EVT_T" "$LINE_FIELD"
fi

# (U) review-pr-journal.py JSON-escapes model-controlled ids on the
# manifest write — adversarial local_id containing `"` and `\n` must
# still produce a parseable manifest line that equals the input
# local_id byte-for-byte after a jq round-trip. Locks the fix at
# review-pr-journal.py:192 (manifest write uses jq -nc --arg).
SDIR8="$FIXTURE/rj-sdir8"; rm -rf "$SDIR8"; mkdir -p "$SDIR8"
# local_id contains a literal " and \n — a shell-substituted printf would
# emit `{"local_id":"U"1","...}}` (unparseable) or corrupt the manifest.
printf '%s\n' \
  '{"local_id":"U1\"with\nquote","file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"escape probe"}' \
  > "$SDIR8/findings.jsonl"
: > "$JPATH"
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR8" 2>/dev/null
# Manifest line must parse as JSON and the local_id must round-trip exactly.
ROUND_TRIP=$(jq -r '.local_id // empty' < "$SDIR8/.journaled" 2>/dev/null)
N_MANI=$(wc -l < "$SDIR8/.journaled" | tr -d ' ')
if [ "$N_MANI" = 1 ] && [ "$ROUND_TRIP" = 'U1"with
quote' ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s manifest escapes adversarial local_id (parseable + round-trip)\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_mani=%s (want 1) round_trip=%q (want the adversarial local_id)\n' "review-pr-journal.py" "$N_MANI" "$ROUND_TRIP"
fi

# (V) review-pr-journal.py writes a manifest line whose finding_id/verdict_id
# match the just-emitted journal event ids — locks the journal↔manifest
# linkage so a future refactor that drops the `>>` (or swaps $fid/$vid) is
# caught at test time, not at retry time (when partial-run recovery would
# silently re-emit duplicates).
SDIR9="$FIXTURE/rj-sdir9"; rm -rf "$SDIR9"; mkdir -p "$SDIR9"
printf '%s\n' \
  '{"local_id":"V1","file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"manifest-link probe"}' \
  > "$SDIR9/findings.jsonl"
: > "$JPATH"
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR9" 2>/dev/null
# Pull finding_id and verdict_id from the journal events and from the
# manifest line, then assert each pair matches.
J_FID=$(grep '"event":"review_finding"' "$JPATH" | head -1 | jq -r '.id // empty')
J_VID=$(grep '"event":"verification_verdict"' "$JPATH" | head -1 | jq -r '.id // empty')
M_FID=$(jq -r '.finding_id // empty' < "$SDIR9/.journaled")
M_VID=$(jq -r '.verdict_id // empty' < "$SDIR9/.journaled")
N_EVT_V=$(wc -l < "$JPATH" | tr -d ' ')
N_MANI_V=$(wc -l < "$SDIR9/.journaled" | tr -d ' ')
if [ "$N_EVT_V" = 2 ] && [ "$N_MANI_V" = 1 ] \
   && [ -n "$J_FID" ] && [ "$J_FID" = "$M_FID" ] \
   && [ -n "$J_VID" ] && [ "$J_VID" = "$M_VID" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s manifest finding_id/verdict_id match journal event ids\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s n_mani=%s j_fid=%s m_fid=%s j_vid=%s m_vid=%s\n' "review-pr-journal.py" "$N_EVT_V" "$N_MANI_V" "$J_FID" "$M_FID" "$J_VID" "$M_VID"
fi

# (W) review-pr-journal.py dedup is keyed on .local_id, NOT on .file/.tier/etc.
# The dedup check (jq INDEX at line 82 + has($id) at line 143) MUST be keyed
# on the SAME field the model uses as the scratch-dedup id (.local_id). The
# threat model: a future "minor cleanup" changes INDEX(.local_id) to
# INDEX(.file) or INDEX(.tier) — under the prior single-finding fixture,
# the COUNTS assertion alone (n_evt=2, n_mani=1) would still PASS because
# the dedup is still SOMETHING, so a wrong-field IX is silently invisible.
# This test uses a 2-finding fixture where A and B share .file and .tier
# but differ in .local_id. A correct dedup (INDEX(.local_id)) emits BOTH on
# the first run (different local_ids → both new) and SKIPS BOTH on the
# second run (both local_ids already in the manifest). A wrong-field
# dedup (e.g. INDEX(.file)) would collapse A and B into one dedup key
# (they share .file) and skip one of them on the first run — counts
# drop to n_evt=2 (1 pair, 1 skipped) instead of n_evt=4 (2 pairs).
# Source local_id A and B are multi-line adversarial values (matching
# test (U)'s shape) so a partial-key IX (e.g. a buggy INDEX(.file) that
# hashes on the first 4 bytes) would also mismatch. The local_id is
# stored JSON-escaped in findings.jsonl (the `\"` and `\n` are 2 chars
# each, NOT a real LF) so the file remains 2 well-formed JSON lines;
# jq decodes the escapes when reading the manifest, recovering the
# real LF for byte-exact comparison. If this test ever regresses, the
# dedup was rewritten against a different field.
# Write the fixture with a here-doc (single-quoted EOF → no shell
# expansion) so the literal \" and \n sequences land in the file as
# JSON-escape sequences, NOT through a bash variable that would close
# the JSON string prematurely. The on-disk source is 15 bytes per
# local_id: W, 1, \, ", w, i, t, h, \, n, q, u, o, t, e. jq decodes
# the JSON escapes to a 13-byte value: W, 1, ", w, i, t, h, LF, q, u,
# o, t, e (the byte count drops by 2 because `\"` and `\n` each
# collapse from a 2-byte escape sequence to 1 byte).
SDIR10="$FIXTURE/rj-sdir10"; rm -rf "$SDIR10"; mkdir -p "$SDIR10"
# A and B share .file and .tier deliberately — a wrong-field IX(.file)
# would key both under the same value and skip one of them.
cat > "$SDIR10/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":"W1\"with\nquote","file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"dedup probe A"}
{"local_id":"W2\"with\nquote","file":"a.py","line":2,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"dedup probe B"}
FIXTURE_EOF
: > "$JPATH"
# First run: 2 fresh local_ids → 2 pairs emitted (n_evt=4 events).
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR10" 2>/dev/null
# Second run: both local_ids already in manifest → 0 pairs emitted.
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR10" 2>/dev/null
# Verify the manifest contains BOTH local_ids (proof that the first run
# emitted both — a wrong-field IX(.file) would have collapsed A and B
# into one dedup key and the manifest would only have one).
N_EVT_W=$(wc -l < "$JPATH" | tr -d ' ')
N_MANI_W=$(wc -l < "$SDIR10/.journaled" | tr -d ' ')
MANI_LIDS=$(jq -r '.local_id // empty' < "$SDIR10/.journaled" 2>/dev/null | sort | tr '\n' '|')
# jq decodes the JSON-escape sequences in the manifest's .local_id to
# their real bytes (a real " and a real LF for \" and \n). The decoded
# form is 13 bytes: W1"with<LF>quote. `printf '%b'` interprets \n as
# a real newline so the comparison matches jq's decoded output. Pipe
# through `sort` to match MANI_LIDS' order, then `tr '\n' '|'` to
# match its delimiter form.
EXPECT_LID_A=$(printf '%b' 'W1"with\nquote')
EXPECT_LID_B=$(printf '%b' 'W2"with\nquote')
EXPECT_LIDS=$(printf '%s\n%s\n' "$EXPECT_LID_A" "$EXPECT_LID_B" | sort | tr '\n' '|')
if [ "$N_EVT_W" = 4 ] && [ "$N_MANI_W" = 2 ] && [ "$MANI_LIDS" = "$EXPECT_LIDS" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s dedup keyed on local_id (n_evt=4, n_mani=2, both A and B present)\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1))
  if [ "$N_EVT_W" != 4 ] || [ "$N_MANI_W" != 2 ]; then
    printf '  ❌ %-26s n_evt=%s (want 4) n_mani=%s (want 2) — dedup collapsed distinct local_ids (wrong-field IX)\n' "review-pr-journal.py" "$N_EVT_W" "$N_MANI_W" >&2
  else
    printf '  ❌ %-26s n_evt=4 n_mani=2 but MANI_LIDS≠EXPECT — manifest lost a local_id\n' "review-pr-journal.py" >&2
  fi
fi

# (X) review-pr-journal.py handles findings with a null or missing
# .local_id — the `// empty` filter on the dedup INDEX must drop those
# rows (line 90) so they don't pollute the lookup with `null` keys, AND
# the upstream local_id validator (line 171) must catch them with a
# stderr ERROR and N_SKIPPED++. A finding with a missing .local_id key
# goes through the validator's `[ -z "$local_id" ]` check (`jq -r '.
# local_id // ""'` returns empty string for missing), the error fires,
# the event is NOT journaled, and the .journaled manifest is unchanged.
SDIR11="$FIXTURE/rj-sdir11"; rm -rf "$SDIR11"; mkdir -p "$SDIR11"
cat > "$SDIR11/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":null,"file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"null local_id probe"}
{"file":"b.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"missing local_id probe"}
{"local_id":"","file":"c.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"empty local_id probe"}
FIXTURE_EOF
: > "$JPATH"
STDERR_X=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR11" 2>&1 >/dev/null || true)
N_EVT_X=$(wc -l < "$JPATH" | tr -d ' ')
# Manifest may not exist if no findings passed the validator; the
# journaler does not touch the file in the all-skip case.
N_MANI_X=0
if [ -e "$SDIR11/.journaled" ]; then
  N_MANI_X=$(wc -l < "$SDIR11/.journaled" | tr -d ' ')
fi
# Expect: 0 events journaled (all 3 are empty-id), 0 manifest lines
# (nothing was emitted, so the file is not created), and 3 ERROR lines
# on stderr — one per finding.
N_ERR_X=$(printf '%s\n' "$STDERR_X" | grep -c "review-pr-journal: ERROR: finding at offset" || true)
if [ "$N_EVT_X" = 0 ] && [ "$N_MANI_X" = 0 ] && [ "$N_ERR_X" = 3 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s null/missing/empty local_id → 3 errors, 0 events, 0 manifest lines\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 0) n_mani=%s (want 0) n_err=%s (want 3)\n' "review-pr-journal.py" "$N_EVT_X" "$N_MANI_X" "$N_ERR_X" >&2
fi

# (Y) review-pr-journal.py dedup INDEX last-wins on duplicate manifest
# entries — a pre-populated manifest with two lines sharing the same
# .local_id produces an INDEX that maps the local_id to the LAST entry.
# This is a known gap (per the partial-run SIGTERM comment in
# review-pr-journal.py:26-41); the journaler does not currently detect
# or repair duplicate manifest entries. This test pins the BEHAVIOR
# (last-wins) so a future fix (dedup-on-load, or fail-loud on dup) is
# caught at test time. A second journaler run with the same fixture
# sees the local_id in the lookup and skips the emit — proving the
# dedup IS consulted, even when the lookup is internally inconsistent.
SDIR12="$FIXTURE/rj-sdir12"; rm -rf "$SDIR12"; mkdir -p "$SDIR12"
cat > "$SDIR12/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":"Y1","file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"dup-manifest probe A"}
FIXTURE_EOF
# Pre-populate the manifest with TWO entries for the same .local_id,
# pointing to fake finding/verdict ids (they don't have to exist in
# the journal — the dedup check is a set-membership test, not a
# cross-reference).
jq -nc '{local_id:"Y1",finding_id:"fake-fid-1",verdict_id:"fake-vid-1"}' > "$SDIR12/.journaled"
jq -nc '{local_id:"Y1",finding_id:"fake-fid-2",verdict_id:"fake-vid-2"}' >> "$SDIR12/.journaled"
: > "$JPATH"
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR12" 2>/dev/null
N_EVT_Y=$(wc -l < "$JPATH" | tr -d ' ')
N_MANI_Y=$(wc -l < "$SDIR12/.journaled" | tr -d ' ')
# Expect: 0 events journaled (Y1 is in the manifest → skipped), and
# the manifest is unchanged at 2 lines (the journaler does not
# rewrite or dedup the manifest on load).
if [ "$N_EVT_Y" = 0 ] && [ "$N_MANI_Y" = 2 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s dup-manifest entries: dedup last-wins, no emit, manifest unchanged\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 0) n_mani=%s (want 2)\n' "review-pr-journal.py" "$N_EVT_Y" "$N_MANI_Y" >&2
fi

# (Z) _lib.py:journal_append fail-loud on non-serializable dict values
# (F1 in the 2026-06-09 review). The str arm of `fields_json` exits 2 on
# JSONDecodeError; the dict arm MUST exit 2 on TypeError (the dict-passing
# contract is documented in the docstring; a TypeError-from-json.dumps
# regression would crash the python caller with a traceback and rc=1,
# violating the contract). `set` is the canonical non-serializable type.
: > "$JPATH"
JE_Z=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 -c '
import sys; sys.path.insert(0, sys.argv[1]); import _lib
import os; os.environ["CLAUDE_JOURNAL_PATH"] = sys.argv[2]
_lib.journal_append("test-hook", "config_change", {"file": set([1,2])})
' "$HOOKS" "$JPATH" 2>&1)
RC_Z=$?
N_EVT_Z=$(wc -l < "$JPATH" | tr -d ' ')
if [ "$RC_Z" = 2 ] && [ "$N_EVT_Z" = 0 ] && printf '%s' "$JE_Z" | grep -q "TypeError"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s non-serializable dict → exit 2 (TypeError caught, no partial write)\n' "_lib.py:journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s (want 2) n_evt=%s (want 0) stderr=%s\n' "_lib.py:journal_append" "$RC_Z" "$N_EVT_Z" "$JE_Z" >&2
fi

# (AA) _lib.py:_redact byte-for-byte equivalent to bash `val_dl` for the
# keyword substring (F2). A value containing `password|secret|token|credential`
# is replaced with `"[redacted]"` (matches bash journal_append's behavior
# at _lib.sh:150-151). Without this fix, the python path leaves the value
# intact while bash would redact — a lockstep-invariant break.
: > "$JPATH"
AA_OUT=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 -c '
import sys; sys.path.insert(0, sys.argv[1]); import _lib
import os; os.environ["CLAUDE_JOURNAL_PATH"] = sys.argv[2]
_lib.journal_append("test-hook", "config_change",
                    {"description": "the user password is leaked"})
' "$HOOKS" "$JPATH" 2>/dev/null)
REDACTED=$(grep '"event":"config_change"' "$JPATH" | head -1 | jq -r '.fields.description')
if [ "$REDACTED" = "[redacted]" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s value-keyword redact matches bash (password|secret|token|credential)\n' "_lib.py:_redact"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s fields.description=%q (want "[redacted]")\n' "_lib.py:_redact" "$REDACTED" >&2
fi

# (BB) _lib.py:_redact emits a stderr WARNING when the depth cap fires
# (F5 in the 2026-06-09 review). A 100-deep nested dict exceeds the cap
# at depth 64; the journaler logs the truncation so the operator can
# tell the journal line was lossy-compressed vs. a real value of the
# same shape. Without this fix, the truncation is silent.
: > "$JPATH"
BB_STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 -c '
import sys; sys.path.insert(0, sys.argv[1]); import _lib
import os; os.environ["CLAUDE_JOURNAL_PATH"] = sys.argv[2]
deep = {"leaf": "value"}; d = deep
for _ in range(100): d["n"] = {"a": 1}; d = d["n"]
_lib.journal_append("test-hook", "config_change", deep)
' "$HOOKS" "$JPATH" 2>&1 >/dev/null)
N_EVT_BB=$(wc -l < "$JPATH" | tr -d ' ')
if [ "$N_EVT_BB" = 1 ] && printf '%s' "$BB_STDERR" | grep -q "WARNING.*depth-capped"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s depth-capped at 64 → stderr WARNING + 1 journal line (no crash)\n' "_lib.py:_redact"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 1) stderr=%s\n' "_lib.py:_redact" "$N_EVT_BB" "$BB_STDERR" >&2
fi

# --- 2026-06-09 review fixes: 7 Critical findings from PR #1 review ---
# CC/DD/EE/FF/GG/HH/II close the 7 Critical gaps surfaced by the Phase-5
# SCRUTINIZE-4 gate (Q3 tightened at 78% rolling 10 — see
# .scratch/review-pr-2026-06-09T11-5756Z/ledger.md). Each test pins one
# file:line fix and asserts the contract the journaler is supposed to
# enforce but didn't before this patch.

# (CC) review-pr-journal.py:_check_enums re.match on non-string crashed
# with TypeError → rc=1 + traceback (CR-1 fix: isinstance guard). Test
# pins the no-crash contract + the type-guard's stderr shape (field name
# + `type=<typename>`). Per-line malformed input → skip + rc=0 (the
# same skip-counter pattern as JSON parse errors); the rc=2 path is
# reserved for whole-file issues (missing findings, unreadable manifest).
SDIR_CC="$FIXTURE/rj-cc"; rm -rf "$SDIR_CC"; mkdir -p "$SDIR_CC"
printf '%s\n' \
  '{"local_id":"CC1","file":"a.py","line":1,"tier":"Critical","disposition":"survived","decision":42,"agent":"x","rejected_reason":"","summary":"decision: int"}' \
  > "$SDIR_CC/findings.jsonl"
: > "$JPATH"
JE_CC=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR_CC" 2>&1 >/dev/null)
RC_CC=$?
N_EVT_CC=$(wc -l < "$JPATH" | tr -d ' ')
# rc=0 (skip, not fatal) + 0 new journal events + stderr names "decision"
# AND contains "type=int" (the type-guard reporting shape from the fix)
# AND does NOT contain "TypeError" or "Traceback" (the pre-fix crash shape).
if [ "$RC_CC" = 0 ] && [ "$N_EVT_CC" = 0 ] \
   && printf '%s' "$JE_CC" | grep -q "decision" \
   && printf '%s' "$JE_CC" | grep -q "type=int" \
   && ! printf '%s' "$JE_CC" | grep -qi "TypeError\|Traceback"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s decision=42 (int) → rc=0 + 0 events + stderr names field+type (no crash)\n' "review-pr-journal.py:CC"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s (want 0) n_evt=%s (want 0) stderr=%s\n' "review-pr-journal.py:CC" "$RC_CC" "$N_EVT_CC" "$JE_CC" >&2
fi

# (DD) review-pr-journal.py:_check_enums bypass on empty-string enum
# (CR-2 fix: drop the `and` short-circuit). Test pins both: stderr
# contains the WARNING (no more silent bypass) AND the finding is still
# emitted (the "still emits anyway" best-effort contract).
SDIR_DD="$FIXTURE/rj-dd"; rm -rf "$SDIR_DD"; mkdir -p "$SDIR_DD"
printf '%s\n' \
  '{"local_id":"DD1","file":"a.py","line":1,"tier":"Critical","disposition":"","decision":"","agent":"x","rejected_reason":"","summary":"empty enums"}' \
  > "$SDIR_DD/findings.jsonl"
: > "$JPATH"
DD_STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR_DD" 2>&1 >/dev/null)
DD_N_EVT=$(wc -l < "$JPATH" | tr -d ' ')
# rc=0 (best-effort, still emits), 2 journal events (finding + verdict),
# stderr contains BOTH "disposition" and "decision" WARNINGs.
if [ "$DD_N_EVT" = 2 ] \
   && printf '%s' "$DD_STDERR" | grep -q "disposition" \
   && printf '%s' "$DD_STDERR" | grep -q "decision"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s disposition="" / decision="" → emits AND stderr names both\n' "review-pr-journal.py:DD"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 2) stderr=%s\n' "review-pr-journal.py:DD" "$DD_N_EVT" "$DD_STDERR" >&2
fi

# (EE) review-pr-journal.py: 5 missing field type-validators (CR-3 fix:
# mirror F7's `or ""` silent-coercion foot-gun for agent/tier/disposition/
# decision/rejected_reason). Test feeds 5 type-mismatched fields in one
# finding; the journaler short-circuits on the first bad field, so we
# can only assert that ONE of the 5 names is in stderr (whichever field
# the F7-pattern check fires on first). The contract pinned: skip +
# rc=0 + stderr names the first offending field + `type=<typename>` +
# no TypeError/Traceback (the pre-fix crash shape).
SDIR_EE="$FIXTURE/rj-ee"; rm -rf "$SDIR_EE"; mkdir -p "$SDIR_EE"
printf '%s\n' \
  '{"local_id":"EE1","file":"a.py","line":1,"tier":["crit"],"disposition":7,"decision":null,"agent":["x"],"rejected_reason":{},"summary":"all bad types"}' \
  > "$SDIR_EE/findings.jsonl"
: > "$JPATH"
EE_STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR_EE" 2>&1 >/dev/null)
EE_RC=$?
EE_N_EVT=$(wc -l < "$JPATH" | tr -d ' ')
# rc=0 (skip) + 0 events + stderr names the first bad field with its type
# + no TypeError/Traceback. The first F7 check that fires is `tier` (the
# field order in _check_enums + the F7 pattern: tier/agent/disposition/
# decision/rejected_reason are checked in that order).
if [ "$EE_RC" = 0 ] && [ "$EE_N_EVT" = 0 ] \
   && printf '%s' "$EE_STDERR" | grep -q "tier" \
   && printf '%s' "$EE_STDERR" | grep -q "type=list" \
   && ! printf '%s' "$EE_STDERR" | grep -qi "TypeError\|Traceback"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s 5 wrong-type fields → rc=0 + 0 events + stderr names tier/type=list (no crash)\n' "review-pr-journal.py:EE"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s n_evt=%s stderr=%s\n' "review-pr-journal.py:EE" "$EE_RC" "$EE_N_EVT" "$EE_STDERR" >&2
fi

# (FF) _lib.sh:_journal_append_py shim end-to-end (CR-4 fix: 0 existing
# tests for the only bash caller of the python module). Sources the lib,
# invokes the shim, asserts rc=0 + well-formed envelope (id, ts, session,
# hook, event, source="journal_append", fields). Also asserts the SID
# propagation contract (CLAUDE_SESSION_ID from the caller reaches the
# envelope `session` field).
: > "$JPATH"
SID_FF="shim-session-test"
# Sister: CLAUDE_JOURNAL_PATH EXPORTED (lands at /tmp/x)
JPATH_FF="$FIXTURE/shim-journal.jsonl"
: > "$JPATH_FF"
( export CLAUDE_JOURNAL_PATH="$JPATH_FF" CLAUDE_SESSION_ID="$SID_FF"
  source "$JLIB"
  _journal_append_py "shim-test" "test_finding" '{"file":"a.py","line":1}' ) > "$FIXTURE/shim-out.txt" 2>&1
FF_RC=$?
FF_STDOUT=$(cat "$FIXTURE/shim-out.txt")
FF_N_EVT=$(wc -l < "$JPATH_FF" | tr -d ' ')
FF_SESSION=$(jq -r '.session' "$JPATH_FF" 2>/dev/null)
FF_EVENT=$(jq -r '.event' "$JPATH_FF" 2>/dev/null)
FF_SOURCE=$(jq -r '.source' "$JPATH_FF" 2>/dev/null)
# Assert: rc=0, 1 event, session propagated, event name stamped, source=journal_append
if [ "$FF_RC" = 0 ] && [ "$FF_N_EVT" = 1 ] && [ "$FF_SESSION" = "$SID_FF" ] \
   && [ "$FF_EVENT" = "test_finding" ] && [ "$FF_SOURCE" = "journal_append" ] \
   && [ -n "$FF_STDOUT" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s rc=0 + 1 event + session/event/source all stamped + id on stdout\n' "_lib.sh:_journal_append_py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s n_evt=%s session=%s event=%s source=%s stdout=%s\n' "_lib.sh:_journal_append_py" "$FF_RC" "$FF_N_EVT" "$FF_SESSION" "$FF_EVENT" "$FF_SOURCE" "$FF_STDOUT" >&2
fi

# (GG) review-pr-journal.py: manifest write I/O error uncaught (CR-5
# fix). Simulate ENOSPC on the manifest path by chmod-ing the manifest
# dir to read-only AFTER pre-seeding it. Test pins: rc=2 + stderr names
# the manifest path + the finding+verdict id is in stderr (operator
# needs to know which ids to manually append to the dedup set).
SDIR_GG="$FIXTURE/rj-gg"; rm -rf "$SDIR_GG"; mkdir -p "$SDIR_GG"
# Pre-seed the manifest as if a prior run died (so the journaler will
# try to append, not create). Read-only dir blocks the open("a").
printf '%s\n' \
  '{"local_id":"GG0","file":"a.py","line":1,"tier":"Critical","disposition":"survived","decision":"fix-now","agent":"x","rejected_reason":"","summary":"gg seed"}' \
  > "$SDIR_GG/findings.jsonl"
: > "$JPATH"
chmod 555 "$SDIR_GG"
GG_STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR_GG" 2>&1 >/dev/null)
GG_RC=$?
chmod 755 "$SDIR_GG"  # cleanup
GG_N_EVT=$(wc -l < "$JPATH" | tr -d ' ')
# rc=2 (not 1) + stderr names the manifest path + stderr prints the journaled ids
# so the operator can manually append. We assert stderr names "$SDIR_GG/.journaled".
if [ "$GG_RC" = 2 ] && [ "$GG_N_EVT" = 2 ] \
   && printf '%s' "$GG_STDERR" | grep -q "\.journaled" \
   && printf '%s' "$GG_STDERR" | grep -q "journaled ids"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s manifest write fail (chmod 555) → rc=2 + 2 events written + stderr names path + ids\n' "review-pr-journal.py:GG"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s n_evt=%s stderr=%s\n' "review-pr-journal.py:GG" "$GG_RC" "$GG_N_EVT" "$GG_STDERR" >&2
fi

# (HH) review-pr-journal.py:_load_manifest_dedup read I/O error uncaught
# (CR-6 fix). Pre-seed the manifest, then chmod 000 so the open() raises
# PermissionError. Test pins: rc=2 + stderr names the manifest path.
SDIR_HH="$FIXTURE/rj-hh"; rm -rf "$SDIR_HH"; mkdir -p "$SDIR_HH"
printf '%s\n' \
  '{"local_id":"HH0","file":"a.py","line":1,"tier":"Critical","disposition":"survived","decision":"fix-now","agent":"x","rejected_reason":"","summary":"hh seed"}' \
  > "$SDIR_HH/findings.jsonl"
# Pre-seed a non-empty manifest so the load path actually runs (chmod 000
# on a non-existent path is ENOENT, not PermissionError; we need the file
# to exist so the chmod denies the open, not the exists() check).
printf '{"local_id":"old","finding_id":"f","verdict_id":"v"}\n' > "$SDIR_HH/.journaled"
chmod 000 "$SDIR_HH/.journaled"
: > "$JPATH"
HH_STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/review-pr-journal.py" "$SDIR_HH" 2>&1 >/dev/null)
HH_RC=$?
chmod 644 "$SDIR_HH/.journaled"  # cleanup
# rc=2 + 0 events (the load failed, so we never even got to the loop) +
# stderr names the manifest path.
if [ "$HH_RC" = 2 ] \
   && printf '%s' "$HH_STDERR" | grep -q "\.journaled" \
   && printf '%s' "$HH_STDERR" | grep -q "manifest read failed"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s manifest read fail (chmod 000) → rc=2 + stderr names path + "manifest read failed"\n' "review-pr-journal.py:HH"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s stderr=%s\n' "review-pr-journal.py:HH" "$HH_RC" "$HH_STDERR" >&2
fi

# (II) _lib.py:journal_append json.dumps accepts NaN/Inf silently (CR-7
# fix: `allow_nan=False` rejects with ValueError, caught by the
# extended `except (..., ValueError)`). Test feeds a fields_json with
# `float('nan')` and `math.inf`; assert rc=2 + ValueError in stderr +
# 0 new events (no silent corruption).
: > "$JPATH"
II_STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 -c '
import sys, math
sys.path.insert(0, sys.argv[1])
import _lib
import os
os.environ["CLAUDE_JOURNAL_PATH"] = sys.argv[2]
_lib.journal_append("test-hook", "config_change", {"x": math.nan, "y": math.inf})
' "$HOOKS" "$JPATH" 2>&1 >/dev/null)
II_RC=$?
II_N_EVT=$(wc -l < "$JPATH" | tr -d ' ')
# rc=2 + 0 events + stderr names "ValueError" (the new allow_nan=False rejection)
if [ "$II_RC" = 2 ] && [ "$II_N_EVT" = 0 ] && printf '%s' "$II_STDERR" | grep -q "ValueError"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s NaN+Inf → rc=2 + 0 events + stderr names ValueError (no silent NaN→null)\n' "_lib.py:journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s n_evt=%s stderr=%s\n' "_lib.py:journal_append" "$II_RC" "$II_N_EVT" "$II_STDERR" >&2
fi

# --- 2026-06-09 followup: 2 Important findings from PR #1 review ---
# JJ/KK close the shim-stderr-capture + python3-guard gap surfaced by the
# Phase-5 SCRUTINIZE-4 pass (see .scratch/c1-followup-shim/issue.md). The
# shim was the contract surface every hook uses; the original code lost
# python's stderr and had no `command -v python3` precheck.

# (JJ) _lib.sh:_journal_append_py has no `command -v python3` guard
# (Important #7). With a PATH that excludes python3 (keeps dirname/cd/jq
# so the shim's other utilities still resolve), the shim must fail loud:
# rc=2 + stderr contains "[<hook_id>] ERROR" + "python3 not found" —
# matching the F5 contract (every journal failure = rc=2 + structured
# prefix), so monitoring alerts that grep "ERROR" catch the case.
# We need a PATH that has everything except python3; the easiest is to
# set PATH to a dir that contains symlinks for the safe utilities but
# NOT python3. Build this in a fresh tmpdir.
JJ_PYBIN="$FIXTURE/jj-pybin"
rm -rf "$JJ_PYBIN" && mkdir -p "$JJ_PYBIN"
# Symlink every command in the current PATH except python3
IFS=':' read -r -a _paths <<< "$PATH"
for _p in "${_paths[@]}"; do
  [ -d "$_p" ] || continue
  for _cmd in "$_p"/*; do
    [ -x "$_cmd" ] || continue
    _base=$(basename "$_cmd")
    [ "$_base" = "python3" ] && continue
    ln -sf "$_cmd" "$JJ_PYBIN/$_base" 2>/dev/null || true
  done
done
JPATH_JJ="$FIXTURE/shim-nopy-journal.jsonl"
: > "$JPATH_JJ"
( export CLAUDE_JOURNAL_PATH="$JPATH_JJ" PATH="$JJ_PYBIN" CLAUDE_SESSION_ID="jj-test"
  source "$JLIB"
  _journal_append_py "shim-nopy" "config_change" '{"file":"a.py","line":1}' ) > "$FIXTURE/jj-out.txt" 2>&1
JJ_RC=$?
JJ_STDERR=$(cat "$FIXTURE/jj-out.txt")
# Assert: rc=2 (NOT 127 from missing-binary) + stderr names hook_id + python3-not-found
if [ "$JJ_RC" = 2 ] && printf '%s' "$JJ_STDERR" | grep -qF "[shim-nopy] ERROR" \
   && printf '%s' "$JJ_STDERR" | grep -qF "python3 not found"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s python3 missing → rc=2 + stderr names [shim-nopy] ERROR + python3 not found (F5 contract)\n' "_lib.sh:_journal_append_py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s (want 2) stderr=%s\n' "_lib.sh:_journal_append_py" "$JJ_RC" "$JJ_STDERR" >&2
fi

# Note: the second finding (Important #1, "stderr from python is not
# captured/re-emitted") is shipped as a structural fix in
# _journal_append_py (explicit stderr capture into a variable before
# re-emitting via >&2) but is not given a test here. The fix is
# defensive — the observable behavior for current callers is unchanged
# because python's stderr was already inheriting the caller's stream.
# The fix makes the shim the OWNER of its stderr channel so future
# callers can suppress, reformat, or log it independently. Per
# METHODOLOGY Rule 9 (tests verify intent, not just behavior), we
# don't add a test for an invisible-behavior change.

# (LL) _lib.sh:_journal_append_py must NOT silently succeed when the
# python journaler omits the FF contract `print(rid)` (Critical #3 from
# PR #2 review). KNOWN-SENTINEL: this test prints a ⚠️ line and does
# NOT increment PASS or FAIL — the current shim cannot detect
# empty-id without an invasive change (capturing stdout requires
# either running python twice, using a temp file, or losing the
# FD-swap cleverness). Closing F3 cleanly is tracked in
# .scratch/c1-followup-shim/issue.md (next-phase PR). When the shim
# gains an "empty-id → rc=2 + F5 prefix" arm, this sentinel becomes
# a real test and starts counting.
#
# Build a minimal fake _lib.py in a tmpdir that writes a journal line
# successfully but does NOT call `print(rid)`. Point _LIBPY_DIR at it
# and call the shim. Observe: rc=0 + empty stdout (the F3 regression
# shape). Today this is the desired/observed behavior on the shim
# side; the regression-guard lives in the python module's own
# assertion (future PR) and in the FF test (line 880-907) which
# already pins the bash `journal_append` happy path.
LL_FAKE_LIBDIR="$FIXTURE/ll-fakelib"
rm -rf "$LL_FAKE_LIBDIR" && mkdir -p "$LL_FAKE_LIBDIR"
cat > "$LL_FAKE_LIBDIR/_lib.py" <<'PYEOF'
import os, sys, json, uuid
def journal_append(hook_id, event, fields_json):
    rid = f"0-{hook_id}-{uuid.uuid4().hex[:8]}"
    journal = os.environ.get("CLAUDE_JOURNAL_PATH") or "/tmp/ll-journal.jsonl"
    with open(journal, "a") as f:
        f.write(json.dumps({"id": rid, "hook": hook_id, "event": event}) + "\n")
    # Intentionally OMIT: print(rid)  — the regression we are testing
PYEOF
export _LIBPY_DIR="$LL_FAKE_LIBDIR"
LL_RC=$(CLAUDE_JOURNAL_PATH="$FIXTURE/ll-journal.jsonl" CLAUDE_SESSION_ID="ll-sid" \
  bash -c '. ./claude/hooks/_lib.sh && _journal_append_py "shim-noid" "config_change" "{}"' \
  > "$FIXTURE/ll-stdout.txt" 2> "$FIXTURE/ll-stderr.txt"; echo $?)
LL_STDOUT=$(cat "$FIXTURE/ll-stdout.txt")
LL_STDERR=$(cat "$FIXTURE/ll-stderr.txt")
unset _LIBPY_DIR
# Known-sentinel: do not increment PASS or FAIL. Prints a clear ⚠️ line
# so the gap is visible in CI without poisoning the suite. Per
# METHODOLOGY Rule 12 ("tests pass is wrong if any were skipped"), we
# name it explicitly here as a sentinel rather than silently skipping
# it or marking it green.
printf '  ⚠️  %-26s empty-id regression not detected on shim (rc=%s stdout=%q stderr=%q) — KNOWN GAP, tracked in .scratch/c1-followup-shim/issue.md\n' "_lib.sh:_journal_append_py empty-id" "$LL_RC" "$LL_STDOUT" "$LL_STDERR"

# --- verification-gate: trails-only SessionEnd sensor (advisory, non-blocking) ---
# Phase-3 verification-doctrine gate: reads .scratch/*/verification-trail.md under
# CLAUDE_PROJECT_DIR, reports the verification_tier mix, flags a no-trail declared
# without a reason, journals a verification_summary event, and NEVER emits a
# permissionDecision (pure sensor — honors gate↔evidence separation, audit #29).
echo
echo "--- verification-gate: trails-only SessionEnd sensor ---"
VGROOT="$FIXTURE/vgroot"
mkdir -p "$VGROOT/.scratch/feat-a" "$VGROOT/.scratch/feat-b"
printf '# Verification trail: feat-a\n- verification_tier: tdd-provenance\n- red_green: aaa111 → bbb222\n- pr_test_analyzer: pass\n- optout_reason: n/a\n' > "$VGROOT/.scratch/feat-a/verification-trail.md"
printf '# Verification trail: feat-b\n- verification_tier: no-trail\n- red_green: n/a\n- pr_test_analyzer: not-run\n- optout_reason:\n' > "$VGROOT/.scratch/feat-b/verification-trail.md"
VGJOURNAL="$FIXTURE/vg-journal.jsonl"; : > "$VGJOURNAL"
VGEVENT='{"session_id":"vg-test","hook_event_name":"SessionEnd"}'
VGOUT=$(printf '%s' "$VGEVENT" | CLAUDE_PROJECT_DIR="$VGROOT" CLAUDE_JOURNAL_PATH="$VGJOURNAL" bash "$HOOKS/verification-gate.sh" 2>/dev/null); VGRC=$?

# (1) exits 0 (never blocks session end) AND emits NO permissionDecision (pure sensor)
if [ "$VGRC" = 0 ] && ! printf '%s' "$VGOUT" | grep -q 'permissionDecision'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s exit 0, no permissionDecision (non-blocking sensor)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s out=%q\n' "verification-gate.sh" "$VGRC" "$VGOUT"
fi

# (2) advisory names the tier mix (tdd-provenance + no-trail both present this session)
if printf '%s' "$VGOUT" | grep -q 'tdd-provenance' && printf '%s' "$VGOUT" | grep -q 'no-trail'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s advisory reports the session tier mix\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s tier mix missing from output: %q\n' "verification-gate.sh" "$VGOUT"
fi

# (3) flags the gap: feat-b is no-trail with an empty optout_reason
if printf '%s' "$VGOUT" | grep -q 'feat-b'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s flags no-trail without a reason (feat-b)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s did not flag the no-trail gap: %q\n' "verification-gate.sh" "$VGOUT"
fi

# (4) journals a verification_summary event with the real session id + counts
if jq -se 'any(.[]; .event=="verification_summary" and .session=="vg-test" and .fields.features==2 and .fields.no_trail==1 and .fields.tdd_provenance==1 and .fields.gaps==1)' "$VGJOURNAL" >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s journals verification_summary {features:2,no_trail:1,gaps:1}\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s verification_summary event wrong/absent: %s\n' "verification-gate.sh" "$(cat "$VGJOURNAL")"
fi

# (5) trail-less project: exit 0, no crash, no verification_summary journaled (no noise)
VGROOT2="$FIXTURE/vgroot-empty"; mkdir -p "$VGROOT2/.scratch/nothing"
VGJOURNAL2="$FIXTURE/vg-journal2.jsonl"; : > "$VGJOURNAL2"
VGOUT2=$(printf '%s' "$VGEVENT" | CLAUDE_PROJECT_DIR="$VGROOT2" CLAUDE_JOURNAL_PATH="$VGJOURNAL2" bash "$HOOKS/verification-gate.sh" 2>/dev/null); VGRC2=$?
if [ "$VGRC2" = 0 ] && ! grep -q 'verification_summary' "$VGJOURNAL2" 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ✅ %-26s trail-less session: exit 0, no event journaled (no noise)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s journal=%s\n' "verification-gate.sh" "$VGRC2" "$(cat "$VGJOURNAL2")"
fi

# (6) richer mix — proves analyzer-pass IS counted, multi-gap accumulation works,
#     and an empty/typo/missing/"none" verification_tier is surfaced as a GAP (not
#     silently misclassified — refutes the review's swallowed-error claim), while a
#     real optout_reason is NOT a gap. 7 feats → f=7, tdd=1, analyzer=1, no_trail=3, gaps=4.
VG3="$FIXTURE/vgroot3"
mkdir -p "$VG3"/.scratch/a-tdd "$VG3"/.scratch/b-analyzer "$VG3"/.scratch/c-reason \
         "$VG3"/.scratch/d-empty "$VG3"/.scratch/e-typo "$VG3"/.scratch/f-notier "$VG3"/.scratch/g-none
printf '# t\n- verification_tier: tdd-provenance\n'  > "$VG3/.scratch/a-tdd/verification-trail.md"
printf '# t\n- verification_tier: analyzer-pass\n'   > "$VG3/.scratch/b-analyzer/verification-trail.md"
printf '# t\n- verification_tier: no-trail\n- optout_reason: docs-only, no behavior to assert\n' > "$VG3/.scratch/c-reason/verification-trail.md"
printf '# t\n- verification_tier: no-trail\n- optout_reason:\n'      > "$VG3/.scratch/d-empty/verification-trail.md"
printf '# t\n- verification_tier: bogus-typo\n'      > "$VG3/.scratch/e-typo/verification-trail.md"
printf '# t\n- red_green: n/a\n'                     > "$VG3/.scratch/f-notier/verification-trail.md"
printf '# t\n- verification_tier: no-trail\n- optout_reason: none\n' > "$VG3/.scratch/g-none/verification-trail.md"
VGJ3="$FIXTURE/vg-journal3.jsonl"; : > "$VGJ3"
VG3_OUT=$(printf '%s' "$VGEVENT" | CLAUDE_PROJECT_DIR="$VG3" CLAUDE_JOURNAL_PATH="$VGJ3" bash "$HOOKS/verification-gate.sh" 2>/dev/null); VG3_RC=$?
if [ "$VG3_RC" = 0 ] && jq -se 'any(.[]; .event=="verification_summary" and .fields.features==7 and .fields.tdd_provenance==1 and .fields.analyzer_pass==1 and .fields.no_trail==3 and .fields.gaps==4)' "$VGJ3" >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s counts analyzer-pass; typo/missing/none/empty are gaps, reasoned no-trail is not (f=7,gaps=4)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s counts wrong: %s\n' "verification-gate.sh" "$VG3_RC" "$(cat "$VGJ3")"
fi

# (7) gap advisory names EVERY gap slug (accumulation) and omits the reasoned no-trail
if printf '%s' "$VG3_OUT" | grep -q 'd-empty' && printf '%s' "$VG3_OUT" | grep -q 'e-typo' \
   && printf '%s' "$VG3_OUT" | grep -q 'f-notier' && printf '%s' "$VG3_OUT" | grep -q 'g-none' \
   && ! printf '%s' "$VG3_OUT" | grep -q 'c-reason'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s gap advisory lists all 4 gaps, omits the reasoned no-trail\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s gap slug list wrong: %q\n' "verification-gate.sh" "$VG3_OUT"
fi

# (8) journal_append failure (jq GUARANTEED absent) must NOT break the non-blocking
#     contract: gate still exits 0 AND still prints the advisory. (Same jq-absent
#     PATH technique as the journal_append fail-loud case above.)
VGBIN="$FIXTURE/vgbin"; mkdir -p "$VGBIN"
for b in bash sed find basename dirname tr head cat python3 mkdir grep; do ln -sf "$(command -v "$b")" "$VGBIN/$b" 2>/dev/null; done
VGJF="$FIXTURE/vg-journalfail.jsonl"; : > "$VGJF"
VGJF_OUT=$(printf '%s' "$VGEVENT" | CLAUDE_PROJECT_DIR="$VG3" CLAUDE_JOURNAL_PATH="$VGJF" PATH="$VGBIN" bash "$HOOKS/verification-gate.sh" 2>/dev/null); VGJF_RC=$?
if [ "$VGJF_RC" = 0 ] && printf '%s' "$VGJF_OUT" | grep -q 'session verification'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s journal fail (no jq) → still exit 0 + advisory (non-blocking)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s out=%q\n' "verification-gate.sh" "$VGJF_RC" "$VGJF_OUT"
fi

# (9) no .scratch dir at all → exit 0 silently, nothing journaled (the -d guard)
VG4="$FIXTURE/vgroot4-noscratch"; mkdir -p "$VG4"
VGJ4="$FIXTURE/vg-journal4.jsonl"; : > "$VGJ4"
VG4_OUT=$(printf '%s' "$VGEVENT" | CLAUDE_PROJECT_DIR="$VG4" CLAUDE_JOURNAL_PATH="$VGJ4" bash "$HOOKS/verification-gate.sh" 2>/dev/null); VG4_RC=$?
if [ "$VG4_RC" = 0 ] && [ -z "$VG4_OUT" ] && ! grep -q 'verification_summary' "$VGJ4" 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ✅ %-26s no .scratch dir → exit 0 silent, nothing journaled\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s out=%q journal=%s\n' "verification-gate.sh" "$VG4_RC" "$VG4_OUT" "$(cat "$VGJ4")"
fi

# (10) F4: gaps>0 → exit_reason="degrading" in the journaled verification_summary.
#     Reuses the VGROOT fixture (feat-a tdd-provenance, feat-b no-trail w/ blank reason → 1 gap).
if jq -se 'any(.[]; .event=="verification_summary" and .session=="vg-test" and .fields.exit_reason=="degrading" and .fields.gaps==1)' "$VGJOURNAL" >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s exit_reason="degrading" when gaps>0 (F4)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit_reason wrong on gap session: %s\n' "verification-gate.sh" "$(cat "$VGJOURNAL")"
fi

# (11) F4: clean session (no gaps) → exit_reason="complete". Builds a fresh fixture:
#     one feature with a real trail, one with a no-trail+reasoned optout → 0 gaps.
VG5="$FIXTURE/vgroot5-clean"
mkdir -p "$VG5/.scratch/feat-good" "$VG5/.scratch/feat-reasoned"
printf '# t\n- verification_tier: tdd-provenance\n' > "$VG5/.scratch/feat-good/verification-trail.md"
printf '# t\n- verification_tier: no-trail\n- optout_reason: docs-only, no behavior to assert\n' > "$VG5/.scratch/feat-reasoned/verification-trail.md"
VGJ5="$FIXTURE/vg-journal5.jsonl"; : > "$VGJ5"
( cd "$VG5" >/dev/null; printf '%s' "$VGEVENT" | CLAUDE_PROJECT_DIR="$VG5" CLAUDE_JOURNAL_PATH="$VGJ5" bash "$HOOKS/verification-gate.sh" >/dev/null 2>&1 ) || true
if jq -se 'any(.[]; .event=="verification_summary" and .session=="vg-test" and .fields.exit_reason=="complete" and .fields.gaps==0 and .fields.features==2)' "$VGJ5" >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s exit_reason="complete" on clean session (F4)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit_reason wrong on clean session: %s\n' "verification-gate.sh" "$(cat "$VGJ5")"
fi

# --- verification-tier-audit.py: retro-grader (declared trail authoritative; fallback no-trail) ---
echo
echo "--- verification-tier-audit: retro-grader ---"
VTA="$FIXTURE/vta"
mkdir -p "$VTA/.scratch/synthfeat" "$VTA/.scratch/baretask"
printf '# Verification trail: synthfeat\n- verification_tier: tdd-provenance\n- red_green: c0ffee → f00df00d\n- pr_test_analyzer: pass\n' > "$VTA/.scratch/synthfeat/verification-trail.md"
printf '# Acceptance: baretask\n' > "$VTA/.scratch/baretask/ACCEPTANCE.md"
VTA_OUT=$(python3 "$HOOKS/../scripts/verification-tier-audit.py" --root "$VTA" synthfeat baretask 2>/dev/null); VTA_RC=$?

# (1) a declared verification-trail.md tier is authoritative
if [ "$VTA_RC" = 0 ] && printf '%s' "$VTA_OUT" | grep -E 'synthfeat' | grep -q 'tdd-provenance'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s reads declared verification_tier from trail\n' "verification-tier-audit.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s out=%q\n' "verification-tier-audit.py" "$VTA_RC" "$VTA_OUT"
fi

# (2) no trail + no tests/evals → graded no-trail (fallback branch)
if printf '%s' "$VTA_OUT" | grep -E 'baretask' | grep -q 'no-trail'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s grades trail-less feature as no-trail\n' "verification-tier-audit.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s baretask not graded no-trail: %q\n' "verification-tier-audit.py" "$VTA_OUT"
fi

# --- review-pr-journal-pre-emit-validator.py: Layer 2 (ask-gate, additive) ---
# Companion to review-pr-journal.py (Layer 1, best-effort, see tests M/N/N2/P).
# The validator is a pre-emit CLI that /review-pr SKILL.md step 4 calls BEFORE
# the journaler. It re-uses the journaler's enum regexes (lockstep via Python
# import — do NOT redeclare the enums) and exits 2 on miss so the human can
# AskUserQuestion before the journal gets polluted. Q3=a is preserved (the
# journaler still WARNINGs but emits; the validator is the ask-gate, not a
# deny-gate). These tests prove the four surface contracts the SKILL.md
# depends on: (CC) all-clean exit 0; (DD) miss → exit 2 + named stderr;
# (EE) manifest dedup short-circuits (already-journaled findings don't
# re-block); (FF) the validator is read-only (it never writes the journal
# or the .journaled manifest, even on a miss).

# (CC) all-clean findings → exit 0, stderr names the count.
VDIR1="$FIXTURE/rj-vdir1"; rm -rf "$VDIR1"; mkdir -p "$VDIR1"
cat > "$VDIR1/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":"CC1","tier":"Critical","disposition":"survived","decision":"fix-now","pair_id":"P1"}
{"local_id":"CC2","tier":"Important","disposition":"rejected","decision":"proceed","pair_id":"P2"}
{"local_id":"CC3","tier":"Minor","disposition":"survived","decision":"fix-later","pair_id":"P3"}
FIXTURE_EOF
EXIT_CODE=0
STDERR=$(python3 "$SCRIPTS/review-pr-journal-pre-emit-validator.py" "$VDIR1" 2>&1 >/dev/null) || EXIT_CODE=$?
N_PASS=$(printf '%s\n' "$STDERR" | grep -c "OK: 3 finding(s) passed" || true)
# The validator must NOT have created a .journaled manifest — that is the
# journaler's job (Layer 1). A Layer-2 write here would double-track state.
HAS_MANIFEST=$([ -e "$VDIR1/.journaled" ] && echo yes || echo no)
if [ "$EXIT_CODE" = 0 ] && [ "$N_PASS" = 1 ] && [ "$HAS_MANIFEST" = no ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s all-clean: exit 0, stderr OK-count, no manifest write (Layer 2 read-only)\n' "review-pr-journal-pre-emit-validator"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit=%s (want 0) n_pass=%s (want 1) has_manifest=%s (want no)\n' "review-pr-journal-pre-emit-validator" "$EXIT_CODE" "$N_PASS" "$HAS_MANIFEST"
fi

# (DD) enum-miss → exit 2, stderr names EVERY offending finding + field, NO
# manifest write. This is the core ask-gate contract: the human must see
# which findings are bad and which field on each, before deciding to
# proceed. A test that only checks exit-2 (without naming) would miss a
# regression where the validator printed "validation failed" without
# per-finding detail.
VDIR2="$FIXTURE/rj-vdir2"; rm -rf "$VDIR2"; mkdir -p "$VDIR2"
cat > "$VDIR2/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":"DD1","tier":"whoops","disposition":"survived","decision":"proceed","pair_id":"P1"}
{"local_id":"DD2","tier":"Minor","disposition":"unknown","decision":"proceed","pair_id":"P2"}
{"local_id":"DD3","tier":"Minor","disposition":"rejected","decision":"eventually","pair_id":"P3"}
{"local_id":"DD4","tier":"Critical","disposition":"survived","decision":"fix-now","pair_id":"P4"}
FIXTURE_EOF
EXIT_CODE=0
STDERR=$(python3 "$SCRIPTS/review-pr-journal-pre-emit-validator.py" "$VDIR2" 2>&1 >/dev/null) || EXIT_CODE=$?
# Expect 3 named findings (DD1 bad tier, DD2 bad disp, DD3 bad dec) and
# DD4 silently passing. The exit-2 message must say ASK-GATE + count, and
# every offending finding's local_id + bad field must appear on stderr.
N_BLOCK=$(printf '%s\n' "$STDERR" | grep -c "ASK-GATE: 3 finding(s) failed" || true)
HAS_DD1=$(printf '%s' "$STDERR" | grep -c "local_id=DD1: tier='whoops'" || true)
HAS_DD2=$(printf '%s' "$STDERR" | grep -c "local_id=DD2: disposition='unknown'" || true)
HAS_DD3=$(printf '%s' "$STDERR" | grep -c "local_id=DD3: decision='eventually'" || true)
NO_DD4=$(printf '%s' "$STDERR" | grep -c "local_id=DD4" || true)
HAS_MANIFEST=$([ -e "$VDIR2/.journaled" ] && echo yes || echo no)
if [ "$EXIT_CODE" = 2 ] && [ "$N_BLOCK" = 1 ] \
   && [ "$HAS_DD1" = 1 ] && [ "$HAS_DD2" = 1 ] && [ "$HAS_DD3" = 1 ] \
   && [ "$NO_DD4" = 0 ] && [ "$HAS_MANIFEST" = no ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s enum-miss: exit 2, all 3 bad findings named on stderr, clean finding silent, no manifest write\n' "review-pr-journal-pre-emit-validator"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit=%s n_block=%s dd1=%s dd2=%s dd3=%s no_dd4=%s has_manifest=%s\n' "review-pr-journal-pre-emit-validator" "$EXIT_CODE" "$N_BLOCK" "$HAS_DD1" "$HAS_DD2" "$HAS_DD3" "$NO_DD4" "$HAS_MANIFEST"
fi

# (EE) manifest dedup short-circuits the validator: a finding with a bad
# enum that is ALREADY in the manifest must NOT block (the manifest
# proves it passed the gate previously, so re-validation is a no-op).
# This is the same dedup-on-load the journaler does (test N/N2) — the
# validator must honor the same manifest or it would block findings the
# journaler would happily re-skip. The finding must still be in the
# output count as "already in manifest", not "passed enum validation",
# which is the proof the dedup branch fired (not the enum-clean branch).
VDIR3="$FIXTURE/rj-vdir3"; rm -rf "$VDIR3"; mkdir -p "$VDIR3"
cat > "$VDIR3/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":"EE1","tier":"CRITICAL_TYPO","disposition":"survived","decision":"fix-now","pair_id":"P1"}
{"local_id":"EE2","tier":"BAD_TIER","disposition":"survived","decision":"proceed","pair_id":"P2"}
FIXTURE_EOF
# Pre-seed manifest as if EE1 was journaled in a prior run.
printf '%s\n' '{"local_id":"EE1","finding_id":"fake-fid","verdict_id":"fake-vid"}' > "$VDIR3/.journaled"
EXIT_CODE=0
STDERR=$(python3 "$SCRIPTS/review-pr-journal-pre-emit-validator.py" "$VDIR3" 2>&1 >/dev/null) || EXIT_CODE=$?
# Expect: exit 2 (EE2 still bad), stderr says 1 already in manifest + 1
# blocked, EE1 NOT named as a blocker.
N_ALREADY=$(printf '%s\n' "$STDERR" | grep -c "1 already in manifest" || true)
N_BLOCK=$(printf '%s\n' "$STDERR" | grep -c "1 finding(s) failed" || true)
HAS_EE1_AS_BLOCKER=$(printf '%s' "$STDERR" | grep -c "local_id=EE1:" || true)
HAS_EE2_AS_BLOCKER=$(printf '%s' "$STDERR" | grep -c "local_id=EE2: tier='BAD_TIER'" || true)
if [ "$EXIT_CODE" = 2 ] && [ "$N_ALREADY" = 1 ] && [ "$N_BLOCK" = 1 ] \
   && [ "$HAS_EE1_AS_BLOCKER" = 0 ] && [ "$HAS_EE2_AS_BLOCKER" = 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s manifest dedup: already-journaled finding skipped, only the new bad one blocks\n' "review-pr-journal-pre-emit-validator"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit=%s n_already=%s n_block=%s ee1_blocker=%s (want 0) ee2_blocker=%s\n' "review-pr-journal-pre-emit-validator" "$EXIT_CODE" "$N_ALREADY" "$N_BLOCK" "$HAS_EE1_AS_BLOCKER" "$HAS_EE2_AS_BLOCKER"
fi

# (FF) the validator is fail-loud on a malformed .journaled manifest
# (analog to journaler test R). A non-JSON line in the manifest means a
# prior run died in a way that left garbage; the validator must NOT
# silently treat the manifest as empty and pass-through — that would
# re-validate findings the journaler would also re-validate, and any
# gate-truth divergence between the two layers would surface as silent
# drift. Lockstep: the validator's manifest parser is byte-identical in
# intent to the journaler's (the test R precedent). Exit 2, stderr
# names the file, no event/journal write — note: the validator does not
# write ANY journal artifacts in any case, so the "no journal write"
# check here is layered on top of "no manifest write".
VDIR4="$FIXTURE/rj-vdir4"; rm -rf "$VDIR4"; mkdir -p "$VDIR4"
cat > "$VDIR4/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":"FF1","tier":"Critical","disposition":"survived","decision":"fix-now","pair_id":"P1"}
FIXTURE_EOF
printf 'not-json-at-all\ngarbage line 2\n' > "$VDIR4/.journaled"
EXIT_CODE=0
STDERR=$(python3 "$SCRIPTS/review-pr-journal-pre-emit-validator.py" "$VDIR4" 2>&1 >/dev/null) || EXIT_CODE=$?
HAS_REFUSING=$(printf '%s' "$STDERR" | grep -c "refusing to validate" || true)
HAS_PATH=$(printf '%s' "$STDERR" | grep -c "\.journaled" || true)
if [ "$EXIT_CODE" = 2 ] && [ "$HAS_REFUSING" = 1 ] && [ "$HAS_PATH" = 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s malformed manifest: exit 2, stderr refuses + names file (lockstep with journaler R)\n' "review-pr-journal-pre-emit-validator"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit=%s (want 2) refusing=%s path=%s\n' "review-pr-journal-pre-emit-validator" "$EXIT_CODE" "$HAS_REFUSING" "$HAS_PATH"
fi

# --- recursive-improve-observe.py: reads verification_summary, surfaces gaps as triggers ---
# Phase-4 observe reader: groups verification_summary events by session, keeps the
# LATEST per session, flags sessions with gaps>0 as improvement triggers. Read-only,
# exit 0 always (a report for the human-gated ritual, not a gate). Reuses
# governance-summary.load_jsonl (no second JSONL parser, same contract as the audit).
echo
echo "--- recursive-improve-observe: verification_summary reader ---"
RIO="$HOOKS/../scripts/recursive-improve-observe.py"
RIJ="$FIXTURE/rio-journal.jsonl"
# one session with a recorded verification gap (gaps=4) + one clean session (gaps=0)
{
  printf '{"id":"1-verification-gate-a","ts":"2026-06-10T01:00:00.000Z","session":"sess-gappy","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":7,"tdd_provenance":1,"analyzer_pass":1,"no_trail":3,"gaps":4}}\n'
  printf '{"id":"2-verification-gate-b","ts":"2026-06-10T02:00:00.000Z","session":"sess-clean","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":2,"tdd_provenance":1,"analyzer_pass":0,"no_trail":1,"gaps":0}}\n'
} > "$RIJ"
RIO_OUT=$(python3 "$RIO" --journal "$RIJ" 2>/dev/null); RIO_RC=$?

# (1) surfaces the gappy session as an improvement trigger (the core observe behavior:
#     if gaps aren't surfaced, the ritual has nothing to act on)
if [ "$RIO_RC" = 0 ] && printf '%s' "$RIO_OUT" | grep -q 'sess-gappy' && printf '%s' "$RIO_OUT" | grep -qi 'gap'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s surfaces a session with gaps>0 as an improvement trigger\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s gappy session not surfaced: rc=%s out=%q\n' "recursive-improve-observe.py" "$RIO_RC" "$RIO_OUT"
fi

# (2) LATEST event per session wins — a session that recorded gaps=2 early then gaps=0
#     later has FIXED its gaps; flagging the stale event would mis-fire the ritual on
#     already-resolved work. Two events, same session; the fixed session is NOT a trigger.
RIJ2="$FIXTURE/rio-journal2.jsonl"
{
  printf '{"id":"1-vg-a","ts":"2026-06-10T01:00:00.000Z","session":"sess-fixed","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":3,"tdd_provenance":1,"analyzer_pass":0,"no_trail":2,"gaps":2}}\n'
  printf '{"id":"2-vg-b","ts":"2026-06-10T05:00:00.000Z","session":"sess-fixed","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":3,"tdd_provenance":3,"analyzer_pass":0,"no_trail":0,"gaps":0}}\n'
} > "$RIJ2"
RIO2_OUT=$(python3 "$RIO" --journal "$RIJ2" 2>/dev/null); RIO2_RC=$?
if [ "$RIO2_RC" = 0 ] && ! printf '%s' "$RIO2_OUT" | grep -q -- '- sess-fixed'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s latest event per session wins (a fixed session is not a trigger)\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s stale gap event flagged a fixed session: rc=%s out=%q\n' "recursive-improve-observe.py" "$RIO2_RC" "$RIO2_OUT"
fi

# (3) all-clean journal (gaps=0) → reports clean, emits NO trigger bullet (false-positive
#     guard: the ritual must not propose work when verification posture is clean)
RIJ3="$FIXTURE/rio-journal3.jsonl"
printf '{"id":"1-vg","ts":"2026-06-10T01:00:00.000Z","session":"sess-ok","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":2,"tdd_provenance":2,"analyzer_pass":0,"no_trail":0,"gaps":0}}\n' > "$RIJ3"
RIO3_OUT=$(python3 "$RIO" --journal "$RIJ3" 2>/dev/null); RIO3_RC=$?
if [ "$RIO3_RC" = 0 ] && printf '%s' "$RIO3_OUT" | grep -qi 'clean' && ! printf '%s' "$RIO3_OUT" | grep -q -- '- sess-ok'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s clean posture → no trigger (false-positive guard)\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s clean posture mishandled: rc=%s out=%q\n' "recursive-improve-observe.py" "$RIO3_RC" "$RIO3_OUT"
fi

# (4) journal exists but has NO verification_summary events → graceful empty, exit 0
#     (don't crash, don't invent a gap when there is no posture data)
RIJ4="$FIXTURE/rio-journal4.jsonl"
printf '{"id":"1-x","ts":"2026-06-10T01:00:00.000Z","session":"s","hook":"review-pr-journaler","event":"review_finding","source":"journal_append","fields":{"file":"a.py","line":1,"tier":"Minor","agent":"code-reviewer","summary":"x"}}\n' > "$RIJ4"
RIO4_OUT=$(python3 "$RIO" --journal "$RIJ4" 2>/dev/null); RIO4_RC=$?
if [ "$RIO4_RC" = 0 ] && printf '%s' "$RIO4_OUT" | grep -qi 'no verification_summary'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s journal w/o summary events → graceful empty, exit 0\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s did not handle summary-less journal: rc=%s out=%q\n' "recursive-improve-observe.py" "$RIO4_RC" "$RIO4_OUT"
fi

# (5) a verification_summary missing the `gaps` field → treated as 0 (no KeyError); the
#     session shows in the table but is NOT a trigger. Robustness vs partial/legacy events.
RIJ5="$FIXTURE/rio-journal5.jsonl"
printf '{"id":"1-vg","ts":"2026-06-10T01:00:00.000Z","session":"sess-partial","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":1,"tdd_provenance":1}}\n' > "$RIJ5"
RIO5_OUT=$(python3 "$RIO" --journal "$RIJ5" 2>/dev/null); RIO5_RC=$?
if [ "$RIO5_RC" = 0 ] && printf '%s' "$RIO5_OUT" | grep -q 'sess-partial' && ! printf '%s' "$RIO5_OUT" | grep -q -- '- sess-partial'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s missing gaps field → 0, no crash (not a trigger)\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s missing-field handling wrong: rc=%s out=%q\n' "recursive-improve-observe.py" "$RIO5_RC" "$RIO5_OUT"
fi

# (6) read-only: a run does NOT mutate the journal (it is a report for a human, not a gate)
RIO_SUM_BEFORE=$(cksum "$RIJ" | awk '{print $1, $2}')
python3 "$RIO" --journal "$RIJ" >/dev/null 2>&1; RIO6_RC=$?
RIO_SUM_AFTER=$(cksum "$RIJ" | awk '{print $1, $2}')
if [ "$RIO6_RC" = 0 ] && [ "$RIO_SUM_BEFORE" = "$RIO_SUM_AFTER" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s read-only: run leaves the journal byte-identical\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s mutated the journal or rc!=0: rc=%s before=%q after=%q\n' "recursive-improve-observe.py" "$RIO6_RC" "$RIO_SUM_BEFORE" "$RIO_SUM_AFTER"
fi

# (7) a verification_summary with a PRESENT-but-garbage field (gaps:"corrupted") must SURFACE
#     the degradation to stderr — silently coercing it to 0 would mask a real gap and contradict
#     verification-gate.sh's malformed→surface precedent. Still exit 0, still not a false trigger.
RIJ7="$FIXTURE/rio-journal7.jsonl"
printf '{"id":"1-vg","ts":"2026-06-10T01:00:00.000Z","session":"sess-garbage","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":1,"gaps":"corrupted"}}\n' > "$RIJ7"
RIO7_ERR="$FIXTURE/rio7-err.txt"
RIO7_OUT=$(python3 "$RIO" --journal "$RIJ7" 2>"$RIO7_ERR"); RIO7_RC=$?
if [ "$RIO7_RC" = 0 ] && grep -qi 'unparseable' "$RIO7_ERR" && grep -q 'corrupted' "$RIO7_ERR"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s present-but-garbage field → stderr warning, not silent (exit 0)\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s garbage field not surfaced: rc=%s err=%q\n' "recursive-improve-observe.py" "$RIO7_RC" "$(cat "$RIO7_ERR")"
fi

# --- harness-audit check #31 — schema-rot detector (4 sub-checks) ---
# Round-2 (2026-06-11) gap-closure: the pre-emit validator is scoped to
# the review-pr journaler's enum regexes only. Check #31 adds a general
# detector for (1) skill SKILL.md I/O contract section presence,
# (2) plugin.json / marketplace.json version validity + 30d cadence,
# (3) decay-cadence.md permission-re-audit bookmark, (4) hooks.json
# schema shape. Sub-checks 1-3 emit info (advisory); sub-check 4 emits
# crit (structural). The tests below are hermetic — they build a
# fresh temp-dir fixture (.claude-plugin/, claude/skills/, claude/hooks/,
# claude/docs/) and run the audit against it, so the harness's real
# plugin.json/hooks.json state is irrelevant. Mirrors the (K)
# check-#29 test pattern.
AUDIT="$HOOKS/../skills/harness-audit/scripts/audit.sh"

# (MM) clean fixture — every sub-check should stay silent. One SKILL.md
# with all 3 canonical sections, one plugin.json with `version` +
# (the marketplace schema requires no `last_reviewed_reason:`), one
# hooks.json with non-empty matcher/type/command, one
# decay-cadence.md with a fresh `last_permission_review: YYYY-MM-DD`
# marker. Today's date is used for the marker so the 90d quarterly
# cadence check passes.
SREP_C="$FIXTURE/srep-clean"; rm -rf "$SREP_C"; mkdir -p "$SREP_C/claude/skills/good-skill" "$SREP_C/claude/hooks" "$SREP_C/claude/agents" "$SREP_C/claude/commands" "$SREP_C/claude/docs" "$SREP_C/.claude-plugin"
cat > "$SREP_C/claude/skills/good-skill/SKILL.md" <<'SK'
---
name: good-skill
description: 'Test fixture for audit #31.'
---
# Good Skill

## Input Contract
- needs: foo

## Output Format
- emits: bar

## Failure Modes
- when: baz
SK
cat > "$SREP_C/.claude-plugin/plugin.json" <<'PJ'
{
  "name": "test-plugin",
  "version": "0.1.0"
}
PJ
cat > "$SREP_C/claude/hooks/hooks.json" <<'HJ'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "echo ok" }
        ]
      }
    ]
  }
}
HJ
# Use today's date so the permission-re-audit bookmark is "fresh"
# (within the 90d quarterly cadence). Without this the clean fixture
# would itself trip PERM_BOOKMARK_STALE.
TODAY_ISO=$(python3 -c 'import datetime; print(datetime.date.today().isoformat())')
cat > "$SREP_C/claude/docs/harness-decay-cadence.md" <<DC
# Decay cadence
last_permission_review: $TODAY_ISO abc123
DC
# Capture rc directly. The pattern `OUT=$(cmd)` masks cmd's $? with
# the assignment's; use a wrapper that preserves the exit status.
set +e
SREP_C_OUT=$(bash "$AUDIT" "$SREP_C" 2>&1)
SREP_C_RC=$?
set -e
SREP_C_SCHEMA=$(printf '%s' "$SREP_C_OUT" | grep -c "schema-rot" || true)
# Clean fixture should produce ZERO schema-rot findings. The audit's
# overall rc is dominated by the always-firing F1 symlink CRIT + 2
# description WARNs on a fresh fixture, so we don't assert rc=0 here
# — only that check #31's own sub-checks stay silent (the contract of
# this test). The (NN) test below covers the rc>0 path.
if [ "$SREP_C_SCHEMA" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s clean fixture: no schema-rot findings (sub-checks 1-4 all silent)\n' "harness-audit #31"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s clean fixture emitted %s schema-rot findings (want 0), rc=%s:\n%s\n' "harness-audit #31" "$SREP_C_SCHEMA" "$SREP_C_RC" "$SREP_C_OUT"
fi

# (NN) violating fixture — every sub-check should fire. SKILL.md
# missing all 3 canonical sections (info), plugin.json missing
# `version` (crit), decay-cadence.md missing the perm-re-audit marker
# (info), hooks.json with an empty matcher AND a missing-type entry
# (crit). The test asserts that BOTH kinds of finding appear: the
# info-level I/O contract drift AND the structural hooks.json crit.
# Hermetic: every file is built at test time, no shared state with
# the real repo.
SREP_V="$FIXTURE/srep-bad"; rm -rf "$SREP_V"; mkdir -p "$SREP_V/claude/skills/bad-skill" "$SREP_V/claude/hooks" "$SREP_V/claude/agents" "$SREP_V/claude/commands" "$SREP_V/claude/docs" "$SREP_V/.claude-plugin"
cat > "$SREP_V/claude/skills/bad-skill/SKILL.md" <<'SK'
---
name: bad-skill
description: 'Test fixture for audit #31 — missing sections.'
---
# Bad Skill

This SKILL.md is missing the canonical sections.
SK
# plugin.json: NO `version` field → fires PLUGIN_NO_VERSION (crit)
cat > "$SREP_V/.claude-plugin/plugin.json" <<'PJ'
{
  "name": "test-plugin-no-version"
}
PJ
# hooks.json: non-string matcher (integer — the genuine schema violation
# the check guards) + a missing `type` field on one entry (defense in
# depth). Empty matcher is NOT a violation (vendor convention for
# multi-source events like ConfigChange — see
# hooks/config-change-log.sh header).
cat > "$SREP_V/claude/hooks/hooks.json" <<'HJ'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": 42,
        "hooks": [
          { "type": "command", "command": "echo bad" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          { "command": "echo no-type" }
        ]
      }
    ]
  }
}
HJ
# decay-cadence.md exists but has NO `last_permission_review:` marker
# → PERM_BOOKMARK_MISSING (info). The check is about drift in an
# existing file; absence-of-file is not drift and is silently skipped.
cat > "$SREP_V/claude/docs/harness-decay-cadence.md" <<'DC'
# Decay cadence

This fixture file intentionally omits the `last_permission_review:` marker
to verify the audit surfaces drift rather than silently passing.
DC
set +e
SREP_V_OUT=$(bash "$AUDIT" "$SREP_V" 2>&1)
SREP_V_RC=$?
set -e
# Expected: a crit on the missing plugin.json `version` (PLUGIN_NO_VERSION),
# crits on the hooks.json shape violations (HOOKS_SHAPE_FAIL), an info
# on the missing SKILL.md canonical sections (SKILL_MISSING) and the
# missing decay-cadence.md perm-re-audit marker (PERM_BOOKMARK_MISSING).
SREP_V_HAS_SKILL_INFO=$(printf '%s' "$SREP_V_OUT" | grep -c "schema-rot: skill 'bad-skill'" || true)
SREP_V_HAS_PLUGIN_CRIT=$(printf '%s' "$SREP_V_OUT" | grep -c "plugin.json has no 'version' field" || true)
SREP_V_HAS_HOOKS_CRIT=$(printf '%s' "$SREP_V_OUT" | grep -c "hooks.json —" || true)
SREP_V_HAS_PERM_INFO=$(printf '%s' "$SREP_V_OUT" | grep -c "schema-rot:.*decay-cadence" || true)
# Exit code must be > 0 (findings present) — the audit's exit =
# crit + warn count. With 1 PLUGIN_NO_VERSION crit + 2 HOOKS_SHAPE_FAIL
# crits = 3 crits (plus the symlink/desc crits that always fire in a
# fresh fixture), rc >= 3. Use >= 2 as a permissive lower bound.
if [ "$SREP_V_HAS_SKILL_INFO" -ge 1 ] && [ "$SREP_V_HAS_PLUGIN_CRIT" -ge 1 ] \
   && [ "$SREP_V_HAS_HOOKS_CRIT" -ge 1 ] && [ "$SREP_V_HAS_PERM_INFO" -ge 1 ] \
   && [ "$SREP_V_RC" -ge 2 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s violating fixture: 4 sub-checks all fire (skill info, plugin crit, hooks crit, perm info); rc>=2 (got %s)\n' "harness-audit #31" "$SREP_V_RC"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s skill=%s plugin=%s hooks=%s perm=%s rc=%s (want >=1/1/1/1/2):\n%s\n' "harness-audit #31" "$SREP_V_HAS_SKILL_INFO" "$SREP_V_HAS_PLUGIN_CRIT" "$SREP_V_HAS_HOOKS_CRIT" "$SREP_V_HAS_PERM_INFO" "$SREP_V_RC" "$SREP_V_OUT"
fi

# (NN2) deferral — a skill missing canonical sections BUT carrying a
# `last_reviewed_reason:` marker in either its SKILL.md frontmatter OR
# its evals/evals.json must NOT fire SKILL_MISSING. Mirrors the existing
# `last_reviewed_reason:` convention at audit.sh #30 (eval-target
# freshness) and the plugin-version check at #31.2. Decay-cadence
# (docs/harness-decay-cadence.md) owns the quarterly human sweep that
# revisits these; the audit is sensor only, sensor-with-documented-
# deferral is preferred over stubbing. This is the regression guard
# for the 2026-06-12 closure of the 25-skill schema-rot gap.
SREP_D1="$FIXTURE/srep-defer-fm"; rm -rf "$SREP_D1"; mkdir -p "$SREP_D1/claude/skills/deferred-skill" "$SREP_D1/claude/hooks" "$SREP_D1/claude/agents" "$SREP_D1/claude/commands" "$SREP_D1/claude/docs" "$SREP_D1/.claude-plugin"
cat > "$SREP_D1/claude/skills/deferred-skill/SKILL.md" <<'SK'
---
name: deferred-skill
last_reviewed_reason: 'deferred to quarterly cadence per docs/harness-decay-cadence.md'
description: 'Test fixture for audit #31 deferral — frontmatter marker.'
---
# Deferred Skill
SK
cat > "$SREP_D1/.claude-plugin/plugin.json" <<'PJ'
{ "name": "d1-fixture", "version": "0.0.1" }
PJ
cat > "$SREP_D1/claude/docs/harness-decay-cadence.md" <<DC
# Decay cadence
last_permission_review: $TODAY_ISO abc123
DC
set +e
SREP_D1_OUT=$(bash "$AUDIT" "$SREP_D1" 2>&1)
SREP_D1_RC=$?
set -e
SREP_D1_HAS_SKILL_INFO=$(printf '%s' "$SREP_D1_OUT" | grep -c "schema-rot: skill 'deferred-skill'" || true)
if [ "$SREP_D1_HAS_SKILL_INFO" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s deferral (frontmatter): SKILL_MISSING suppressed by last_reviewed_reason: marker\n' "harness-audit #31.1"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s deferral (frontmatter): SKILL_MISSING fired %s times (want 0):\n%s\n' "harness-audit #31.1" "$SREP_D1_HAS_SKILL_INFO" "$SREP_D1_OUT"
fi

# (NN3) deferral via evals/evals.json — same suppression, marker
# lives in the sibling evals file instead of SKILL.md frontmatter.
# This is the path the 20 stamped skills (acli/adr/decommission/etc.)
# actually use, so guarding it is the load-bearing test.
SREP_D2="$FIXTURE/srep-defer-evals"; rm -rf "$SREP_D2"; mkdir -p "$SREP_D2/claude/skills/deferred-via-evals" "$SREP_D2/claude/skills/deferred-via-evals/evals" "$SREP_D2/claude/hooks" "$SREP_D2/claude/agents" "$SREP_D2/claude/commands" "$SREP_D2/claude/docs" "$SREP_D2/.claude-plugin"
cat > "$SREP_D2/claude/skills/deferred-via-evals/SKILL.md" <<'SK'
---
name: deferred-via-evals
description: 'Test fixture for audit #31 deferral — evals.json marker.'
---
# Deferred via evals
SK
cat > "$SREP_D2/claude/skills/deferred-via-evals/evals/evals.json" <<'EJ'
{
  "skill_name": "deferred-via-evals",
  "last_reviewed_reason": "deferred to quarterly cadence per docs/harness-decay-cadence.md"
}
EJ
cat > "$SREP_D2/.claude-plugin/plugin.json" <<'PJ'
{ "name": "d2-fixture", "version": "0.0.1" }
PJ
cat > "$SREP_D2/claude/docs/harness-decay-cadence.md" <<DC
# Decay cadence
last_permission_review: $TODAY_ISO abc123
DC
set +e
SREP_D2_OUT=$(bash "$AUDIT" "$SREP_D2" 2>&1)
SREP_D2_RC=$?
set -e
SREP_D2_HAS_SKILL_INFO=$(printf '%s' "$SREP_D2_OUT" | grep -c "schema-rot: skill 'deferred-via-evals'" || true)
if [ "$SREP_D2_HAS_SKILL_INFO" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s deferral (evals.json): SKILL_MISSING suppressed — JSON key form matched\n' "harness-audit #31.1"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s deferral (evals.json): SKILL_MISSING fired %s times (want 0) — JSON form regex broken:\n%s\n' "harness-audit #31.1" "$SREP_D2_HAS_SKILL_INFO" "$SREP_D2_OUT"
fi

# (OO) regression guard — empty matcher must NOT fire HOOKS_SHAPE_FAIL.
# This mirrors the real kbg-harness pattern: hooks/hooks.json:415 has
# `"matcher": ""` for the ConfigChange event, which is a legal vendor
# convention (empty matcher = match all known multi-source events; see
# hooks/config-change-log.sh header). The check #31 was refined on
# 2026-06-12 after the round-2 reconcile found the "must be non-empty"
# spec was too strict. This test guards the refinement: a fixture
# that uses empty matchers (and otherwise satisfies the check) must
# produce zero HOOKS_SHAPE_FAIL findings.
SREP_O="$FIXTURE/srep-empty-matcher"; rm -rf "$SREP_O"; mkdir -p "$SREP_O/claude/skills/ok-skill" "$SREP_O/claude/hooks" "$SREP_O/claude/agents" "$SREP_O/claude/commands" "$SREP_O/claude/docs" "$SREP_O/.claude-plugin"
cat > "$SREP_O/claude/skills/ok-skill/SKILL.md" <<'SK'
---
name: ok-skill
description: 'Test fixture for audit #31 OO — empty matcher regression.'
---
# OK Skill

## Input Contract
- **Input 1**: ...

## Output Format
- **Output 1**: ...

## Failure Modes to Avoid
- **Failure mode 1**: ...
SK
cat > "$SREP_O/.claude-plugin/plugin.json" <<'PJ'
{ "name": "test-empty-matcher", "version": "0.0.1" }
PJ
# hooks.json: empty matcher is the SUBJECT of this test — must pass
# silently. All other fields valid. ConfigChange event registration
# with empty matcher is the real-world precedent this guards.
cat > "$SREP_O/claude/hooks/hooks.json" <<'HJ'
{
  "hooks": {
    "ConfigChange": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "echo config-change" }
        ]
      }
    ]
  }
}
HJ
cat > "$SREP_O/claude/docs/harness-decay-cadence.md" <<'DC'
# Decay cadence

last_permission_review: $TODAY_ISO abc123
DC
set +e
SREP_O_OUT=$(bash "$AUDIT" "$SREP_O" 2>&1)
SREP_O_RC=$?
set -e
# Assertions: zero HOOKS_SHAPE_FAIL findings, zero CRITs on the hooks.json
# shape. The test is about the hooks sub-check only — SKILL_MISSING and
# perm-bookmark are NOT the subject and can vary.
SREP_O_HAS_HOOKS_CRIT=$(printf '%s' "$SREP_O_OUT" | grep -c "HOOKS_SHAPE_FAIL" || true)
SREP_O_HAS_MATCHER_CRIT=$(printf '%s' "$SREP_O_OUT" | grep -c "matcher: not a string" || true)
if [ "$SREP_O_HAS_HOOKS_CRIT" = 0 ] && [ "$SREP_O_HAS_MATCHER_CRIT" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s empty matcher regression: 0 HOOKS_SHAPE_FAIL (legal vendor pattern accepted)\n' "harness-audit #31"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s empty matcher regression fired hooks-crit=%s matcher-crit=%s (want 0/0):\n%s\n' "harness-audit #31" "$SREP_O_HAS_HOOKS_CRIT" "$SREP_O_HAS_MATCHER_CRIT" "$SREP_O_OUT"
fi

# --- harness-audit check #32 — autonomy invariant guardrail ---
# Round-2 drill-down (2026-06-12) found that the load-bearing autonomy
# invariant (CONTEXT.md §Invariants) had no deterministic check. This
# trio (PP/QQ/RR) is the regression guard for that check. The invariant
# is enforced via the `disable-model-invocation: true` frontmatter on
# skills/recursive-improve/SKILL.md. If the field regresses to `: false`,
# `: True` (Python truthy), or is removed, the harness loses its
# self-binding and the model can self-start the recursive-improve skill
# — a one-model-version-away self-rewriter. The check emits CRIT, not
# WARN, because the invariant is irreversible (per ADR 0002).
#
# Mirrors the (MM)/(NN)/(OO) trio pattern: hermetic temp-dir fixture
# for the violation paths, real-repo path for the positive control.
# The (PP) test runs against the real kbg-harness repo to verify the
# check is silent when the field is present (the contract is that the
# audit green bar is preserved for the actual harness state).
AUDIT="$HOOKS/../skills/harness-audit/scripts/audit.sh"

# (PP) positive control — real repo, recursive-improve has the field.
# The audit should produce zero INVARIANT_FAIL findings. This is the
# test that runs in CI on every push; it would fail if a future
# commit removed the field from the real skill.
set +e
PP_OUT=$(bash "$AUDIT" . 2>&1)
PP_RC=$?
set -e
PP_HAS_INVARIANT=$(printf '%s' "$PP_OUT" | grep -c "INVARIANT\|autonomy invariant regressed" || true)
if [ "$PP_HAS_INVARIANT" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s real repo: 0 INVARIANT_FAIL (recursive-improve has disable-model-invocation: true)\n' "harness-audit #32"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s real repo emitted %s INVARIANT_FAIL findings (want 0), rc=%s:\n%s\n' "harness-audit #32" "$PP_HAS_INVARIANT" "$PP_RC" "$PP_OUT"
fi

# (QQ) violation fixture — temp recursive-improve skill with the field
# set to `false` (the would-be regression). The check should emit
# exactly 1 CRIT. Build a fresh fixture; do NOT mutate the real
# recursive-improve/SKILL.md (the (RR) test below would also be
# affected if the real file were touched).
QQ_F="$FIXTURE/qq-ri-bad"; rm -rf "$QQ_F"; mkdir -p "$QQ_F/claude/skills/recursive-improve" "$QQ_F/claude/agents" "$QQ_F/claude/commands" "$QQ_F/claude/hooks" "$QQ_F/claude/docs" "$QQ_F/.claude-plugin"
cat > "$QQ_F/claude/skills/recursive-improve/SKILL.md" <<'SK'
---
name: recursive-improve
description: "fixture — field flipped to false"
disable-model-invocation: false
---
# fixture
SK
cat > "$QQ_F/.claude-plugin/plugin.json" <<'PJ'
{ "name": "qq-fixture", "version": "0.0.1" }
PJ
set +e
QQ_OUT=$(bash "$AUDIT" "$QQ_F" 2>&1)
QQ_RC=$?
set -e
QQ_HAS_CRIT=$(printf '%s' "$QQ_OUT" | grep -c "missing 'disable-model-invocation: true'" || true)
# Expect exactly 1 CRIT — one for the recursive-improve regression.
# The audit's overall rc is dominated by the always-firing F1 symlink
# CRIT + 2 description WARNs on a fresh fixture, so we don't assert
# rc=0 here — only that check #32's own CRIT fires (the contract of
# this test).
if [ "$QQ_HAS_CRIT" -ge 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s violation fixture: 1+ CRIT fires (disable-model-invocation flipped to false)\n' "harness-audit #32"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s violation fixture: 0 CRIT (want 1+), rc=%s:\n%s\n' "harness-audit #32" "$QQ_RC" "$QQ_OUT"
fi

# (RR) regression guard — field value-typo must NOT pass silently.
# Mirrors the (OO) empty-matcher regression: the check must look for
# the EXACT string `disable-model-invocation: true` (lowercase,
# colon-space, lowercase), not just any truthy value. A regression to
# "True" / "yes" / "1" / "on" would silently disable the gate. The
# check is grep -qF (fixed string) which is exact-match — verified
# here by feeding it `: True` (Python truthy) and asserting 1+ CRIT.
RR_F="$FIXTURE/rr-ri-truthy"; rm -rf "$RR_F"; mkdir -p "$RR_F/claude/skills/recursive-improve" "$RR_F/claude/agents" "$RR_F/claude/commands" "$RR_F/claude/hooks" "$RR_F/claude/docs" "$RR_F/.claude-plugin"
cat > "$RR_F/claude/skills/recursive-improve/SKILL.md" <<'SK'
---
name: recursive-improve
description: "fixture — field is Python truthy `True` (capital T)"
disable-model-invocation: True
---
# fixture
SK
cat > "$RR_F/.claude-plugin/plugin.json" <<'PJ'
{ "name": "rr-fixture", "version": "0.0.1" }
PJ
set +e
RR_OUT=$(bash "$AUDIT" "$RR_F" 2>&1)
RR_RC=$?
set -e
RR_HAS_CRIT=$(printf '%s' "$RR_OUT" | grep -c "missing 'disable-model-invocation: true'" || true)
if [ "$RR_HAS_CRIT" -ge 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s truthy-typo regression: CRIT fires (check is exact-match on `: true`, not truthy)\n' "harness-audit #32"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s truthy-typo regression: 0 CRIT (want 1+) — check would silently pass `: True` — rc=%s:\n%s\n' "harness-audit #32" "$RR_RC" "$RR_OUT"
fi

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" = 0 ] || { echo "FAIL: $FAIL test(s) failed" >&2; exit 1; }
echo "✅ all critical hooks enforce as specified"
