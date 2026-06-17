---
name: fixture-skill
description: "Fixture skill for harness-audit tests. Use when validating F1 fires on a non-symlinked, non-plugin-delivered skill. Don't use for: real work — this is a test fixture. Don't use for: anything outside the harness-audit test suite."
---

# Fixture skill

A minimal skill that exists only to prove the harness-audit F1 check is
not silently disabled under the new plugin-aware code path. Has neither
a `~/.claude/skills/fixture-skill` symlink nor an entry in the kbg@kobig
plugin cache, so F1 must fire.
