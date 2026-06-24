#!/bin/bash
# learn-drain-nudge.sh — matcher-less SessionStart advisory hook.
#
# Closes the learn-capture loop: when a backlog of unreviewed learning candidates
# has aged in the out-of-repo queue, inject a ONE-LINE additionalContext nudge to
# run kbg:learn. Without this, passive capture is write-only — rows accumulate and
# are never resurfaced unless you happen to run kbg:learn. (AUDIT FIX #2.)
#
# Self-disabling: instant exit 0 when no queue exists (so it is inert unless
# capture has actually produced candidates — no need to gate on KBG_LEARN_CAPTURE).
# Hash-gated: never re-nags the SAME stale set (modeled on notify-sensor-staleness).
# Informational only — no permissionDecision (autonomy invariant). ALWAYS exit 0.
#
# Knobs: KBG_LEARN_DRAIN_MIN (default 5)  KBG_LEARN_DRAIN_DAYS (default 7)
# Bypass: export CLAUDE_DISABLED_HOOKS=learn-drain-nudge
set -uo pipefail

HOOK_ID="learn-drain-nudge"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0   # honors CLAUDE_DISABLED_HOOKS + PROFILE=off (INPUT unused here)

command -v python3 >/dev/null 2>&1 || exit 0

# Queue dir (CANDIDATE-SCHEMA.md): at SessionStart the transcript may not exist
# yet, so use the fallback slug = ${CLAUDE_PROJECT_DIR:-$PWD} with / -> -.
PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
SLUG=$(printf '%s' "$PROJ" | sed 's|/|-|g')
QUEUE="$HOME/.claude/projects/$SLUG/memory/_candidates/queue.jsonl"
[ -r "$QUEUE" ] || exit 0

STATE="$HOME/.claude/state/kbg-learn-drain-dismissed.json"
MIN="${KBG_LEARN_DRAIN_MIN:-5}"
DAYS="${KBG_LEARN_DRAIN_DAYS:-7}"

CTX=$(
  KBG_LD_QUEUE="$QUEUE" KBG_LD_STATE="$STATE" KBG_LD_MIN="$MIN" KBG_LD_DAYS="$DAYS" \
  python3 - <<'PY' 2>/dev/null
import json, os, hashlib, datetime as dt

QUEUE = os.environ["KBG_LD_QUEUE"]
STATE = os.environ["KBG_LD_STATE"]
MIN = int(os.environ.get("KBG_LD_MIN", "5") or 5)
DAYS = int(os.environ.get("KBG_LD_DAYS", "7") or 7)
today = dt.datetime.now(dt.timezone.utc).date()

def age_days(d):
    try:
        return (today - dt.date.fromisoformat(str(d)[:10])).days
    except (ValueError, TypeError):
        return 0

stale = []
try:
    with open(QUEUE, encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            try:
                r = json.loads(ln)
            except json.JSONDecodeError:
                continue  # tolerate a trailing partial line
            if not isinstance(r, dict):
                continue
            if r.get("status", "open") != "open":
                continue
            if age_days(r.get("first_seen", "")) >= DAYS:
                stale.append(r)
except OSError:
    raise SystemExit(0)

if len(stale) < MIN:
    raise SystemExit(0)

# hash the stale set (sorted kind|evidence) so we never re-nag the same backlog
key = "\n".join(sorted(str(r.get("kind", "")) + "|" + str(r.get("evidence", "")) for r in stale))
cur = "sha256:" + hashlib.sha256(key.encode()).hexdigest()

try:
    with open(STATE, encoding="utf-8") as f:
        if json.load(f).get("hash") == cur:
            raise SystemExit(0)  # already nudged this exact set
except (OSError, ValueError):
    pass

# Emit the nudge FIRST, then record the dismissal — so a crash between the two
# never silences a backlog the user has not actually seen (re-nag is the safe side).
n = len(stale)
import sys
sys.stdout.write(
    f"\U0001f4a1 {n} learning candidate{'s' if n != 1 else ''} (≥{DAYS}d old) await review"
    " — run `kbg:learn` to triage the queue, or ignore to keep them staged.\n")
sys.stdout.flush()

# record the dismissal-by-emit so the same set is not nudged again
try:
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as f:
        json.dump({"hash": cur, "count": len(stale),
                   "at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}, f)
except OSError:
    pass
PY
)

[ -n "$CTX" ] || exit 0

CTX_JSON=$(printf '%s' "$CTX" | jq -cRs . 2>/dev/null)
[ -n "$CTX_JSON" ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$CTX_JSON"
exit 0
