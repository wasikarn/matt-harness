---
description: "Cost-report: local Claude Code spend from the cost-tracker metrics log. Use when checking session spend. Don't use for scheduling or budget alerts (none exist)."
name: cost-report
argument-hint: "[csv]"
model: inherit
effort: low
---

# Cost Report

Print and read back the spend summary that the plugin's own Stop hook accumulates in
`~/.local/share/kbg/metrics/costs.jsonl`. It covers every session on this machine that ran
with the `stop:cost-tracker` hook, across all projects, with subagent spend split out by agent
type. Native `/usage` (alias `/cost`) covers the live session per model and, on a subscription, a
24h/7d attribution share; this is the per-day, per-agent-type dollar history it lacks.

## Run

One Bash call. The script reads the log, dedups it, and prints the report; do not open the
log yourself or add up rows by hand.

```bash
node "${CLAUDE_SKILL_DIR}/scripts/cost-report-dedup.js"
```

`/cost-report csv` appends `csv` and prints the last 100 raw rows instead of the summary.

`MH_COSTS_FILE=<path>` points the script at another log; use it only when the user or the
task names a log outside the default location.

If the file is missing, the script prints `Cost tracker not set up` and exits 0. Relay that
line: the log fills after the first session ends with the hook enabled. Do not invent numbers.
If `node` is missing, say so; the report has no other runtime.

## Read back

Quote the script's numbers as printed. Add only what a reader needs to interpret them:

- **Whole machine, not this project.** Every project writes to the same log and the report never
  groups by project. Compare a trend over days, not one total against another project.
- **`warning:` lines mean unknown, not zero.** A session listed there had only `jq_failed`
  sentinel rows (the tracker's jq pass died); it is left out of every total, so say its spend
  is unknown rather than reading the total as complete.
- **`note:` lines first.** Rows written before 2026-09-04 summed tokens per transcript line,
  so their turns, tokens, and cost run about 2.4x high; a short run after that kept a streaming
  placeholder and reads about 39% low on output. The script does not rewrite either era, so a
  total that mixes eras is a ceiling, not a bill. Say which note applies before quoting `total`.
- **`(rate unverified)` means guessed.** A Claude model the tracker has no rate table for is
  priced at the Sonnet rate. Rank those models by the `tok` column, not by dollars.
- **Non-Claude models are history.** Proxy-served models (minimax, glm, kimi, nemotron) only
  appear in rows from before 2026-08-07; the tracker drops them now.
- **Subagent spend starts 2026-08-07.** Earlier rows are orchestrator-only, so a before/after
  difference across that date is a schema change, not a spending change.
- **Codex invocations are counts.** Codex exposes no local per-call price, so that section
  never has a dollar column; it is absent until a session has used `codex:*`.
- **Handoff cost (2026-09-20+ rows) prices reading a subagent's return.** Median/p90 tokens
  main spends per subagent return (`verify_tokens`), plus returns per orchestrator turn. Rows
  before this restore carry no `verify_per_return` and the section is omitted if none do.

Never re-estimate prices from raw tokens. `estimated_cost_usd` is the tracker's number; the
rate table lives in `hooks/stop/cost-tracker.sh` and changes there.

## Data model and dedup rule

Row schema, the three legacy eras, and the aggregation key the report must keep are in
`references/data-model.md`. The rule that must not regress: for each session, keep the latest
row per (`session_id`, `stream`, `model`, `agent_type`) and sum across keys; a legacy row with
no `stream` counts as `orchestrator`. `tests/skills/test-cost-report.sh` pins every element of
that key with a wrong-answer fixture; run it after any change to the script.
