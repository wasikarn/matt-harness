#!/usr/bin/env bash
# Full pre-push gauntlet: heavier than pre-commit, blocks on any failure.
# Runs in parallel: plugin-validate, full shell lint, JSON validation, harness-audit.
# Critical-hooks behavioral suite and eval gate deferred until harness rebuilt.
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
  local rc=0
  while IFS= read -r f; do
    [ -f "$ROOT/$f" ] || continue
    if ! bash -n "$ROOT/$f" 2>&1; then
      echo "  bash syntax error: $f" >&2
      rc=1
    fi
    if ! shellcheck --severity=warning "$ROOT/$f" 2>&1; then
      rc=1
    fi
  done < <(git -C "$ROOT" ls-files '*.sh')
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

# Launch all layers in parallel.
run_validate  > "$WORK_TMP/validate.log"  2>&1 &  PID_VAL=$!
run_shell_lint > "$WORK_TMP/lint.log"     2>&1 &  PID_LINT=$!
run_json_lint  > "$WORK_TMP/json.log"     2>&1 &  PID_JSON=$!
run_audit      > "$WORK_TMP/audit.log"    2>&1 &  PID_AUDIT=$!

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

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "gauntlet failed. Fix issues above before pushing." >&2
  exit 1
fi

echo "gauntlet: all layers green" >&2
exit 0
