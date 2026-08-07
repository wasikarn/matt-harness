#!/usr/bin/env bash
# Regression test for commands/cost-report.md's embedded "## Report" node script.
# Extracts the script the same way a user would run it (the first ```bash fence),
# points it at a synthetic HOME so it never touches the real
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
# Run standalone: bash tests/commands/test-cost-report.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COST_REPORT_MD="$ROOT/commands/cost-report.md"

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

# Extract the first ```bash fenced block (the "## Report" script) the same way a
# user copy-pastes it — no separate maintained copy to drift from the doc. The
# block itself is a complete `node -e '...'` shell command, so it's executed
# directly as bash, not re-wrapped inside another `node -e`.
extract_report_script() {
  awk '/^```bash$/{f++; if (f==1) {p=1; next}} /^```$/{if (p) {p=0}} p' "$COST_REPORT_MD"
}
REPORT_SCRIPT=$(extract_report_script)
[[ -n "$REPORT_SCRIPT" ]] || { echo "FATAL: could not extract the report script from $COST_REPORT_MD" >&2; exit 1; }
[[ "$REPORT_SCRIPT" == node* ]] || { echo "FATAL: extracted block doesn't start with 'node' — extraction grabbed the wrong fence or cost-report.md's script shape changed" >&2; exit 1; }

echo "=== cost-report.md dedup (stream-aware) ==="

# Adversarial case: a session_id with a pre-stream legacy row (model_scoped:true,
# no `stream` field — always meant the orchestrator total) and a post-fix
# orchestrator row for the SAME model, newer timestamp. Must dedup to ONE row
# (the newer one wins), not sum both.
fake_home=$(mktemp -d)
metrics_dir="$fake_home/.local/share/kbg/metrics"
mkdir -p "$metrics_dir"
cat > "$metrics_dir/costs.jsonl" <<'EOF'
{"timestamp":"2026-08-01T00:00:00Z","session_id":"upgrade-span","transcript_path":"/t","model":"claude-opus-4-8","model_scoped":true,"input_tokens":100,"output_tokens":50,"cache_write_tokens":0,"cache_read_tokens":0,"rate_verified":true,"estimated_cost_usd":5.0}
{"timestamp":"2026-08-07T00:00:00Z","session_id":"upgrade-span","transcript_path":"/t","model":"claude-opus-4-8","model_scoped":true,"stream":"orchestrator","turns":2,"input_tokens":100,"output_tokens":50,"cache_write_tokens":0,"cache_read_tokens":0,"cache_read_per_turn":0,"rate_verified":true,"estimated_cost_usd":5.0}
EOF
out=$(HOME="$fake_home" bash -c "$REPORT_SCRIPT" 2>&1)
rc=$?
total=$(printf '%s' "$out" | /usr/bin/grep '^total:' | /usr/bin/grep -oE '\$[0-9.]+' | tr -d '$')
[[ "$rc" == "0" && "$total" == "5.0000" ]] && ok=1 || ok=0
assert "legacy streamless row + post-fix orchestrator row (same session+model) dedup to ONE row, not summed (got total=\$${total:-?}, want \$5.0000)" "$ok"
rm -rf "$fake_home"

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
out=$(HOME="$fake_home" bash -c "$REPORT_SCRIPT" 2>&1)
rc=$?
total=$(printf '%s' "$out" | /usr/bin/grep '^total:' | /usr/bin/grep -oE '\$[0-9.]+' | tr -d '$')
[[ "$rc" == "0" && "$total" == "5.0000" ]] && ok=1 || ok=0
assert "orchestrator + subagent rows (same session+model, DIFFERENT stream) both survive dedup and sum (got total=\$${total:-?}, want \$5.0000)" "$ok"
rm -rf "$fake_home"

echo ""
total_t=$((pass + fail))
echo "=== $pass/$total_t passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
