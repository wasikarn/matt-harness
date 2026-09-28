#!/usr/bin/env python3
# Gate-verdict journal, restored (2026-09-12) after commit 2cac98c8 deleted the
# central-dispatcher version (hooks/dispatch-pretooluse.py) without a replacement.
# Every gate imports this defensively -- see each gate's own `try: from _journal
# import journal / except Exception: def journal(*a, **k): pass` -- never a bare
# import, since irrecoverable.py's wrapper turns any non-{0,2} exit into a hard
# deny (irrecoverable.sh:36-39): an ImportError here must never become a
# machine-wide Bash lockout.
import json, os


def journal(gate_id, tool_name, decision, session_id=None):
    # Non-allow verdicts only ("ask"/"deny", plus secret-scan.py's own
    # "allow-suppressed" for a same-line-marker-suppressed match) -- matches
    # the actual need ("how often did gate X block/ask") and avoids the
    # write-rate of logging every allow. Must NEVER affect the calling
    # gate's own exit code or verdict: every failure mode below is
    # swallowed silently.
    try:
        override = os.environ.get("MH_GATE_JOURNAL_PATH")  # test-layer override,
        if override:                                        # same naming precedent
            path = override                                 # as cost-report's
        else:                                                # MH_COSTS_FILE
            home = os.environ.get("HOME")
            if not home or not os.path.isabs(home):
                # Unset/relative HOME must never resolve into the current
                # working directory -- this exact bug once wrote
                # gate-decisions.jsonl into this repo's own tree (2026-08-28;
                # see .gitignore's ".local/" comment and CHANGELOG.md).
                return
            path = os.path.join(home, ".local", "share", "kbg", "metrics", "gate-decisions.jsonl")
        log_dir = os.path.dirname(path)
        os.makedirs(log_dir, exist_ok=True)
        if os.path.islink(path):
            # Refuse to append through a symlink -- same hardening
            # cost-tracker.sh applies to costs.jsonl.
            return
        from datetime import datetime, timezone  # lazy: irrecoverable.py runs
        row = {                                   # on every Bash call and its
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),  # .sh
            "id": gate_id,                                                    # wrapper
            "tool_name": tool_name,                                          # exists to
            "decision": decision,                                            # dodge
            "session_id": session_id,                                        # cold-start
        }
        with open(path, "a") as f:
            f.write(json.dumps(row) + "\n")
    except Exception:
        pass
