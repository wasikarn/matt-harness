---
name: risk-check
description: "Risk-check: classify a PR LOW/MEDIUM/HIGH from diff size, sensitive-path, and hotspot signals. Use when scoping review effort. Don't use for the merge decision (mh:ship-merge)."
argument-hint: "[pr-number|branch]"
model: inherit
effort: low
---

# Risk Check

Read-only. Classifies a PR's risk level from three signals — diff size,
sensitive-path overlap, and file-hotspot history (how often each touched
file has been committed to before) — and reports which one drove the tier. Never gates,
scores a merge decision, or skips anything: this is the "Risk Analyzer"
half the user explicitly asked for from the Cosmos-article gap analysis,
deliberately without its other half (auto-approval for low-risk changes),
which conflicts with `ship-merge.md`'s automation-bias guard: a self-tiered
risk judgment must not be trusted to bypass anything on its own say-so.

## Resolve the target

Skills get no positional-argument substitution — decide which `gh pr view` form
applies from the user's own words, then run that literal command yourself:
- No target mentioned → current branch's PR: `gh pr view --json number,additions,deletions,changedFiles,files`
- A bare integer `<n>` mentioned → substitute it directly: `gh pr view <n> --json number,additions,deletions,changedFiles,files`
- Anything else → not a PR — this command has no branch-only mode,
  since diff-size/file-list only exist for an actual
  PR's comparison; tell the user to open one first.

## Classify

Run the resolved `gh pr view` command from above, capture its output as `PR_JSON`, then classify it:

