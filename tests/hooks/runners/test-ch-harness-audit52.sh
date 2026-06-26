# shellcheck disable=SC1090,SC1091,SC2034
# shellcheck shell=bash
source "$(dirname "$0")/test-critical-hooks-lib.sh"
# test-ch-harness-audit52.sh — standalone suite run by test-critical-hooks.sh
# Covers: harness-audit check #52 (UU/VV) — push-gate review-rigor observe-flag.
#
# The armed-push Gate-2 check (push-gate.sh:87) authorizes on the PRESENCE of a
# `review_finding` event, not its rigor: an inline-review verdict satisfies the
# gate identically to a full multi-agent kbg:review-pr. Audit #52 (gated on the
# ADR 0002 addendum) INFO-flags review_finding events whose `fields.agent` is NOT
# composed of fleet reviewer names — the decay-sweep prompt that the maker≠checker
# bar was met, not rubber-stamped. INFO never inflates the audit exit code.
#
# Two cases:
#   (UU) fire      — an inline-agent review_finding → audit #52 emits INFO, count=1
#                    (a co-resident kbg:code-reviewer finding is NOT counted).
#   (VV) no-fire   — only dispatched forms (kbg:-namespaced, bare-name, and a
#                    multi-agent `A+B` combined form) → audit #52 is SILENT.
#                    This is the regression guard for the predicate: it proves the
#                    bare-name + combined forms (the pre-kbg: convention) are NOT
#                    misclassified as inline. A `!~ ^kbg:` predicate would cry "3"
#                    here — the positive-identification predicate must stay silent.
AUDIT="$HOOKS/../skills/harness-audit/scripts/audit.sh"
ADR_REL="docs/adr/0002-addendum-push-gate-review-rigor.md"

# Build a minimal-but-valid audit fixture: a repo with a claude/ tree (fleet
# dirs so the no-fleet guard does not err_die) + the ADR (so #52's gate opens).
# Other checks may CRIT/WARN on the empty fixture; we only grep for #52.
mk_audit_fixture() {
  local f="$1"
  /bin/rm -rf "$f" 2>/dev/null || true
  mkdir -p "$f/claude/agents" "$f/claude/skills" "$f/claude/commands" "$f/claude/hooks" "$f/claude/docs/adr" "$f/.claude-plugin"
  printf '# ADR 0002 addendum — fixture (gates audit #52 on)\n' > "$f/claude/$ADR_REL"
  printf '{ "name": "kbg", "version": "0.0.1" }\n' > "$f/.claude-plugin/plugin.json"
}

# emit_review_finding <journal> <agent> — append one review_finding envelope.
emit_review_finding() {
  local jpath="$1" agent="$2"
  jq -nc --arg agent "$agent" \
    '{id:"t",ts:"2026-06-23T00:00:00Z",session:"t",hook:"test",event:"review_finding",source:"test",fields:{agent:$agent}}' \
    >> "$jpath"
}

# push-gate-retired 2026-06-25 (ADR 0006) — audit #52 (review-rigor observe-flag) no-op'd.
# UU/VV asserted #52 INFO firing; with #52 no-op'd there is no INFO → UU fails.
# Re-enable by setting KBG_AUDIT_52_LIVE=live when #52 returns.
if [ "${KBG_AUDIT_52_LIVE:-no}" = "live" ]; then
# (UU) fire — inline-agent review_finding present → audit #52 INFO, count=1.
UU_F="$FIXTURE/uu-52"; mk_audit_fixture "$UU_F"
UU_J="$UU_F/journal.jsonl"
emit_review_finding "$UU_J" "inline-review (staff-eng)"
emit_review_finding "$UU_J" "kbg:code-reviewer"   # dispatched — must NOT be counted
set +e
UU_OUT=$(CLAUDE_JOURNAL_PATH="$UU_J" bash "$AUDIT" "$UU_F" 2>&1)
UU_RC=$?
set -e
UU_HAS52=$(printf '%s' "$UU_OUT" | grep -c "audit #52: 1 review_finding" || true)
if [ "$UU_HAS52" -ge 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s fire: inline-agent review_finding → INFO count=1 (dispatched co-resident not counted)\n' "harness-audit #52"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s fire: want "audit #52: 1 review_finding", rc=%s:\n%s\n' "harness-audit #52" "$UU_RC" "$UU_OUT" | head -20
fi

# (VV) no-fire — only dispatched forms (kbg: + bare + combined) → audit #52 SILENT.
VV_F="$FIXTURE/vv-52"; mk_audit_fixture "$VV_F"
VV_J="$VV_F/journal.jsonl"
emit_review_finding "$VV_J" "kbg:code-reviewer"                # namespaced
emit_review_finding "$VV_J" "security-reviewer"                # bare-name (pre-kbg: convention)
emit_review_finding "$VV_J" "code-reviewer+security-reviewer"  # multi-agent combined
set +e
VV_OUT=$(CLAUDE_JOURNAL_PATH="$VV_J" bash "$AUDIT" "$VV_F" 2>&1)
VV_RC=$?
set -e
VV_HAS52=$(printf '%s' "$VV_OUT" | grep -c "audit #52:" || true)
if [ "$VV_HAS52" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s no-fire: dispatched forms (kbg:+bare+combined) → #52 silent (predicate robust to convention shift)\n' "harness-audit #52"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s no-fire: #52 must be silent for dispatched-only journal, but emitted (rc=%s):\n%s\n' "harness-audit #52" "$VV_RC" "$(printf '%s' "$VV_OUT" | grep "audit #52:" | head -5)"
fi
else
  printf "  ⏭  push-gate-retired 2026-06-25 (ADR 0006) — audit #52 no-op'd — UU/VV skipped\n"
fi

report