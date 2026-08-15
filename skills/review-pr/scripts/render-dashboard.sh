#!/usr/bin/env bash
# review-dashboard's default "list every active review" renderer. Extracted
# from commands/review-dashboard.md's embedded python3 -c block (pure move,
# no logic change) -- this was already the single largest embedded script in
# the repo's *.md commands, past the point where this repo's own precedent
# (hooks/gates/lib/_codeowners_match.py) says it should be a real file.
#
# Usage: render-dashboard.sh
#   Reads REVIEW_PR_STATE_DIR (default ~/.claude/state) for review-pr-*.json
#   and review-last.json, same as write-review-state.sh/should-continue-loop.sh.
#
# Stdout: a table of every in-flight review, followed by a single JSON line
# ({"own_branch_state_path": ..., "own_branch_current_head": ...} or {}) --
# see commands/review-dashboard.md's "Default: list every active review"
# section for how the caller consumes that last line.
set -euo pipefail

python3 -c '
import json, glob, os, sys, datetime, subprocess

STATE_DIR = os.environ.get("REVIEW_PR_STATE_DIR") or os.path.join(os.path.expanduser("~"), ".claude", "state")

def load(path):
    # Production data (2026-08-14 census, 105 real files) confirmed ~40 files
    # drift from the schema written today -- a parse failure or a non-dict
    # top level (a hand-edited or ancient-format file) must flag that ONE
    # file, never abort the whole listing.
    try:
        with open(path) as f:
            d = json.load(f)
        if not isinstance(d, dict):
            return None, "top-level JSON is not an object"
        return d, None
    except Exception as e:
        return None, str(e)

def short_sha(s):
    return (s or "?")[:7]

def age(ts):
    if not ts or not isinstance(ts, str):
        return "?"
    try:
        t = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
        secs = (datetime.datetime.now(datetime.timezone.utc) - t).total_seconds()
        if secs < 0: return "0s"  # future/clock-skewed ts -- do not print a negative age
        if secs < 60: return "%ds" % int(secs)
        if secs < 3600: return "%dm" % int(secs / 60)
        if secs < 86400: return "%dh" % int(secs / 3600)
        return "%dd" % int(secs / 86400)
    except Exception:
        return "?"

entries = []  # (path, data_or_None, err_or_None, kind)
for p in sorted(glob.glob(os.path.join(STATE_DIR, "review-pr-*.json"))):
    d, err = load(p)
    entries.append((p, d, err, "pr-by-number"))

last_path = os.path.join(STATE_DIR, "review-last.json")
if os.path.isfile(last_path):
    d, err = load(last_path)
    entries.append((last_path, d, err, "own-branch"))

if not entries:
    print("No review state found under %s -- nothing in flight (or REVIEW_PR_STATE_DIR points elsewhere)." % STATE_DIR)
    sys.exit(0)

readable = [(p, d, k) for p, d, err, k in entries if d is not None]
malformed = [(p, err) for p, d, err, k in entries if d is None]
readable.sort(key=lambda x: x[1].get("ts") or "", reverse=True)

ROW_FMT = "%-22s %-13s %-4s %-9s %-12s %-6s %-8s %s"
hdr = ROW_FMT % ("Target", "Mode", "Rnd", "C/I/M", "State", "Clean", "SHA", "Age")
print(hdr)
print("-" * len(hdr))
own_branch_row = None
for p, d, k in readable:
    if k == "pr-by-number":
        base = os.path.basename(p)
        target = "PR #" + base[len("review-pr-"):-len(".json")]
    else:
        target = d.get("branch") or "(unknown branch)"
        own_branch_row = (p, d)
    cim = "%s/%s/%s" % (d.get("critical_count", "?"), d.get("important_count", "?"), d.get("minor_count", "?"))
    clean_val = d.get("clean")
    clean_str = "yes" if clean_val is True else ("no" if clean_val is False else "?")
    print(ROW_FMT % (
        target, k, str(d.get("round", "?")), cim, str(d.get("convergence_state", "?")),
        clean_str, short_sha(d.get("last_sha")), age(d.get("ts")),
    ))

if malformed:
    print("\n%d file(s) skipped (unreadable/non-conforming):" % len(malformed))
    for p, err in malformed:
        print("  %s: %s" % (p, err))

if any(k == "pr-by-number" for _, _, k in readable):
    print("\nPR-by-number rows: auto-continue N/A (ADR 0009 scopes it to own-branch only).")

if own_branch_row:
    p, d = own_branch_row
    branch = d.get("branch")
    # The state file own last_sha is NOT a valid freshness check against
    # itself -- would always trivially match, defeating the one thing
    # the stale-sha guard in should-continue-loop.sh exists to catch (found
    # in a deep-audit pass, 2026-08-14). Resolve the branch REAL current
    # HEAD instead; best-effort since this command may run from a different
    # repo or an already-deleted branch.
    real_head = None
    if isinstance(branch, str) and branch:
        try:
            r = subprocess.run(["git", "rev-parse", branch], capture_output=True, text=True, timeout=5)
            if r.returncode == 0:
                real_head = r.stdout.strip()
        except Exception:
            pass
    print(json.dumps({"own_branch_state_path": p, "own_branch_current_head": real_head}))
else:
    print("{}")
'
