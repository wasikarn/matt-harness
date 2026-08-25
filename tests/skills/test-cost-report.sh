#!/usr/bin/env bash
# Regression test for the mh:cost-report dedup script,
# scripts/workflows/cost-report-dedup.js (extracted 2026-08-23 from the
# command body's embedded fence — 200-LOC cap refactor; this file now runs the
# real bundled script directly instead of extracting a fence, so there is no
# separate maintained copy to drift from the command). Points it at a
# synthetic HOME so it never touches the real
# ~/.local/share/kbg/metrics/costs.jsonl, and checks the dedup math.
#
# Covers a live bug found 2026-08-07 by an adversarial code-correctness review of
# v0.68.209/210 (docs/research/orchestrator-tax-gap-analysis-2026-08-07.md): the
# dedup key `(r.stream||"")+" "+(r.model||"")` treated a streamless legacy row
# (written before `stream` shipped — always implicitly the orchestrator's own
# total) and a same-model post-fix `stream:"orchestrator"` row as two different
# buckets, so a session_id spanning the upgrade got double-counted. Confirmed live
# against the operator's real costs.jsonl: an $8.07 overcount on one session.
# Fixed by defaulting the missing `stream` to `"orchestrator"` in the dedup key.
#
# Note on what proves what (found by a second-round adversarial review,
# 2026-08-07): the actual proof that these fixtures discriminate the fix from
# the bug is the mutation test: manually reverting `(r.stream||"orchestrator")`
# to `(r.stream||"")` in a scratch copy of scripts/workflows/
# cost-report-dedup.js and pointing REPORT_JS at it — case 1 then fails with a
# wrong total instead of a crash. That's not automated here (it would require
# mutating the file under test, which this suite intentionally doesn't do);
# re-run it by hand if this test's fixtures are ever revised. (The pre-2026-08-23
# fenced-script version of this recipe mutated a scratch copy of
# skills/meta/cost-report/SKILL.md instead — same mutation, different file.)
# Extended 2026-08-07 for the agent_type breakdown (docs/research/
# orchestrator-tax-gap-analysis-2026-08-07.md, "Re-read audit" G1 follow-up): the
# dedup key widened again, from (session_id, stream, model) to (session_id, stream,
# model, agent_type), for the identical reason `stream` was added to it earlier the
# same day — two agent types spending on the same model would otherwise collide.
# Run standalone: bash tests/skills/test-cost-report.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_JS="$ROOT/scripts/workflows/cost-report-dedup.js"
COMMAND_MD="$ROOT/skills/meta/cost-report/SKILL.md"

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

[[ -f "$REPORT_JS" ]] || { echo "FATAL: $REPORT_JS not found — the cost-report skill's script moved without updating this test" >&2; exit 1; }
[[ -f "$COMMAND_MD" ]] || { echo "FATAL: $COMMAND_MD not found — the command moved without updating this test" >&2; exit 1; }

echo "=== cost-report dedup (stream-aware) ==="

# Wiring guard (plan-review finding, 2026-08-23): the command body must invoke
# the script via ${MH_PLUGIN_ROOT} — the hook-only ${CLAUDE_PLUGIN_ROOT}
# expands EMPTY in a command body (hooks/session/command-root-anchor.sh's own
# header says command bodies must not name it), which would ENOENT for every
# installed-plugin user while this suite still passes green against the repo
# path. No other gate sees that mismatch, so pin it here.
cpr_refs=$(/usr/bin/grep -c 'CLAUDE_PLUGIN_ROOT' "$COMMAND_MD") || true
kpr_refs=$(/usr/bin/grep -c 'MH_PLUGIN_ROOT.*cost-report-dedup\.js' "$COMMAND_MD") || true
[[ "$cpr_refs" == "0" && "$kpr_refs" -ge 1 ]] && ok=1 || ok=0
assert "COMMAND.md invokes cost-report-dedup.js via \${MH_PLUGIN_ROOT} and never names the hook-only \${CLAUDE_PLUGIN_ROOT} (got $kpr_refs KBG refs, $cpr_refs CLAUDE refs)" "$ok"

