# Sensor-fire notification — design

**Status:** design (REG-1 + DOC-1 complete, awaiting HOOK-1 / AUDIT-1 / CMD-1 / FIX-1)
**Plan:** `.claude/tasks/sensor-fire-notification.md`
**Author:** LEAD-D (code-architect) on the `sensor-fire-notification` plan
**Date:** 2026-06-15

---

## 1. Context

Böckeler (Thoughtworks, [harness-engineering 2026-04](https://martinfowler.com/articles/harness-engineering.html)) closes the article with four open questions. The third — **L553** — is the open observation: *"how do we keep a harness coherent?"* The article raises it and drops it. The fourth open question, **L493** (the "ambient affordances" sidebar attributed to Ned Letcher), gives the operational answer: a codebase's *strongly-typed language, defined module boundaries, and framework abstractions* implicitly make it more governable, because the *absence* of those affordances — in the same way that the absence of a sensor firing is a *coverage gap*, not a *quality signal* — is what you have to detect.

`kbg-harness` has 31 unique hook-event sensors and 42 kbg hook registrations across 14 lifecycle events. The plugin's 2×2 model (see `CLAUDE.md` § "Harness as a 2×2 mental model") populates every cell. But the article's "silent sensors = coverage gap" insight is *not* operationalized: the closest analog is `audit.sh:773-880` (eval-target freshness), which *reports* staleness at audit time but does not *notify* the operator when a runtime sensor goes dark in production.

This plan closes the gap. It is intentionally narrow: a hand-curated registry of runtime sensors, a SessionStart hook that diffs the journal against the registry, a Q3 severity-gated `additionalContext` block, and a Q4 hash-gated dismiss command. Total new surface: `hooks/sensors.json` (1 file) + `commands/dismiss-stale.md` (1 file) + `hooks/maintenance/notify-sensor-staleness.sh` (1 file) + 1 entry in `hooks/hooks.json` + 1 flag in `audit.sh`. Q&A #12 calls this "scope creep that's bounded and load-bearing."

## 2. Registry schema (v1)

The registry is `hooks/sensors.json`, co-located with the consumer hook (Q1 verdict A: BASH_SOURCE-stable — `$(dirname "$0")/sensors.json` works whether the hook runs from the source tree or the plugin cache). It is *hand-curated* per METHODOLOGY Rule 2 (no speculative configurability): no `$KBG_*` env-var defaults, no inference from filesystem globs.

Each entry has seven fields:

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | matches `hooks/<name>.sh` basename; unique within the file |
| `should_fire_when` | string | yes | `Event:matcher` literal from `hooks/hooks.json`; for multi-registered scripts, the most-specific (non-`*`) registration is canonical |
| `max_silent_days` | int | yes | per-event-bucket default (Q2 mapping, table below); the staleness threshold in calendar days |
| `fallback_role` | enum | no | one of `computational-FF` / `inferential-FF` / `computational-FB` / `inferential-FB`; **omit** to treat as `off` (Q7 — the only intentional-silent exemplar) |
| `must_fire_in_session` | bool | no (default `false`) | if `true`, the staleness check is session-count, not days (Q2's "days ≠ session-count" extension) |
| `enabled` | bool | no (default `true`) | runtime kill switch (Q5 verdict A); flipping this in place is the toggle, structural removal = decay-cadence quarter |
| `observable` | bool | no (default `true`) | is **journal-silence a meaningful staleness signal** for this sensor? `false` in two cases: **(1)** it never writes the governance journal — nudges/reminders (emit `additionalContext`), session/usage/backup hooks (own sink); **(2)** it *does* journal but fires only on **event-dependent** triggers where silence is benign — the `*-log` audit hooks (`auto-mode-denial`, `bypass-audit`, `evidence-trail`, `fabrication-verdict`) dual-write to the journal (`journal_append`, per the "journal replaces scattered TSV logs" goal below) **and** their own `.log`, but a silent one means "no bypass/denial/fabrication/web-fetch happened," not a broken sensor. For `observable:false`, a never-journaled sensor is NOT flagged — it is measured only once it actually fires (the `days_silent > threshold` path ignores `observable`). Böckeler L553 (never-fired = coverage gap) applies only to `observable:true` sensors — those expected to fire on a regular cadence. This is the fix for the false "silent never" alarms that listed ~13 sensors every SessionStart. |

**Q2 bucket defaults (per `sensor-fire-notification.md:25-28`):**

| Event bucket | `max_silent_days` | Rationale |
|---|---|---|
| `PreToolUse` | 1 | gates should fire on every destructive-Bash attempt; if a gate hasn't fired in a day, the operator hasn't run a Bash command, OR the gate is mis-registered |
| `PostToolUse` | 1 | audits fire on every Edit/Write/Bash; 1-day window matches the per-commit cadence |
| `UserPromptSubmit` | 7 | nudges fire on every user prompt; a 7-day window tolerates "I haven't been prompting about X this week" without alarm fatigue |
| `TaskCompleted` | 7 | matches the per-week agent-team cadence |
| `SessionStart` | 30 | quarterly decay-cadence match |
| `SessionEnd` | 30 | quarterly decay-cadence match |
| `Stop` | 30 | quarterly decay-cadence match |
| `PreCompact` / `Notification` / `SubagentStop` / `TeammateIdle` / `ConfigChange` / `PermissionRequest` / `PermissionDenied` / `PostToolUseFailure` | 90 | rare events — three-month window is the right beat |

**v1 count: 31 entries** (one per unique hook-event script in `hooks/hooks.json`; see § "Defects surfaced to lead" for the plan's "43" overcount).

## 3. Trigger (Q3 verdict B, severity-gated)

The hook reads `audit.sh --staleness-only` (the new flag added by AUDIT-1) at SessionStart. The flag emits a JSON list of `{name, last_fired, days_silent, fallback_role}` per registered sensor. The hook then applies Q3 severity gating:

- **Enforcement stale:** if **any** sensor with `fallback_role IN {computational-FF, computational-FB}` is silent past its `max_silent_days`, the trigger fires. Computational sensors either *block* (FF) or *audit* (FB) — silence means the operator has lost a coverage dimension they *need*.
- **Advisory stale:** if **≥ 3** sensors with `fallback_role IN {inferential-FF, inferential-FB}` are silent past their thresholds, the trigger fires. The threshold of 3 absorbs the LLM-judge-circularity concern (per `CLAUDE.md` § "LLM-judge circularity"): inferential sensors may legitimately stay quiet if their trigger conditions never arise, so a *single* advisory silence is not signal — three is.

When the trigger fires, the hook emits a single `hookSpecificOutput.additionalContext` block:

```
**N sensors haven't fired:**
- [enforcement] block-dangerous-git (silent 23d, threshold 1d), secret-scan (silent 8d, threshold 1d), ...
- [advisory] iron-rule-reminder (silent 12d, threshold 7d), skill-nudge (silent 9d, threshold 7d), orchestrator-nudge (silent 8d, threshold 7d)
Dismiss: /dismiss-stale | Audit: bash "${KBG_PLUGIN_ROOT}/skills/harness-audit/scripts/audit.sh" "${KBG_PLUGIN_ROOT}"
```

When the trigger does *not* fire, the hook is silent. It **never** emits a `permissionDecision`, **never** calls `AskUserQuestion`, **never** aborts the session. The block is informational — the operator decides whether to investigate.

**Why not just trigger on N≥1 (any stale)?** — Computational enforcement silence is signal (the harness *should* be denying/auditing constantly). Inferential silence is a tri-state: (a) the trigger condition legitimately never arose, (b) the trigger condition arose but the sensor is broken, (c) the operator stopped using the workflow. The 1-vs-3 threshold discriminates (a) from (b/c) cheaply without requiring the operator to remember "did I use that workflow last week?"

## 4. Dismissal (Q4 verdict C, hash-gated)

The new `commands/dismiss-stale.md` (operator-only, `disable-model-invocation: true` per the Q&A #4 manual-gate convention) writes `~/.claude/state/kbg-staleness-dismissed.json` with the shape:

```json
{
  "dismissed_until": "2026-06-22T00:00:00Z",
  "dismissed_set_hash": "sha256:4e8d2c1a..."
}
```

The `dismissed_set_hash` is `sha256sum` over the **sorted, newline-joined names** of every sensor currently considered stale by the Q3 trigger. The hash is recomputed on every SessionStart, and the hook *re-injects* the `additionalContext` block if the current stale-set hash differs from the stored hash. The effect:

- If the operator dismisses and the stale set stays the same, the hook stays silent for 7 days.
- If a *new* sensor goes silent (e.g. one stale sensor dies and a fresh one becomes stale), the hash changes and the block re-injects. The operator is paged with the *new* sensor, not drowned in the same old list.
- After 7 days (`dismissed_until` is `now + 7d`), the dismissal expires and the hook re-injects unconditionally on the next Q3 trigger.

**Why hash the names, not the count?** — The count changes for trivial reasons (a sensor came back online, a new one went silent) and would re-inject the *same* list with a different number — alarm fatigue. The set-of-names hashes only on the *new* sensor, which is the load-bearing signal. The set is also stable across renames: if a sensor is renamed, the dismissal expires (the operator is forced to re-acknowledge the new name).

## 5. Toggle (Q5 verdict A, runtime only)

Two ways to turn a sensor off:

- **Runtime kill switch:** flip `enabled: false` in `hooks/sensors.json`. No version bump, no plugin-cache invalidation, no `claude plugin update`. The change is effective on the next SessionStart.
- **Structural removal:** delete the `hooks/<name>.sh` script + remove its `hooks/hooks.json` entry + remove its registry entry + remove the corresponding `test-critical-hooks.sh` block + bump the plugin version. This is a decay-cadence-quarter move (per `docs/harness-decay-cadence.md`).

**Why runtime-only as the default?** — The harness's autonomy invariant (ADR 0002) forbids autonomous mutation. A runtime toggle is human-gated by definition — the operator edits a JSON file and the change is effective immediately. A structural removal requires 5 file edits and a version bump, which is the right shape for "this sensor is genuinely dead" but overkill for "I want to silence this for a week."

**Why decay-cadence for structural removal?** — Per Q5, structural removal *is* the decay decision. The decay cadence (`docs/harness-decay-cadence.md:1-3`) is the human-run review loop that decides "is this component compensating for an assumed model limitation that no longer holds?" Flipping `enabled: false` in place is the *investigation* phase; the *removal* phase is decay-cadence.

## 6. Roadmap (Q6 verdict A, runtime truth only)

The registry lists *only* runtime sensors — the 31 unique hook scripts currently registered in `hooks/hooks.json`. The 2×2 design grid in `CLAUDE.md` (the table starting "Böckeler models a coding-agent harness as a 2×2") is the *intentional-gap* roadmap: the cells where kbg has no sensor are documented design decisions, not registry entries. The 2×2 itself is a hand-curated description of *intent*; the registry is a hand-curated description of *runtime reality*. Conflating them would force the registry to either:

1. lie (list sensors that don't exist) — Q6 verdict A is the rejection of this;
2. expand scope (audit the 2×2 itself for drift) — out of scope, belongs to `inventory` + `BOUNDARY.md`;
3. defer to the 2×2 as roadmap (current state) — the right answer, and the cross-reference for the sibling P3 plan.

**Cross-reference:** the `harness-coverage-metric` plan (P3, blocked on this plan + the `inferential-structural-test` plan) will build a "what fraction of the harness's *claimed* sensors fired on the last N commits?" tool. That plan *is* the meta-coverage check; this plan is its *sensor*. The dependency is:

```
sensor-fire-notification (this plan, P2)   ──┐
                                              ├── enables ──>  harness-coverage-metric (P3)
inferential-structural-test (sibling P2)   ──┘
```

## 7. Cost

- **Wall time:** one `bash audit.sh --staleness-only` invocation per SessionStart. The audit is already O(seconds) for 38 checks (`audit.sh:1-5` exit code 0 = clean; the staleness check is a sub-5s slice). The flag emits a single JSON list — no per-sensor subprocess. Net cost: **~1 second of session-start latency**.
- **Token cost:** zero. The trigger reads a JSON list and *only* emits `additionalContext` when Q3 fires; the message is short (sensor name + days + threshold), not a 1500-char block.
- **Disk cost:** the dismissal file is `~/.claude/state/kbg-staleness-dismissed.json`, ~80 bytes. Negligible.
- **Token cost for the operator:** the operator sees the block when Q3 fires (rare — most sessions are quiet); dismiss with one slash command; or ignore and let the 7-day TTL expire.

The plan trades ~1s/session-start latency + the cost of the operator's attention to a stale-sensor block for closing a load-bearing observability gap (Böckeler L553). The trade is favorable: the harness is personal, sessions are the cadence, and the cost is bounded.

## 8. Why-not alternatives

- **CI cron (`.github/workflows/sensor-staleness-notify.yml`).** — Rejected. A cron is **L3 autonomy** per `docs/adr/0002-autonomy-invariant.md` ("no CronCreate, no `/loop`, no scheduled unattended loop"). The kbg harness is personal — sessions *are* the cadence. A SessionStart hook fires when the operator picks up the harness, which is the right beat; a cron fires on a wall clock, which the operator may not be at.
- **`kbg:harness-health` command (operator-invoked).** — Rejected as the *load-bearing* surface (kept as a complement, optional). A command requires the operator to *remember to run it*. The harness is the right place to surface "your sensors are stale." A command is the right shape for a *deep dive* (one-shot, ad-hoc, returns a full report); the hook is the right shape for a *nudge* (every session, silent when clean).
- **Log-watch tail + Slack/email page.** — Rejected. Paging outside the harness is a behavioral change that the plan's "scope" doesn't authorize (Q&A #10: "Does NOT page the operator outside the harness"). Out of scope.
- **Auto-disable a stale sensor.** — Rejected per Q5 verdict A and the autonomy invariant. The operator's attention is the gate; the harness never auto-mutates.

## 9. Out of scope

- **Auto-disable / auto-mutation.** The registry is hand-curated; the harness never edits it on the operator's behalf. Decay-cadence owns the removal decision (`docs/harness-decay-cadence.md`).
- **Auto-page outside the harness.** The notification surface is `additionalContext` in the operator's own session, period. No Slack, no email, no webhook.
- **A new `kbg:harness-health` command** (Q&A #2) is *not* a deliverable of this plan but is a natural complement; filing as a separate follow-up if the operator wants an ad-hoc deep dive.
- **Cross-sibling-plan coordination.** The `inferential-structural-test` plan (P2, sibling) adds a *new* sensor when it lands; that plan owns adding its own registry entry. The two plans are siblings, not parent/child (Q&A #11).
- **A "must_fire_in_session: true" entry.** v1 sets all entries to `false` per METHODOLOGY Rule 2 (no speculative configurability). Operators can flip individual entries to `true` as the need surfaces.

---

## Q1-Q6 verdicts (named, justified)

- **Q1 → A** (registry at `hooks/sensors.json`): co-located with the consumer hook; BASH_SOURCE-stable via `$(dirname "$0")/sensors.json`; no env-var indirection.
- **Q2 → B (with extension):** per-event-bucket `max_silent_days` defaults (table in §2) + a separate `must_fire_in_session` boolean (default `false`). v1 sets all entries to `false`; operators flip as needed.
- **Q3 → B (severity-gated trigger):** inject on any *enforcement* stale (computational-FF/FB) OR ≥3 *advisory* stale (inferential-FF/FB). Walk-through in §3.
- **Q4 → C (dismissable, hash-gated re-inject):** new `commands/dismiss-stale.md` writes `~/.claude/state/kbg-staleness-dismissed.json` with `{dismissed_until, dismissed_set_hash}`. Hook re-injects on hash mismatch or TTL expiry. Walk-through in §4.
- **Q5 → A (single runtime toggle):** `enabled: false` is the kill switch (no version bump, no cache invalidation). Structural removal = 5-file revert + version bump at decay-cadence. Walk-through in §5.
- **Q6 → A (runtime truth only):** the 31-entry registry lists *runtime* sensors; the 2×2 design grid in `CLAUDE.md` is the intentional-gap roadmap. Walk-through in §6.

## Q&A cross-reference (12 from the plan)

- Q1 (why SessionStart, not CI cron) → §8 (alternatives) + §7 (cost)
- Q2 (why not a new command) → §8 (alternatives)
- Q3 (staleness threshold) → §2 (schema, Q2 bucket table) + §3 (Q3 severity gating)
- Q4 (where does the registry live) → §2 (BASH_SOURCE-stable) + §5 (toggle lives in same file)
- Q5 (what does the user see) → §3 (the `additionalContext` block format)
- Q6 (interaction with `harness-audit`) → §7 + §3 (consumes the `--staleness-only` flag)
- Q7 (sensors that are *supposed* to be silent) → §2 (`fallback_role` omitted = `off`; the only intentional exemplar is `recursive-improve-observe.py` — see §"Defects surfaced to lead" for why it does not appear in the v1 registry)
- Q8 (cost) → §7
- Q9 (tests) → sibling plan deliverables AUDIT-1 / HOOK-1 / FIX-1 (this design doc covers the *what*, not the *test*; the eval fixtures are a separate file)
- Q10 (what this plan does NOT do) → §9 (out of scope) + §8 (why-not alternatives)
- Q11 (separation from `inferential-structural-test.md`) → §6 (siblings, not parent/child)
- Q12 (scope-creep check) → §1 (the total new surface is bounded; cited verbatim)

## Defects surfaced to lead

1. **Plan says "43 entries"; the registry has 31.** The plan's count is an overcount. Derivation: `hooks/hooks.json` registers 42 kbg hook *registrations* (excluding the external `$SUPERSET_HOME_DIR/hooks/notify.sh` × 14), but those collapse to **31 unique hook scripts** (one entry per unique basename). The 38 figure in `CHANGELOG.md:1265` and `docs/research/harness-engineering-2026-04-apply-gap.md:16` is a historical count that doesn't match the current registry. The 43 figure in `sensor-fire-notification.md:79,89` appears to assume 42 registrations + `recursive-improve-observe.py`. **Lead decision needed:** is 31 the right count, or do we want to count registrations separately (e.g. as a `should_fire_when: [list]` field, expanding the schema)? Current registry = 31 (one entry per unique script); the v1 schema has a singular `should_fire_when` for simplicity.
2. **`recursive-improve-observe.py` (the Q7 "intentional silent" exemplar) is not in the registry.** Per the plan's Q7 + Q6, the registry excludes non-existent sensors. `recursive-improve-observe.py` lives in `scripts/`, not `hooks/`, is not a hook-event sensor, and is human-invoked by the `recursive-improve` skill. It is documented in `skills/recursive-improve/SKILL.md:46-62` and `docs/agents/verification-trail.md:12,18,72`. **Lead decision needed:** is the v1 registry correct in *not* listing it (Q6 strict reading), or should the registry gain a "non-hook posture observers" section for sibling visibility? Current v1 = not listed.
3. **`must_fire_in_session: true` has no v1 entry.** Per METHODOLOGY Rule 2, v1 leaves the boolean at `false` everywhere. The most defensible case for `true` is `doctrine-bootstrap` (matcher-less SessionStart, fires every session) but the staleness check is calendar-days in v1, and `doctrine-bootstrap`'s 30-day threshold is already conservative. **Lead decision needed:** is `doctrine-bootstrap` the only `true` candidate, or do we have other "must fire every session" sensors? Current v1 = none.
4. **`hooks/hooks.json` is structurally sound.** Confirmed: the 31.4 audit check (`audit.sh:1105-1151`) validates the top-level shape; no defects found during REG-1 cross-check.
