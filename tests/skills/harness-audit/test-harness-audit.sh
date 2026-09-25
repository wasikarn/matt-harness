#!/usr/bin/env bash
# test-harness-audit.sh: self-test for harness-audit (maker-grades-own-work guard).
#
# audit.sh's fragment integrity guard catches LOST checks, not SILENT ones. Each
# known-bad fixture below is paired with a clean one; the matching check must
# FIRE on bad and stay SILENT on good. Per-check fixtures cover 04, 05, 20, 22, 28, 29, 54,
# 70, 71, 72, 73, 74 (five fixtures, two added 2026-09-21), 75, 76, 77; the fleet-bad / fleet-good pair covers the other sixteen with at
# least one defect per check (43 is driven by the env ceiling, not a planted defect).
# check-73-bad-missing-command-field and check-73-bad-args-fingerprint-mismatch (below) are
# deep-audit fixes, 2026-09-10: a Codex-primary fresh-context checker found the original check
# 73 silently passed a handler missing its "command" field, and never compared the "args" field
# (a real, documented command-hook field, exec form) -- both independently reproduced before fix.
set -uo pipefail

HERE="$(cd -P "$(dirname "$0")" && pwd)"
AUDIT="$HERE/../../../skills/meta/harness-audit/scripts/audit.sh"
FIX="$HERE/known-bad"
# shellcheck source=../../../scripts/_lib/codex-state-path.sh
. "$HERE/../../../scripts/_lib/codex-state-path.sh"

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  PASS: $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

