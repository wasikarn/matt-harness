# Eval Harness

Systematic evaluation before ship. Held-out datasets + regression fixtures + gating.

## Directory Layout

```
eval/
├── README.md              # This file
├── SCHEMA.md              # Dataset + fixture schema
├── run-eval.py            # Entry point
├── datasets/              # Held-out task descriptions (≥3 required)
│   ├── 7-agent-pattern.json
│   ├── accept-task.json
│   ├── article-mine.json
│   ├── commands.json
│   ├── harness-audit.json
│   ├── memory-trim.json
│   ├── progressive-refine.json
│   ├── recursive-improve.json
│   ├── review-pr.json
│   ├── ship-change.json
│   ├── task-sizing.json
│   ├── triage.json
│   ├── types-first.json
│   └── usage-monitor.json
├── fixtures/              # Expected outputs / assertions
│   └── acceptance-pass.json
├── regressions/           # Known failure patterns that must not recur
│   └── loop-overshoot.json
└── results/               # Generated per-run (timestamped subdirs)
```

## Usage

```bash
# Run all datasets (works from any CWD when KBG_PLUGIN_ROOT is exported)
python3 "${KBG_PLUGIN_ROOT}/eval/run-eval.py" --dataset "${KBG_PLUGIN_ROOT}/eval/datasets/"

# Run only regressions (fast smoke test)
python3 "${KBG_PLUGIN_ROOT}/eval/run-eval.py" --regression

# Gate mode: exit non-zero on failure (for CI)
python3 "${KBG_PLUGIN_ROOT}/eval/run-eval.py" --dataset "${KBG_PLUGIN_ROOT}/eval/datasets/" --gate
```

## Adding a Dataset

1. Create `eval/datasets/<name>.json` matching the schema in `SCHEMA.md`.
2. Add at least 3 cases per dataset.
3. Run `python3 "${KBG_PLUGIN_ROOT}/eval/run-eval.py" --dataset "${KBG_PLUGIN_ROOT}/eval/datasets/" --gate` to verify.

## Adding a Regression Fixture

1. Create `eval/regressions/<name>.json` with `expected_failure: true`.
2. The harness verifies the task still fails (i.e., the bug has not recurred).
3. If the task starts passing, the fixture flags a **regression detected**.
