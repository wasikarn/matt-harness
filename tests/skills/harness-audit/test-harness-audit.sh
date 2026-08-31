#!/usr/bin/env bash
# test-harness-audit.sh — self-test for harness-audit (maker-grades-own-work guard).
#
# The audit's own fragment integrity guard catches LOST checks, not SILENT
# checks. The audit has shipped silent gaps before (v0.35.5 found real ones), so
# this pairs each known-bad fixture with a clean one and asserts the matching
# check FIRES on bad and is SILENT on good. Three checks (Rule 2 — fixtures
# cover the highest-silence-risk checks and prove the self-test mechanism; a
# full fleet-wide fixture suite is speculative):
#   36 — recursive-improve disable-model-invocation flag (CRIT)
#   37 — dead `mh:` reference doc-rot (WARN; exit stays 0 — asserted via the
#        Warnings line, not the exit code)
#   45 — score-decision disable-model-invocation flag (CRIT; added 2026-07-23
#        alongside check 45 itself — the other safety-load-bearing instance of
#        the flag, previously unguarded). Also carries a prose-mention
#        regression fixture (check-45-bad-prose-mention, added the same day
#        by a `compliance-audit` adversarial pass) proving checks 36/45 are
#        frontmatter-scoped, not a raw substring grep.
# (Check numbers above renumbered 2026-08-25, ticket 87, from the pre-cleanup
# 39/40/49/55 — the old numbers this test used before the 8 stubbed checks
# were deleted and the survivors renumbered 1..56.)
set -uo pipefail

HERE="$(cd -P "$(dirname "$0")" && pwd)"
AUDIT="$HERE/../../../skills/meta/harness-audit/scripts/audit.sh"
FIX="$HERE/known-bad"

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  PASS: $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

# run_check <id> <fixture-root>: sets CRIT_FOUND / WARN_FOUND from the audit
# summary lines. Audit may exit non-zero on a CRIT fixture; capture via `|| true`.
CRIT_FOUND=0
WARN_FOUND=0
INFO_FOUND=0
run_check() {
  local id="$1" root="$2" out c w i
  out=$(bash "$AUDIT" "$root" --only "$id" 2>/dev/null || true)
  c=$(printf '%s\n' "$out" | sed -n 's/^Critical: //p')
  w=$(printf '%s\n' "$out" | sed -n 's/^Warnings: //p')
  i=$(printf '%s\n' "$out" | sed -n 's/^Info: *//p')
  CRIT_FOUND="${c:-0}"
  WARN_FOUND="${w:-0}"
  INFO_FOUND="${i:-0}"
}

echo "=== harness-audit self-test ==="

# Check 36 — CRIT must fire when the flag is missing, stay silent when present.
run_check 36 "$FIX/check-36-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-36 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-36 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 36 "$FIX/check-36-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-36 good fixture silent"
else
  bad "check-36 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 37 — WARN must fire on a dead mh: ref, stay silent when it resolves.
run_check 37 "$FIX/check-37-bad"
if [ "$WARN_FOUND" -ge 1 ]; then
  ok "check-37 bad fixture fires WARN (warn=$WARN_FOUND)"
else
  bad "check-37 bad fixture did NOT fire WARN (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 37 "$FIX/check-37-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-37 good fixture silent"
else
  bad "check-37 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 45 — CRIT must fire when the flag is missing, stay silent when present.
run_check 45 "$FIX/check-45-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-45 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-45 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 45 "$FIX/check-45-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-45 good fixture silent"
else
  bad "check-45 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Checks 58-64 — CRIT guards for the 7 disable-model-invocation carriers that
# previously had no equivalent to checks 36/40/45 (2026-08-30 deep-audit
# finding). Same bad/good pattern as check 36 above, one pair per skill.
run_check 58 "$FIX/check-58-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-58 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-58 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 58 "$FIX/check-58-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-58 good fixture silent"
else
  bad "check-58 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

run_check 59 "$FIX/check-59-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-59 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-59 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 59 "$FIX/check-59-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-59 good fixture silent"
else
  bad "check-59 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

