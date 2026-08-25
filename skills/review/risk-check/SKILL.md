---
name: risk-check
description: "Classify a PR's risk as LOW/MEDIUM/HIGH from diff size and sensitive-path signals. Use when scoping review effort. Advisory only — never gates a merge. Don't use for the merge decision (mh:ship-merge)."
argument-hint: "[pr-number|branch]"
model: inherit
effort: low
---

# Risk Check

Read-only. Classifies a PR's risk level from two signals — diff size and
sensitive-path overlap — and reports which one drove the tier. Never gates,
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
# skills/ship-merge/references/scored-gate-guards.md's automation-bias
# guard -- the second surface reusing this exact regex
# (skills/ship-merge/SKILL.md is the canonical source; ship/COMMAND.md's
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

print("PR #%s -- risk: %s" % (d.get("number", "?"), tier))
for r in reasons:
    print("  %s" % r)
print()
print("Thresholds are round defaults (<=50/50 lines LOW, >400 lines or >15 files or any")
print("sensitive path HIGH), not calibrated against this repo history -- no incident data")
print("exists here to calibrate against.")
print()
print("Advisory only -- does not gate or skip anything. See mh:ship-merge for the actual")
print("merge decision, mattpocock-skills:code-review for the actual review.")
' "$PR_JSON" "${MH_PLUGIN_ROOT}/hooks/gates/lib"
```

## Notes

- Deliberately does not wire this tier into any review dispatch/aspect
  routing (would scale reviewer-agent effort by risk — real value, but a
  separate follow-up, not folded into this command).
- Deliberately does not touch `ship-merge.md` at all — no bypass, no
  lightened gate for a LOW tier. That half of the article's design was
  explicitly declined.
- No historical/incident-rate signal — this repo has no data source to
  compute one from; the tier is diff-shape only, not track-record-informed.
