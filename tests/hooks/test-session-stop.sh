#!/usr/bin/env bash
# Session/Stop hook smoke tests: doctrine-bootstrap (SessionStart),
# command-root-anchor (SessionStart), cost-tracker (Stop). These hooks never
# block (no permissionDecision) — tests assert exit 0 + expected side effect
# (stdout injection / env-file append / metrics-file append), and that each
# fails safe (exit 0, no side effect) when its required env var is unset.
# Run standalone: bash tests/hooks/test-session-stop.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DOCTRINE="$ROOT/hooks/session/doctrine-bootstrap.sh"
ROOT_ANCHOR="$ROOT/hooks/session/command-root-anchor.sh"
COST_TRACKER="$ROOT/hooks/stop/cost-tracker.sh"

pass=0
fail=0

assert() {
  local desc="$1" ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "  ✅ $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ $desc" >&2
    fail=$((fail + 1))
  fi
}

# make_transcript_line <model> <input_tokens> <output_tokens> [cache_read_tokens]
# One assistant-turn JSONL line. cache_creation is always 0; cache_read defaults to 0
# and is settable because the orchestrator-tax split reports cache_read_per_turn.
make_transcript_line() {
  python3 -c 'import json,sys; print(json.dumps({"type": "assistant", "message": {"model": sys.argv[1],
    "usage": {"input_tokens": int(sys.argv[2]), "output_tokens": int(sys.argv[3]),
              "cache_creation_input_tokens": 0,
              "cache_read_input_tokens": int(sys.argv[4]) if len(sys.argv) > 4 else 0}}}))' "$1" "$2" "$3" ${4:+"$4"}
}

echo "=== doctrine-bootstrap hook (SessionStart) ==="