```bash
PR_JSON=$(gh pr view --json number,additions,deletions,changedFiles,files)  # or: gh pr view <n> --json ...
# Hotspot inputs -- root-relative to match gh's PR paths. Degrade to empty on
# any failure: the classifier announces the skip, never silently drops the signal.
# ponytail: renamed files restart their commit count (no --follow); add per-file
# --follow only if rename noise ever shows up in practice.
REPO_TOP=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
HIST_FILE=$(mktemp); TRACKED_FILE=$(mktemp)
git -C "$REPO_TOP" log --format= --name-only 2>/dev/null > "$HIST_FILE" || true
git -C "$REPO_TOP" ls-files 2>/dev/null > "$TRACKED_FILE" || true
TOTAL_COMMITS=$(git -C "$REPO_TOP" rev-list --count HEAD 2>/dev/null || echo 0)
python3 -c '
import json, re, sys

sys.path.insert(0, sys.argv[2])
from _protected_paths import is_gate_path

d = json.loads(sys.argv[1])
additions = d.get("additions", 0)
deletions = d.get("deletions", 0)
changed_files = d.get("changedFiles", 0)
total_lines = additions + deletions
paths = [f.get("path", "") for f in d.get("files", [])]

# Sensitive-path definition reused verbatim from
# skills/workflow/ship-merge/references/scored-gate-guards.md's automation-bias
# guard -- the second surface reusing this exact regex
# (skills/workflow/ship-merge/SKILL.md is the canonical source; ship/COMMAND.md's
# Phase-8 failure-mode note points at ship-merge/SKILL.md rather than
# holding its own copy -- confirmed 2026-08-17). Do
# not redefine it here.
# Case-insensitive to match verifier-protect.sh -- CHANGELOG.md already
# documents a real bypass from skipping this fold on macOS/APFS.
KEYWORD_RE = re.compile(r"auth|secret|credential|payment|billing|token", re.IGNORECASE)

# is_gate_path -- imported above from hooks/gates/lib/_protected_paths.py
# (2026-08-15 extraction; this file previously defined its own narrower
# copy missing hooks/advisory/ coverage). Also used by
# hooks/gates/verifier-protect.sh, which is the more complete original.

sensitive_hits = [p for p in paths if KEYWORD_RE.search(p) or is_gate_path(p)]

# Floor-rule style tier -- one bad signal is not averaged away by good
# ones, matching the scored-gate idiom already used in ship-merge.md.
reasons = []
if sensitive_hits:
    tier = "HIGH"
    reasons.append("sensitive path(s): %s" % ", ".join(sensitive_hits))
elif total_lines > 400:
    tier = "HIGH"
    reasons.append("%d changed lines (over the 400-line HIGH threshold)" % total_lines)
elif changed_files > 15:
    tier = "HIGH"
    reasons.append("%d files touched (over the 15-file HIGH threshold)" % changed_files)
elif total_lines <= 50 and changed_files <= 3:
    tier = "LOW"
    reasons.append("%d changed lines across %d file(s) -- under the LOW thresholds (<=50 lines, <=3 files)" % (total_lines, changed_files))
else:
    tier = "MEDIUM"
    reasons.append("%d changed lines across %d file(s) -- above LOW, below HIGH" % (total_lines, changed_files))

# --- Hotspot signal (third signal; probe-calibrated 2026-08-26, see Notes) ---
# Graded/probabilistic, so it escalates ONE step only (LOW->MEDIUM, MEDIUM->HIGH)
# and never jumps straight to HIGH the way the categorical sensitive-path floor
# does. Args are optional: missing/unreadable history data -> announced skip,
# never a silent drop (portability doctrine).
hotspot_note = None
hotspot_hits = []
if len(sys.argv) < 6:
    hotspot_note = "hotspot signal skipped: no history data passed"
else:
    try:
        counts = {}
        for line in open(sys.argv[3]):
            p = line.strip()
            if p:
                counts[p] = counts.get(p, 0) + 1
        tracked = set(l.strip() for l in open(sys.argv[4]) if l.strip())
        total_commits = int(sys.argv[5])
        hist = sorted((counts.get(f, 0) for f in tracked), reverse=True)
        if total_commits < 100:
            hotspot_note = ("hotspot signal skipped: repo has %d commits (<100) -- "
                            "not enough history to rank" % total_commits)
        elif not hist:
            hotspot_note = "hotspot signal skipped: no tracked-file history found"
        else:
            threshold = hist[max(0, int(len(hist) * 0.10) - 1)]
            if threshold <= 2:
                hotspot_note = ("hotspot signal skipped: flat history (top-decile "
                                "threshold %d commits <= 2) -- cannot discriminate" % threshold)
            else:
                for p in paths:
                    c = counts.get(p, 0)
                    if p in tracked and c >= threshold:
                        pct = 100.0 * sum(1 for h in hist if h >= c) / len(hist)
                        hotspot_hits.append((p, c, max(1, round(pct))))
    except Exception as e:
        hotspot_note = "hotspot signal skipped: %s" % e

if hotspot_hits:
    desc_h = ", ".join("%s (%d commits, top %d%% of repo)" % (p, c, pct)
                       for p, c, pct in hotspot_hits)
    if tier == "LOW":
        tier = "MEDIUM"
        reasons.append("hotspot: %s -- bumped LOW->MEDIUM" % desc_h)
    elif tier == "MEDIUM":
        tier = "HIGH"
        reasons.append("hotspot: %s -- bumped MEDIUM->HIGH" % desc_h)
    else:
        reasons.append("hotspot: %s -- already HIGH, no further bump" % desc_h)

print("PR #%s -- risk: %s" % (d.get("number", "?"), tier))
for r in reasons:
    print("  %s" % r)
if hotspot_note:
    print("  %s" % hotspot_note)
print()
print("Line/file thresholds are round defaults (<=50 lines LOW, >400 lines or >15 files or")
print("any sensitive path HIGH), not calibrated against this repo history. The hotspot")
print("decile IS probe-calibrated (2026-08-26, two private repos: top-decile files were")
print("~3-4x more likely than baseline to need future fixes); other deciles untested.")
print()
print("Advisory only -- does not gate or skip anything. See mh:ship-merge for the actual")
print("merge decision, mattpocock-skills:code-review for the actual review.")
' "$PR_JSON" "${MH_PLUGIN_ROOT}/hooks/gates/lib" "$HIST_FILE" "$TRACKED_FILE" "$TOTAL_COMMITS"
```

**Done when:** the printed tier and its reasons are on record — confirm the tier before citing it
anywhere else (e.g. a review-effort scoping note); this skill never gates on its own output.

## Notes

- Deliberately does not wire this tier into any review dispatch/aspect
  routing (would scale reviewer-agent effort by risk — real value, but a
  separate follow-up, not folded into this command).
- Deliberately does not touch `ship-merge.md` at all — no bypass, no
  lightened gate for a LOW tier. That half of the article's design was
  explicitly declined.
- Hotspot signal is probe-calibrated, not folklore: a pre-registered probe
  (2026-08-26, two private work repos — one Python, one TypeScript; details
  in the operator's memory store, not this public repo) measured historical
  commit count as the most consistent cross-repo predictor of future
  fix-touched files (top-2 precision@10% on both fields, ~3-4x lift over
  random), beating churn, past-fix count, recency-weighted fixes, author
  count, and a CRAP-score prototype. The top-10% decile is the probe's
  measured k — other deciles were not tested, hence the disclaimer. It
  escalates one step only because the evidence is probabilistic, unlike
  the categorical sensitive-path floor.
