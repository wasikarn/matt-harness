# 48. L4 F1 floor — fires under the flag AND stays byte-identical flag-off (design
# §5 #48, ADR 0004). The single-key autonomy_on() collapse is exactly the refactor
# that can regress the flag-OFF path via empty-string truthiness / a wrong default,
# so this check PROVES both directions instead of asserting them in prose. Gated on
# ADR 0004 presence. Three legs:
#   (a) armed (per-repo KBG_AUTONOMY=1, no L5 allowlist, no KBG_REVIEW_DONE) → the
#       push gate DENIES a real git push. Under L5 (ADR 0005 addendum) a green+allow-
#       listed armed push may ALLOW, so the probe unsets KBG_L5_SHIP_ALLOWLIST to
#       guarantee the L5 leg does not allow → the gate FIRES (step-3 deny) rather than
#       no-ops. That firing-under-the-flag is the F1 invariant; the L5 allow path is
#       covered hermetically in test-ch-l3.sh (green-for-HEAD + allowlist → allow);
#   (b) flag unset → the push gate no-ops (exit 0) as the L2 baseline;
#   (c) enumeration — every arming read routes through autonomy_on(): CRIT on a raw
#       KBG_AUTONOMY literal outside the sanctioned homes, and on any LEFTOVER legacy
#       KBG_AUTONOMY_L3 / KBG_L3_REVIEW_DONE in active code (the collapse must be
#       complete — a leftover direct read is the inert-under-L4 hole F1 closes).
ADR0004="$CLAUDE_DIR/docs/adr/0004-l4-autonomy.md"
if [ -f "$ADR0004" ]; then
  PUSHGATE48="$CLAUDE_DIR/hooks/gates/push-gate.sh"
  # 48a/48b: runtime both directions. Skip cleanly if the gate or jq is absent.
  if [ -f "$PUSHGATE48" ] && command -v jq >/dev/null 2>&1; then
    _ev48='{"tool_name":"Bash","tool_input":{"command":"git push origin develop"}}'
    _ap48=$(mktemp -d)
    mkdir -p "$_ap48/.claude"
    printf '{"env":{"KBG_AUTONOMY":"1"}}' > "$_ap48/.claude/settings.local.json"
    _arm48=$(printf '%s' "$_ev48" | env -u KBG_REVIEW_DONE -u KBG_L5_SHIP_ALLOWLIST KBG_AUTONOMY=1 CLAUDE_PROJECT_DIR="$_ap48" bash "$PUSHGATE48" 2>/dev/null \
             | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null) || true
    # The gate emits NO JSON when it no-ops (exit 0 early) — jq on an empty stream
    # exits 0 with empty output, so treat empty as "none" (no deny), mirroring the
    # pcheck helper in test-ch-l3.sh.
    if [ -z "$_arm48" ]; then _arm48="none"; fi
    _off48=$(printf '%s' "$_ev48" | bash "$PUSHGATE48" 2>/dev/null \
             | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null) || true
    if [ -z "$_off48" ]; then _off48="none"; fi
    # disposable mktemp fixture in $TMPDIR — trash if available (owner pref), else rm -rf.
    if command -v trash >/dev/null 2>&1; then trash "$_ap48" >/dev/null 2>&1 || rm -rf "$_ap48"; else rm -rf "$_ap48"; fi
    [ "$_arm48" = "deny" ] || crit "audit #48a: under KBG_AUTONOMY=1 (per-repo, no L5 allowlist) the push gate must DENY a real git push (got '$_arm48') — the gate must fire under the flag (F1), not no-op. Under L5 a green+allowlisted push may allow (tested in test-ch-l3), but a push with no allowlist must still deny (design §5 #48, ADR 0004/0005)"
    [ "$_off48" = "none" ] || crit "audit #48b: with the flag unset the push gate must no-op (exit 0) as the L2 baseline (got '$_off48') — flag-OFF byte-identical regressed (design §5 #48)"
  fi
  # 48c: enumeration. Sanctioned raw-KBG_AUTONOMY homes (the helper bodies + the
  # tamper lists); every OTHER arming read must go through autonomy_on(). Comments
  # stripped first (a comment NAMING the rule is fine). Legacy keys must be GONE.
  _bad_new=""; _bad_old=""
  while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    _base=$(basename "$_f")
    # Sanctioned homes for a raw KBG_AUTONOMY literal: the helper bodies (_lib.sh,
    # loop-guard.py), the push-gate tamper list (push-gate.sh), AND the L4
    # self-launch launcher (scripts/l4/launch.sh) — which SETS the flag for the cycle
    # (an arming SOURCE, not a read; it is the caged, flag-gated sole sanctioned
    # self-start, design §8). Every OTHER arming read must route through autonomy_on().
    case "$_f" in
      */scripts/l4/launch.sh) _newok=1 ;;
      *) case "$_base" in _lib.sh|push-gate.sh|loop-guard.py) _newok=1 ;; *) _newok=0 ;; esac ;;
    esac
    _active=$(sed -E 's/#.*$//' "$_f" 2>/dev/null)
    if [ "$_newok" = "0" ] && printf '%s\n' "$_active" | grep -qE 'KBG_AUTONOMY([^_A-Z]|$)'; then
      _bad_new="$_bad_new $_f"
    fi
    if printf '%s\n' "$_active" | grep -qE 'KBG_AUTONOMY_L3|KBG_L3_REVIEW_DONE'; then
      _bad_old="$_bad_old $_f"
    fi
  done < <(find "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/scripts" -type f \( -name '*.sh' -o -name '*.py' \) 2>/dev/null)
  [ -z "$_bad_new" ] || crit "audit #48c: raw KBG_AUTONOMY literal outside autonomy_on() in:$_bad_new — every arming read must route through autonomy_on() (design §5 F1/#48c)"
  [ -z "$_bad_old" ] || crit "audit #48c: leftover legacy autonomy key(s) in active code:$_bad_old — the single-key collapse must be complete (KBG_AUTONOMY_L3/KBG_L3_REVIEW_DONE → KBG_AUTONOMY/KBG_REVIEW_DONE)"
  # 48d: F4 installer fail-safe present (design §5 F4 + §12 guards 1+2). The guard
  # MUST anchor REPO_ROOT to the mutated tree (git toplevel of CWD) + affirmatively
  # assert repo-identity (.claude-plugin/plugin.json name=='kbg') — without it a
  # flag-armed installer is stopped only by the silent, brittle cache-has-no-.git
  # path, which evaporates the moment a delivery path makes the cache a git repo.
  # Static grep over the guard source; a removed/renamed anchor → CRIT.
  _GUARD48="$CLAUDE_DIR/scripts/loop-guard.py"
  if [ -f "$_GUARD48" ]; then
    _gsrc=$(cat "$_GUARD48" 2>/dev/null)
    _f4bad=""
    printf '%s\n' "$_gsrc" | grep -qF '_assert_repo_root' || _f4bad="$_f4bad _assert_repo_root(def)"
    printf '%s\n' "$_gsrc" | grep -qF 'show-toplevel'      || _f4bad="$_f4bad git-toplevel"
    printf '%s\n' "$_gsrc" | grep -qF '.claude-plugin'     || _f4bad="$_f4bad plugin.json-sentinel"
    printf '%s\n' "$_gsrc" | grep -qF '!= "kbg"'           || _f4bad="$_f4bad name==kbg-check"
    [ -z "$_f4bad" ] || crit "audit #48d: loop-guard.py F4 anchoring incomplete (missing:$_f4bad) — the installer fail-safe (REPO_ROOT anchor + repo-identity) must stay in place (design §5 F4)"
  fi
fi