out=$(CLAUDE_PLUGIN_ROOT="$ROOT" bash "$DOCTRINE" 2>/dev/null)
rc=$?
# Markers AND a real content token: asserting only the open/close markers would
# pass on an empty/rotted injection (silent doctrine-content rot). "Decision-sizing
# triad" is Rule 1's heading in docs/METHODOLOGY.md — its presence proves the
# body was injected, not just the wrapper.
[[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q '<!-- kbg:doctrine-bootstrap -->' \
  && echo "$out" | /usr/bin/grep -q '<!-- /kbg:doctrine-bootstrap -->' \
  && echo "$out" | /usr/bin/grep -q 'Decision-sizing triad' && ok=1 || ok=0
assert "injects METHODOLOGY.md wrapped in markers when plugin root is valid" "$ok"

out=$(env -u CLAUDE_PLUGIN_ROOT bash "$DOCTRINE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "fails safe (exit 0, silent) when CLAUDE_PLUGIN_ROOT is unset" "$ok"

out=$(CLAUDE_PLUGIN_ROOT="/nonexistent-plugin-root" bash "$DOCTRINE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "fails safe (exit 0, silent) when plugin root path doesn't exist" "$ok"

echo ""
echo "=== command-root-anchor hook (SessionStart) ==="

envfile=$(mktemp)
CLAUDE_PLUGIN_ROOT="/some/plugin/root/" CLAUDE_ENV_FILE="$envfile" bash "$ROOT_ANCHOR" 2>/dev/null
rc=$?
[[ "$rc" == "0" ]] && /usr/bin/grep -qx 'export KBG_PLUGIN_ROOT=/some/plugin/root' "$envfile" && ok=1 || ok=0
assert "strips trailing slash and appends export to CLAUDE_ENV_FILE" "$ok"
rm -f "$envfile"

envfile=$(mktemp)
env -u CLAUDE_PLUGIN_ROOT CLAUDE_ENV_FILE="$envfile" bash "$ROOT_ANCHOR" 2>/dev/null
rc=$?
[[ "$rc" == "0" && ! -s "$envfile" ]] && ok=1 || ok=0
assert "fails safe (exit 0, no append) when CLAUDE_PLUGIN_ROOT is unset" "$ok"
rm -f "$envfile"

CLAUDE_PLUGIN_ROOT="/some/plugin/root" env -u CLAUDE_ENV_FILE bash "$ROOT_ANCHOR" 2>/dev/null
rc=$?
[[ "$rc" == "0" ]] && ok=1 || ok=0
assert "fails safe (exit 0) when CLAUDE_ENV_FILE is unset" "$ok"

echo ""
echo "=== cost-tracker hook (Stop) ==="

fake_home=$(mktemp -d)
transcript=$(mktemp)
make_transcript_line claude-sonnet-5 100 50 > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-session"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
# cost-tracker appends with `jq -c` → one compact JSON object per line (found
# 2026-07-03: the old pretty-printed format broke every line-oriented reader).
row=$(tail -1 "$metrics_file" 2>/dev/null)
[[ "$rc" == "0" && "$out" == "$payload" && -f "$metrics_file" ]] \
  && printf '%s' "$row" | /usr/bin/grep -q '"session_id":"test-session"' \
  && [[ "$(wc -l < "$metrics_file" | tr -d ' ')" == "1" ]] \
  && printf '%s' "$row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && ok=1 || ok=0
assert "echoes payload through + appends one compact JSONL cost row for a valid transcript" "$ok"
rm -rf "$fake_home" "$transcript"

fake_home=$(mktemp -d)
payload=$(python3 -c 'import json; print(json.dumps({"transcript_path": "/nonexistent/transcript.jsonl", "session_id": "test-session"}))')
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && ! -f "$metrics_file" ]] && ok=1 || ok=0
assert "fails safe (exit 0, echoes payload, no metrics row) for a missing transcript" "$ok"
rm -rf "$fake_home"

# Adversarial: malformed (non-JSON) transcript content. The jq `try fromjson`
# filter skips unparseable lines → usage is null → no row. Must fail safe.
fake_home=$(mktemp -d)
transcript=$(mktemp)
printf 'this is not json\n{ broken\nalso not json\n' > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-session"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && ! -f "$metrics_file" ]] && ok=1 || ok=0
assert "fails safe (exit 0, no metrics row) for a malformed-JSON transcript" "$ok"
rm -rf "$fake_home" "$transcript"

# Adversarial: assistant line carries usage: null. The jq
# `select((.message // {}).usage != null)` filter drops it → usage is null → no row.
fake_home=$(mktemp -d)
transcript=$(mktemp)
python3 -c '
import json
line = {"type": "assistant", "message": {"model": "claude-sonnet-5", "usage": None}}
print(json.dumps(line))
' > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-session"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && ! -f "$metrics_file" ]] && ok=1 || ok=0
assert "fails safe (exit 0, no metrics row) when usage is null" "$ok"
rm -rf "$fake_home" "$transcript"

# Adversarial: multi-line transcript (two assistant lines) must aggregate into ONE
# compact JSONL row with summed tokens, not one row per line.
fake_home=$(mktemp -d)
transcript=$(mktemp)
{ make_transcript_line claude-sonnet-5 100 50; make_transcript_line claude-sonnet-5 200 80; } > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "multi"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
row=$(tail -1 "$metrics_file" 2>/dev/null)
# Exactly one row, input_tokens summed to 300 (100+200), output_tokens summed to 130.
[[ "$rc" == "0" && -f "$metrics_file" \
  && "$(wc -l < "$metrics_file" | tr -d ' ')" == "1" ]] \
  && printf '%s' "$row" | /usr/bin/grep -q '"session_id":"multi"' \
  && printf '%s' "$row" | /usr/bin/grep -q '"input_tokens":300' \
  && printf '%s' "$row" | /usr/bin/grep -q '"output_tokens":130' \
  && printf '%s' "$row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && ok=1 || ok=0
assert "aggregates a multi-line transcript into one summed JSONL cost row" "$ok"
rm -rf "$fake_home" "$transcript"

# Adversarial: multi-MODEL transcript (two assistant lines, different `.message.model`)
# must write ONE row PER MODEL, each model_scoped:true, each carrying only that
# model's own tokens — not one summed row tagged with whichever model was last used
# (the pre-fix behavior this rewrite replaced).
fake_home=$(mktemp -d)
transcript=$(mktemp)
{ make_transcript_line claude-opus-4-8 100 50; make_transcript_line claude-sonnet-5 200 80; } > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "multi-model"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
opus_row=$(/usr/bin/grep '"model":"claude-opus-4-8"' "$metrics_file" 2>/dev/null)
sonnet_row=$(/usr/bin/grep '"model":"claude-sonnet-5"' "$metrics_file" 2>/dev/null)
[[ "$rc" == "0" && -f "$metrics_file" \
  && "$(wc -l < "$metrics_file" | tr -d ' ')" == "2" ]] \
  && printf '%s' "$opus_row" | /usr/bin/grep -q '"model_scoped":true' \
  && printf '%s' "$opus_row" | /usr/bin/grep -q '"input_tokens":100' \
  && printf '%s' "$opus_row" | /usr/bin/grep -q '"output_tokens":50' \
  && printf '%s' "$sonnet_row" | /usr/bin/grep -q '"model_scoped":true' \
  && printf '%s' "$sonnet_row" | /usr/bin/grep -q '"input_tokens":200' \
  && printf '%s' "$sonnet_row" | /usr/bin/grep -q '"output_tokens":80' \
  && printf '%s' "$opus_row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null \
  && printf '%s' "$sonnet_row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && ok=1 || ok=0
assert "multi-model transcript writes one model_scoped row per model with that model's own tokens" "$ok"
rm -rf "$fake_home" "$transcript"

# Orchestrator-tax split. Claude Code writes the main session to
# <project>/<session-id>.jsonl and each subagent to its own file under the sibling
# <project>/<session-id>/subagents/agent-*.jsonl. cost-tracker read only the main
# file, so every subagent's spend was invisible to /cost-report (verified against a
# real 15-subagent session, 2026-08-07: 0 rows with isSidechain:true ever land in the
# main transcript). Assert both halves are now counted, tagged by `stream`, and that
# each row carries the turn count + cache_read-per-turn that make the orchestrator's
# carried-context cost readable — docs/research/orchestrator-tax-gap-analysis-2026-08-07.md.
fake_home=$(mktemp -d)
sess_dir=$(mktemp -d)
transcript="$sess_dir/sess.jsonl"
mkdir -p "$sess_dir/sess/subagents"
# main: 2 turns, cache_read 1000 each → cache_read_per_turn 1000
{ make_transcript_line claude-sonnet-5 100 50 1000; make_transcript_line claude-sonnet-5 100 50 1000; } > "$transcript"
# subagents: 2 files × 1 turn each, same model → one aggregated subagent row, 2 turns
make_transcript_line claude-sonnet-5 7 3 40 > "$sess_dir/sess/subagents/agent-aaa.jsonl"
make_transcript_line claude-sonnet-5 7 3 40 > "$sess_dir/sess/subagents/agent-bbb.jsonl"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "tax"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
orch_row=$(/usr/bin/grep '"stream":"orchestrator"' "$metrics_file" 2>/dev/null)
sub_row=$(/usr/bin/grep '"stream":"subagent"' "$metrics_file" 2>/dev/null)
[[ "$rc" == "0" && "$out" == "$payload" && -f "$metrics_file" \
  && "$(wc -l < "$metrics_file" | tr -d ' ')" == "2" ]] \
  && printf '%s' "$orch_row" | /usr/bin/grep -q '"input_tokens":200' \
  && printf '%s' "$orch_row" | /usr/bin/grep -q '"cache_read_tokens":2000' \
  && printf '%s' "$orch_row" | /usr/bin/grep -q '"turns":2' \
  && printf '%s' "$orch_row" | /usr/bin/grep -q '"cache_read_per_turn":1000' \
  && printf '%s' "$sub_row" | /usr/bin/grep -q '"input_tokens":14' \
  && printf '%s' "$sub_row" | /usr/bin/grep -q '"cache_read_tokens":80' \
  && printf '%s' "$sub_row" | /usr/bin/grep -q '"turns":2' \
  && printf '%s' "$orch_row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null \
  && printf '%s' "$sub_row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && ok=1 || ok=0
assert "counts subagent transcripts and tags each row with stream + turns + cache_read_per_turn" "$ok"
rm -rf "$fake_home" "$sess_dir"

# Fails safe when there is no subagents/ dir at all (the common single-agent session):
# one orchestrator row, no empty subagent row, no crash from the empty glob.
fake_home=$(mktemp -d)
sess_dir=$(mktemp -d)
transcript="$sess_dir/solo.jsonl"
make_transcript_line claude-sonnet-5 100 50 1000 > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "solo"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && -f "$metrics_file" \
  && "$(wc -l < "$metrics_file" | tr -d ' ')" == "1" ]] \
  && /usr/bin/grep -q '"stream":"orchestrator"' "$metrics_file" \
  && ! /usr/bin/grep -q '"stream":"subagent"' "$metrics_file" && ok=1 || ok=0
