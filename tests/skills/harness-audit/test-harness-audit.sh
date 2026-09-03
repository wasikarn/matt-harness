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
#
# 2026-09-01 addition — checks 05, 20, 28, 34, 47, 53 (all edited or created
# the same session) had zero fixture coverage; a silent regression in any of
# them would be indistinguishable from "clean" on the live fleet. Fixtures
# added below, same known-bad/known-good pairing convention:
#   05 — skill trigger-pattern clause (WARN) + the desc_len==20 boundary
#   20 — description length >1536 chars (WARN) + 20.5 duplicate-surface twin
#   28 — malformed YAML frontmatter on a bucketed 2-level path (CRIT)
#   34 — matt-doctrine leading-word rule (INFO-only)
#   47 — disambiguation clause, promoted INFO->WARN this session, plus the
#        harness-audit self-reference carve-out inherited from check 05
#   53 — cross-file content drift (WARN) via a Jaccard-similarity pair
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

# Checks 61/62/64 — CRIT guards for the disable-model-invocation carriers
# that previously had no equivalent to checks 36/40/45 (2026-08-30 deep-audit
# finding). Same bad/good pattern as check 36 above, one pair per skill.
# Checks 58 (ideate-search), 59 (tiered-pipeline), 60 (wiki-ingest), and 63
# (ship-release) were retired 2026-09-01 as their carrier skills left the
# plugin — both the check files and these test sections went with them.
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

