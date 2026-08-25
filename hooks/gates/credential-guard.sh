#!/usr/bin/env bash
# Gate: block Read/Grep access to credential-bearing file paths. #96.
# Resolves the target via realpath BEFORE matching, closing the bypass where
# a symlink with an innocuous name (e.g. notes.txt) points at a real
# credential file (e.g. ~/.ssh/id_rsa) -- a naive string match on the
# unresolved path would sail straight through.
#
# Scope: Read + Grep only, and only when the tool targets a specific file
# (Grep's `path` pointing at a directory is skipped -- a broad recursive
# grep incidentally sweeping a credential file into its output is a real
# but separate threat model, needing a post-hoc output scan rather than a
# pre-flight path check; accepted gap, not closed here). Bash-mediated reads
# (cat/less/grep via Bash) are a scoped follow-up, not covered by this gate
# -- extracting a path from an arbitrary shell command has real
# false-negative risk and deserves its own pass, per the issue's own
# research (2026-08-25, #96).
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — credential-path gate cannot run; allowing (install python3 to restore deny coverage)" >&2
  exit 0
fi

python3 -c '
import json, os, sys

try:
    d = json.load(sys.stdin)
except Exception:
    d = None

if not isinstance(d, dict) or not isinstance(d.get("tool_input"), dict):
    sys.exit(0)  # malformed payload: nothing this gate can check, allow

tool_name = d.get("tool_name", "")
ti = d["tool_input"]

path = ti.get("file_path") if tool_name == "Read" else ti.get("path")
if not path or not isinstance(path, str):
    sys.exit(0)

try:
    real = os.path.realpath(path)
except Exception:
    real = path

if os.path.isdir(real):
    sys.exit(0)

base = os.path.basename(real).lower()

if base in (".env.example", ".env.sample"):
    sys.exit(0)

DENY_EXACT = {"id_rsa", "id_ed25519", "id_ecdsa", ".netrc", ".npmrc", ".htpasswd"}
if base in DENY_EXACT or base == ".env" or base.startswith(".env."):
    reason = base
elif base.endswith(".pem") or base.endswith(".key"):
    reason = base
elif "service-account" in base and base.endswith(".json"):
    reason = base
else:
    sys.exit(0)

print(
    "[mh:gate] BLOCKED: " + tool_name + " targets a credential-bearing path (" + reason
    + ") -- resolved via realpath to " + real,
    file=sys.stderr,
)
sys.exit(2)
'
