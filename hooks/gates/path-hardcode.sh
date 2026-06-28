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
if not (fp.endswith(".sh") or fp.endswith(".py")):
    sys.exit(0)
content = ti.get("content") or ti.get("new_string") or ""
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
