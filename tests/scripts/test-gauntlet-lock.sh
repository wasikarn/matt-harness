#!/usr/bin/env bash
# test-gauntlet-lock.sh — GH #158: scripts/_lib/gauntlet-lock.sh queues pre-push gauntlets so
# only one runs per machine (timing rows fail when several run at once). Each case runs the
# library in its own `bash -c` process, so every case has its own $$, against a throwaway lock
# dir. Fail-open by design: a wait that outlasts GAUNTLET_LOCK_WAIT_SECS proceeds with a message.
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
LIB="$HERE/../../scripts/_lib/gauntlet-lock.sh"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== gauntlet-lock: one gauntlet per machine (GH #158) ==="

source "$HERE/../_lib/harness.sh"
trap _cleanup_trash EXIT
T=$(mktemp -d "${TMPDIR:-/tmp}/gauntlet-lock.XXXXXX") || exit 1
track_trash "$T"
BG=""
cleanup_bg() { [ -n "$BG" ] && kill $BG 2>/dev/null; return 0; }
trap 'cleanup_bg; _cleanup_trash' EXIT

L="$T/lock"
# run <snippet>: source the library in a fresh process with fast polling and a short wait cap.
run() {
  GAUNTLET_LOCK_DIR="$L" GAUNTLET_LOCK_POLL=0.1 GAUNTLET_LOCK_WAIT_SECS="${WAIT:-1}" \
    bash -c ". '$LIB'; $1" 2>&1
}
reset() { [ -d "$L" ] && { rm -f "$L/pid"; rmdir "$L"; }; return 0; }

# 1. free lock: acquired by this process, removed on release.
out=$(run 'gauntlet_lock_acquire; echo "mine=$$ pid=$(cat "$GAUNTLET_LOCK_DIR/pid")"; gauntlet_lock_release; [ -e "$GAUNTLET_LOCK_DIR" ] && echo STILL-THERE || echo GONE')
mine=$(printf '%s\n' "$out" | sed -n 's/^mine=\([0-9]*\) pid=.*/\1/p')
pidf=$(printf '%s\n' "$out" | sed -n 's/^mine=[0-9]* pid=\([0-9]*\)$/\1/p')
if [ -n "$mine" ] && [ "$mine" = "$pidf" ]; then ok "a free lock is taken and records this process's pid"; else bad "pid file not this process: $out"; fi
if printf '%s' "$out" | /usr/bin/grep -q '^GONE$'; then ok "release removes the lock"; else bad "lock left behind: $out"; fi

# 2. held by a live process: wait out the cap, then fail open with a message and leave the
# holder's lock alone.
sleep 30 & BG=$!
mkdir "$L"; echo "$BG" > "$L/pid"
out=$(WAIT=1 run 'gauntlet_lock_acquire; echo "rc=$?"; gauntlet_lock_release')
if printf '%s' "$out" | /usr/bin/grep -q 'rc=0' && printf '%s' "$out" | /usr/bin/grep -qi 'without the lock'; then
  ok "a wait past the cap proceeds (fail open) and says so"
else bad "no fail-open message: $out"; fi
if [ "$(cat "$L/pid" 2>/dev/null)" = "$BG" ]; then ok "a fail-open run leaves the live holder's lock alone"; else bad "holder's lock was touched: $(cat "$L/pid" 2>/dev/null)"; fi
if printf '%s' "$out" | /usr/bin/grep -q 'waiting'; then ok "the waiter announces that it is waiting"; else bad "no waiting message: $out"; fi

# 3. reentrant: a child of the lock holder (a test that runs the pre-push hook) must not queue.
start=$(date +%s)
out=$(MH_GAUNTLET_LOCK_OWNER="$BG" WAIT=20 run 'gauntlet_lock_acquire; echo "rc=$?"; gauntlet_lock_release')
elapsed=$(( $(date +%s) - start ))
if printf '%s' "$out" | /usr/bin/grep -q 'rc=0' && [ "$elapsed" -lt 10 ] && [ "$(cat "$L/pid")" = "$BG" ]; then
  ok "a child of the holder skips the queue and leaves the lock"
else bad "reentrant acquire waited ${elapsed}s or touched the lock: $out"; fi
kill $BG 2>/dev/null; wait $BG 2>/dev/null; BG=""
reset

# 4. stale lock (owner process is gone): reclaimed at once.
dead=$(bash -c 'echo $$')
mkdir "$L"; echo "$dead" > "$L/pid"
start=$(date +%s)
out=$(WAIT=20 run 'gauntlet_lock_acquire; echo "mine=$$ pid=$(cat "$GAUNTLET_LOCK_DIR/pid")"; gauntlet_lock_release')
elapsed=$(( $(date +%s) - start ))
mine=$(printf '%s\n' "$out" | sed -n 's/^mine=\([0-9]*\) pid=.*/\1/p')
pidf=$(printf '%s\n' "$out" | sed -n 's/^mine=[0-9]* pid=\([0-9]*\)$/\1/p')
if [ -n "$mine" ] && [ "$mine" = "$pidf" ] && [ "$elapsed" -lt 10 ]; then ok "a lock whose owner is gone is reclaimed at once"; else bad "stale lock not reclaimed (${elapsed}s): $out"; fi
reset

# 5. a lock dir with no pid file that is old enough is also reclaimed (a crash between mkdir and write).
mkdir "$L"; touch -t 202601010000 "$L"
out=$(WAIT=20 GAUNTLET_LOCK_NOPID_SECS=60 run 'gauntlet_lock_acquire; echo "rc=$?"; gauntlet_lock_release')
if printf '%s' "$out" | /usr/bin/grep -q 'rc=0' && ! printf '%s' "$out" | /usr/bin/grep -qi 'without the lock'; then ok "an old lock dir with no pid file is reclaimed"; else bad "old pid-less lock not reclaimed: $out"; fi
reset

# 6. queueing: a waiter gets the lock after the holder releases, and says it waited.
bash -c ". '$LIB'; GAUNTLET_LOCK_DIR='$L' gauntlet_lock_acquire; sleep 2; GAUNTLET_LOCK_DIR='$L' gauntlet_lock_release" >/dev/null 2>&1 &
BG=$!
# Start the waiter only once the holder really holds the lock (a loaded machine can be slow to
# start its bash), or the waiter could win the race and never wait.
for _ in $(seq 1 100); do [ -f "$L/pid" ] && break; sleep 0.1; done
out=$(WAIT=30 run 'gauntlet_lock_acquire; echo "mine=$$ pid=$(cat "$GAUNTLET_LOCK_DIR/pid")"; gauntlet_lock_release')
mine=$(printf '%s\n' "$out" | sed -n 's/^mine=\([0-9]*\) pid=.*/\1/p')
pidf=$(printf '%s\n' "$out" | sed -n 's/^mine=[0-9]* pid=\([0-9]*\)$/\1/p')
if [ -n "$mine" ] && [ "$mine" = "$pidf" ] && printf '%s' "$out" | /usr/bin/grep -q 'waiting'; then
  ok "a waiter takes the lock after the holder releases"
else bad "waiter did not get its turn: $out"; fi
wait $BG 2>/dev/null; BG=""
if [ ! -e "$L" ]; then ok "no lock is left after both runs"; else bad "lock left behind after the queue drained"; fi

# 7. a lock dir that cannot be created (read-only parent) fails open at once; it must not
# pretend another gauntlet is running and wait out the whole cap.
RO="$T/ro"; mkdir "$RO"; chmod 555 "$RO"
if [ ! -w "$RO" ]; then
  start=$(date +%s)
  out=$(GAUNTLET_LOCK_DIR="$RO/lock" GAUNTLET_LOCK_POLL=0.1 GAUNTLET_LOCK_WAIT_SECS=30 \
    bash -c ". '$LIB'; gauntlet_lock_acquire; echo \"rc=\$?\"; gauntlet_lock_release" 2>&1)
  elapsed=$(( $(date +%s) - start ))
  if printf '%s' "$out" | /usr/bin/grep -q 'rc=0' && [ "$elapsed" -lt 10 ] \
    && printf '%s' "$out" | /usr/bin/grep -qi 'cannot create' && ! printf '%s' "$out" | /usr/bin/grep -q 'another gauntlet'; then
    ok "an uncreatable lock dir fails open at once and says why"
  else bad "uncreatable lock dir stalled ${elapsed}s or blamed another gauntlet: $out"; fi
else
  echo "  SKIP: read-only parent is still writable (running as root?)"
fi
chmod 755 "$RO"

echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
