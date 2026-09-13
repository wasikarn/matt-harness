#!/usr/bin/env bash
cat > standup.md <<'FIXTURE_EOF'
Standup 2026-09-04

Yesterday: chased the flaky `test_retry_backoff` for most of the afternoon. Turned out the fake clock in conftest.py wasn't reset between parametrized cases, so the third case inherited 2.5s of drift. Fixed in PR #218 (small, one fixture). Merged.

Today: pairing with Ploy on the invoice export. She thinks the CSV encoder is the slow part, I think it's the N+1 on customer lookups. We'll profile it instead of arguing.

Blocker: still waiting on staging DB creds from ops (asked Tuesday, ticket OPS-91).
FIXTURE_EOF
