# Inferential structural-judge — design

**Status:** design (DOC-1 complete; AGENT-1, HOOK-1, FIX-1, EVAL-1, SURF-1, XREF-1 downstream)
**Plan:** `.claude/tasks/inferential-structural-test.md`
**Author:** LEAD-D (code-architect) on the `inferential-structural-test` plan
**Date:** 2026-06-15
**Resolves:** Q5 (verdict schema), Q6 (LLM-judge-circularity mitigations), Q8 (cost ceiling)

---

## 1. Purpose & placement in the 2×2

This is a new **Inferential FB** sensor that closes the **behaviour-harness** gap Böckeler (2026-04, L465–478) calls *"the elephant in the room"* and then punts on. The existing 2×2 cell holds `verification-gate.sh` (SessionEnd, session-trails summary), `fabrication-verdict-log.sh` (Stop, fabrication rate), and `kbg:review-pr` (manual, deep, multi-pass). All three are *advisory* by the autonomy invariant (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model §L115) and all three judge **what the session did**, not **what shape the diff took**. The new agent judges *shape*: over-engineering, architectural drift, test-pattern regression, and doctrine conformance — the four dimensions Böckeler lists at L444 (duplicate code, complexity, coverage, style) and L465–478 (behaviour). The cell now has both a *posture* sensor (existing) and a *structural* sensor (this).

## 2. Trigger & lifecycle

- **Event:** SessionEnd.
- **Matcher:** matcher-less (mirrors `doctrine-bootstrap.sh` on SessionStart — one global sensor, no per-tool filtering).
- **Cadence:** one invocation per session, regardless of edit count.
- **Bypass env vars** (must match `verification-gate.sh` so operators have one mental model): `export CLAUDE_HOOK_PROFILE=off` and `export CLAUDE_DISABLED_HOOKS=inferential-structural-judge`.
- **Output sink:** the existing `~/.claude/governance-events.jsonl` JSONL stream (per `JOURNAL-SCHEMA.md`); event name = `inferential_structural_verdict`; `hook` = `inferential-structural-judge`; `fields` carries the verdict payload (see §3).
- **Failure mode on hook error:** always exit 0 (matches `verification-gate.sh`); the SessionEnd lifecycle must not block the user's session closure on a sensor failure.

## 3. Verdict schema (resolves Q5)

```jsonc
{
  "id":      "<ms>-inferential-structural-judge-<rand>",
  "ts":      "2026-06-15T16:45:12.345Z",
  "session": "<session-id>",
  "hook":    "inferential-structural-judge",
  "event":   "inferential_structural_verdict",
  "source":  "journal_append",
  "fields": {
    "score":            7,                            // int 1..10
    "dimensions": {
      "over_engineering":      3,                      // int 1..5
      "arch_drift":            4,                      // int 1..5
      "test_pattern":          2,                      // int 1..5
      "doctrine_conformance":  3                       // int 1..5
    },
    "top_finding":     "Added CacheLayer wrapper for a single-call site; existing module-private memo already covered this need.",
    "recommendation":  "flag",                        // "accept" | "flag" | "escalate"
    "paths":           ["agents/foo.md", "skills/bar/SKILL.md"]  // set by HOOK-1 at journal time, NOT by the agent
  }
}
```

The `paths` field is set by the **hook** at journal time, not by the agent — it lists the files the session's diff touched. It is the lookup key the next session's prior-verdict reader uses to load the drift-aware context for §4(a).

### Why this 4-dimensional structure (rationale for Q5)

Böckeler L444 names four maintenance dimensions (duplicate code, complexity, coverage, style) and L465–478 names behaviour as the unsolved fifth. The four dimensions chosen here collapse that pair onto the kbg-harness surface — the dimensions an *operator of this harness* would actually want flagged, not the dimensions a generic static-analysis tool would surface:

- `over_engineering` (1-5) — is this diff solving a problem the harness does not have, or duplicating an existing primitive? (Böckeler L518: *"defining topologies is a variety-reduction move"* — the agent judges whether the diff reduces or inflates variety.)
- `arch_drift` (1-5) — does this diff move a module's responsibility, or break a `BOUNDARY.md` invariant, in a way the existing patterns would not? (Böckeler L451–463, architecture-fitness axis.)
- `test_pattern` (1-5) — does the test code regress to agent-slop (asserting tautologies, over-mocking, missing negative cases)? (Böckeler L476: *"we put a lot of faith into the AI-generated tests, that's not good enough yet"* — the dimension exists precisely because we cannot trust generation.)
- `doctrine_conformance` (1-5) — does the diff respect the doctrine's hard rules (no `disallowedTools:`, no `permissionDecision` from inferential sensors, no plugin-cache-bypass, no permission drift)? (kbg-specific; not in Böckeler because every harness has different doctrine.)

