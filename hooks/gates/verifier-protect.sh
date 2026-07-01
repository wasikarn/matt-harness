#!/usr/bin/env bash
# Gate: prompt the human to approve any Write/Edit/MultiEdit to the verifier
# surfaces — hooks/gates/**, hooks/hooks.json, AND the non-model audit verifier
# (skills/harness-audit/scripts/audit.sh + checks/**) — so the model cannot
# neuter the deny-gates OR weaken the audit checks that judge it without an
# in-session human approval (the tamper-resistance principle: the agent cannot
# edit the code that judges it). A gate/check the model can silently disable is
# not a computational deny — and a half-protected perimeter is worse than none,
# so BOTH deterministic verifiers (the gates AND the audit) are guarded.
#
# Emits a PreToolUse `permissionDecision: ask` JSON (exit 0) so Claude Code
# surfaces a live Approve/Deny prompt to the operator — no env-var bypass, no
# restart. The maker still cannot self-approve; the human decides each edit.
#
# Reads the PreToolUse JSON payload from stdin. Exit 0 + ask JSON on hit
# (JSON honored); exit 0 + no output on miss (clean allow); exit 0 + ask JSON
# on internal error too (fail-safe: an unparseable payload must never resolve
# to a silent allow on a tamper-resistance gate — found 2026-07-01, a bare
# `|| true` around the whole interpreter call was swallowing every Python
# exception, including json.JSONDecodeError on malformed stdin, into a silent
# clean allow).
#
# Path matching is case-INsensitive: macOS/APFS is case-insensitive but
# case-preserving, and os.path.realpath() does not correct a path's casing to
# match the on-disk directory-entry casing — so a case-sensitive substring
# check can be bypassed by writing to a differently-cased path (e.g.
# "hooks/Gates/x.sh") that the filesystem still resolves into the real
# protected directory (found 2026-07-01). Lowercasing both sides only widens
# the match (more prompts, never fewer) so it is safe on case-sensitive
# filesystems too.
set -uo pipefail

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import sys, json, os

def emit_ask(fp, reason=None):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": reason or (
                "Editing a verifier surface (" + fp + ") — the deny-gates or "
                "audit checks that judge the model live here. Tamper-resistance: "
                "the model cannot edit the code that judges it without your "
                "approval."
            ),
        }
    }))

try:
    d = json.load(sys.stdin)
    fp = d.get("tool_input", {}).get("file_path", "") or ""

    # Normalize: strip leading "./" and realpath if it exists, else use as-is.
    norm = fp.lstrip()
    if norm.startswith("./"):
        norm = norm[2:]
    try:
        norm = os.path.realpath(norm)
    except Exception:
        pass
    norm_l = norm.lower()

    # Relative-form fallback (path not yet resolved / file does not exist yet)
    rel = fp.lstrip()
    if rel.startswith("./"):
        rel = rel[2:]
    rel_l = rel.lower()

    # The verifier surfaces the model must not edit without human approval.
    hit = False
    # hooks/gates/** (the deny-gates themselves)
    if "/hooks/gates/" in norm_l or norm_l.endswith("/hooks/gates"):
        hit = True
    # hooks/hooks.json (the wiring — disabling a hook = neutering the gate)
    if norm_l.endswith("/hooks/hooks.json"):
        hit = True
    # skills/harness-audit/scripts/audit.sh + checks/** — the non-model audit
    # verifier (the OTHER deterministic grader). Editing a check to weaken it =
    # the maker grading its own work — the same circularity hooks.json
    # protection stops.
    if norm_l.endswith("/skills/harness-audit/scripts/audit.sh"):
        hit = True
    if "/skills/harness-audit/scripts/checks/" in norm_l or \
       norm_l.endswith("/skills/harness-audit/scripts/checks"):
        hit = True
    if rel_l == "hooks/hooks.json" or rel_l.startswith("hooks/gates/"):
        hit = True
    if rel_l == "skills/harness-audit/scripts/audit.sh" or \
       rel_l.startswith("skills/harness-audit/scripts/checks/") or \
       rel_l == "skills/harness-audit/scripts/checks":
        hit = True

    if hit:
        emit_ask(fp)
except Exception:
    # Cannot confirm this write is safe — fail toward asking, never toward a
    # silent allow.
    emit_ask("<unparsed tool input>", (
        "verifier-protect could not parse this tool call and cannot confirm "
        "it is safe. Fail-safe: approve manually or deny."
    ))
'