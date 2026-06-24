# 44. L5 push-gate + git wiring (ADR 0005 + addendum 0005-addendum-manual-push-
# precondition-waiver.md; supersedes the ADR 0003 Gate-2 "push stays human-gated"
# form). The push-gate.sh PreToolUse hook now authorizes a manual armed `git push`
# via a COMPUTATIONAL ship-gate — SHA-bound green gauntlet + allowlisted dest + no
# cross-repo security-gate loosening — NOT a human-review flag, and never a model
# verdict alone (the deepest invariant: the gate that authorizes a ship stays
# computational, never a model). `gh pr merge`/`repo sync` stay human-gated (Gate 2).
# The git-hook gauntlet that runs the in-loop check is wired via core.hooksPath=
# git-hooks. A removed push-gate, a redirected hooksPath, a reverted-to-stale-green
# check, or a missing emitter/tripwire silently disables the L5 ship-gate.
if [ -f "$ADR0003" ] || [ -f "$CLAUDE_DIR/docs/adr/0005-l5-auto-push.md" ]; then
  PUSHGATE="$CLAUDE_DIR/hooks/gates/push-gate.sh"
  HOOKSJSON="$CLAUDE_DIR/hooks/hooks.json"
  GAUNTLET="$CLAUDE_DIR/scripts/run-gauntlet.sh"
  if [ ! -f "$PUSHGATE" ]; then
    crit "L5 push-gate missing: hooks/gates/push-gate.sh absent (the ship-gate is unenforced — the loop could push its own batch)"
  elif [ -f "$HOOKSJSON" ] && ! grep -qF 'push-gate.sh' "$HOOKSJSON"; then
    crit "L5 push-gate not registered: hooks/gates/push-gate.sh exists but is not wired in hooks/hooks.json (the gate never fires)"
  fi
  # L5 contract (ADR 0005 §floor 3): the push leg must be SHA-bound green, not a
  # stale any-green and not a model verdict. Pin the byte-level shape so a regression
  # to the dormant skeleton (tail -n 500 | grep outcome:green) fails loud.
  if [ -f "$PUSHGATE" ]; then
    if ! grep -qF '\"sha\"' "$PUSHGATE" || ! grep -qF 'gauntlet_run' "$PUSHGATE"; then
      crit "L5 push-gate contract: push-gate.sh lacks the SHA-bound gauntlet_run green check (ADR 0005 §floor 3) — a stale any-green or a model verdict could authorize a ship (model-authorizing ship = the forbidden invariant)"
    fi
    # The pre-push cross-repo CRIT must key on the three ADR-named security gates.
    if ! grep -qF 'hooks/gates/secret-scan.sh' "$PUSHGATE" \
       || ! grep -qF 'hooks/gates/block-dangerous-git.sh' "$PUSHGATE" \
       || ! grep -qF 'hooks/gates/db-write-gate.sh' "$PUSHGATE"; then
      crit "L5 push-gate CRIT: push-gate.sh does not key the cross-repo CRIT on all three ADR-named gates (secret-scan / block-dangerous-git / db-write-gate) — a loosened brake could ship (ADR 0005 §floor 2)"
    fi
  fi
  # The computational ship-gate evidence emitter: run-gauntlet.sh must emit a
  # SHA-bound gauntlet_run event. Without it, no green-for-HEAD can ever exist and
  # the L5 leg is dead (denies every push — fail-closed, but the gate is non-functional).
  if [ -f "$GAUNTLET" ] && ! grep -qF 'gauntlet_run' "$GAUNTLET"; then
    crit "L5 ship-gate emitter: run-gauntlet.sh does not emit a gauntlet_run event — the SHA-bound green-for-HEAD evidence the L5 push leg reads is never produced (ADR 0005 addendum item 1)"
  fi
  # The post-push tripwire witness (ADR 0005 §floor 5) must be registered.
  if [ -f "$HOOKSJSON" ] && ! grep -qF 'post-push-tripwire.sh' "$HOOKSJSON"; then
    warn "L5 post-push tripwire: hooks/post-tool/post-push-tripwire.sh is not registered in hooks/hooks.json (ADR 0005 §floor 5 outside-the-cage witness missing — a loosened brake that slipped via the Gate-2 override goes unwitnessed)"
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