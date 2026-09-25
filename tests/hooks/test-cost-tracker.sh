#!/usr/bin/env bash
# Tests for hooks/stop/cost-tracker.sh's pricing.
#
# Phase 1 -- rate() model-pricing table. Extracts the live `def rate: ...
# end;` block from the script (so the model branches this test checks can't
# drift out of sync with the real function) and asserts each model-family
# test matches only its own family, not a broader sibling whose name it
# contains (e.g. "opus-5-5" must not fall through to "opus"). $sonnet_rate
# below is a fixed stand-in value the rate def expects as an argument, not a
# pasted copy of a checked branch.
#
# Phase 2 -- group_and_price()'s cache-write pricing (issue #162). Runs the
# real script end to end against a synthetic transcript, so it exercises the
# 5m/1h split as it actually executes, not a re-derived jq snippet.
#
# Run standalone: bash tests/hooks/test-cost-tracker.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/hooks/stop/cost-tracker.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

rate_def="$(sed -n '/^    def rate:/,/end;$/p' "$SCRIPT")"
if [[ -z "$rate_def" ]]; then
  bad "could not extract 'def rate: ... end;' from $SCRIPT — has it been restructured?"
  echo "1 passed, $fail failed"; exit 1
fi

price() {
  local model="$1"
  jq -n --argjson sonnet_rate '{"i":2.0,"o":10.0,"cw":2.50,"cw1h":4.00,"cr":0.20}' --arg m "$model" \
    "$rate_def"$'\n'"{model: \$m} | rate"
}

result="$(price claude-opus-5-5)"
i="$(jq -r .i <<<"$result")"
o="$(jq -r .o <<<"$result")"
cr="$(jq -r .cr <<<"$result")"
v="$(jq -r .v <<<"$result")"
if [[ "$i" == "4.0" && "$o" == "20.0" && "$cr" == "0.20" && "$v" == "true" ]]; then
  ok "claude-opus-5-5 prices at 4.0/20.0, cr=0.20, v=true (Opus 5.5 rate), not Opus 5's 5.0/25.0"
else
  bad "claude-opus-5-5 priced at i=$i o=$o cr=$cr v=$v, expected i=4.0 o=20.0 cr=0.20 v=true — Opus 5.5 branch missing, wrong, or still unverified"
fi

result="$(price claude-opus-5)"
i="$(jq -r .i <<<"$result")"
if [[ "$i" == "5.0" ]]; then
  ok "claude-opus-5 (not 5.5) still prices at 5.0 — the opus-5-5 branch didn't swallow the bare opus test"
else
  bad "claude-opus-5 priced at i=$i, expected i=5.0 — opus-5-5 branch is too broad"
fi

# 1-hour cache-write rate (issue #162): every model's 1h cache write is priced
# at 2x its base input rate on the live pricing page (confirmed 2026-09-25),
# distinct from and higher than the 5-minute write rate (1.25x). rate() must
# expose it as cw1h so group_and_price can bill 1h-TTL writes correctly.
result="$(price claude-opus-5-5)"
cw="$(jq -r .cw <<<"$result")"
cw1h="$(jq -r .cw1h <<<"$result")"
if [[ "$cw" == "5.00" && "$cw1h" == "8.00" ]]; then
  ok "claude-opus-5-5 exposes cw=5.00 (5m) and cw1h=8.00 (1h), distinct rates"
else
  bad "claude-opus-5-5 cw=$cw cw1h=$cw1h, expected cw=5.00 cw1h=8.00 — 1h cache-write rate missing or wrong"
fi

echo "$pass passed, $fail failed (phase 1)"

echo "=== group_and_price: bills 1h-TTL cache writes at the 1h rate, not the 5m rate ==="

pass2=0
fail2=0
ok2()  { pass2=$((pass2 + 1)); echo "PASS: $1"; }
bad2() { fail2=$((fail2 + 1)); echo "FAIL: $1" >&2; }

# make_usage_line <cache_creation_input_tokens> [ephemeral_5m] [ephemeral_1h]
# Omitting the last two args reproduces a pre-breakdown transcript: only the
# flat field, no `cache_creation` object at all.
make_usage_line() {
  python3 -c '
import json, sys
flat = sys.argv[1]
e5m = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != "" else None
e1h = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "" else None
usage = {"input_tokens": 0, "output_tokens": 0,
         "cache_creation_input_tokens": int(flat), "cache_read_input_tokens": 0}
if e5m is not None:
    usage["cache_creation"] = {"ephemeral_5m_input_tokens": int(e5m), "ephemeral_1h_input_tokens": int(e1h)}
print(json.dumps({"type": "assistant", "message": {"model": "claude-opus-5-5", "usage": usage}}))
' "$1" "${2-}" "${3-}"
}

