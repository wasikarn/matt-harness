#!/usr/bin/env bash
# Stop: log cumulative per-model token usage to ~/.local/share/kbg/metrics/costs.jsonl
#
# Re-derives cumulative token totals from the full transcript on every stop (stateless
# by design — no separate counter file to corrupt or fall out of sync). Grouping by
# `.message.model` before summing, instead of tagging one whole-session sum with
# whichever model was last active, is what makes a row's numbers belong to that model
# alone: a session that switches models gets one row per model actually used, each
# with that model's own true cumulative tokens/cost. `model_scoped: true` marks rows
# in this format so a reader (skills/meta/cost-report/SKILL.md) can tell them apart from rows
# written by the pre-fix version of this hook, which never carried the field and whose
# per-row cost was the whole session's cumulative total repriced at the current model.
set -uo pipefail

payload=$(cat)

# Portability guard (#93): every extraction and aggregation below is jq. Skip
# metrics entirely without it — announced once per session by
# doctrine-bootstrap.sh's preflight, not per-stop (a Stop hook fires every turn).
if ! command -v jq >/dev/null 2>&1; then
  printf '%s' "$payload"
  exit 0
fi

transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null)

metrics_dir="$HOME/.local/share/kbg/metrics"
mkdir -p "$metrics_dir"

# Sonnet 5 pricing: $2/$10/$2.50/$0.20 per MTok. Originally introductory
# through 2026-08-31 with a scheduled reversion to $3/$15/$3.75/$0.30 on
# 2026-09-01 — that reversion was cancelled. Confirmed live against
# platform.claude.com/docs/en/about-claude/pricing, 2026-08-20: "The $2/$10
# ... pricing for Claude Sonnet 5 ... is now the standard price. The
# previously scheduled increase ... will not occur."
sonnet_rate='{"i":2.0,"o":10.0,"cw":2.50,"cr":0.20}'

# build_type_map <transcript-file>...
# Maps each subagent transcript to the `agentType` from its sibling
# agent-<id>.meta.json (Claude Code writes one alongside every agent-<id>.jsonl,
# carrying the real Agent-tool subagent_type — confirmed shape against a real
# transcript, 2026-08-07). Missing/unreadable meta.json falls back to "unknown"
# rather than dropping the row — a type gap shouldn't cost the spend data. The
# orchestrator's own transcript has no such sibling, so it's never passed here;
# emit_rows treats a file absent from the map as agent_type:null.
build_type_map() {
  local out='{}' f meta t
  for f in "$@"; do
    meta="${f%.jsonl}.meta.json"
    t=$([[ -f "$meta" ]] && jq -r '.agentType // empty' "$meta" 2>/dev/null)
    [[ -z "$t" ]] && t="unknown"
    out=$(printf '%s' "$out" | jq -c --arg f "$f" --arg t "$t" '. + {($f): $t}' 2>/dev/null) || out='{}'
  done
  printf '%s' "$out"
}

# emit_rows <stream-label> <type-map-json> <transcript-file>...
# Aggregates every named JSONL transcript into one priced row per (model, agent_type)
# pair, tagged with the stream it came from. Reads files un-slurped (`-nR` + `inputs`,
# not `-Rs`) so `input_filename` can key into the type map per line — a whole
# subagents/ directory still aggregates in one jq pass, but two agent types spending
# on the same model no longer collapse into one row. `turns` and `cache_read_per_turn`
# are what make the orchestrator's carried-context cost readable: cache_read is
# re-billed on every turn, so per-turn is the rent rate, not the one-off bill —
# docs/research/orchestrator-tax-gap-analysis-2026-08-07.md.
#
# Claude-only, at operator request (2026-08-07): a session can run non-Claude models
# (a proxy swapping ANTHROPIC_BASE_URL) — confirmed real in production data
# (minimax-m3, glm-5.2, kimi-k2.7-code, nemotron-3-super all showed real spend). Those
# turns are dropped before grouping, not priced at a guessed rate — this hook only
# tracks claude-* spend.
emit_rows() {
  local stream="$1" typemap="$2"; shift 2
  (( $# )) || return 0
  local usages
  usages=$(jq -nRc --argjson typemap "$typemap" '
    [ inputs | try fromjson |
      select(.type == "assistant") |
      select((.message // {}).usage != null) |
      select((.message.model // "") | ascii_downcase | test("^claude")) |
      { in: (.message.usage.input_tokens // 0),
        out: (.message.usage.output_tokens // 0),
        cw: (.message.usage.cache_creation_input_tokens // 0),
        cr: (.message.usage.cache_read_input_tokens // 0),
        m: (.message.model // "unknown"),
        t: ($typemap[input_filename] // null) } ]
    | group_by([.m, .t])
    | map({
        model: .[0].m,
        agent_type: .[0].t,
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
      model_scoped: true, stream: $stream, agent_type: $u.agent_type, turns: $u.turns,
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
  rows=$(emit_rows orchestrator '{}' "$transcript")

  # Claude Code writes each subagent to its own file under a sibling
  # <session-id>/subagents/ directory — NOT into the main transcript, which never
  # carries a row with isSidechain:true (verified against a real 15-subagent session,
  # 2026-08-07). Reading only .transcript_path therefore made every subagent's spend
  # invisible to mh:cost-report. Both halves are now counted and separable by `stream`.
  sub_dir="${transcript%.jsonl}/subagents"
  if [[ -d "$sub_dir" ]]; then
    shopt -s nullglob
    sub_files=("$sub_dir"/*.jsonl)
    shopt -u nullglob
    if (( ${#sub_files[@]} )); then
      sub_typemap=$(build_type_map "${sub_files[@]}")
      sub_rows=$(emit_rows subagent "$sub_typemap" "${sub_files[@]}")
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
