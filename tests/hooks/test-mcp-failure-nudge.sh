#!/usr/bin/env bash
# mcp-failure-nudge unit tests (#97): simulates PostToolUseFailure JSON
# payloads, asserts stdout (hookSpecificOutput.additionalContext) fires once
# an MCP server fails MH_MCP_FAILURE_THRESHOLD+ times within the trailing
# MH_MCP_FAILURE_WINDOW_SECONDS, dedupes on subsequent failures while the
# rate holds, and re-arms once the rate drops. Uses MH_MCP_FAILURE_NOW to
# inject a fake clock -- real time windows can't be tested deterministically
# without sleeping. The hook never blocks (advisory only), so every call
# expects exit 0.
# Run standalone: bash tests/hooks/test-mcp-failure-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/advisory/mcp-failure-nudge.sh"

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
    "tool_input": {},
    "tool_use_id": "toolu_test",
    "error": sys.argv[3],
    "hook_event_name": "PostToolUseFailure",
}, ensure_ascii=False))
' "$1" "$2" "$3"
}

call() {
  # call <session> <tool> <error> <now-epoch>
  HOME="$TMP_HOME" MH_MCP_FAILURE_NOW="$4" bash -c "echo '$(payload "$1" "$2" "$3")' | '$HOOK'" 2>/dev/null
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

BASE=1700000000

# --- Scenario 1: below threshold never fires ---
out=$(call "s1" "mcp__qmd__query" "conn refused" "$BASE")
assert_silent "1st failure" "$out"
out=$(call "s1" "mcp__qmd__query" "conn refused" "$((BASE + 5))")
assert_silent "2nd failure (still below threshold=3)" "$out"

# --- Scenario 2: 3rd failure within the window fires, 4th dedupes ---
out=$(call "s1" "mcp__qmd__query" "conn refused" "$((BASE + 10))")
assert_fire "3rd failure crosses threshold" "$out"
out=$(call "s1" "mcp__qmd__query" "conn refused" "$((BASE + 15))")
assert_silent "4th failure deduped (same message already emitted)" "$out"

# --- Scenario 3: non-MCP tool names are out of scope ---
out=$(call "s2" "Bash" "exit 1" "$BASE")
out=$(call "s2" "Bash" "exit 1" "$BASE")
out=$(call "s2" "Bash" "exit 1" "$BASE")
assert_silent "non-MCP tool_name never fires" "$out"

# --- Scenario 4: different servers get independent buckets ---
out=$(call "s3" "mcp__firecrawl__scrape" "timeout" "$BASE")
out=$(call "s3" "mcp__firecrawl__scrape" "timeout" "$BASE")
out=$(call "s3" "mcp__qmd__query" "conn refused" "$BASE")
assert_silent "2 failures on firecrawl + 1 on qmd -- neither alone crosses threshold" "$out"

# --- Scenario 4b: DIFFERENT TOOLS on the SAME server share one bucket ---
# (the actual thing server-slug parsing guarantees -- a bucket keyed on the
# full tool_name instead of just the parsed server would fail this, since
# each distinct tool name would get its own separate, never-crossing count).
out=$(call "s3b" "mcp__qmd__query" "err" "$BASE")
out=$(call "s3b" "mcp__qmd__status" "err" "$((BASE + 2))")
out=$(call "s3b" "mcp__qmd__query" "err" "$((BASE + 4))")
assert_fire "s3b: query+status+query on the SAME server 'qmd' cross threshold together" "$out"

# --- Scenario 5: failures spread OUTSIDE the window don't accumulate ---
# window default 300s: two failures 400s apart never both count toward the
# same trailing window, so a 3rd shortly after the 2nd still isn't 3-in-300s.
out=$(call "s4" "mcp__gmail__send" "rate limited" "$BASE")
out=$(call "s4" "mcp__gmail__send" "rate limited" "$((BASE + 400))")
out=$(call "s4" "mcp__gmail__send" "rate limited" "$((BASE + 405))")
assert_silent "failures spread beyond the window never accumulate to 3" "$out"

# --- Scenario 6: rate drops below threshold, then a later burst re-fires ---
out=$(call "s5" "mcp__qmd__query" "err" "$BASE")
out=$(call "s5" "mcp__qmd__query" "err" "$((BASE + 5))")
out=$(call "s5" "mcp__qmd__query" "err" "$((BASE + 10))")
assert_fire "s5: 3rd failure crosses threshold" "$out"
# Jump far enough forward that the whole window has aged out (rate settles).
out=$(call "s5" "mcp__qmd__query" "err" "$((BASE + 1000))")
assert_silent "s5: window aged out -- rate has settled, marker cleared" "$out"
out=$(call "s5" "mcp__qmd__query" "err" "$((BASE + 1005))")
out=$(call "s5" "mcp__qmd__query" "err" "$((BASE + 1010))")
assert_fire "s5: fresh burst re-fires (marker was cleared, not stuck-suppressed)" "$out"

# --- Scenario 7: error text is capped, not echoed unbounded ---
LONG_ERROR=$(python3 -c "print('x' * 5000)")
out=$(call "s6" "mcp__qmd__query" "$LONG_ERROR" "$BASE")
out=$(call "s6" "mcp__qmd__query" "$LONG_ERROR" "$((BASE + 5))")
out=$(call "s6" "mcp__qmd__query" "$LONG_ERROR" "$((BASE + 10))")
ctx_len=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | wc -c | tr -d ' ')
if [[ -n "$out" && "${ctx_len:-99999}" -lt 500 ]]; then
  echo "  ✅ CAPPED: 5000-char error excerpt stays well under 500 chars in the message"; pass=$((pass + 1))
else
  echo "  ❌ expected a capped message under 500 chars, got ${ctx_len:-unknown}" >&2
  fail=$((fail + 1))
fi

# --- Scenario 8: missing jq -> silent no-op, never a hard failure ---
NOJQ_BIN="$(mktemp -d)"
for b in bash cat grep awk tail mkdir python3 date wc mv printf head tr; do
  p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$NOJQ_BIN/$b"
done
out=$(HOME="$TMP_HOME" MH_MCP_FAILURE_NOW="$BASE" env PATH="$NOJQ_BIN" bash -c "echo '$(payload "s7" "mcp__qmd__query" "err")' | '$HOOK'" 2>/dev/null)
rc=$?
if [[ "$rc" == "0" && -z "$out" ]]; then
  echo "  ✅ SILENT: missing jq -> no-op, exit 0"; pass=$((pass + 1))
else
  echo "  ❌ expected silent exit 0 with jq absent, got rc=$rc out=<$out>" >&2
  fail=$((fail + 1))
fi
trash "$NOJQ_BIN" 2>/dev/null || true

echo ""
echo "mcp-failure-nudge: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
