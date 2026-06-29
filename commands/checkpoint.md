---
description: Record and list named session checkpoints (timestamp + git SHA).
name: checkpoint
---

# Checkpoint Command

Session-scoped metadata logger for named checkpoints.

## Usage

`/checkpoint [create|list] [name]`

## Create Checkpoint

Log a named checkpoint with timestamp and current git SHA:

```bash
echo "$(date +%Y-%m-%d-%H:%M) | $CHECKPOINT_NAME | $(git rev-parse --short HEAD)" >> .claude/session-checkpoints.log
```

Session checkpoints are **not** git snapshots — use native `git stash`, `git commit`, or `git tag` for actual state capture.

## List Checkpoints

Show all checkpoints for this session:
- Name
- Timestamp
- Git SHA

## Arguments

$ARGUMENTS:
- `create <name>` - Create named checkpoint
- `list` - Show all checkpoints
