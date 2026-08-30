---
name: refactor-clean
description: "Refactor-clean: remove dead code (JS/TS, Python, Go, Rust), verifying tests after each change. Use when cleaning unused code. Don't use for logic refactors."
model: inherit
effort: low
---

# Refactor Clean

Safely identify and remove dead code with test verification at every step. Delegates to the `refactor-cleaner` agent, which owns the detect → categorize → safe-delete → consolidate procedure across JS/TS (knip/depcheck/ts-prune), Python (vulture), Go (deadcode), and Rust (cargo-udeps).

## Usage

Optionally name a target path when invoking this skill; defaults to the current project.

## Output Contract

The agent returns:

1. Items deleted, grouped by category (unused exports / files / dependencies / duplicates).
2. Items skipped, with the reason (test failed, dynamic import, public API, uncertain).
3. Test status before and after — verify green both times before keeping a deletion.
4. Lines saved.
5. **Suggested next step:**
   - Deletions landed, tests green → `mattpocock-skills:code-review` before shipping the removal.
   - Nothing safe to remove → done.