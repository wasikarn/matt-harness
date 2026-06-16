#!/usr/bin/env bash
# notify-sensor-staleness.sh — matcher-less SessionStart hook
#
# Q3 severity gate: inject additionalContext when ANY enforcement sensor
# (computational-FF/FB) is stale, OR >=3 advisory sensors (inferential-FF/FB)
# are stale, OR any must_fire_in_session sensor is stale.
#
# Q4 hash-gated dismissal: re-inject when the current stale-set hash differs
# from the dismissed hash in $HOME/.claude/state/kbg-staleness-dismissed.json,
# OR the dismissal has expired (dismissed_until is in the past).
#
# Informational only — no permissionDecision (autonomy invariant). The hook
# ALWAYS exits 0. Graceful degradation: missing sensors.json, missing
# audit.sh, or missing python3/jq = silent no-op.
#
# Design: docs/research/sensor-staleness-notifier-design.md §3+§4
# Plan: .claude/tasks/sensor-fire-notification.md HOOK-1
set -uo pipefail

# ── Paths (BASH_SOURCE-stable) ────────────────────────────────────────
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENSORS_JSON="$HOOK_DIR/../sensors.json"
AUDIT_SH="$HOOK_DIR/../../skills/harness-audit/scripts/audit.sh"
DISMISS_FILE="$HOME/.claude/state/kbg-staleness-dismissed.json"
JOURNAL="${CLAUDE_JOURNAL_PATH:-$HOME/.claude/governance-events.jsonl}"

# ── Graceful degradation (silent no-op on missing deps) ─────────────
command -v python3 >/dev/null 2>&1 || exit 0
command -v jq      >/dev/null 2>&1 || exit 0
[ -r "$SENSORS_JSON" ] || exit 0
[ -r "$AUDIT_SH" ]     || exit 0

# ── Compute Q3 + Q4 logic in a single python call. ───────────────────
# (Bash + jq could do it, but the staleness-set classification + hash +
# dismissal-TTL + block format is ~50 lines of bash. One python call is
# clearer and harder to get wrong.)
read -r result < <(
  CLAUDE_JOURNAL_PATH="$JOURNAL" \
  python3 - "$SENSORS_JSON" "$AUDIT_SH" "$DISMISS_FILE" <<'PY' 2>/dev/null
import datetime as dt, hashlib, json, os, subprocess, sys

sensors_path, audit_sh, dismiss_path = sys.argv[1:4]
now = dt.datetime.now(dt.timezone.utc)

# ── Load registry (graceful: missing/malformed = silent no-op) ──
try:
    with open(sensors_path, encoding="utf-8") as f:
        reg = json.load(f)
except (OSError, ValueError):
    print("{}")
    sys.exit(0)
sensors = reg.get("sensors", [])
if not isinstance(sensors, list):
    print("{}")
    sys.exit(0)

# ── Get staleness data from audit.sh --staleness-only ─────────
try:
    proc = subprocess.run(
        ["bash", audit_sh, "--staleness-only"],
        capture_output=True, text=True, timeout=30,
        env={**os.environ,
             "CLAUDE_JOURNAL_PATH": os.environ.get("CLAUDE_JOURNAL_PATH", "")},
    )
except (OSError, subprocess.TimeoutExpired):
    print("{}")
    sys.exit(0)
if proc.returncode != 0 or not proc.stdout.strip():
    print("{}")
    sys.exit(0)
try:
    staleness = json.loads(proc.stdout)
except ValueError:
    print("{}")
    sys.exit(0)
staleness_by_name = {s.get("name"): s for s in staleness if isinstance(s, dict)}

# ── Classify sensors ──────────────────────────────────────────
def days_silent_of(s):
    return staleness_by_name.get(s["name"], {}).get("days_silent")

def is_stale(s):
    """Standard staleness: enabled + days_silent > max_silent_days.
    null days_silent (never fired) is treated as stale per Böckeler L553 —
    the absence of a sensor firing is a coverage gap, not a quality signal."""
    if not s.get("enabled", True):
        return False
    thr = s.get("max_silent_days")
    if not isinstance(thr, (int, float)):
        return False
    ds = days_silent_of(s)
    if ds is None:
        return True
    return ds > thr

def is_must_fire_stale(s):
    """must_fire_in_session: stale if enabled + days_silent >= 1.
    (v1 registry has no such entries per design §9, but the field is in
    the schema; this branch keeps it load-bearing for future operators.)"""
    if not s.get("must_fire_in_session", False):
        return False
    if not s.get("enabled", True):
        return False
    ds = days_silent_of(s)
    return ds is not None and ds >= 1

enforcement_roles = {"computational-FF", "computational-FB"}
advisory_roles    = {"inferential-FF",   "inferential-FB"}

enforcement_stale = [s for s in sensors
                     if s.get("fallback_role") in enforcement_roles and is_stale(s)]
advisory_stale = [s for s in sensors
                  if s.get("fallback_role") in advisory_roles and is_stale(s)]
must_fire_stale = [s for s in sensors if is_must_fire_stale(s)]

# ── Q3 trigger ───────────────────────────────────────────────
triggered = bool(
    len(enforcement_stale) >= 1
    or len(advisory_stale) >= 3
    or len(must_fire_stale) >= 1
)

# ── Q4 hash-gated dismissal ──────────────────────────────────
stale_set = sorted([s["name"] for s in enforcement_stale + advisory_stale + must_fire_stale])
current_hash = "sha256:" + hashlib.sha256("\n".join(stale_set).encode()).hexdigest()

dismissed = False
if triggered and os.path.isfile(dismiss_path):
    try:
        with open(dismiss_path, encoding="utf-8") as f:
            d = json.load(f)
        until = d.get("dismissed_until")
        dhash = d.get("dismissed_set_hash")
        if dhash == current_hash and isinstance(until, str):
            try:
                until_dt = dt.datetime.fromisoformat(until.replace("Z", "+00:00"))
                if until_dt > now:
                    dismissed = True
                    triggered = False
            except ValueError:
                pass
    except (OSError, ValueError):
        pass

# ── Compose additionalContext block ──────────────────────────
if triggered:
    def fmt(s):
        ds = days_silent_of(s)
        thr = s.get("max_silent_days")
        ds_str = "never" if ds is None else f"{ds}d"
        return f"{s['name']} (silent {ds_str}, threshold {thr}d)"
    parts = []
    if enforcement_stale:
        parts.append("[enforcement] " + ", ".join(fmt(s) for s in enforcement_stale))
    if advisory_stale:
        parts.append("[advisory] " + ", ".join(fmt(s) for s in advisory_stale))
    if must_fire_stale:
        parts.append("[must-fire] " + ", ".join(fmt(s) for s in must_fire_stale))
    n = len(enforcement_stale) + len(advisory_stale) + len(must_fire_stale)
    block = (
        f"**{n} sensor{'s' if n != 1 else ''} haven't fired:**\n"
        + "\n".join(f"- {p}" for p in parts)
        + "\nDismiss: /dismiss-stale | Audit: bash skills/harness-audit/scripts/audit.sh ."
    )
else:
    block = ""

print(json.dumps({
    "triggered": triggered,
    "dismissed": dismissed,
    "enforcement_count": len(enforcement_stale),
    "advisory_count": len(advisory_stale),
    "must_fire_count": len(must_fire_stale),
    "stale_set_hash": current_hash,
    "additional_context": block,
}, separators=(",", ":")))
PY
)

