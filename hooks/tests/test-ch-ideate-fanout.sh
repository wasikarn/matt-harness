#!/usr/bin/bash
# test-ch-ideate-fanout — locks the 2-wave fan-out structure of
# skills/ideate/SKILL.md (PR2 of ideate-adhd-port). The 2026-06-12 audit
# caught a 44→105-agent failure mode where a soft cap on a work-list was
# silently doubled by an audit + verify layer (memory/bounded-agent-spawning.md).
# The ideate skill is engineered to fit the F8.5 cap exactly: Phase 1 (5
# parallel Agent calls) + Phase 2 (host-only) + Phase 3 (3 parallel Agent
# calls) = peak concurrent 5. Collapsing the 2 waves into 1 would either
# overshoot the cap or compress the algorithm. This test fails loudly if
# any of the load-bearing structural markers disappear from the file.

echo
echo "--- ideate 2-wave fan-out structure ---"
_IDEATE_SKILL="$(cd "$(dirname "$0")/../.." && pwd)/skills/ideate/SKILL.md"
if [ ! -f "$_IDEATE_SKILL" ]; then
  FAIL=$((FAIL+1)); printf '  ❌ ideate-fanout          %s\n' "skills/ideate/SKILL.md missing"
else
  for _kw in "## 2-wave fan-out" "Phase 1" "Phase 2" "fan-out" "F8.5" "Do not collapse"; do
    if /usr/bin/grep -qF -- "$_kw" "$_IDEATE_SKILL"; then
      PASS=$((PASS+1)); printf '  ✅ ideate-fanout          %s\n' "contains \"$_kw\""
    else
      FAIL=$((FAIL+1)); printf '  ❌ ideate-fanout          %s (missing "%s")\n' "skills/ideate/SKILL.md" "$_kw"
    fi
  done
fi
