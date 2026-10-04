#!/usr/bin/env bash
# gauntlet-lock.sh — a machine-wide queue so only one pre-push gauntlet runs at a time (GH #158).
# The gauntlet's timing rows (finishes inside 4 s / 8 s) fail when several gauntlets, or a gauntlet
# and busy peer sessions, share the machine; waiting for your turn is deterministic where waiting
# for the load to drop is a guess. Source it, then:
#   gauntlet_lock_acquire; trap gauntlet_lock_release EXIT
# The lock is a directory taken with an atomic mkdir, holding the owner's pid. Waiters poll with
# jitter so peers do not all start the moment it frees. A lock whose owner is gone, or that is older
# than GAUNTLET_LOCK_MAX_AGE (pid reuse), is reclaimed with an atomic rename so two waiters cannot
# both reclaim it. A child of the holder (a test that runs the pre-push hook) sees
# MH_GAUNTLET_LOCK_OWNER and skips the queue, so it cannot deadlock the gauntlet that runs it.
# Fail open: a wait past GAUNTLET_LOCK_WAIT_SECS, or an uncreatable lock dir, prints a message and
# runs without the lock. This only orders work; it is never a gate.
# Env: GAUNTLET_LOCK_DIR (default $HOME/.cache/mh/gauntlet.lock), GAUNTLET_LOCK_WAIT_SECS (1800),
# GAUNTLET_LOCK_POLL (5, seconds, stretched by 0-50% jitter), GAUNTLET_LOCK_MAX_AGE (3600),
# GAUNTLET_LOCK_NOPID_SECS (60: how old a pid-less lock dir must be to count as a crash leftover).
# Bash 3.2.

GAUNTLET_LOCK_HELD=0

_gl_dir() { printf '%s' "${GAUNTLET_LOCK_DIR:-$HOME/.cache/mh/gauntlet.lock}"; }

_gl_alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

# Seconds since the lock dir last changed (GNU stat first: BSD stat has no -c).
_gl_age() {
  local m
  m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null) || { echo 0; return 0; }
  echo $(( $(date +%s) - m ))
}

# 0 when the lock at $1 can be reclaimed.
_gl_stale() {
  local d=$1 owner age
  owner=$(cat "$d/pid" 2>/dev/null || true)
  age=$(_gl_age "$d")
  if [ -n "$owner" ]; then
    _gl_alive "$owner" && [ "$age" -lt "${GAUNTLET_LOCK_MAX_AGE:-3600}" ] && return 1
    return 0
  fi
  [ "$age" -ge "${GAUNTLET_LOCK_NOPID_SECS:-60}" ]
}

gauntlet_lock_acquire() {
  local d max poll start owner announced=0
  d=$(_gl_dir)
  max="${GAUNTLET_LOCK_WAIT_SECS:-1800}"
  poll="${GAUNTLET_LOCK_POLL:-5}"

  if [ -n "${MH_GAUNTLET_LOCK_OWNER:-}" ] && _gl_alive "$MH_GAUNTLET_LOCK_OWNER" \
    && [ "$(cat "$d/pid" 2>/dev/null)" = "$MH_GAUNTLET_LOCK_OWNER" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$d")" 2>/dev/null || {
    echo "gauntlet-lock: cannot create $(dirname "$d"); running without the lock" >&2
    return 0
  }

  start=$(date +%s)
  while :; do
    if mkdir "$d" 2>/dev/null; then
      printf '%s\n' "$$" >"$d/pid"
      GAUNTLET_LOCK_HELD=1
      export MH_GAUNTLET_LOCK_OWNER=$$
      return 0
    fi
    if _gl_stale "$d" && mv "$d" "$d.stale.$$" 2>/dev/null; then
      rm -f "$d.stale.$$/pid"
      rmdir "$d.stale.$$" 2>/dev/null
      continue
    fi
    if [ $(( $(date +%s) - start )) -ge "$max" ]; then
      echo "gauntlet-lock: waited ${max}s for the gauntlet lock at $d; running without the lock (timing rows may flake under load, GH #158)" >&2
      return 0
    fi
    if [ "$announced" -eq 0 ]; then
      owner=$(cat "$d/pid" 2>/dev/null || true)
      echo "gauntlet-lock: another gauntlet (pid ${owner:-unknown}) is running; waiting up to ${max}s for my turn" >&2
      announced=1
    fi
    sleep "$(awk -v p="$poll" -v r="$RANDOM" 'BEGIN { printf "%.2f", p * (1 + (r % 50) / 100) }')"
  done
}

gauntlet_lock_release() {
  [ "$GAUNTLET_LOCK_HELD" = 1 ] || return 0
  local d
  d=$(_gl_dir)
  if [ "$(cat "$d/pid" 2>/dev/null)" = "$$" ]; then
    rm -f "$d/pid"
    rmdir "$d" 2>/dev/null
  fi
  GAUNTLET_LOCK_HELD=0
}
