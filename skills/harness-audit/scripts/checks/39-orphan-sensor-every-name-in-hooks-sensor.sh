# 39. Orphan sensor — every name in hooks/sensors.json must resolve to a real
# hook script. A sensor whose hook was renamed/removed lingers as a phantom and
# makes the staleness monitor (notify-sensor-staleness.sh) report a false 'never
# fired' for a sensor that no longer exists. Generalizes the sensor→file
# resolution #34 already does for inferential-FB. Allowlist-free + deterministic
# → WARN. (The inverse — a journaling hook with no sensor entry — is deliberately
# NOT guarded: it needs a hand-maintained allowlist of non-sensor hooks, itself a
# drift seam. #34 + this cover the load-bearing direction.)
SENSORS_JSON="$CLAUDE_DIR/hooks/sensors.json"
if [ -f "$SENSORS_JSON" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r _sname; do
    [ -n "$_sname" ] || continue
    _hk=$(find "$CLAUDE_DIR/hooks" -type f -name "${_sname}*" 2>/dev/null | grep -E '\.(sh|py)$' | head -1)
    if [ -z "$_hk" ]; then
      warn "sensor '$_sname' in sensors.json has no matching hook script under hooks/ (orphan — staleness monitor will report false 'never fired')"
    fi
  done < <(jq -r '.sensors[].name' "$SENSORS_JSON" 2>/dev/null || true)
fi

