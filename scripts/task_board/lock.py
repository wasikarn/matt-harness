"""
scripts/_task_board_lock.py — mkdir-based locking (private module).

Owns: lock_acquire, lock_release.
"""

from __future__ import annotations

import json
import shutil
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .io import LOCK_DIRNAME


# ---------------------------------------------------------------------------
# Locking (mkdir protocol — portable POSIX)
# ---------------------------------------------------------------------------

def lock_acquire(plan_dir: str, timeout: int = 10) -> bool:
    """Acquire a mkdir-based lock on plan_dir/.lock

    Parameters
    ----------
    plan_dir: Directory to lock under
    timeout:  Seconds to wait before giving up

    Returns
    -------
    bool: True if lock acquired, False on timeout
    """
    lock_dir = Path(plan_dir) / LOCK_DIRNAME
    waited = 0
    retries = 0
    max_retries = 3
    stale_grace_seconds = 30
    lock_ttl_seconds = 60
    # Each iteration sleeps 0.1s, so timeout*10 iterations ~= timeout seconds
    while True:
        try:
            lock_dir.mkdir(parents=False, exist_ok=False)
            expires_at = (datetime.now(timezone.utc) + timedelta(seconds=lock_ttl_seconds)).isoformat()
            (lock_dir / "lock.json").write_text(
                json.dumps({"expires_at": expires_at}),
                encoding="utf-8",
            )
            return True
        except FileExistsError:
            if retries >= max_retries:
                return False
            now = datetime.now(timezone.utc)
            stale = False
            lock_json = lock_dir / "lock.json"
            if lock_json.exists():
                try:
                    data = json.loads(lock_json.read_text(encoding="utf-8"))
                    expires_at_str = data.get("expires_at")
                    if expires_at_str:
                        expires_at = datetime.fromisoformat(expires_at_str)
                        if now > expires_at:
                            stale = True
                    else:
                        stale = True
                except (json.JSONDecodeError, ValueError, OSError):
                    stale = True
            else:
                # No lock.json — treat as stale after grace period based on mtime
                try:
                    mtime = datetime.fromtimestamp(lock_dir.stat().st_mtime, tz=timezone.utc)
                    if (now - mtime).total_seconds() > stale_grace_seconds:
                        stale = True
                except OSError:
                    stale = True

            if stale:
                try:
                    shutil.rmtree(lock_dir)
                    retries += 1
                    continue
                except OSError:
                    pass

            time.sleep(0.1)
            waited += 1
            if waited >= timeout * 10:
                return False


def lock_release(plan_dir: str) -> None:
    """Release the mkdir-based lock.

    Parameters
    ----------
    plan_dir: Directory whose .lock should be removed
    """
    lock_dir = Path(plan_dir) / LOCK_DIRNAME
    if lock_dir.exists():
        lock_dir.rmdir()
