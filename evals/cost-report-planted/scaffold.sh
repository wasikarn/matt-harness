#!/usr/bin/env bash
mkdir -p metrics
cat > metrics/costs.jsonl <<'FIXTURE_EOF'
{"timestamp":"2026-08-01T00:00:00Z","session_id":"upgrade-span","transcript_path":"/t","model":"claude-opus-5","model_scoped":true,"input_tokens":100,"output_tokens":50,"cache_write_tokens":0,"cache_read_tokens":0,"rate_verified":true,"estimated_cost_usd":5.0}
{"timestamp":"2026-09-05T00:00:00Z","session_id":"upgrade-span","transcript_path":"/t","model":"claude-opus-5","model_scoped":true,"dedup_usage":true,"usage_pick":"last","stream":"orchestrator","turns":3,"input_tokens":200,"output_tokens":80,"cache_write_tokens":0,"cache_read_tokens":0,"cache_read_per_turn":0,"rate_verified":true,"estimated_cost_usd":7.0}
{"timestamp":"2026-09-05T00:00:01Z","session_id":"delegated","transcript_path":"/u","model":"claude-sonnet-5","model_scoped":true,"dedup_usage":true,"usage_pick":"last","stream":"subagent","agent_type":"Explore","turns":1,"input_tokens":5,"output_tokens":2,"cache_write_tokens":0,"cache_read_tokens":0,"cache_read_per_turn":0,"rate_verified":true,"estimated_cost_usd":2.0}
{"timestamp":"2026-09-05T00:00:02Z","session_id":"legacy-era","transcript_path":"/v","model":"claude-sonnet-5","model_scoped":true,"stream":"orchestrator","turns":2,"input_tokens":100,"output_tokens":50,"cache_write_tokens":0,"cache_read_tokens":0,"cache_read_per_turn":0,"rate_verified":true,"estimated_cost_usd":1.0}
FIXTURE_EOF
