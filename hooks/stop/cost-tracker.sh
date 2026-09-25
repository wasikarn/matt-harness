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

# Change receipt: the plugin version that wrote the row and the HEAD commit of the
# session cwd, so a cost or quality regression is attributable to a policy version
# and has a rollback point. Either may be null; the row is written regardless.
mh_version=$(jq -r .version "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/.claude-plugin/plugin.json" 2>/dev/null)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
head_commit=$(git -C "${cwd:-/nonexistent}" rev-parse HEAD 2>/dev/null)

# Unset/relative HOME must never resolve into the current working directory --
# this exact bug once wrote a sibling metrics file into this repo's own tree
# (2026-08-28; see .gitignore's ".local/" comment and CHANGELOG.md).
# hooks/gates/_journal.py carries the identical guard for gate-decisions.jsonl.
if [ -z "${HOME:-}" ] || [[ "$HOME" != /* ]]; then
  printf '%s' "$payload"
  exit 0
fi

metrics_dir="$HOME/.local/share/kbg/metrics"
mkdir -p "$metrics_dir"

# Sonnet 5 pricing: $2/$10/$2.50/$0.20 per MTok. Originally introductory
# through 2026-08-31 with a scheduled reversion to $3/$15/$3.75/$0.30 on
# 2026-09-01 — that reversion was cancelled. Confirmed live against
# platform.claude.com/docs/en/about-claude/pricing, 2026-08-20: "The $2/$10
# ... pricing for Claude Sonnet 5 ... is now the standard price. The
# previously scheduled increase ... will not occur."
# cw1h $4.00 (issue #162, closed 2026-09-25): the 1-hour cache-write rate,
# confirmed live on the same pricing page as exactly 2x base input for every
# model in this file's table -- distinct from cw ($2.50), the 5-minute rate
# (1.25x input). See rate()'s cw1h fields below for the other models.
sonnet_rate='{"i":2.0,"o":10.0,"cw":2.50,"cw1h":4.00,"cr":0.20}'

# build_type_map <parent-map-json> <vmap-json> <subagent-transcript-file>...
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
# Each map value is {t: <agent_type>}.
#
# parent_map/vmap are now passed in pre-computed (2026-09-22 single-scan perf
# fix, see scan_transcript below) instead of re-deriving them from the parent
# transcript here — this function used to jq-scan the (potentially huge) main
# transcript twice on its own (once for parent_map, once via build_verify_map),
# on top of the two more full scans emit_rows and emit_codex_invocations did
# independently. Measured 9.5s/Stop-call against a real 158MB/42,838-line
# transcript before this fix (docs/research/cost-tracker-single-scan-perf-2026-09-22.md).
build_type_map() {
  local parent_map="$1" vmap="$2" out='{}' f meta t tu id; shift 2
  for f in "$@"; do
    id=$(basename "$f" .jsonl); id="${id#agent-}"
    meta="${f%.jsonl}.meta.json"
    t=$([[ -f "$meta" ]] && jq -r '.agentType // empty' "$meta" 2>/dev/null)
    if [[ -z "$t" && -f "$meta" ]]; then
      tu=$(jq -r '.toolUseId // empty' "$meta" 2>/dev/null)
      [[ -n "$tu" ]] && t=$(printf '%s' "$parent_map" | jq -r --arg k "$tu" '.[$k] // empty' 2>/dev/null)
    fi
    [[ -z "$t" ]] && t="unknown"
    out=$(printf '%s' "$out" | jq -c --arg f "$f" --arg t "$t" --arg id "$id" --argjson vmap "$vmap" \
      '. + {($f): {t: $t, v: ($vmap[$id] // [])}}' 2>/dev/null) || out='{}'
  done
  printf '%s' "$out"
}

# The third handoff cost (docs/research/delegation-criteria-field-survey-2026-09-04.md
# gap G1): main's own tokens spent reading a subagent's return, re-reading files to
# verify it, and deciding — between that return and the next Agent dispatch. Each
# return lands in the main transcript as a `user` line whose string content starts
# `<task-notification>` with `<task-id>` = the subagent's file id (agent-<id>.jsonl);
# the Agent tool_result itself only says "Async agent launched" (verified against a
# real 23-dispatch session, 2026-09-04). A window opens at each notification and
# closes at the next notification, the first assistant line carrying an Agent
# tool_use (that line counts — deciding to dispatch is part of the handoff), or EOF.
# `v` sums input + cache_write + output (cache_write IS fresh input under prompt
# caching; raw input_tokens is ~2/turn), `c` keeps cache_read separate — the rent,
# not the work. Same-message.id duplicate lines count once per line, matching
# emit_rows' `turns`. Output: {"<agent-id>": [{v,c}, ...]} — one entry per return
# (the same agent can notify more than once).
#
# 2026-09-20 restore note: reapplied from commit 6603c384 (removed alongside the
# unrelated [role:] tag in 2cac98c8) verbatim except for the role-grouping half,
# which stays removed per M14 — this mechanism is independent of role and answers
# a still-open question (docs/research/matt-harness-gap-audit-2026-09-20.md, H8).
#
# Only a <task-id> that resolves to a sibling agent-<id>.jsonl opens or closes a
# window: a background-Bash completion uses the same tag with a task-id that
# matches no agent file, and used to inflate `returns` and cut real windows
# short (2026-09-21 deep-audit finding). This logic used to live in its own
# build_verify_map(parent-transcript) function, called once for the orchestrator
# typemap and again (redundantly, on the identical input) inside build_type_map
# when subagents existed; folded into scan_transcript's single pass below
# (2026-09-22), same $ids-glob + jq filter, unchanged semantics.

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
# raw_records <typemap-json> <file>...
# Extracts + dedups per-API-response usage records (one per (file, message.id),
# last-line-wins — see emit_rows' original 2026-09-04 comment, unchanged) from
# one or more transcript files. Stops BEFORE grouping/pricing so the orchestrator
# path (scan_transcript below) can produce the same record shape from an
# already-parsed in-memory line set instead of re-reading the file here.
raw_records() {
  local typemap="$1"; shift
  jq -nRc --argjson typemap "$typemap" '
    [ inputs | try fromjson |
      select(.type == "assistant") |
      select((.message // {}).usage != null) |
      select((.message.model // "") | ascii_downcase | test("^claude")) |
      { in: (.message.usage.input_tokens // 0),
        out: (.message.usage.output_tokens // 0),
        cw: (.message.usage.cache_creation.ephemeral_5m_input_tokens // .message.usage.cache_creation_input_tokens // 0),
        cw1h: (.message.usage.cache_creation.ephemeral_1h_input_tokens // 0),
        cr: (.message.usage.cache_read_input_tokens // 0),
        m: (.message.model // "unknown"),
        t: ($typemap[input_filename].t // null),
        id: (.message.id // null),
        f: input_filename } ]
    | reduce .[] as $x ({byid: {}, out: []};
        if $x.id == null then .out += [$x]
        else .byid[$x.f + "\u0000" + $x.id] = $x end)
    | .out + (.byid | [.[]])
  ' "$@"
}

# group_and_price <typemap-json> <stream> <records-json>
# Groups already-extracted records by (model, agent_type), attaches each
# group's verify-window tokens from typemap, and prices each row. Pure jq over
# already-in-memory JSON — no file I/O — so both the subagent path (via
# emit_rows below, still file-scanning) and the orchestrator path (via
# scan_transcript, pre-scanned) share this one pricing implementation.
group_and_price() {
  local typemap="$1" stream="$2" records="$3"
  [[ -z "$records" || "$records" == "[]" ]] && return 0
  printf '%s' "$records" | jq -c --argjson typemap "$typemap" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sid "$session_id" \
    --arg tp "$transcript" \
    --arg stream "$stream" \
    --arg mhv "$mh_version" \
    --arg head "$head_commit" \
    --argjson sonnet_rate "$sonnet_rate" '
    def rate:
      # Haiku 4.5 and Opus 5/4.8 rates confirmed live against
      # platform.claude.com/docs/en/about-claude/pricing, 2026-07-31 —
      # the previously coded values were retired-model (Haiku 3.5, Opus
      # 4.1/4) pricing. See docs/research/official-docs-audit-2026-07-31.md.
      # Fable/Mythos 5.x: $10/$50 per MTok. cr is quoted, not derived: Fable 5.1
      # cache read is $0.25/MTok (not 0.1x input); Fable 5 is $1.00/MTok.
      # The 5-1 test must precede the bare fable test; same reason, the opus-5-5
      # test must precede the bare opus test ("opus-5-5" contains "opus").
      # Opus 5.5 (claude-opus-5-5): $4/$20/MTok, cr $0.20 — confirmed live
      # against platform.claude.com/docs/en/about-claude/pricing, 2026-09-25.
      # v:true here means the model matched this row, not that every field
      # was independently audited. cw is the 5-minute cache-write rate; cw1h
      # is the 1-hour rate -- each read directly off the live pricing table
      # own per-model column (platform.claude.com/docs/en/about-claude/pricing,
      # 2026-09-25), not derived from a formula, closing
      # https://github.com/wasikarn/matt-harness/issues/162. Every cw1h below
      # happens to equal 2x that branch own i (the page states this as the
      # general 1h-write multiplier), a cross-check, not the source of the
      # numbers -- cr on the fable/mythos branches is the proof a flat
      # multiplier cannot always be assumed instead of read. (raw_records/
      # scan_transcript above now read the Messages API usage objects own
      # cache_creation breakdown to tell 5m from 1h; cache_creation_input_tokens
      # alone never could.)
      if (.model | ascii_downcase | test("fable-5-1|mythos-5-1")) then {i:10.0,o:50.0,cw:12.50,cw1h:20.00,cr:0.25,v:true}
      elif (.model | ascii_downcase | test("fable|mythos")) then {i:10.0,o:50.0,cw:12.50,cw1h:20.00,cr:1.00,v:true}
      elif (.model | ascii_downcase | test("haiku")) then {i:1.00,o:5.0,cw:1.25,cw1h:2.00,cr:0.10,v:true}
      elif (.model | ascii_downcase | test("opus-5-5")) then {i:4.0,o:20.0,cw:5.00,cw1h:8.00,cr:0.20,v:true}
      elif (.model | ascii_downcase | test("opus")) then {i:5.0,o:25.0,cw:6.25,cw1h:10.00,cr:0.50,v:true}
      elif (.model | ascii_downcase | test("sonnet")) then ($sonnet_rate + {v:true})
      else ($sonnet_rate + {v:false}) end;
    ( group_by([.m, .t])
      | map(([.[].f] | unique | map($typemap[.].v // []) | add // []) as $w
        | {
          model: .[0].m,
          agent_type: .[0].t,
          turns: length,
          input_tokens: ((map(.in) | add) // 0),
          output_tokens: ((map(.out) | add) // 0),
          cache_write_tokens: ((map(.cw) | add) // 0),
          cache_write_tokens_1h: ((map(.cw1h) | add) // 0),
          cache_read_tokens: ((map(.cr) | add) // 0),
          returns: ($w | length),
          verify_tokens: (if ($w | length) > 0 then ($w | map(.v) | add) else null end),
          verify_cache_read: (if ($w | length) > 0 then ($w | map(.c) | add) else null end),
          verify_per_return: ($w | map(.v))
        })
      | map(select(.input_tokens + .output_tokens + .cache_write_tokens + .cache_write_tokens_1h + .cache_read_tokens > 0))
    )
    | .[] | . as $u | ($u | rate) as $r |
    { timestamp: $ts, session_id: $sid, transcript_path: $tp, model: $u.model,
      model_scoped: true, dedup_usage: true, usage_pick: "last", stream: $stream, agent_type: $u.agent_type, turns: $u.turns,
      input_tokens: $u.input_tokens, output_tokens: $u.output_tokens,
      cache_write_tokens: $u.cache_write_tokens, cache_write_tokens_1h: $u.cache_write_tokens_1h,
      cache_read_tokens: $u.cache_read_tokens,
      cache_read_per_turn: (if $u.turns > 0 then ($u.cache_read_tokens / $u.turns | round) else 0 end),
      returns: $u.returns, verify_tokens: $u.verify_tokens, verify_cache_read: $u.verify_cache_read,
      verify_per_return: $u.verify_per_return,
      rate_verified: $r.v,
      mh_version: (if $mhv == "" or $mhv == "null" then null else $mhv end),
      head_commit: (if $head == "" then null else $head end),
      estimated_cost_usd: (
        ($u.input_tokens / 1e6 * $r.i) + ($u.output_tokens / 1e6 * $r.o) +
        ($u.cache_write_tokens / 1e6 * $r.cw) + ($u.cache_write_tokens_1h / 1e6 * $r.cw1h) +
        ($u.cache_read_tokens / 1e6 * $r.cr) |
        (. * 1e6 | round) / 1e6
      ) }
  ' 2>/dev/null
}

# emit_rows <stream-label> <type-map-json> <transcript-file>...
# Thin wrapper: raw_records (file I/O + jq_failed sentinel handling, unchanged
# from before the 2026-09-22 split) -> group_and_price (pure, no file I/O).
# Still used for the subagent stream, which has no pre-scanned equivalent to
# scan_transcript below (subagent transcripts are typically small; only the
# main transcript — read via scan_transcript — was the measured hotspot).
emit_rows() {
  local stream="$1" typemap="$2"; shift 2
  (( $# )) || return 0
  local records jq_err jq_rc
  jq_err=$(mktemp 2>/dev/null) || jq_err=/dev/null
  records=$(raw_records "$typemap" "$@" 2>"$jq_err")
  jq_rc=$?
  if [[ $jq_rc -ne 0 ]]; then
    # A real jq failure (malformed transcript shape jq's own `try fromjson`
    # can't catch -- e.g. .message.usage indexed on a non-object -- or any
    # other runtime error) produced the exact same empty result as the
    # documented legitimate case (a session with no claude-model turns at
    # all). Distinguish them: emit a sentinel row instead of silently
    # reading as zero spend, so mh:cost-report can surface the gap rather
    # than a misleading "no spend that turn."
    echo "[mh:cost-tracker] emit_rows($stream): jq failed rc=$jq_rc on: $*" >&2
    cat "$jq_err" >&2 2>/dev/null
    rm -f "$jq_err" 2>/dev/null
    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$session_id" \
      --arg tp "$transcript" --arg stream "$stream" --arg files "$*" \
      '{timestamp: $ts, session_id: $sid, transcript_path: $tp, stream: $stream,
        error: "jq_failed", files: $files}' 2>/dev/null
    return 0
  fi
  rm -f "$jq_err" 2>/dev/null
  group_and_price "$typemap" "$stream" "$records"
}

# scan_transcript <transcript-file>
# Single jq pass over the main transcript, replacing what used to be 3-5
# separate full-file jq scans per Stop call (build_verify_map for the
# orchestrator typemap, build_type_map's own parent_map extraction PLUS its
# own internal build_verify_map re-scan when subagents exist, emit_rows'
# orchestrator extraction, emit_codex_invocations' main-transcript half) --
# each one an independent `jq -nR 'inputs | ...'` re-read of the same file.
# Measured 9.5s/Stop-call against a real 158MB/42,838-line transcript before
# this fix; a session's cumulative re-parse cost across T turns was O(T) work
# per Stop, i.e. O(T^2) total bytes parsed over the session
# (docs/research/cost-tracker-single-scan-perf-2026-09-22.md).
#
# All four sub-computations are wrapped in their own try/catch, matching each
# original function's own independent fallback ({} for verify_map/parent_map/
# codex, the {__error:true} marker for usages -- the caller's signal to emit
# the same jq_failed sentinel emit_rows always has). This preserves the
# original code's independent-failure-domain behavior: one malformed line
# breaks only the sub-computation that actually touches the field it's
# malformed on, never the other three. Getting this wrong is not
# hypothetical: an earlier draft left verify_map unwrapped on the assumption
# that only `usages` ever indexes .message.usage.<field> -- wrong, verify_map
# does the same arithmetic inside its own reduce once a verify-window is
# open, so a malformed usage line arriving INSIDE an open window (not H7's
# fixture shape, which has no window open at all) threw inside the whole
# combined object construction and silently dropped everything -- caught via
# a dedicated fixture, see docs/research/cost-tracker-single-scan-perf-2026-09-22.md.
scan_transcript() {
  local _d="${1%.jsonl}/subagents" _f _ids=()
  shopt -s nullglob
  for _f in "$_d"/agent-*.jsonl; do _f=$(basename "$_f" .jsonl); _ids+=("${_f#agent-}"); done
  shopt -u nullglob
  # ponytail: [inputs|try fromjson] materializes the whole parsed transcript
  # in jq's heap (the original code streamed `inputs` directly through each
  # separate reduce, never holding more than one parsed line at a time).
  # Fine at the measured 158MB/42,838 lines; upgrade path if a transcript
  # much larger than that ever shows up is a single streaming `reduce (inputs
  # | try fromjson) as $l (...)` computing all four accumulators together
  # instead of materializing $lines first.
  jq -nRc --arg tp "$1" --argjson ids "$(jq -nc '$ARGS.positional' --args ${_ids[@]+"${_ids[@]}"})" '
    [inputs | try fromjson] as $lines
    | {
        verify_map: ( try (
          reduce ($lines[] | select(.type == "user" or .type == "assistant")) as $l
            ({cur: null, m: {}};
             if $l.type == "user" then
               (($l.message.content | strings | select(startswith("<task-notification>"))
                 | capture("<task-id>(?<id>[^<]+)</task-id>") | .id | select(IN($ids[]))) // null) as $id
               | if $id then .cur = $id | .m[$id] += [{v: 0, c: 0}] else . end
             elif .cur != null and ($l.message.usage != null) then
               .cur as $id | ((.m[$id] | length) - 1) as $i
               | .m[$id][$i].v += (($l.message.usage.input_tokens // 0) + ($l.message.usage.cache_creation_input_tokens // 0) + ($l.message.usage.output_tokens // 0))
               | .m[$id][$i].c += ($l.message.usage.cache_read_input_tokens // 0)
               | if (($l.message.content // []) | arrays | any(.type == "tool_use" and .name == "Agent")) then .cur = null else . end
             else . end)
          | .m
        ) catch {} ),
        parent_map: ( try (
          [$lines[] | select(.type == "assistant")
            | (.message.content // [])[]? | select(.type == "tool_use" and .name == "Agent" and .id != null)
            | {(.id): (.input.subagent_type // empty)}] | add // {}
        ) catch {} ),
        usages: ( try (
          [ $lines[] |
            select(.type == "assistant") |
            select((.message // {}).usage != null) |
            select((.message.model // "") | ascii_downcase | test("^claude")) |
            { in: (.message.usage.input_tokens // 0),
              out: (.message.usage.output_tokens // 0),
              cw: (.message.usage.cache_creation.ephemeral_5m_input_tokens // .message.usage.cache_creation_input_tokens // 0),
              cw1h: (.message.usage.cache_creation.ephemeral_1h_input_tokens // 0),
              cr: (.message.usage.cache_read_input_tokens // 0),
              m: (.message.model // "unknown"),
              t: null,
              id: (.message.id // null),
              f: $tp } ]
          | reduce .[] as $x ({byid: {}, out: []};
              if $x.id == null then .out += [$x]
              else .byid[$x.id] = $x end)
          | .out + (.byid | [.[]])
        ) catch {__error: true, msg: .} ),
        codex: ( try (
          [$lines[] | select(.type == "assistant") |
            { c: (.message.content // []), id: (.message.id // null) }]
          | reduce .[] as $x ({byid: {}, out: []};
              if $x.id == null then .out += [$x]
              else .byid[$x.id] = $x end)
          | (.out + (.byid | [.[]])) | map(.c[]?) | map(select(.type == "tool_use")) |
            map(if .name == "Skill" and ((.input.skill // "") | startswith("codex:")) then .input.skill
                elif .name == "Agent" and ((.input.subagent_type // "") | startswith("codex:")) then .input.subagent_type
                else empty end)
          | group_by(.) | map({(.[0]): length}) | add // {}
        ) catch {} )
      }
  ' "$1"
}

# emit_codex_invocations <transcript-file>...
# Tallies `/codex:*` Skill and Agent tool_use calls across the given
# transcripts into one small counts object -- a count, not a cost (Codex
# exposes no local per-call price). Separate pass from emit_rows: that
# function only scans .message.usage on claude*-model turns, but a Codex
# tool_use block lives inside one of those same turns and needs its own scan.
# Same last-line-per-(file, message.id) dedup as emit_rows -- one API response
# spans several JSONL lines sharing one message.id (see emit_rows' own
# 2026-09-04 comment), so a tool_use block on a repeated line would otherwise
# be counted once per duplicate line, not once per real call.
emit_codex_invocations() {
  (( $# )) || return 0
  local counts
  counts=$(jq -nRc '
    [ inputs | try fromjson | select(.type == "assistant") |
      { c: (.message.content // []), id: (.message.id // null), f: input_filename } ]
    | reduce .[] as $x ({byid: {}, out: []};
        if $x.id == null then .out += [$x]
        else .byid[$x.f + "::" + $x.id] = $x end)
    | (.out + (.byid | [.[]])) | map(.c[]?) | map(select(.type == "tool_use")) |
      map(if .name == "Skill" and ((.input.skill // "") | startswith("codex:")) then .input.skill
          elif .name == "Agent" and ((.input.subagent_type // "") | startswith("codex:")) then .input.subagent_type
          else empty end)
    | group_by(.) | map({(.[0]): length}) | add // {}
  ' "$@" 2>/dev/null) || counts=''
  [[ -z "$counts" || "$counts" == "{}" ]] && return 0
  printf '%s' "$counts"
}

if [[ -n "$transcript" && -f "$transcript" ]]; then
  # Completion marker (#117): re-deriving totals from the transcript on every
  # Stop had no way to tell "already processed this turn" from "new turn" --
  # if the same Stop event ever fired twice for one turn, the append below
  # had no lease to recognize that and would double-write the row (same bug
  # shape as vercel/workflow#2376: a lease that dies the instant the
  # operation finishes lets a retry redo it from scratch instead of seeing it
  # already ran). The transcript only ever grows, so an unchanged byte size
  # for the same session_id + transcript_path means this Stop event has
  # already been processed for this exact state -- skip re-deriving and
  # re-appending entirely. One marker file per session_id (overwritten, not
  # appended) is enough: a duplicate Stop fires right after the original, not
  # some unbounded time later, so only the most recent key needs remembering.
  # Sequential duplicates only: this is check-then-write with no lock, and the
  # hook runs async (hooks.json), so two overlapping cost-tracker processes for
  # one session would both pass the check and both append. No observed case;
  # add a mkdir lock if one ever shows up.
  marker_dir="$metrics_dir/.markers"
  mkdir -p "$marker_dir" 2>/dev/null
  # session_id is taken verbatim from the Stop payload with no validation --
  # deep-audit finding (2026-09-21): every other use of session_id in this
  # repo treats it as a data field, never a path component, and
  # scripts/_lib/hook_payload.py already carries a shared validator
  # (`[A-Za-z0-9._-]+`, rejecting "." and "..") for exactly this reason.
  # Mirror that same character class here (this file is bash, that module is
  # Python) so a session_id containing "/" or ".." can't walk the marker
  # write outside $marker_dir. Low real-world severity -- normal Stop
  # payloads are produced by the Claude Code host, not by prompt-injectable
  # tool output -- but the guard is one line, same cost/benefit as the
  # existing symlink guard below.
  marker_id="$session_id"
  [[ "$marker_id" =~ ^[A-Za-z0-9._-]+$ && "$marker_id" != "." && "$marker_id" != ".." ]] || marker_id="default"
  marker_file="$marker_dir/$marker_id"
  transcript_size=$(wc -c < "$transcript" 2>/dev/null | tr -d ' ')
  dedup_key="$transcript"$'\t'"$transcript_size"
  if [[ -f "$marker_file" && "$(cat "$marker_file" 2>/dev/null)" == "$dedup_key" ]]; then
    printf '%s' "$payload"
    exit 0
  fi

  # Single pass over the main transcript (2026-09-22 perf fix — see
  # scan_transcript's own comment above) replaces the 3-5 separate full-file
  # jq scans this block used to run.
  scan=$(scan_transcript "$transcript")
  scan_rc=$?
  verify_map=$(printf '%s' "$scan" | jq -c '.verify_map' 2>/dev/null); [[ -z "$verify_map" ]] && verify_map='{}'
  parent_map=$(printf '%s' "$scan" | jq -c '.parent_map' 2>/dev/null); [[ -z "$parent_map" ]] && parent_map='{}'
  main_usages=$(printf '%s' "$scan" | jq -c '.usages' 2>/dev/null)
  main_codex=$(printf '%s' "$scan" | jq -c '.codex' 2>/dev/null); [[ -z "$main_codex" ]] && main_codex='{}'

  # Orchestrator row: every return window in the whole session, so its
  # verify_tokens is the session total handoff-verification cost.
  orch_typemap=$(printf '%s' "$verify_map" | jq -c --arg f "$transcript" \
    '{($f): {v: ([.[]] | add // [])}}' 2>/dev/null)
  [[ -z "$orch_typemap" ]] && orch_typemap='{}'
  # usages resolving to the {__error:true} marker means scan_transcript's own
  # try/catch caught a runtime error extracting usage records (H7 case); a
  # nonzero rc or empty $scan means the whole single-pass call itself failed
  # (defense in depth -- every sub-expression inside scan_transcript is now
  # individually try/caught, so this shouldn't fire, but a silently-dropped
  # orchestrator row on ANY failure mode would defeat the exact guarantee H7
  # exists for). Either way: emit the same jq_failed sentinel emit_rows
  # always has for this failure, never fail silently.
  usages_failed=0
  if [[ $scan_rc -ne 0 || -z "$scan" ]]; then
    usages_failed=1
  elif printf '%s' "$main_usages" | jq -e 'type == "object"' >/dev/null 2>&1; then
    usages_failed=1
  fi
  if [[ $usages_failed -eq 1 ]]; then
    usages_msg=$(printf '%s' "$main_usages" | jq -r '.msg // empty' 2>/dev/null)
    echo "[mh:cost-tracker] emit_rows(orchestrator): jq failed extracting usage records on: $transcript${usages_msg:+ -- $usages_msg}" >&2
    rows=$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$session_id" \
      --arg tp "$transcript" --arg stream orchestrator --arg files "$transcript" \
      '{timestamp: $ts, session_id: $sid, transcript_path: $tp, stream: $stream,
        error: "jq_failed", files: $files}' 2>/dev/null)
  else
    rows=$(group_and_price "$orch_typemap" orchestrator "$main_usages")
  fi

  # Claude Code writes each subagent to its own file under a sibling
  # <session-id>/subagents/ directory — NOT into the main transcript, which never
  # carries a row with isSidechain:true (verified against a real 15-subagent session,
  # 2026-08-07). Reading only .transcript_path therefore made every subagent's spend
  # invisible to mh:cost-report. Both halves are now counted and separable by `stream`.
  sub_dir="${transcript%.jsonl}/subagents"
  sub_files=()
  if [[ -d "$sub_dir" ]]; then
    shopt -s nullglob
    sub_files=("$sub_dir"/*.jsonl)
    shopt -u nullglob
    if (( ${#sub_files[@]} )); then
      sub_typemap=$(build_type_map "$parent_map" "$verify_map" "${sub_files[@]}")
      sub_rows=$(emit_rows subagent "$sub_typemap" "${sub_files[@]}")
      [[ -n "$sub_rows" ]] && rows="${rows:+$rows$'\n'}$sub_rows"
    fi
  fi

  # Codex tally: main transcript's contribution comes from the single scan
  # above; subagent files (typically small — not the measured hotspot) are
  # still scanned here. The two are summed per-key, not overwritten — the
  # original single combined call effectively did the same summation by
  # tallying tool_use blocks across every file's lines together.
  sub_codex=$(emit_codex_invocations "${sub_files[@]}"); [[ -z "$sub_codex" ]] && sub_codex='{}'
  codex_counts=$(jq -nc --argjson a "$main_codex" --argjson b "$sub_codex" \
    'reduce (($b | keys_unsorted)[]) as $k ($a; .[$k] = ((.[$k] // 0) + $b[$k]))' 2>/dev/null)
  [[ "$codex_counts" == "{}" ]] && codex_counts=''
  if [[ -n "$codex_counts" ]]; then
    codex_row=$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$session_id" \
      --argjson c "$codex_counts" '{timestamp: $ts, session_id: $sid, codex_invocations: $c}')
    [[ -n "$codex_row" ]] && rows="${rows:+$rows$'\n'}$codex_row"
  fi

  metrics_file="$metrics_dir/costs.jsonl"
  # Refuse to append through a symlink — caveman (JuliusBrussee/caveman,
  # src/hooks/caveman-config.js) hardens this exact predictable-path-append
  # pattern against a same-user local attacker swapping the target for a
  # symlink into an arbitrary writable file. Narrower threat here (data
  # corruption, not privilege escalation — the attacker already needs
  # same-user write access to plant the symlink) but the guard is one line.
  # Only mark this transcript state done if there was nothing to persist, or
  # it was actually persisted. Marking it done on ANY failed append (blocked
  # by the symlink guard, or any other append error -- deep-audit finding,
  # 2026-09-21: the symlink-only version of this check missed a plain write
  # failure, e.g. a full disk or a broken path) would be the exact bug this
  # fix closes, inverted: a completion lease set on a write that never
  # happened, so a later retry (transcript unchanged) would never get
  # another chance to append it.
  append_ok=1
  if [[ -n "$rows" ]]; then
    if [[ -L "$metrics_file" ]]; then
      append_ok=0
    else
      printf '%s\n' "$rows" >> "$metrics_file" || append_ok=0
    fi
  fi
  # Same `-L` guard as the costs.jsonl append above: a pre-planted symlink at
  # .markers/<session_id> must not redirect this truncating write.
  (( append_ok )) && [[ ! -L "$marker_file" ]] && printf '%s' "$dedup_key" > "$marker_file" 2>/dev/null
fi

printf '%s' "$payload"
exit 0