run_check 60 "$FIX/check-60-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-60 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-60 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 60 "$FIX/check-60-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-60 good fixture silent"
else
  bad "check-60 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

run_check 61 "$FIX/check-61-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-61 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-61 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 61 "$FIX/check-61-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-61 good fixture silent"
else
  bad "check-61 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

run_check 62 "$FIX/check-62-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-62 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-62 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 62 "$FIX/check-62-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-62 good fixture silent"
else
  bad "check-62 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

run_check 63 "$FIX/check-63-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-63 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-63 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 63 "$FIX/check-63-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-63 good fixture silent"
else
  bad "check-63 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

run_check 64 "$FIX/check-64-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-64 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-64 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 64 "$FIX/check-64-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-64 good fixture silent"
else
  bad "check-64 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 65 — meta-completeness WARN: a new disable-model-invocation carrier
# with no dedicated CRIT-guard check file (no matching _f= line anywhere
# under checks/) must WARN, not CRIT (it's a coverage gap, not proof the flag
# is currently missing); an already-guarded carrier stays silent. The bad
# fixture also proves the check doesn't abort under set -euo pipefail when
# its own scaffolded checks/ dir is absent (2026-08-30 deep-audit finding —
# same pipefail-glob regression class check 25 already guards against).
run_check 65 "$FIX/check-65-bad"
if [ "$WARN_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-65 bad fixture fires WARN, no abort (warn=$WARN_FOUND)"
else
  bad "check-65 bad fixture did NOT fire WARN as expected (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 65 "$FIX/check-65-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-65 good fixture silent"
else
  bad "check-65 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Regression test — a `compliance-audit` adversarial pass (2026-07-23) found
# the raw `head -20 | grep -qF` form (checks 36/45's original shape)
# false-negatives when the literal flag string appears only in prose (e.g.
# `description:`) with the real key absent. Both checks were fixed to use
# frontmatter-scoped `fm_get` instead; this fixture proves the fix.
run_check 45 "$FIX/check-45-bad-prose-mention"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-45 prose-mention regression fixture still fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-45 prose-mention regression fixture did NOT fire CRIT — the frontmatter-scoping fix has regressed (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 25 — pipefail-abort regression guard. The plugin-cache glob added
# 2026-08-09 (v0.68.231) once shipped with no directory guard: on a $HOME
# with no ~/.claude/plugins/cache yet, the unmatched multi-level glob failed
# its own `[ -d ]` test and, under `set -euo pipefail` in a sourced check,
# silently aborted the whole audit mid-run (no "=== Summary ===" line at
# all). Fixed with a scoped nullglob toggle; this fixture proves the fix by
# running check 25 in isolation against a $HOME with zero plugin cache dirs
# and asserting the run completes (prints a Summary) instead of aborting.
FAKE_HOME_NO_CACHE=$(mktemp -d)
CHECK25_OUT=$(HOME="$FAKE_HOME_NO_CACHE" bash "$AUDIT" "$HERE/../../.." --only 25 2>&1 || true)
trash "$FAKE_HOME_NO_CACHE" 2>/dev/null || true
if printf '%s\n' "$CHECK25_OUT" | grep -q "=== Summary"; then
  ok "check-25 survives a \$HOME with no plugin cache (no pipefail abort)"
else
  bad "check-25 aborted before printing a Summary against an empty-cache \$HOME — nullglob regression:
$CHECK25_OUT"
fi

# Check 50 — mattpocock-skills integration refs (A refs resolve / B flag
# claims / C coverage ledger / D gated-ref phrasing). The check reads the
# mattpocock plugin cache from $MH_MATT_CACHE when set (fixture override;
# real runs default to ~/.claude/plugins/cache/mattpocock/mattpocock-skills).
export MH_MATT_CACHE="$FIX/check-50-bad/fake-matt-cache"
run_check 50 "$FIX/check-50-bad"
if [ "$WARN_FOUND" -ge 3 ] && [ "$INFO_FOUND" -ge 2 ]; then
  ok "check-50 bad fixture fires A+B+C WARNs and D INFOs incl. marker-masking regression (warn=$WARN_FOUND info=$INFO_FOUND)"
else
  bad "check-50 bad fixture did NOT fire all sub-checks (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND; need warn>=3 info>=2 — info=1 means the free-text-marker masking regressed)"
fi
# Manifest-drift regression (adversarial finding 2026-08-10): plugin.json's
# skills array in an unrecognized format (object entries) must FAIL CLOSED —
# a parse-blind WARN — never a vacuous sub-check-C pass. Same fixture also
# carries a duplicate ledger row, which must fire its own WARN.
export MH_MATT_CACHE="$FIX/check-50-bad-manifest-drift/fake-matt-cache"
run_check 50 "$FIX/check-50-bad-manifest-drift"
if [ "$WARN_FOUND" -ge 2 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-50 manifest-drift fixture fails closed (parse-blind + duplicate-row WARNs, warn=$WARN_FOUND)"
else
  bad "check-50 manifest-drift fixture did NOT fail closed (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND; need warn>=2 — 0 means sub-check C went vacuously green on a drifted manifest)"
fi
export MH_MATT_CACHE="$FIX/check-50-good/fake-matt-cache"
run_check 50 "$FIX/check-50-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ] && [ "$INFO_FOUND" -eq 0 ]; then
  ok "check-50 good fixture silent"
else
  bad "check-50 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi
# Graceful skip: no mattpocock cache at all → INFO note only, never WARN/CRIT,
# and the run completes (same class of guard as the check-25 nullglob test).
export MH_MATT_CACHE="$FIX/check-50-good/no-such-cache"
run_check 50 "$FIX/check-50-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ] && [ "$INFO_FOUND" -ge 1 ]; then
  ok "check-50 gracefully skips when no mattpocock cache exists (info=$INFO_FOUND)"
else
  bad "check-50 missing-cache run not a graceful skip (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi
unset MH_MATT_CACHE

# Check 50 sub-check C — pipefail-abort regression guard (2026-08-30 drill-down).
# `_row=$(grep -E ... "$_ledger" 2>/dev/null | head -1)` at line ~125 had no
# `|| true`: a promoted matt skill entirely absent from the ledger — the exact
# state right after an upstream rename, before the ledger catches up, i.e. the
# scenario this sub-check exists to catch — makes grep exit 1, pipefail
# propagates through head, and set -e kills the whole audit.sh process with no
# `=== Summary` line. Same class of guard as the check-39 test above, but
# run_check()'s Critical/Warnings/Info parse can't detect this failure mode: on
# a crash those lines never print, so run_check() silently reports 0/0/0,
# indistinguishable from "check ran clean" — hence the raw-output capture here
# instead of routing through run_check().
export MH_MATT_CACHE="$FIX/check-50-crash-ledger-gap/fake-matt-cache"
CHECK50C_OUT=$(bash "$AUDIT" "$FIX/check-50-crash-ledger-gap" --only 50 2>&1 || true)
unset MH_MATT_CACHE
if printf '%s\n' "$CHECK50C_OUT" | grep -q "ledger row missing for promoted matt skill 'foo'" \
   && printf '%s\n' "$CHECK50C_OUT" | grep -q "=== Summary"; then
  ok "check-50 crash-ledger-gap fixture: sub-check C warns without crashing (pipefail regression)"
else
  bad "check-50 crash-ledger-gap fixture crashed or missed the WARN:
$CHECK50C_OUT"
fi

# Check 39 — grep -c pipefail-abort regression guard (2026-08-17 bug sweep).
# `_count=$(grep -c ... 2>/dev/null)` with no `|| true` dies under set -e when
# the pattern legitimately has zero matches — the exact doc-rot condition this
# check exists to WARN about, so the crash hides the one case it should catch.
# Same class of guard as the check-25 test above: assert the run completes
# (prints a Summary) instead of aborting mid-source.
FAKE39=$(mktemp -d)
mkdir -p "$FAKE39/skills/workflow/orchestrate" "$FAKE39/docs"
cat > "$FAKE39/skills/workflow/orchestrate/SKILL.md" <<'EOF'
# orchestrate
no matching content in this fixture
EOF
cat > "$FAKE39/docs/common-mistakes.md" <<'EOF'
Self-check: `grep -c "this-pattern-does-not-exist-anywhere" "skills/workflow/orchestrate/SKILL.md"`
EOF
CHECK39_OUT=$(bash "$AUDIT" "$FAKE39" --only 39 2>&1 || true)
trash "$FAKE39" 2>/dev/null || true
if printf '%s\n' "$CHECK39_OUT" | grep -q "=== Summary"; then
  ok "check-39 survives a zero-match self-check pattern (no pipefail abort)"
else
  bad "check-39 aborted before printing a Summary on a zero-match pattern — grep -c/set -e regression:
$CHECK39_OUT"
fi

# Check 56 — diagram content/export/a11y drift. Sub-check B (export
# freshness) walks two hops via git status: html->svg and svg->png. A
# deep-audit pass (2026-08-28) found the first cut only walked svg->png —
# editing the .html source (every diagram's actual authored source) with no
# svg/png touch produced zero warnings. These fixtures prove both hops fire,
# and that a properly-completed re-export (both hops touched) stays silent.
# Built as a real git repo, not the read-only fixture dirs above, because
# sub-check B's whole mechanism is `git status --porcelain` — there is no
# way to simulate "dirty relative to HEAD" without an actual commit history.
_mk56fixture() {
  local root
  root=$(mktemp -d)
  mkdir -p "$root/.claude-plugin" "$root/hooks/advisory" "$root/docs/diagrams"
  printf '{"name": "mh"}\n' > "$root/.claude-plugin/plugin.json"
  printf '{"hooks": {}}\n' > "$root/hooks/hooks.json"
  printf '[]\n' > "$root/hooks/pretooluse-table.json"
  printf '<html><svg></svg></html>\n' > "$root/docs/diagrams/fixture-diagram.html"
  printf '<svg xmlns="http://www.w3.org/2000/svg"></svg>\n' > "$root/docs/diagrams/fixture-diagram.svg"
  printf 'not-a-real-png-just-needs-to-exist\n' > "$root/docs/diagrams/fixture-diagram.png"
  git -C "$root" init -q
  git -C "$root" -c user.email=test@test -c user.name=test add -A
  git -C "$root" -c user.email=test@test -c user.name=test commit -q -m "baseline"
  printf '%s' "$root"
}

# Hop 1 (html -> svg): edit html only, leave svg/png untouched.
FIX56_A=$(_mk56fixture)
printf '<html><svg>EDITED</svg></html>\n' > "$FIX56_A/docs/diagrams/fixture-diagram.html"
CHECK56_A_OUT=$(bash "$AUDIT" "$FIX56_A" --only 56 2>&1 || true)
trash "$FIX56_A" 2>/dev/null || true
if printf '%s\n' "$CHECK56_A_OUT" | grep -q "fixture-diagram.html changed but .*fixture-diagram.svg wasn't re-exported"; then
  ok "check-56 catches an html-only edit (svg never re-exported)"
else
  bad "check-56 did NOT catch an html-only edit — the html->svg hop has regressed:
$CHECK56_A_OUT"
fi

# Hop 2 (svg -> png): edit svg only, leave png untouched.
FIX56_B=$(_mk56fixture)
printf '<svg xmlns="http://www.w3.org/2000/svg">EDITED</svg>\n' > "$FIX56_B/docs/diagrams/fixture-diagram.svg"
CHECK56_B_OUT=$(bash "$AUDIT" "$FIX56_B" --only 56 2>&1 || true)
trash "$FIX56_B" 2>/dev/null || true
if printf '%s\n' "$CHECK56_B_OUT" | grep -q "fixture-diagram.svg changed but .*fixture-diagram.png wasn't re-exported"; then
  ok "check-56 catches an svg-only edit (png never re-exported)"
else
  bad "check-56 did NOT catch an svg-only edit — the svg->png hop has regressed:
$CHECK56_B_OUT"
fi

# All three files touched (a real, correct re-export) — must stay silent
# about export freshness. Touching only html+svg (forgetting the png) would
# be a real bug this same check should catch via hop 2 — don't under-test it.
FIX56_C=$(_mk56fixture)
printf '<html><svg>EDITED</svg></html>\n' > "$FIX56_C/docs/diagrams/fixture-diagram.html"
printf '<svg xmlns="http://www.w3.org/2000/svg">EDITED</svg>\n' > "$FIX56_C/docs/diagrams/fixture-diagram.svg"
printf 'not-a-real-png-just-needs-to-exist-EDITED\n' > "$FIX56_C/docs/diagrams/fixture-diagram.png"
CHECK56_C_OUT=$(bash "$AUDIT" "$FIX56_C" --only 56 2>&1 || true)
trash "$FIX56_C" 2>/dev/null || true
if printf '%s\n' "$CHECK56_C_OUT" | grep -q "wasn't re-exported"; then
  bad "check-56 false-positived on a fully re-exported diagram (both hops touched):
$CHECK56_C_OUT"
else
  ok "check-56 stays silent when both export hops are touched"
fi
unset -f _mk56fixture

# Regression guard for the sub-check C finding-count bug (deep-audit,
# 2026-08-28): `case "$out" in *"0 finding"*)` is a false-negative trap —
# "10 finding(s)" and "20 finding(s)" both contain the literal substring
# "0 finding", so a real double-digit geometry failure would silently pass
# as clean. Tested as an isolated snippet (not a full fixture run) because
# forcing verify-geometry.py itself to emit >=10 real findings would depend
# on diagram-design plugin internals this repo doesn't control or bundle.
# Messages already contain a colon ("Summary: ..."), so a colon-joined
# "msg:want" pair can't be split on ":" without truncating the message
# itself — caught by this test's own first draft failing for the wrong
# reason. Parallel arrays instead, indexed together.
_geom56_msgs=(
  "Summary: 1 file(s) checked, 0 finding(s)."
  "Summary: 1 file(s) checked, 10 finding(s)."
  "Summary: 1 file(s) checked, 20 finding(s)."
  "garbage with no count"
)
_geom56_want=("0" "10" "20" "")
_geomcount_regression_ok=1
for _i in "${!_geom56_msgs[@]}"; do
  _msg="${_geom56_msgs[$_i]}"
  _want="${_geom56_want[$_i]}"
  _got=$(printf '%s' "$_msg" | grep -oE '[0-9]+ finding' | grep -oE '^[0-9]+' | head -1)
  if [ "${_got:-}" != "$_want" ]; then
    _geomcount_regression_ok=0
    bad "check-56 geometry-count extraction: '$_msg' -> got '${_got:-<empty>}', want '${_want:-<empty>}'"
  fi
done
unset _i _geom56_msgs _geom56_want
if [ "$_geomcount_regression_ok" -eq 1 ]; then
  ok "check-56 geometry-count extraction correctly rejects 10/20-finding outputs (not fooled by the '0 finding' substring)"
fi
unset _msg _want _got _geomcount_regression_ok

# Check 04 — agent bucket enum validation (2026-08-31 drill-down finding: a
# typo like `bucket: reveiw` passed the old non-empty-only check silently,
# degrading BOUNDARY.md's grouping with zero warning — same "magic string
# typo-checks clean" shape as the Vercel Workflow SDK community critique this
# fix was prompted by). WARN, not CRIT — matches the existing missing-bucket
# severity (grouping-only impact, doesn't break agent loading).
run_check 04 "$FIX/check-04-bad-bucket-enum"
if [ "$WARN_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-04 bad-bucket-enum fixture fires WARN (warn=$WARN_FOUND)"
else
  bad "check-04 bad-bucket-enum fixture did NOT fire WARN as expected (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 04 "$FIX/check-04-good-bucket-enum"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-04 good-bucket-enum fixture silent"
else
  bad "check-04 good-bucket-enum fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

echo ""
echo "self-test: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0