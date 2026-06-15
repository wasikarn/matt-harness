---
slug: inferential-structural-test
priority: P2
source: .scratch/research/harness-engineering-2026-04.md §"Actionable changes" #4
status: planned (research, not build)
target: kbg-harness 0.2.x (after 0.1.18 description-trim lands)
created: 2026-06-15
related: ADR 0002 §L112 (verification-gate.sh advisory invariant), sensor-fire-notification.md
---

# Plan: Inferential structural-test layer for kbg-harness

## Brain dump

Böckeler's `harness-engineering` article punts on the **behaviour harness** (L465–478): "we still have a lot to do." The closest the article offers is the **approved-fixtures** pattern (Lexler) — goldens for AI outputs — and mutation testing as a *quality monitor*, not a *solution*.

kbg-harness currently has:
- **Computational FB** — 204 critical-hooks tests + 38 audit checks (the load-bearing enforcement layer)
- **Inferential FB, advisory only** — `verification-gate.sh` (SessionEnd), `fabrication-verdict-log.sh` (Stop), `kbg:review-pr` (command, manual trigger)

The gap: no **automatic** inferential FB on a diff that asks "is this over-engineered?" / "does this introduce architectural drift?" / "is the test pattern reverting to agent-slop?" Today those are *tasks* (`kbg:review-pr`), not *sensors* (run on every commit, journal verdicts, surface drift).

This plan designs a new inferential-FB agent that:
- Runs on **SessionEnd** (advisory — never emits `permissionDecision`, per ADR 0002)
- Journals verdicts to the existing JSONL contract
- Is **non-blocking** (autonomy-invariant-safe)
- Costs at most ~1k tokens per session (per `METHODOLOGY.md` "Token Budgets Are Not Advisory" Rule 6)

The agent is the *new sensor* that `sensor-fire-notification.md` will register in `hooks/sensors.json` (Q6 verdict: registry = runtime ground truth; sibling plan adds its own entry when this lands). Its verdicts feed the future `harness-coverage-metric.md` aggregator.

## Q&A log

1. **Why an agent and not a hook script?** — Hooks are deterministic. The whole point of inferential FB is *semantic* judgment. An agent is the right shape. Cost is the trade.
2. **Why SessionEnd and not PostToolUse/Edit?** — SessionEnd fires once per session; PostToolUse/Edit would burn N×tokens per session. The article's "shift feedback left" is the wrong axis here — we want *coverage*, not *speed*, and coverage of architectural drift is cumulative.
3. **Why not just expand `verification-gate.sh`?** — `verification-gate.sh` is a single-context pass; it has no memory of the previous session's verdicts. A new agent can journal *and* read the journal (cumulative drift signal).
4. **What's the "structural" in "structural test"?** — Borrowed from the article's L375 example ("ArchUnit tests that check for violations of module boundaries") and L444 ("duplicate code, cyclomatic complexity, missing test coverage, architectural drift, style violations"). We are not building ArchUnit for Markdown plugins — we are asking the agent to *judge* the same dimensions against the diff.
5. **What's the verdict schema?** — TBD; candidate: `{score: 1-10, dimensions: {over_engineering, arch_drift, test_pattern, doctrine_conformance}, top_finding: str, recommendation: 'accept'|'flag'|'escalate'}`.
6. **How do we prevent the agent from rubber-stamping its own session's work?** — LLM-judge-circularity (Böckeler L356–359, L393). The agent's *prompt* must be templated to include the diff + the *prior* session's verdict for the same files, so the judge is at least *aware* of its own drift. The deeper fix is a *different model class* (Opus judge, Sonnet generator) — but that costs the F8 model split benefit.
7. **How does this interact with `kbg:review-pr`?** — `kbg:review-pr` is the *deep* review (manual trigger, full context, multiple passes). The new agent is the *sensor* (auto, per-session, shallow). They are complements, not substitutes.
8. **What's the cost ceiling?** — `METHODOLOGY.md` Rule 6 = 4k tokens/task, 30k/session. The new agent must run within the *session* budget, not add a per-call budget. If the session is already at 25k, the agent skips and journals a "skipped: budget" event.
9. **What's the test for the new agent?** — A regression fixture: 5 known-good diffs (verdict < 4) and 5 known-bad diffs (verdict > 7), with hand-written rationales. Eval fixture lives at `eval/regressions/inferential-structural-judge.json`. The agent's pass criterion = ≥ 4/5 in each bucket. Note: this is the *exact* test-quality problem the article warns about (L476: "we put a lot of faith into the AI-generated tests, that's not good enough yet") — hand-curated, not agent-generated, is the mitigation.
10. **What does the user get?** — A `~/.scratch/journal/inferential-structural-verdicts.jsonl` stream, queryable via `kbg:state-of-the-harness` (or a new `kbg:harness-health` command). Drift becomes visible.
11. **Why now?** — Not now. The brief calls this a "later" action. This plan exists so the work is *decomposable* when the time comes; nothing ships until a 0.2.x design pass.
12. **What's the rollback?** — `disable-model-invocation: true` on the agent's `SKILL.md` frontmatter, plus removing the SessionStart entry from `hooks/hooks.json`. Two-line revert. Verified by 204-test critical-hooks suite (which checks the *absence* of a verdict event is not a fail). Companion: `hooks/sensors.json` gets this agent's entry added (per Q6 cross-plan contract); remove the entry to silence the staleness-notifier from flagging it.

