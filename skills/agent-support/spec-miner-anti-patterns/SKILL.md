---
name: spec-miner-anti-patterns
description: Catalog of spec-miner's 10 Anti-Patterns FAIL list. Auto-loads when spec-miner runs. Don't use for other agents or standalone spec authoring.
metadata:
  origin: kbg
model: inherit
effort: high
---

# Spec-Miner Anti-Patterns Reference

Extracted from `agents/spec-miner.md` (2026-08-18, harness-audit check 51 threshold) to keep
the agent body under 20,000 chars. Loaded via that agent's `skills:` frontmatter field (preloaded
at spawn, independent of the Skill tool — `spec-miner` carries no `Skill` tool grant) — this file
is the anti-pattern reference, not a separately-triggered pass.

## Anti-Patterns

- FAIL: Creating type-classification chapters ("## Business Rules", "## API Contracts") instead of flat `### Requirement:` blocks
- FAIL: Describing file structure instead of behavior ("has a controllers/ folder")
- FAIL: Copying docstrings verbatim without cross-validating against callers
- FAIL: Mining every module at once — spec rot starts when specs outpace usage
- FAIL: Writing specs for generated code or vendored dependencies
- FAIL: Guessing at behavior because the code is hard to read — use `<!-- uncertainty: -->`
- FAIL: Creating Requirements without `entities` or `enforced` metadata — unsearchable spec is dead spec
- FAIL: Using `###` for anything other than `Requirement:` or `Invariant:` — breaks OpenSpec delta compatibility
- FAIL: Reading every file in a large module instead of using sample-and-expand — wastes tokens and hits context limits
- FAIL: Recording `depends_on` / `triggers` for cross-module or async event-driven relationships — those are not statically traceable

Done when none of the 10 bullets above describes what this mining pass just did.
