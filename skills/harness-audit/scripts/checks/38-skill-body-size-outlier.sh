#!/usr/bin/env bash
# 38. Skill body size outlier — flag SKILL.md bodies large enough to warrant a
# token-optimizer pass (e.g. `/markdown-token-optimizer`). INFO only, never a
# hard cap: kbg's skills are legitimately denser than a generic small-skill
# target (orchestrate carries load-bearing procedure/reference
# content). Threshold is the fleet's own distribution, not an imported one —
# picked 2026-07-17 from n=33 (p90 ~15K chars); the two skills currently above
# it are the two that already needed a manual token-optimizer pass this
# session. Gap this closes: no fleet-native surface (`mh:inventory`,
# `--health`) reports SKILL.md body size — `--health` is session token COST,
# inventory lists surfaces with no size field at all.
SIZE_THRESHOLD_CHARS=20000
for _f in "$CLAUDE_DIR"/skills/[!_]*/SKILL.md; do
  [ -f "$_f" ] || continue
  _chars=$(wc -c < "$_f" | tr -d ' ')
  if [ "$_chars" -gt "$SIZE_THRESHOLD_CHARS" ]; then
    _tokens=$((_chars / 4))
    _skill=$(basename "$(dirname "$_f")")
    info "'$_skill' SKILL.md is ${_chars} chars (~${_tokens} tokens, fleet threshold ${SIZE_THRESHOLD_CHARS}) — consider a token-optimizer pass to move detail into reference.md"
  fi
done
unset _f _chars _tokens _skill SIZE_THRESHOLD_CHARS
