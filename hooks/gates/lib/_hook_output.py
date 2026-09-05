#!/usr/bin/env python3
# Shared hook-output JSON primitive. Used by the ask-tier gates
# (config-write-guard.sh, test-integrity.sh) via sys.path.insert on
# hooks/gates/lib. Extracted 2026-08-15.
# -- each gate still builds its own reason message inline (that part is
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
