---
name: incident
description: "Incident: run a production incident incl. hotfix. Use when alerts fire or user asks for hotfix. Thai: 'เหตุฉุกเฉิน'. Don't use for non-prod bugs or post-mortem."
bucket: workflow
model: inherit
effort: high
---

# Incident

Run a production incident from first alert to resolution. **Incident response is not debugging — it's mitigation, communication, and controlled recovery.**

**When to use:** Alerts fire, monitors red, widespread user issues, error rate spikes.

**When NOT to use:** Non-production bugs, planned maintenance, security incidents requiring special handling (STOP — redirect to `security-reviewer` first), post-incident docs.

## Procedure

1. **Detect & Acknowledge** — Validate signal (correlated metrics), acknowledge in channel, claim command, start timer.

2. **Assess** — What broke? Who's affected? When did it start? Blast radius trend? Classify severity (S1–S4). Default S2. Rank hypotheses by likelihood with a quick-test table.

3. **Confirm mitigation plan** — Before executing outward-facing / irreversible actions:
   - **Self-consistency**: if blast radius is already confirmed expanding, skip the ask and
     escalate immediately — the "Escalate, don't absorb" rule under METHODOLOGY below already
     answers it, and spending the ask's own time cost on a question already settled works against
     this skill's own MTTR discipline. Severity alone, even S1, does **not** trigger this skip —
     the ask's own options only *recommend* escalating on S1, they don't mandate it, so an S1 with
     a confirmed, non-expanding blast radius still goes through the ask. Never skip toward
     `Execute mitigation now` without asking — only the escalate branch is safe to auto-select; an
     irreversible mitigation always needs the explicit confirmation.
   - **AskUserQuestion** single-select: "Severity = [S1/S2/S3/S4], blast radius = [service / subset / none], recommended mitigation = [rollback / kill-switch / circuit breaker / scale / hotfix]. Proceed?"
     - `Execute mitigation now (best when the user is the incident commander and the blast radius is confirmed)` — proceed to step 4
     - `Escalate first (best when severity is S1 or blast radius is expanding)` — stop; notify on-call or exec before acting
4. **Mitigate** — In order of speed. **Note N/A steps explicitly** (e.g., "Rollback: N/A — no recent deploy") rather than skipping silently:
   - Rollback (fastest)
   - Kill-switch / feature flag
   - Circuit breaker / rate limit
   - Scale up / failover
   - Hotfix (slowest — run the hotfix path from `references/hotfix.md` under this same skill)
   Preserve evidence first. Document gaps: if a kill-switch or circuit breaker does not exist, say so.

5. **Communicate** — Initial status within 5 min. Updates every 5 min during active incident. Audience scales with severity.

6. **Fix Forward** — If mitigation ≠ rollback, run the hotfix path from `references/hotfix.md` (S1/S2) or hand off to `mattpocock-skills:diagnosing-bugs` (S3). Severity reassessment belongs in step 2, not here.

7. **Resolve & Monitor** — Verify fix in production. Monitor window: S1=1hr, S2=30min, S3=10min. Close incident, schedule post-mortem if S1/S2. For S3/S4, if this was an alert misfire or threshold is too sensitive, include alert tuning in the close notes.

8. **Handoff to Post-Mortem** — Immediate notes, schedule within 24hr (S1) or 48hr (S2). Hand off to `/post-mortem`.

Done.

## Security Incident Override

If the incident involves unauthorized access, data exfiltration, or any security breach: **STOP.** Do not classify severity here. Do not apply the 8-step procedure above. Redirect to `security-reviewer` immediately. Once security-reviewer clears forensic steps, return to this procedure for infrastructure recovery only.

## Severity

| Tier | Condition | MTTR Target | Comms Audience |
|---|---|---|---|
| S1 (Critical) | Service down, data loss, security breach | <15 min | All + exec + customers |
| S2 (Major) | Degraded core, workaround exists | <1 hr | Team + stakeholders + customers |
| S3 (Minor) | Non-core degraded, no user impact | <4 hr | Team only |
| S4 (Noise) | Alert fired, no actual impact | N/A | Tune alert threshold, close |

## Output Format

Produce at close:

- **Severity:** S1–S4 (final, post-reassessment)
- **Mitigation applied:** <rollback / kill-switch / circuit breaker / scale / hotfix — note N/A steps explicitly>
- **MTTR:** <actual vs target>
- **Root cause (preliminary):** <one line — full analysis is /post-mortem's job>
- **Evidence preserved:** <logs/metrics links or locations>
- **Alert tuning:** <if S3/S4 misfire — threshold change, or "N/A">
- **Post-mortem:** scheduled at <time> (S1 ≤24hr, S2 ≤48hr) | N/A (S3/S4)

## Constraints

- Mitigate first, investigate second.
- Communication is triage — update every 5 min.
- Single incident commander.
- Preserve evidence before fixing.
- Escalate if MTTR > target or blast radius expands.

## METHODOLOGY

- **Rule 1:** Assess before mitigate.
- **Rule 4:** MTTR is the metric.
- **Clear phase exits:** each phase has a well-defined stop condition before the next begins.
- **Escalate, don't absorb:** blast radius expands = escalate immediately.

## References

- `references/common-ops.md` — Concrete commands for DB failover, circuit breaker ops, investigation queries, and alert tuning. Load this when the incident involves infrastructure you can SSH into or when the engineer needs copy-paste commands.

## Related

- `references/hotfix.md` — hotfix path when rollback/kill-switch is insufficient (formerly `kbg:hotfix`)
- `mattpocock-skills:diagnosing-bugs` — non-urgent root cause fix after mitigation
- `/post-mortem` — after resolution, blameless analysis
- `mh:ship-merge` — deploying fix PR after resolution

**Named model** (cc-thinking-skills): the detect → assess → mitigate → monitor loop is *ooda* (observe-orient-decide-act under time pressure). Catalog + honesty caveat: read via Bash with `cat "${MH_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.

## Done when

The incident is mitigated and monitors stay green under load — verify the rollback or fix held before declaring resolution. confirm the post-mortem is filed as a separate step; never close an incident on a single green datapoint.
