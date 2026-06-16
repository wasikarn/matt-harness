# shellcheck disable=SC1090,SC2034
# shellcheck shell=bash
# test-ch-harness-audit31.sh — sourced by test-critical-hooks.sh
# Covers: harness-audit check #31 (tests MM, NN, OO).

# --- harness-audit check #31 — schema-rot detector (3 sub-checks) ---
# Round-2 (2026-06-11) gap-closure: the pre-emit validator is scoped to
# the review-pr journaler's enum regexes only. Check #31 adds a general
# detector for (31.2) plugin.json / marketplace.json version validity + 30d
# cadence, (31.3) decay-cadence.md permission-re-audit bookmark, (31.4)
# hooks.json schema shape. 31.2-31.3 emit info (advisory); 31.4 emits crit
# (structural). [31.1 skill-section presence was RETIRED 2026-06-16 — it was a
# self-referential blanket forcing byte-identical boilerplate; see audit.sh.] The tests below are hermetic — they build a
# fresh temp-dir fixture (.claude-plugin/, claude/skills/, claude/hooks/,
# claude/docs/) and run the audit against it, so the harness's real
# plugin.json/hooks.json state is irrelevant. Mirrors the (K)
# check-#29 test pattern.
AUDIT="$HOOKS/../skills/harness-audit/scripts/audit.sh"

# (MM) clean fixture — every sub-check should stay silent. One SKILL.md
# with all 3 canonical sections, one plugin.json with `version` +
# (the marketplace schema requires no `last_reviewed_reason:`), one
# hooks.json with non-empty matcher/type/command, one
# decay-cadence.md with a fresh `last_permission_review: YYYY-MM-DD`
# marker. Today's date is used for the marker so the 90d quarterly
# cadence check passes.
SREP_C="$FIXTURE/srep-clean"; rm -rf "$SREP_C"; mkdir -p "$SREP_C/claude/skills/good-skill" "$SREP_C/claude/hooks" "$SREP_C/claude/agents" "$SREP_C/claude/commands" "$SREP_C/claude/docs" "$SREP_C/.claude-plugin"
cat > "$SREP_C/claude/skills/good-skill/SKILL.md" <<'SK'
---
name: good-skill
description: 'Test fixture for audit #31.'
---
# Good Skill

## Input Contract
- needs: foo

## Output Format
- emits: bar

## Failure Modes
- when: baz
SK
cat > "$SREP_C/.claude-plugin/plugin.json" <<'PJ'
{
  "name": "test-plugin",
  "version": "0.1.0"
}
PJ
cat > "$SREP_C/claude/hooks/hooks.json" <<'HJ'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "echo ok" }
        ]
      }
    ]
  }
}
HJ
# Use today's date so the permission-re-audit bookmark is "fresh"
# (within the 90d quarterly cadence). Without this the clean fixture
# would itself trip PERM_BOOKMARK_STALE.
TODAY_ISO=$(python3 -c 'import datetime; print(datetime.date.today().isoformat())')
cat > "$SREP_C/claude/docs/harness-decay-cadence.md" <<DC
# Decay cadence
last_permission_review: $TODAY_ISO abc123
DC
# Capture rc directly. The pattern `OUT=$(cmd)` masks cmd's $? with
# the assignment's; use a wrapper that preserves the exit status.
set +e
SREP_C_OUT=$(bash "$AUDIT" "$SREP_C" 2>&1)
SREP_C_RC=$?
set -e
SREP_C_SCHEMA=$(printf '%s' "$SREP_C_OUT" | grep -c "schema-rot" || true)
# Clean fixture should produce ZERO schema-rot findings. The audit's
# overall rc is dominated by the always-firing F1 symlink CRIT + 2
# description WARNs on a fresh fixture, so we don't assert rc=0 here
# — only that check #31's own sub-checks stay silent (the contract of
# this test). The (NN) test below covers the rc>0 path.
if [ "$SREP_C_SCHEMA" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s clean fixture: no schema-rot findings (sub-checks 1-4 all silent)\n' "harness-audit #31"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s clean fixture emitted %s schema-rot findings (want 0), rc=%s:\n%s\n' "harness-audit #31" "$SREP_C_SCHEMA" "$SREP_C_RC" "$SREP_C_OUT"
fi

# (NN) violating fixture — every sub-check should fire. SKILL.md
# missing all 3 canonical sections (info), plugin.json missing
# `version` (crit), decay-cadence.md missing the perm-re-audit marker
# (info), hooks.json with an empty matcher AND a missing-type entry
# (crit). The test asserts that BOTH kinds of finding appear: the
# info-level I/O contract drift AND the structural hooks.json crit.
# Hermetic: every file is built at test time, no shared state with
# the real repo.
SREP_V="$FIXTURE/srep-bad"; rm -rf "$SREP_V"; mkdir -p "$SREP_V/claude/skills/bad-skill" "$SREP_V/claude/hooks" "$SREP_V/claude/agents" "$SREP_V/claude/commands" "$SREP_V/claude/docs" "$SREP_V/.claude-plugin"
cat > "$SREP_V/claude/skills/bad-skill/SKILL.md" <<'SK'
---
name: bad-skill
description: 'Test fixture for audit #31 — missing sections.'
---
# Bad Skill

This SKILL.md is missing the canonical sections.
SK
# plugin.json: NO `version` field → fires PLUGIN_NO_VERSION (crit)
cat > "$SREP_V/.claude-plugin/plugin.json" <<'PJ'
{
  "name": "test-plugin-no-version"
}
PJ
# hooks.json: non-string matcher (integer — the genuine schema violation
# the check guards) + a missing `type` field on one entry (defense in
# depth). Empty matcher is NOT a violation (vendor convention for
# multi-source events like ConfigChange — see
# hooks/config-change-log.sh header).
cat > "$SREP_V/claude/hooks/hooks.json" <<'HJ'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": 42,
        "hooks": [
          { "type": "command", "command": "echo bad" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          { "command": "echo no-type" }
        ]
      }
    ]
  }
}
HJ
# decay-cadence.md exists but has NO `last_permission_review:` marker
# → PERM_BOOKMARK_MISSING (info).
cat > "$SREP_V/claude/docs/harness-decay-cadence.md" <<'DC'
# Decay cadence