# Adversarial case: a session_id with a pre-stream legacy row (model_scoped:true,
# no `stream` field — always meant the orchestrator total) and a post-fix
# orchestrator row for the SAME model, newer timestamp. Must dedup to ONE row
# (the newer one wins), not sum both. The two rows carry DIFFERENT costs ($5.0
# vs $7.0) on purpose — if the dedup key were buggy and summed instead of
# deduping, the total would be $12.0000; if it deduped but picked the wrong
# (older) row, it'd be $5.0000. Only "latest wins, no summing" lands on $7.0000,
# so the assertion pins the exact semantics, not just a plausible-looking number.
fake_home=$(mktemp -d)
metrics_dir="$fake_home/.local/share/kbg/metrics"
mkdir -p "$metrics_dir"
cat > "$metrics_dir/costs.jsonl" <<'EOF'
{"timestamp":"2026-08-01T00:00:00Z","session_id":"upgrade-span","transcript_path":"/t","model":"claude-opus-4-8","model_scoped":true,"input_tokens":100,"output_tokens":50,"cache_write_tokens":0,"cache_read_tokens":0,"rate_verified":true,"estimated_cost_usd":5.0}
{"timestamp":"2026-08-07T00:00:00Z","session_id":"upgrade-span","transcript_path":"/t","model":"claude-opus-4-8","model_scoped":true,"stream":"orchestrator","turns":2,"input_tokens":100,"output_tokens":50,"cache_write_tokens":0,"cache_read_tokens":0,"cache_read_per_turn":0,"rate_verified":true,"estimated_cost_usd":7.0}
EOF
out=$(HOME="$fake_home" node "$REPORT_JS" 2>&1)
rc=$?
total=$(printf '%s' "$out" | /usr/bin/grep '^total:' | /usr/bin/grep -oE '\$[0-9.]+' | tr -d '$')
[[ "$rc" == "0" && "$total" == "7.0000" ]] && ok=1 || ok=0
assert "legacy streamless row (\$5) + post-fix orchestrator row (\$7, same session+model) dedup to the NEWER row only, not summed (got total=\$${total:-?}, want \$7.0000)" "$ok"
trash "$fake_home" 2>/dev/null || true

# Positive case: two DIFFERENT streams for the same session+model must NOT
# collide — orchestrator and subagent are genuinely separate spend and both
# should survive dedup and sum.
fake_home=$(mktemp -d)
metrics_dir="$fake_home/.local/share/kbg/metrics"
mkdir -p "$metrics_dir"
cat > "$metrics_dir/costs.jsonl" <<'EOF'
{"timestamp":"2026-08-07T00:00:00Z","session_id":"two-streams","transcript_path":"/t","model":"claude-sonnet-5","model_scoped":true,"stream":"orchestrator","turns":2,"input_tokens":100,"output_tokens":50,"cache_write_tokens":0,"cache_read_tokens":0,"cache_read_per_turn":0,"rate_verified":true,"estimated_cost_usd":3.0}
{"timestamp":"2026-08-07T00:00:01Z","session_id":"two-streams","transcript_path":"/t","model":"claude-sonnet-5","model_scoped":true,"stream":"subagent","turns":4,"input_tokens":50,"output_tokens":25,"cache_write_tokens":0,"cache_read_tokens":0,"cache_read_per_turn":0,"rate_verified":true,"estimated_cost_usd":2.0}
EOF
out=$(HOME="$fake_home" node "$REPORT_JS" 2>&1)
rc=$?
total=$(printf '%s' "$out" | /usr/bin/grep '^total:' | /usr/bin/grep -oE '\$[0-9.]+' | tr -d '$')
[[ "$rc" == "0" && "$total" == "5.0000" ]] && ok=1 || ok=0
assert "orchestrator + subagent rows (same session+model, DIFFERENT stream) both survive dedup and sum (got total=\$${total:-?}, want \$5.0000)" "$ok"
trash "$fake_home" 2>/dev/null || true