assert "no subagents/ dir → one orchestrator row, no empty subagent row" "$ok"
rm -rf "$fake_home" "$sess_dir"

# Per-agent-type breakdown. Claude Code writes an agent-<id>.meta.json sibling next to
# every agent-<id>.jsonl carrying the real `agentType` (the Agent tool's subagent_type
# param) — confirmed shape against a real transcript, 2026-08-07. Two subagent files on
# the SAME model but DIFFERENT agentType must produce two rows, not collapse into one:
# a kbg:code-reviewer dispatch and an Explore dispatch on the same model are different
# populations of work, exactly the reasoning behind the earlier stream split.
fake_home=$(mktemp -d)
sess_dir=$(mktemp -d)
transcript="$sess_dir/types.jsonl"
mkdir -p "$sess_dir/types/subagents"
make_transcript_line claude-sonnet-5 100 50 > "$transcript"
make_transcript_line claude-sonnet-5 10 5 > "$sess_dir/types/subagents/agent-aaa.jsonl"
printf '{"agentType":"kbg:code-reviewer","description":"x","toolUseId":"t1","spawnDepth":1}' > "$sess_dir/types/subagents/agent-aaa.meta.json"
make_transcript_line claude-sonnet-5 20 8 > "$sess_dir/types/subagents/agent-bbb.jsonl"
printf '{"agentType":"Explore","description":"y","toolUseId":"t2","spawnDepth":1}' > "$sess_dir/types/subagents/agent-bbb.meta.json"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "types"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
reviewer_row=$(/usr/bin/grep '"agent_type":"kbg:code-reviewer"' "$metrics_file" 2>/dev/null)
explore_row=$(/usr/bin/grep '"agent_type":"Explore"' "$metrics_file" 2>/dev/null)
orch_row=$(/usr/bin/grep '"stream":"orchestrator"' "$metrics_file" 2>/dev/null)
[[ "$rc" == "0" && -f "$metrics_file" \
  && "$(wc -l < "$metrics_file" | tr -d ' ')" == "3" ]] \
  && printf '%s' "$reviewer_row" | /usr/bin/grep -q '"input_tokens":10' \
  && printf '%s' "$explore_row" | /usr/bin/grep -q '"input_tokens":20' \
  && printf '%s' "$orch_row" | /usr/bin/grep -q '"agent_type":null' \
  && printf '%s' "$reviewer_row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null \
  && printf '%s' "$explore_row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && ok=1 || ok=0
