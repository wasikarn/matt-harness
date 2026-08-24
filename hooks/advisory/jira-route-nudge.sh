#!/usr/bin/env bash
# Advisory: when the user's prompt mentions Jira/Confluence work, nudge
# routing through the jira-acli plugin's skills (jira-acli:acli,
# jira-acli:jira-content, jira-acli:confluence-content) before any direct
# mcp__*atlassian*/mcp__*Rovo* tool call or raw acli command. UserPromptSubmit
# hook. Output -> plain stdout — docs: "added as context Claude can see and
# act on" (not the JSON hookSpecificOutput.additionalContext path, which is
# what's specifically documented as wrapped in a "system reminder"); never
# blocks, always exits 0. Errors are silently swallowed.
#
# Why still non-blocking here (the actual block lives elsewhere now): this
# fires on the PROMPT, before any tool call exists yet, so there is nothing
# to block -- it is the earliest-possible reminder, not the enforcement
# boundary. The enforcement boundary is gates/atlassian-mcp-gate.sh
# (gate:mcp:atlassian-cold-start in hooks.json), added 2026-07-15 after this
# nudge alone proved insufficient in practice -- it hard-blocks (exit 2) any
# direct mcp__*atlassian*/mcp__*rovo* call until a jira-acli:* skill has
# loaded that session, and specifically does NOT fire on jira-acli's own
# in-skill MCP fallback (a session-scoped "engaged" marker set when the skill
# loads), so it doesn't create the happy-path friction this file used to cite
# as the reason to stay advisory-only. The two layers are complementary: this
# one nudges before the first tool call; that one blocks the call itself.
# Confirmed incident this answers: TP-809/TP-806 (2026-07-06) -- raw
# `acli ... --description-file` on a PRD/finding text file bypassed
# jira-acli's canonical template, flattening ADF into one paragraph.
#
# Heuristic (revised 2026-07-08 after false positives): a bare mention of
# jira/confluence is NOT enough -- in harness/dotfiles sessions "jira" is a
# plugin name, not work intent (e.g. "ทำให้ CC รู้จัก plugin jira-acli" fired
# the nudge on pure meta-discussion). Gate:
#   - TP-* ticket key => fire (unambiguous work intent).
#   - jira/confluence token => fire only with a work verb (create/file/write/
#     edit/update/comment/transition/publish/search/view/find/list/query/
#     export/check/post + Thai สร้าง/แก้/อัปเดต/ย้าย/เขียน/ค้น/หา/ดู/เช็ค/โพสต์)
#     AND no harness-meta signal (plugin|jira-acli|matt-harness|hook|skill|
#     doctrine) -- the meta signal means the prompt is ABOUT the plugin system,
#     not a Jira/Confluence task. "acli" alone is NOT meta (raw acli is the
#     bypass this nudge catches).
set -uo pipefail

# Feature-detect the jira-acli plugin (same shape as doctrine-bootstrap.sh's
# mattpocock-preflight check) -- this nudge is meaningless noise on a machine
# that never installed jira-acli@wasikarn; skip firing entirely rather than
# route the user toward a plugin they don't have. KBG_JIRA_ACLI_CACHE is a
# test-only override so unit tests don't depend on the real plugin cache.
JIRA_ACLI_CACHE="${KBG_JIRA_ACLI_CACHE:-${HOME:-}/.claude/plugins/cache/wasikarn/jira-acli}"
[[ -d "$JIRA_ACLI_CACHE" ]] || exit 0

INPUT=$(cat)

# TP-* ticket key = unambiguous work intent.
if /usr/bin/grep -qiE '\btp-[0-9]+\b' <<< "$INPUT"; then
  : # fall through to emit
elif /usr/bin/grep -qiE '\b(jira|confluence)\b' <<< "$INPUT"; then
  # harness-meta signal = discussion about the plugin/harness, not jira work.
  if /usr/bin/grep -qiE '\b(plugin|jira-acli|matt-harness|hooks?|skills?|doctrine)\b' <<< "$INPUT"; then
    exit 0
  fi
  # require a work verb (EN + TH); bare mention without one is not work intent.
  if ! /usr/bin/grep -qiE '\b(create|file|open|log|report|raise|write|edit|update|comment|transition|publish|search|view|find|list|query|export|check|post|move|bulk)\b|สร้าง|แก้|อัปเดต|ย้าย|คอมเมนต์|เปิด|เขียน|ค้น|หา|ดู|เช็ค|โพสต์|เพิ่ม' <<< "$INPUT"; then
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
  jira-acli's own docs list the cases where the Atlassian MCP is the
  documented fallback (e.g. Confluence page create/update).
The nudge is advisory; the model judges.
EOF

exit 0