# ── Parse the python output; bail if not triggered ──────────────
triggered=$(printf '%s' "$result" | jq -r '.triggered // false' 2>/dev/null)
[ "$triggered" = "true" ] || exit 0

ctx=$(printf '%s' "$result" | jq -r '.additional_context // ""' 2>/dev/null)
[ -n "$ctx" ] || exit 0

# JSON-encode for embedding in the hook output envelope
ctx_json=$(printf '%s' "$ctx" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null)
[ -n "$ctx_json" ] || exit 0

# ── Journal the fire (best-effort; silent on failure) ────────────
# Inline shape mirrors journal_append in _lib.sh (id/ts/session/hook/event/fields).
# This hook is matcher-less SessionStart and does not need hook_init's
# PreToolUse parsing helpers, so the journal is built directly to avoid
# dragging in _lib.sh.
fields=$(printf '%s' "$result" | jq -c '{
  triggered: true,
  enforcement_count: (.enforcement_count // 0),
  advisory_count: (.advisory_count // 0),
  must_fire_count: (.must_fire_count // 0),
  hash_match: (.dismissed // false),
  stale_set_hash: (.stale_set_hash // "")
}' 2>/dev/null)

CLAUDE_SESSION_ID="${CLAUDE_SESSION_ID:-no-sid}" \
CLAUDE_JOURNAL_PATH="$JOURNAL" \
python3 - "$fields" <<'PY' 2>/dev/null
import datetime as d, json, os, sys, uuid
fields_json = sys.argv[1]
journal = os.environ.get("CLAUDE_JOURNAL_PATH") or os.path.expanduser("~/.claude/governance-events.jsonl")
try:
    os.makedirs(os.path.dirname(journal), exist_ok=True)
except OSError:
    pass
try:
    fields = json.loads(fields_json)
except ValueError:
    fields = {}
ts = d.datetime.now(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
rid = uuid.uuid4().hex[:8]
envelope = {
    "id": f"{int(d.datetime.now().timestamp()*1000)}-notify-sensor-staleness-{rid}",
    "ts": ts,
    "session": os.environ.get("CLAUDE_SESSION_ID", "no-sid"),
    "hook": "notify-sensor-staleness",
    "event": "notify-sensor-staleness",
    "source": "journal_append",
    "fields": fields,
}
with open(journal, "a", encoding="utf-8") as f:
    f.write(json.dumps(envelope, separators=(",", ":")) + "\n")
PY

# ── Emit the additionalContext block ────────────────────────────
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$ctx_json"
