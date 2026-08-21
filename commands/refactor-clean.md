---
description: Safely identify and remove dead code (JS/TS, Python, Go, Rust) with test verification after each change. Delegates to the refactor-cleaner agent.
name: refactor-clean
model: inherit
effort: low
---

# Refactor Clean

Safely identify and remove dead code with test verification at every step. Delegates to the `refactor-cleaner` agent, which owns the detect → categorize → safe-delete → consolidate procedure across JS/TS (knip/depcheck/ts-prune), Python (vulture), Go (deadcode), and Rust (cargo-udeps).

## Usage

`/refactor-clean [path]`

- `path` (optional): defaults to the current project.

## Output Contract

The agent returns:

1. Items deleted, grouped by category (unused exports / files / dependencies / duplicates).
2. Items skipped, with the reason (test failed, dynamic import, public API, uncertain).
3. Test status before and after (all green required to keep a deletion).
4. Lines saved.
5. Suggested next step: deletions landed, tests green → kbg:review-pr before shipping the removal; nothing safe to remove → done.

## Arguments

$ARGUMENTS:
- optional target path