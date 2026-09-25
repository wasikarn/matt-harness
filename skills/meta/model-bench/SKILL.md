---
name: model-bench
description: "Compares two models' scored eval performance on the same case set via claude plugin eval --model, reusing existing graders. Use when choosing between models."
argument-hint: "<model-a> <model-b> [-- <claude plugin eval args>]"
disable-model-invocation: true
disable-model-invocation-reason: launches paid claude plugin eval runs — the user decides when to spend judge-token cost, not the model
model: inherit
effort: low
---

# Model Bench

Run this repo's own eval suite twice, once per subject model, and diff the scores. Reuses the
rubric machinery, judge panel, and grader files that already exist under `evals/` — this adds no
new judging logic, only a labeled side-by-side comparison of two `claude plugin eval` runs.

Invoke explicitly: `/mh:model-bench`. Not model-invoked — this spends real judge-token cost, so
the user decides when to run it, not the model.

## Scope: this compares models only cleanly on skill/prompt-driven cases

Cases whose `prompt.md` dispatches a subagent (`subagent_type:` in the prompt, or a
`graders/agent-fired.md` in the case dir) run that subagent at its `agents/*.md`
frontmatter-pinned model regardless of `--model`. Whether `--model` reaches subagent dispatch
inside the eval sandbox is **unverified** — no live eval has been run to check it, since doing so
spends judge cost. The report prints how many compared cases are agent-dispatch cases so this
caveat reaches the output itself, not just this doc.

**The CLI `--effort` flag never reaches the eval child — a re-probe corrected an earlier, wrong
conclusion here.** The 2026-09-25 probe above only inspected the OUTER `claude plugin eval`
process's own `--debug-file`, which is that process's own startup log, not the eval child's
per-turn trace — it never actually observed the child's resolved effort at all. A same-day
re-probe (`code-architect-trivial-no-dispatch`, `--keep-temp`, reading the child's own
`config/projects/**/*.jsonl` session transcript, which carries `effort`/`perTurnEffort` on every
assistant turn) found:
- `--model opus`, parent `--effort xhigh` → child resolves `effort: "medium"` — Opus 5.5's own
  documented default, not "high" and not "xhigh". The earlier "fixed effort: high" conclusion was
  really just sonnet's own default effort observed on a single model, mistaken for a harness-wide
  constant.
- The parent's `--effort` flag genuinely never reaches the child under either model — confirmed
  again here.
- **`CLAUDE_CODE_EFFORT_LEVEL=low` in the invoking shell's environment DOES reach the child**:
  `--model sonnet` with that env var set resolved every turn to `effort: "low"` (sonnet's default
  is otherwise "high") — a real, working propagation route the CLI flag doesn't have.

So a `model@effort` arm syntax IS implementable — just not via `--effort`; it needs
`CLAUDE_CODE_EFFORT_LEVEL=<level>` set on the child's environment per arm. Not yet built pending
an explicit go-ahead (a design decision, not a doc fix). Re-verify with the same `--keep-temp` +
child-transcript method (not the outer `--debug-file`) before trusting any future claim here.

## Run

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/model-bench.sh" <model-a> <model-b> [-- <claude plugin eval args>]
```

Runs `claude plugin eval` twice — once per model — then prints a labeled comparison. Any
`claude plugin eval` flags after `--` pass straight through to both runs (`--tag`, `--case`,
`--scaffold`, `--allow-tools`, etc.). Unless already present in those passthrough args, the
wrapper adds three defaults:

- `--ablation none` — the default `with-without` doubles cost and, if the plugin is
  `defaultEnabled: false`, can silently compare a disabled-plugin baseline instead of the models.
- `--threshold 0` — the CLI default (1.0) makes `claude plugin eval` exit 1 on any normal run;
  the wrapper treats exit 1/2 as "ran, proceed to diff" regardless, but this avoids the noise.
- `--max-cost-usd 5` — a conservative ceiling per arm. Override with your own `--max-cost-usd` in
  the passthrough args.

To diff two already-completed runs without spending anything new:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/model-bench.sh" --diff-only \
  --label-a <name> --label-b <name> \
  <result-a>/aggregate-result.json <result-b>/aggregate-result.json
```

## Reading the report

- **Hard-fail** (no comparison printed): either side has a `suite.plugins[].problem` (plugin
  didn't load as expected), or either side has `partial: true` (a cost/turn ceiling cut the run
  short — its score covers a different, smaller case set and isn't comparable).
- **WARN, but still compared**: a mismatch in judge model, case filter, ablation mode, Claude
  Code version, or plugin version between the two sides. Read the warning before trusting the
  delta — it means the two runs aren't apples-to-apples on that axis.
- **Not comparable section**: any case name present on only one side (different `--tag`/`--case`
  filters between the two arms, most often).

Never re-derive scores by hand from the raw JSON; the script's numbers are the source of truth for
this comparison. `aggregate-result.json` never records which model produced a run — the label the
script prints is the only place that information exists, so always pass real model names, not
placeholders.
