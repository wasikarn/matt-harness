# kbg — Claude Code harness (plugin)

`kbg` packages a personal Claude Code harness as an installable plugin: senior-specialist
subagents, workflow skills, slash commands, governance hooks, always-on doctrine injection
(METHODOLOGY / RTK / ACLI / DBGATE), and the TECH-LEAD-THAI output style.

## Install

```
/plugin marketplace add BIG-TATHEP/kbg-harness
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

Some hooks shell out to external tools (`rtk`, `qmd`, `memory-lint`, `code-review-graph`). They
degrade gracefully when those tools are absent — the hook affected is skipped, the session is
unaffected. No MCP or LSP servers are bundled.

## For external installers

This is a **personal harness**, not a general-purpose toolkit. If you enable `kbg`, every session
inherits the owner's doctrine (`METHODOLOGY` / `RTK` / `ACLI` / `DBGATE`) as mandatory context, plus
the Thai-code-switched `TECH-LEAD-THAI` output style. That's intentional — there is no opt-in flag.
If the conventions don't fit you:

- **Use components without enabling the plugin** — install the marketplace and invoke individual
  `/kbg:<command>` / `/kbg:<skill>` / agents without enabling `kbg` (no doctrine injection fires).
- **Disable it** — `"kbg@kobig": false` in `settings.json`, or `/plugin disable kbg`.
- **Fork and adapt** — remove `doctrine-bootstrap.sh` from `hooks/hooks.json`, swap the output style.

No support SLA; best-effort, pre-`1.0.0`. See `docs/ARCHITECTURE.md` for the delivery model and
`CHANGELOG.md` for release notes.

## License

MIT — see `LICENSE`.
