#!/usr/bin/env bash
# 49. Reviewer skills: preload must survive rewrites (CRIT).
# typescript-reviewer + nextjs-reviewer originally preloaded their framework-patterns skill
# via the official `skills:` agent-frontmatter field (CC >= 2.0.43,
# code.claude.com/docs/en/sub-agents "Preload skills into subagents": full
# skill content injected at spawn; independent of the Skill tool). The effect
# was live-verified 2026-08-07 (byte-level transcript diff + negative control,
# docs/research/orchestrator-tax-gap-analysis-2026-08-07.md), then removed
# 2026-08-09 (v0.68.231) by a cleanup pass whose rationale conflated preload
# with Skill-tool access — two audits reached opposite conclusions about the
# same mechanism and nothing reconciled them. Restored v0.68.244. This check
# is the regression fixture: a future removal argues with a failing gate, not
# a prose comment. Mirrors #36/#45's shape — a silently-dropped field here is
# a capability regression invisible at dispatch time (the agent still
# answers, just without the injected patterns content).
# typescript-reviewer|mh:typescript-patterns and nextjs-reviewer|mh:frontend-
# patterns REMOVED 2026-09-04 (v0.68.637): the preload mechanism is real (above),
# but neither body used the content — ~10 KB/spawn each for nothing. Both
# agents now carry a Read-when pointer to the SKILL.md instead. Deliberate,
# not the 2026-08-09 conflation; re-add only if a body citation returns.
# nextjs-reviewer|mh:review-lens-nextjs-routing added 2026-08-18 (v0.68.345):
# same preload mechanism, added when nextjs-reviewer.md was split under check
# 52's 20K-char threshold — carries App Router File Conventions/Middleware
# content this agent has no Skill tool to fetch on demand, so an unguarded
# drop here is the identical silent-regression shape this check exists for.
# requirement-analyst|mh:requirement-analyst-format added 2026-08-18: same
# split, same reason — requirement-analyst.md has no Skill tool by design
# (its own Tool guardrails section blocks adding one, to preserve the
# Jira/Confluence no-self-fetch boundary), so this preload is the only lawful
# extraction path and carries the self-consistency pass, Output Format
# template, and Anti-Patterns list this agent has no other way to reach.
# blind-spot-hunter|mh:blind-spot-hunter-shapes added 2026-08-18: same split,
# same reason — blind-spot-hunter.md has no Skill tool (tools: [Read, Grep,
# Glob, Bash]) and no prior companion skill existed, so this preload is the
# only lawful extraction path and carries the 7-shape hunt catalog this agent
# has no other way to reach.
# plan-reviewer|mh:plan-reviewer-format added 2026-08-18: same split, same
# reason — plan-reviewer.md has no Skill tool (tools: [Read, Grep, Glob,
# Bash]) and no prior companion skill existed, so this preload is the only
# lawful extraction path and carries the Output Format template, lens-
# disambiguation notes, and Anti-Patterns list this agent has no other way
# to reach. Removed from this list 2026-08-18 through 2026-08-24 (#78,
# planning/prep surfaces wrongly judged to overlap
# mattpocock-skills:grilling) — restored 2026-08-25.
# summarizer|mh:summarizer-format added 2026-08-18: same split, same reason
# — summarizer.md has no Skill tool (tools: ["Read", "Grep", "Glob"]) and no
# prior companion skill existed, so this preload is the only lawful
# extraction path and carries the Output Format templates, word-level
# compression BAD/GOOD table, and Anti-Patterns list this agent has no other
# way to reach.
# security-reviewer|mh:security-reviewer-patterns added 2026-08-18: same
# split, same reason — security-reviewer.md has no Skill tool (tools:
# ["Read", "Bash", "Grep", "Glob"]). This skill carries only the BAD/GOOD
# code-example appendix this agent has no other way to reach.
# spec-miner|mh:spec-miner-anti-patterns added 2026-08-18: same split, same
# reason — spec-miner.md has no Skill tool (tools: ["Read", "Grep", "Glob",
# "Bash", "Write"]) and no prior companion skill existed, so this preload is
# the only lawful extraction path and carries the 10-item Anti-Patterns list
# this agent has no other way to reach.
# performance-optimizer|mh:performance-optimizer-algorithms added 2026-08-18:
# same split, same reason — performance-optimizer.md has no Skill tool
# (tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]) and no prior
# companion skill existed, so this preload is the only lawful extraction path
# and carries the 14-row Algorithmic Analysis pattern table this agent has no
# other way to reach.
for _pair in "nextjs-reviewer|mh:review-lens-nextjs-routing" "requirement-analyst|mh:requirement-analyst-format" "blind-spot-hunter|mh:blind-spot-hunter-shapes" "summarizer|mh:summarizer-format" "security-reviewer|mh:security-reviewer-patterns" "performance-optimizer|mh:performance-optimizer-algorithms" "plan-reviewer|mh:plan-reviewer-format"; do
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
