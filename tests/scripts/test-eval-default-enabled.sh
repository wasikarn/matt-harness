#!/usr/bin/env bash
# test-eval-default-enabled.sh — exercises scripts/_lib/eval-default-enabled.sh's flip/restore
# logic against a scratch copy of the manifest, never the real repo's .claude-plugin/plugin.json.
# `with_default_enabled_true` infers its repo root from its own BASH_SOURCE, so each case sources
# a fresh copy of the lib under a throwaway "$scripts/_lib/eval-default-enabled.sh" + fixture
# ".claude-plugin/plugin.json" tree, isolating it from the real manifest.
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
LIB_SRC="$ROOT/scripts/_lib/eval-default-enabled.sh"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== eval-default-enabled.sh self-test ==="

new_sandbox() {
  # $1: initial plugin.json body (one or more "defaultEnabled": ... lines)
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts/_lib" "$dir/.claude-plugin"
  cp "$LIB_SRC" "$dir/scripts/_lib/eval-default-enabled.sh"
  printf '%s' "$1" > "$dir/.claude-plugin/plugin.json"
  echo "$dir"
}

# --- normal flip + restore on success ---
sandbox="$(new_sandbox '{"defaultEnabled": false}')"
during=$(bash -c "
source '$sandbox/scripts/_lib/eval-default-enabled.sh'
with_default_enabled_true cat '$sandbox/.claude-plugin/plugin.json'
")
after=$(cat "$sandbox/.claude-plugin/plugin.json")
[[ "$during" == *'"defaultEnabled": true'* ]] && ok "flips true during the wrapped command" \
  || bad "did not flip true during the wrapped command (got: $during)"
[[ "$after" == *'"defaultEnabled": false'* ]] && ok "restores false after normal return" \
  || bad "did not restore false after normal return (got: $after)"
rm -rf "$sandbox"

# --- restores even when the wrapped command fails ---
sandbox="$(new_sandbox '{"defaultEnabled": false}')"
bash -c "
source '$sandbox/scripts/_lib/eval-default-enabled.sh'
with_default_enabled_true false
" >/dev/null 2>&1
after=$(cat "$sandbox/.claude-plugin/plugin.json")
[[ "$after" == *'"defaultEnabled": false'* ]] && ok "restores false when the wrapped command exits non-zero" \
  || bad "did not restore false after wrapped-command failure (got: $after)"
rm -rf "$sandbox"

# --- restores even under a CALLER's own `set -e` (errexit skips a function's RETURN trap
# entirely unless the wrapped command's own failure is defused first before the function itself
# returns that same failure to the caller -- the caller then legitimately stops there, same as
# for any other failing command under set -e; the property under test is only that the restore
# already happened by that point, not that the caller keeps going) ---
sandbox="$(new_sandbox '{"defaultEnabled": false}')"
bash -c "
set -e
source '$sandbox/scripts/_lib/eval-default-enabled.sh'
with_default_enabled_true false
echo should-not-reach-here
" >/dev/null 2>&1
after=$(cat "$sandbox/.claude-plugin/plugin.json")
[[ "$after" == *'"defaultEnabled": false'* ]] && ok "restores false under a caller's set -e, before errexit aborts the caller" \
  || bad "did not restore false under set -e (got: $after)"
rm -rf "$sandbox"

# --- restores once a SIGTERM'd wrapped command exits (regression: RETURN alone never fires on
# a signal, per matt-harness commit d44c31fe -> 4254f657). Bash defers a trapped signal until
# the current foreground child exits, so this proves "restored after", not "interrupted mid-run" ---
sandbox="$(new_sandbox '{"defaultEnabled": false}')"
bash -c "
source '$sandbox/scripts/_lib/eval-default-enabled.sh'
with_default_enabled_true sleep 3
" &
runner_pid=$!
sleep 0.3
kill -TERM "$runner_pid"
wait "$runner_pid" 2>/dev/null
status=$?
after=$(cat "$sandbox/.claude-plugin/plugin.json")
[[ "$after" == *'"defaultEnabled": false'* ]] && ok "restores false once a SIGTERM'd wrapped command exits" \
  || bad "left defaultEnabled true after SIGTERM (got: $after)"
[ "$status" -ne 0 ] && ok "SIGTERM still actually terminates the wrapper (exit $status)" \
  || bad "wrapper survived SIGTERM instead of terminating (exit $status)"
rm -rf "$sandbox"

# --- same, for SIGHUP (e.g. a closed terminal/dropped SSH session mid-eval) ---
sandbox="$(new_sandbox '{"defaultEnabled": false}')"
bash -c "
source '$sandbox/scripts/_lib/eval-default-enabled.sh'
with_default_enabled_true sleep 3
" &
runner_pid=$!
sleep 0.3
kill -HUP "$runner_pid"
wait "$runner_pid" 2>/dev/null
after=$(cat "$sandbox/.claude-plugin/plugin.json")
[[ "$after" == *'"defaultEnabled": false'* ]] && ok "restores false once a SIGHUP'd wrapped command exits" \
  || bad "left defaultEnabled true after SIGHUP (got: $after)"
rm -rf "$sandbox"

# --- ambiguous manifest (2 matches): flip aborts loudly instead of silently no-op'ing ---
sandbox="$(new_sandbox '{"defaultEnabled": false, "other": {"defaultEnabled": false}}')"
before=$(cat "$sandbox/.claude-plugin/plugin.json")
out=$(bash -c "
source '$sandbox/scripts/_lib/eval-default-enabled.sh'
with_default_enabled_true echo ran
" 2>&1)
status=$?
after=$(cat "$sandbox/.claude-plugin/plugin.json")
[ "$status" -ne 0 ] && ok "ambiguous manifest: with_default_enabled_true returns non-zero" \
  || bad "ambiguous manifest: exited 0 (expected a hard failure)"
[[ "$out" != *"ran"* ]] && ok "ambiguous manifest: wrapped command never runs" \
  || bad "ambiguous manifest: wrapped command ran anyway with the plugin still disabled"
[ "$after" = "$before" ] && ok "ambiguous manifest: file left untouched" \
  || bad "ambiguous manifest: file was modified despite the abort (got: $after)"
rm -rf "$sandbox"

# --- missing manifest: hard error, not a silent no-op ---
sandbox="$(mktemp -d)"
mkdir -p "$sandbox/scripts/_lib"
cp "$LIB_SRC" "$sandbox/scripts/_lib/eval-default-enabled.sh"
out=$(bash -c "
source '$sandbox/scripts/_lib/eval-default-enabled.sh'
with_default_enabled_true echo ran
" 2>&1)
status=$?
[ "$status" -ne 0 ] && ok "missing manifest: with_default_enabled_true returns non-zero" \
  || bad "missing manifest: exited 0 (expected a hard failure)"
[[ "$out" != *"ran"* ]] && ok "missing manifest: wrapped command never runs" \
  || bad "missing manifest: wrapped command ran anyway"
rm -rf "$sandbox"

# --- already-true manifest: no-op flip, no incorrect restore-to-false ---
sandbox="$(new_sandbox '{"defaultEnabled": true}')"
bash -c "
source '$sandbox/scripts/_lib/eval-default-enabled.sh'
with_default_enabled_true true
" >/dev/null 2>&1
after=$(cat "$sandbox/.claude-plugin/plugin.json")
[[ "$after" == *'"defaultEnabled": true'* ]] && ok "already-true manifest is left true, not incorrectly restored to false" \
  || bad "already-true manifest was incorrectly changed (got: $after)"
rm -rf "$sandbox"

# --- non-bash caller (zsh): refuses instead of silently no-op'ing with the plugin still
# disabled (BASH_SOURCE/BASH_VERSION are unset under zsh, confirmed 2026-09-26) ---
if command -v zsh >/dev/null 2>&1; then
  sandbox="$(new_sandbox '{"defaultEnabled": false}')"
  before=$(cat "$sandbox/.claude-plugin/plugin.json")
  out=$(zsh -c "
cd '$sandbox'
source scripts/_lib/eval-default-enabled.sh
with_default_enabled_true echo ran
" 2>&1)
  status=$?
  after=$(cat "$sandbox/.claude-plugin/plugin.json")
  [ "$status" -ne 0 ] && ok "zsh caller: with_default_enabled_true returns non-zero" \
    || bad "zsh caller: exited 0 (expected a hard failure)"
  [[ "$out" != *"ran"* ]] && ok "zsh caller: wrapped command never runs" \
    || bad "zsh caller: wrapped command ran anyway with the plugin still disabled"
  [ "$after" = "$before" ] && ok "zsh caller: file left untouched" \
    || bad "zsh caller: file was modified despite the refusal (got: $after)"
  rm -rf "$sandbox"
else
  echo "  SKIP: zsh not installed, skipping non-bash-caller case"
fi

# --- traps don't leak into the caller's shell after a normal return (a later kill -TERM/-INT/
# -HUP in the SAME shell must not hit a stale trap referencing an out-of-scope $flipped) ---
sandbox="$(new_sandbox '{"defaultEnabled": false}')"
out=$(bash -c "
source '$sandbox/scripts/_lib/eval-default-enabled.sh'
with_default_enabled_true true >/dev/null 2>&1
trap -p RETURN INT TERM HUP
")
# Not a plain emptiness check: a caller whose own environment already ignores a signal (e.g. a
# backgrounded job under a test runner) reports it via 'trap -- \"\" SIGNAME', which is an
# inherited disposition, not a trap this function left behind -- only the function's own handler
# name is a real leak.
[[ "$out" != *"_restore_default_enabled"* ]] && ok "no _restore_default_enabled trap remains registered after a normal return" \
  || bad "a trap leaked into the caller's shell after return (trap -p: $out)"
rm -rf "$sandbox"

echo
echo "=== Summary: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
