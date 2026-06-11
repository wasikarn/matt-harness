---
name: harness-audit
description: "Automated audit of the custom Claude Code skills/agents/commands/hooks ecosystem — symlink, frontmatter, plugin-cache loadability. Use when harness-audit reports CRITICAL, after editing agents/skills/commands/hooks, or when F1 fires on plugin-delivered components. Don't use for: writing new skills (use skill-creator), implementation work (use /feature-dev or /backend-dev), or security audits (use /security-auditor)."
---

# Skill Audit

Run a deterministic health check across the custom Claude Code ecosystem. Detects drift before it becomes a silent failure.

## Quick start

```bash
bash ~/.claude/skills/harness-audit/scripts/audit.sh
```

Produces exit code = count of findings. Zero = clean.

## What it checks

| Check | Finding type |
|---|---|
| **Fleet count** | Count agents, skills, commands, hooks |
| **Symlink integrity** | Every repo artifact symlinked to `~/.claude/` |
| **Frontmatter completeness** | `name`, `description`, `tools` (agents), `disable-model-invocation` (commands) |
| **Name/filename consistency** | Frontmatter `name` matches directory/file name |
| **Tool-grant scoping** | Agents have explicit `tools:` (no inherit-all) |
| **Orphaned hooks** | Hook files in repo but not wired in `settings.json` |
| **Orphaned skills** | Skills in repo but not symlinked to `~/.claude/skills/` |
| **Routing table coverage** | All agents referenced in `orchestrate` routing table |
| **Memory index drift** | All `.md` references in `MEMORY.md` exist |
| **Boundary drift** | `BOUNDARY.md` matches the live fleet (regenerate if stale) |
| **Bundled script syntax** | Every `.py` / `.sh` under a skill compiles / parses |
| **Bundled JSON validity** | Every `.json` under a skill parses |
| **Duplicate tools** | Same tool listed twice in an agent's `tools:` |
| **Placeholder residue** | "Daisy" or other upstream placeholders |
| **PyCache tracked** | `__pycache__/` or `*.pyc` accidentally git-tracked |
| **Description length** | Skill/agent/command `description` ≤ 1536 chars (runtime truncates over-limit) |
| **Agent model value** | `model:`, if present, is an alias (`sonnet`/`opus`/`haiku`/`inherit`) or a `claude-*` ID |
| **Hook event name** | Each `settings.json` hook event is in the documented 31-event set |
| **Hook handler type** | Each handler `type` is one of `command`/`http`/`mcp`/`agent`/`prompt` |
| **Hook matcher regex** | Each `matcher` (other than `*` / `""` wildcards) compiles as a regex |
| **Hook context length** | Static `additionalContext` ≤ 10000 chars |
| **Name format** | Skill/agent `name` is lowercase/digits/hyphens, ≤ 64 chars |
| **Tool-grant tokens** | Each agent `tools:` token is a real Claude Code tool (typo guard) |
| **Eval-target freshness** | Every `**/evals.json` / baseline-eval driver carries a `last_reviewed:` (or `last_reviewed_reason:` to defer); older than 180d emits info (#30) |
| **Skill-ref resolution** | Each agent `skills:` ref resolves to a repo or installed skill |
| **Test-honesty / tautology** | Test files (`*.test.*`, `test_*.py`, `*_test.py`) lack greppable anti-patterns: tautological `assert True/False`, identity/repr assertions, `test_<placeholder>` names, `pass`/`,` skeletons (Rule 9) |

The bottom nine are validated against `code.claude.com/docs` (hooks 31-event set,
skills/sub-agents 1536-char limit, model-config aliases). They are **WARN**, not
CRIT: vendor docs lag features, so an unrecognized event or type may be
real-but-undocumented — flagged for a human, not failed (Rule 1 / Rule 12).

## Output

```
=== Skill Audit Report ===
Fleet: 27 agents, 26 skills, 8 commands, 32 hooks

CRITICAL:
  F1: probe skill not symlinked to ~/.claude/skills/
  F2: qmd-reindex.py exists in hooks/ but not wired in settings.json

WARNINGS:
  W1: inventory skill missing 'Don't use for' in description

INFO:
  I1: commands derive name from filename (no name: frontmatter) — expected

Exit: 2
```

## Plugin delivery (F1 is plugin-aware)

When `kbg@kobig` is enabled and its plugin cache is populated
(`~/.claude/plugins/cache/kobig/kbg/<version>/{agents,skills,commands,hooks,output-styles}/`),
F1 ("not symlinked to `~/.claude/…`") treats plugin-delivered components as
loadable and does **not** fire — Claude Code resolves them via
`${CLAUDE_PLUGIN_ROOT}` at runtime, not via a symlink. The audit emits an
`INFO` line confirming plugin-mode is active. Components that are neither
symlinked **nor** plugin-delivered still fire F1 (the genuine-drift case).
The cache path can be overridden with `--plugin-cache <path>` (used by the
test fixtures in `tests/fixtures/`, which point at fake caches so the F1
check is exercised without a live install). The live cache version is
auto-detected via `ls ~/.claude/plugins/cache/kobig/kbg/ | sort -V | tail -1` — do not hardcode.

## Integration

Run in CI, pre-commit, or after any fleet change:

```bash
bash ~/.claude/skills/harness-audit/scripts/audit.sh || echo "Audit failed"
```

Wire into a post-fleet-change hook for continuous enforcement.

## Extending checks

Add new checks to `audit.sh` in the order they appear. Each check emits:

- `[CRIT] <id>: <message>` — requires immediate fix
- `[WARN] <id>: <message>` — should fix but not blocking
- `[INFO] <id>: <message>` — expected behavior, document only

## METHODOLOGY alignment

- **Rule 10 (Checkpoint):** every check runs independently; one failure doesn't mask others.
- **Rule 12 (Fail loud):** exit code = finding count; zero is the only silent success.
