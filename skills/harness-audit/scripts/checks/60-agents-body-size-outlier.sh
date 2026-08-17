#!/usr/bin/env bash
# 60. Agent body size outlier — flag agents/*.md files large enough to warrant
# a token-optimizer pass or a lens-extraction split. INFO only, mirrors check
# 42 (skills) / 51 (commands) exactly, same 20K-char threshold and reasoning.
# Gap this closes: neither 42 nor 51 globs agents/*.md, so a subagent
# definition has never been mechanically flagged for size regardless of how
# large it grows — the identical blind spot check 51 itself was built to
# close for commands/*.md on 2026-07-31, recurring one surface over.
# Confirmed 2026-08-17 (5-agent deep-audit follow-up): agents/code-reviewer.md
# (23,979 chars, already lens-extracted once) and agents/nextjs-reviewer.md
# (22,772 chars, single-domain, no split candidate) both sat over this same
# threshold with zero check able to see them.
SIZE_THRESHOLD_CHARS=20000
for _f in "$CLAUDE_DIR"/agents/*.md; do
  [ -f "$_f" ] || continue
  _chars=$(wc -c < "$_f" | tr -d ' ')
  if [ "$_chars" -gt "$SIZE_THRESHOLD_CHARS" ]; then
    _tokens=$((_chars / 4))
    _agent=$(basename "$_f" .md)
    info "'$_agent' agent body is ${_chars} chars (~${_tokens} tokens, fleet threshold ${SIZE_THRESHOLD_CHARS}) — consider a token-optimizer pass, or (if it already carries the Skill tool) extracting a conditionally-relevant section into a kbg:review-lens-* style skill"
  fi
done
unset _f _chars _tokens _agent SIZE_THRESHOLD_CHARS