run_row() {
  local transcript payload fake_home row
  fake_home=$(mktemp -d)
  transcript=$(mktemp)
  cat > "$transcript"
  payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "t162"}))' "$transcript")
  printf '%s' "$payload" | HOME="$fake_home" bash "$SCRIPT" >/dev/null 2>/dev/null
  row=$(tail -1 "$fake_home/.local/share/kbg/metrics/costs.jsonl" 2>/dev/null)
  trash "$fake_home" "$transcript" 2>/dev/null || true
  printf '%s' "$row"
}

# All-1h write: 1,000,000 tokens, entirely ephemeral_1h. Opus 5.5's cw1h rate
# is $8/MTok vs cw (5m) $5/MTok -- expect 8.0, not 5.0.
row="$(make_usage_line 1000000 0 1000000 | run_row)"
cost="$(jq -r .estimated_cost_usd <<<"$row" 2>/dev/null)"
if [[ "$cost" == "8" || "$cost" == "8.0" ]]; then
  ok2 "1,000,000 all-1h cache-write tokens bill at \$8/MTok (1h rate) = \$8.00"
else
  bad2 "1,000,000 all-1h cache-write tokens billed \$$cost, expected \$8.00 -- still using the 5m rate (\$5.00) or wrong"
fi

# Legacy shape (no `cache_creation` breakdown object at all): must still bill
# the full flat total at the 5m rate, unchanged from before this fix.
row="$(make_usage_line 1000000 | run_row)"
cost="$(jq -r .estimated_cost_usd <<<"$row" 2>/dev/null)"
if [[ "$cost" == "5" || "$cost" == "5.0" ]]; then
  ok2 "legacy transcript with only the flat field still bills \$5/MTok (5m rate), unchanged"
else
  bad2 "legacy flat-field-only transcript billed \$$cost, expected \$5.00 -- backward-compat fallback broke"
fi

