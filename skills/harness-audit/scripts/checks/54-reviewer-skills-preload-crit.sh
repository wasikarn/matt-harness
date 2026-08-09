#!/usr/bin/env bash
# 54. Reviewer skills: preload must survive rewrites (CRIT).
# typescript-reviewer + nextjs-reviewer preload their framework-patterns skill
# via the official `skills:` agent-frontmatter field (CC >= 2.0.43,
# code.claude.com/docs/en/sub-agents "Preload skills into subagents": full
# skill content injected at spawn; independent of the Skill tool). The effect
# was live-verified 2026-08-07 (byte-level transcript diff + negative control,
# docs/research/orchestrator-tax-gap-analysis-2026-08-07.md), then removed
# 2026-08-09 (v0.68.231) by a cleanup pass whose rationale conflated preload
# with Skill-tool access — two audits reached opposite conclusions about the
# same mechanism and nothing reconciled them. Restored v0.68.244. This check
# is the regression fixture: a future removal argues with a failing gate, not
# a prose comment. Mirrors #39/#49's shape — a silently-dropped field here is
# a capability regression invisible at dispatch time (the agent still
# answers, just without the injected patterns content).
for _pair in "typescript-reviewer|kbg:typescript-patterns" "nextjs-reviewer|kbg:frontend-patterns"; do
  _agent="${_pair%%|*}"
  _skill="${_pair#*|}"
  _f="$CLAUDE_DIR/agents/$_agent.md"
  if [ -f "$_f" ]; then
    _fm="$(awk '/^---$/{n++; next} n==1' "$_f")"
    if ! { printf '%s\n' "$_fm" | grep -q '^skills:' \
        && printf '%s\n' "$_fm" | grep -qF -- "- $_skill"; }; then
      crit "'agents/$_agent.md': missing 'skills:' preload of $_skill — the spawn-time patterns injection (official sub-agents field, live-verified 2026-08-07) has been silently dropped; read this check's header + CHANGELOG v0.68.244 before removing it again"
    fi
  fi
done
