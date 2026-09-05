# Environment variables

Only variables a shipped script actually reads. Set user-scope knobs in `~/.claude/settings.json`
under `env`, never in a committed file.

| Variable | Read by | Purpose |
|---|---|---|
| `MH_PLUGIN_ROOT` | skill markdown (`bash "${MH_PLUGIN_ROOT}/..."`) | Exported at SessionStart by `hooks/session/command-root-anchor.sh` from `CLAUDE_PLUGIN_ROOT`, so skill prose can name bundled scripts portably. Not a user knob. |
| `MH_CACHE_DIR` | `skills/meta/harness-audit/scripts/audit.sh`, check 35 | Overrides the mh plugin cache root the audit resolves loadability against; `--plugin-cache <path>` wins over it. |
| `MH_CODEX_DATA_DIR` | `scripts/_lib/codex-state-path.sh`, check 71 | Overrides the paired `codex@openai-codex` plugin's per-plugin data root (default: `~/.claude/plugins/data/codex-openai-codex`) that check 71 reads the review-gate state from. Test-only: points the self-test at a throwaway directory instead of the real, shared one. |

Native Claude Code variables this plugin relies on but does not own: `CLAUDE_PLUGIN_ROOT`
(every hook command), `CLAUDE_ENV_FILE` (command-root-anchor writes the export there),
`CLAUDE_PLUGIN_DATA` — observed as `~/.claude/plugins/data/<plugin>-<marketplace>/`, consistent
across every installed plugin on this machine; not documented by Claude Code, and mh doesn't
read it directly (check 71 hardcodes the resolved default instead, since `audit.sh` runs as a
bare `bash` invocation with the env var unset outside an actual plugin-hook context).
