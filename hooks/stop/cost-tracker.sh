#!/usr/bin/env bash
# Stop: log cumulative session token usage to ~/.local/share/kbg/metrics/costs.jsonl
set -uo pipefail

payload=$(cat)

transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null)

metrics_dir="$HOME/.local/share/kbg/metrics"
mkdir -p "$metrics_dir"

if [[ -n "$transcript" && -f "$transcript" ]]; then
  usage=$(jq -Rs '
    [ split("\n")[] | select(. != "") | try fromjson |
      select(.type == "assistant") |
      select((.message // {}).usage != null) |
      { in: (.message.usage.input_tokens // 0),
        out: (.message.usage.output_tokens // 0),
        cw: (.message.usage.cache_creation_input_tokens // 0),
        cr: (.message.usage.cache_read_input_tokens // 0),
        m: (.message.model // "unknown") } ] |
    if length == 0 then null
    else {
      input_tokens: (map(.in) | add),
      output_tokens: (map(.out) | add),
      cache_write_tokens: (map(.cw) | add),
      cache_read_tokens: (map(.cr) | add),
      model: (last.m // "unknown")
    } end
  ' "$transcript" 2>/dev/null) || usage=''

  if [[ -n "$usage" && "$usage" != "null" ]]; then
    row=$(printf '%s' "$usage" | jq -c \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg sid "$session_id" \
      --arg tp "$transcript" '
      def rate:
        if (.model | ascii_downcase | test("haiku")) then {i:0.80,o:4.0,cw:1.00,cr:0.08,v:true}
        elif (.model | ascii_downcase | test("opus")) then {i:15.0,o:75.0,cw:18.75,cr:1.50,v:true}
        elif (.model | ascii_downcase | test("sonnet")) then {i:3.0,o:15.0,cw:3.75,cr:0.30,v:true}
        else {i:3.0,o:15.0,cw:3.75,cr:0.30,v:false} end;
      . as $u | rate as $r |
      { timestamp: $ts, session_id: $sid, transcript_path: $tp, model: $u.model,
        input_tokens: $u.input_tokens, output_tokens: $u.output_tokens,
        cache_write_tokens: $u.cache_write_tokens, cache_read_tokens: $u.cache_read_tokens,
        rate_verified: $r.v,
        estimated_cost_usd: (
          ($u.input_tokens / 1e6 * $r.i) + ($u.output_tokens / 1e6 * $r.o) +
          ($u.cache_write_tokens / 1e6 * $r.cw) + ($u.cache_read_tokens / 1e6 * $r.cr) |
          (. * 1e6 | round) / 1e6
        ) }
    ' 2>/dev/null) && [[ -n "$row" ]] && printf '%s\n' "$row" >> "$metrics_dir/costs.jsonl"
  fi
fi

printf '%s' "$payload"
exit 0
