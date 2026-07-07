#!/usr/bin/env bash
# Advisory: when the user's prompt mentions Jira/Confluence work, nudge
# routing through the jira-acli plugin's skills (jira-acli:acli,
# jira-acli:jira-content, jira-acli:confluence-content) before any direct
# mcp__*atlassian*/mcp__*Rovo* tool call or raw acli command. UserPromptSubmit
# hook. Output -> stdout (CC surfaces as a system-reminder); never blocks,
# always exits 0. Errors are silently swallowed.
#
# Why non-blocking, not a gate: user-chosen scope (2026-07-07 audit) is nudge
# for Jira, ask-gate for tathep-db -- gating every mcp__*Rovo*/mcp__*Atlassian*
# call would also fire on jira-acli's OWN correct usage of those same MCP
# tools underneath its skills, converting the intended reminder into friction
# on the happy path. Confirmed incident this answers: TP-809/TP-806
# (2026-07-06) -- raw `acli ... --description-file` on a PRD/finding text file
# bypassed jira-acli's canonical template, flattening ADF into one paragraph.
#
# Heuristic: a bare mention of jira/confluence/a TP-* ticket key is narrow
# enough on its own (proper nouns, not generic English) -- no write-verb
# conjunction needed, unlike flow-nudge's broader IMPL verb set.
set -uo pipefail

INPUT=$(cat)

if ! /usr/bin/grep -qiE '\b(jira|confluence|tp-[0-9]+)\b' <<< "$INPUT"; then
  exit 0
fi

cat <<'EOF'

[kbg:jira-route-nudge] Jira/Confluence work detected.
  Route through jira-acli first: jira-acli:acli (mechanical/query/bulk ops),
  jira-acli:jira-content (Bug/Story/Task/Epic/Sub-task templates), or
  jira-acli:confluence-content (Spec/PRD pages) -- not a raw acli command or
  a direct mcp__*atlassian*/mcp__*Rovo* tool call.
  See ~/.claude/CLAUDE.md's "Atlassian / Jira & Confluence Work" section for
  the closed-gap list where the Atlassian MCP is the documented fallback.
The nudge is advisory; the model judges.
EOF

exit 0
