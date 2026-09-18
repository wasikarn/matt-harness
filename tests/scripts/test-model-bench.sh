#!/usr/bin/env bash
# test-model-bench.sh — exercises skills/meta/model-bench/scripts/model-bench-diff.py's
# --diff-only report against static fixtures built to the real aggregate-result.json schema
# (verified against every file under evals/results/ on this machine, not guessed — see the
# plan history in skills/meta/model-bench/SKILL.md). Fixtures are hand-authored rather than
# derived from a live evals/results/ dir at test time: that directory is gitignored, so a
# fresh clone or CI runner has none to derive from.
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
DIFF_PY="$ROOT/skills/meta/model-bench/scripts/model-bench-diff.py"
FIXTURES="$HERE/fixtures/model-bench"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== model-bench-diff.py self-test ==="

# --- clean pair: happy path, per-case table, outer-join, agent-dispatch caveat ---
out=$(python3 "$DIFF_PY" --label-a fixture-a --label-b fixture-b \
  "$FIXTURES/clean-a.json" "$FIXTURES/clean-b.json" 2>&1)
status=$?

if [ "$status" -eq 0 ]; then ok "clean pair: exit 0"; else bad "clean pair: exit $status (expected 0)"; fi

printf '%s\n' "$out" | /usr/bin/grep -qF 'shared-skill-case' \
  && printf '%s\n' "$out" | /usr/bin/grep -qF '+0.050' \
  && ok "clean pair: shared-skill-case delta is +0.050 (0.95 - 0.9)" \
  || bad "clean pair: shared-skill-case delta wrong or missing"

printf '%s\n' "$out" | /usr/bin/grep -qF 'shared-agent-case' \
  && printf '%s\n' "$out" | /usr/bin/grep -qF '+0.200' \
  && ok "clean pair: shared-agent-case delta is +0.200 (0.8 - 0.6)" \
  || bad "clean pair: shared-agent-case delta wrong or missing"

printf '%s\n' "$out" | /usr/bin/grep -qF 'only-in-a: only in fixture-a' \
  && printf '%s\n' "$out" | /usr/bin/grep -qF 'only-in-b: only in fixture-b' \
  && ok "clean pair: outer-join lists both one-sided cases under their real label" \
  || bad "clean pair: outer-join missing a one-sided case"

printf '%s\n' "$out" | /usr/bin/grep -qF 'CAVEAT: 1 of 2 compared cases dispatch a subagent' \
  && ok "clean pair: agent-dispatch caveat counts exactly the 1 case with subagent_type" \
  || bad "clean pair: agent-dispatch caveat count wrong or missing"

printf '%s\n' "$out" | /usr/bin/grep -q 'WARN' \
  && bad "clean pair: printed a WARN with nothing that should mismatch" \
  || ok "clean pair: no spurious WARN"

# --- mismatched pair: judgeModel + caseFilter differ, must WARN not hard-fail ---
out=$(python3 "$DIFF_PY" --label-a fixture-a --label-b fixture-b \
  "$FIXTURES/clean-a.json" "$FIXTURES/mismatch-b.json" 2>&1)
status=$?

if [ "$status" -eq 0 ]; then ok "mismatch pair: exit 0 (WARN, not fatal)"; else bad "mismatch pair: exit $status (expected 0)"; fi

printf '%s\n' "$out" | /usr/bin/grep -qF 'judgeModel differs: fixture-a=sonnet vs fixture-b=haiku' \
  && ok "mismatch pair: WARN on judgeModel sonnet vs haiku" \
  || bad "mismatch pair: judgeModel WARN missing or wrong"

printf '%s\n' "$out" | /usr/bin/grep -qF 'caseFilter differs: fixture-a=model-bench-fixture vs fixture-b=all cases' \
  && ok "mismatch pair: WARN on caseFilter set vs absent(default)" \
  || bad "mismatch pair: caseFilter WARN missing or wrong"

# --- partial arm: must hard-fail, never print a comparison table ---
out=$(python3 "$DIFF_PY" --label-a fixture-a --label-b fixture-b \
  "$FIXTURES/clean-a.json" "$FIXTURES/partial-b.json" 2>&1)
status=$?

if [ "$status" -eq 1 ]; then ok "partial arm: exit 1 (hard-fail)"; else bad "partial arm: exit $status (expected 1)"; fi
printf '%s\n' "$out" | /usr/bin/grep -qF 'HARD-FAIL' \
  && printf '%s\n' "$out" | /usr/bin/grep -qF 'partial run (reason: test-interrupted)' \
  && ok "partial arm: HARD-FAIL names the partialReason" \
  || bad "partial arm: HARD-FAIL message missing or wrong"
printf '%s\n' "$out" | /usr/bin/grep -q 'overallScore\|score=' \
  && bad "partial arm: printed score numbers despite hard-fail (numbers would be misleading)" \
  || ok "partial arm: no score table printed alongside the hard-fail"

# --- zero-case arm: explicit note, no divide-by-zero crash ---
out=$(python3 "$DIFF_PY" --label-a fixture-a --label-b fixture-b \
  "$FIXTURES/clean-a.json" "$FIXTURES/zero-cases.json" 2>&1)
status=$?

if [ "$status" -eq 0 ]; then ok "zero-case arm: exit 0"; else bad "zero-case arm: exit $status (expected 0)"; fi
printf '%s\n' "$out" | /usr/bin/grep -qF 'casesTotal is 0' \
  && ok "zero-case arm: explicit note instead of a crash or misleading 0-vs-0 table" \
  || bad "zero-case arm: missing the casesTotal==0 note"

echo "model-bench-diff.py self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
