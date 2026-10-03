#!/usr/bin/env python3
"""PostToolUseFailure(Bash) sensor: on a Bash failure, injects a
diagnose-before-retry nudge back into the same turn. Never blocks (always
exit 0) -- this is advisory only, not a gate. GH #153. Registered only on
PostToolUseFailure: a real Bash failure dispatches via that event in this CC
version, not PostToolUse (confirmed live, deep-audit 2026-09-07) -- a
PostToolUse registration would only ever see successful calls (exit_code 0),
so it was dropped rather than kept as an always-no-op.

Capped at 1 nudge per distinct failing command per session (tightened from an
earlier 3-per-signature cap in v1.1.55; this docstring drifted stale until the
2026-09-20 audit caught it) via a small session-scoped counter file -- the
fleet's first stateful hook, deliberately narrow in scope: a local rate-limit
on one advisory nudge, not a cross-agent orchestration layer. Still framed by
METHODOLOGY Rule 13's bounded-retry doctrine ("stop after 3 rounds, the fault
is then in the plan, not the unit") even though the nudge's own cap is
tighter than that number.

Fires on every non-zero exit except a user interrupt (GH #331; no denylist of "worth nudging on" patterns) --
a deliberate first cut, narrowing to specific failure shapes is left for a
follow-up if the noise turns out to matter in practice.
"""
import contextlib
import hashlib
import json
import os
import sys

# The session id names the counter file, so it must pass the shared rule
# (scripts/_lib/hook_payload.py; cost-tracker.sh mirrors it in bash). Loaded by
# this file's own path, never from cwd. A missing or broken lib fails open:
# the nudge still goes out, uncapped, with a diagnostic. No bytecode cache:
# scripts/_lib stays free of __pycache__ (test-hook-payload.sh checks it).
sys.dont_write_bytecode = True
try:
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts", "_lib"))
    from hook_payload import validate_session_id
except Exception as _e:  # noqa: BLE001 -- any load failure must fail open
    validate_session_id = None
    _LIB_ERROR = repr(_e)[:200]

CAP = 1

NUDGE = (
    "<mh-failure-diagnose-nudge>\n"
    "A Bash command just exited non-zero. If you expected that (a red test you just wrote, a "
    "grep with no match), carry on. Otherwise, before retrying: check MEMORY.md and its "
    "sub-indexes for a matching prior gotcha, and find the cause before moving on. If the fix "
    "is a durable, non-obvious lesson, record it with mh:learn or a memory file directly -- "
    "never a separate log/store.\n"
    "</mh-failure-diagnose-nudge>"
)


def is_failure(data):
    # Deep-audit 2026-09-07 (GH #153 fix): a real nonzero Bash exit does NOT
    # dispatch via PostToolUse in this Claude Code version -- confirmed live,
    # in-session, with a debug dump added directly to this file: a genuine
    # `ls <missing-path>` failure produced zero invocations on the
    # PostToolUse(Bash) registration that existed before this fix. It
    # dispatches via PostToolUseFailure instead, whose input schema (confirmed
    # directly in the installed CC binary's own Zod definitions) carries NO
    # tool_response/exit_code at all -- only hook_event_name, tool_name,
    # tool_input, tool_use_id, and error (a string). hooks.json now registers
    # this sensor only on PostToolUseFailure, so its mere presence is the
    # signal -- no exit-code inspection needed or possible for that shape.
    # GH #331: the same event also fires when the user interrupts the command
    # (is_interrupt: true). That is not a failure to diagnose, so skip it.
    return data.get("hook_event_name") == "PostToolUseFailure" and data.get("is_interrupt") is not True


def extract_command(data):
    ti = data.get("tool_input")
    if isinstance(ti, dict):
        cmd = ti.get("command")
        if isinstance(cmd, str):
            return cmd
    return ""


def signature(command):
    return hashlib.sha256(command.strip().encode("utf-8", "replace")).hexdigest()[:16]


def load_counts(state_path):
    try:
        with open(state_path) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save_counts(state_path, counts):
    try:
        os.makedirs(os.path.dirname(state_path), exist_ok=True)
        with open(state_path, "w") as f:
            json.dump(counts, f)
    except OSError:
        pass  # fail-open: losing the counter just means the cap resets, never blocks


@contextlib.contextmanager
def locked(state_path):
    # Deep-audit 2026-09-07: load_counts/save_counts used to run as two
    # separate, uncoordinated file opens -- two Bash calls completing close
    # together (a backgrounded one finishing near a foreground one) could
    # interleave their read-modify-write and lose an increment, letting the
    # per-signature CAP (see module docstring for its current value) under-
    # or over-count. flock on a sibling .lock file
    # (not state_path itself, so a reader never blocks on the writer's own
    # rename/truncate) serializes the whole load+save critical section across
    # processes. Advisory-only feature: a lock that can't be acquired (no
    # fcntl on this platform, or the directory can't be created) fails open
    # to an unlocked in-process default -- losing the lock only risks the
    # same latent miscounting this fix closes, never a block.
    try:
        import fcntl
        os.makedirs(os.path.dirname(state_path), exist_ok=True)
        lock_path = state_path + ".lock"
        fh = open(lock_path, "a+")
    except (OSError, ImportError):
        # ImportError (ModuleNotFoundError is a subclass) covers a platform
        # with no fcntl module at all -- OSError alone let that case crash
        # instead of falling open as this comment already claimed it would
        # (codex-validator round, deep-audit 2026-09-07, reproduced directly).
        yield
        return
    try:
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX)
    except OSError:
        fh.close()
        yield
        return
    try:
        yield
    finally:
        try:
            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
        except OSError:
            pass
        fh.close()


def default_state_path(data):
    # session_id is on every documented hook payload (PreToolUse and
    # PostToolUse examples both carry it) -- prefer it over the env var so
    # the cap stays session-scoped even if CLAUDE_CODE_SESSION_ID is ever
    # unset. An id that fails validate_session_id ("/", "..", NUL, empty, not
    # a string) returns None: no counter file, so the caller nudges uncapped.
    # A "/" and ".." id once wrote outside mh-sensors and a NUL crashed open().
    # Only the Claude Code host builds the payload (UUIDs), so this is hardening.
    raw = data.get("session_id") or os.environ.get("CLAUDE_CODE_SESSION_ID")
    if validate_session_id is None:
        print(f"[mh:sensor] failure-diagnose-nudge: cannot load scripts/_lib/hook_payload.py ({_LIB_ERROR}); "
              "nudging without the per-session cap", file=sys.stderr)
        return None
    session = validate_session_id(raw)
    if not session:
        print(f"[mh:sensor] failure-diagnose-nudge: session_id {repr(raw)[:80]} is not a safe file name; "
              "nudging without the per-session cap", file=sys.stderr)
        return None
    tmpdir = os.environ.get("TMPDIR", "/tmp").rstrip("/")
    return f"{tmpdir}/mh-sensors/failure-nudge-{session}.json"


def main(argv):
    try:
        data = json.load(sys.stdin)
    except (ValueError, TypeError):
        return 0
    if not isinstance(data, dict):
        return 0

    if not is_failure(data):
        return 0

    state_path = argv[1] if len(argv) > 1 else default_state_path(data)
    if state_path is not None:
        sig = signature(extract_command(data))
        with locked(state_path):
            counts = load_counts(state_path)
            seen = counts.get(sig, 0)
            if seen >= CAP:
                return 0  # capped -- stay silent for this exact command, don't spam

            counts[sig] = seen + 1
            save_counts(state_path, counts)

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUseFailure",
            "additionalContext": NUDGE,
        }
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
