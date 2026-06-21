#!/usr/bin/env bash
# read-candidates.sh — shared reader for the learn-capture queue (kept top-level,
# not duplicated, to avoid the sync-seam class audit #37-40 guards).
#
# Reads the out-of-repo candidate queue (CANDIDATE-SCHEMA.md), MERGES rows by
# (kind, normalized evidence) so a learning seen across N sessions accrues
# seen_count=N, computes the ORDERING-only confidence, and prints the open review
# list sorted by confidence desc — one JSON object per line (with an added
# `confidence` float). kbg:learn consumes this at Step 0.
#
# Usage:
#   read-candidates.sh [--transcript <path>]            # list open candidates (JSON/line)
#   read-candidates.sh [--transcript <path>] --archive <key> <status>  # dispose a candidate
#                                                        # key = "<kind>|<normalized-evidence>"
#                                                        # status = promoted | rejected
#
# Confidence is an ORDERING signal ONLY — this script never gates on it. It owns
# cap+rotate (200) here, in the human-gated flow, where a rewrite is kill-safe
# (NOT in the SessionEnd hook). Exit 0 + silent when the queue is absent.
set -uo pipefail

command -v python3 >/dev/null 2>&1 || exit 0

TRANSCRIPT=""
ARCHIVE_KEY=""
ARCHIVE_STATUS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --transcript) TRANSCRIPT="${2:-}"; shift 2 ;;
    --archive)    ARCHIVE_KEY="${2:-}"; ARCHIVE_STATUS="${3:-rejected}"; shift 3 ;;
    *) shift ;;
  esac
done

# Queue dir (CANDIDATE-SCHEMA.md): prefer the transcript's own parent dir so the
# reader agrees with the writer; else fall back to the CWD/project slug.
if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
  QUEUE="$(dirname "$TRANSCRIPT")/memory/_candidates/queue.jsonl"
else
  PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
  SLUG=$(printf '%s' "$PROJ" | sed 's|/|-|g')
  QUEUE="$HOME/.claude/projects/$SLUG/memory/_candidates/queue.jsonl"
fi
[ -r "$QUEUE" ] || exit 0

KBG_RC_QUEUE="$QUEUE" KBG_RC_ARCHIVE_KEY="$ARCHIVE_KEY" KBG_RC_ARCHIVE_STATUS="$ARCHIVE_STATUS" \
python3 - <<'PY'
import json, os, re, datetime as dt

QUEUE = os.environ["KBG_RC_QUEUE"]
AKEY = os.environ.get("KBG_RC_ARCHIVE_KEY", "")
ASTATUS = os.environ.get("KBG_RC_ARCHIVE_STATUS", "rejected") or "rejected"
CAP = 200
today = dt.datetime.now(dt.timezone.utc).date()


def norm(s):
    return re.sub(r"\s+", " ", str(s)).strip().lower()


def rowkey(r):
    return str(r.get("kind", "")) + "|" + norm(r.get("evidence", ""))


def weeks_since(d):
    try:
        days = (today - dt.date.fromisoformat(str(d)[:10])).days
    except (ValueError, TypeError):
        days = 0
    return max(0, days) // 7


def confidence(seen_count, last_seen):
    c = 0.30 + min(0.05 * (seen_count - 1), 0.50) - 0.02 * weeks_since(last_seen)
    return round(max(0.0, min(1.0, c)), 3)


rows = []
try:
    with open(QUEUE, encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            try:
                r = json.loads(ln)
            except json.JSONDecodeError:
                continue  # tolerate a trailing partial line; never abort
            if isinstance(r, dict):
                rows.append(r)
except OSError:
    raise SystemExit(0)

# ── archive mode: mark matching rows, atomic rewrite + cap/rotate ──
if AKEY:
    changed = False
    for r in rows:
        if rowkey(r) == AKEY and r.get("status", "open") == "open":
            r["status"] = ASTATUS
            changed = True
    # cap+rotate: keep ALL open rows (unreviewed candidates are the whole point —
    # never silently drop them); trim disposed rows oldest-first down to the cap.
    if len(rows) > CAP:
        open_rows = [r for r in rows if r.get("status", "open") == "open"]
        disposed = sorted((r for r in rows if r.get("status", "open") != "open"),
                          key=lambda r: str(r.get("ts", "")))
        if len(open_rows) > CAP:
            # pathological: more unreviewed rows than the cap — surface it, don't hide it
            import sys
            sys.stderr.write(
                f"[read-candidates] WARNING: {len(open_rows)} open candidates exceed cap {CAP}; "
                "trimming oldest unreviewed rows — run kbg:learn to drain\n")
            open_rows.sort(key=lambda r: str(r.get("ts", "")))
            rows = open_rows[-CAP:]
        else:
            keep = CAP - len(open_rows)
            rows = open_rows + (disposed[-keep:] if keep > 0 else [])
        changed = True
    if changed:
        tmp = QUEUE + ".tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                for r in rows:
                    f.write(json.dumps(r, separators=(",", ":")) + "\n")
            os.replace(tmp, QUEUE)
        except OSError:
            pass
    raise SystemExit(0)

# ── list mode: merge open rows by (kind, normalized evidence), order by conf ──
merged = {}
for r in rows:
    if r.get("status", "open") != "open":
        continue
    k = rowkey(r)
    m = merged.get(k)
    if m is None:
        merged[k] = {
            "kind": r.get("kind", ""),
            "trigger": r.get("trigger", ""),
            "evidence": r.get("evidence", ""),
            "seen_count": int(r.get("seen_count", 1) or 1),
            "first_seen": str(r.get("first_seen", "")),
            "last_seen": str(r.get("last_seen", "")),
            "key": k,
        }
    else:
        m["seen_count"] += int(r.get("seen_count", 1) or 1)
        m["first_seen"] = min(m["first_seen"] or "9999", str(r.get("first_seen", "")) or "9999")
        m["last_seen"] = max(m["last_seen"], str(r.get("last_seen", "")))

out = []
for m in merged.values():
    m["confidence"] = confidence(m["seen_count"], m["last_seen"])
    out.append(m)
out.sort(key=lambda m: m["confidence"], reverse=True)
for m in out:
    print(json.dumps(m, separators=(",", ":")))
PY
