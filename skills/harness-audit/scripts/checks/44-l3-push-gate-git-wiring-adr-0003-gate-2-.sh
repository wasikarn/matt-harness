# 44. L5 git wiring (gauntlet emitter + core.hooksPath wiring). Push-gate legs
# RETIRED 2026-06-25 (CLAUDE.md §The operating model (was L4 self-launch, retired) Gate-2 + CLAUDE.md §The operating model (was L5 auto-push, retired) L5; replaced by block-dangerous-
# git.sh scoped denials + advisory-push-reminder.sh). Post-push tripwire leg
# RETIRED 2026-06-25 (post-push-tripwire.sh deleted in Batch 2). ADRs are
# append-only, so the gate is no-op'd directly here rather than relying on ADR
# absence. Re-gated on run-gauntlet.sh / hooks.json / git-hooks FILE presence
# (NOT on CLAUDE.md §The operating model (was L3 bounded autonomy, retired)/0005) — the gauntlet_run-emit + core.hooksPath guards stay
# live on file presence.
HOOKSJSON="$CLAUDE_DIR/hooks/hooks.json"
GAUNTLET="$CLAUDE_DIR/scripts/run-gauntlet.sh"
# The computational ship-gate evidence emitter: run-gauntlet.sh must emit a
# SHA-bound gauntlet_run event. Without it, no green-for-HEAD can ever exist and
# the L5 leg is dead. Gated on the gauntlet FILE being present (not on CLAUDE.md §The operating model (was L5 auto-push, retired)).
if [ -f "$GAUNTLET" ] && ! grep -qF 'gauntlet_run' "$GAUNTLET"; then
  crit "L5 ship-gate emitter: run-gauntlet.sh does not emit a gauntlet_run event — the SHA-bound green-for-HEAD evidence the L5 push leg reads is never produced (CLAUDE.md §The operating model (was L5 auto-push, retired) addendum item 1)"
fi
# hooksPath sub-check: only when auditing the actual git working tree (skip for
# the plugin cache, which has no .git, and for non-kbg repos without git-hooks/).
# Gated on the git-hooks/ dir being present (not on CLAUDE.md §The operating model (was L3 bounded autonomy, retired)/0005).
if [ -d "$CLAUDE_DIR/git-hooks" ] && git -C "$CLAUDE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  _hp=$(git -C "$CLAUDE_DIR" config --local core.hooksPath 2>/dev/null || true)
  _expected_abs="$(cd "$CLAUDE_DIR" && pwd)/git-hooks"
  if [ "$_hp" != "git-hooks" ] && [ "$_hp" != "$_expected_abs" ]; then
    crit "L5 git wiring: core.hooksPath is '${_hp:-<unset>}', expected 'git-hooks' (or its absolute equivalent $_expected_abs) — the gauntlet (pre-commit/pre-push) is bypassed (CLAUDE.md §The operating model (was L5 auto-push, retired) §B computational push gate)"
  fi
fi
info "audit #44: push-gate + post-push tripwire legs RETIRED 2026-06-25 (CLAUDE.md §The operating model (current) supersedes 0003/0005); gauntlet_run-emit + core.hooksPath guards re-gated on file presence" 2>/dev/null || true