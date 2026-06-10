# kbg — Claude Code harness (plugin)

`kbg` packages a personal Claude Code harness as an installable plugin: senior-specialist
subagents, workflow skills, slash commands, governance hooks, always-on doctrine injection
(METHODOLOGY / RTK / ACLI / DBGATE), and the TECH-LEAD-THAI output style.

## Install

```
/plugin marketplace add <this-repo>
/plugin install kbg@kobig
```

Components are namespaced — invoke as `/kbg:<command>` and `/kbg:<skill>`.

## Components

| Dir | What |
|---|---|
| `agents/` | 27 senior-specialist subagents |
| `skills/` | 25 workflow skills (`_lib/` holds shared shell helpers, not a skill) |
| `commands/` | 8 slash commands |
| `hooks/` | governance hooks + always-on doctrine injection |
| `output-styles/` | TECH-LEAD-THAI |
| `themes/` | catppuccin-mocha |

## External dependencies

Some hooks shell out to external tools (`rtk`, `qmd`, `memory-lint`). They degrade gracefully
when those tools are absent — the hook affected is skipped, the session is unaffected.

## License

MIT — see `LICENSE`.
