#!/usr/bin/env bash
# 22. Hook config validity — settings.json (checks C–F).
# Verified against code.claude.com/docs/en/hooks (30-event canonical set, re-confirmed
# 2026-07-31 via raw HTML fetch — the DOC_EVENTS set below matches the live doc
# item-for-item). Findings are WARN not CRIT: vendor docs lag features (Rule 1), so
# an unrecognized event/type may be real-but-undocumented — flag for a human, do
# not fail the build. A bad regex, by contrast, genuinely never matches.
if [ -f "$SETTINGS" ]; then
  while IFS= read -r finding; do
    [ -n "$finding" ] && warn "$finding"
  done < <(python3 - "$SETTINGS" <<'PYEOF'
import json, re, sys
# Canonical event set — code.claude.com/docs/en/hooks "Hook lifecycle" table.
DOC_EVENTS = {
    "SessionStart","Setup","UserPromptSubmit","UserPromptExpansion","PreToolUse",
    "PermissionRequest","PermissionDenied","PostToolUse","PostToolUseFailure",
    "PostToolBatch","Notification","MessageDisplay","SubagentStart","SubagentStop",
    "TaskCreated","TaskCompleted","Stop","StopFailure","TeammateIdle",
    "InstructionsLoaded","ConfigChange","CwdChanged","FileChanged","WorktreeCreate",
    "WorktreeRemove","PreCompact","PostCompact","Elicitation","ElicitationResult",
    "SessionEnd",
}
VALID_TYPES = {"command","http","mcp","agent","prompt"}
AC_MAX = 10000
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)  # JSON validity is covered elsewhere; don't double-report.
hooks = cfg.get("hooks", {})
if not isinstance(hooks, dict):
    sys.exit(0)
for ev, arr in hooks.items():
    # E: event name in documented set
    if ev not in DOC_EVENTS:
        print(f"hook event '{ev}' not in documented event set (typo? or undocumented — verify)")
    if not isinstance(arr, list):
        continue
    for blk in arr:
        if not isinstance(blk, dict):
            continue
        # D: matcher must be a compilable regex. '*' and '' are wildcard
        # sentinels (match-all), valid to Claude Code but not to Python re —
        # skip them so they don't false-positive.
        m = blk.get("matcher")
        if isinstance(m, str) and m not in ("", "*"):
            try:
                re.compile(m)
            except re.error as e:
                print(f"hook '{ev}' matcher {m!r} is not a valid regex ({e})")
        for h in blk.get("hooks", []):
            if not isinstance(h, dict):
                continue
            # C: handler type
            t = h.get("type")
            if t is not None and t not in VALID_TYPES:
                print(f"hook '{ev}' handler type '{t}' not in {sorted(VALID_TYPES)}")
            # F: static additionalContext length. Runtime-generated context
            # (command-type stdout) is invisible here; this only catches a
            # literal field hardcoded in settings.json.
            ac = h.get("additionalContext")
            if isinstance(ac, str) and len(ac) > AC_MAX:
                print(f"hook '{ev}' static additionalContext is {len(ac)} chars (>{AC_MAX}; truncated)")
PYEOF
)
fi

