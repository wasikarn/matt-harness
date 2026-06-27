# 53. Profile-ladder floor coverage (CLAUDE.md §Hook architecture (current profile ladder design)) — `CLAUDE_HOOK_PROFILE=minimal`
# dials friction down WITHOUT losing the safety floor. That invariant holds ONLY
# if every irrecoverable-floor gate opts into all three profiles
# (`HOOK_PROFILES="minimal standard strict"`) AND _lib.sh's hook_init implements
# the profile-tier gate (matched here by the `HOOK_PROFILES:-standard strict`
# default token — unique to the tier `case`, robust to quoting/brace variance).
# A floor gate that drops `minimal` = a minimal session silently loses the
# safety floor (block-dangerous-* / secret-* stop firing) — the exact one-way-door
# CLAUDE.md §Hook architecture (current profile ladder design) exists to protect. CRIT, not WARN: the floor is the load-bearing
# surface; a hole is one `export CLAUDE_HOOK_PROFILE=minimal` away from an
# unrecoverable op. Comments stripped before grepping (the inline `# floor gate`
# rationale sits on the assignment line; full-line docs must not mask a drop).
_FLOOR_GATES=(
  block-dangerous-bash block-dangerous-git
  secret-read-guard secret-scan block-bash-doctrine-write
)
_LIB="$CLAUDE_DIR/hooks/_lib.sh"
if [ -f "$_LIB" ]; then
  sed '/^[[:space:]]*#/d' "$_LIB" 2>/dev/null | /usr/bin/grep -qE 'HOOK_PROFILES:-standard strict' \
    || crit "profile ladder: _lib.sh hook_init has no HOOK_PROFILES tier (default 'standard strict') — profile gating is inert (CLAUDE.md §Hook architecture (current profile ladder design))"
fi
for _g in "${_FLOOR_GATES[@]}"; do
  _f=$(find "$CLAUDE_DIR/hooks" -type f -name "$_g.sh" 2>/dev/null | head -1)
  [ -f "$_f" ] || { crit "profile ladder: floor gate '$_g.sh' missing (CLAUDE.md §Hook architecture (current profile ladder design) floor)"; continue; }
  sed '/^[[:space:]]*#/d' "$_f" 2>/dev/null | /usr/bin/grep -qE 'HOOK_PROFILES="minimal standard strict"' \
    || crit "profile ladder: floor gate '$_g.sh' missing HOOK_PROFILES=\"minimal standard strict\" — a minimal session loses this floor gate (CLAUDE.md §Hook architecture (current profile ladder design))"
done