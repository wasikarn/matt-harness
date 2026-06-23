# 43. L3 cage integrity (ADR 0003) — the cage-denylist + its guard are the single
# code-level bound on an unattended L3 run. If the cage is empty/missing, the guard
# is gone, or the cage stops covering a load-bearing safety surface, the loop could
# edit its own gates/audit/gauntlet and escape. Gated on ADR 0003 presence (other
# plugin repos + the audit fixtures don't declare L3, so the whole block is skipped).
# CRIT, not WARN: a holed cage is one model-version from a self-rewriting loop.
ADR0003="$CLAUDE_DIR/docs/adr/0003-l3-bounded-autonomy.md"
CAGE="$CLAUDE_DIR/scripts/cage.txt"
GUARD="$CLAUDE_DIR/scripts/loop-guard.py"
if [ -f "$ADR0003" ]; then
  # 43a/43b/43d: cage-completeness core (design §5 R3). The logic lives ONCE in
  # scripts/l4/cage-intact.sh (the standalone) so the loop-guard's per-cycle
  # --assert-cage-intact and this audit call the SAME implementation — no sync-seam
  # for the curated anchor list. Relay the standalone's "CRIT: <msg>" lines through
  # the audit's crit() so they count toward the audit's CRIT_COUNT + summary.
  _cage_rc=0
  _cage_out=$(bash "$CLAUDE_DIR/scripts/l4/cage-intact.sh" "$CLAUDE_DIR" 2>/dev/null) || _cage_rc=$?
  if [ "$_cage_rc" -ne 0 ]; then
    _relayed=0
    while IFS= read -r _cline; do
      case "$_cline" in
        CRIT:\ *) crit "${_cline#CRIT: }"; _relayed=$((_relayed + 1)) ;;
      esac
    done <<<"$_cage_out"
    # Fail-closed: the standalone exited non-zero but emitted no parseable CRIT.
    [ "$_relayed" -gt 0 ] || crit "L3 cage-intact standalone exited rc=$_cage_rc with no CRIT message (design §5 R3 — the cage check failed opaquely)"
  fi
  # 43c: guard present, compiles, and its self-check passes (the matcher + fail-closed posture).
  if [ ! -f "$GUARD" ]; then
    crit "L3 guard missing: scripts/loop-guard.py absent but ADR 0003 declares L3 (no code-level enforcer of the caps/cage)"
  elif command -v python3 >/dev/null 2>&1; then
    if ! python3 -m py_compile "$GUARD" 2>/dev/null; then
      crit "L3 guard broken: scripts/loop-guard.py does not compile (py_compile failed)"
    elif ! python3 "$GUARD" selftest >/dev/null 2>&1; then
      crit "L3 guard selftest FAILED: scripts/loop-guard.py selftest non-zero (cage matcher or fail-closed posture regressed)"
    fi
  fi
fi

