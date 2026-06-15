#!/usr/bin/env python3
# PostToolUse hook: refresh QMD index when tracked collection files change (Write/Edit). Collection roots read from ~/.config/qmd/index.yml; hot-path exit ~25ms for non-trigger ops.
# Author: KOBIG
# Source: https://github.com/kobig/dotfiles (personal)
"""Claude PostToolUse hook: refresh QMD index when any tracked collection
file changes (Write/Edit).

Generic across all collections. Collection roots are read from the live
`~/.config/qmd/index.yml`, so adding a collection needs no hook change.

Hot-path optimized: non-trigger Write/Edit exits in ~25 ms (Python
startup floor). All imports at module top (PEP 8).

Modes:
  (no args)         Claude hook entry. Reads JSON from stdin, checks path
                    against collection roots from index.yml, signals worker,
                    exits 0.
  --trigger [path]  External trigger (git post-merge, fswatch, manual).
                    Signals worker directly — no path filter, no JSON read.
                    Use when caller already knows the change is in-scope.
  --worker          Detached worker. Holds flock; drains pending flag by
                    running `qmd update` and `qmd embed` globally.

Safety:
  - No shell=True. qmd invoked as argv list.
  - flock(LOCK_EX|LOCK_NB) serializes workers; pending flag coalesces bursts.
  - Log rotates when > 1 MiB via collections.deque(maxlen=500) — O(tail) space.
  - Skips on tool_response failure.
"""
from __future__ import annotations

import datetime
import fcntl
import json
import os
import subprocess
import sys
from collections import deque
from functools import lru_cache
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None  # hook is best-effort; skip if PyYAML unavailable

HOME = os.environ.get("HOME") or os.path.expanduser("~")
QMD_CONFIG = Path(HOME) / ".config" / "qmd" / "index.yml"
QMD_STATE_DIR = Path(HOME) / ".cache" / "qmd"

LOG_PATH = QMD_STATE_DIR / "reindex.log"
LOCK_PATH = QMD_STATE_DIR / ".reindex.lock"
PENDING_PATH = QMD_STATE_DIR / ".reindex.pending"

LOG_MAX_BYTES = 1_048_576  # 1 MiB
LOG_TAIL_LINES = 500
WORKER_CYCLE_CAP = 5
CMD_TIMEOUT_SEC = 600


# ---------------------------------------------------------------- hook mode

def _tool_succeeded(payload: dict) -> bool:
    """PostToolUse fires on success; verify defensively."""
    resp = payload.get("tool_response")
    if resp is None or not isinstance(resp, dict):
        return True
    if resp.get("success") is False:
        return False
    if resp.get("error") or resp.get("is_error"):
        return False
    return True


@lru_cache(maxsize=1)
def _collection_roots() -> list[str]:
    """Read collection roots from qmd index.yml. Returns absolute path
    strings with trailing separator — ready for startswith() checks.
    Cached for session lifetime — config file rarely changes mid-session.
    Empty on any error (hook is best-effort)."""
    _yaml = yaml
    if _yaml is None:
        return []
    try:
        with QMD_CONFIG.open("r", encoding="utf-8") as f:
            data = _yaml.safe_load(f) or {}
    except Exception:
        return []
    roots: list[str] = []
    for cfg in (data.get("collections") or {}).values():
        if not isinstance(cfg, dict):
            continue
        path = cfg.get("path")
        if not path:
            continue
        abs_path = os.path.abspath(os.path.expanduser(path))
        roots.append(abs_path.rstrip(os.sep) + os.sep)
    return roots


def _is_trigger(path: str, roots: list[str]) -> bool:
    """Return True if path lives under any collection root.

    Pattern filtering (e.g. `**/*.ts`) is left to qmd itself during
    `qmd update` — hook errs on the side of over-triggering, which is
    cheap because the worker coalesces bursts via a pending flag.
    """
    if not path or not roots:
        return False
    if os.path.isabs(path):
        norm = os.path.normpath(path)
    else:
        norm = os.path.abspath(path)
    return any(norm.startswith(r) for r in roots)


def hook_mode() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    if not _tool_succeeded(payload):
        return 0

    tool_input = payload.get("tool_input") or {}
    path = tool_input.get("file_path") or tool_input.get("path") or ""
    if not path:
        return 0

    roots = _collection_roots()
    if not _is_trigger(str(path), roots):
        return 0

    # Signal pending work (cheap: O_CREAT with no data).
    try:
        QMD_STATE_DIR.mkdir(parents=True, exist_ok=True)
        fd = os.open(PENDING_PATH, os.O_WRONLY | os.O_CREAT, 0o644)
        os.close(fd)
    except OSError:
        return 0

    _spawn_worker(str(path))
    return 0


