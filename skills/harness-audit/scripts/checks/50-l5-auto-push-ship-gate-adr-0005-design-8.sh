# 50. L5 auto-push ship-gate (ADR 0005, design §8.5, #35). With the human out of the
# push loop, the in-plugin ship-gate (folded into push-gate.sh as the L5 leg) must
# default to an EMPTY allowlist (an un-configured install pushes NOWHERE), deny on
# cross-remote host+org divergence, AND require a green gauntlet (a recent l3_cycle
# green event) — the model never authorizes the ship. Positive assertions over the
# push-gate's L5 leg (CRIT UNLESS each holds — design §8.5 blocker: same commit as
# the gate; test injects a regression + asserts the CRIT).
if [ -f "$CLAUDE_DIR/docs/adr/0005-l5-auto-push.md" ]; then
  _PG="$CLAUDE_DIR/hooks/gates/push-gate.sh"
  if [ -f "$_PG" ]; then
    _pg=$(grep -vE '^[[:space:]]*#' "$_PG" 2>/dev/null)
    _pbad=""
    printf '%s\n' "$_pg" | grep -qF 'KBG_L5_SHIP_ALLOWLIST' || _pbad="$_pbad allowlist-var"
    # empty default: the :-} empty-default expansion (un-configured → nowhere).
    printf '%s\n' "$_pg" | grep -qF 'KBG_L5_SHIP_ALLOWLIST:-}' || _pbad="$_pbad empty-default(noplace-unconfigured)"
    printf '%s\n' "$_pg" | grep -qF -- 'git remote get-url' || _pbad="$_pbad dest-resolution(get-url)"
    printf '%s\n' "$_pg" | grep -qF '"outcome":"green"' || _pbad="$_pbad green-gauntlet-required"
    # the allow fires ONLY when dest is in the allowlist AND green (the case match).
    printf '%s\n' "$_pg" | grep -qF '",$_allow,"' || _pbad="$_pbad allowlist-membership-check"
    [ -z "$_pbad" ] || crit "audit #50: push-gate.sh L5 ship-gate leg regressed (missing:$_pbad) — design §8.5, ADR 0005. The auto-push must stay cross-remote-restricted + empty-allowlist-default + green-gauntlet-gated (the model never authorizes)."
  fi
fi

