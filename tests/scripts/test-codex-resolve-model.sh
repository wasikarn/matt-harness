#!/usr/bin/env bash
# test-codex-resolve-model.sh -- scripts/_lib/codex-resolve-model.py against a fixture catalog in a
# throwaway CODEX_HOME, never the real ~/.codex.
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
RESOLVE="$HERE/../../scripts/_lib/codex-resolve-model.py"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }
t() { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
eq() { [ "$1" = "$2" ]; }
ok_with() { [ "$1" -eq 0 ] && [ "$2" = "$3" ]; }
fails_with() { [ "$1" -ne 0 ] && [ -z "$2" ] && grep -q "$4" "$3"; }
clean_error() { [ "$1" -ne 0 ] && [ -z "$2" ] && [ -s "$3" ] && ! grep -q Traceback "$3"; }

T="$(mktemp -d)" || exit 1
trap 'trash "$T"' EXIT
export CODEX_HOME="$T"
cat > "$T/models_cache.json" <<'JSON'
{"models": [
 {"slug":"gpt-9-sol","priority":1,"visibility":"list","supported_reasoning_levels":[{"effort":"low"},{"effort":"medium"}]},
 {"slug":"gpt-8-sol","priority":3,"visibility":"list","supported_reasoning_levels":[{"effort":"low"},{"effort":"medium"},{"effort":"xhigh"}]},
 {"slug":"gpt-hidden-sol","priority":0,"visibility":"hide","supported_reasoning_levels":[{"effort":"medium"}]},
 {"slug":"gpt-5-terra","priority":8,"visibility":"list","supported_reasoning_levels":[{"effort":"medium"}]}
]}
JSON

echo "=== codex-resolve-model.py ==="
out="$(python3 "$RESOLVE" sol)"; rc=$?
t "best visible model of the tier (hidden priority-0 entry skipped)" ok_with "$rc" "$out" gpt-9-sol
t "tier is case-insensitive; a supported effort keeps the best model" eq "$(python3 "$RESOLVE" Sol --effort medium)" gpt-9-sol
t "an effort the best model lacks falls to the next model that lists it" eq "$(python3 "$RESOLVE" sol --effort xhigh)" gpt-8-sol
t "another tier resolves on its own" eq "$(python3 "$RESOLVE" terra)" gpt-5-terra

out="$(python3 "$RESOLVE" sol --effort ultra 2>"$T/err")"; rc=$?
t "no model lists the effort: exit non-zero, no stdout, reason on stderr" fails_with "$rc" "$out" "$T/err" ultra
out="$(python3 "$RESOLVE" astra 2>"$T/err")"; rc=$?
t "unknown tier: exit non-zero, no stdout, reason on stderr" fails_with "$rc" "$out" "$T/err" astra

echo '{not json' > "$T/models_cache.json"
out="$(python3 "$RESOLVE" sol 2>"$T/err")"; rc=$?
t "malformed catalog: clean error, no traceback" clean_error "$rc" "$out" "$T/err"
trash "$T/models_cache.json"
out="$(python3 "$RESOLVE" sol 2>"$T/err")"; rc=$?
t "missing catalog: clean error" fails_with "$rc" "$out" "$T/err" catalog

# fail closed on odd input
cat > "$T/models_cache.json" <<'JSON'
{"models": [{"slug":"gpt-9-sol","priority":1,"visibility":"list","supported_reasoning_levels":[{"effort":"medium"}]}]}
JSON
out="$(python3 "$RESOLVE" sol --effort "" 2>"$T/err")"; rc=$?
t "empty --effort is refused, not treated as no effort" fails_with "$rc" "$out" "$T/err" effort
for body in '{"models": null}' '{"models": 3}' '[1,2]'; do
  printf '%s' "$body" > "$T/models_cache.json"
  out="$(python3 "$RESOLVE" sol 2>"$T/err")"; rc=$?
  t "catalog $body: clean error, no traceback" clean_error "$rc" "$out" "$T/err"
done
cat > "$T/models_cache.json" <<'JSON'
{"models": [{"slug":"gpt-9-sol","priority":1,"visibility":"list","supported_reasoning_levels":3}]}
JSON
out="$(python3 "$RESOLVE" sol --effort medium 2>"$T/err")"; rc=$?
t "supported_reasoning_levels of the wrong type: clean error, no traceback" clean_error "$rc" "$out" "$T/err"
cat > "$T/models_cache.json" <<'JSON'
{"models": [
 {"slug":"gpt-bool-sol","priority":false,"visibility":"list","supported_reasoning_levels":[{"effort":"medium"}]},
 {"slug":"gpt-retiring-sol","priority":0,"visibility":"list","upgrade":{"model":"gpt-ok-sol"},"supported_reasoning_levels":[{"effort":"medium"}]},
 {"slug":"gpt-ok-sol","priority":2,"visibility":"list","supported_reasoning_levels":[{"effort":"medium"}]}]}
JSON
t "a boolean priority and a model with an upgrade field are not chosen" eq "$(python3 "$RESOLVE" sol)" gpt-ok-sol

echo "===$pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
