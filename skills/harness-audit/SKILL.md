---
name: harness-audit
description: "Harness-state surface, two modes: fleet/schema audit, --health for session token cost. Use for harness audits or cost checks. Don't use for repo lint/security (kbg:security-auditor)."
---

# Harness Audit

Single harness-state surface with two modes:

- **Default (audit)** — deterministic fleet/schema/structural check. Detects drift before it becomes a silent failure.
- **--health mode** — per-session token cost from the live cost ledger (formerly `kbg:harness-health`). See `references/health.md`.

## Mode selection

| User asks for | Mode | Entry |
|---|---|---|
| "audit harness", "fleet check", "manifest drift", Thai: 'audit harness', 'ตรวจ harness' | audit (default) | `bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh"` |
| "harness health", "token cost", "session cost", Thai: 'harness health', 'สุขภาพ harness' | --health | `bash "${CLAUDE_SKILL_DIR}/scripts/health.sh"` or `python3 "${CLAUDE_SKILL_DIR}/scripts/harness-health.py" ...` |


## Quick start

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh"
```

Produces exit code = count of findings. Zero = clean.

## What it checks

| Check | Finding type |
|---|---|
| **Fleet count** | Count agents, skills, commands, hooks |
| **Loadability** | Every repo artifact is loadable by Claude Code (plugin cache or symlink) |
| **Frontmatter completeness** | `name`, `description`, `tools` (agents), `disable-model-invocation` (commands) |
| **Name/filename consistency** | Frontmatter `name` matches directory/file name |
| **Tool-grant scoping** | Agents have explicit `tools:` (no inherit-all) |
| **Orphaned hooks** | Hook files in repo but not wired in `settings.json` |
| **Orphaned skills** | Skills in repo but not loadable by Claude Code |
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
| **Test-honesty / tautology** | Test files (`*.test.*`, `test_*.py`, `*_test.py`) lack greppable anti-patterns: tautological `assert True/False`, identity/repr assertions, `test_<placeholder>` names, `pass`/`,` skeletons (tests that can't fail when logic changes are wrong) |

The bottom nine are validated against `code.claude.com/docs` (hooks 31-event set,
skills/sub-agents 1536-char limit, model-config aliases). They are **WARN**, not
CRIT: vendor docs lag features, so an unrecognized event or type may be
real-but-undocumented — flagged for a human, not failed (Rule 1; surfaced, not silently dropped).

## Output

```
=== Skill Audit Report ===
Fleet: <n> agents, <n> skills, <n> commands, <n> hooks

CRITICAL:
  F1: probe skill not loadable by Claude Code
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
the plugin cache at runtime, not via a symlink. The audit emits an
`INFO` line confirming plugin-mode is active. Components that are neither
symlinked **nor** plugin-delivered still fire F1 (the genuine-drift case).
The cache path can be overridden with `--plugin-cache <path>` (used by the
test fixtures in `tests/harness-audit/fixtures/`, which point at fake caches so the F1
check is exercised without a live install). The live cache version is
auto-detected via `ls ~/.claude/plugins/cache/kobig/kbg/ | sort -V | tail -1` — do not hardcode.

## Integration

Run in CI, pre-commit, or after any fleet change:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh" || echo "Audit failed"
```

Wire into a post-fleet-change hook for continuous enforcement.

## Extending checks

Add a new check as its own file under `scripts/checks/`, named `NN-slug.sh` (2-digit prefix,
hyphen, then a short slug — `audit.sh`'s loader globs `checks/[0-9][0-9]-*.sh` and dot-sources
each match into its own shell process, so a wrong extension or separator means the check silently
never runs). Call the shared `crit "<message>"` / `warn "<message>"` / `info "<message>"`
functions to report a finding — they increment the shared `CRIT_COUNT`/`WARN_COUNT`/`INFO_COUNT`
totals `audit.sh` aggregates at the end; a check does not print its own formatted line for
`audit.sh` to parse.

- `crit` — requires immediate fix
- `warn` — should fix but not blocking
- `info` — expected behavior, document only

After adding a check, bump the integrity guard's expected count (`_exp_ids` near the end of
`audit.sh`) in the same commit — it fails closed if the check count doesn't match.

## References

- `references/health.md` — full `--health` mode contract (formerly `kbg:harness-health`).

## Completion criterion

The audit ran to completion (exit code = finding count, not a script crash) and every CRIT finding
was either fixed and re-verified with a clean re-run, or explicitly accepted with a documented
reason. Reading the summary line after a fix, without re-running the audit, is not done — a typo in
the fix itself only shows up on the re-run.

## Failure modes

- **WARN read as pass.** Exit code is a raw finding count, not a pass/fail bit — a WARN-only run
  still exits nonzero. Check the CRIT/WARN/INFO breakdown, not just "exit 0 or not."
- **Stale `--plugin-cache` override.** F1's plugin-aware skip auto-detects the live cache version
  via `sort -V | tail -1` — a manually-passed `--plugin-cache` pointing at a stale version
  reintroduces the false F1s the auto-detection exists to avoid.
- **Fixing without re-running.** A finding is only closed once the audit re-runs clean on it —
  editing the file and assuming the fix landed skips the one step that would catch a mistake in the
  fix itself.

## METHODOLOGY alignment

- **Independent checks:** every check runs independently; one failure doesn't mask others.
- **Fail loud:** exit code = finding count; zero is the only silent success.
