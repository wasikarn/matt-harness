#!/usr/bin/env bash
# Stop: log cumulative per-model token usage to ~/.local/share/kbg/metrics/costs.jsonl
#
# Re-derives cumulative token totals from the full transcript on every stop (stateless
# by design — no separate counter file to corrupt or fall out of sync). Grouping by
# `.message.model` before summing, instead of tagging one whole-session sum with
# whichever model was last active, is what makes a row's numbers belong to that model
# alone: a session that switches models gets one row per model actually used, each
# with that model's own true cumulative tokens/cost. `model_scoped: true` marks rows
# in this format so a reader (commands/cost-report.md) can tell them apart from rows
# written by the pre-fix version of this hook, which never carried the field and whose
# per-row cost was the whole session's cumulative total repriced at the current model.
set -uo pipefail

payload=$(cat)

transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null)

metrics_dir="$HOME/.local/share/kbg/metrics"
mkdir -p "$metrics_dir"

if [[ -n "$transcript" && -f "$transcript" ]]; then
  usages=$(jq -Rsc '
    [ split("\n")[] | select(. != "") | try fromjson |
      select(.type == "assistant") |
      select((.message // {}).usage != null) |
      { in: (.message.usage.input_tokens // 0),
        out: (.message.usage.output_tokens // 0),
        cw: (.message.usage.cache_creation_input_tokens // 0),
        cr: (.message.usage.cache_read_input_tokens // 0),
        m: (.message.model // "unknown") } ]
    | group_by(.m)
    | map({
        model: .[0].m,
        input_tokens: ((map(.in) | add) // 0),
        output_tokens: ((map(.out) | add) // 0),
        cache_write_tokens: ((map(.cw) | add) // 0),
        cache_read_tokens: ((map(.cr) | add) // 0)
      })
    | map(select(.input_tokens + .output_tokens + .cache_write_tokens + .cache_read_tokens > 0))
  ' "$transcript" 2>/dev/null) || usages=''

  if [[ -n "$usages" && "$usages" != "[]" ]]; then
    rows=$(printf '%s' "$usages" | jq -c \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg sid "$session_id" \
      --arg tp "$transcript" '
      def rate:
        if (.model | ascii_downcase | test("haiku")) then {i:0.80,o:4.0,cw:1.00,cr:0.08,v:true}
        elif (.model | ascii_downcase | test("opus")) then {i:15.0,o:75.0,cw:18.75,cr:1.50,v:true}
        elif (.model | ascii_downcase | test("sonnet")) then {i:3.0,o:15.0,cw:3.75,cr:0.30,v:true}
        else {i:3.0,o:15.0,cw:3.75,cr:0.30,v:false} end;
      .[] | . as $u | ($u | rate) as $r |
      { timestamp: $ts, session_id: $sid, transcript_path: $tp, model: $u.model,
        model_scoped: true,
        input_tokens: $u.input_tokens, output_tokens: $u.output_tokens,
        cache_write_tokens: $u.cache_write_tokens, cache_read_tokens: $u.cache_read_tokens,
        rate_verified: $r.v,
        estimated_cost_usd: (
          ($u.input_tokens / 1e6 * $r.i) + ($u.output_tokens / 1e6 * $r.o) +
          ($u.cache_write_tokens / 1e6 * $r.cw) + ($u.cache_read_tokens / 1e6 * $r.cr) |
          (. * 1e6 | round) / 1e6
        ) }
    ' 2>/dev/null) && [[ -n "$rows" ]] && printf '%s\n' "$rows" >> "$metrics_dir/costs.jsonl"
  fi
fi

printf '%s' "$payload"
exit 0
