---
slug: inferential-structural-judge-escalation-mirror
priority: P3
source: .claude/tasks/inferential-structural-test.md (deferred from the design doc §3 "operational meaning" table)
status: planned (deferred follow-up)
target: kbg-harness 0.3.x (after the 0.2.x inferential-structural-test build lands + ≥ 1 month of real session data accumulates)
created: 2026-06-15
related: docs/research/inferential-structural-judge-design.md §3 (operational meaning, score ≥ 7 row), .claude/tasks/inferential-structural-test.md
---

# Plan: SessionStart inference-mirror for inferential-structural-judge escalations

## Why this is a separate plan, not a wave in the parent

The parent `inferential-structural-test` plan documents the escalation channel in design doc §3's "operational meaning" table: when `score ≥ 7`, the verdict "is mirrored to the next SessionStart's `additionalContext` block, so the next session's first prompt carries 'the previous session escalated on X.'"

**The parent plan's SessionEnd hook only journals; it does not perform the mirror.** The mirror is a SessionStart-time read of the most-recent high-score verdict event + a write into the `additionalContext` of the next session's `SessionStart` hook output.

This plan ships that mirror mechanism. It is its own plan because:

1. **Bidirectional lifecycle.** The mirror is a SessionStart hook, not SessionEnd; it reads *across* sessions. A new file in `hooks/` + a new entry in `hooks/hooks.json` + a new sensor entry in `hooks/sensors.json` — all of which deserve the parent plan's full validation chain.
2. **Sister plan dependency.** The mirror depends on a stable verdict-event shape (per the parent plan's design doc §3), so it cannot land before 0.2.x ships.
3. **Volume of data.** A meaningful mirror needs ≥ 1 real session with a `score ≥ 7` verdict to test against; the parent plan's fixtures are synthetic and would mask the real-mirror semantics (drift, recency-window, multi-session chains).

## Brain dump

The mirror hook reads the most recent `inferential_structural_verdict` event from `~/.claude/governance-events.jsonl` where `fields.score >= 7`, then injects a markdown block into the next SessionStart's `additionalContext`:

```markdown
## ⚠️ Prior session escalated (inferential-structural-judge)

**Date:** 2026-XX-XXTHH:MM:SSZ
**Score:** 9/10
**Top finding:** <fields.top_finding>
**Recommendation:** escalate
**Dimensions:** {over_engineering: 4, arch_drift: 5, test_pattern: 3, doctrine_conformance: 5}

This is an advisory read from the previous session. Use it as input to your own judgment, not as a directive.
```

The hook is **informational only** — it never emits `permissionDecision` (autonomy invariant) and never mutates the journal. It is a *read-then-format-then-inject* sensor, like `doctrine-bootstrap.sh` (which injects doctrine) and `notify-sensor-staleness.sh` (which injects staleness notices).

## Q&A log

1. **Why SessionStart and not the next SessionEnd?** — SessionEnd can only observe *its own* session's events. The escalation needs to be *visible to the next session's planning* — that means it has to be present at the start of the next session, not discovered at the end.
2. **Why not just use the existing `notify-sensor-staleness.sh`?** — That hook is about *staleness* (sensors not firing), not about *high-severity verdicts firing*. The escalation-mirror is a different signal — it answers "what did the previous session's structural judge think?" — and belongs in a separate hook so the staleness-notifier stays simple.
3. **How recent is "the most recent" verdict?** — Last 7 days. If the most recent score-≥-7 verdict is older than 7 days, the hook emits nothing. This prevents stale escalations from haunting a session that's moved on. The 7-day window is configurable in the sensor's `escalation_recency_days` field.
4. **What if the previous session's verdict is contested by a more recent lower verdict?** — The hook reads *only* the most recent score-≥-7 verdict, even if a more recent lower verdict followed it. This is the "highest-severity signal wins" semantics; the alternative (most-recent-verdict-wins regardless of severity) was considered and rejected as it would let a session "talk down" its own escalation. (This is a model-driven failure mode the autonomy invariant warns about.)
5. **What's the cost?** — ~50 tokens per SessionStart (one journal read, one markdown block). Negligible vs the ~30k/session budget per METHODOLOGY Rule 6.
6. **What about cross-session chains?** — If session A escalates, session B mirrors it, session C (which starts after B) does *not* see A's escalation unless C's start time is within 7 days of A. The mirror is one-hop, not transitive. This is the "escalation is a local property" semantic.
7. **What's the rollback?** — Remove the SessionStart entry from `hooks/hooks.json` + delete the hook script. Two-line revert. The 204-test critical-hooks suite verifies the absence is not a fail.
8. **How does this interact with `kbg:review-pr`?** — The mirror is automatic (per-session, shallow). `kbg:review-pr` is manual (per-PR, deep). They are complements, not substitutes — same as the parent plan's Q7 answer.

## Team Members

| Name | Role | Agent Type |
|------|------|------------|
| LEAD-D | Hook design + recency-window semantics + cross-session chain spec | code-architect |
| LEAD-B | Hook script + hooks.json entry + sensors.json entry + test fixture | backend-engineer |
| V | Critical-hooks test + audit + journal-recency verification | code-reviewer |

## Step by Step Tasks

| Task ID | Description | Depends On | Assigned To | Files | Criteria | Constraints |
|---------|-------------|------------|-------------|-------|----------|-------------|
| MIRROR-1 | Design doc for the mirror (recency window, one-hop semantics, score-≥-7 filter) | - | LEAD-D | docs/research/inferential-structural-judge-mirror-design.md | Recency window = 7 days (configurable); one-hop semantics; score-≥-7 filter; "highest-severity wins" rule; LLM-judge-circularity mitigation section (mirror is informational, not directive) | No `permissionDecision`; no mutation of the journal; no transitive cross-session chains |
| MIRROR-2 | Author the SessionStart hook script | MIRROR-1 | LEAD-B | hooks/inferential-structural-judge-escalation-mirror.sh | Reads the most recent score-≥-7 verdict from `~/.claude/governance-events.jsonl` (last 7 days); emits JSON envelope with `hookSpecificOutput.additionalContext` containing the markdown block; exit 0 always | Bash 3.2 compat; `set -uo pipefail` (not `-e`); `command -v` guards on python3/jq; matcher-less SessionStart; bypass env vars match the parent hook's pattern |
| MIRROR-3 | Register the hook in `hooks/hooks.json` + add sensor entry to `hooks/sensors.json` | MIRROR-2 | LEAD-B | hooks/hooks.json, hooks/sensors.json | New SessionStart array element with `${CLAUDE_PLUGIN_ROOT}/hooks/inferential-structural-judge-escalation-mirror.sh`; new sensor entry: `name: inferential-structural-judge-escalation-mirror`, `should_fire_when: SessionStart:`, `max_silent_days: 7` (per the Q2 default for advisory SessionStart sensors), `fallback_role: inferential-FF`, `must_fire_in_session: false`, `enabled: true` | One new array element per file; existing entries byte-identical |
| MIRROR-4 | Add the 8th critical-hooks test | MIRROR-2 | LEAD-B | hooks/tests/test-critical-hooks.sh | Test that a journal with one score-9 verdict (within 7 days) triggers the mirror; test that a score-9 verdict older than 7 days does not trigger; test that the mirror emits the correct `additionalContext` shape; test that `permissionDecision` is never emitted | Use the existing `check_hook` pattern from the file; 4 new assertions (mirror of the 4 `notify-sensor-staleness` tests) |
| MIRROR-5 | Author the eval fixture | MIRROR-2 | LEAD-B | eval/regressions/inferential-structural-judge-escalation-mirror.json | 4 hand-curated fixtures (1 mirror-triggers, 1 mirror-skips-stale, 1 mirror-skips-no-event, 1 mirror-skips-low-score); uses `script-cli` skill | 4 fixtures, all with hand-written rationales |
| INT-3 | End-to-end: cache-update + restart + manual smoke | MIRROR-1, MIRROR-2, MIRROR-3, MIRROR-4, MIRROR-5 | LEAD-B | (none) | `claude plugin update kbg@kobig` exits 0; restart → run session with a real score-9 verdict in journal → next SessionStart emits the mirror block | run via V validation step |

## Acceptance Criteria

- [ ] MIRROR-1: design doc covers recency window, one-hop semantics, score-≥-7 filter, LLM-judge-circularity
- [ ] MIRROR-2: hook script is bash 3.2 compat, shellcheck-clean, 212/212 critical-hooks tests pass
- [ ] MIRROR-3: hooks.json + sensors.json entries added; existing entries byte-identical
- [ ] MIRROR-4: 4 new test cases in critical-hooks suite; total 212 passing
- [ ] MIRROR-5: 4 hand-curated fixtures; all 4 with hand-written rationales
- [ ] No `permissionDecision` ever emitted by the mirror hook
- [ ] INT-3: harness-audit exits 0C/0W (or 0C/0W/1I) post-restart

## Validation Commands

- `bash skills/harness-audit/scripts/audit.sh .` — manifest, schema, descriptions
- `bash hooks/tests/test-critical-hooks.sh` — critical-hooks regression
- `python3 eval/run-eval.py --regression --tag inferential-structural-judge-escalation-mirror --gate` — eval gate green
- `git grep -n 'permissionDecision' hooks/inferential-structural-judge-escalation-mirror.sh` — autonomy-invariant scan (expect 0)
- `claude plugin update kbg@kobig` — plugin cache update + restart Claude Code

## What this plan does NOT do

- Does NOT implement transitive cross-session chains (Q6)
- Does NOT let a more recent lower verdict "talk down" an older escalation (Q4)
- Does NOT modify the parent plan's SessionEnd hook (the mirror is a separate hook)
- Does NOT add a `disallowedTools:` block (decay-cadence convention)
- Does NOT auto-mutate `hooks/sensors.json` (the registry is hand-curated)
