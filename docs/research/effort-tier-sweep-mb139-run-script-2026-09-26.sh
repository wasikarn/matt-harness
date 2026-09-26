#!/usr/bin/env bash
# mb139_run.sh — re-run of mb78's A/B effort sweep, fixed: adds --scaffold (mb78 never passed it,
# so no case's fixture file was ever created) and uses the now-fixed eval-default-enabled.sh
# helper (bash, signal-safe) instead of leaving defaultEnabled unmanaged.
set -uo pipefail
cd ~/Codes/Personals/matt-harness || { echo "cd failed"; exit 1; }
source scripts/_lib/eval-default-enabled.sh
OUT=/private/tmp/claude-501/-Users-kobig-Codes-Personals-dotfiles/28d9265b-ad93-497c-80d1-bd86498321bb/scratchpad/mb139-results
mkdir -p "$OUT"
CEIL=3.00

# agent:field:alt_value  (field is "effort"; ideate-critic excluded, its evals are prompt-only,
# no scaffold dependency, already validated in the mb78 sweep)
PLAN=(
  "backend-architect:effort:medium"
  "code-architect:effort:medium"
  "requirement-analyst:effort:medium"
  "blind-spot-hunter:effort:high"
  "plan-reviewer:effort:high"
)

revert() { git checkout -- "agents/${1}.md" 2>/dev/null || true; }
# shellcheck disable=SC2154  # e/a are the for-loop's own locals inside this trap string, not undeclared
trap 'for e in "${PLAN[@]}"; do a="${e%%:*}"; revert "$a"; done' EXIT

for entry in "${PLAN[@]}"; do
  agent="${entry%%:*}"; rest="${entry#*:}"; field="${rest%%:*}"; alt="${rest#*:}"
  f="agents/${agent}.md"
  base_val=$(/usr/bin/grep -m1 "^${field}:" "$f" | cut -d' ' -f2)
  echo "== $agent  field=$field  baseline=$base_val  alt=$alt  =="

  echo "-- baseline run --"
  with_default_enabled_true claude plugin eval . --case "${agent}-*" --scaffold --runs 1 -j 3 --no-publish \
    --max-cost-usd "$CEIL" --output-dir "$OUT/${agent}-baseline" \
    > "$OUT/${agent}-baseline.log" 2>&1
  echo "baseline exit=$?"

  python3 -c "
import re, sys
p = '$f'; field = '$field'; alt = '$alt'
s = open(p).read()
s2 = re.sub(rf'(?m)^{field}: .*$', f'{field}: {alt}', s, count=1)
assert s2 != s, 'frontmatter field not replaced'
open(p, 'w').write(s2)
"
  echo "-- alt run ($field=$alt) --"
  with_default_enabled_true claude plugin eval . --case "${agent}-*" --scaffold --runs 1 -j 3 --no-publish \
    --max-cost-usd "$CEIL" --output-dir "$OUT/${agent}-alt" \
    > "$OUT/${agent}-alt.log" 2>&1
  echo "alt exit=$?"

  revert "$agent"
  echo "-- reverted $agent --"
done

echo "ALL DONE"
git status --short agents/
