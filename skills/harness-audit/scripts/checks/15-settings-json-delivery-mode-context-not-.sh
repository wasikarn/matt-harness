# 15. settings.json delivery mode — context, NOT a finding. In the single
# plugin-delivery path (ADR 0001) settings.json carries only `hooks`; the
# commands/agents/skills arrays are absent BY DESIGN (loaded from the plugin
# cache). That's permanent, not drift, so a missing array fires every run and
# is never actionable — same shape as the demoted F1/plugin-cache line. Print
# it as context alongside Root:/Fleet:, don't emit info() noise.
if [ -f "$SETTINGS" ]; then
  _missing=""
  for _k in commands agents skills; do
    python3 -c "import json,sys; d=json.load(open('$SETTINGS')); sys.exit(0 if '$_k' in d else 1)" 2>/dev/null || _missing="$_missing $_k"
  done
  [ -n "$_missing" ] && echo "settings.json delivery: arrays absent ($_missing ) — loaded via plugin cache / ~/.claude directly"
fi

