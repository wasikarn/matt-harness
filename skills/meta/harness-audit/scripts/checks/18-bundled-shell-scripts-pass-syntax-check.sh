#!/usr/bin/env bash
# 18. Bundled shell scripts pass syntax check
# hooks/ added 2026-09-01 (deep-audit finding) -- this check previously scanned
# only skills/, leaving the entire hooks/ tree (gates, advisory, session, stop)
# invisible to the harness's own self-audit. Commit/push-time coverage already
# exists for hooks/*.sh (git-hooks/pre-commit, scripts/run-gauntlet.sh both run
# bash -n + shellcheck), but that only fires at commit/push -- this check is the
# one that can be run standalone, any time, mid-session, before a broken gate
# script is committed at all.
while IFS= read -r f; do
  if ! bash -n "$f" 2>/dev/null; then
    crit "bundled script '${f#$CLAUDE_DIR/}' has a shell syntax error"
  fi
done < <({ find "$CLAUDE_DIR/skills" -name '*.sh' 2>/dev/null; find "$CLAUDE_DIR/hooks" -name '*.sh' 2>/dev/null; } || true)

