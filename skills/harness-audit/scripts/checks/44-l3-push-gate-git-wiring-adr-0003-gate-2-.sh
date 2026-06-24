# 44. L3 push-gate + git wiring (ADR 0003) — Gate 2 (push stays human-gated) is
# enforced by the push-gate.sh PreToolUse hook; the git-hook gauntlet that runs
# the in-loop check is wired via core.hooksPath=git-hooks. A removed push-gate or a
# redirected hooksPath silently disables Gate 2 / the gauntlet. Gated on ADR 0003.
if [ -f "$ADR0003" ]; then
  PUSHGATE="$CLAUDE_DIR/hooks/gates/push-gate.sh"
  HOOKSJSON="$CLAUDE_DIR/hooks/hooks.json"
  if [ ! -f "$PUSHGATE" ]; then
    crit "L3 push-gate missing: hooks/gates/push-gate.sh absent but ADR 0003 declares L3 (Gate 2 unenforced — the loop could push its own batch)"
  elif [ -f "$HOOKSJSON" ] && ! grep -qF 'push-gate.sh' "$HOOKSJSON"; then
    crit "L3 push-gate not registered: hooks/gates/push-gate.sh exists but is not wired in hooks/hooks.json (the gate never fires)"
  fi
  # hooksPath sub-check: only when auditing the actual git working tree (skip for
  # the plugin cache, which has no .git, and for non-kbg repos without git-hooks/).
  if [ -d "$CLAUDE_DIR/git-hooks" ] && git -C "$CLAUDE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    _hp=$(git -C "$CLAUDE_DIR" config --local core.hooksPath 2>/dev/null || true)
    _expected_abs="$(cd "$CLAUDE_DIR" && pwd)/git-hooks"
    if [ "$_hp" != "git-hooks" ] && [ "$_hp" != "$_expected_abs" ]; then
      crit "L3 git wiring: core.hooksPath is '${_hp:-<unset>}', expected 'git-hooks' (or its absolute equivalent $_expected_abs) — the gauntlet (pre-commit/pre-push) is bypassed (ADR 0003 §B computational push gate)"
    fi
  fi
fi

