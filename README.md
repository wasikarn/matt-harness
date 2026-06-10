# kbg — Claude Code harness (plugin)

`kbg` packages a personal Claude Code harness as an installable plugin: senior-specialist
subagents, workflow skills, slash commands, governance hooks, always-on doctrine injection
(METHODOLOGY / RTK / ACLI / DBGATE), and the TECH-LEAD-THAI output style.

## Install

```
/plugin marketplace add wasikarn/kbg-harness
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

## Requirements

**Required**

| Need | Why | Without it |
|---|---|---|
| Claude Code **≥ v2.1.154** | honors `defaultEnabled: false` (opt-in) | older builds ignore the flag and enable `kbg` by default |
| `python3` | doctrine injection JSON-escapes via `python3`; two governance hooks use it | doctrine does **not** inject; those hooks no-op |
| `git` | git-aware skills/hooks (`/kbg:review-pr`, dangerous-git guard, review markers) | git workflows unavailable; other components unaffected |

Standard `bash` / `grep` / `sed` are assumed. `jq` is used for audit journaling and self-guards if missing.

**Optional integrations** — each hook below guards with `command -v` and silently no-ops when the tool
is absent (no error, no "hook error" notice). Install separately to unlock the feature:

| Tool | Unlocks | Fires on |
|---|---|---|
| `rtk` | token-optimized Bash proxy (60–90% savings) | every Bash call |
| `code-review-graph` | review-context graph (status + incremental update) | SessionStart, post-edit |
| `qmd` | local markdown-search reindex | Edit / Write |
| Superset (`$SUPERSET_HOME_DIR`) | agent-activity notifications | env-gated |

These are external tools / MCP servers, **not bundled** and **not required** — the core (agents,
skills, commands, doctrine, governance hooks) runs without any of them. Audit hooks append logs to
`~/.claude/*.log` and `~/.claude/governance-events.jsonl` on your machine; `chmod 700 ~/.claude` if
other local users shouldn't read them.

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
