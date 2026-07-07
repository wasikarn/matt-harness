#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal \$ in payload strings is intentional
# Flow-nudge unit tests: simulates UserPromptSubmit JSON payloads and
# asserts stdout output (nudge fired) vs silence (nudge skipped). The
# hook never blocks, so all tests expect exit 0.
# Run standalone: bash hooks/tests/test-flow-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/advisory/flow-nudge.sh"

pass=0
fail=0

# Build a UserPromptSubmit payload. The real CC payload carries `prompt` at the
# TOP LEVEL (not under tool_input) — found 2026-07-03: the old fixture put it
# under tool_input, matching the hook's same wrong read, so the suite validated
# the bug and stayed green while the sensor never fired in production.
user_prompt_payload() {
  python3 -c '
import sys, json
prompt = sys.argv[1]
print(json.dumps({"tool_name": "UserPromptSubmit", "prompt": prompt}))
' "$1"
}

# Expect the hook to FIRE (stdout non-empty, exit 0).
test_nudge() {
  local desc="$1" prompt="$2"
  local out
  out=$(echo "$(user_prompt_payload "$prompt")" | bash "$HOOK" 2>/dev/null)
  local rc=$?
  if [[ "$rc" == "0" && -n "$out" ]]; then
    echo "  ✅ NUDGE: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ NUDGE EXPECTED but rc=$rc stdout=<$(printf '%s' "$out" | head -c 80)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

# Expect the hook to be SILENT (stdout empty, exit 0).
test_silent() {
  local desc="$1" prompt="$2"
  local out
  out=$(echo "$(user_prompt_payload "$prompt")" | bash "$HOOK" 2>/dev/null)
  local rc=$?
  if [[ "$rc" == "0" && -z "$out" ]]; then
    echo "  ✅ SILENT: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ SILENT EXPECTED but rc=$rc stdout=<$(printf '%s' "$out" | head -c 80)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

echo "=== flow-nudge hook (UserPromptSubmit) ==="
echo ""
echo "--- trivial prompts (must stay silent) ---"
test_silent "single-word prompt"          "typo"
test_silent "short typo-fix prompt"       "fix typo in CLAUDE.md line 5"
test_silent "short doc tweak"             "update README header"
test_silent "single-line question"        "what does this skill do?"
test_silent "empty prompt"                ""
# v0.36.0: bare 'build' fires (the v0.35.9 narrowing to `build (a|an|the|out)`
# cost recall — 8/8 natural impl phrasings were silent). Precision is reclaimed
# by a 2-pass CI-failure carve-out: if the ONLY impl match is a build-failure
# phrase (build failed/broken/error/fails/…) and no other impl verb is present,
# stay silent — it's a debug task, not implementation.
test_silent "build-failure is debug, not impl (carve-out)" "build failed, help me debug the CI"
test_silent "build broken in CI (carve-out)" "the build is broken after the merge"
test_nudge  "build failed BUT also add a limiter (other verb → fire)" \
  "build failed, but also add a rate limiter to the public API"

echo ""
echo "--- non-trivial prompts (must fire nudge) ---"
test_nudge  "explicit 'build a new feature' verb" \
  "build a new skill called playwright-coach for visual regression"
test_nudge  "long + multi-sentence feature request" \
  "I want to build a feature. It involves a database migration. Then a REST endpoint. Then CLI wiring. Can you plan it for me so we can ship it next sprint?"
test_nudge  "refactor verb" \
  "refactor the audit script to use the new plugin architecture and shared library"
test_nudge  "migrate verb" \
  "migrate the existing table-based inventory to a content-addressable store with backward compatibility"
test_nudge  "new endpoint verb" \
  "design a new endpoint to expose the audit results over HTTP with proper auth and rate limiting"
test_nudge  "implicit flow verbs (grill, to-prd)" \
  "let's grill this design and turn it into a PRD then split into issues for the team to pick up"
# Natural implementation phrasings on a real project (not kbg meta-work) — these
# were all silent before v0.35.8 (verb set was tuned to harness self-work), which
# defeated the plan-first nudge on exactly the work the owner reported. Guard the
# widened verb set so a future narrowing re-introduces the miss loudly.
test_nudge  "add verb (feature on a real project)" \
  "add a rate limiter to the public API"
test_nudge  "create verb (new endpoint, natural phrasing)" \
  "create an endpoint for user search with pagination"
test_nudge  "set up verb (auth wiring)" \
  "set up auth with JWT and refresh tokens"
test_nudge  "optimize verb (perf work)" \
  "optimize the slow dashboard queries"
# v0.36.0: bare 'build' phrasings that the v0.35.9 narrowing (build a/an/the/out)
# silently missed — these are the natural real-project impl phrasings the owner
# reported were going unplanned. Guard bare 'build' recall.
test_nudge  "build new features (bare build, plural)" \
  "build new features for the admin dashboard"
test_nudge  "build this feature (bare build, determiner-less)" \
  "build this feature for the billing flow"
test_nudge  "build our billing service (bare build, our)" \
  "build our billing service with metered usage"
test_nudge  "build it (bare build, pronoun)" \
  "build it and wire it to the existing API"
test_nudge  "build out the dashboard (build out was in v0.35.9 too)" \
  "build out the dashboard with the new charts"
test_nudge  "implement the auth flow" \
  "implement the auth flow with JWT and refresh tokens"
test_nudge  "wire up the webhook" \
  "wire up the webhook to the billing service"
test_nudge  "integrate the payments service" \
  "integrate the payments service with the order pipeline"
test_nudge  "rewrite the audit pipeline" \
  "rewrite the audit pipeline to use the shared library"
test_nudge  "new command for X" \
  "new command for exporting audit results to CSV"
test_nudge  "to-prd this idea" \
  "to-prd this idea about a usage metering feature"
test_nudge  "to-issues this PRD" \
  "to-issues this PRD into grabbable tickets"
test_nudge  "ship this" \
  "ship this rate-limiter change"
test_silent "long doc reorg w/ no flow verb (must stay silent — length alone must not fire)" \
  "document the README to introduce the plugin, then cover a quickstart for install plus first surface plus first hook. Then a troubleshooting section. Then a deep-dive on the composer-not-creator doctrine and how matt-pocock's flow fits our native doctrine. After that, expand the existing examples. After that, a migration guide. After that, link out to the relevant skills and commands. After that, a CHANGELOG entry."

echo ""
echo "--- nudge content contract (must name plan mode) ---"
# Lock the plan-first framing: a future edit that drops the plan-mode line from
# the nudge output must fail here (the fire/silent tests only check the trigger,
# which is unchanged, so they wouldn't catch a content regression).
content_out=$(echo "$(user_prompt_payload "refactor the whole audit pipeline across many files")" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$content_out" | /usr/bin/grep -qi "plan mode"; then
  echo "  ✅ CONTENT: nudge names 'plan mode'"
  pass=$((pass + 1))
else
  echo "  ❌ CONTENT EXPECTED 'plan mode' in nudge: <$(printf '%s' "$content_out" | head -c 120)>" >&2
  fail=$((fail + 1))
fi

echo ""
echo "--- empty / malformed input (must stay silent + exit 0) ---"
# Empty stdin (no JSON) → silent. Test by piping empty input directly.
empty_out=$(echo "" | bash "$HOOK" 2>/dev/null)
empty_rc=$?
if [[ "$empty_rc" == "0" && -z "$empty_out" ]]; then
  echo "  ✅ SILENT: empty stdin"
  pass=$((pass + 1))
else
  echo "  ❌ SILENT EXPECTED but rc=$empty_rc stdout=<$(printf '%s' "$empty_out" | head -c 80)>: empty stdin" >&2
  fail=$((fail + 1))
fi

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1