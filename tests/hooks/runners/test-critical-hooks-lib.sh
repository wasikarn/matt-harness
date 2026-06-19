#!/usr/bin/env bash
# test-critical-hooks-lib.sh — shared helpers + temp fixture for
# test-ch-*.sh suites. Each suite is run standalone by test-critical-hooks.sh
# in parallel; this file gives every suite the same environment, helper
# functions, and isolated fixture directory.
#
# Sourcing convention:
#   source "$(dirname "$0")/test-critical-hooks-lib.sh"
#   # ... suite-specific checks ...
#   report

# shellcheck disable=SC1090,SC2034
# shellcheck shell=bash
set -uo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../hooks" && pwd)"
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
validator_bash_event()    { printf '{"tool_name":"Bash","agent_type":%s,"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)"; }
main_thread_bash_event()  { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -R .)"; }
write_event()    { printf '{"tool_name":"Write","tool_input":{"file_path":%s,"content":%s}}' "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)"; }
edit_new_event() { printf '{"tool_name":"Edit","tool_input":{"file_path":%s,"new_string":%s}}' "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)"; }
agent_event() { jq -n --arg desc "$1" --arg prompt "$2" --argjson bg "${3:-false}" '{tool_name:"Agent",tool_input:{description:$desc,prompt:$prompt,run_in_background:$bg}}'; }
task_event() { jq -n --arg id "$1" --arg subj "$2" --arg desc "$3" '{hook_event_name:"TaskCompleted",task_id:$id,task_subject:$subj,task_description:$desc}'; }
teammate_idle_event() { jq -n '{hook_event_name:"TeammateIdle"}'; }
task_created_event() { jq -n --arg id "$1" --arg subj "$2" --arg desc "$3" '{hook_event_name:"TaskCreated",task_id:$id,task_subject:$subj,task_description:$desc}'; }

# Temp fixture for gates that check real on-disk existence.
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
printf 'module.exports={};\n' > "$FIXTURE/.eslintrc"

# Export journal path so every test in this isolated process writes governance
# events to a temp file, never the operator's real ~/.claude journal.
JPATH="$FIXTURE/journal.jsonl"
export CLAUDE_JOURNAL_PATH="$JPATH"
JLIB="$HOOKS/_lib.sh"

# Governance summary script path (used by journal phase II).
GS="$HOOKS/../scripts/governance/governance-summary.py"

# Scripts root used by review-pr journaler / validator tests.
SCRIPTS="$HOOKS/../scripts"

# Print a parseable summary line for the orchestrator.
report() {
  printf 'SUITE PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
}

# Ensure every standalone suite emits a summary, even if it exits early.
trap report EXIT
