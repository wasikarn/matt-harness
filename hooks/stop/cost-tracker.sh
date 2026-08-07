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

# Sonnet 5 runs introductory pricing ($2/$10/$2.50/$0.20 per MTok) through
# 2026-08-31; standard pricing ($3/$15/$3.75/$0.30, unchanged from prior
# Sonnet generations) resumes 2026-09-01. Confirmed live against
# platform.claude.com/docs/en/about-claude/pricing, 2026-07-31 —
# docs/research/official-docs-audit-2026-07-31.md.
if [[ "$(date -u +%Y%m%d)" -lt 20260901 ]]; then
  sonnet_rate='{"i":2.0,"o":10.0,"cw":2.50,"cr":0.20}'
else
  sonnet_rate='{"i":3.0,"o":15.0,"cw":3.75,"cr":0.30}'
fi

# emit_rows <stream-label> <transcript-file>...
# Aggregates every named JSONL transcript into one priced row per model, tagged
# with the stream it came from. `jq -Rs` slurps all file arguments into a single
# string before parsing, so a whole subagents/ directory aggregates in one pass.
# `turns` and `cache_read_per_turn` are what make the orchestrator's carried-context
# cost readable: cache_read is re-billed on every turn, so per-turn is the rent rate,
# not the one-off bill — docs/research/orchestrator-tax-gap-analysis-2026-08-07.md.
emit_rows() {
  local stream="$1"; shift
  (( $# )) || return 0
  local usages
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
        turns: length,
        input_tokens: ((map(.in) | add) // 0),
        output_tokens: ((map(.out) | add) // 0),
        cache_write_tokens: ((map(.cw) | add) // 0),
        cache_read_tokens: ((map(.cr) | add) // 0)
      })
    | map(select(.input_tokens + .output_tokens + .cache_write_tokens + .cache_read_tokens > 0))
  ' "$@" 2>/dev/null) || usages=''
  [[ -z "$usages" || "$usages" == "[]" ]] && return 0
  printf '%s' "$usages" | jq -c \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sid "$session_id" \
    --arg tp "$transcript" \
    --arg stream "$stream" \
    --argjson sonnet_rate "$sonnet_rate" '
    def rate:
      # Haiku 4.5 and Opus 5/4.8 rates confirmed live against
      # platform.claude.com/docs/en/about-claude/pricing, 2026-07-31 —
      # the previously coded values were retired-model (Haiku 3.5, Opus
      # 4.1/4) pricing. See docs/research/official-docs-audit-2026-07-31.md.
      if (.model | ascii_downcase | test("haiku")) then {i:1.00,o:5.0,cw:1.25,cr:0.10,v:true}
      elif (.model | ascii_downcase | test("opus")) then {i:5.0,o:25.0,cw:6.25,cr:0.50,v:true}
      elif (.model | ascii_downcase | test("sonnet")) then ($sonnet_rate + {v:true})
      else ($sonnet_rate + {v:false}) end;
    .[] | . as $u | ($u | rate) as $r |
    { timestamp: $ts, session_id: $sid, transcript_path: $tp, model: $u.model,
      model_scoped: true, stream: $stream, turns: $u.turns,
      input_tokens: $u.input_tokens, output_tokens: $u.output_tokens,
      cache_write_tokens: $u.cache_write_tokens, cache_read_tokens: $u.cache_read_tokens,
      cache_read_per_turn: (if $u.turns > 0 then ($u.cache_read_tokens / $u.turns | round) else 0 end),
      rate_verified: $r.v,
      estimated_cost_usd: (
        ($u.input_tokens / 1e6 * $r.i) + ($u.output_tokens / 1e6 * $r.o) +
        ($u.cache_write_tokens / 1e6 * $r.cw) + ($u.cache_read_tokens / 1e6 * $r.cr) |
        (. * 1e6 | round) / 1e6
      ) }
  ' 2>/dev/null
}

if [[ -n "$transcript" && -f "$transcript" ]]; then
  rows=$(emit_rows orchestrator "$transcript")

  # Claude Code writes each subagent to its own file under a sibling
  # <session-id>/subagents/ directory — NOT into the main transcript, which never
  # carries a row with isSidechain:true (verified against a real 15-subagent session,
  # 2026-08-07). Reading only .transcript_path therefore made every subagent's spend
  # invisible to /cost-report. Both halves are now counted and separable by `stream`.
  sub_dir="${transcript%.jsonl}/subagents"
  if [[ -d "$sub_dir" ]]; then
    shopt -s nullglob
    sub_files=("$sub_dir"/*.jsonl)
    shopt -u nullglob
    if (( ${#sub_files[@]} )); then
      sub_rows=$(emit_rows subagent "${sub_files[@]}")
      [[ -n "$sub_rows" ]] && rows="${rows:+$rows$'\n'}$sub_rows"
    fi
  fi

  metrics_file="$metrics_dir/costs.jsonl"
  # Refuse to append through a symlink — caveman (JuliusBrussee/caveman,
  # src/hooks/caveman-config.js) hardens this exact predictable-path-append
  # pattern against a same-user local attacker swapping the target for a
  # symlink into an arbitrary writable file. Narrower threat here (data
  # corruption, not privilege escalation — the attacker already needs
  # same-user write access to plant the symlink) but the guard is one line.
  [[ -n "$rows" && ! -L "$metrics_file" ]] && printf '%s\n' "$rows" >> "$metrics_file"
fi

printf '%s' "$payload"
exit 0
