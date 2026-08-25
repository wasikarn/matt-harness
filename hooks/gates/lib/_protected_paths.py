#!/usr/bin/env python3
# Shared gate/verifier-governance path classifier. Ported near-verbatim
# (2026-08-15) from hooks/gates/verifier-protect.sh's own is_verifier_path()
# -- the more complete of two prior copies. skills/risk-check/SKILL.md's
# embedded is_gate_path() was the other, missing hooks/advisory/ coverage;
# both now call this one instead, closing that gap.
#
# Covers: hooks/gates/**, hooks/advisory/**, hooks/hooks.json, the
# non-model audit verifier (skills/harness-audit/scripts/audit.sh +
# checks/**), and (added 2026-08-25, #91 adversarial audit) the PreToolUse
# dispatcher's own table + merge logic (hooks/pretooluse-table.json,
# hooks/dispatch-pretooluse.py, hooks/dispatch-pretooluse.sh) -- T12 moved
# gate routing OUT of the already-protected hooks/hooks.json into these
# three new files, and they inherited none of that protection: a model
# could repoint a gate's script, delete a table row, or rewrite the merge
# logic with zero prompt. Same tamper-resistance surface verifier-protect.sh's
# own header comment names, just wider now that gate wiring itself moved.

import os


def is_gate_path(fp):
    if not fp:
        return False
    norm = fp.lstrip()
    if norm.startswith("./"):
        norm = norm[2:]
    try:
        norm = os.path.realpath(norm)
    except Exception:
        pass
    nl = norm.lower()
    rel = fp.lstrip()
    if rel.startswith("./"):
        rel = rel[2:]
    rl = rel.lower()
    if "/hooks/gates/" in nl or nl.endswith("/hooks/gates"):
        return True
    if "/hooks/advisory/" in nl or nl.endswith("/hooks/advisory"):
        return True
    if nl.endswith("/hooks/hooks.json"):
        return True
    if nl.endswith("/hooks/pretooluse-table.json"):
        return True
    if nl.endswith("/hooks/dispatch-pretooluse.py") or nl.endswith("/hooks/dispatch-pretooluse.sh"):
        return True
    if nl.endswith("/skills/harness-audit/scripts/audit.sh"):
        return True
    if "/skills/harness-audit/scripts/checks/" in nl or \
       nl.endswith("/skills/harness-audit/scripts/checks"):
        return True
    if rl == "hooks/hooks.json" or rl.startswith("hooks/gates/") or \
       rl.startswith("hooks/advisory/"):
        return True
    if rl == "hooks/pretooluse-table.json" or rl == "hooks/dispatch-pretooluse.py" or \
       rl == "hooks/dispatch-pretooluse.sh":
        return True
    if rl == "skills/harness-audit/scripts/audit.sh" or \
       rl.startswith("skills/harness-audit/scripts/checks/") or \
       rl == "skills/harness-audit/scripts/checks":
        return True
    return False
