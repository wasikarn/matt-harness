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
# Assumes a response's lines are not split by a task-notification (0 of 63K runs in corpus).
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

# build_type_map <parent-transcript> <subagent-transcript-file>...
# Maps each subagent transcript to the `agentType` from its sibling
# agent-<id>.meta.json (Claude Code writes one alongside every agent-<id>.jsonl,
# carrying the real Agent-tool subagent_type — confirmed shape against a real
# transcript, 2026-08-07; 2762/2762 metas on this machine carried it, 2026-09-03).
# Fallback when meta has no agentType: its `toolUseId` keyed into the parent
# transcript's Agent tool_use `.input.subagent_type` — the only other place the
# type is recorded (the subagent JSONL itself carries none, and the parent never
# mentions the agent id, so a fully missing meta has no recoverable source).
# Missing/unreadable meta.json then falls back to "unknown" rather than dropping
# the row — a type gap shouldn't cost the spend data. The orchestrator's own
# transcript has no such sibling, so it's never passed as a subagent file;
# emit_rows treats a file absent from the map as agent_type:null.
#
# Each map value is {t: <agent_type>, r: <role>}. `r` is the chain role from the
# spawn brief's `[role: builder|validator|fixer|re-validator|research|other]` tag
# (docs/reference/spawn-brief.md), read from the subagent's first
# user message — the only place the brief lands. Fail-open: no tag, no user
# line, unreadable file → "unknown", never a dropped row (2026-09-03,
# docs/research/orchestrate-cost-optimization-2026-09-03.md candidate #10).
build_type_map() {
  local parent="$1" out='{}' f meta t tu r id; shift
  local parent_map vmap
  parent_map=$(jq -nRc '[inputs | try fromjson | select(.type == "assistant")
    | (.message.content // [])[]? | select(.type == "tool_use" and .name == "Agent")
    | {(.id): (.input.subagent_type // empty)}] | add // {}' "$parent" 2>/dev/null) || parent_map='{}'
  vmap=$(build_verify_map "$parent")
  for f in "$@"; do
    id=$(basename "$f" .jsonl); id="${id#agent-}"
    meta="${f%.jsonl}.meta.json"
    t=$([[ -f "$meta" ]] && jq -r '.agentType // empty' "$meta" 2>/dev/null)
    if [[ -z "$t" && -f "$meta" ]]; then
      tu=$(jq -r '.toolUseId // empty' "$meta" 2>/dev/null)
      [[ -n "$tu" ]] && t=$(printf '%s' "$parent_map" | jq -r --arg k "$tu" '.[$k] // empty' 2>/dev/null)
    fi
    [[ -z "$t" ]] && t="unknown"
    r=$(jq -nRr 'first(inputs | try fromjson | select(.type == "user"))
      | .message.content
      | if type == "string" then . else ([.[]? | .text? // empty] | join(" ")) end
      | ascii_downcase | capture("\\[role: *(?<r>[a-z-]+)\\]") | .r' "$f" 2>/dev/null) || r=''
    [[ -z "$r" ]] && r="unknown"
    out=$(printf '%s' "$out" | jq -c --arg f "$f" --arg t "$t" --arg r "$r" --arg id "$id" --argjson vmap "$vmap" \
      '. + {($f): {t: $t, r: $r, v: ($vmap[$id] // [])}}' 2>/dev/null) || out='{}'
  done
  printf '%s' "$out"
}

# build_verify_map <parent-transcript>
# The third handoff cost (docs/research/delegation-criteria-field-survey-2026-09-04.md
# gap G1): main's own tokens spent reading a subagent's return, re-reading files to
# verify it, and deciding — between that return and the next Agent dispatch. Each
# return lands in the main transcript as a `user` line whose string content starts
# `<task-notification>` with `<task-id>` = the subagent's file id (agent-<id>.jsonl);
# the Agent tool_result itself only says "Async agent launched" (verified against a
# real 23-dispatch session, 2026-09-04). A window opens at each notification and
# closes at the next notification, the first assistant line carrying an Agent
# tool_use (that line counts — deciding to dispatch is part of the handoff), a `user`
# line with plain string content that is not a notification (a human or injected
# prompt — main moved on; tool_result lines carry array content and keep the window
# open; measured 2026-09-04: 32% of windows held a human prompt, 70% of window tokens
# fell after one), a `user` line whose array content has no `tool_result` block and
# `isMeta != true` (an image-paste prompt — 37 in the corpus; same close), or EOF. Notification content is read as a string or a text-block
# array, same as the role capture in build_type_map.
# `v` sums input + cache_write + output (cache_write IS fresh input under prompt
# caching; raw input_tokens is ~2/turn), `c` keeps cache_read separate — the rent,
# not the work. Claude Code streams one JSONL line per content block of one response,
# all sharing `message.id`; the FIRST line carries a placeholder `output_tokens`, the
# LAST the final count (measured 2026-09-04 over 119,013 ids: last == max on 100% of
# differing ids; keeping the first line undercounted output 38.6%). So the last-seen
# usage per id is held in `pend` and flushed into the window it belongs to (`pw`) when
# the id changes or at EOF; the window-close check still runs on every line since the
# Agent tool_use block can sit on a later line of the same response. Lines with no id
# count per line (old transcripts). Output: {"<agent-id>": [{v,c}, ...]} — one entry
# per return (the same agent can notify more than once). Fail-open: any parse error → {}.
build_verify_map() {
  jq -nRc '
    def usage_v: (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.output_tokens // 0);
    def flush: if .pend != null and .pw != null and (.m[.pw.id] | length) > 0
      then .m[.pw.id][.pw.i].v += (.pend | usage_v) | .m[.pw.id][.pw.i].c += (.pend.cache_read_input_tokens // 0) else . end
      | .pend = null | .pw = null | .pid = null;
    reduce (inputs | try fromjson | select(.type == "user" or .type == "assistant")) as $l
    ({cur: null, m: {}, pend: null, pw: null, pid: null};
     if $l.type == "user" then
       ($l.message.content | if type == "string" then . else ([.[]? | .text? // empty] | join("")) end) as $txt
       | (($txt | select(startswith("<task-notification>"))
           | capture("<task-id>(?<id>[^<]+)</task-id>") | .id) // null) as $id
       | if $id then flush | .cur = $id | .m[$id] += [{v: 0, c: 0}]
         elif ($l.message.content | type) == "string" then flush | .cur = null
         elif ($l.message.content | type) == "array" and (($l.isMeta // false) != true)
              and (($l.message.content | any(.type? == "tool_result")) | not) then flush | .cur = null
         else . end
     elif ($l.message.usage != null) and (.cur != null or (($l.message.id // null) != null and $l.message.id == .pid)) then
       ($l.message.id // null) as $mid
       | if $mid == null or $mid != .pid then flush else . end
       | if .cur != null then .pw = {id: .cur, i: ((.m[.cur] | length) - 1)} else . end
       | .pend = $l.message.usage | .pid = $mid
       | if $mid == null then flush else . end
       | if (($l.message.content // []) | arrays | any(.type == "tool_use" and .name == "Agent")) then .cur = null else . end
     else . end)
    | flush | .m' "$1" 2>/dev/null || printf '{}'
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
#
# One API response spans several JSONL lines (one per content block) sharing one
# `message.id` — measured 2026-09-04 across every session on disk (119,013 ids):
# 92,431 same-usage duplicate lines vs 33,695 differing per id. Summing per line ran
# ~2.4x high; keeping the FIRST line per id (v0.68.639) undercounted output_tokens
# 38.6% — the first line carries a streaming placeholder, the last the final count
# (last == max on 100% of differing ids). The LAST line per (file, message.id) is
# kept, so `turns` = API responses; lines with no id (old transcripts) still count
# per line. Rows carry `dedup_usage: true` + `usage_pick: "last"` from then on.
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
        t: ($typemap[input_filename].t // null),
        r: ($typemap[input_filename].r // null),
        id: (.message.id // null),
        f: input_filename } ]
    | reduce .[] as $x ({byid: {}, out: []};
        if $x.id == null then .out += [$x]
        else .byid[$x.f + "\u0000" + $x.id] = $x end)
    | .out + (.byid | [.[]])
    | group_by([.m, .t, .r])
    | map(([.[].f] | unique | map($typemap[.].v // []) | add // []) as $w
      | {
        model: .[0].m,
        agent_type: .[0].t,
        role: .[0].r,
        turns: length,
        input_tokens: ((map(.in) | add) // 0),
        output_tokens: ((map(.out) | add) // 0),
        cache_write_tokens: ((map(.cw) | add) // 0),
        cache_read_tokens: ((map(.cr) | add) // 0),
        returns: ($w | length),
        verify_tokens: (if ($w | length) > 0 then ($w | map(.v) | add) else null end),
        verify_cache_read: (if ($w | length) > 0 then ($w | map(.c) | add) else null end),
        verify_per_return: ($w | map(.v))
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
      model_scoped: true, dedup_usage: true, usage_pick: "last", stream: $stream, agent_type: $u.agent_type, role: $u.role, turns: $u.turns,
      input_tokens: $u.input_tokens, output_tokens: $u.output_tokens,
      cache_write_tokens: $u.cache_write_tokens, cache_read_tokens: $u.cache_read_tokens,
      cache_read_per_turn: (if $u.turns > 0 then ($u.cache_read_tokens / $u.turns | round) else 0 end),
      returns: $u.returns, verify_tokens: $u.verify_tokens, verify_cache_read: $u.verify_cache_read,
      verify_per_return: $u.verify_per_return,
      rate_verified: $r.v,
      estimated_cost_usd: (
        ($u.input_tokens / 1e6 * $r.i) + ($u.output_tokens / 1e6 * $r.o) +
        ($u.cache_write_tokens / 1e6 * $r.cw) + ($u.cache_read_tokens / 1e6 * $r.cr) |
        (. * 1e6 | round) / 1e6
      ) }
  ' 2>/dev/null
}

if [[ -n "$transcript" && -f "$transcript" ]]; then
  # Orchestrator row: every return window, so its verify_tokens is the session total.
  orch_typemap=$(build_verify_map "$transcript" | jq -c --arg f "$transcript" \
    '{($f): {v: ([.[]] | add // [])}}' 2>/dev/null)
  [[ -z "$orch_typemap" ]] && orch_typemap='{}'
  rows=$(emit_rows orchestrator "$orch_typemap" "$transcript")

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
      sub_typemap=$(build_type_map "$transcript" "${sub_files[@]}")
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