# Adversarial case (2026-08-07, agent_type breakdown): two subagent rows, same
# session+model+stream, DIFFERENT agent_type. Must NOT collide — a mh:code-reviewer
# dispatch and an Explore dispatch on the same model are different populations of
# work, same reasoning as the stream split above. Differing costs ($4/$6) so only
# "both survive, sum to $10" passes — a buggy dedup key that ignores agent_type
# would drop one and land on $4 or $6 instead.
fake_home=$(mktemp -d)
metrics_dir="$fake_home/.local/share/kbg/metrics"
mkdir -p "$metrics_dir"
cat > "$metrics_dir/costs.jsonl" <<'EOF'
{"timestamp":"2026-08-07T00:00:00Z","session_id":"two-types","transcript_path":"/t","model":"claude-sonnet-5","model_scoped":true,"stream":"subagent","agent_type":"mh:code-reviewer","turns":2,"input_tokens":100,"output_tokens":50,"cache_write_tokens":0,"cache_read_tokens":0,"cache_read_per_turn":0,"rate_verified":true,"estimated_cost_usd":4.0}
{"timestamp":"2026-08-07T00:00:01Z","session_id":"two-types","transcript_path":"/t","model":"claude-sonnet-5","model_scoped":true,"stream":"subagent","agent_type":"Explore","turns":4,"input_tokens":50,"output_tokens":25,"cache_write_tokens":0,"cache_read_tokens":0,"cache_read_per_turn":0,"rate_verified":true,"estimated_cost_usd":6.0}
EOF
out=$(HOME="$fake_home" node "$REPORT_JS" 2>&1)
rc=$?
total=$(printf '%s' "$out" | /usr/bin/grep '^total:' | /usr/bin/grep -oE '\$[0-9.]+' | tr -d '$')
[[ "$rc" == "0" && "$total" == "10.0000" ]] \
  && printf '%s' "$out" | /usr/bin/grep -q 'By agent type' \
  && printf '%s' "$out" | /usr/bin/grep -q 'mh:code-reviewer' \
  && printf '%s' "$out" | /usr/bin/grep -q 'Explore' && ok=1 || ok=0
assert "two subagent rows (same session+model+stream, DIFFERENT agent_type) both survive dedup, sum to \$10, and appear in the By agent type section (got total=\$${total:-?})" "$ok"
trash "$fake_home" 2>/dev/null || true

# Regression (found live, 2026-08-07, running this exact report against real
# production data): the report's `by()` helper groups over the FULL `latest` array
# regardless of which key function is passed — it does not pre-filter to the rows
# the caller actually cares about. "By stream" already guards this by skipping the
# "(unknown)" bucket when printing; "By agent type" shipped WITHOUT that same guard,
# so every non-subagent row (every orchestrator row, on a real dataset almost the
# whole total) landed in an "(unknown)" line that read as "$38,403 of untyped
# subagent spend" when it was actually "everything that isn't a typed subagent row."
# Pin it: one large orchestrator row (no agent_type) + one small typed subagent row.
# The By agent type section must show ONLY the subagent row's own $2, never the
# orchestrator's $1000, and must never print a bare "(unknown)" line.
fake_home=$(mktemp -d)
metrics_dir="$fake_home/.local/share/kbg/metrics"
mkdir -p "$metrics_dir"
cat > "$metrics_dir/costs.jsonl" <<'EOF'
{"timestamp":"2026-08-07T00:00:00Z","session_id":"unknown-leak","transcript_path":"/t","model":"claude-sonnet-5","model_scoped":true,"stream":"orchestrator","turns":2,"input_tokens":100,"output_tokens":50,"cache_write_tokens":0,"cache_read_tokens":0,"cache_read_per_turn":0,"rate_verified":true,"estimated_cost_usd":1000.0}
{"timestamp":"2026-08-07T00:00:01Z","session_id":"unknown-leak","transcript_path":"/t","model":"claude-sonnet-5","model_scoped":true,"stream":"subagent","agent_type":"Explore","turns":1,"input_tokens":5,"output_tokens":2,"cache_write_tokens":0,"cache_read_tokens":0,"cache_read_per_turn":0,"rate_verified":true,"estimated_cost_usd":2.0}
EOF
out=$(HOME="$fake_home" node "$REPORT_JS" 2>&1)
rc=$?
agent_section=$(printf '%s' "$out" | awk '/=== By agent type/{f=1;next} /^$/{f=0} f')
[[ "$rc" == "0" ]] \
  && printf '%s' "$agent_section" | /usr/bin/grep -q 'Explore' \
  && printf '%s' "$agent_section" | /usr/bin/grep -q '\$2.0000' \
  && ! printf '%s' "$agent_section" | /usr/bin/grep -q '1000' \
  && ! printf '%s' "$out" | /usr/bin/grep -qE '\(unknown\)\s*$' \
  && ! printf '%s' "$out" | /usr/bin/grep -q '(unknown)  ' && ok=1 || ok=0
assert "By agent type shows only the typed subagent row's own \$2.0000, never the untyped orchestrator row's \$1000, and never prints an (unknown) line" "$ok"
trash "$fake_home" 2>/dev/null || true

echo ""
total_t=$((pass + fail))
echo "=== $pass/$total_t passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
