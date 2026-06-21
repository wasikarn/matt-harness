#!/bin/bash
# Cost-capture hook — at SessionEnd, sum the session's token usage from the
# transcript and journal a `cost_capture` governance event.
#
# Honest TOKEN counts only — NO dollar estimate. There is no honest local price
# signal (prices are model-specific and drift); faking one would violate
# no-fake-metrics, the same reasoning behind the L3 `--max-cost` deferral.
#
# This is the FEEDBACK half of METHODOLOGY Rule 6 (token budgets are not
# advisory) and the Böckeler 2x2's "feedforward needs feedback" — kbg preached
# token discipline but never measured spend (usage-monitor tried and failed on a
# wrong jq path; this reads the real per-message `usage` fields). Computational-FB
# sensor: advisory only, never blocks, always exit 0.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=cost-capture

HOOK_ID="cost-capture"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$TRANSCRIPT" ] || exit 0
[ -f "$TRANSCRIPT" ] || exit 0

# Sum per-assistant-message usage, deduped by message id. Streamed partials can
# repeat a usage block for the same API response; counting per unique id avoids
# double-counting. Tokens are the honest, exact signal; dollars are not minted.
PAYLOAD=$(python3 - "$TRANSCRIPT" <<'PY' 2>/dev/null
import json, sys
path = sys.argv[1]
seen = set()
# Output keys deliberately avoid the substring "token": the journal's secret-
# redactor (_lib.sh) nukes any field whose name matches token|secret|key|... .
# These are usage COUNTS, not secrets — short names keep them out of the journal.
SRC = {"input": "input_tokens", "output": "output_tokens",
       "cache_write": "cache_creation_input_tokens", "cache_read": "cache_read_input_tokens"}
tot = {k: 0 for k in SRC}
msgs = 0
try:
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                d = json.loads(line)
            except Exception:
                continue
            m = d.get("message") or {}
            u = m.get("usage")
            if not isinstance(u, dict):
                continue
            mid = m.get("id") or d.get("uuid")
            if mid is not None:
                if mid in seen:
                    continue
                seen.add(mid)
            msgs += 1
            for short, full in SRC.items():
                v = u.get(full)
                if isinstance(v, int):
                    tot[short] += v
except OSError:
    sys.exit(1)
out = {"messages": msgs, "total": sum(tot.values())}
out.update(tot)
print(json.dumps(out))
PY
)
[ -n "$PAYLOAD" ] || exit 0

journal_append "$HOOK_ID" "cost_capture" "$PAYLOAD" >/dev/null 2>&1 || true
exit 0