def _spawn_worker(trigger_path: str) -> None:
    """Fire detached worker process."""
    try:
        subprocess.Popen(
            [sys.executable, os.path.abspath(__file__),
             "--worker", "--trigger", trigger_path],
            cwd=str(QMD_STATE_DIR),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
    except OSError as e:
        _log(f"spawn_worker failed: {e!r}")


# ---------------------------------------------------------- external trigger

def trigger_mode(trigger_path: str | None) -> int:
    """External trigger (git post-merge / fswatch / manual invocation).
    Skips stdin JSON + path filter — caller guarantees the change matters."""
    try:
        QMD_STATE_DIR.mkdir(parents=True, exist_ok=True)
        fd = os.open(PENDING_PATH, os.O_WRONLY | os.O_CREAT, 0o644)
        os.close(fd)
    except OSError:
        return 0
    _spawn_worker(trigger_path or "external")
    return 0


# ---------------------------------------------------------- worker mode

def worker_mode(trigger_path: str | None) -> int:
    """Hold exclusive lock; drain pending flag via qmd update + embed."""
    try:
        QMD_STATE_DIR.mkdir(parents=True, exist_ok=True)
        lock_f = LOCK_PATH.open("w")
    except OSError as e:
        _log(f"worker: cannot open lock: {e!r}")
        return 0
    try:
        try:
            fcntl.flock(lock_f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0  # Another worker has the lock; it will re-check PENDING.

        _log(f"worker: start (trigger={trigger_path or '-'})")
        for cycle in range(1, WORKER_CYCLE_CAP + 1):
            if not PENDING_PATH.exists():
                break
            try:
                PENDING_PATH.unlink()
            except FileNotFoundError:
                pass
            rc_u = _run(["qmd", "update"])
            rc_e = _run(["qmd", "embed"])
            _log(f"worker: cycle {cycle} rc_update={rc_u} rc_embed={rc_e}")
        _rotate_log_if_large()
        _log("worker: done")
    finally:
        try:
            fcntl.flock(lock_f, fcntl.LOCK_UN)
        except OSError:
            pass
        lock_f.close()
    return 0


def _run(argv: list[str]) -> int:
    try:
        proc = subprocess.run(
            argv,
            cwd=str(QMD_STATE_DIR),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=CMD_TIMEOUT_SEC,
            check=False,
        )
        out = (proc.stdout or b"").decode("utf-8", errors="replace").strip()
        if out:
            lines = out.splitlines()
            head = lines[0]
            tail = lines[-1] if len(lines) > 1 else ""
            if tail and tail != head:
                _log(f"{argv[0]} {argv[1]}: {head} … {tail}")
            else:
                _log(f"{argv[0]} {argv[1]}: {head}")
        return proc.returncode
    except FileNotFoundError:
        _log(f"{argv[0]}: command not found")
        return 127
    except subprocess.TimeoutExpired:
        _log(f"{' '.join(argv)}: timeout")
        return 124
    except OSError as e:
        _log(f"{' '.join(argv)}: {e!r}")
        return 1


# ---------------------------------------------------------- logging

def _log(msg: str) -> None:
    """Append a timestamped line."""
    ts = datetime.datetime.now().isoformat(timespec="seconds")
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(f"[{ts}] {msg}\n")
    except OSError:
        pass


def _rotate_log_if_large() -> None:
    """Truncate log to tail LOG_TAIL_LINES when > LOG_MAX_BYTES.

    Complexity:
      time  O(n)         — scan the log once
      space O(tail)      — bounded ring buffer; independent of file size
      amortized O(1)     — rotation fires once per LOG_MAX_BYTES of writes

    Uses collections.deque(maxlen=tail) as a bounded ring buffer so peak
    memory stays flat even if LOG_MAX_BYTES is raised to GB scale.
    """
    try:
        st = LOG_PATH.stat()
    except (FileNotFoundError, OSError):
        return
    if st.st_size <= LOG_MAX_BYTES:
        return
    try:
        tail: deque[str] = deque(maxlen=LOG_TAIL_LINES)
        with LOG_PATH.open("r", encoding="utf-8", errors="replace") as f:
            for line in f:
                tail.append(line)
        ts = datetime.datetime.now().isoformat(timespec="seconds")
        with LOG_PATH.open("w", encoding="utf-8") as f:
            f.write(f"[rotated {ts}]\n")
            f.writelines(tail)
    except OSError:
        pass


# ---------------------------------------------------------- entry

def _parse_trigger_arg(args: list[str]) -> str | None:
    if "--trigger" not in args:
        return None
    i = args.index("--trigger")
    if i + 1 < len(args):
        return args[i + 1]
    return None


def main() -> int:
    args = sys.argv[1:]
    if args and args[0] == "--worker":
        return worker_mode(_parse_trigger_arg(args))
    if args and args[0] == "--trigger":
        return trigger_mode(_parse_trigger_arg(args))
    return hook_mode()


if __name__ == "__main__":
    sys.exit(main())
