---
name: build-fix
description: "Detect the project build system and incrementally fix build/type errors with minimal safe changes. Use when a build or type-check is failing. Delegates to the build-error-resolver agent. Don't use for logic bugs (mattpocock-skills:diagnosing-bugs)."
model: inherit
effort: low
---

# Build and Fix

Incrementally fix build and type errors with minimal, safe changes. Delegates to the `build-error-resolver` agent, which owns the detect → parse/group → fix-one-at-a-time → guardrail procedure across npm/tsc, Cargo, Maven, Gradle, Go, and Python.

## Usage

Optionally name a target path when invoking this skill; defaults to the current project.

## Output Contract

The agent returns:

1. Errors fixed, with file paths.
2. Errors remaining, if any.
3. New errors introduced (should be zero).
4. Unresolved issues, if any — with a suggested next step per issue.
5. If no unresolved issues remain: suggested next step — a compiling build is not a passing one, run the test suite / mh:test-coverage before continuing.
