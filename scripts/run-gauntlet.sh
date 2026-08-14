#!/usr/bin/env bash
# Full pre-push gauntlet: heavier than pre-commit, blocks on any failure.
# Runs in parallel: plugin-validate, full shell lint, JSON validation, harness-audit,
# hook behavioral suite (deny-gate + advisory-sensor unit tests).
# The broader fleet critical-hooks suite and the eval dataset gate remain deferred
# until rebuilt; the deny-gate behavioral tests below are the safety-critical subset.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_TMP=$(mktemp -d "${TMPDIR:-/tmp}/kbg-gauntlet.XXXXXX")
trap 'rm -rf "$WORK_TMP"' EXIT

fail=0

# ---- plugin validate ----
run_validate() {
  cd "$ROOT" || return 1
  claude plugin validate --strict . 2>&1
}

# ---- full shell lint (all tracked .sh files) ----
run_shell_lint() {
  local rc=0 files=()
  while IFS= read -r f; do
    [ -f "$ROOT/$f" ] || continue
    files+=("$f")
    if ! bash -n "$ROOT/$f" 2>&1; then
      echo "  bash syntax error: $f" >&2
      rc=1
    fi
  done < <(git -C "$ROOT" ls-files '*.sh')
  # Batch shellcheck into one invocation over all files instead of spawning
  # it per file (~1.2s saved over ~66 files; parse work still scales with file
  # count). Whitespace-safe arg expansion (mapfile-style prefix). shellcheck
  # includes the filename in each finding so per-file attribution is preserved.
  # Note: shellcheck is NOT the gauntlet long-pole — harness-audit is (~8.4s
  # vs this layer's ~0.9s, measured 2026-07-03). Batching is still worth it,
  # just not the felt-latency lever.
  if [ "${#files[@]}" -gt 0 ]; then
    if ! shellcheck --severity=warning "${files[@]/#/$ROOT/}" 2>&1; then
      rc=1
    fi
  fi
  return "$rc"
}

# ---- JSON validation (all tracked .json files) ----
run_json_lint() {
  local rc=0
  while IFS= read -r f; do
    [ -f "$ROOT/$f" ] || continue
    if ! jq -e . "$ROOT/$f" >/dev/null 2>&1; then
      echo "  invalid JSON: $f" >&2
      rc=1
    fi
  done < <(git -C "$ROOT" ls-files '*.json')
  return "$rc"
}

# ---- harness-audit (all findings, graceful-skip if absent) ----
run_audit() {
  local AUDIT="$ROOT/skills/harness-audit/scripts/audit.sh"
  [ -f "$AUDIT" ] || AUDIT="$HOME/.claude/skills/harness-audit/scripts/audit.sh"
  if [ ! -f "$AUDIT" ]; then
    echo "  harness-audit not found — skipped"
    return 0
  fi
  local audit_cmd="bash $AUDIT $ROOT"
  [ -n "${KBG_GAUNTLET_PLUGIN_CACHE:-}" ] && audit_cmd="$audit_cmd --plugin-cache $KBG_GAUNTLET_PLUGIN_CACHE"
  eval "$audit_cmd" 2>&1
}

# ---- path hygiene (all tracked text files; public repo) ----
# Second layer behind pre-commit's staged-file check: catches a literal home
# path that got committed anyway (a clone without core.hooksPath wired, a
# commit from another machine). $HOME expands per-machine so each machine
# guards its own leak; /Users/<name> placeholder text passes untouched.
run_path_hygiene() {
  [ -z "${HOME:-}" ] && return 0  # empty pattern would match everything
  local hits
  hits="$(git -C "$ROOT" grep -lF "$HOME" -- '*.md' '*.json' '*.yml' '*.yaml' '*.txt' 2>/dev/null)"
  if [ -n "$hits" ]; then
    echo "  literal home path in tracked files — use ~:" >&2
    printf '%s\n' "$hits" | sed 's/^/    /' >&2
    return 1
  fi
  return 0
}

# ---- behavioral test suite (hooks + slash-command scripts) ----
# Runs the actual gate scripts against fixture payloads and asserts allow/deny/ask;
# also runs regression tests for embedded slash-command scripts (e.g. cost-report.md's
# node aggregation). This is the safety-critical net: a regression in irrecoverable.sh /
# verifier-protect.sh (incl. the folded path-hardcode deny) fails here instead of shipping
# green — same for a shipped command that's silently syntax-broken or double-counts.
# Graceful-skip if absent.
run_hook_tests() {
  local rc=0 t
  for t in "$ROOT/tests/hooks/test-gates.sh" "$ROOT/tests/hooks/test-worktree-guard.sh" "$ROOT/tests/hooks/test-verifier-protect.sh" "$ROOT/tests/hooks/test-flow-nudge.sh" "$ROOT/tests/hooks/test-jira-route-nudge.sh" "$ROOT/tests/hooks/test-session-stop.sh" "$ROOT/tests/hooks/test-learn-nudge.sh" "$ROOT/tests/hooks/test-plan-review-nudge.sh" "$ROOT/tests/hooks/test-compliance-audit-nudge.sh" "$ROOT/tests/hooks/test-memory-health-nudge.sh" "$ROOT/tests/hooks/test-convergence-merge-gate.sh" "$ROOT/tests/skills/harness-audit/test-harness-audit.sh" "$ROOT/tests/skills/review-pr/test-write-review-state.sh" "$ROOT/tests/skills/review-pr/test-should-continue-loop.sh" "$ROOT/tests/commands/test-cost-report.sh" "$ROOT/tests/commands/test-ship-merge-codeowners.sh" "$ROOT/tests/commands/test-risk-check.sh"; do
    [ -f "$t" ] || continue
    bash "$t" 2>&1 || rc=1
  done
  return "$rc"
}

# Launch all layers in parallel.
run_validate  > "$WORK_TMP/validate.log"  2>&1 &  PID_VAL=$!
run_shell_lint > "$WORK_TMP/lint.log"     2>&1 &  PID_LINT=$!
run_json_lint  > "$WORK_TMP/json.log"     2>&1 &  PID_JSON=$!
run_audit      > "$WORK_TMP/audit.log"    2>&1 &  PID_AUDIT=$!
run_path_hygiene > "$WORK_TMP/pathhyg.log" 2>&1 & PID_PATH=$!
run_hook_tests > "$WORK_TMP/hooktests.log" 2>&1 & PID_HOOK=$!

wait_layer() {
  local name="$1" pid="$2" log="$3"
  if wait "$pid"; then
    echo "  ✅ $name" >&2
  else
    echo "  ❌ $name" >&2
    tail -n 20 "$log" | sed 's/^/     /' >&2
    fail=1
  fi
}

wait_layer "plugin-validate" "$PID_VAL"   "$WORK_TMP/validate.log"
wait_layer "shell-lint"      "$PID_LINT"  "$WORK_TMP/lint.log"
wait_layer "json-lint"       "$PID_JSON"  "$WORK_TMP/json.log"
wait_layer "harness-audit"   "$PID_AUDIT" "$WORK_TMP/audit.log"
wait_layer "path-hygiene"    "$PID_PATH"  "$WORK_TMP/pathhyg.log"
wait_layer "hook-tests"      "$PID_HOOK"  "$WORK_TMP/hooktests.log"

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "gauntlet failed. Fix issues above before pushing." >&2
  exit 1
fi

echo "gauntlet: all layers green" >&2
exit 0
