#!/usr/bin/env python3
# PreToolUse dispatcher merge logic. Invoked by dispatch-pretooluse.sh with
# the tool-call JSON payload on stdin and two argv: the routing table path
# and the repo root (script paths in the table are repo-relative).
#
# Fans out, IN PARALLEL (subprocess.Popen, not sequential), to every table
# entry whose matcher regex matches tool_name -- parallel because Claude
# Code's own native multi-hook PreToolUse dispatch already runs candidates
# concurrently (verified against code.claude.com/docs/en/hooks-guide,
# "Combine results from multiple hooks", 2026-08-25); running the 9 gates
# here sequentially would multiply every python3 cold-start onto the
# critical path of every Bash/Write/Edit call instead of paying it once.
#
# Merge rules, all verified against the same doc page + code.claude.com/docs/en/hooks
# ("Other Exit Codes" / "Critical Warning About Exit Code 1"), not invented:
#   - exit 2              -> deny (the only exit code that blocks on its own).
#   - exit 0              -> parse stdout as JSON; a permissionDecision field
#                            contributes to the merge (deny > defer > ask >
#                            allow, strictest wins); empty/unparseable stdout
#                            is a clean no-decision (implicit allow).
#   - any other exit code -> "non-blocking error" per the docs -- the action
#                            proceeds regardless. Logged to stderr (mirrors
#                            "transcript shows a notice + first line of
#                            stderr"), never promoted to a deny.
#   - updatedInput        -> applies only when the merged decision is NOT
#                            blocking (docs: a blocking decision suppresses
#                            it). Multiple hooks setting it is flagged
#                            "avoid" by the docs and non-deterministic
#                            ("last to finish") under real parallel
#                            execution; here table order is used as the
#                            deterministic tie-break instead, with a warning.
#   - additionalContext   -> concatenated from every hook that set one (docs:
#                            "kept from every hook and passed to Claude
#                            together").
#   - systemMessage       -> a top-level (not hookSpecificOutput-nested)
#                            field some hooks set for direct operator
#                            display (confirmed live: worktree-guard.py's
#                            redirect message). Concatenated the same way
#                            additionalContext is -- dropping it silently
#                            lost the redirect explanation in the first
#                            parity test run against the real gate
#                            (2026-08-25), the exact kind of gap a synthetic
#                            fixture alone would not have caught.
import json
import re
import subprocess
import sys

RANK = {"allow": 0, "ask": 1, "defer": 2, "deny": 3}


def main():
    table_path, root = sys.argv[1], sys.argv[2]
    payload = sys.stdin.read()

    try:
        d = json.loads(payload)
        tool_name = d.get("tool_name", "") if isinstance(d, dict) else ""
    except Exception:
        tool_name = ""

    with open(table_path) as f:
        table = json.load(f)

    matched = [e for e in table if re.fullmatch(e["matcher"], tool_name or "")]
    if not matched:
        return 0

    procs = []
    for entry in matched:
        script = root.rstrip("/") + "/" + entry["script"]
        proc = subprocess.Popen(
            ["bash", script],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        procs.append((entry, proc))

    results = []
    for entry, proc in procs:
        out, err = proc.communicate(input=payload)
        results.append((entry, proc.returncode, out, err))

    worst_rank, worst_reason = -1, None
    deny_messages = []
    additional_ctx = []
    system_messages = []
    updated_input = None
    multi_update_ids = []

    for entry, rc, out, err in results:
        if rc == 2:
            if RANK["deny"] > worst_rank:
                worst_rank = RANK["deny"]
            msg = err.strip()
            if msg:
                deny_messages.append(msg)
            continue

        if rc != 0:
            # Non-blocking error per docs: log it, never treat as a decision.
            msg = err.strip() or f"(exit {rc}, no stderr)"
            print(
                f"[mh:dispatch] {entry['id']} exited {rc} — non-blocking error, proceeding: {msg.splitlines()[0]}",
                file=sys.stderr,
            )
            continue

        out = out.strip()
        if not out:
            continue
        try:
            out_json = json.loads(out)
        except Exception:
            continue
        if isinstance(out_json, dict):
            sm = out_json.get("systemMessage")
            if sm:
                system_messages.append(sm)
        hso = out_json.get("hookSpecificOutput") if isinstance(out_json, dict) else None
        if not isinstance(hso, dict):
            continue

        decision = hso.get("permissionDecision")
        if decision in RANK and RANK[decision] > worst_rank:
            worst_rank = RANK[decision]
            worst_reason = hso.get("permissionDecisionReason")

        ctx = hso.get("additionalContext")
        if ctx:
            additional_ctx.append(ctx)

        ui = hso.get("updatedInput")
        if ui:
            if updated_input is not None:
                multi_update_ids.append(entry["id"])
            updated_input = ui  # table-order: last match wins (deterministic)

    if multi_update_ids:
        print(
            "[mh:dispatch] more than one PreToolUse gate returned updatedInput "
            f"for this call ({', '.join(multi_update_ids)}); applying the last "
            "in table order. Claude Code's own docs caution against more than "
            "one hook modifying the same tool's input.",
            file=sys.stderr,
        )

    if worst_rank == RANK["deny"]:
        for m in deny_messages:
            print(m, file=sys.stderr)
        return 2

    result: dict = {}
    if worst_rank >= RANK["ask"]:
        result = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask" if worst_rank == RANK["ask"] else "defer",
                "permissionDecisionReason": worst_reason or "A gate requested manual approval.",
            }
        }
    elif updated_input is not None:
        result = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": worst_reason or "",
                "updatedInput": updated_input,
            }
        }

    if additional_ctx:
        if result:
            result["hookSpecificOutput"]["additionalContext"] = "\n\n".join(additional_ctx)
        else:
            result = {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "additionalContext": "\n\n".join(additional_ctx),
                }
            }

    if system_messages:
        result = result or {}
        result["systemMessage"] = "\n\n".join(system_messages)

    if result:
        print(json.dumps(result))
    return 0


sys.exit(main())