CRIT_FOUND=0
WARN_FOUND=0
INFO_FOUND=0
OUT=""
run_check() {
  local id="$1" root="$2" out c w i
  shift 2
  out=$(bash "$AUDIT" "$root" --only "$id" "$@" 2>/dev/null || true)
  OUT="$out"
  # A missing fixture dir, a crash, or a bad invocation produces no "=== Summary" block and
  # empty Critical:/Warnings:/Info: lines -- which used to parse as a silent 0/0/0, letting
  # expect_silent pass on a fixture that never actually ran (mh:deep-audit F2, 2026-09-24).
  # -1 fails every expect_* function's own condition (silent needs ==0, warn/crit need >=1),
  # so one guard here covers every caller instead of touching each expect_* individually.
  if ! printf '%s\n' "$out" | /usr/bin/grep -q '^=== Summary'; then
    bad "run_check $id $root: audit produced no '=== Summary' block (missing fixture, crash, or bad args) -- forcing failure"
    CRIT_FOUND=-1; WARN_FOUND=-1; INFO_FOUND=-1
    return
  fi
  c=$(printf '%s\n' "$out" | sed -n 's/^Critical: //p')
  w=$(printf '%s\n' "$out" | sed -n 's/^Warnings: //p')
  i=$(printf '%s\n' "$out" | sed -n 's/^Info: *//p')
  CRIT_FOUND="${c:-0}"
  WARN_FOUND="${w:-0}"
  INFO_FOUND="${i:-0}"
}
# expect <id> <fixture> <crit-cond> <warn-cond> <label>: run and assert.
expect_silent() {
  run_check "$1" "$FIX/$2" "${@:3}"
  if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then ok "check-$1 $2 silent"
  else bad "check-$1 $2 not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"; fi
}
expect_silent_match() {
  run_check "$1" "$FIX/$2"
  if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ] && printf '%s\n' "$OUT" | /usr/bin/grep -qE "$3"; then ok "check-$1 $2 silent and reports '$3'"
  else bad "check-$1 $2 not silent or missing '$3' (crit=$CRIT_FOUND warn=$WARN_FOUND)"; fi
}
# expect_info_only <id> <fixture>: the fail-open branches emit exactly INFO, never WARN/CRIT.
expect_info_only() {
  run_check "$1" "$FIX/$2"
  if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ] && [ "$INFO_FOUND" -ge 1 ]; then ok "check-$1 $2 fails open as INFO ($3)"
  else bad "check-$1 $2 did not fail open as INFO ($3) (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"; fi
}
expect_warn() {
  run_check "$1" "$FIX/$2" "${@:3}"
  if [ "$WARN_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then ok "check-$1 $2 fires WARN (warn=$WARN_FOUND)"
  else bad "check-$1 $2 did NOT fire WARN (crit=$CRIT_FOUND warn=$WARN_FOUND)"; fi
}
# expect_warn_match <id> <fixture> <regex>: WARN fires AND names the specific defect, not just any WARN.
expect_warn_match() {
  run_check "$1" "$FIX/$2"
  if [ "$WARN_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ] && printf '%s\n' "$OUT" | /usr/bin/grep -qE "$3"; then ok "check-$1 $2 fires WARN and reports '$3'"
  else bad "check-$1 $2 did not fire WARN or missing '$3' (crit=$CRIT_FOUND warn=$WARN_FOUND)"; fi
}
expect_crit() {
  run_check "$1" "$FIX/$2" "${@:3}"
  if [ "$CRIT_FOUND" -ge 1 ]; then ok "check-$1 $2 fires CRIT (crit=$CRIT_FOUND)"
  else bad "check-$1 $2 did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"; fi
}

echo "=== harness-audit self-test ==="

# Check 04: agent bucket enum. Typos WARN; case variants, quoting, and trailing
# whitespace are not typos; whitespace-only is "missing", exactly one WARN.
expect_warn   04 check-04-bad-bucket-enum
expect_silent 04 check-04-good-bucket-enum
expect_silent 04 check-04-good-bucket-case-insensitive
expect_silent 04 check-04-good-bucket-trailing-whitespace
expect_silent 04 check-04-good-bucket-quoted
expect_warn   04 check-04-bad-bucket-missing
run_check 04 "$FIX/check-04-bad-bucket-whitespace-only"
if [ "$WARN_FOUND" -eq 1 ]; then
  ok "check-04 bad-bucket-whitespace-only fires exactly 1 WARN (missing, not unrecognized)"
else
  bad "check-04 bad-bucket-whitespace-only fired warn=$WARN_FOUND (want exactly 1)"
fi

# Check 32: reviewer read-only invariant, bucket-field path. fleet-bad's
# bad-reviewer.md already covers the name-substring path; this pair proves the
# 2026-09-20 fix — an unmatched name with bucket: review/analysis must still
# fire CRIT on a Write/Edit grant, and stay silent when read-only.
expect_crit   32 check-32-bad-bucket
expect_silent 32 check-32-good-bucket

# Check 05: trigger-pattern clause. WARN when a routing-length description has
# no "Use when" clause; silent at the desc_len==20 boundary.
expect_warn   05 check-05-bad-no-trigger
expect_silent 05 check-05-good-with-trigger
expect_silent 05 check-05-good-boundary-desc-len-20

# Check 20: description length (>1536 chars WARN) and the duplicate-surface twin.
expect_warn   20 check-20-bad-long-desc
expect_silent 20 check-20-good-short-desc
expect_warn   20 check-20-bad-duplicate-surface
expect_silent 20 check-20-good-duplicate-distinct

# Check 22: hooks/hooks.json event/type/matcher validity (plugin mode; used to
# be gated on settings.json and passed vacuously in the plugin repo).
expect_warn   22 check-22-bad-hooks-json
expect_silent 22 check-22-good-hooks-json

# Check 28: strict YAML frontmatter on the bucketed 2-level path.
expect_crit   28 check-28-bad-malformed-yaml
expect_silent 28 check-28-good-valid-yaml

# Check 29: agents/*.md descriptions are scanned; NEVER joins the imperative list.
run_check 29 "$FIX/check-29-bad"
if [ "$INFO_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-29 bad fixture (NEVER in agent description) fires INFO (info=$INFO_FOUND)"
else
  bad "check-29 bad fixture did NOT fire INFO (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi

# Check 29 WARN branch: an injection phrase in a description fires WARN; a plain one is silent.
expect_warn 29 check-29-bad-injection
run_check 29 "$FIX/check-29-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ] && [ "$INFO_FOUND" -eq 0 ]; then ok "check-29 good silent (no INFO either)"
else bad "check-29 good not silent (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"; fi

# Check 70: stray top-level entries (gitignored working-tree clutter). WARN on a
# leftover `*-workspace/` dir; silent when the root holds only keep-list entries.
expect_warn   70 check-70-bad-stray-entry
expect_silent 70 check-70-good-clean-root

# Check 71: paired Codex plugin's review-gate state. The state file's path is
# content-addressed by the fixture's own absolute path (sha256 of its
# realpath), so it can't be pre-committed to git -- written fresh here with
# the same helper the check itself uses, under a throwaway MH_CODEX_DATA_DIR
# so this never touches the real, shared ~/.claude/plugins/data/.
CODEX_TMP=$(mktemp -d)
trap 'trash "$CODEX_TMP" 2>/dev/null || true' EXIT
setup_codex_state() {
  local fixture="$1" gate="$2" path
  export MH_CODEX_DATA_DIR="$CODEX_TMP/$fixture"
  path=$(codex_state_path "$FIX/$fixture") || { bad "check-71 $fixture: codex_state_path failed"; return 1; }
  mkdir -p "$(dirname "$path")"
  printf '{"config":{"stopReviewGate":%s}}' "$gate" > "$path"
}
setup_codex_state check-71-bad-review-gate-on true
expect_warn   71 check-71-bad-review-gate-on
setup_codex_state check-71-good-review-gate-off false
expect_silent 71 check-71-good-review-gate-off
unset MH_CODEX_DATA_DIR

# Check 21: agent model value. fable is a documented alias but a discouraged pin
# (agent-authoring-conventions.md) -- must WARN by name, not silently pass as valid.
expect_warn_match 21 check-21-bad-fable-pin 'fable'

# Check 72: Codex effort-set drift. A fake plugin cache carries the plugin's
# VALID_REASONING_EFFORTS line; the fixture doc either matches it or not.
mkdir -p "$CODEX_TMP/cache/scripts"
printf 'const VALID_REASONING_EFFORTS = new Set(["none", "minimal", "low", "medium", "high", "xhigh"]);\n' > "$CODEX_TMP/cache/scripts/codex-companion.mjs"
export MH_CODEX_CACHE_DIR="$CODEX_TMP/cache"
expect_warn   54 check-54-bad-effort-max
expect_warn   72 check-72-bad-effort-drift
expect_warn   72 check-72-bad-effort-missing
expect_silent_match 72 check-72-good-effort-set 'matches the installed plugin'
# Normalisation: doc order and plugin quote style must not read as drift.
expect_silent_match 72 check-72-good-effort-reordered 'matches the installed plugin'
printf "const VALID_REASONING_EFFORTS = new Set(['none', 'minimal', 'low', 'medium', 'high', 'xhigh']);\n" > "$CODEX_TMP/cache/scripts/codex-companion.mjs"
expect_silent_match 72 check-72-good-effort-set 'matches the installed plugin'
# Fail-open branches: plugin layout changed, doc missing, plugin not installed -> INFO only.
printf 'export const nothing = 1;\n' > "$CODEX_TMP/cache/scripts/codex-companion.mjs"
expect_info_only 72 check-72-good-effort-set 'VALID_REASONING_EFFORTS missing'
printf 'const VALID_REASONING_EFFORTS = new Set(["none", "minimal", "low", "medium", "high", "xhigh"]);\n' > "$CODEX_TMP/cache/scripts/codex-companion.mjs"
expect_info_only 72 check-72-info-no-doc 'spawn-brief.md missing'
MH_CODEX_CACHE_DIR="$CODEX_TMP/nonexistent" expect_info_only 72 check-72-good-effort-set 'plugin not installed'
unset MH_CODEX_CACHE_DIR
# Without the override the check must find the newest versioned cache dir itself (sort -V:
# 1.0.10 beats 1.0.9); the older dir carries a smaller set so a wrong pick fires a false WARN.
_c72_home="$CODEX_TMP/home"
for _v in 1.0.9 1.0.10; do mkdir -p "$_c72_home/.claude/plugins/cache/openai-codex/codex/$_v/scripts"; done
printf 'const VALID_REASONING_EFFORTS = new Set(["low", "medium", "high"]);\n' > "$_c72_home/.claude/plugins/cache/openai-codex/codex/1.0.9/scripts/codex-companion.mjs"
cp "$CODEX_TMP/cache/scripts/codex-companion.mjs" "$_c72_home/.claude/plugins/cache/openai-codex/codex/1.0.10/scripts/codex-companion.mjs"
HOME="$_c72_home" expect_silent_match 72 check-72-good-effort-set 'codex/1\.0\.10/'
HOME="$_c72_home" expect_warn 72 check-72-bad-effort-drift

# 73: hooks.json <-> hook-registry.json id/description drift. Five distinct bad fixtures,
# not one, because count-mismatch and stray-key alone leave the command-fingerprint and
# defensive-parsing branches untested (round-2 Codex review on the plan that added this check).
expect_silent 73 check-73-good-registry-synced
expect_warn   73 check-73-bad-length-mismatch
expect_warn   73 check-73-bad-stray-metadata-key
expect_warn   73 check-73-bad-command-mismatch
expect_warn   73 check-73-bad-malformed-structure
expect_warn   73 check-73-bad-duplicate-id
expect_warn   73 check-73-bad-missing-command-field
expect_warn   73 check-73-bad-args-fingerprint-mismatch

# Check 74: subagent-scoped gate agent_id presence-check invariant (harness
# gap-audit, 2026-09-20). A truthiness regression in any of the four files
# must fire CRIT; a missing file must also fire CRIT (can't verify the
# invariant); all four present and correct must stay silent.
expect_silent 74 check-74-good-all-present
expect_crit   74 check-74-bad-truthiness-regression
expect_crit   74 check-74-bad-missing-file
# (2026-09-21 deep-audit) the check used to strip only # comments, so the idiom
# inside a docstring passed, and it accepted one match for irrecoverable.py,
# which has two _nested_spawn call sites to keep in step.
expect_crit   74 check-74-bad-docstring-only
expect_crit   74 check-74-bad-one-site-regressed

# Check 75: manifest skill-reference drift (harness gap-audit M12, 2026-09-20).
# "bar" is a real skill dir excluded from its fixture plugin.json's skills
# list -- referencing it with the mh: prefix (as if shipped) must fire CRIT;
# describing it without that prefix must stay silent.
expect_crit   75 check-75-bad-excluded-referenced
expect_silent 75 check-75-good-clean

# Check 76: measurement coverage status freshness (harness gap-audit M14,
# 2026-09-20). Shallow on purpose -- WARN, not CRIT -- for the retired
# harness-coverage mechanism's lazy replacement.
expect_silent 76 check-76-good-populated
expect_warn   76 check-76-bad-missing-row
expect_warn   76 check-76-bad-file-missing

# Check 77: description word count (>25 WARN) and third-person voice (first/second-person
# pronoun WARN) -- skill-authoring-conventions.md's own cap, distinct from check 20's
# 1536-char runtime-truncation limit. Two independent trigger conditions, each fixture
# isolates one (mh:deep-audit gap, 2026-09-24: the check shipped with no fixture at all).
expect_warn   77 check-77-bad-long-desc
expect_warn   77 check-77-bad-pronoun
expect_silent 77 check-77-good-clean

# run_check's completion guard (mh:deep-audit F2, 2026-09-24): a missing fixture dir used to
# parse as a silent CRIT=0/WARN=0, letting expect_silent pass on a fixture that never ran.
# Isolate run_check's own internal bad() line so this meta-test contributes exactly one
# pass/fail verdict, not two.
_fail_before=$fail
run_check 77 "$FIX/check-77-DOES-NOT-EXIST"
fail=$_fail_before
if [ "$CRIT_FOUND" = "-1" ] && [ "$WARN_FOUND" = "-1" ] && [ "$INFO_FOUND" = "-1" ]; then
  ok "run_check forces failure on a missing fixture dir instead of a silent 0/0/0"
else
  bad "run_check completion guard did not fire on a missing fixture dir (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi

# Fleet pair: every check without a per-check fixture. fleet-bad plants one defect per
# check; fleet-good is a complete clean fleet and doubles as the fake plugin cache for
# 02/03 (loadability = present under --plugin-cache). 43 is driven by the env ceiling.
GOOD="$FIX/fleet-good"
# The cache is a copy, not the fixture itself: passing fleet-good as its own cache would make
# 02/03 pass with the checks gutted. A decoy cache (populated, holding none of the fleet)
# proves they still discriminate; an empty cache would only WARN "unverified". 02/03 also
# read HOME's symlink farm, so they run under an empty HOME (not the full run: python3 loses
# user-site PyYAML without the real HOME and check 28 WARNs). 43 runs with the ceiling pinned.
CACHE="$CODEX_TMP/cache-copy"; cp -R "$GOOD" "$CACHE"
DECOY="$CODEX_TMP/decoy-cache"; mkdir -p "$DECOY/agents" "$DECOY/skills/meta/unrelated"
EMPTY_HOME="$CODEX_TMP/empty-home"; mkdir -p "$EMPTY_HOME"
# Pinned, not emptied: an empty value falls through to $HOME/.claude/settings.json
# (skillListingBudgetFraction), which made the full runs below machine-dependent.
export SLASH_COMMAND_TOOL_CHAR_BUDGET=100000
for id in 02 03; do
  HOME="$EMPTY_HOME" expect_crit   "$id" fleet-bad  --plugin-cache "$CACHE"
  HOME="$EMPTY_HOME" expect_silent "$id" fleet-good --plugin-cache "$CACHE"
  HOME="$EMPTY_HOME" expect_crit   "$id" fleet-good --plugin-cache "$DECOY"
done
for id in 07 08 09 11 17 18 19 23 32 33; do
  expect_crit   "$id" fleet-bad  --plugin-cache "$CACHE"
  expect_silent "$id" fleet-good --plugin-cache "$CACHE"
done
for id in 10 21 24 35 41 42 54; do
  expect_warn   "$id" fleet-bad
  expect_silent "$id" fleet-good
done
SLASH_COMMAND_TOOL_CHAR_BUDGET=10     expect_warn   43 fleet-bad
SLASH_COMMAND_TOOL_CHAR_BUDGET=100000 expect_silent 43 fleet-good
# A HOME whose settings.json sets a tiny skillListingBudgetFraction must not leak into 43.
TINY_HOME="$CODEX_TMP/tiny-home"; mkdir -p "$TINY_HOME/.claude"
printf '{"skillListingBudgetFraction":0.00001}\n' > "$TINY_HOME/.claude/settings.json"
HOME="$TINY_HOME" expect_silent 43 fleet-good
# Full run on the clean fleet: proves the fixture is a whole fleet, not just silent per check,
# and that the vacuous-surface guard stays quiet when agents/, skills/, hooks/ all exist.
full=$(bash "$AUDIT" "$GOOD" --plugin-cache "$CACHE" 2>/dev/null || true)
if printf '%s\n' "$full" | /usr/bin/grep -q '^Critical: 0$' && printf '%s\n' "$full" | /usr/bin/grep -q '^Warnings: 0$'; then
  ok "fleet-good full run: 0 CRIT, 0 WARN"
else
  bad "fleet-good full run not clean: $(printf '%s\n' "$full" | /usr/bin/grep -E 'CRIT|WARN' | head -3)"
fi
# Vacuous-surface guard: a fleet with no hooks/ dir must say so in a full run (green-because-empty).
NOHOOKS="$CODEX_TMP/nohooks"
mkdir -p "$NOHOOKS" && cp -R "$GOOD/agents" "$GOOD/skills" "$NOHOOKS/"
# Capture first: under pipefail, grep -q closing the pipe early hands the audit a SIGPIPE.
nohooks_out=$(bash "$AUDIT" "$NOHOOKS" --plugin-cache "$CACHE" 2>/dev/null || true)
if printf '%s\n' "$nohooks_out" | /usr/bin/grep -q "no hooks/ dir"; then
  ok "vacuous-surface guard names the missing hooks/ dir"
else
  bad "vacuous-surface guard silent on a fleet with no hooks/ dir"
fi

echo ""
echo "self-test: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0
