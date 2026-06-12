# kbg — Claude Code harness (plugin)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![validate-plugin](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml/badge.svg)](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml)

Personal Claude Code harness delivered as a Claude Code plugin — 27 senior-specialist
subagents, 26 workflow skills, 8 slash commands, governance hooks, and always-on doctrine
injection. See [`CONTEXT.md`](CONTEXT.md) for the bounded-context model and the autonomy
invariant.

## Install

```
/plugin marketplace add wasikarn/kbg-harness
/plugin install kbg@kobig
```

**Verify** with `/plugin list` (look for `kbg@kobig`), then run any slash command
(e.g. `/kbg:review-pr --help`) to confirm components load.

The plugin is **opt-in** (`defaultEnabled: false`) — nothing injects until you enable it
in `settings.json`. Components are namespaced as `/kbg:<command>` and `/kbg:<skill>`
once enabled.

**Uninstall** with `/plugin uninstall kbg`. To keep installed but disable:
`"kbg@kobig": false` in `settings.json`, or `/plugin disable kbg`.

## What you get

| Dir | What |
|---|---|
| `agents/` | 27 senior-specialist subagents (engineer, reviewer, security, …) |
| `skills/` | 26 workflow skills (`_lib/` holds shared shell helpers, not a skill) |
| `commands/` | 8 slash commands (`feature-dev`, `fix-bug`, `ship-merge`, …) |
| `hooks/` | governance hooks across 14 lifecycle events + always-on doctrine injection |
| `output-styles/` | `TECH-LEAD-THAI` (Thai-code-switched register, see `output-styles/TECH-LEAD-THAI.md`) |
| `themes/` | `catppuccin-mocha` |

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
- **Fork and adapt** — remove `doctrine-bootstrap.sh` from `hooks/hooks.json`, swap the output style,
  edit the doctrine files in place.

No support SLA; best-effort, pre-`1.0.0`. The full delivery rationale lives in
[`docs/adr/0001-personal-harness-as-plugin.md`](docs/adr/0001-personal-harness-as-plugin.md).

## Documentation

**First time here?** Start with [`docs/onboarding.md`](docs/onboarding.md) (10-min cold-start).

Supporting docs:

- [`docs/onboarding.md`](docs/onboarding.md) — 10-minute cold-start (≤500 tokens)
- [`CONTEXT.md`](CONTEXT.md) — domain language, autonomy invariant, delivery model
- [`METHODOLOGY.md`](METHODOLOGY.md) — 13-rule behavioral doctrine
- [`CHANGELOG.md`](CHANGELOG.md) — release notes (Keep-a-Changelog, SemVer)
- [`AGENTS.md`](AGENTS.md) — issue-tracker / triage-label conventions
- [`docs/adr/0001-personal-harness-as-plugin.md`](docs/adr/0001-personal-harness-as-plugin.md) — why "personal harness as plugin"
- [`docs/harness-decay-cadence.md`](docs/harness-decay-cadence.md) — build-to-delete / permission re-audit cadence
- [`docs/agents/verification-trail.md`](docs/agents/verification-trail.md) — verification-trail schema
- [`docs/agents/domain.md`](docs/agents/domain.md) — bounded-context dispatch
- [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md) — `.scratch/<slug>/` working dir
- [`RTK.md`](RTK.md), [`ACLI.md`](ACLI.md), [`DBGATE.md`](DBGATE.md) — always-on doctrine
- [`BOUNDARY.md`](BOUNDARY.md) — auto-regenerated cross-context inventory
- [`hooks/JOURNAL-SCHEMA.md`](hooks/JOURNAL-SCHEMA.md) — governance evidence journal schema

## License

MIT — see [`LICENSE`](LICENSE).
