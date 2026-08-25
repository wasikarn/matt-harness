#!/usr/bin/env bash
# Gate: ask before CREATING a brand-new Claude Code settings file
# (.claude/settings.json, .claude/settings.local.json -- covers both the
# user-level ~/.claude/ and any project-level .claude/ dir, since both share
# that same basename shape). Editing an EXISTING one is unaffected.
#
# Why the asymmetry: an edit lands on a file a human has already reviewed at
# least once; a brand-new file introduces a whole unreviewed behavior surface
# with no prior review anchor. Same create-vs-modify split as the pre-commit
# new-file LOC gate (git-hooks/pre-commit), applied here at tool-call time via
# a plain existence check instead of at commit time via `git diff --diff-filter=A`.
#
# ASK, not DENY: creating a new settings file is reversible (it can be
# deleted), so this isn't the "irrecoverable set" DENY gates exist for.
#
# #98, deferred-idea backlog filed from spec #75's migration (2026-08-24).
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found -- config-write-guard cannot run; allowing" >&2
  exit 0
fi

python3 -c '
import sys, json, os
sys.path.insert(0, sys.argv[1])
from _hook_output import emit_ask

try:
    d = json.load(sys.stdin)
    ti = d.get("tool_input")
    if not isinstance(ti, dict):
        sys.exit(0)
    fp = ti.get("file_path")
    if not isinstance(fp, str) or not fp:
        sys.exit(0)

    # normpath only -- deliberately NOT realpath. This gate classifies
    # "is something already sitting at this path," and realpath would
    # resolve a dangling symlink to its (missing) target and misreport it
    # as absent. lexists() below is the actual existence check.
    path = os.path.normpath(os.path.expanduser(fp))
    parent, base = os.path.split(path)
    if base not in ("settings.json", "settings.local.json"):
        sys.exit(0)
    if os.path.basename(parent) != ".claude":
        sys.exit(0)

    if os.path.lexists(path):
        sys.exit(0)  # MODIFY of an existing file (or a symlink already there) -- no friction

    emit_ask(
        "config-write-guard: creating a new Claude Code settings file (" + path +
        ") -- a fresh, unreviewed behavior surface. Confirm this is intentional."
    )
except Exception:
    sys.exit(0)
' "$(dirname "$0")/lib"