This fixture file intentionally omits the `last_permission_review:` marker
to verify the audit surfaces drift rather than silently passing.
DC
set +e
SREP_V_OUT=$(bash "$AUDIT" "$SREP_V" 2>&1)
SREP_V_RC=$?
set -e
SREP_V_HAS_PLUGIN_CRIT=$(printf '%s' "$SREP_V_OUT" | grep -c "plugin.json has no 'version' field" || true)
SREP_V_HAS_HOOKS_CRIT=$(printf '%s' "$SREP_V_OUT" | grep -c "hooks.json —" || true)
SREP_V_HAS_PERM_INFO=$(printf '%s' "$SREP_V_OUT" | grep -c "schema-rot:.*decay-cadence" || true)
# (#31.1 skill-section sub-check was RETIRED 2026-06-16 — the bad-skill SKILL.md
# missing sections no longer fires; the remaining 3 sub-checks still must.)
if [ "$SREP_V_HAS_PLUGIN_CRIT" -ge 1 ] \
   && [ "$SREP_V_HAS_HOOKS_CRIT" -ge 1 ] && [ "$SREP_V_HAS_PERM_INFO" -ge 1 ] \
   && [ "$SREP_V_RC" -ge 2 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s violating fixture: 3 sub-checks fire (plugin crit, hooks crit, perm info); rc>=2 (got %s)\n' "harness-audit #31" "$SREP_V_RC"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s plugin=%s hooks=%s perm=%s rc=%s (want >=1/1/1/2):\n%s\n' "harness-audit #31" "$SREP_V_HAS_PLUGIN_CRIT" "$SREP_V_HAS_HOOKS_CRIT" "$SREP_V_HAS_PERM_INFO" "$SREP_V_RC" "$SREP_V_OUT"
fi

# (OO) regression guard — empty matcher must NOT fire HOOKS_SHAPE_FAIL.
# This mirrors the real kbg-harness pattern: hooks/hooks.json:415 has
# `"matcher": ""` for the ConfigChange event, which is a legal vendor
# convention (empty matcher = match all known multi-source events).
SREP_O="$FIXTURE/srep-empty-matcher"; rm -rf "$SREP_O"; mkdir -p "$SREP_O/claude/skills/ok-skill" "$SREP_O/claude/hooks" "$SREP_O/claude/agents" "$SREP_O/claude/commands" "$SREP_O/claude/docs" "$SREP_O/.claude-plugin"
cat > "$SREP_O/claude/skills/ok-skill/SKILL.md" <<'SK'
---
name: ok-skill
description: 'Test fixture for audit #31 OO — empty matcher regression.'
---
# OK Skill

## Input Contract
- **Input 1**: ...

## Output Format
- **Output 1**: ...

## Failure Modes to Avoid
- **Failure mode 1**: ...
SK
cat > "$SREP_O/.claude-plugin/plugin.json" <<'PJ'
{ "name": "test-empty-matcher", "version": "0.0.1" }
PJ
cat > "$SREP_O/claude/hooks/hooks.json" <<'HJ'
{
  "hooks": {
    "ConfigChange": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "echo config-change" }
        ]
      }
    ]
  }
}
HJ
cat > "$SREP_O/claude/docs/harness-decay-cadence.md" <<DC
# Decay cadence

last_permission_review: $TODAY_ISO abc123
DC
set +e
SREP_O_OUT=$(bash "$AUDIT" "$SREP_O" 2>&1)
SREP_O_RC=$?
set -e
SREP_O_HAS_HOOKS_CRIT=$(printf '%s' "$SREP_O_OUT" | grep -c "HOOKS_SHAPE_FAIL" || true)
SREP_O_HAS_MATCHER_CRIT=$(printf '%s' "$SREP_O_OUT" | grep -c "matcher: not a string" || true)
if [ "$SREP_O_HAS_HOOKS_CRIT" = 0 ] && [ "$SREP_O_HAS_MATCHER_CRIT" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s empty matcher regression: 0 HOOKS_SHAPE_FAIL (legal vendor pattern accepted)\n' "harness-audit #31"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s empty matcher regression fired hooks-crit=%s matcher-crit=%s (want 0/0):\n%s\n' "harness-audit #31" "$SREP_O_HAS_HOOKS_CRIT" "$SREP_O_HAS_MATCHER_CRIT" "$SREP_O_OUT"
fi
