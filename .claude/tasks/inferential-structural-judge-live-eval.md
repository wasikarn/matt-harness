---
slug: inferential-structural-judge-live-eval
priority: P3
source: .claude/tasks/inferential-structural-test.md (deferred from EVAL-1)
status: planned (deferred follow-up)
target: kbg-harness 0.3.x (after the 0.2.x inferential-structural-test build lands + ≥ 1 month of real session data accumulates in the journal)
created: 2026-06-15
related: .claude/tasks/inferential-structural-test.md EVAL-1 row, docs/research/inferential-structural-judge-design.md §4(b)
---

# Plan: Live eval for inferential-structural-judge (EVAL-1.5 follow-up)

## Why this is a separate plan, not a wave in the parent

The parent `inferential-structural-test` plan's EVAL-1 row ships the *infrastructure* for bucket-threshold scoring: `TAG_ONLY_TAGS = frozenset({"inferential-structural-judge"})` in `eval/run-eval.py`, the `compute_bucket_threshold()` helper, and the tag-only failure mode. **It does not** wire a real `agent-cli` dispatcher to actually invoke the agent against the synthetic sessions described in the 10 fixtures, because:

1. **Cost.** A real agent roundtrip per fixture × 10 fixtures × multiple iterations = significant token spend. The parent plan runs the gate with stub fixtures; this plan runs the *actual* bucket-threshold eval against a real agent.
2. **Calibration.** The first real run will almost certainly need adjustment — the agent's prompt template may need tuning, the bucket boundaries may shift, etc. Iterating inside the parent plan's tight scope would be expensive.
3. **Volume of data.** A meaningful live eval needs ≥ 1 month of real-session journal data to compare agent verdicts against actual session outcomes (e.g., did the flagged session actually result in a re-roll? a revert? a continuation?). This plan's evaluation metric evolves over time; the parent plan's metric is binary (gate green/red).

## Brain dump

The parent plan's 10 fixtures are currently tagged `manual` and rely on `script-cli` echo commands. The fixtures describe synthetic sessions in prose (e.g. "agent judges a 1-line typo fix in a method comment — expects score in [1, 3]") but never actually invoke the agent. This plan:

1. Lifts the `manual` tag from each fixture.
2. Adds a new `agent-cli` strategy to `eval/run-eval.py`'s 6-strategy ladder (alongside `script-cli`, `harness-audit`, `observe-script`, etc.).
3. Implements the strategy: it reads the fixture's `task` field, assembles a synthetic session in a temp dir (creates a fake transcript.jsonl, fake `~/.claude/governance-events.jsonl`, etc.), invokes the agent via `claude -p --agent inferential-structural-judge`, and parses the resulting verdict JSON.
4. The 10 fixtures' success criteria (`score in [1, 3]` for good, `score in [7, 10]` for bad) are then exercised against the real agent.
5. The bucket-threshold verdict becomes meaningful: ≥ 4/5 in each bucket = PASS.

## Q&A log

