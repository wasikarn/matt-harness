#!/usr/bin/env bash
# loop-repeat-nudge unit tests (#99): simulates PostToolUse JSON payloads,
# asserts stdout (hookSpecificOutput.additionalContext) fires once a tool is
# called with identical parameters MH_LOOP_REPEAT_THRESHOLD+ times in the
# last MH_LOOP_REPEAT_WINDOW calls, dedupes on subsequent identical calls,
# and re-arms after the pattern breaks. The hook never blocks (advisory
# only), so every call expects exit 0.
# Run standalone: bash tests/hooks/test-loop-repeat-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/advisory/loop-repeat-nudge.sh"

pass=0
fail=0

TMP_HOME="$(mktemp -d)"
trap 'trash "$TMP_HOME" 2>/dev/null || true' EXIT

payload() {
  python3 -c '
import sys, json
print(json.dumps({
    "session_id": sys.argv[1],
    "tool_name": sys.argv[2],
    "tool_input": json.loads(sys.argv[3]),
    "hook_event_name": "PostToolUse",
}, ensure_ascii=False))
' "$1" "$2" "$3"
}

call() {
  # call <session> <tool> <input-json>
  HOME="$TMP_HOME" bash -c "echo '$(payload "$1" "$2" "$3")' | '$HOOK'" 2>/dev/null
}

assert_fire() {
  local desc="$1" out="$2"
  if [[ -n "$out" ]] && printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
    echo "  ✅ FIRE: $desc"; pass=$((pass + 1))
  else
    echo "  ❌ FIRE EXPECTED but got <$(printf '%s' "$out" | head -c 120)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

assert_silent() {
  local desc="$1" out="$2"
  if [[ -z "$out" ]]; then
    echo "  ✅ SILENT: $desc"; pass=$((pass + 1))
  else
    echo "  ❌ SILENT EXPECTED but got <$(printf '%s' "$out" | head -c 120)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

# --- Scenario 1: below threshold never fires ---
out=$(call "s1" "Read" '{"file_path":"a.txt"}')
assert_silent "1st identical call" "$out"
out=$(call "s1" "Read" '{"file_path":"a.txt"}')
assert_silent "2nd identical call (still below threshold=3)" "$out"

# --- Scenario 2: 3rd identical call fires, 4th dedupes ---
out=$(call "s1" "Read" '{"file_path":"a.txt"}')
assert_fire "3rd identical call crosses threshold" "$out"
out=$(call "s1" "Read" '{"file_path":"a.txt"}')
assert_silent "4th identical call deduped (same message already emitted)" "$out"

# --- Scenario 3: different params never trip the counter ---
out=$(call "s2" "Edit" '{"file_path":"a.txt","old_string":"x"}')
out=$(call "s2" "Edit" '{"file_path":"a.txt","old_string":"y"}')
out=$(call "s2" "Edit" '{"file_path":"a.txt","old_string":"z"}')
assert_silent "3 calls to the same tool with DIFFERENT params never fires" "$out"

# --- Scenario 4: key-order in tool_input doesn't dodge detection ---
out=$(call "s3" "Bash" '{"command":"ls","timeout":5}')
out=$(call "s3" "Bash" '{"timeout":5,"command":"ls"}')
out=$(call "s3" "Bash" '{"command":"ls","timeout":5}')
assert_fire "reordered-but-identical JSON keys still counted as the same call" "$out"

# --- Scenario 5: pattern genuinely drops below threshold, then re-fires
# later (re-arm, not stuck-suppressed forever after the first fire).
# Window defaults to 5: 3x foo fires; 3 distinct fillers push foo's count
# in the trailing window down to 2 (below threshold), which clears foo's
# dedupe marker the next time foo itself is the current call; two more foo
# calls bring the window back to 3x foo and it fires again.
out=$(call "s4" "Grep" '{"pattern":"foo"}')
out=$(call "s4" "Grep" '{"pattern":"foo"}')
out=$(call "s4" "Grep" '{"pattern":"foo"}')
assert_fire "s4: 3rd identical call crosses threshold" "$out"
call "s4" "Grep" '{"pattern":"d1"}' >/dev/null
call "s4" "Grep" '{"pattern":"d2"}' >/dev/null
call "s4" "Grep" '{"pattern":"d3"}' >/dev/null
out=$(call "s4" "Grep" '{"pattern":"foo"}')
assert_silent "s4: foo's count in the window has dropped to 2 (below threshold) -- clears its marker" "$out"
out=$(call "s4" "Grep" '{"pattern":"foo"}')
assert_silent "s4: still below threshold (count=2)" "$out"
out=$(call "s4" "Grep" '{"pattern":"foo"}')
assert_fire "s4: window is 3x foo again -- re-fires (marker was cleared, not stuck-suppressed)" "$out"

# --- Scenario 6: an unrelated intervening pattern on the SAME tool doesn't
# clear the dedupe marker of a still-ongoing, different pattern ---
out=$(call "s5" "Write" '{"file_path":"x.txt","content":"same"}')
out=$(call "s5" "Write" '{"file_path":"x.txt","content":"same"}')
out=$(call "s5" "Write" '{"file_path":"x.txt","content":"same"}')
assert_fire "s5: pattern A (same tool) crosses threshold" "$out"
out=$(call "s5" "Write" '{"file_path":"y.txt","content":"different"}')
assert_silent "s5: pattern B (different params, same tool) is below its own threshold" "$out"
out=$(call "s5" "Write" '{"file_path":"x.txt","content":"same"}')
assert_silent "s5: pattern A is STILL deduped -- pattern B's call didn't clear A's marker" "$out"

# --- Scenario 7: missing jq -> silent no-op, never a hard failure ---
NOJQ_BIN="$(mktemp -d)"
for b in bash cat grep awk tail mkdir python3 cksum rm mv printf; do
  p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$NOJQ_BIN/$b"
done
out=$(HOME="$TMP_HOME" env PATH="$NOJQ_BIN" bash -c "echo '$(payload "s6" "Read" '{"a":1}')' | '$HOOK'" 2>/dev/null)
rc=$?
if [[ "$rc" == "0" && -z "$out" ]]; then
  echo "  ✅ SILENT: missing jq -> no-op, exit 0"; pass=$((pass + 1))
else
  echo "  ❌ expected silent exit 0 with jq absent, got rc=$rc out=<$out>" >&2
  fail=$((fail + 1))
fi
trash "$NOJQ_BIN" 2>/dev/null || true

echo ""
echo "loop-repeat-nudge: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
