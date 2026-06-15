---
name: dismiss-stale
type: command
description: "Dismiss the sensor-staleness notification for 7 days (writes ~/.claude/state/kbg-staleness-dismissed.json with the current stale-set hash). Use when the user says 'dismiss', 'silence the staleness alert', 'mute the sensor warning', or after a SessionStart injection has been acknowledged. The dismissal is hash-gated: a new sensor going stale re-injects immediately. Don't use for: removing sensors (decay-cadence), silencing one specific sensor (edit hooks/sensors.json), or auditing why a sensor is stale (run /harness-audit)."
argument-hint: ""
disable-model-invocation: true
---

# /dismiss-stale — Silence the sensor-staleness notification (7-day TTL)

Write `~/.claude/state/kbg-staleness-dismissed.json` so the SessionStart hook (`hooks/notify-sensor-staleness.sh`) stays quiet for the next 7 days — *only* if the operator is acknowledging the *current* set of stale sensors. The dismissal is hash-gated: if a *new* sensor goes silent, the hash changes and the hook re-injects. This is the operator-only reset for the Q3-triggered `additionalContext` block, not a permanent off-switch.

**Design:** `docs/research/sensor-staleness-notifier-design.md` §4 (Dismissal — Q4 verdict C).
**Symmetric partner:** `hooks/notify-sensor-staleness.sh` (HOOK-1) — the Q3 severity gate logic MUST match.

---

## Why this command exists

Without dismissal, every session the operator is re-paged with the same stale-sensor block. With dismissal, the operator acknowledges "yes, I've seen this; don't pinger me for 7 days" — and the hook respects that, *unless* the stale set changes (a new sensor joins the stale list, or a stale sensor comes back and a different one becomes stale). Hashing the *set of names* (not the count, not the timestamp) is the load-bearing invariant: it surfaces *new* signal but tolerates known noise.

---

## Core invariants (do not break)

- **Operator-only.** `disable-model-invocation: true` is mandatory. The harness never invokes this on the operator's behalf — the autonomy invariant (ADR 0002) forbids the model from self-muting its own coverage alerts.
- **Atomic write.** Plain `>` redirect is forbidden — it leaves a window where the file is truncated but not yet written, and a racing `notify-sensor-staleness.sh` read could see an empty/corrupt dismissal. The write MUST go via `mktemp` + `os.replace` (or `mv -f` after `fsync`). The script below uses Python's `os.replace` so the rename is atomic on POSIX (and `os.fsync` flushes the temp file before the rename).
- **Q3 severity gate must match the hook.** The Q3 trigger is the same set the hook uses to decide "should I inject?" — i.e. the *current* stale set under the same severity rules (1 enforcement stale OR ≥3 advisory stale OR ≥1 must_fire stale). If the Q3 trigger does *not* fire (no stale sensors), the command refuses to write a dismissal — otherwise the operator is dismissing a non-existent problem and the next SessionStart would re-inject immediately, masking the actual reason the Q3 was off.
- **7-day TTL, hard-coded.** `now + 7 days` is the only TTL. Not configurable, per METHODOLOGY Rule 2 (no speculative configurability). An operator who wants a different cadence edits `hooks/notify-sensor-staleness.sh` itself.
- **Hash of sorted stale names.** The set is computed by the same logic the hook uses (load `hooks/sensors.json` + `audit.sh --staleness-only`, apply Q3, sort, sha256 over newline-joined names).

---

## Step 1 — Compute the current stale set (Q3 mirror)

