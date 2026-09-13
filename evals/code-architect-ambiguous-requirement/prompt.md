---
name: code-architect-ambiguous-requirement
tags: [code-architect, planted]
runs: 3
max_turns: 20
timeout_seconds: 400
allowed_tools: [Bash, Read, Grep, Glob, Agent]
---
Add a referral rewards feature: when a user refers a friend who signs up, the referrer gets $10
credit via `CreditLedger.add_credit()` (see `src/domain/credit_ledger.py`). Signup already tracks
`referred_by` (see `src/domain/user.py` and `src/api/signup_routes.py`). Use the
`mh:code-architect` agent for this (dispatch it via the Agent tool with
`subagent_type: "mh:code-architect"`) to produce a full implementation blueprint. Relay whatever it
produces back to me in full, verbatim.