## Team Members

| Name | Role | Agent Type |
|------|------|------------|
| LEAD-D | Agent prompt template + design doc author | code-architect |
| LEAD-B | Hook wiring + fixture + eval-gate builder | backend-engineer |
| V | Lint + critical-hooks + audit + eval validator | code-reviewer |

## Step by Step Tasks

| Task ID | Description | Depends On | Assigned To | Files | Criteria | Constraints |
|---------|-------------|------------|-------------|-------|----------|-------------|
| DOC-1 | Resolve Q5 (verdict schema) and Q6 (circularity mitigations) in design doc | - | LEAD-D | docs/research/inferential-structural-judge-design.md | Schema field set, 3 mitigations, cost ceiling (Q8) explicit; LLM-judge-circularity section cites Böckeler L356–359 | No speculative configurability (METHODOLOGY Rule 2); no `permissionDecision` (ADR 0002) |
| AGENT-1 | Author the agent file | DOC-1 | LEAD-B | agents/inferential-structural-judge.md | `description:` ≤ 1536 chars (audit #31); has `## Input Contract`, `## Output Format`, `## Failure Modes` (audit #31.1); `tools:` allowlist, no `disallowedTools:` (decay-cadence convention) | Description includes "advisory only" trigger |
| HOOK-1 | Wire the SessionStart hook (SessionEnd trigger, journal emit) | DOC-1, AGENT-1 | LEAD-B | hooks/inferential-structural-judge-on-session-end.sh, hooks/hooks.json | Bash 3.2 compat (zsh 5.9 OK); degrades on agent absent (`command -v`); emits JSONL event per `JOURNAL-SCHEMA.md` | Hook is *matcher-less* SessionStart to match the doctrine-bootstrap pattern |
| FIX-1 | Author the regression fixture | DOC-1, AGENT-1 | LEAD-B | eval/regressions/inferential-structural-judge.json | 10 hand-curated diffs (5 good / 5 bad) with hand-written rationales; eval strategy follows existing 6-strategy ladder in `run-eval.py:60-519` | No agent-generated rationale (defeats Q9's circularity test) |
| EVAL-1 | Add to `eval/run-eval.py --gate` | FIX-1 | LEAD-B | eval/run-eval.py (or a new fixture-loader) | `python3 eval/run-eval.py --regression --tag inferential-structural-judge --gate` exits 0 on 0.2.x; ≥ 4/5 in each bucket | Tag-only gate, no global failure |
| SURF-1 | Surface in `kbg:state-of-the-harness` (or new `kbg:harness-health`) | AGENT-1, HOOK-1, FIX-1, EVAL-1 | LEAD-B | skills/state-of-the-harness/SKILL.md (extend) or new skill | Querying "last 10 verdicts" returns the JSONL stream; surfacing a session with verdict > 7 prints the rationale | Per the article's "If sensors never fire — high quality or inadequate detection?" (L553), the surface must show *both* verdict and *fired-event count* |
| XREF-1 | Update `CLAUDE.md` 2×2 table + add `sensors.json` registry entry for the new agent | DOC-1, AGENT-1 | LEAD-D | CLAUDE.md, hooks/sensors.json | The "Inferential FB" row now lists the new agent alongside `verification-gate.sh`, `fabrication-verdict-log.sh`, `kbg:review-pr`; sensors.json entry has correct Q2 bucket defaults (SessionEnd = 30 days) | Q6 cross-plan contract: sibling plan registers this agent |
| INT-1 | End-to-end: cache-update + restart + manual smoke (run session, observe verdict in journal) | AGENT-1, HOOK-1, FIX-1, EVAL-1, SURF-1, XREF-1 | LEAD-B | (none) | `claude plugin update kbg@kobig` exits 0; restart → SessionEnd emits 1 verdict event | run via V validation step |

## Acceptance Criteria

- [ ] DOC-1: Design doc explicitly addresses the 6 Q items it owns (Q2, Q5, Q6, Q8, Q9, Q12) and marks the remaining 6 (Q1, Q3, Q4, Q7, Q10, Q11) as "out of scope for 0.2.0, deferred to a §0.x plan" in a Q&A resolution table. validation_command: grep -cE 'Q[0-9]+' docs/research/inferential-structural-judge-design.md  (count must be ≥ 12 — one reference per Q item)
- [ ] AGENT-1: agent has frontmatter `description: ...` ≤ 1536 chars, no `disallowedTools:`, has all 3 canonical SKILL sections (audit #31.1) validation_command: bash skills/harness-audit/scripts/audit.sh .
- [ ] HOOK-1: Hook script is shellcheck-clean and 204/204 critical-hooks tests still pass validation_command: bash hooks/tests/test-critical-hooks.sh
- [ ] FIX-1: 10 hand-curated fixtures, all 10 with hand-written rationales (no agent-generated text) validation_command: jq '.evals | length' eval/regressions/inferential-structural-judge.json
- [ ] EVAL-1: eval gate exits 0 validation_command: python3 eval/run-eval.py --regression --tag inferential-structural-judge --gate
- [ ] INT-1: harness-audit exits 0C/0W (or 0C/0W/1I — only the I1 plugin-cache info) validation_command: bash skills/harness-audit/scripts/audit.sh .
- [ ] DOC-1: design doc includes LLM-judge-circularity mitigation section citing Böckeler L356–359 validation_command: grep -c 'L356' docs/research/inferential-structural-judge-design.md
- [ ] XREF-1: CLAUDE.md 2×2 row updated to include the new agent validation_command: grep -c 'inferential-structural-judge' CLAUDE.md
- [ ] No `permissionDecision` ever emitted by the new agent or its hook (verified by 0 matches) validation_command: git grep -n 'permissionDecision' hooks/inferential-structural-judge-on-session-end.sh agents/inferential-structural-judge.md

## Validation Commands

- `bash skills/harness-audit/scripts/audit.sh .` — manifest, schema, descriptions
- `bash hooks/tests/test-critical-hooks.sh` — critical-hooks regression
- `python3 eval/run-eval.py --regression --tag inferential-structural-judge --gate` — eval gate green
- `claude plugin validate --strict .` — manifest valid (the new agent is a plugin-surface change → version bump required)
- `git grep -n 'permissionDecision' hooks/inferential-structural-judge-on-session-end.sh agents/inferential-structural-judge.md` — autonomy-invariant scan (expect 0)
- `claude plugin update kbg@kobig` — plugin cache update + restart Claude Code

## What this plan does NOT do

- Does NOT introduce mutation testing (separate plan: `mutation-testing.md`)
- Does NOT introduce property-based tests (separate plan: `property-based-tests.md`)
- Does NOT change `verification-gate.sh` (the existing advisory FB is the precedent; this plan extends the pattern, not the existing script)
- Does NOT add a `disallowedTools:` block (per decay-cadence convention)
- Does NOT auto-prune the existing 38 hook scripts (separate `decay-cadence` work)
- Does NOT auto-mutate `hooks/sensors.json` (Q6: registry is hand-curated; this plan adds its own entry as part of XREF-1, but the registry remains human-curated)
- **Does NOT wire a real `agent-cli` dispatcher for the bucket-threshold eval (EVAL-1.5 follow-up).** The tag-only gate passes (exit 0) by design (this plan's Q9 + EVAL-1 row), and the bucket-threshold infrastructure (`TAG_ONLY_TAGS` + `compute_bucket_threshold()`) is in place. The follow-up that lifts the `manual` tag from each fixture, adds an `agent-cli` strategy to the 6-strategy ladder, and runs real agent roundtrips against synthetic sessions is a separate plan: `inferential-structural-judge-live-eval.md` (target 0.3.x).
- **Does NOT add the SessionStart `inference_mirror` mechanism for score ≥ 7 escalations.** The escalation channel is *documented* in design doc §3 as "mirror to next SessionStart's `additionalContext`" but the wiring of the receiving hook is a separate plan. The current build's SessionEnd hook only journals; a future plan adds a SessionStart hook that reads the latest escalation event and injects it as `additionalContext` if `score ≥ 7`. Tracked under `inferential-structural-judge-escalation-mirror.md`.