Run the following single `python3` invocation. It mirrors the Q3 severity gate from `hooks/notify-sensor-staleness.sh` (the hook's `enforcement_roles`, `advisory_roles`, `is_stale`, `is_must_fire_stale`, and `triggered` definitions are duplicated verbatim). Output is JSON on stdout:

```bash
cd <repo-root>  # the kbg-harness checkout
python3 - <<'PY'
import datetime as dt, hashlib, json, os, subprocess, sys
import platform

REPO_ROOT = os.getcwd()
SENSORS_JSON = os.path.join(REPO_ROOT, "hooks", "sensors.json")
AUDIT_SH = os.path.join(REPO_ROOT, "skills", "harness-audit", "scripts", "audit.sh")

# ── Q3 mirror (must match hooks/notify-sensor-staleness.sh) ──
enforcement_roles = {"computational-FF", "computational-FB"}
advisory_roles    = {"inferential-FF",   "inferential-FB"}

def is_stale(s, staleness_by_name):
    if not s.get("enabled", True):
        return False
    thr = s.get("max_silent_days")
    if not isinstance(thr, (int, float)):
        return False
    ds = staleness_by_name.get(s["name"], {}).get("days_silent")
    if ds is None:
        return True
    return ds > thr

def is_must_fire_stale(s, staleness_by_name):
    if not s.get("must_fire_in_session", False):
        return False
    if not s.get("enabled", True):
        return False
    ds = staleness_by_name.get(s["name"], {}).get("days_silent")
    return ds is not None and ds >= 1

# Graceful: missing registry / audit.sh = empty result
if not os.path.isfile(SENSORS_JSON) or not os.path.isfile(AUDIT_SH):
    print(json.dumps({"triggered": False, "stale_set": [], "hash": None,
                      "reason": "missing registry or audit.sh"}))
    sys.exit(0)

with open(SENSORS_JSON, encoding="utf-8") as f:
    sensors = json.load(f).get("sensors", [])

try:
    proc = subprocess.run(
        ["bash", AUDIT_SH, "--staleness-only"],
        capture_output=True, text=True, timeout=30,
    )
except (OSError, subprocess.TimeoutExpired):
    print(json.dumps({"triggered": False, "stale_set": [], "hash": None,
                      "reason": "audit.sh invocation failed"}))
    sys.exit(0)

if proc.returncode != 0 or not proc.stdout.strip():
    print(json.dumps({"triggered": False, "stale_set": [], "hash": None,
                      "reason": "audit.sh non-zero exit or empty"}))
    sys.exit(0)

try:
    staleness = json.loads(proc.stdout)
except ValueError:
    print(json.dumps({"triggered": False, "stale_set": [], "hash": None,
                      "reason": "audit.sh non-JSON output"}))
    sys.exit(0)

staleness_by_name = {s.get("name"): s for s in staleness if isinstance(s, dict)}

enforcement_stale = [s for s in sensors
                     if s.get("fallback_role") in enforcement_roles and is_stale(s, staleness_by_name)]
advisory_stale    = [s for s in sensors
                     if s.get("fallback_role") in advisory_roles and is_stale(s, staleness_by_name)]
must_fire_stale   = [s for s in sensors if is_must_fire_stale(s, staleness_by_name)]

triggered = bool(
    len(enforcement_stale) >= 1
    or len(advisory_stale) >= 3
    or len(must_fire_stale) >= 1
)
stale_set = sorted([s["name"] for s in enforcement_stale + advisory_stale + must_fire_stale])
current_hash = "sha256:" + hashlib.sha256("\n".join(stale_set).encode()).hexdigest()

print(json.dumps({
    "triggered": triggered,
    "stale_set": stale_set,
    "hash": current_hash,
    "enforcement_count": len(enforcement_stale),
    "advisory_count": len(advisory_stale),
    "must_fire_count": len(must_fire_stale),
}))
PY
```

Capture the JSON into a variable. The fields you'll use: `triggered` (bool), `stale_set` (list of names), `hash` (string or `null`).

**Why mirror the gate instead of importing it?** — `hooks/notify-sensor-staleness.sh` is a shell script, not a Python module. Importing the gate verbatim into a Python helper would require either (a) parsing the shell script, or (b) refactoring the hook into Python. Both are out of scope. The mirror is small (~15 lines), well-commented, and the brief explicitly identifies Q3-gate-mismatch as a regression risk — so the duplication is intentional and load-bearing. The `// SYNC-WITH: hooks/notify-sensor-staleness.sh:107-121` comment in the script above is the seam.

---

## Step 2 — Refuse to dismiss if Q3 is not triggered

If `triggered == false`:

- Print: `No stale sensors to dismiss.`
- Exit 0.
- Do NOT touch the dismissal file (the existing dismissal, if any, is left in place — an operator can still be in a 7-day window from a prior dismissal).

**Why refuse?** — A dismissal written against an empty stale-set hashes to a fixed value (`sha256:` of the empty string). On the next SessionStart, the Q3 trigger will be off (no stale sensors), the hash check is moot, and the dismissal file becomes a no-op artifact. Worse: if a single sensor goes stale next session, the hash *changes* and the operator gets re-paged immediately — which is the correct behavior, but the operator may interpret "I just dismissed, why is it back?" as a bug. The clean answer is: don't write a dismissal when there's nothing to dismiss.

---

## Step 3 — Compute `dismissed_until` (7-day TTL, platform-aware)

Use BSD `date` on macOS, GNU `date` on Linux. Detect the platform once and dispatch:

```bash
if date -u -v+7d +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
  DISMISSED_UNTIL="$(date -u -v+7d +%Y-%m-%dT%H:%M:%SZ)"
else
  DISMISSED_UNTIL="$(date -u -d '+7 days' +%Y-%m-%dT%H:%M:%SZ)"
fi
```

The output is an ISO-8601 UTC timestamp (e.g. `2026-06-22T14:32:07Z`). The hook's Q4 logic parses this with `datetime.fromisoformat(until.replace("Z", "+00:00"))` and compares against `datetime.now(timezone.utc)`.

**Why 7 days, hard-coded?** — Per METHODOLOGY Rule 2 (no speculative configurability). The TTL is the same one the design doc names. If the operator wants a different cadence, that's a design change, not a config knob.

---

## Step 4 — Atomic write of the dismissal file

**This is the load-bearing step.** A plain `>` redirect to `~/.claude/state/kbg-staleness-dismissed.json` would leave a window where the file is truncated but not yet fully written; a racing read from `notify-sensor-staleness.sh` could see `{}` (invalid JSON, the hook bails to "no dismissal" — which is safe, but it means the dismissal was *silently lost*).

Use `mktemp` + `os.replace` so the rename is atomic on POSIX:

```bash
mkdir -p ~/.claude/state
TMP=$(mktemp ~/.claude/state/kbg-staleness-dismissed.json.XXXXXX)
DISMISS_FILE=~/.claude/state/kbg-staleness-dismissed.json

python3 - "$TMP" "$DISMISS_FILE" "$DISMISSED_UNTIL" "$CURRENT_HASH" <<'PY'
import json, os, sys
tmp_path, final_path, until, hash_value = sys.argv[1:5]
payload = {"dismissed_until": until, "dismissed_set_hash": hash_value}
data = json.dumps(payload, separators=(",", ":")) + "\n"
# Write + fsync the temp file, then atomic-rename over the final path.
# os.replace is atomic on POSIX (and on Windows when both paths are on
# the same filesystem, which they are — both under ~/.claude/state/).
fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
try:
    os.write(fd, data.encode("utf-8"))
    os.fsync(fd)
finally:
    os.close(fd)
os.replace(tmp_path, final_path)
PY
```

**Why Python `os.replace` instead of `mv -f`?** — `mv -f` on macOS/Linux is implemented as `rename(2)` for same-filesystem moves, which is atomic, so functionally equivalent. Python's `os.replace` is used here for two reasons: (1) it makes the atomic-rename intent explicit in code, and (2) it makes the `os.fsync` call natural (Bash `sync` flushes the whole kernel buffer cache; `fsync(2)` flushes just the file's dirty data and metadata, which is what we want). The pattern in `commands/team-cleanup.md:109` ("tempfile + rename") is the same invariant; the only difference is the explicit `fsync` step.

