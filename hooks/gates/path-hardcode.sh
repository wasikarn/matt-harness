#!/usr/bin/env bash
# Gate: block hardcoded /Users/<name> paths being written into .sh or .py files.
# Reads the PreToolUse JSON payload from stdin; exits 2 to block.
set -uo pipefail

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
file_path=$(python3 -c '
import sys, json, re
d = json.load(sys.stdin)
ti = d.get("tool_input", {})
fp = ti.get("file_path", "")
# Case-insensitive: foo.SH / foo.PY bypassed a case-sensitive endswith() check
# (found 2026-07-01).
if not fp.lower().endswith((".sh", ".py")):
    sys.exit(0)
# Write/Edit carry the new text at top-level content/new_string. MultiEdit
# carries an edits[] array instead — reading only the top-level fields left
# every MultiEdit call unscanned even though hooks.json registers this gate
# on the Write|Edit|MultiEdit matcher (found 2026-07-01).
content = ti.get("content") or ti.get("new_string") or ""
for edit in ti.get("edits") or []:
    content += "\n" + (edit.get("new_string") or "")
# /Users/<letter> = hardcoded username; /Users/$VAR = safe
if re.search(r"/Users/[a-zA-Z]", content):
    print(fp)
    sys.exit(1)
')
rc=$?

if [[ $rc -eq 1 ]]; then
  echo "[kbg:gate] BLOCKED: hardcoded /Users/ path in $file_path — use \$HOME or ~ instead" >&2
  exit 2
fi

exit 0