1. **Why not include this in the parent plan's EVAL-1 row?** — Cost (1 above), calibration (2), data-volume (3). The parent plan's EVAL-1 ships the *infrastructure*; this plan uses it.
2. **What changes in `eval/run-eval.py`?** — One new `elif skill == "agent-cli":` branch in the 6-strategy ladder. No changes to the existing `TAG_ONLY_TAGS` / `compute_bucket_threshold()` infrastructure.
3. **What's the eval's pass threshold?** — Same as the parent plan's Q9: ≥ 4/5 in each bucket. The parent's "tag-only" annotation remains so a partial-pass doesn't fail the global `--gate`.
4. **What data does the agent actually see?** — A synthetic session transcript (10-50 fake `tool_use` entries) + a synthetic journal (10-50 fake `inferential_structural_verdict` events for "prior verdicts" per design doc §4(a)'s drift-aware template). The synthetic session's diff is the fixture's `task` field rendered into a real `git diff` output.
5. **What does the runner do with a real verdict?** — It populates `_actual_score` (already wired in the parent EVAL-1) from the agent's verdict JSON, and the existing `compute_bucket_threshold()` reports the real bucket-pass count.
6. **What's the cost ceiling per fixture?** — ≤ 1,000 tokens output + ≤ 3,000 tokens input per design doc §5. 10 fixtures × 4,000 tokens = ~40k tokens total per live eval. The plan runs the eval at most weekly.
7. **What about agent drift over time?** — The plan adds a `last_live_eval_at` field to `hooks/sensors.json` for the `inferential-structural-judge` entry, so the staleness-notifier can flag if a live eval hasn't run in 30 days. The eval itself is `script-cli` + `agent-cli` dispatch — no new hooks.
8. **What about calibration drift?** — When the bucket-threshold verdict shifts (e.g., 5/5 in both buckets instead of the expected 4/5), the operator gets a `kbg:state-of-the-harness`-style notice. The fixture rationales are the calibration baseline.

## Team Members

| Name | Role | Agent Type |
|------|------|------------|
| LEAD-D | agent-cli strategy design + fixture-promotion | code-architect |
| LEAD-B | run-eval.py agent-cli branch + synthetic session harness | backend-engineer |
| V | first live eval smoke + drift-verdict sanity check | code-reviewer |

## Step by Step Tasks

| Task ID | Description | Depends On | Assigned To | Files | Criteria | Constraints |
|---------|-------------|------------|-------------|-------|----------|-------------|
| AGENTCLI-1 | Add `agent-cli` strategy to `run-eval.py` 6-strategy ladder | - | LEAD-B | eval/run-eval.py | New `elif skill == "agent-cli":` branch reads fixture's `task`, synthesizes a session in a temp dir, invokes the agent via `claude -p`, parses verdict JSON, populates `_actual_score` | No new dependencies; no `pip install`; no changes to existing branches |
| AGENTCLI-2 | Lift `manual` tag from 10 fixtures, set `skill: "agent-cli"` | AGENTCLI-1 | LEAD-B | eval/regressions/inferential-structural-judge.json | All 10 fixtures have `tags` array without `"manual"` and with `"agent-cli"`; `skill: "agent-cli"`; existing `manual_reason:` fields deleted | Run-eval.py's `manual` short-circuit (`run-eval.py:66-84`) no longer skips them |
| AGENTCLI-3 | Synthetic session harness — render fixture's `task` field into a real session.jsonl + journal.jsonl | AGENTCLI-1 | LEAD-B | eval/run-eval.py (or new harness module) | Given a fixture, the harness creates ≥ 1 fake `tool_use` entry matching the `task`'s described diff; ≥ 1 fake `inferential_structural_verdict` event matching the "prior verdict" pattern in design doc §4(a) | No real user data; no real user transcripts; deterministic seed for reproducibility |
| AGENTCLI-4 | First live eval run + bucket-threshold verdict report | AGENTCLI-1, AGENTCLI-2, AGENTCLI-3 | LEAD-B | eval/results/<date>/summary.json | `python3 eval/run-eval.py --regression --tag inferential-structural-judge --gate` exits 0; bucket-threshold verdict = PASS/FAIL with real numbers; per-fixture detail shows real `score` from agent | Tag-only gate (does not fail global); ≤ 40k tokens total cost; no regressions in other tags' eval results |
| AGENTCLI-5 | Add `last_live_eval_at` field to `hooks/sensors.json` `inferential-structural-judge` entry | AGENTCLI-4 | LEAD-D | hooks/sensors.json | The 32nd sensor entry now has `last_live_eval_at: "2026-XX-XX"`; sibling `sensor-fire-notification` plan's staleness-notifier picks it up | Field name matches the sibling plan's expectation; no breaking changes to existing fields |
| INT-2 | End-to-end: cache-update + restart + manual smoke | AGENTCLI-1, AGENTCLI-2, AGENTCLI-3, AGENTCLI-4, AGENTCLI-5 | LEAD-B | (none) | `claude plugin update kbg@kobig` exits 0; restart → live eval gate is green | run via V validation step |

## Acceptance Criteria

- [ ] AGENTCLI-1: `eval/run-eval.py` has a new `elif skill == "agent-cli":` branch, syntactically valid Python, no new deps
- [ ] AGENTCLI-2: All 10 fixtures have `tags` without `"manual"` and with `"agent-cli"`
- [ ] AGENTCLI-3: Synthetic session harness produces a real session.jsonl + journal.jsonl from a fixture's `task` field, deterministically
- [ ] AGENTCLI-4: Live eval gate exits 0 with bucket-threshold verdict reported; per-fixture `score` populated from real agent output
- [ ] AGENTCLI-5: `hooks/sensors.json` 32nd entry has `last_live_eval_at` field
- [ ] No `permissionDecision` ever emitted by the new strategy (autonomy invariant)
- [ ] No regressions in the existing 31 sensor entries' `last_live_eval_at` absence (i.e., only the 32nd entry gains the field)

## Validation Commands

- `python3 eval/run-eval.py --regression --tag inferential-structural-judge --gate` — live eval gate green
- `bash skills/harness-audit/scripts/audit.sh .` — manifest, schema, descriptions clean
- `bash hooks/tests/test-critical-hooks.sh` — critical-hooks regression
- `git grep -n 'permissionDecision' eval/run-eval.py` — autonomy-invariant scan (expect 0)
- `claude plugin update kbg@kobig` — plugin cache update + restart Claude Code

## What this plan does NOT do

- Does NOT add new dimensions to the agent's verdict schema (the agent's 4 dimensions are fixed per the parent plan's design doc §3)
- Does NOT change the bucket-threshold pass criterion (≥ 4/5 in each bucket is locked per parent plan's Q9)
- Does NOT introduce mutation testing for the agent (separate plan: `mutation-testing.md`)
- Does NOT introduce property-based tests (separate plan: `property-based-tests.md`)
- Does NOT add the `inference_mirror` SessionStart hook (separate plan: `inferential-structural-judge-escalation-mirror.md`)
