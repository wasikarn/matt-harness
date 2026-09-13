---
name: ideate-critic-security-review-misroute
tags: [ideate-critic, misroute]
runs: 3
max_turns: 20
timeout_seconds: 400
allowed_tools: [Bash, Read, Grep, Glob, Agent]
---
Review `src/auth/login.py` for security issues and code quality before we ship it.
