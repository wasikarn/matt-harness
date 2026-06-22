#!/usr/bin/env bash
# launch.sh — the L4 self-launch launcher (design §8, ADR 0004 #1).
#
# Invoked by a detached, persistent macOS launchd StartInterval plist (NO Claude
# Code session). Reads cadence/config ONLY from the caged scheduler.conf, honors the
# kill-file before every launch, sets KBG_AUTONOMY=1, and drives ONE --auto cycle.
# The cycle is the recursive-improve prose, which calls the SAME l3-loop-guard.py
# subcommands (caps + cage + --max-flat + R4 + --assert-cage-intact) — NO parallel
# enforcement path. Gate 2 (push review) still holds every batch — nothing here
# auto-pushes or auto-merges.
#
# Cadence is throttled by R4 (the cycle's precheck reads --max-runs-per-window /
# --window-seconds, surfaced here from scheduler.conf). Kill-switch = delete the
# caged scheduler.conf entry OR drop the kill-file; R4 window caps auto-STOP a
# runaway before a human intervenes.
#
# NOT /loop or CronCreate — greenfield, in-cage. The OS scheduler (launchd), NOT the
# model, self-starts this shell script, so recursive-improve's
# disable-model-invocation: true is NOT contradicted (audit #32 stays unchanged +
# additively asserts THIS path is the sole sanctioned self-start).
#
# KBG_LAUNCH_CMD overrides the cycle invocation (tests inject a fake); the default
# invokes a claude --auto cycle on the repo. The owner arms L4 as a separate, later
# act — Slice 3 builds the launcher, it does not enable it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONF="${KBG_L4_CONF:-$SCRIPT_DIR/scheduler.conf}"
KILLFILE="${KBG_L4_KILLFILE:-$HOME/.claude/kbg-l4-kill}"

# 1. Config ONLY from the caged scheduler.conf. No file → kill-switch active.
if [ ! -f "$CONF" ]; then
  echo "l4-launch: no scheduler.conf — kill-switch (delete the entry) is active; aborting" >&2
  exit 0
fi
command -v jq >/dev/null 2>&1 || { echo "l4-launch: jq missing — cannot read scheduler.conf" >&2; exit 0; }
MAXRUNS=$(jq -r '.max_runs_per_window // 0' "$CONF")
WINSEC=$(jq -r '.window_seconds // 0' "$CONF")

# 2. Honor the kill-file before every launch (a kill-file defeats a self-reinstalling
#    schedule — the loop cannot remove it: the Act-layer gate denies writes to it
#    while armed, + this check is outside the loop's reach).
if [ -f "$KILLFILE" ]; then
  echo "l4-launch: kill-file present ($KILLFILE) — aborting launch" >&2
  exit 0
fi

# 3. Arm + drive ONE --auto cycle. cd to the repo so the cycle's l3-loop-guard
#    _assert_repo_root (F4) anchors REPO_ROOT to THIS checkout. R4 caps are surfaced
#    via env for the cycle's precheck.
cd "$REPO" || { echo "l4-launch: cannot cd to $REPO" >&2; exit 0; }
export KBG_AUTONOMY=1
export CLAUDE_PROJECT_DIR="$REPO"
export KBG_L4_MAX_RUNS_PER_WINDOW="$MAXRUNS"
export KBG_L4_WINDOW_SECONDS="$WINSEC"
CYCLE_CMD="${KBG_LAUNCH_CMD:-claude -p --dangerously-skip-permissions \"run one kbg:recursive-improve --auto cycle now\"}"
# shellcheck disable=SC2086
eval "$CYCLE_CMD" || true
exit 0