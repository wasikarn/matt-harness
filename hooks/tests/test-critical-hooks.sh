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
task_event() { jq -n --arg id "$1" --arg subj "$2" --arg desc "$3" '{hook_event_name:"TaskCompleted",task_id:$id,task_subject:$subj,task_description:$desc}'; }
teammate_idle_event() { jq -n '{hook_event_name:"TeammateIdle"}'; }
task_created_event() { jq -n --arg id "$1" --arg subj "$2" --arg desc "$3" '{hook_event_name:"TaskCreated",task_id:$id,task_subject:$subj,task_description:$desc}'; }

# Temp fixture for gates that check real on-disk existence (config-protection
# only gates EDITS of a pre-existing config). Our own mktemp dir — cleaned on exit.
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
printf 'module.exports={};\n' > "$FIXTURE/.eslintrc"

echo "=== critical hook tests ==="

# Source sub-files in section order. Each sub-file is sourced (not executed
# as a subshell) so that PASS, FAIL, HOOKS, FIXTURE, and all helper functions
# (check, check_task, bash_event, …) are shared without re-declaration.
# shellcheck source=hooks/tests/test-ch-gates.sh
. "$(dirname "$0")/test-ch-gates.sh"
# shellcheck source=hooks/tests/test-ch-journal.sh
. "$(dirname "$0")/test-ch-journal.sh"
# shellcheck source=hooks/tests/test-ch-journal-phaseii.sh
. "$(dirname "$0")/test-ch-journal-phaseii.sh"
# shellcheck source=hooks/tests/test-ch-review-fixes.sh
. "$(dirname "$0")/test-ch-review-fixes.sh"
# shellcheck source=hooks/tests/test-ch-verif-validators.sh
. "$(dirname "$0")/test-ch-verif-validators.sh"
# shellcheck source=hooks/tests/test-ch-harness-audit31.sh
. "$(dirname "$0")/test-ch-harness-audit31.sh"
# shellcheck source=hooks/tests/test-ch-harness-audit32.sh
. "$(dirname "$0")/test-ch-harness-audit32.sh"
# shellcheck source=hooks/tests/test-ch-harness-audit-fixtures.sh
. "$(dirname "$0")/test-ch-harness-audit-fixtures.sh"
# shellcheck source=hooks/tests/test-ch-orphaned-runners.sh
. "$(dirname "$0")/test-ch-orphaned-runners.sh"
# shellcheck source=hooks/tests/test-ch-ideate-fanout.sh
. "$(dirname "$0")/test-ch-ideate-fanout.sh"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" = 0 ] || { echo "FAIL: $FAIL test(s) failed" >&2; exit 1; }
echo "✅ all critical hooks enforce as specified"

