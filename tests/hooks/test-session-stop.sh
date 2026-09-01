#!/usr/bin/env bash
# Session/Stop hook smoke tests: doctrine-bootstrap (SessionStart),
# command-root-anchor (SessionStart), memory-health-nudge (SessionStart),
# cost-tracker (Stop), nudge-compliance-tracker (Stop), memory-audit-commit (Stop).
# These hooks never block
# (no permissionDecision) —
# tests assert exit 0 + expected side effect (stdout injection / env-file
# append / metrics-file append), and that each fails safe (exit 0, no side
# effect) when its required env var is unset.
# Run standalone: bash tests/hooks/test-session-stop.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DOCTRINE="$ROOT/hooks/session/doctrine-bootstrap.sh"
ROOT_ANCHOR="$ROOT/hooks/session/command-root-anchor.sh"
MEMORY_NUDGE="$ROOT/hooks/session/memory-health-nudge.sh"
COST_TRACKER="$ROOT/hooks/stop/cost-tracker.sh"
NUDGE_COMPLIANCE_TRACKER="$ROOT/hooks/stop/nudge-compliance-tracker.sh"
MEMORY_COMMIT="$ROOT/hooks/stop/memory-audit-commit.sh"
STALE_TASK_NUDGE="$ROOT/hooks/stop/stale-task-nudge.sh"

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
[[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q '<!-- mh:doctrine-bootstrap -->' \
  && echo "$out" | /usr/bin/grep -q '<!-- /mh:doctrine-bootstrap -->' \
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

# Dependency preflight (#93): with python3 and jq missing from PATH, the
# SessionStart injection must NAME both missing deps (the gates' per-call
# stderr notes rely on this being the one up-front announcement).
NOPY_BIN=$(mktemp -d "${TMPDIR:-/tmp}/kbg-ss-nopy.XXXXXX")
for _t in bash cat grep sed tr; do
  _src=$(PATH="/usr/bin:/bin" command -v "$_t" || command -v "$_t")
  ln -s "$_src" "$NOPY_BIN/$_t"
done
out=$(env PATH="$NOPY_BIN" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$DOCTRINE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q 'portability-preflight' \
  && echo "$out" | /usr/bin/grep -q 'python3.*not found' \
  && echo "$out" | /usr/bin/grep -q 'jq.*not found' && ok=1 || ok=0
assert "preflight names python3 AND jq when both are missing from PATH (#93)" "$ok"

out=$(CLAUDE_PLUGIN_ROOT="$ROOT" bash "$DOCTRINE" 2>/dev/null)
echo "$out" | /usr/bin/grep -q 'portability-preflight' && ok=0 || ok=1
assert "no portability preflight when python3/jq are present" "$ok"

# mattpocock-skills companion-plugin preflight: fixture $HOME, independent of
# whatever plugins happen to be installed on the machine running this test.
# make_matt_cache_fixture <home>: a "complete" cache the shared resolver
# (scripts/_lib/mattpocock-root.sh, #92/T13) will actually resolve — a
# version dir with a real SKILL.md under skills/, not just the bare parent
# directory the old ad-hoc check accepted.
make_matt_cache_fixture() {
  local root="$1/.claude/plugins/cache/mattpocock/mattpocock-skills/9.9.9"
  mkdir -p "$root/skills/engineering/to-spec"
  printf '%s\n' '---
name: to-spec
description: test fixture
---
body' > "$root/skills/engineering/to-spec/SKILL.md"
}

fake_home_present=$(mktemp -d)
make_matt_cache_fixture "$fake_home_present"
out=$(CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$fake_home_present" bash "$DOCTRINE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" ]] && ! echo "$out" | /usr/bin/grep -q 'mh:mattpocock-preflight' && ok=1 || ok=0
assert "silent when mattpocock-skills plugin cache is present" "$ok"
trash "$fake_home_present" 2>/dev/null || true

fake_home_absent=$(mktemp -d)
out=$(CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$fake_home_absent" bash "$DOCTRINE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q '<!-- mh:mattpocock-preflight -->' \
  && echo "$out" | /usr/bin/grep -q 'mattpocock-skills@mattpocock' \
  && echo "$out" | /usr/bin/grep -q '<!-- /mh:mattpocock-preflight -->' && ok=1 || ok=0
assert "warns when mattpocock-skills plugin cache is absent" "$ok"
trash "$fake_home_absent" 2>/dev/null || true

# Half-extracted cache (#92/T13's actual new behavior): a version directory
# exists but skills/ is empty — the OLD bare `-d $MATTPOCOCK_CACHE` check
# would have passed this (parent dir present) and stayed silent; the shared
# resolver's completeness probe (a real SKILL.md must exist somewhere under
# skills/) correctly rejects it and warns instead.
fake_home_half=$(mktemp -d)
mkdir -p "$fake_home_half/.claude/plugins/cache/mattpocock/mattpocock-skills/9.9.9/skills"
out=$(CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$fake_home_half" bash "$DOCTRINE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q '<!-- mh:mattpocock-preflight -->' \
  && echo "$out" | /usr/bin/grep -qi 'incomplete' && ok=1 || ok=0
assert "warns (not silent) when the cache's version dir exists but skills/ has no real SKILL.md — half-extracted install" "$ok"
trash "$fake_home_half" 2>/dev/null || true

fake_home_disabled=$(mktemp -d)
make_matt_cache_fixture "$fake_home_disabled"
cat > "$fake_home_disabled/.claude/settings.json" <<'EOF'
{"enabledPlugins": {"mattpocock-skills@mattpocock": false}}
EOF
out=$(CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$fake_home_disabled" bash "$DOCTRINE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q '<!-- mh:mattpocock-preflight -->' \
  && echo "$out" | /usr/bin/grep -qi 'installed but disabled' && ok=1 || ok=0
assert "warns when mattpocock-skills plugin cache is present but disabled in settings.json" "$ok"
trash "$fake_home_disabled" 2>/dev/null || true

fake_home_enabled=$(mktemp -d)
make_matt_cache_fixture "$fake_home_enabled"
cat > "$fake_home_enabled/.claude/settings.json" <<'EOF'
{"enabledPlugins": {"mattpocock-skills@mattpocock": true}}
EOF
out=$(CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$fake_home_enabled" bash "$DOCTRINE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" ]] && ! echo "$out" | /usr/bin/grep -q 'mh:mattpocock-preflight' && ok=1 || ok=0
assert "stays silent when mattpocock-skills is present and explicitly enabled" "$ok"
trash "$fake_home_enabled" 2>/dev/null || true

echo ""
echo "=== command-root-anchor hook (SessionStart) ==="

envfile=$(mktemp)
CLAUDE_PLUGIN_ROOT="/some/plugin/root/" CLAUDE_ENV_FILE="$envfile" bash "$ROOT_ANCHOR" 2>/dev/null
rc=$?
[[ "$rc" == "0" ]] && /usr/bin/grep -qx 'export MH_PLUGIN_ROOT=/some/plugin/root' "$envfile" && ok=1 || ok=0
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
echo "=== memory-health-nudge hook (SessionStart) ==="

# Fixture directories must be resolved with `pwd -P` (physical path) before
# encoding, matching both memory-lint.py's os.getcwd() and the hook's own
# `pwd -P` pre-check — on macOS /tmp and /var are symlinks into /private/…,
# so mktemp -d fixtures diverge from a naive $DIR substitution (caught while
# writing this hook: an earlier ad-hoc smoke test used the logical path and
# silently never found its own fixture).
fake_home=$(mktemp -d)

clean_dir=$(mktemp -d)
clean_enc="$(cd "$clean_dir" && pwd -P | sed 's|/|-|g')"
mkdir -p "$fake_home/.claude/projects/$clean_enc/memory"
printf '%s\n' "# Memory index" > "$fake_home/.claude/projects/$clean_enc/memory/MEMORY.md"
out=$(cd "$clean_dir" && CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$fake_home" bash "$MEMORY_NUDGE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "silent (exit 0, no output) when the memory store has zero findings" "$ok"

dirty_dir=$(mktemp -d)
dirty_enc="$(cd "$dirty_dir" && pwd -P | sed 's|/|-|g')"
dirty_mem="$fake_home/.claude/projects/$dirty_enc/memory"
mkdir -p "$dirty_mem"
cat > "$dirty_mem/orphan-note.md" <<'EOF'
---
name: orphan-note
description: "test fixture"
metadata:
  type: feedback
---
Body content, no links, never referenced from MEMORY.md.
EOF
printf '%s\n' "# Memory index" > "$dirty_mem/MEMORY.md"
out=$(cd "$dirty_dir" && CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$fake_home" bash "$MEMORY_NUDGE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" ]] \
  && printf '%s' "$out" | /usr/bin/grep -q '\[memory-lint\]' \
  && printf '%s' "$out" | /usr/bin/grep -q 'UNINDEXED: orphan-note.md' \
  && printf '%s' "$out" | /usr/bin/grep -q 'mh:memory-lint' && ok=1 || ok=0
assert "emits a one-line advisory naming the finding when the store has drift" "$ok"

nodir=$(mktemp -d)
out=$(cd "$nodir" && CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$fake_home" bash "$MEMORY_NUDGE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "fails safe (exit 0, silent) when the project has no memory store at all" "$ok"

out=$(cd "$dirty_dir" && env -u CLAUDE_PLUGIN_ROOT HOME="$fake_home" bash "$MEMORY_NUDGE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "fails safe (exit 0, silent) when CLAUDE_PLUGIN_ROOT is unset" "$ok"

trash "$fake_home" "$clean_dir" "$dirty_dir" "$nodir" 2>/dev/null || true

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
trash "$fake_home" "$transcript" 2>/dev/null || true

fake_home=$(mktemp -d)
payload=$(python3 -c 'import json; print(json.dumps({"transcript_path": "/nonexistent/transcript.jsonl", "session_id": "test-session"}))')
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && ! -f "$metrics_file" ]] && ok=1 || ok=0
assert "fails safe (exit 0, echoes payload, no metrics row) for a missing transcript" "$ok"
trash "$fake_home" 2>/dev/null || true

# Portability (#93): with jq missing from PATH the tracker must echo the
# payload through and write NOTHING — not garbage rows. Payload is built
# first, with python3/jq still available; NOPY_BIN comes from the
# doctrine-bootstrap preflight test above (bash/cat/grep/sed/tr, no jq).
fake_home=$(mktemp -d)
transcript=$(mktemp)
make_transcript_line claude-sonnet-5 100 50 > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-nojq"}))' "$transcript")
out=$(printf '%s' "$payload" | env PATH="$NOPY_BIN" HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && ! -f "$metrics_file" ]] && ok=1 || ok=0
assert "no jq on PATH -> echoes payload, exit 0, zero metrics rows (#93)" "$ok"
trash "$fake_home" "$transcript" 2>/dev/null || true

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
trash "$fake_home" "$transcript" 2>/dev/null || true

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
trash "$fake_home" "$transcript" 2>/dev/null || true

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
trash "$fake_home" "$transcript" 2>/dev/null || true

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
trash "$fake_home" "$transcript" 2>/dev/null || true

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
trash "$fake_home" "$sess_dir" 2>/dev/null || true

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
trash "$fake_home" "$sess_dir" 2>/dev/null || true

# Per-agent-type breakdown. Claude Code writes an agent-<id>.meta.json sibling next to
# every agent-<id>.jsonl carrying the real `agentType` (the Agent tool's subagent_type
# param) — confirmed shape against a real transcript, 2026-08-07. Two subagent files on
# the SAME model but DIFFERENT agentType must produce two rows, not collapse into one:
# a mh:code-reviewer dispatch and an Explore dispatch on the same model are different
# populations of work, exactly the reasoning behind the earlier stream split.
fake_home=$(mktemp -d)
sess_dir=$(mktemp -d)
transcript="$sess_dir/types.jsonl"
mkdir -p "$sess_dir/types/subagents"
make_transcript_line claude-sonnet-5 100 50 > "$transcript"
make_transcript_line claude-sonnet-5 10 5 > "$sess_dir/types/subagents/agent-aaa.jsonl"
printf '{"agentType":"mh:code-reviewer","description":"x","toolUseId":"t1","spawnDepth":1}' > "$sess_dir/types/subagents/agent-aaa.meta.json"
make_transcript_line claude-sonnet-5 20 8 > "$sess_dir/types/subagents/agent-bbb.jsonl"
printf '{"agentType":"Explore","description":"y","toolUseId":"t2","spawnDepth":1}' > "$sess_dir/types/subagents/agent-bbb.meta.json"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "types"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
reviewer_row=$(/usr/bin/grep '"agent_type":"mh:code-reviewer"' "$metrics_file" 2>/dev/null)
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
trash "$fake_home" "$sess_dir" 2>/dev/null || true

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
trash "$fake_home" "$sess_dir" 2>/dev/null || true

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
trash "$fake_home" "$transcript" 2>/dev/null || true

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
trash "$fake_home" "$transcript" 2>/dev/null || true

echo ""
echo "=== memory-audit-commit hook (Stop) ==="

fake_home=$(mktemp -d)

# Each case gets its own project dir → own encoded memory dir, so no
# leftover state (untracked files, prior commits) from one case can leak
# into the next.
proj_noopt=$(mktemp -d)
mem_noopt="$fake_home/.claude/projects/$(cd "$proj_noopt" && pwd -P | sed 's|/|-|g')/memory"
mkdir -p "$mem_noopt"
echo "not opted in" > "$mem_noopt/f.md"
out=$(cd "$proj_noopt" && HOME="$fake_home" bash "$MEMORY_COMMIT" 2>/dev/null)
rc=$?
still_no_git="no"; [[ "$(cd "$mem_noopt" && git rev-parse --is-inside-work-tree 2>&1)" != "true" ]] && still_no_git="yes"
[[ "$rc" == "0" && -z "$out" && "$still_no_git" == "yes" ]] && ok=1 || ok=0
assert "no-op (exit 0, no repo created) when the memory dir isn't already a git repo" "$ok"

proj=$(mktemp -d)
mem_dir="$fake_home/.claude/projects/$(cd "$proj" && pwd -P | sed 's|/|-|g')/memory"
mkdir -p "$mem_dir"
echo "# Memory index" > "$mem_dir/MEMORY.md"
(cd "$mem_dir" && git init -q && git add MEMORY.md && git -c user.email=test@test -c user.name=test commit -q -m baseline)

before=$(cd "$mem_dir" && git rev-parse HEAD)
out=$(cd "$proj" && HOME="$fake_home" bash "$MEMORY_COMMIT" 2>/dev/null)
rc=$?
after=$(cd "$mem_dir" && git rev-parse HEAD)
[[ "$rc" == "0" && "$before" == "$after" ]] && ok=1 || ok=0
assert "clean tree → no-op, HEAD unchanged" "$ok"

echo "new memory" > "$mem_dir/new-note.md"
out=$(cd "$proj" && HOME="$fake_home" bash "$MEMORY_COMMIT" 2>/dev/null)
rc=$?
log_count=$(cd "$mem_dir" && git log --oneline | wc -l | tr -d ' ')
porcelain=$(cd "$mem_dir" && git status --porcelain)
[[ "$rc" == "0" && "$log_count" == "2" && -z "$porcelain" ]] && ok=1 || ok=0
assert "new untracked file → auto-committed, working tree clean after" "$ok"

echo "edited" >> "$mem_dir/MEMORY.md"
out=$(cd "$proj" && HOME="$fake_home" bash "$MEMORY_COMMIT" 2>/dev/null)
rc=$?
log_count2=$(cd "$mem_dir" && git log --oneline | wc -l | tr -d ' ')
porcelain2=$(cd "$mem_dir" && git status --porcelain)
[[ "$rc" == "0" && "$log_count2" == "3" && -z "$porcelain2" ]] && ok=1 || ok=0
assert "edit to an already-tracked file → auto-committed, working tree clean after" "$ok"

trash "$fake_home" "$proj_noopt" "$proj" 2>/dev/null || true

echo ""
echo "=== stale-task-nudge hook (Stop) ==="

nudge_fix=$(mktemp -d)

cat > "$nudge_fix/stale.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"do the thing"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"9","status":"in_progress"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Here is the final report."}]}}
EOF

cat > "$nudge_fix/clean.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"do the thing"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"9","status":"in_progress"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"9","status":"completed"}}]}}
EOF

nudge_home=$(mktemp -d)

out=$(HOME="$nudge_home" bash "$STALE_TASK_NUDGE" < <(printf '{"transcript_path":"%s/stale.jsonl","session_id":"s1","stop_hook_active":false}' "$nudge_fix") 2>/dev/null)
rc=$?
[[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q '"additionalContext"' \
  && echo "$out" | /usr/bin/grep -q '#9' && ok=1 || ok=0
assert "fires additionalContext for a task last set to in_progress, untouched since" "$ok"

out=$(HOME="$nudge_home" bash "$STALE_TASK_NUDGE" < <(printf '{"transcript_path":"%s/stale.jsonl","session_id":"s1","stop_hook_active":false}' "$nudge_fix") 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "same session + same task, fired again → silent (per-session dedup)" "$ok"

out=$(HOME="$nudge_home" bash "$STALE_TASK_NUDGE" < <(printf '{"transcript_path":"%s/clean.jsonl","session_id":"s2","stop_hook_active":false}' "$nudge_fix") 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "silent when the task's last recorded status is completed" "$ok"

out=$(HOME="$nudge_home" bash "$STALE_TASK_NUDGE" < <(printf '{"transcript_path":"%s/stale.jsonl","session_id":"s3","stop_hook_active":true}' "$nudge_fix") 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "silent when stop_hook_active=true (anti-loop guard)" "$ok"

out=$(HOME="$nudge_home" bash "$STALE_TASK_NUDGE" < <(printf '{"session_id":"s4"}') 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "fails safe (exit 0, silent) when transcript_path is missing" "$ok"

out=$(HOME="$nudge_home" bash "$STALE_TASK_NUDGE" < <(printf '{"transcript_path":"/nonexistent-%s.jsonl","session_id":"s5"}' "$$") 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "fails safe (exit 0, silent) when the transcript file doesn't exist" "$ok"

cat > "$nudge_fix/traversal.jsonl" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"TaskUpdate","input":{"taskId":"../../../../tmp/kbg-nudge-traversal-probe","status":"in_progress"}}]}}
EOF

out=$(HOME="$nudge_home" bash "$STALE_TASK_NUDGE" < <(printf '{"transcript_path":"%s/traversal.jsonl","session_id":"s6","stop_hook_active":false}' "$nudge_fix") 2>/dev/null)
rc=$?
[[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q '"additionalContext"' && ok=1 || ok=0
assert "path-traversal-shaped taskId still fires the nudge" "$ok"
[[ ! -e /tmp/kbg-nudge-traversal-probe ]] && ok=1 || ok=0
assert "path-traversal-shaped taskId does not write its marker outside the marker dir" "$ok"

out=$(HOME="$nudge_home" bash "$STALE_TASK_NUDGE" < <(printf '{"transcript_path":"%s/traversal.jsonl","session_id":"s6","stop_hook_active":false}' "$nudge_fix") 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "same path-traversal-shaped taskId, fired again → silent (dedup still works, not bypassed by sanitization)" "$ok"

trash "$nudge_fix" "$nudge_home" 2>/dev/null || true

echo ""
echo "=== nudge-compliance-tracker hook (Stop) ==="

# make_fire_line -- one flow-nudge fire, as it actually appears in a transcript
# (attachment/hook_success/UserPromptSubmit, content prefix-matched by the hook).
make_fire_line() {
  python3 -c 'import json; print(json.dumps({"type": "attachment", "attachment": {"type": "hook_success", "hookName": "UserPromptSubmit", "content": "[mh:flow-nudge] Non-trivial work detected — interrogate..."}}))'
}
# make_enterplanmode_line -- a real EnterPlanMode tool_use, as it appears on an
# assistant-type transcript line.
make_enterplanmode_line() {
  python3 -c 'import json; print(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "EnterPlanMode", "input": {}}]}}))'
}
# make_advisor_line -- a genuine advisor() consultation, per the real shape found by the
# 2026-08-30 audit: nested under message.usage.iterations[], not a top-level tool_use.
make_advisor_line() {
  python3 -c 'import json; print(json.dumps({"type": "assistant", "message": {"content": [], "usage": {"iterations": [{"type": "advisor_message"}]}}}))'
}
# make_agent_line [isSidechain] -- a real Agent-tool dispatch, as it appears on an
# assistant-type transcript line. Added 2026-09-01 (Part B, mattpocock-compat +
# delegation-discipline redesign): a turn that delegated via Agent used to score
# non-compliant. Optional isSidechain arg (default false) so main_dispatches scoping
# can be fixture-tested the same way make_write_line's isSidechain arg tests main_writes.
make_agent_line() {
  python3 -c 'import json,sys; print(json.dumps({"type": "assistant", "isSidechain": sys.argv[1] == "true", "message": {"content": [{"type": "tool_use", "name": "Agent", "input": {}}]}}))' "${1:-false}"
}
make_noise_line() {
  python3 -c 'import json; print(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {}}]}}))'
}
# make_write_line <isSidechain> -- an Edit tool_use on an assistant-type transcript
# line, with isSidechain set explicitly (true/false) so main_writes scoping can be
# fixture-tested against both a main-thread and a subagent turn.
make_write_line() {
  python3 -c 'import json,sys; print(json.dumps({"type": "assistant", "isSidechain": sys.argv[1] == "true", "message": {"content": [{"type": "tool_use", "name": "Edit", "input": {}}]}}))' "$1"
}

fake_home=$(mktemp -d)
transcript=$(mktemp)
{ make_fire_line; make_enterplanmode_line; } > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-session"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$NUDGE_COMPLIANCE_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/nudge-compliance.jsonl"
row=$(tail -1 "$metrics_file" 2>/dev/null)
[[ "$rc" == "0" && "$out" == "$payload" && -f "$metrics_file" ]] \
  && printf '%s' "$row" | /usr/bin/grep -q '"nudges_fired":1' \
  && printf '%s' "$row" | /usr/bin/grep -q '"nudges_complied":1' \
  && printf '%s' "$row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && ok=1 || ok=0
assert "one fire + EnterPlanMode after it -> 1 fired, 1 complied" "$ok"
trash "$fake_home" "$transcript" 2>/dev/null || true

fake_home=$(mktemp -d)
transcript=$(mktemp)
{ make_fire_line; make_noise_line; } > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-session"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$NUDGE_COMPLIANCE_TRACKER" 2>/dev/null)
metrics_file="$fake_home/.local/share/kbg/metrics/nudge-compliance.jsonl"
row=$(tail -1 "$metrics_file" 2>/dev/null)
printf '%s' "$row" | /usr/bin/grep -q '"nudges_fired":1' \
  && printf '%s' "$row" | /usr/bin/grep -q '"nudges_complied":0' && ok=1 || ok=0
assert "one fire, no EnterPlanMode/advisor after it -> 1 fired, 0 complied" "$ok"
trash "$fake_home" "$transcript" 2>/dev/null || true

# Regression test for the bounded-window fix (2026-08-30 deep-audit): an earlier
# draft used "any later response marks every earlier fire compliant" -- fire#1 with
# nothing before fire#2, fire#2 with EnterPlanMode after it, must score 1/2, not 2/2.
fake_home=$(mktemp -d)
transcript=$(mktemp)
{ make_fire_line; make_fire_line; make_enterplanmode_line; } > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-window"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$NUDGE_COMPLIANCE_TRACKER" 2>/dev/null)
metrics_file="$fake_home/.local/share/kbg/metrics/nudge-compliance.jsonl"
row=$(tail -1 "$metrics_file" 2>/dev/null)
printf '%s' "$row" | /usr/bin/grep -q '"nudges_fired":2' \
  && printf '%s' "$row" | /usr/bin/grep -q '"nudges_complied":1' && ok=1 || ok=0
assert "two fires, response only before the 2nd -> 1/2 complied, not 2/2 (bounded window, not 'any later')" "$ok"
trash "$fake_home" "$transcript" 2>/dev/null || true

fake_home=$(mktemp -d)
transcript=$(mktemp)
{ make_fire_line; make_advisor_line; } > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-advisor"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$NUDGE_COMPLIANCE_TRACKER" 2>/dev/null)
metrics_file="$fake_home/.local/share/kbg/metrics/nudge-compliance.jsonl"
row=$(tail -1 "$metrics_file" 2>/dev/null)
printf '%s' "$row" | /usr/bin/grep -q '"nudges_fired":1' \
  && printf '%s' "$row" | /usr/bin/grep -q '"nudges_complied":1' && ok=1 || ok=0
assert "advisor_message iteration (not a tool_use) also counts as compliance" "$ok"
trash "$fake_home" "$transcript" 2>/dev/null || true

fake_home=$(mktemp -d)
transcript=$(mktemp)
{ make_fire_line; make_agent_line; } > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-agent"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$NUDGE_COMPLIANCE_TRACKER" 2>/dev/null)
metrics_file="$fake_home/.local/share/kbg/metrics/nudge-compliance.jsonl"
row=$(tail -1 "$metrics_file" 2>/dev/null)
printf '%s' "$row" | /usr/bin/grep -q '"nudges_fired":1' \
  && printf '%s' "$row" | /usr/bin/grep -q '"nudges_complied":1' && ok=1 || ok=0
assert "Agent tool_use after a fire also counts as compliance (delegation, not just plan-mode/advisor)" "$ok"
trash "$fake_home" "$transcript" 2>/dev/null || true

# main_writes scoping (2026-09-01): 3 main-thread Edit tool_use entries plus 1
# sidechain (isSidechain:true) Edit tool_use entry -- the sidechain one must be
# excluded, so main_writes must equal exactly 3, not 4.
fake_home=$(mktemp -d)
transcript=$(mktemp)
{ make_write_line false; make_write_line false; make_write_line false; make_write_line true; } > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-main-writes"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$NUDGE_COMPLIANCE_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/nudge-compliance.jsonl"
row=$(tail -1 "$metrics_file" 2>/dev/null)
[[ "$rc" == "0" ]] && printf '%s' "$row" | /usr/bin/grep -q '"main_writes":3' && ok=1 || ok=0
assert "main_writes counts only main-thread Edit tool_use entries, excludes the isSidechain:true one (3, not 4)" "$ok"
trash "$fake_home" "$transcript" 2>/dev/null || true

# main_dispatches scoping: an Agent tool_use on the main thread counts; the same
# fixture line's Agent-tool count from the compliance test above already exercises
# the happy path, this asserts the field is present and correctly scoped on its own.
fake_home=$(mktemp -d)
transcript=$(mktemp)
{ make_agent_line; make_agent_line; } > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-main-dispatches"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$NUDGE_COMPLIANCE_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/nudge-compliance.jsonl"
row=$(tail -1 "$metrics_file" 2>/dev/null)
[[ "$rc" == "0" ]] && printf '%s' "$row" | /usr/bin/grep -q '"main_dispatches":2' && ok=1 || ok=0
assert "main_dispatches counts main-thread Agent tool_use entries (2)" "$ok"
trash "$fake_home" "$transcript" 2>/dev/null || true

# Inverse case: zero main-thread writes/dispatches but several sidechain
# (isSidechain:true) ones present -- the more realistic shape for an orchestrator-heavy
# session. Guards that sidechain activity never leaks into either count.
fake_home=$(mktemp -d)
transcript=$(mktemp)
{ make_write_line true; make_write_line true; make_write_line true; make_write_line true; make_agent_line true; make_agent_line true; } > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-all-sidechain"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$NUDGE_COMPLIANCE_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/nudge-compliance.jsonl"
row=$(tail -1 "$metrics_file" 2>/dev/null)
[[ "$rc" == "0" ]] && printf '%s' "$row" | /usr/bin/grep -q '"main_writes":0' \
  && printf '%s' "$row" | /usr/bin/grep -q '"main_dispatches":0' && ok=1 || ok=0
assert "all-sidechain transcript (4 Edit + 2 Agent, isSidechain:true) -> main_writes:0, main_dispatches:0" "$ok"
trash "$fake_home" "$transcript" 2>/dev/null || true

fake_home=$(mktemp -d)
transcript=$(mktemp)
printf 'this is not json\n{ broken\n' > "$transcript"
{ cat "$transcript"; make_fire_line; make_enterplanmode_line; } > "${transcript}.mixed"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-malformed"}))' "${transcript}.mixed")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$NUDGE_COMPLIANCE_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/nudge-compliance.jsonl"
row=$(tail -1 "$metrics_file" 2>/dev/null)
[[ "$rc" == "0" ]] && printf '%s' "$row" | /usr/bin/grep -q '"nudges_fired":1' \
  && printf '%s' "$row" | /usr/bin/grep -q '"nudges_complied":1' && ok=1 || ok=0
assert "malformed lines interleaved with a real fire don't crash the pass or skew the count" "$ok"
trash "$fake_home" "$transcript" "${transcript}.mixed" 2>/dev/null || true

fake_home=$(mktemp -d)
payload=$(python3 -c 'import json; print(json.dumps({"transcript_path": "/nonexistent/transcript.jsonl", "session_id": "test-session"}))')
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$NUDGE_COMPLIANCE_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/nudge-compliance.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && ! -f "$metrics_file" ]] && ok=1 || ok=0
assert "fails safe (exit 0, echoes payload, no metrics row) for a missing transcript" "$ok"
trash "$fake_home" 2>/dev/null || true

fake_home=$(mktemp -d)
transcript=$(mktemp)
make_fire_line > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-nojq"}))' "$transcript")
out=$(printf '%s' "$payload" | env PATH="$NOPY_BIN" HOME="$fake_home" bash "$NUDGE_COMPLIANCE_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/nudge-compliance.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && ! -f "$metrics_file" ]] && ok=1 || ok=0
assert "no jq on PATH -> echoes payload, exit 0, zero metrics rows (#93)" "$ok"
trash "$fake_home" "$transcript" 2>/dev/null || true

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