# Multi-iteration turn (deep-audit finding, 2026-09-25): a real transcript
# line's top-level `cache_creation` object is a copy of iterations[0]'s own
# breakdown, NOT a sum across `.message.usage.iterations[]` -- unlike the
# flat `cache_creation_input_tokens` field, which DOES sum across iterations
# (confirmed empirically: top-level flat == sum(iteration flats) in 2571/2604
# real mismatched lines on this machine; top-level breakdown == sum(iteration
# breakdowns) in only 23/2604). Reading the top-level breakdown directly
# undercounts any multi-iteration turn. Shape below is a real observed line
# (model claude-sonnet-5, iterations [message, advisor_message on
# claude-opus-5, message] -- mh:blind-spot-hunter F8: an earlier draft of
# this fixture mislabeled it "agentic tool-loop" and stripped type/model,
# which is why the F5 case below went unnoticed the first time), values
# otherwise unchanged. Correct total: 3029 (5m) + 429 (1h) = 3458, matching
# the flat field; the bug would instead report 0 (5m) + 429 (1h) = 429,
# dropping iteration[2]'s 3029 5m tokens entirely.
multi_iter_line="$(python3 -c '
import json
iters = [
    {"type": "message", "input_tokens": 2, "output_tokens": 1662, "cache_creation_input_tokens": 429,
     "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 429}},
    {"type": "advisor_message", "model": "claude-opus-5", "input_tokens": 125077, "output_tokens": 3808,
     "cache_creation_input_tokens": 0,
     "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 0}},
    {"type": "message", "input_tokens": 2, "output_tokens": 401, "cache_creation_input_tokens": 3029,
     "cache_creation": {"ephemeral_5m_input_tokens": 3029, "ephemeral_1h_input_tokens": 0}},
]
usage = {"input_tokens": 4, "output_tokens": 2063, "cache_read_input_tokens": 0,
          "cache_creation_input_tokens": 3458,
          "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 429},
          "iterations": iters}
print(json.dumps({"type": "assistant", "message": {"model": "claude-sonnet-5", "id": "msg_multi1", "usage": usage}}))
')"
row="$(printf '%s\n' "$multi_iter_line" | run_row)"
cw="$(jq -r .cache_write_tokens <<<"$row" 2>/dev/null)"
cw1h="$(jq -r .cache_write_tokens_1h <<<"$row" 2>/dev/null)"
if [[ "$cw" == "3029" && "$cw1h" == "429" ]]; then
  ok2 "multi-iteration turn sums cache-write breakdown across iterations: cw=3029 cw1h=429 (total 3458, matches the flat field)"
else
  bad2 "multi-iteration turn gave cw=$cw cw1h=$cw1h, expected cw=3029 cw1h=429 -- top-level breakdown (iteration[0] only) used instead of summing across iterations"
fi

# F3 (mh:blind-spot-hunter, round 2): an iteration with cache-write tokens
# but no `cache_creation` breakdown object at all (0 real occurrences, but
# the map's own `// 0` would silently treat it as zero on both cw and cw1h
# with no flat-anchored floor). Top-level flat is the only place these
# tokens are visible; the row must not vanish.
row="$(python3 -c '
import json
iters = [{"type": "message", "input_tokens": 2, "output_tokens": 5, "cache_creation_input_tokens": 1000000}]
usage = {"input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 0,
          "cache_creation_input_tokens": 1000000, "iterations": iters}
print(json.dumps({"type": "assistant", "message": {"model": "claude-opus-5-5", "id": "msg_nobreak1", "usage": usage}}))
' | run_row)"
cw="$(jq -r .cache_write_tokens <<<"$row" 2>/dev/null)"
cw1h="$(jq -r .cache_write_tokens_1h <<<"$row" 2>/dev/null)"
if [[ "$cw" == "1000000" && "$cw1h" == "0" ]]; then
  ok2 "an iteration missing cache_creation entirely still anchors to the top-level flat (cw=1000000), row not dropped"
else
  bad2 "iteration-missing-breakdown case gave cw=$cw cw1h=$cw1h (row=$row), expected cw=1000000 cw1h=0 -- the whole turn's cost went missing"
fi

# F4 (mh:blind-spot-hunter, round 2): Claude Code's background-session
# transcripts copy one message.id across sibling files with every
# top-level counter zeroed on the copies except iterations/cache_creation.
# Summing iterations directly would manufacture real dollars on an
# all-zero row (measured on this machine: 17 real records, +55,743
# tokens); anchoring to the (zero) top-level flat must suppress it.
row="$(python3 -c '
import json
iters = [{"type": "message", "input_tokens": 4, "output_tokens": 209, "cache_creation_input_tokens": 209,
          "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 209}}]
usage = {"input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 0,
          "cache_creation_input_tokens": 0, "iterations": iters}
print(json.dumps({"type": "assistant", "message": {"model": "claude-opus-5-5", "id": "msg_bgcopy1", "usage": usage}}))
' | run_row)"
if [[ -z "$row" ]]; then
  ok2 "a zeroed background-session duplicate copy (real top-level flat=0, iterations nonzero) writes no row at all"
else
  bad2 "zeroed-duplicate-copy case wrote a row when it should have written none: $row"
fi

# F5 (mh:blind-spot-hunter, round 2): an advisor_message iteration bills a
# different model than the turn's primary model. If it carries real
# cache-write tokens (0 real occurrences observed, but the mechanism is
# untested without this), summing it in unfiltered could attribute that
# spend to the wrong row. The flat anchor bounds the damage to "no more
# than the executor's own real total, split may skew" rather than adding
# dollars that were never really billed to this row.
row="$(python3 -c '
import json
iters = [
    {"type": "message", "input_tokens": 2, "output_tokens": 5, "cache_creation_input_tokens": 100,
     "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 100}},
    {"type": "advisor_message", "model": "claude-opus-5", "input_tokens": 2, "output_tokens": 5,
     "cache_creation_input_tokens": 900,
     "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 900}},
]
usage = {"input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 0,
          "cache_creation_input_tokens": 100, "iterations": iters}
print(json.dumps({"type": "assistant", "message": {"model": "claude-sonnet-5", "id": "msg_advisor1", "usage": usage}}))
' | run_row)"
cw="$(jq -r .cache_write_tokens <<<"$row" 2>/dev/null)"
cw1h="$(jq -r .cache_write_tokens_1h <<<"$row" 2>/dev/null)"
if [[ "$cw" == "0" && "$cw1h" == "100" ]]; then
  ok2 "an advisor iteration on a different model cannot push this row's total above its own top-level flat (cw+cw1h=100, not 1000)"
else
  bad2 "advisor-contamination case gave cw=$cw cw1h=$cw1h, expected cw=0 cw1h=100 (total capped at flat=100, not the raw iteration sum of 1000)"
fi

echo "$pass2 passed, $fail2 failed (phase 2)"

pass=$((pass + pass2))
fail=$((fail + fail2))
echo "TOTAL: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
