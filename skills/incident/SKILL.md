---
name: incident
description: "Manage a live production incident end-to-end. Use when alerts fire, monitors show red, users report widespread issues, or error rates spike. Thai: 'incident', 'เหตุฉุกเฉิน', 'production เสีย', 'ระบบล่ม'. Do NOT use for: non-production bugs (use /fix-bug), planned maintenance, security incidents requiring special handling (use security-reviewer first), or post-incident documentation (use /post-mortem after resolution)."
---

# Incident

Run a production incident from first alert to resolution. **Incident response is not debugging — it's mitigation, communication, and controlled recovery.**

**When to use:** Alerts fire, monitors red, widespread user issues, error rate spikes.

**When NOT to use:** Non-production bugs, planned maintenance, security incidents requiring special handling (STOP — redirect to `security-reviewer` first), post-incident docs.

---

## Procedure

1. **Detect & Acknowledge** — Validate signal (correlated metrics), acknowledge in channel, claim command, start timer.

2. **Assess** — What broke? Who's affected? When did it start? Blast radius trend? Classify severity (S1–S4). Default S2. Rank hypotheses by likelihood with a quick-test table.

3. **Confirm mitigation plan** — Before executing outward-facing / irreversible actions:
   - **AskUserQuestion** single-select: "Severity = [S1/S2/S3/S4], blast radius = [service / subset / none], recommended mitigation = [rollback / kill-switch / circuit breaker / scale / hotfix]. Proceed?"
     - `Execute mitigation now (Recommended when the user is the incident commander and the blast radius is confirmed)` — proceed to step 4
     - `Escalate first (Recommended when severity is S1 or blast radius is expanding)` — stop; notify on-call or exec before acting
4. **Mitigate** — In order of speed. **Note N/A steps explicitly** (e.g., "Rollback: N/A — no recent deploy") rather than skipping silently:
   - Rollback (fastest)
   - Kill-switch / feature flag
   - Circuit breaker / rate limit
   - Scale up / failover
   - Hotfix (slowest — hand off to `kbg:hotfix`)
   Preserve evidence first. Document gaps: if a kill-switch or circuit breaker does not exist, say so.

5. **Communicate** — Initial status within 5 min. Updates every 5 min during active incident. Audience scales with severity.

6. **Fix Forward** — If mitigation ≠ rollback, hand off to `kbg:hotfix` (S1/S2) or `/fix-bug` (S3). Severity reassessment belongs in step 2, not here.

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

## Constraints

- Mitigate first, investigate second.
- Communication is triage — update every 5 min.
- Single incident commander.
- Preserve evidence before fixing.
- Escalate if MTTR > target or blast radius expands.

## METHODOLOGY

- **Rule 1:** Assess before mitigate.
- **Rule 4:** MTTR is the metric.
- **Rule 10:** Each phase has a clear exit.
- **Rule 12:** Blast radius expands = escalate immediately.

## References

- `references/common-ops.md` — Concrete commands for DB failover, circuit breaker ops, investigation queries, and alert tuning. Load this when the incident involves infrastructure you can SSH into or when the engineer needs copy-paste commands.

## Related

- `kbg:hotfix` — rollback/kill-switch insufficient; actual fix under incident
- `/fix-bug` — non-urgent root cause fix after mitigation
- `/post-mortem` — after resolution, blameless analysis
- `/ship-merge` — deploying fix PR after resolution

**Named model** (cc-thinking-skills): the detect → assess → mitigate → monitor loop is *ooda* (observe-orient-decide-act under time pressure). Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.
