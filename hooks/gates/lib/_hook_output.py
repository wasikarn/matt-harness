#!/usr/bin/env python3
# Shared hook-output JSON primitive. Used by hooks/gates/db-write-gate.sh and
# hooks/gates/verifier-protect.sh's embedded python3 -c blocks, both of which
# defined an identical emit_ask() before this extraction (2026-08-15) --
# each gate still builds its own reason message inline (that part is
# legitimately gate-specific), only the JSON-shape emission is shared here.

import json


def emit_ask(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": reason,
        }
    }))
