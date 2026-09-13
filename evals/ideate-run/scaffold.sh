#!/usr/bin/env bash
cat > PROBLEM.md <<'FIXTURE_EOF'
Design a per-tenant rate limiter for a multi-region HTTP API. Limits must keep holding
through a region failover and a leader election, and a tenant must never be able to
exceed 2x its quota during the election window. Latency budget: 2 ms p99 added per request.
FIXTURE_EOF
