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
# Heuristic (revised 2026-07-08 after false positives): a bare mention of
# jira/confluence is NOT enough -- in harness/dotfiles sessions "jira" is a
# plugin name, not work intent (e.g. "ทำให้ CC รู้จัก plugin jira-acli" fired
# the nudge on pure meta-discussion). Gate:
#   - TP-* ticket key => fire (unambiguous work intent).
#   - jira/confluence token => fire only with a work verb (create/file/write/
#     edit/update/comment/transition/publish/search/view/find/list/query/
#     export/check/post + Thai สร้าง/แก้/อัปเดต/ย้าย/เขียน/ค้น/หา/ดู/เช็ค/โพสต์)
#     AND no harness-meta signal (plugin|jira-acli|kbg-harness|hook|skill|
#     doctrine) -- the meta signal means the prompt is ABOUT the plugin system,
#     not a Jira/Confluence task. "acli" alone is NOT meta (raw acli is the
#     bypass this nudge catches).
set -uo pipefail

INPUT=$(cat)

# TP-* ticket key = unambiguous work intent.
if /usr/bin/grep -qiE '\btp-[0-9]+\b' <<< "$INPUT"; then
  : # fall through to emit
elif /usr/bin/grep -qiE '\b(jira|confluence)\b' <<< "$INPUT"; then
  # harness-meta signal = discussion about the plugin/harness, not jira work.
  if /usr/bin/grep -qiE '\b(plugin|jira-acli|kbg-harness|hooks?|skills?|doctrine)\b' <<< "$INPUT"; then
    exit 0
  fi
  # require a work verb (EN + TH); bare mention without one is not work intent.
  if ! /usr/bin/grep -qiE '\b(create|file|open|log|report|raise|write|edit|update|comment|transition|publish|search|view|find|list|query|export|check|post|move|bulk)\b' <<< "$INPUT" \
     && ! /usr/bin/grep -qE 'สร้าง|แก้|อัปเดต|ย้าย|คอมเมนต์|เปิด|เขียน|ค้น|หา|ดู|เช็ค|โพสต์|เพิ่ม' <<< "$INPUT"; then
    exit 0
  fi
else
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
