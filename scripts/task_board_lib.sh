#!/bin/bash
# task_board_lib.sh — bash helpers for task board integration
# Used by hooks/task-lifecycle.sh and other bash consumers.
#
# Functions:
#   kbg_board_read <plan_dir>          → stdout: board.json contents
#   kbg_board_write <plan_dir> <json>  → atomic write to board.json
#   kbg_lock_acquire <plan_dir> [timeout] → mkdir-based lock with auto-release
#   kbg_recompute_blocked <plan_dir>   → recompute blocked_by from depends_on

# P0: fail fast on errors and unset variables
set -euo pipefail

# Read board.json. Returns 1 if missing or invalid JSON.
kbg_board_read() {
  local plan_dir="$1"
  local board_file="${plan_dir}/board.json"
  if [ ! -f "$board_file" ]; then
    echo "[task-board] board.json not found: $board_file" >&2
    return 1
  fi
  if ! jq -e . "$board_file" >/dev/null 2>&1; then
    echo "[task-board] board.json is invalid JSON: $board_file" >&2
    return 1
  fi
  cat "$board_file"
}

# Atomic write via tmp + mv. Payload is a single JSON string.
kbg_board_write() {
  local plan_dir="$1"
  local payload="$2"
  local board_file="${plan_dir}/board.json"
  local tmp_file="${board_file}.tmp.$$"
  # P0: refuse to write empty payload to avoid accidental board wipe
  if [ -z "$payload" ]; then
    echo "[task-board] ERROR: refuse to write empty payload to $board_file" >&2
    return 1
  fi
  printf '%s\n' "$payload" > "$tmp_file"
  mv "$tmp_file" "$board_file"
}

# Portable POSIX directory-lock via mkdir. Auto-released on process exit.
kbg_lock_acquire() {
  local plan_dir="$1"
  local timeout="${2:-10}"
  local lock_dir="${plan_dir}/.lock"
  local waited=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    # P0: distinguish permission errors from EEXIST contention
    if [ ! -e "$lock_dir" ]; then
      echo "[task-board] ERROR: mkdir $lock_dir failed (permissions?)" >&2
      return 1
    fi
    sleep 0.1
    waited=$((waited + 1))
    if [ "$waited" -ge "$((timeout * 10))" ]; then
      echo "[task-board] ERROR: lock acquisition timed out after ${timeout}s: $lock_dir" >&2
      return 1
    fi
  done
  # shellcheck disable=SC2064
  local lock_dir_escaped
  lock_dir_escaped=$(printf '%q' "$lock_dir")
  trap "rmdir ${lock_dir_escaped} 2>/dev/null || true" EXIT
  return 0
}

# Recompute blocked_by for all non-completed tasks based on depends_on.
# Updates board.json in place.
kbg_recompute_blocked() {
  local plan_dir="$1"
  local board
  board=$(kbg_board_read "$plan_dir") || return 1
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local new_board
  # P0: fail loudly if jq pipeline errors to prevent empty board overwrite
  new_board=$(printf '%s' "$board" | jq --arg now "$now" '
    [ .tasks | to_entries[] | select(.value.status == "completed") | .key ] as $completed_set |
    .tasks |= map_values(
      if .status == "completed" then .
      else
        (.depends_on // []) as $deps |
        [ $deps[] | select(. as $d | $completed_set | contains([$d]) | not) ] as $remaining |
        .blocked_by = $remaining |
        if ($remaining | length) > 0 and .status != "in_progress" and .status != "completed" then
          .status = "blocked"
        elif ($remaining | length) == 0 and .status == "blocked" then
          .status = "pending"
        else
          .
        end
      end
    ) |
    .updated_at = $now
  ') || return 1

  kbg_board_write "$plan_dir" "$new_board"
}
