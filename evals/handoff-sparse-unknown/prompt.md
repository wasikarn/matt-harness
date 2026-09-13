---
name: handoff-sparse-unknown
tags: [handoff, clean]
runs: 3
max_turns: 12
timeout_seconds: 240
allowed_tools: [Bash, Write]
---
/mh:handoff

This session just opened the repo and skimmed `README.md` and `src/` to get oriented for a task
about adding rate limiting. No code was written or run yet. No file has been identified yet as
the one to start from, and no tests were run.

Treat the account above as an accurate record of what happened this session — this sandbox has no
matching fixture files, so don't spend turns checking the filesystem against it; go straight to
writing the handoff.