assert "subagent rows split by agent_type (from meta.json sibling) even on the same model; orchestrator row carries agent_type:null" "$ok"
rm -rf "$fake_home" "$sess_dir"

# Missing meta.json sibling (older sessions, or a subagent that never got one) must
# fail safe to agent_type:"unknown" — never drop the row, never crash.
fake_home=$(mktemp -d)
sess_dir=$(mktemp -d)
transcript="$sess_dir/nometa.jsonl"
mkdir -p "$sess_dir/nometa/subagents"
make_transcript_line claude-sonnet-5 100 50 > "$transcript"
make_transcript_line claude-sonnet-5 10 5 > "$sess_dir/nometa/subagents/agent-ccc.jsonl"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "nometa"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
sub_row=$(/usr/bin/grep '"stream":"subagent"' "$metrics_file" 2>/dev/null)
[[ "$rc" == "0" && -f "$metrics_file" ]] \
  && printf '%s' "$sub_row" | /usr/bin/grep -q '"agent_type":"unknown"' \
  && printf '%s' "$sub_row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && ok=1 || ok=0
assert "subagent transcript with no .meta.json sibling falls back to agent_type:\"unknown\" (fails safe, no crash)" "$ok"
rm -rf "$fake_home" "$sess_dir"

# Claude-only tracking (2026-08-07, operator request): a session can run non-Claude
# models (e.g. via a proxy that swaps ANTHROPIC_BASE_URL — confirmed real in
# production data: minimax-m3, glm-5.2, kimi-k2.7-code, nemotron-3-super all showed
# real spend). The tracker must write a row ONLY for turns whose `.message.model`
# matches claude-*, and silently drop non-Claude turns — not error, not fold them
# into an "unknown" row, not let them inflate any Claude row's totals.
fake_home=$(mktemp -d)
transcript=$(mktemp)
{ make_transcript_line claude-sonnet-5 100 50; make_transcript_line minimax-m3 999 999; } > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "mixed-vendor"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && -f "$metrics_file" \
  && "$(wc -l < "$metrics_file" | tr -d ' ')" == "1" ]] \
  && /usr/bin/grep -q '"model":"claude-sonnet-5"' "$metrics_file" \
  && /usr/bin/grep -q '"input_tokens":100' "$metrics_file" \
  && ! /usr/bin/grep -qi 'minimax' "$metrics_file" && ok=1 || ok=0
assert "non-Claude model turns (minimax-m3) are silently dropped — only the claude-sonnet-5 row is written, with its own tokens, not inflated by the dropped turn" "$ok"
rm -rf "$fake_home" "$transcript"

# A transcript with ONLY non-Claude turns must write no row at all (not a crash, not
# an empty/garbage row) — the existing "no usage → no row" fail-safe path.
fake_home=$(mktemp -d)
transcript=$(mktemp)
make_transcript_line glm-5.2 50 20 > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "all-foreign"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && ! -f "$metrics_file" ]] && ok=1 || ok=0
assert "an all-non-Claude transcript (glm-5.2 only) writes no metrics row at all" "$ok"
rm -rf "$fake_home" "$transcript"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
