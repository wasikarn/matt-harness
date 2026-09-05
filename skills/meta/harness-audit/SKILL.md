---
name: harness-audit
description: "Deterministic structural audit of the plugin's agents, skills, and hooks. Use when asked to audit the harness or check drift. Don't use for repo lint."
model: inherit
effort: medium
---

# Harness Audit

Runs 30 structural checks over `agents/`, `skills/`, and `hooks/` and reports CRIT / WARN / INFO.
Exit code = CRIT count; WARN and INFO never change it.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh"            # full run
bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh" --only 25  # one check by number
```

## What it checks

| Area | Checks |
|---|---|
| Loadability | 02 skills, 03 hooks + agents (plugin cache or symlink) |
| Frontmatter | 04 agents (name, description, bucket enum), 05 skills (name, description, bucket dir, trigger clause), 28 strict YAML, 54 model + effort present |
| Names | 07/08 name matches filename, 23 lowercase-hyphen format |
| Agent tool grants | 09 explicit `tools:`, 10 no duplicates, 24 real tool tokens, 41 never `Agent`, 32 reviewers stay read-only |
| Preloads | 25 `skills:` refs resolve, 49 reviewer preloads present (CRIT) |
| Hooks | 11 no orphaned hook files, 22 hooks.json event / type / matcher validity, 33 `${CLAUDE_PLUGIN_ROOT}` not `CLAUDE_PLUGIN_DIR` |
| Bundled files | 17 python compiles, 18 shell parses, 19 JSON parses |
| Descriptions | 20 <= 1536 chars each, 29 no imperative injection words, 43 cumulative listing budget |
| Size caps | 51 agent body, 55 LOC cap on auto-loaded surfaces |
| Doc rot | 35 script pointers in prose resolve, 42 reference files carry no leaking frontmatter |

Vendor-validated limits (1536-char descriptions, hook event set, model aliases, name format) are
WARN, not CRIT: vendor docs lag features, so an unrecognized value is flagged for a human.

## Plugin delivery

When `mh@wasikarn` is installed, components load from
`~/.claude/plugins/cache/<marketplace>/mh/<version>/` with no symlink; the audit picks the
highest installed version automatically. `--plugin-cache <path>` overrides it (used by the
fixtures under `tests/skills/harness-audit/known-bad/`); `MH_CACHE_DIR` overrides the cache root.

## Extending checks

Add `scripts/checks/NN-slug.sh` (two-digit prefix, hyphen, slug; the loader globs
`checks/[0-9][0-9]-*.sh`) with a `# NN. <title>` header line. Call `crit`, `warn`, or `info`
with a message; never print your own summary line. Then add `NN` to `_exp_ids` near the end of
`audit.sh` in the same commit: the integrity guard fails closed on any lost, duplicated, or
unlisted fragment. Pair a new check with a known-bad and known-good fixture in
`tests/skills/harness-audit/known-bad/` and an assertion in `test-harness-audit.sh`.

## Completion criterion

The audit ran to completion (a `=== Summary` block, not a crash) and every CRIT was either fixed
and confirmed by a clean re-run, or accepted with a written reason. Editing a file without
re-running is not done.

## Failure modes

- **Fixing without re-running.** A typo in the fix only shows up on the re-run.
- **Stale `--plugin-cache`.** A hand-passed old version reintroduces the loadability CRITs the
  auto-detection exists to avoid.
- **Green because empty.** A check that globs a directory that no longer exists passes vacuously;
  when a surface type is removed, remove or retarget its check.
