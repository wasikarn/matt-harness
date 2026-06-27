# 54. fact-force-gate structured-decision contract (CLAUDE.md §Hook architecture (current profile ladder design)) — the four-fact
# gate fires on the FIRST edit of each file per session. Its deny MUST travel as
# `hookSpecificOutput.permissionDecision` (hookEventName PreToolUse). This gate
# satisfies the contract by delegating to _lib.sh's `hook_decision deny` helper
# (the sanctioned structured emitter) — so the regression to guard is NOT "does
# the literal field appear here" but "does the deny path still route through
# hook_decision". A hand-rolled `printf '{"permissionDecision":"deny"}'` +
# exit 0 is SILENTLY IGNORED and the edit lands ungated — the operator sees
# friction that protects nothing (the exact third-party-port class, CLAUDE.md §Hook architecture (current profile ladder design)
# contract #1). Also asserts the off-switch so an operator can disarm for
# setup/repair. CRIT: a silent no-op gate is worse than no gate (false-reassures).
# Comments stripped before grepping so a doc-only mention of hook_decision
# cannot mask a code regression.
_F=$(find "$CLAUDE_DIR/hooks" -type f -name "fact-force-gate.sh" 2>/dev/null | head -1)
if [ -f "$_F" ]; then
  _code=$(sed '/^[[:space:]]*#/d' "$_F" 2>/dev/null)
  printf '%s\n' "$_code" | /usr/bin/grep -qE 'hook_decision deny' \
    || crit "fact-force-gate.sh: deny path does not call _lib's hook_decision — a hand-rolled top-level permissionDecision is silently ignored (CLAUDE.md §Hook architecture (current profile ladder design) contract #1)"
  printf '%s\n' "$_code" | /usr/bin/grep -qE 'KBG_GATEGUARD=off|KBG_FACT_FORCE_DISABLED' \
    || warn "fact-force-gate.sh: no off-switch (KBG_GATEGUARD=off / KBG_FACT_FORCE_DISABLED) — operator cannot disarm (CLAUDE.md §Hook architecture (current profile ladder design))"
fi