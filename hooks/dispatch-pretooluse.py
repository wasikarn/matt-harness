#!/usr/bin/env python3
# PreToolUse dispatcher merge logic. Invoked by dispatch-pretooluse.sh with
# the tool-call JSON payload on stdin and two argv: the routing table path
# and the repo root (script paths in the table are repo-relative).
#
# Fans out, IN PARALLEL (subprocess.Popen, not sequential), to every table
# entry whose matcher regex matches tool_name -- parallel because Claude
# Code's own native multi-hook PreToolUse dispatch already runs candidates
# concurrently (verified against code.claude.com/docs/en/hooks-guide,
# "Combine results from multiple hooks", 2026-08-25); running the matched gates
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
#
# Failure isolation (added 2026-08-25 after an independent adversarial audit
# of #91): this file has no test/deploy step that validates
# pretooluse-table.json's shape before it ships, so it must survive a
# malformed table itself. Two failure classes, two different responses:
#   - the WHOLE table fails to load/parse -> deny this call (fail CLOSED).
#     We're the sole PreToolUse gate; an uncaught exception here used to
#     exit 1 and silently disable all 9 deny gates with just a traceback —
#     an accidental fail-open, not the deliberate announced kind every gate
#     script's own python3-missing guard uses.
#   - ONE table entry is malformed (missing field, bad regex) -> skip that
#     entry, log it, keep evaluating the rest. Denying an unrelated tool
#     call over a different gate's broken row would be disproportionate,
#     and we can't even tell whether the broken entry would have matched.
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

RANK = {"allow": 0, "ask": 1, "defer": 2, "deny": 3}


def _journal(gate_id, tool_name, decision):
    # Gate-verdict journal: append a JSONL row for a non-"allow" verdict only
    # (matches the actual need -- "how often did gate X block/ask" -- and
    # avoids logging on every allow, which at up to 4 matched gates per Bash
    # call would run at several times the write rate of the existing
    # cost-tracker.sh/instructions-loaded-journal.sh telemetry precedents).
    # Non-negotiable: this must NEVER be able to affect the dispatch's own
    # exit code or merged decision. An unwritable/nonexistent journal path
    # (no ~/.local/share/kbg/metrics yet, read-only $HOME, full disk) throws
    # inside the try below and is swallowed -- if it instead propagated,
    # this file's own header (see "any other exit code -> non-blocking
    # error... proceeds regardless") documents the resulting failure mode:
    # a fail-OPEN across all matched gates, not the fail-closed this file
    # otherwise guarantees. Mirrors instructions-loaded-journal.sh's
    # swallow-everything shape (mkdir -p + >> ... 2>/dev/null + unconditional
    # exit 0), translated to Python.
    try:
        log_dir = os.path.join(os.environ.get("HOME", ""), ".local", "share", "kbg", "metrics")
        os.makedirs(log_dir, exist_ok=True)
        row = {
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "id": gate_id,
            "tool_name": tool_name,
            "decision": decision,
        }
        with open(os.path.join(log_dir, "gate-decisions.jsonl"), "a") as f:
            f.write(json.dumps(row) + "\n")
    except Exception:
        pass


def main():
    table_path, root = sys.argv[1], sys.argv[2]
    payload = sys.stdin.read()

    try:
        d = json.loads(payload)
        tool_name = d.get("tool_name", "") if isinstance(d, dict) else ""
    except Exception:
        tool_name = ""

    # Catastrophic failure: the table itself can't even be read/parsed. This
    # dispatcher is now the SOLE PreToolUse gate — if we can't tell what's
    # supposed to run, that's an unverified state, not a clean one. An
    # uncaught exception here used to exit 1 (Claude Code treats any
    # non-2 exit as non-blocking), silently disabling every one of the 9
    # deny gates with nothing but a cryptic traceback (#91 audit finding,
    # 2026-08-25) — an ACCIDENTAL fail-open, unlike every gate's own
    # deliberate, announced python3-missing fail-open. Fail closed instead:
    # deny this one call, loudly, rather than silently drop all coverage.
    try:
        with open(table_path) as f:
            table = json.load(f)
    except Exception as exc:
        print(
            f"[mh:dispatch] FATAL: pretooluse-table.json failed to load ({exc}) — "
            "denying this call rather than silently disabling all PreToolUse gates. "
            "Fix the table file (or its MH_MATT_CACHE-independent repo copy) to restore coverage.",
            file=sys.stderr,
        )
        return 2

    # Per-entry validation: one malformed table row (missing/bad matcher or
    # script field) must not take down evaluation of the other 8 (#91 audit
    # finding — the old single list-comprehension threw on the FIRST bad
    # entry, before any gate ever ran). A malformed entry is logged and
    # skipped for this call, not promoted to a deny — we don't know whether
    # it would even have matched this tool_name, and denying an unrelated
    # tool call over a different gate's broken config would be disproportionate.
    matched = []
    for e in table:
        try:
            matcher, script = e["matcher"], e["script"]
        except Exception as exc:
            print(
                f"[mh:dispatch] table entry {e.get('id', '?')!r} is malformed, skipped: {exc}",
                file=sys.stderr,
            )
            continue
        try:
            is_match = re.fullmatch(matcher, tool_name or "")
        except re.error as exc:
            print(
                f"[mh:dispatch] table entry {e.get('id', '?')!r} has an invalid matcher regex, skipped: {exc}",
                file=sys.stderr,
            )
            continue
        if is_match:
            matched.append(e)
    if not matched:
        return 0

    procs = []
    for entry in matched:
        script = root.rstrip("/") + "/" + entry["script"]
        try:
            proc = subprocess.Popen(
                ["bash", script],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        except OSError as exc:
            print(
                f"[mh:dispatch] {entry.get('id', '?')} failed to launch ({exc}) — "
                "non-blocking error, proceeding without this gate's verdict",
                file=sys.stderr,
            )
            continue
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
            _journal(entry.get("id", "?"), tool_name, "deny")
            continue

        if rc != 0:
            # Non-blocking error per docs: log it, never treat as a decision.
            msg = err.strip() or f"(exit {rc}, no stderr)"
            print(
                f"[mh:dispatch] {entry['id']} exited {rc} — non-blocking error, proceeding: {msg.splitlines()[0]}",
                file=sys.stderr,
            )
            _journal(entry.get("id", "?"), tool_name, "error")
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
        if decision in RANK and decision != "allow":
            _journal(entry.get("id", "?"), tool_name, decision)
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
        # The multi-updatedInput warning belongs HERE, not unconditionally
        # earlier: a deny/ask/defer decision suppresses updatedInput
        # entirely (this branch is only reached when it isn't), so warning
        # about "applying the last in table order" for an input that was
        # actually discarded a moment ago would be misleading (#91
        # adversarial audit, 2026-08-25).
        if multi_update_ids:
            print(
                "[mh:dispatch] more than one PreToolUse gate returned updatedInput "
                f"for this call ({', '.join(multi_update_ids)}); applying the last "
                "in table order. Claude Code's own docs caution against more than "
                "one hook modifying the same tool's input.",
                file=sys.stderr,
            )
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
