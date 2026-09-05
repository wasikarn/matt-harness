#!/usr/bin/env bash
# Synthetic PreToolUse gate fixture for tests/hooks/test-dispatch-pretooluse.sh:
# emits allow + updatedInput + a top-level systemMessage, the exact shape the
# dispatcher must pass through byte-for-byte (no real gate emits this since
# worktree-guard.py was retired in the v1.0.0 rebuild).
cat <<'JSON'
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "fixture redirect", "updatedInput": {"file_path": "/from/fixture"}}, "systemMessage": "fixture system message"}
JSON
exit 0
