# Environment variables

Only variables a shipped script actually reads. Set user-scope knobs in `~/.claude/settings.json`
under `env`, never in a committed file.

| Variable | Read by | Purpose |
|---|---|---|
| `MH_PLUGIN_ROOT` | skill markdown (`bash "${MH_PLUGIN_ROOT}/..."`) | Exported at SessionStart by `hooks/session/command-root-anchor.sh` from `CLAUDE_PLUGIN_ROOT`, so skill prose can name bundled scripts portably. Not a user knob. |
| `MH_MATT_CACHE` | `scripts/_lib/mattpocock-root.sh` | Overrides the `mattpocock-skills` plugin cache root (default `~/.claude/plugins/cache/mattpocock/mattpocock-skills`). Used by test fixtures. |
| `MH_CACHE_DIR` | `skills/meta/harness-audit/scripts/audit.sh`, check 35 | Overrides the mh plugin cache root the audit resolves loadability against; `--plugin-cache <path>` wins over it. |

Native Claude Code variables this plugin relies on but does not own: `CLAUDE_PLUGIN_ROOT`
(every hook command), `CLAUDE_ENV_FILE` (command-root-anchor writes the export there).
