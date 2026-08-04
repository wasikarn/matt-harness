#!/usr/bin/env bash
# Stop: gate a substantial reply on carrying a short Thai closing summary.
#
# Global CLAUDE.md's "Task Completion Summary" rule (close every finished task with a
# short plain-Thai recap) had no mechanical enforcement — memory only, and it lapsed
# mid-session (confirmed 2026-08-04, caught by the operator). This makes it real:
# blocks the turn from ending until the last message either is short (a one-liner /
# clarifying question doesn't need a closing recap — a length floor, not a content
# classifier, per advisor review) or already contains Thai script.
#
# Blocks AT MOST ONCE per turn: `stop_hook_active == true` means this Stop is itself
# the forced retry, so it always allows rather than re-checking and potentially
# re-blocking. One forced retry converts a miss into a hit; burning multiple retries
# on a style nit (Claude Code's own cap is 8 consecutive blocks, CLAUDE_CODE_STOP_HOOK_
# BLOCK_CAP) would be a worse failure than letting one summary slide.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)

stop_hook_active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0
[[ "$stop_hook_active" == "true" ]] && exit 0

msg=$(printf '%s' "$payload" | jq -r '.last_assistant_message // ""' 2>/dev/null) || exit 0

# Below the floor: too short to be a task-completion reply that needs a closing recap.
[[ ${#msg} -lt 400 ]] && exit 0

has_thai=$(printf '%s' "$payload" | jq -r '(.last_assistant_message // "") | test("[฀-๿]")' 2>/dev/null) || exit 0
[[ "$has_thai" == "true" ]] && exit 0

jq -n '{decision:"block", reason:"งานนี้ดูเหมือนจะเสร็จแล้วแต่ยังไม่มีสรุปปิดท้าย — ปิดท้ายด้วยสรุปสั้น ๆ เป็นภาษาไทยเข้าใจง่าย ตามกฎ Task Completion Summary ใน CLAUDE.md"}'
exit 0
