# 34. Autonomy invariant — surface 5: inferential-FB sensors are advisory-only
# and must NEVER emit a permissionDecision (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model + CLAUDE.md "advisory only"
# invariant). Check #29 catches a hook that BOTH journals AND decides; it does
# NOT catch an inferential-FB sensor that gates WITHOUT journaling — that hook
# would slip #29 yet still be a model-driven mutation gate (covert L4). This
# check closes that gap: read sensors.json for fallback_role=="inferential-FB",
# resolve each sensor name to its hook script (basename starts with the name),
# strip full-line comments (a comment mentioning the invariant is fine), and
# CRIT if the code emits a decision (raw permissionDecision key, the _lib
# hook_decision emitter, or kbg_permission_decision). Hermetic: gated on
# sensors.json + jq presence, so non-kbg plugin repos skip cleanly.
SENSORS_JSON="$CLAUDE_DIR/hooks/sensors.json"
if [ -f "$SENSORS_JSON" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r _sname; do
    [ -n "$_sname" ] || continue
    _hook=$(find "$CLAUDE_DIR/hooks" -type f -name "${_sname}*" 2>/dev/null | grep -E '\.(sh|py)$' | head -1)
    [ -n "$_hook" ] || continue
    if grep -vE '^[[:space:]]*#' "$_hook" 2>/dev/null | grep -qE 'permissionDecision|hook_decision|kbg_permission_decision'; then
      crit "autonomy invariant: inferential-FB sensor '$_sname' (${_hook#"$CLAUDE_DIR"/}) emits a permissionDecision in code — advisory sensors must journal, not gate (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model surface 5 + CLAUDE.md 'advisory only')"
    fi
  done < <(jq -r '.sensors[] | select(.fallback_role=="inferential-FB") | .name' "$SENSORS_JSON" 2>/dev/null || true)
fi