# Check 67 — composer-not-creator sourcing (GH #119): a new surface whose
# name/description resembles a mattpocock-skills ledger entry must WARN
# unless it carries the literal `composer-not-creator: checked, genuinely
# new` marker. Bad fixture collides twice (name: code-implementer vs
# implement; description: domain-modeling); good fixture is the same
# content plus the marker.
run_check 67 "$FIX/check-67-bad"
if [ "$WARN_FOUND" -ge 2 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-67 bad fixture fires both WARNs (warn=$WARN_FOUND)"
else
  bad "check-67 bad fixture did NOT fire 2 WARNs as expected (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 67 "$FIX/check-67-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-67 good fixture (marker present) silent"
else
  bad "check-67 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 68 — obsolete prompt patterns in bodies (INFO only): bad fixture has
# "step by step" in an agent body and "MUST ALWAYS" in a skill body; good
# fixture is the same frontmatter with clean bodies.
run_check 68 "$FIX/check-68-bad"
if [ "$INFO_FOUND" -ge 2 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-68 bad fixture fires INFOs (info=$INFO_FOUND)"
else
  bad "check-68 bad fixture did NOT fire >=2 INFOs as expected (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi
run_check 68 "$FIX/check-68-good"
if [ "$INFO_FOUND" -eq 0 ] && [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-68 good fixture silent"
else
  bad "check-68 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi

# Check 29 — agents/*.md description: is now scanned too, and NEVER joined
# the imperative list (2026-09-03).
run_check 29 "$FIX/check-29-bad"
if [ "$INFO_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-29 bad fixture (NEVER in agent description) fires INFO (info=$INFO_FOUND)"
else
  bad "check-29 bad fixture did NOT fire INFO for NEVER in agent description (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
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
# Sub-check E (2026-08-31) — bare backtick + bare slash matt-skill names with
# no mattpocock-skills: prefix must fire INFO; the correctly-namespaced forms
# on the same fixture's adversarial-clean line must not add extra findings.
export MH_MATT_CACHE="$FIX/check-50-bad-bare-token/fake-matt-cache"
run_check 50 "$FIX/check-50-bad-bare-token"
if [ "$INFO_FOUND" -ge 2 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-50 sub-check E fires on bare backtick + bare slash matt-skill names (info=$INFO_FOUND)"
else
  bad "check-50 sub-check E did not fire as expected (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND; need info>=2)"
fi
# Sub-check F (2026-08-31) — a ledger row still marked "deferred" while a live
# surface already references that skill must WARN (ledger prose drift).
export MH_MATT_CACHE="$FIX/check-50-bad-ledger-drift/fake-matt-cache"
run_check 50 "$FIX/check-50-bad-ledger-drift"
if [ "$WARN_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-50 sub-check F fires on deferred-but-referenced ledger row (warn=$WARN_FOUND)"
else
  bad "check-50 sub-check F did not fire on ledger prose drift (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND; need warn>=1)"
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

# Check 04 — self-inflicted regression guard (2026-08-31 deep-audit): the enum
# check above compares the raw frontmatter value with no normalization, so a
# case variant or incidental trailing whitespace — neither a real typo — false
# positives as "unrecognized bucket". Empirically confirmed against a scratch
# fixture before this test was written (bucket: Review and bucket: "review "
# both fired a bogus WARN). These prove the fix trims whitespace and folds
# case before comparing.
run_check 04 "$FIX/check-04-good-bucket-case-insensitive"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-04 good-bucket-case-insensitive fixture silent (Review == review)"
else
  bad "check-04 good-bucket-case-insensitive fixture not silent — case-sensitivity false positive (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 04 "$FIX/check-04-good-bucket-trailing-whitespace"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-04 good-bucket-trailing-whitespace fixture silent"
else
  bad "check-04 good-bucket-trailing-whitespace fixture not silent — untrimmed whitespace false positive (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 04 — completeness gap closed (2026-08-31 deep-audit): these 3 branches
# were only spot-checked manually during the audit, never locked in as
# fixtures. Without them, a future edit to this check's trim/enum logic could
# silently reintroduce the exact bugs just fixed above with nothing to catch it.
run_check 04 "$FIX/check-04-good-bucket-quoted"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-04 good-bucket-quoted fixture silent (YAML-quoted value still recognized)"
else
  bad "check-04 good-bucket-quoted fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 04 "$FIX/check-04-bad-bucket-missing"
if [ "$WARN_FOUND" -ge 1 ]; then
  ok "check-04 bad-bucket-missing fixture fires WARN (warn=$WARN_FOUND)"
else
  bad "check-04 bad-bucket-missing fixture did NOT fire WARN (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 04 "$FIX/check-04-bad-bucket-whitespace-only"
if [ "$WARN_FOUND" -eq 1 ]; then
  ok "check-04 bad-bucket-whitespace-only fixture fires exactly 1 WARN (missing, not unrecognized)"
else
  bad "check-04 bad-bucket-whitespace-only fixture fired warn=$WARN_FOUND (want exactly 1 — either silent, or both missing+unrecognized fired)"
fi

# Check 05 — trigger-pattern clause. WARN when a routing-length description
# (>20 chars) has no "Use when…" style clause; silent when it does; silent
# at the desc_len==20 boundary (too short to carry routing text at all, so
# the routing sub-check must not even run).
run_check 05 "$FIX/check-05-bad-no-trigger"
if [ "$WARN_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-05 bad-no-trigger fixture fires WARN (warn=$WARN_FOUND)"
else
  bad "check-05 bad-no-trigger fixture did NOT fire WARN as expected (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 05 "$FIX/check-05-good-with-trigger"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-05 good-with-trigger fixture silent"
else
  bad "check-05 good-with-trigger fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 05 "$FIX/check-05-good-boundary-desc-len-20"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-05 good-boundary-desc-len-20 fixture silent (desc_len==20 skips the routing sub-check)"
else
  bad "check-05 good-boundary-desc-len-20 fixture not silent — desc_len boundary regressed (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 20 — description length (>1536 chars WARN) and the 20.5 duplicate-
# surface detector (two surfaces sharing the same `name:` with near-identical
# descriptions WARN; sharing a name with genuinely different descriptions —
# a legitimate skill+agent twin — stays silent).
run_check 20 "$FIX/check-20-bad-long-desc"
if [ "$WARN_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-20 bad-long-desc fixture fires WARN (warn=$WARN_FOUND)"
else
  bad "check-20 bad-long-desc fixture did NOT fire WARN as expected (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 20 "$FIX/check-20-good-short-desc"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-20 good-short-desc fixture silent"
else
  bad "check-20 good-short-desc fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 20 "$FIX/check-20-bad-duplicate-surface"
if [ "$WARN_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-20 bad-duplicate-surface fixture fires WARN (warn=$WARN_FOUND)"
else
  bad "check-20 bad-duplicate-surface fixture did NOT fire WARN as expected (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 20 "$FIX/check-20-good-duplicate-distinct"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-20 good-duplicate-distinct fixture silent (same name, distinct descriptions — legitimate twin)"
else
  bad "check-20 good-duplicate-distinct fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 28 — frontmatter YAML strict-parse validity on the BUCKETED
# (skills/<bucket>/<name>/SKILL.md, 2-level) path. CRIT on genuinely broken
# YAML; silent on well-formed frontmatter. (The separate 3-level-nesting
# blind spot this same deep-audit found is fixed directly in the check
# script elsewhere this session — out of scope here.)
run_check 28 "$FIX/check-28-bad-malformed-yaml"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-28 bad-malformed-yaml fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-28 bad-malformed-yaml fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 28 "$FIX/check-28-good-valid-yaml"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-28 good-valid-yaml fixture silent"
else
  bad "check-28 good-valid-yaml fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 34 — matt doctrine conformance, leading-word rule (INFO-only,
# never WARN/CRIT). A description opening with a non-vocabulary word must
# INFO; opening with an allowlisted term (matt or kbg-native) stays silent.
run_check 34 "$FIX/check-34-bad-leadword"
if [ "$INFO_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-34 bad-leadword fixture fires INFO (info=$INFO_FOUND)"
else
  bad "check-34 bad-leadword fixture did NOT fire INFO as expected (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi
run_check 34 "$FIX/check-34-good-leadword"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ] && [ "$INFO_FOUND" -eq 0 ]; then
  ok "check-34 good-leadword fixture silent"
else
  bad "check-34 good-leadword fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi

# Check 47 — skill disambiguation clause. Promoted INFO->WARN 2026-09-01
# (absorbed check 05's negation-clause half); a missing "don't use for X"
# clause must now WARN, not INFO. Also confirms the harness-audit
# self-reference carve-out (carried forward from check 05) stays silent even
# with no disambiguation clause.
run_check 47 "$FIX/check-47-bad-no-disambig"
if [ "$WARN_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-47 bad-no-disambig fixture fires WARN, confirming the INFO->WARN promotion (warn=$WARN_FOUND)"
else
  bad "check-47 bad-no-disambig fixture did NOT fire WARN as expected — INFO->WARN promotion may have regressed (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 47 "$FIX/check-47-good-with-disambig"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-47 good-with-disambig fixture silent"
else
  bad "check-47 good-with-disambig fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 47 "$FIX/check-47-good-harness-audit-carveout"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-47 good-harness-audit-carveout fixture silent (self-reference carve-out holds with no disambiguation clause)"
else
  bad "check-47 good-harness-audit-carveout fixture not silent — self-reference carve-out regressed (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 53 — cross-file content drift. A near-duplicate paragraph pair
# (J=0.71, inside the 0.60-0.95 drift band, not in accepted-duplication.tsv)
# must WARN; a similar-length, similar-opening but genuinely different-topic
# pair (J=0.10, below the 0.60 floor) must stay silent.
run_check 53 "$FIX/check-53-bad-drift"
if [ "$WARN_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-53 bad-drift fixture fires WARN (warn=$WARN_FOUND)"
else
  bad "check-53 bad-drift fixture did NOT fire WARN as expected (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 53 "$FIX/check-53-good-nodrift"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-53 good-nodrift fixture silent (below the Jaccard drift floor)"
else
  bad "check-53 good-nodrift fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

echo ""
echo "self-test: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0