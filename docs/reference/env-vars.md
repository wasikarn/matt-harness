# Environment variables

Only variables a shipped script actually reads. Set user-scope knobs in `~/.claude/settings.json`
under `env`, never in a committed file.

| Variable | Read by | Purpose |
|---|---|---|
| `MH_PLUGIN_ROOT` | `skills/workflow/ideate/references/provenance.md` (doc reads only) | Exported at SessionStart by `hooks/session/command-root-anchor.sh` from `CLAUDE_PLUGIN_ROOT`. No skill runs a script through it any more; an eval sandbox may not run the hook. Not a user knob. |
| `MH_COSTS_FILE` | `skills/meta/cost-report/scripts/cost-report-dedup.js` | Overrides the cost log path (default `~/.local/share/kbg/metrics/costs.jsonl`); tests and evals plant a fixture through it. |
| `MH_GATE_JOURNAL_PATH` | `hooks/gates/_journal.py` | Overrides the gate-verdict journal path (default `~/.local/share/kbg/metrics/gate-decisions.jsonl`); `scripts/run-gauntlet.sh` and every standalone-runnable gate test suite set it to an isolated tmp path so local test runs don't pollute the operator's real journal. |
| `MH_CACHE_DIR` | `skills/meta/harness-audit/scripts/audit.sh`, check 35 | Overrides the mh plugin cache root the audit resolves loadability against; `--plugin-cache <path>` wins over it. |
| `MH_CODEX_DATA_DIR` | `scripts/_lib/codex-state-path.sh`, check 71 | Overrides the paired `codex@openai-codex` plugin's per-plugin data root (default: `~/.claude/plugins/data/codex-openai-codex`) that check 71 reads the review-gate state from. Test-only: points the self-test at a throwaway directory instead of the real, shared one. |
| `MH_CODEX_CACHE_DIR` | check 72 | Overrides the paired `codex@openai-codex` plugin's cache dir (default: newest `~/.claude/plugins/cache/openai-codex/codex/<version>/`) that check 72 reads `VALID_REASONING_EFFORTS` from. Test-only. |
| `MH_FRAGMENTS_DEBUG` | `hooks/sensors/fragments-capture.sh` | Set to `1` to trace each decision point (why a capture did or didn't fire — not armed, window expired, no match, publish race) to stderr. Silent by default; a user knob for debugging the writing-fragments pointer-capture sensor, not read by any other script. |

Native Claude Code variables this plugin relies on but does not own: `CLAUDE_PLUGIN_ROOT`
(every hook command), `CLAUDE_SKILL_DIR` (set while a skill body runs; `harness-audit`,
`memory-lint`, and `cost-report` invoke their bundled scripts through it, so it works in an eval
sandbox where no SessionStart hook ran), `CLAUDE_ENV_FILE` (command-root-anchor writes the export there),
`CLAUDE_PLUGIN_DATA` — observed as `~/.claude/plugins/data/<plugin>-<marketplace>/`, consistent
across every installed plugin on this machine; not documented by Claude Code, and mh doesn't
read it directly (check 71 hardcodes the resolved default instead, since `audit.sh` runs as a
bare `bash` invocation with the env var unset outside an actual plugin-hook context).
