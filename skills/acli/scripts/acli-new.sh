#!/usr/bin/env bash
# acli-new.sh — create a Jira work item from a Markdown file in one step.
#
# Pipeline: Markdown → md2adf (ADF create payload) → acli create → print new key.
# Collapses the write → tempfile → create → parse-key dance into one command.
#
# Usage:
#   acli-new.sh DESC.md -s "Summary" -p PROJECT -t Type [-l a,b] [-P PARENT-KEY]
#
# Sub-task: add -P/--parent PARENT-KEY and -t Sub-task. All flags after DESC.md
# are forwarded verbatim to md2adf.py.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# md2adf only emits a create payload when -s/-p/-t are present; otherwise a bare
# ADF doc, which can't be created. Build it, then refuse the bare-doc case loudly.
python3 "$SCRIPT_DIR/md2adf.py" "$@" > "$tmp"
if ! python3 -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get('type')!='doc' else 1)" "$tmp"; then
  echo "FATAL: need -s/--summary, -p/--project, -t/--type to create (got a bare ADF doc)" >&2
  exit 1
fi

# Create and surface the new key. pipefail makes an acli error abort the pipe.
acli jira workitem create --from-json "$tmp" --json \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('key','(no key returned)'))"
