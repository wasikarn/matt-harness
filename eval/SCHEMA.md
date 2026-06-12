# Eval Schema

## Dataset Entry

```json
{
  "id": "ship-change-with-review-comments",
  "task": "Address 3 review comments on a PR",
  "skill": "ship-change",
  "context": {
    "files_changed": ["src/api.py", "tests/test_api.py"],
    "review_comments": [
      {"file": "src/api.py", "line": 42, "body": "Add input validation"}
    ]
  },
  "success_criteria": [
    "All review comments are addressed",
    "No new lint errors introduced",
    "CI passes"
  ],
  "expected_duration_seconds": 120,
  "expected_tokens": 8000,
  "tags": ["ship-change", "review", "regression"],
  "eval_type": "assertion"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Unique slug (kebab-case). |
| `task` | yes | Human-readable task description. |
| `skill` | yes | Skill under test (maps to `skills/<skill>/`). |
| `context` | no | Arbitrary JSON context passed to the evaluator. |
| `success_criteria` | yes | List of strings; checked by assertion or human. |
| `expected_duration_seconds` | no | Soft budget; exceeded → warning, not failure. |
| `expected_tokens` | no | Soft budget; exceeded → warning, not failure. |
| `tags` | no | Classification for filtering (`--tag`). |
| `eval_type` | yes | `assertion` (machine-graded) or `human` (requires review). |

## Regression Fixture

Same schema as dataset, plus:

```json
{
  "expected_failure": true,
  "failure_pattern": "infinite-loop-retry",
  "fixed_by": "commit-sha-or-pr"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `expected_failure` | yes | `true` — the task must still fail (bug not yet fixed) or `false` — must pass (bug fixed, guard against recurrence). |
| `failure_pattern` | yes | Human-readable description of the known bug. |
| `fixed_by` | no | Reference to the fix (commit SHA, PR, or issue). |

## Result Record

```json
{
  "run_id": "2026-06-12T14-23-00Z",
  "dataset_id": "ship-change-with-review-comments",
  "result": "passed",
  "details": {
    "duration_seconds": 98,
    "tokens_used": 7200,
    "criteria_met": 3,
    "criteria_total": 3
  }
}
```

| `result` | Meaning |
|----------|---------|
| `passed` | All criteria met. |
| `failed` | ≥1 criterion unmet. |
| `skipped` | `eval_type: human` and no human reviewer assigned. |
| `warning` | Soft budget exceeded; criteria met. |
| `regression` | Regression fixture started passing when it should still fail (or vice versa). |
