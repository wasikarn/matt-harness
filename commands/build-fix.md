---
description: Detect the project build system and incrementally fix build/type errors with minimal safe changes. Delegates to the build-error-resolver agent.
name: build-fix
agent: build-error-resolver
subtask: true
---

# Build and Fix

Incrementally fix build and type errors with minimal, safe changes. Delegates to the `build-error-resolver` agent, which owns the detect → parse/group → fix-one-at-a-time → guardrail procedure across npm/tsc, Cargo, Maven, Gradle, Go, and Python.

## Usage

`/build-fix [path]`

- `path` (optional): defaults to the current project.

## Output Contract

The agent returns:

1. Errors fixed, with file paths.
2. Errors remaining, if any.
3. New errors introduced (should be zero).
4. Suggested next steps for unresolved issues.

## Arguments

$ARGUMENTS:
- optional target path
