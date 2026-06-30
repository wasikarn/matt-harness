#!/usr/bin/env bash
# Gate: block Write/Edit/MultiEdit to the verifier surfaces — hooks/gates/** and
# hooks/hooks.json — so the model cannot neuter the deny-gates that judge it
# (the Kitchen Loop tamper-resistance principle: the agent cannot edit the code
# that judges it). A gate the model can disable is not a computational deny.
#
# Model-safe bypass: KBG_ALLOW_VERIFIER_EDIT=1. The model cannot set the parent
# process env mid-session, so only a developer shell (or settings.json env) can
# bypass — legit harness dev, not runtime escape.
#
# Reads the PreToolUse JSON payload from stdin; exits 2 to block.
set -uo pipefail

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
file_path=$(python3 -c '
import sys, json, os
d = json.load(sys.stdin)
fp = d.get("tool_input", {}).get("file_path", "") or ""

# Developer bypass (model cannot set parent-env mid-session).
if os.environ.get("KBG_ALLOW_VERIFIER_EDIT") == "1":
    sys.exit(0)

# Normalize: strip leading "./" and realpath if it exists, else use as-is.
norm = fp.lstrip()
if norm.startswith("./"):
    norm = norm[2:]
try:
    norm = os.path.realpath(norm)
except Exception:
    pass

# The verifier surfaces the model must not edit at runtime.
hit = False
# hooks/gates/** (the deny-gates themselves)
if "/hooks/gates/" in norm or norm.endswith("/hooks/gates"):
    hit = True
# hooks/hooks.json (the wiring — disabling a hook = neutering the gate)
if norm.endswith("/hooks/hooks.json"):
    hit = True
# Relative-form fallback (path not yet resolved / file does not exist yet)
rel = fp.lstrip()
if rel.startswith("./"):
    rel = rel[2:]
if rel == "hooks/hooks.json" or rel.startswith("hooks/gates/"):
    hit = True

if hit:
    print(fp)
    sys.exit(1)
')

rc=$?

if [[ $rc -eq 1 ]]; then
  echo "[kbg:gate] BLOCKED: editing verifier surface $file_path — the model cannot edit the gates that judge it (tamper-resistance). Set KBG_ALLOW_VERIFIER_EDIT=1 in your shell for legit harness dev." >&2
  exit 2
fi

exit 0