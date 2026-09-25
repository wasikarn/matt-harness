#!/usr/bin/env bash
# Unit test for hooks/stop/cost-tracker.sh's rate() model-pricing table.
# Extracts the live `def rate: ... end;` block from the script (so the model
# branches this test checks can't drift out of sync with the real function)
# and asserts each model-family test matches only its own family, not a
# broader sibling whose name it contains (e.g. "opus-5-5" must not fall
# through to "opus"). $sonnet_rate below is a fixed stand-in value the rate
# def expects as an argument, not a pasted copy of a checked branch.
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
  jq -n --argjson sonnet_rate '{"i":2.0,"o":10.0,"cw":2.50,"cr":0.20}' --arg m "$model" \
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

echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
