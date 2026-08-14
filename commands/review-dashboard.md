---
name: review-dashboard
description: "List every in-flight PR review's status in one table, or drill into one PR/branch. Don't use for merge decisions (/ship-merge) or running a review (kbg:review-pr)."
argument-hint: "[pr-number|branch]"
---

# Review Dashboard

Aggregates `kbg:review-pr`'s own state files into one view. Read-only — never
writes, never scores a merge decision, never triggers a review. Every field
shown is a raw read of what `skills/review-pr/scripts/write-review-state.sh`
already wrote; this command adds no new tracking.

**Why this exists**: nothing else in this codebase globs
`review-pr-*.json` — `ship-merge.md`, `address-review/COMMAND.md`, and
`should-continue-loop.sh` all resolve one already-known PR#/branch. This is
the first surface that lists what's actually in flight.

## Default: list every active review

Uses `%`-style string formatting throughout, not f-strings — matching
`write-review-state.sh`/`should-continue-loop.sh`'s own convention, and
deliberately: an f-string expression containing a backslash-escaped quote
(needed here for dict-key lookups inside the format string) is a hard
`SyntaxError` on Python < 3.12, and `/usr/bin/python3` (Apple's system
stub) still ships pre-3.12 on plenty of real machines.

```bash
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
```

**If the printed object has a non-null `own_branch_state_path` key** (an
own-branch review exists — `{}` alone means it doesn't, that's still valid
JSON so check the key, not just "is it an object"), and `own_branch_current_head`
is **not** null, run `should-continue-loop.sh` against that real current
HEAD to show the *authoritative* auto-continue verdict — reuse the real
decision script, don't re-derive `convergence_state`/`force_human` logic
here (the exact sync-seam ADR 0009's implementation was about closing):

```bash
bash skills/review-pr/scripts/should-continue-loop.sh "<own_branch_current_head from the JSON above>" ""
```

**Never pass the state file's own `last_sha`** as the expected sha here —
that was the tautological bug above. Render the script's two-line output as
`Auto-continue verdict: continue` or `Auto-continue verdict: stop
(reason=<token>)`. **If `own_branch_current_head` is null** (branch
unresolvable from this working directory — deleted, or you're not in the
right repo), print `Auto-continue verdict: unavailable — can't resolve
<branch>'s current HEAD from here` instead of guessing.

**Do not compute a `ship-merge`-style score anywhere in this command.** For
Critical findings, print the raw count with a one-line pointer only —
`Critical findings: 0 (ship-merge weights this 30/100 — see /kbg:ship-merge
for the actual merge decision)` — never a computed pass/fail of your own.

## Drill-down: `/review-dashboard <pr-number-or-branch>`

1. **Resolve the target** — same pattern as `address-review/COMMAND.md`'s
   Phase 1 step 1:
   - No argument → `gh pr view --json number,headRefOid,headRefName,url` (current branch's PR)
   - A bare integer `<n>` → `gh pr view <n> --json number,headRefOid,headRefName,url`
   - Anything else → treat as a branch name; there is no PR to resolve, read
     `review-last.json` directly and check its `branch` field matches.
2. **Read the one relevant state file** — PR-keyed
   (`review-pr-<n>.json`) if a PR number resolved, else `review-last.json`
   (same fallback order `ship-merge.md` Phase 1 already documents).
3. **Render every field**, human-labeled: `review_mode`, `round`,
   Critical/Important/Minor counts + `prev_*` deltas, `convergence_state`,
   `clean`, `rehunt`, `last_sha` (full), `branch`, `ts` (with computed age),
   `stalled`, `regressed`, `force_human`, `finding_files` (if non-empty),
   `file_streaks`/`churn_files` (if non-empty). Same "point at ship-merge,
   don't score" rule as the list view for anything ship-merge's gate weighs.
4. **Get the real current HEAD to check freshness against** — prefer step 1's
   `headRefOid` if a PR was resolved; otherwise (branch-name target) run
   `git rev-parse <branch>` (best-effort — the branch may be deleted, or this
   command may run from a different repo). **Never use the state file's own
   `last_sha` as the freshness reference** — it would always trivially match
   itself, defeating the one check `should-continue-loop.sh`'s `stale-sha`
   guard exists to run (tautology bug found in a deep-audit pass, 2026-08-14).
   - **If the state file's `last_sha` doesn't match this real current HEAD**,
     say so explicitly — `⚠ state is stale: last reviewed <sha>, current HEAD
     is now <sha>` — this command never re-runs a review to refresh it;
     that's `kbg:review-pr`'s job.
   - **If the real current HEAD couldn't be resolved at all**, say so —
     `⚠ can't verify freshness — <branch>'s current HEAD isn't resolvable
     from here` — and skip step 5 rather than guessing.
5. **If `review_mode == "own-branch"` and step 4 resolved a real current
   HEAD**, run `should-continue-loop.sh "<real current HEAD>" ""` and render
   its verdict the same way the list view does.

## Notes

- `review-last.json` is a single shared slot keyed by branch name (not a
  history) — reviewing branch A, then B, then A again shows only A's *second*
  pass. This command surfaces the `branch` field so that's visible, not
  hidden.
- Rejection-rate trend / ledger health (`skills/review-pr/ledger.md`,
  `policy.md`) is a different axis (session-level fleet health, not
  per-review status) and already surfaces in `review-pr`'s own Phase 6 —
  intentionally not duplicated here.
- The `.scratch/<slug>/proofs/` evidence directory `review-pr/SKILL.md`
  specifies is never actually instantiated in real usage (confirmed against
  every session directory on disk) — this command doesn't render an
  always-empty evidence section for it.
