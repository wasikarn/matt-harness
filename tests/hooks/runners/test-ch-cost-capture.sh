#!/usr/bin/env bash
# test-ch-cost-capture.sh — the SessionEnd cost-capture sensor. Sums per-message
# token usage from the transcript (deduped by message id), journals a cost_capture
# event, and NEVER blocks. Distinguishing assertions: dedup (a repeated message id
# must count once) and redaction-survival (the count fields must NOT be named with
# the substring "token", or the journal's secret-redactor nukes them — revert the
# short field names and "total":195 flips to "[redacted]" and this suite fails).
# shellcheck disable=SC1090,SC2034
# shellcheck shell=bash
source "$(dirname "$0")/test-critical-hooks-lib.sh"

HOOK="$HOOKS/session/cost-capture.sh"

# fixture: 2 unique assistant msgs + 1 DUPLICATE id (dedup) + 1 user line (no usage)
FIX="$FIXTURE/transcript.jsonl"
python3 - "$FIX" <<'PY'
import json, sys
lines = [
    {"type": "user", "message": {"role": "user"}},
    {"message": {"id": "msg_1", "usage": {"input_tokens": 10, "output_tokens": 20, "cache_creation_input_tokens": 5, "cache_read_input_tokens": 100}}},
    {"message": {"id": "msg_1", "usage": {"input_tokens": 10, "output_tokens": 20, "cache_creation_input_tokens": 5, "cache_read_input_tokens": 100}}},
    {"message": {"id": "msg_2", "usage": {"input_tokens": 3, "output_tokens": 7, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 50}}},
]
open(sys.argv[1], "w").write("\n".join(json.dumps(x) for x in lines))
PY

JOURNAL="$FIXTURE/journal.jsonl"
RC=0
printf '%s' "{\"transcript_path\":\"$FIX\"}" | CLAUDE_JOURNAL_PATH="$JOURNAL" bash "$HOOK" || RC=$?

# Extract fields numerically (format-independent) + a redaction flag.
read -r EV MSGS TOTAL CR RED <<<"$(python3 -c "
import json
try:
    e = json.loads(open('$JOURNAL').read().strip()); f = e.get('fields', {})
    red = '1' if 'redacted' in json.dumps(f).lower() else '0'
    print(e.get('event', 'x'), f.get('messages', 'x'), f.get('total', 'x'), f.get('cache_read', 'x'), red)
except Exception:
    print('x x x x 1')
")"

ccheck() {  # ccheck <rc> <label>
  if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "cost-capture" "$2"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "cost-capture" "$2"; fi
}

[ "$RC" -eq 0 ];        ccheck $? "exit 0 (advisory — never blocks)"
[ "$EV" = "cost_capture" ]; ccheck $? "journals a cost_capture event"
[ "$MSGS" = "2" ];      ccheck $? "dedup: counts unique msgs (2, not 3)"
[ "$TOTAL" = "195" ];   ccheck $? "sums tokens (total=195) AND survives the redactor"
[ "$CR" = "150" ];      ccheck $? "cache_read summed across msgs (150)"
[ "$RED" = "0" ];       ccheck $? "no [redacted] in count fields"

# graceful: no transcript_path → exit 0, no event written
RC2=0; J2="$FIXTURE/j2.jsonl"
printf '%s' '{}' | CLAUDE_JOURNAL_PATH="$J2" bash "$HOOK" || RC2=$?
{ [ "$RC2" -eq 0 ] && [ ! -f "$J2" ]; }; ccheck $? "graceful on missing transcript_path (exit 0, no event)"

report
