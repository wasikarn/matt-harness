# 44. L5 git wiring (gauntlet emitter + git-hooks/core.hooksPath wiring + post-push
# tripwire witness; push-gate legs RETIRED 2026-06-25 (ADR 0004 Gate-2 + ADR 0005 L5);
# the ship-gate enforced denial is replaced by block-dangerous-git.sh scoped
# denials + advisory-push-reminder.sh).
if [ -f "$ADR0003" ] || [ -f "$CLAUDE_DIR/docs/adr/0005-l5-auto-push.md" ]; then
  HOOKSJSON="$CLAUDE_DIR/hooks/hooks.json"
  GAUNTLET="$CLAUDE_DIR/scripts/run-gauntlet.sh"
  # The computational ship-gate evidence emitter: run-gauntlet.sh must emit a
  # SHA-bound gauntlet_run event. Without it, no green-for-HEAD can ever exist and
  # the L5 leg is dead (denies every push — fail-closed, but the gate is non-functional).
  if [ -f "$GAUNTLET" ] && ! grep -qF 'gauntlet_run' "$GAUNTLET"; then
    crit "L5 ship-gate emitter: run-gauntlet.sh does not emit a gauntlet_run event — the SHA-bound green-for-HEAD evidence the L5 push leg reads is never produced (ADR 0005 addendum item 1)"
  fi
  # The post-push tripwire witness (ADR 0005 §floor 5) must be registered.
  if [ -f "$HOOKSJSON" ] && ! grep -qF 'post-push-tripwire.sh' "$HOOKSJSON"; then
    warn "L5 post-push tripwire: hooks/post-tool/post-push-tripwire.sh is not registered in hooks/hooks.json (a loosened brake that ships goes unwitnessed (push-gate retired 2026-06-25; this tripwire is the sole brake-loosening witness))"
  fi
  # hooksPath sub-check: only when auditing the actual git working tree (skip for
  # the plugin cache, which has no .git, and for non-kbg repos without git-hooks/).
  if [ -d "$CLAUDE_DIR/git-hooks" ] && git -C "$CLAUDE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    _hp=$(git -C "$CLAUDE_DIR" config --local core.hooksPath 2>/dev/null || true)
    _expected_abs="$(cd "$CLAUDE_DIR" && pwd)/git-hooks"
    if [ "$_hp" != "git-hooks" ] && [ "$_hp" != "$_expected_abs" ]; then
      crit "L5 git wiring: core.hooksPath is '${_hp:-<unset>}', expected 'git-hooks' (or its absolute equivalent $_expected_abs) — the gauntlet (pre-commit/pre-push) is bypassed (ADR 0005 §B computational push gate)"
    fi
  fi
fi