**Mode 0o600.** The dismissal file is *operator* state — there is no reason for it to be world-readable. Mode 0o600 (owner read/write only) is the right default.

---

## Step 5 — Confirm

Print exactly one line:

```
Dismissed <N> sensors until <ISO-8601>
```

where `<N>` is `len(stale_set)` and `<ISO-8601>` is the `dismissed_until` value from Step 3. Example:

```
Dismissed 3 sensors until 2026-06-22T14:32:07Z
```

If `N == 1`, the message is `Dismissed 1 sensor until ...` (no trailing `s`).

Exit 0. The dismissal is now effective on the next SessionStart.

---

## Done-when

- [ ] Stale set computed by Q3 mirror, matches what `hooks/notify-sensor-staleness.sh` would consider stale for the same journal state
- [ ] If Q3 is not triggered: `No stale sensors to dismiss.` printed, no file written, exit 0
- [ ] `dismissed_until` = `now + 7d` in ISO-8601 UTC (Z suffix)
- [ ] `~/.claude/state/kbg-staleness-dismissed.json` written atomically (`mktemp` + `os.fsync` + `os.replace`), mode 0o600
- [ ] Hash in file = `sha256:` + hex of newline-joined sorted stale names
- [ ] Confirmation line printed: `Dismissed <N> sensor(s) until <ISO-8601>`
- [ ] `disable-model-invocation: true` preserved in the command's frontmatter (operator-only)

---

## What this command does NOT do

- Does NOT touch `hooks/sensors.json`. Removing a sensor entirely is a decay-cadence-quarter move, not a dismissal.
- Does NOT extend the TTL of an existing dismissal. A new `/dismiss-stale` overwrites the file (operator-initiated, intentional — the freshest ack wins).
- Does NOT page the operator. The dismissal is a *negative* signal (the operator has acknowledged); the hook re-injects on hash mismatch or TTL expiry.
- Does NOT take arguments. There is no `days:` flag (METHODOLOGY Rule 2: no speculative configurability).

---

## Cross-references

- `hooks/notify-sensor-staleness.sh` — the SessionStart hook this command is the symmetric partner to. The Q3 gate at `hooks/notify-sensor-staleness.sh:107-121` MUST be kept in sync with Step 1.
- `hooks/sensors.json` — the 31-entry registry (Wave 1 deliverable) whose `fallback_role` + `max_silent_days` fields feed the Q3 gate.
- `skills/harness-audit/scripts/audit.sh --staleness-only` — the AUDIT-1 deliverable whose output drives both the hook and this command's stale-set computation.
- `docs/research/sensor-staleness-notifier-design.md` §4 — the design doc this command implements.
- `.claude/tasks/sensor-fire-notification.md` CMD-1 — the plan row that authorizes this work.