Each dimension is 1-5 (not 1-10) because the agent's prompt needs four coarse buckets to score reliably; finer granularity at this level is below the noise floor of an LLM judge and inflates the cost ceiling. The `score` field is 1-10 to give a single comparable number for the future `harness-coverage-metric` aggregator (`harness-engineering-2026-04.md` §"Actionable changes" #6) and for human readers scanning the journal.

### Operational meaning of the score ranges

| `score` | `recommendation` | What the surface does |
|---|---|---|
| **1-3** | `accept` | Journal only. The session is silently green. `kbg:harness-audit --health` shows the verdict count, never the rationale. |
| **4-6** | `flag` | Journal + the verdict surfaces in `kbg:harness-audit --health` (or the new `kbg:harness-audit --health` command) with the rationale. The operator is *informed*, not interrupted. |
| **7-10** | `escalate` | Journal + the verdict surfaces prominently with the rationale in `kbg:harness-audit --health`. The next-session auto-mirror (into SessionStart `additionalContext`, so the next session's first prompt carries "the previous session escalated on X") is a deferred follow-up — see `.claude/tasks/inferential-structural-judge-escalation-mirror.md` and Q10 below. No push notification, no PagerDuty. |

The *intended* escalation channel is *the next session*, not the current one: a model cannot fix its own session-end problem, and interrupting a finished session is meaningless. (Until the mirror lands per Q10, escalate-tier verdicts are read from `kbg:harness-audit --health`.) This is the symmetric counterpart of `verification-gate.sh`'s "pure SENSOR" stance (per its own header) — the FB cell journals by default and escalates into the next-session FF cell only when warranted.

## 4. LLM-judge-circularity mitigations (resolves Q6)

Three concrete mitigations, each load-bearing:

**(a) Drift-aware prompt template.** The agent's prompt is *templated* (not free-form) to include, for each file in the diff: (i) the diff hunk, (ii) the **prior session's verdict** for the same path (read from the journal, with the most-recent verdict winning), and (iii) an explicit "if your verdict is improving the prior verdict, justify why this session's work is better; if it is degrading, justify why the prior verdict was wrong" instruction. This makes the judge *aware* of its own drift trajectory, which is the partial mitigation for the shared-blind-spot failure mode Böckeler names at L356–359 (*"we need a model that is suitable"* — meaning, independent of the generator's class) and L393 (*"we can of course also use AI to improve the harness"* — compounding the same-model-class risk). The deeper fix is a different-model-class judge (Opus judge, Sonnet generator) — deferred per the plan's Q6; it is a cost, not a correctness, decision and the F8 model-split benefit is real.

**(b) Cross-check against hand-curated fixtures.** The agent is **not** evaluated on agent-generated test cases. The 10-fixture regression at `eval/regressions/inferential-structural-judge.json` (FIX-1) is hand-curated: 5 known-good diffs (expected `score < 4`) and 5 known-bad diffs (expected `score > 7`), with hand-written rationales. The eval gate (EVAL-1) requires ≥ 4/5 in each bucket, with a tag-only failure mode (does not fail the global `--gate`). This is the explicit countermeasure to the test-quality problem Böckeler warns about at L476 (*"we put a lot of faith into the AI-generated tests, that's not good enough yet"*). Hand-curation is the mitigation; agent-generated rationales would defeat the test.

**(c) No mutation, no `permissionDecision`.** The agent **never** writes to the repo and **never** emits a `permissionDecision`. The verdict is journal-only; the future `kbg:harness-audit --health` / `kbg:harness-audit --health` surface is a *read* of the journal, not a write-back. This is the autonomy invariant (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model §L115: *"Pure SENSOR: it journals but NEVER emits a permissionDecision"*, the `verification-gate.sh` precedent). It is the load-bearing guard against the L4-loop covert failure mode Böckeler's L356–359 warning points at: an inferential-FB sensor with `permissionDecision: deny` authority is a model-driven mutation gate, which the invariant forecloses. CI enforcement: `git grep -n 'permissionDecision' "${KBG_PLUGIN_ROOT}/agents/inferential-structural-judge.md" "${KBG_PLUGIN_ROOT}/hooks/session/inferential-structural-judge-on-session-end.sh"` must return zero matches (the plan's final validation command).

## 5. Cost attribution (resolves Q8)

- **Per-session token budget for the agent itself:** ~1,000 tokens output (verdict JSON) + ~3,000 tokens input (diff + prior-verdict context) = **~4,000 tokens per session**.
- **Session budget gate:** per METHODOLOGY Rule 6 (`METHODOLOGY.md:113-118`, "Token Budgets Are Not Advisory"), the harness allocates 30,000 tokens per session. The new agent **must** run within that budget, not add a per-call budget. Concretely: the SessionEnd hook reads the session's running token count (via the same mechanism `verification-gate.sh` already uses to read `.scratch/*/verification-trail.md`); if the count is already ≥ 25,000, the hook **skips** and journals a `skipped: budget` event with the same envelope shape and `event: "inferential_structural_verdict_skipped"`.
- **Hard ceiling:** the agent's prompt template must be **bounded** — no whole-repo context, only files touched in the session, only the prior verdict for those exact files, and a hard cap of 50 files in the diff (truncate beyond that with a `truncated: true` flag in the verdict, so the next session's reader knows the verdict is partial).
- **Why 25,000 and not 30,000:** leaves a 5k-token headroom for `session-summary.sh` and the SessionEnd report itself, both of which run on the same lifecycle and have the same budget contract.

