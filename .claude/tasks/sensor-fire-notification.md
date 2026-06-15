---
slug: sensor-fire-notification
priority: P2
source: .scratch/research/harness-engineering-2026-04.md §"Actionable changes" #5
status: planned (research, not build)
target: kbg-harness 0.2.x
created: 2026-06-15
drilldown: 2026-06-15 (Q1-Q6 verdicts baked in)
related: audit.sh:773-880 (staleness detection), JOURNAL-SCHEMA.md, decay-cadence.md, inferential-structural-test.md
---

# Plan: Sensor-fire notification (close the "silent sensors" gap)

## Brain dump

Böckeler L553 open question: *"If sensors never fire, is that a sign of high quality or inadequate detection mechanisms?"* The article's ambient-affordances sidebar (L493) gives the answer: dead sensors are coverage gaps. kbg's `harness-audit` (check #31 / audit.sh:773-880) already *reports* staleness ("hook X didn't fire in 90 days") but the report is read once at audit time — no human is *notified*.

The harness's sensor surface is 38 hooks (computational FB) + 5 journaling hooks (computational + inferential FB). Each has a "should fire" cadence (per-commit, per-session, per-merge). When one of those cadences lapses, the system has lost a *coverage* dimension, not just a *line* in a report.

This plan designs a notification surface: at the start of each session, the harness surfaces "X sensors didn't fire in N days — is that a quality signal or a coverage gap?" in a way the operator can act on, not just stare at. The Q1-Q6 design decisions drilled down on 2026-06-15 are baked into the schema and Acceptance Criteria below.

### Schema decisions from Q1-Q6 drill-down

- **Q1 → A:** registry lives at `hooks/sensors.json` (co-located with the hook that reads it; BASH_SOURCE-stable).
- **Q2 → B (with extension):** per-event-bucket defaults for `max_silent_days` + a separate boolean `must_fire_in_session: true` (days ≠ session-count).
  - PreToolUse = 1 day, PostToolUse = 1 day, UserPromptSubmit = 7, TaskCompleted = 7,
    SessionStart = 30, SessionEnd = 30, Stop = 30, PreCompact/Notification/SubagentStop/
    TeammateIdle/ConfigChange/PermissionRequest/PermissionDenied/PostToolUseFailure = 90.
- **Q3 → B (severity-gated trigger):** inject if any sensor with `fallback_role IN {computational-FF, computational-FB}` is stale (enforcement), OR if ≥3 sensors with `fallback_role IN {inferential-FF, inferential-FB}` are stale (advisory tolerates silence per LLM-judge-circularity).
- **Q4 → C (dismissable, hash-gated re-inject):** new `commands/dismiss-stale.md` writes `~/.claude/state/kbg-staleness-dismissed.json` with `{dismissed_until: <ISO-8601>, dismissed_set_hash: <sha256 of sorted stale-sensor names>}`; hook re-injects when current stale-set hash ≠ stored hash.
- **Q5 → A (single runtime toggle):** `enabled: false` in `sensors.json` (no version bump, no cache invalidation); structural removal = 5-file revert + version bump at decay-cadence.
- **Q6 → A (runtime truth only):** registry never references non-existent files; 2×2 design grid in `CLAUDE.md` is the roadmap (intentional gaps), coverage metric is the cross-reference.

### `sensors.json` schema (v1)

```json
{
  "version": 1,
  "sensors": [
    {
      "name": "block-dangerous-git",
      "should_fire_when": "PreToolUse:Bash",
      "max_silent_days": 1,
      "fallback_role": "computational-FF",
      "must_fire_in_session": false,
      "enabled": true
    }
  ]
}
```

## Q&A log

1. **Why a SessionStart hook and not a CI cron?** — Cron is L3 autonomy (per ADR 0002; "no CronCreate"). The kbg harness is personal — sessions *are* the cadence. A SessionStart hook fires when the operator picks up the harness, which is the right beat.
2. **Why not a new `kbg:harness-health` command?** — A command requires the operator to *remember to run it*. The harness is the right place to surface "your sensors are stale." A *new* command is also fine as a complement, but the hook is the load-bearing surface.
3. **What's the staleness threshold?** — Per-sensor, sourced from a new `hooks/sensors.json` registry: `{"name": "block-dangerous-git", "should_fire_when": "PreToolUse:Bash", "max_silent_days": 1, "fallback_role": "computational-FF", "must_fire_in_session": false, "enabled": true}`. Defaults are per-event-bucket (Q2 mapping). The `must_fire_in_session: true` boolean is for the rare "must fire every session" sensor (days ≠ session-count).
4. **Where does the registry live?** — `hooks/sensors.json` (Q1 verdict A). The hook script is *matcher-less* SessionStart and reads the registry via `$(dirname "$0")/sensors.json`, reusing the BASH_SOURCE-stable pattern every hook in the repo already employs. Adding/removing sensors is JSON-only.
5. **What does the user see?** — On SessionStart, if Q3 trigger fires: an `additionalContext` block ("**N sensors haven't fired: [enforcement] X, Y; [advisory] Z. Dismiss: `/dismiss-stale`. Audit: `bash skills/harness-audit/scripts/audit.sh .`**"). If trigger does not fire: silent. The block is *informational*, not a gate — no `permissionDecision`, no AskUserQuestion. The operator decides whether to investigate.
6. **How does this interact with `harness-audit`'s existing staleness detection?** — `audit.sh:773-880` *already* detects staleness; the new hook *uses* that data instead of duplicating. The hook reads `audit.sh --staleness-only` (new flag, see AUDIT-1) at SessionStart, parses, applies Q3 severity gating, applies Q4 hash check against `~/.claude/state/kbg-staleness-dismissed.json`, and injects.
7. **What about sensors that are *supposed* to be silent?** — `recursive-improve-observe.py` is intentionally event-driven. The registry's `fallback_role: "off"` (or absent) is the answer: a sensor with that role is excluded from staleness checks. Distinct from "not built yet" (Q6: registry never references non-existent files; 2×2 design grid in CLAUDE.md is the roadmap).
8. **What's the cost?** — One `audit.sh --staleness-only` invocation per SessionStart + one sha256 of sorted stale names. The audit is already O(seconds) for 38 checks. Net cost: ~1 second of session-start latency, zero token cost.
9. **What's the test?** — Three fixtures: (a) a populated `sensors.json` with 1 enforcement sensor (computational-FF) that has not fired in 30 days + dismissal file with stale hash → expect 1 line in `additionalContext`; (b) a registry where all sensors are recent → expect no `additionalContext`; (c) dismissal file whose hash matches current stale set → expect no `additionalContext`. All 3 in `eval/regressions/sensor-staleness-notifier.json`.
10. **What does this plan NOT do?** — Does NOT auto-disable stale sensors. Does NOT mutate the registry based on observed fire rates (registry is hand-curated). Does NOT page the operator outside the harness. All mutations stay human-gated (decay-cadence).
11. **Why a separate plan from `inferential-structural-test.md`?** — They are siblings, not parent/child. The structural-test agent is a *new* sensor; this plan is about *notifying when existing sensors go silent*. Conflating them hides the design choices. Q6 confirms: registry lists runtime sensors only, sibling plan #2 adds its own registry entry when it lands.
12. **Is the "sensors.json" registry scope creep?** — It is, in the sense that it's new surface. The mitigation: the registry is the *only* new policy file. New surface also includes the new `commands/dismiss-stale.md` (Q4 verdict C). Total new plugin surface = 2 files (registry + command) + 1 new SessionStart hook script + 1 hooks.json entry + 1 audit.sh flag. The cost is bounded; the value is closing a load-bearing observability gap (Böckeler L553).

## Team Members

| Name | Role | Agent Type |
|------|------|------------|
| LEAD-D | Registry + design doc author | code-architect |
| LEAD-B | Hook script + audit flag + fixture builder | backend-engineer |
| V | Lint + critical-hooks + audit + eval validator | code-reviewer |

## Step by Step Tasks

| Task ID | Description | Depends On | Assigned To | Files | Criteria | Constraints |
|---------|-------------|------------|-------------|-------|----------|-------------|
| REG-1 | Author `hooks/sensors.json` registry v1 with 31 entries (unique hook scripts in `hooks/hooks.json`; 42 registrations when multi-matcher dupes are counted — see INT-1 + design doc §2). 43 in the original plan was an overcount (lead-revised post-Wave-1). | - | LEAD-D | hooks/sensors.json | 31 sensors listed, all required fields present, JSON schema-valid, zero drift vs `hooks/*.sh` filesystem | hand-curated; no env-var defaults (per METHODOLOGY Rule 2) |
| AUDIT-1 | Add `--staleness-only` flag to `audit.sh`; emit JSON list `[{name, last_fired, days_silent, fallback_role}]` | REG-1 | LEAD-B | skills/harness-audit/scripts/audit.sh | `bash audit.sh --staleness-only` exits 0, emits valid JSON, < 5s on real repo | reuse existing journal-query helper; no new audit logic |
| HOOK-1 | Author matcher-less SessionStart hook + register in `hooks/hooks.json`; apply Q3 severity gating + Q4 hash check | REG-1, AUDIT-1 | LEAD-B | hooks/notify-sensor-staleness.sh, hooks/hooks.json | BASH_SOURCE-stable, degrades on `audit.sh` absent (silent no-op), injects `additionalContext` only when Q3 trigger fires AND hash mismatch | hook fires *after* `doctrine-bootstrap.sh`; no `permissionDecision` |
| CMD-1 | Author `commands/dismiss-stale.md`; writes `~/.claude/state/kbg-staleness-dismissed.json` with `{dismissed_until, dismissed_set_hash}` | HOOK-1 | LEAD-B | commands/dismiss-stale.md, .claude-plugin/plugin.json, .claude-plugin/marketplace.json | `/dismiss-stale` exits 0, file written, 7-day TTL, plugin manifest version bumped | disable-model-invocation: true (operator-only); updates description count in both manifests |
| FIX-1 | Author 3 regression fixtures in `eval/regressions/sensor-staleness-notifier.json` | HOOK-1, CMD-1 | LEAD-B | eval/regressions/sensor-staleness-notifier.json | (a) stale enforcement + stale hash → 1-line block; (b) all recent → no block; (c) dismissal hash matches → no block | hand-curated, no agent-generated fixture text |
| DOC-1 | Author `docs/research/sensor-staleness-notifier-design.md` resolving all 12 Q&A + Q1-Q6 verdicts | - | LEAD-D | docs/research/sensor-staleness-notifier-design.md | cites Böckeler L493, L553, audit.sh:773-880, all 6 drill-down verdicts | - |
| INT-1 | End-to-end: cache-update + restart + manual smoke (inject fake stale-sensor, observe `additionalContext`) | REG-1, AUDIT-1, HOOK-1, CMD-1, FIX-1, DOC-1 | LEAD-B | (none) | `claude plugin update kbg@kobig` exits 0; restart → additionalContext lists 1 stale sensor | run via V validation step |

## Acceptance Criteria

- [ ] REG-1: 31 entries in `hooks/sensors.json` with all required fields (lead-revised from plan's 43 — see INT-1 + design doc §2) validation_command: jq empty hooks/sensors.json
- [ ] AUDIT-1: `--staleness-only` exits 0 in < 5s and emits valid JSON validation_command: bash skills/harness-audit/scripts/audit.sh . --staleness-only | jq . > /dev/null
- [ ] HOOK-1: 215/215 critical-hooks tests pass (current 210 + 5 new; lead-revised from plan's 209 — the suite grew post-2026-06-12 audit) and shellcheck-clean validation_command: bash hooks/tests/test-critical-hooks.sh
- [ ] CMD-1: `claude plugin validate --strict .` exits 0 (manifest + description counts consistent) validation_command: claude plugin validate --strict .
- [ ] FIX-1: 3 fixtures pass `python3 eval/run-eval.py --regression --tag sensor-staleness-notifier --gate` validation_command: python3 eval/run-eval.py --regression --tag sensor-staleness-notifier --gate
- [ ] INT-1: harness-audit exits 0C/0W (or 0C/0W/1I — only the I1 plugin-cache info) validation_command: bash skills/harness-audit/scripts/audit.sh .
- [ ] No `permissionDecision` ever emitted (informational only) validation_command: git grep -n 'permissionDecision' hooks/notify-sensor-staleness.sh commands/dismiss-stale.md
- [ ] No new `CronCreate` or `/loop` machinery (autonomy-invariant holds) validation_command: git grep -n 'CronCreate\|/loop' hooks/notify-sensor-staleness.sh commands/dismiss-stale.md

## Validation Commands

- `jq empty hooks/sensors.json` — registry is valid JSON
- `bash hooks/tests/test-critical-hooks.sh` — all hook tests pass
- `python3 eval/run-eval.py --regression --tag sensor-staleness-notifier --gate` — eval gate green
- `claude plugin validate --strict .` — manifest valid
- `git grep -n 'permissionDecision\|CronCreate\|/loop' hooks/notify-sensor-staleness.sh commands/dismiss-stale.md` — autonomy-invariant scan (expect 0)
- `bash skills/harness-audit/scripts/audit.sh .` — self-audit clean