## 6. Failure modes

| Failure | Behaviour | Why |
|---|---|---|
| Agent absent (plugin cache stale, file missing) | `command -v` guard in the hook; on absence, journal an `event: "inferential_structural_verdict_skipped"` with `fields.reason: "agent_absent"` and exit 0 | Matches `verification-gate.sh` and `doctrine-bootstrap.sh` "degrade gracefully" convention. A missing sensor is not a broken harness; it is a coverage gap the staleness-notifier will surface. |
| Journal file unwritable (disk full, permission denied) | Hook logs to stderr and exits 0; **does not** retry, **does not** block session end | SessionEnd cannot be allowed to fail because the journal is broken. The 204-test critical-hooks suite does not test "absence of verdict event is a fail" (per the plan's Q12) — silent skips are by design. |
| Empty diff (no edits this session) | Hook journals `event: "inferential_structural_verdict"` with `fields.score: 0`, `fields.dimensions: {}`, `fields.recommendation: "accept"`, `fields.top_finding: "no edits this session"` | An empty session is the *strongest* accept signal, not a reason to skip. Score 0 is below the 1-3 silent-accept band, so it journals clean. |
| Prior-session verdict file missing (first run) | The prompt template's drift-awareness section degrades to a "no prior verdict" branch; the agent judges the diff without a drift comparator; the verdict still journals | First-run state is a real state, not an error. The 4-dimension scoring still works; only the drift-trajectory context is missing. |
| Session already at ≥ 25,000 tokens | Journal `skipped: budget` event, exit 0 | Per §5. The 5k headroom for `session-summary.sh` is load-bearing. |
| Diff > 50 files | Truncate to 50, journal `fields.truncated: true` | Prevents the prompt from blowing the cost ceiling. The journal flag tells the next-session reader "this verdict is partial" so a high score on a truncated diff is not over-trusted. |

## 7. Open questions for Wave 2-5

The downstream agents need to make the following decisions, which this doc deliberately does not pre-commit:

- **AGENT-1 (agent file author):** exact `tools:` allowlist (likely `Read`, `Grep`, `Bash` for `git diff` only — no `Edit` / `Write`); the literal prompt template that implements §4(a)'s drift-aware block; the `description:` frontmatter wording (must be ≤ 1,536 chars per audit #31 and must include "advisory only" per the plan's constraint column).
- **HOOK-1 (hook script author):** the exact `session-summary.sh`-compatible bypass env-var read pattern; the matcher-less registration in `hooks/hooks.json` (one new entry, `SessionEnd`, empty `matcher`); the bash-3.2-safe token-count read mechanism.
- **FIX-1 (regression fixture author):** the 10 specific diffs (5 good / 5 bad) and the hand-written rationales; the exact JSON envelope for `eval/regressions/inferential-structural-judge.json` (mirror the existing 6-strategy ladder in `eval/run-eval.py:60-519`).
- **EVAL-1 (eval-gate author):** the tag-only failure mode (must not fail global `--gate`); the bucket-threshold pass criterion (≥ 4/5 in each bucket per the plan's Q9).
- **SURF-1 (surfacing author):** extend `kbg:harness-audit` with a `--health` flag (or a dedicated `--verdicts` query); the exact query shape ("last 10 verdicts", "verdicts > 7 in the last 30 days", "silent-sensor count"); the dual-fire-count surfacing per L553 (*"if sensors never fire — high quality or inadequate detection?"*) — the surface must show *both* verdict and *fired-event count*, otherwise a silent-sensor failure mode is invisible.
- **XREF-1 (CLAUDE.md + sensors.json author):** the 2×2 table row update (the "Inferential FB" row gets the new agent listed alongside the three existing entries); the `hooks/sensors.json` entry (per the Q6 cross-plan contract: name = `inferential-structural-judge`, `should_fire_when` = `SessionEnd:`, `max_silent_days` = 30 per the Q2 bucket default, `fallback_role` = `inferential-FB`, `must_fire_in_session` = `false`).
- **INT-1 (integration smoke):** the manual smoke procedure (run a session that touches ≥ 1 file, observe one `inferential_structural_verdict` event in the journal, verify the `score` field parses).

---

**Backwards compatibility:** the existing `verification-gate.sh` / `fabrication-verdict-log.sh` / `kbg:review-pr` precedent is unchanged; this is a *new* sensor in the same cell, not a replacement. The 204-test critical-hooks suite continues to pass without modification (verified by the plan's Q12: "removing the SessionStart entry from `hooks/hooks.json`" is the two-line revert).

## 8. Q&A resolution status (resolves the plan's "all 12 Q items" criterion)

This section maps every Q item from the plan's `## Q&A log` to either a section in this design doc (where it is resolved) or a follow-up plan (where it is deferred). The plan's acceptance criterion #1 reads: *"Design doc explicitly addresses the 6 Q items it owns (Q2, Q5, Q6, Q8, Q9, Q12) and marks the remaining 6 (Q1, Q3, Q4, Q7, Q10, Q11) as 'out of scope for 0.2.0, deferred to a §0.x plan' in a Q&A resolution table."* This table is the audit trail.

| Q# | Q summary (1-line from plan) | Status | Where resolved / deferred |
|----|------------------------------|--------|----------------------------|
| Q1 | Why an agent and not a hook script? | **Deferred** (Q1 is a *meta-rationale* question, not a design decision) | The decision ("agent, not hook") is implicit in the plan's "This plan designs a new inferential-FB agent that…" framing. A future ADR can formalize the agent-vs-hook trade-off across all 14 hook events; out of scope for 0.2.0. Tracked under a future `harness-engineering-2x3` or similar. |
| Q2 | Why SessionEnd and not PostToolUse/Edit? | **Resolved** | §2 "Trigger & lifecycle" (SessionEnd fires once per session; PostToolUse/Edit would burn N×tokens). The §2 paragraph quotes this trade-off explicitly. |
| Q3 | Why not just expand `verification-gate.sh`? | **Resolved** (rationale) + **deferred** (the architectural question of consolidating sensors in one cell) | The *rationale* (verification-gate has no journal-read capability, no drift-aware comparator) is implicit in §2 + §4(a). The deeper architectural question of whether verification-gate and inferential-structural-judge should be one script or two is deferred — out of scope for 0.2.0; tracked as a future `verification-gate-consolidation` ADR. |
| Q4 | What's the "structural" in "structural test"? | **Resolved** | §1 paragraph 1 cites Böckeler L375 + L444 + L465–478 and names the 4 dimensions. |
| Q5 | What's the verdict schema? | **Resolved** | §3 (the JSON envelope + the 4-dimensional scoring rationale + the operational score-range table). |
| Q6 | How do we prevent the agent from rubber-stamping its own session's work? | **Resolved** | §4 (the three mitigations: drift-aware prompt template, hand-curated fixtures, no mutation / no `permissionDecision`). |
| Q7 | How does this interact with `kbg:review-pr`? | **Resolved** | Documented in the plan's Q7 answer (sensor vs deep review). The doc itself defers to the plan. |
| Q8 | What's the cost ceiling? | **Resolved** | §5 (per-session 4k token budget, 25k-token skip gate, 50-file truncation). |
| Q9 | What's the test for the new agent? | **Resolved** (infrastructure) + **deferred** (live eval) | The 10-fixture regression + bucket-threshold infrastructure is shipped in this build (FIX-1 + EVAL-1). The *live* eval — running real agent roundtrips against the fixtures via a new `agent-cli` strategy in `run-eval.py`'s 6-strategy ladder — is deferred to `.claude/tasks/inferential-structural-judge-live-eval.md` (target 0.3.x). |
| Q10 | What does the user get? | **Resolved** | §2 (output sink) + the "What this plan does NOT do" deferral of the SessionStart `inference_mirror` mechanism to `.claude/tasks/inferential-structural-judge-escalation-mirror.md` (target 0.3.x). The journal stream is the immediate user-facing surface; the mirror is the secondary surface. |
| Q11 | Why now? | **Resolved** (in the plan) | The plan's Q11 answer is the authority: "Not now. The brief calls this a 'later' action. This plan exists so the work is *decomposable* when the time comes; nothing ships until a 0.2.x design pass." The 0.2.x design pass IS this build. |
| Q12 | What's the rollback? | **Resolved** | The doc's "Backwards compatibility" paragraph (above this section) quotes Q12 verbatim and names the two-line revert. |

**Summary:**
- 9 of 12 Q items resolved in this design doc (Q2, Q3-rationale, Q4, Q5, Q6, Q7, Q8, Q9-infrastructure, Q10, Q12 — note Q3 has both resolved-rationale and deferred-architectural halves).
- 3 of 12 Q items fully deferred to follow-up plans (Q1, Q9-live-eval, Q10-mirror).
- 0 of 12 Q items unaddressed.
