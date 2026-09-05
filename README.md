# matt-harness

A small Claude Code plugin (`mh@wasikarn`) that keeps only what native Claude Code and the
installed plugins (`mattpocock-skills`, `ponytail`, `diagram-design`, `qmd`) cannot do:
a short set of deny gates, a 4 KB methodology injected at session start, and a few
skills and agents that earned their place.

## What it enforces (5 gates, `hooks/pretooluse-table.json`)

| gate | effect |
|---|---|
| `gate:bash:irrecoverable` | denies `rm -rf`, `find -delete`, `--no-verify`, `push --force`, `reset --hard`, `clean -f`, discarding `restore`/`checkout`, `branch -D`, `stash drop/clear`, `commit --amend`, `dd`, SQL `DROP`, `git add -A` outside a merge, nested `claude` spawns from a subagent |
| `gate:bash:subagent-git-guard` | denies `git stash`/`reset`/`clean` from a dispatched subagent |
| `gate:task:complete-separation` | denies a subagent marking its own task complete |
| `gate:write:test-integrity` | asks before a write that weakens a test |
| `gate:write:config-guard` | asks before a write to Claude Code settings `hooks`/`enabledPlugins` |

One PreToolUse entry (`hooks/dispatch-pretooluse.sh`) fans out to every matching gate in
parallel and merges by Claude Code precedence (deny > ask > allow). A gate that exceeds 8 s is
killed and counted as allow, journaled.

## What it injects

`docs/METHODOLOGY.md` (under 4 KB) at SessionStart: the decision-sizing triad, interrogate the
claim, bug fix = failing test first, context economy and delegation (5 agents per wave, fresh
validator for anything touching 2+ files, `NEEDS-DECISION` instead of guessing), score not feel.
`hooks/session/injection-budget-check.sh` warns if session-start output passes 8192 bytes.

## What it ships

- **Skills:** `mh:harness-audit` (30 structural checks), `mh:memory-lint`, `mh:cost-report`,
  `mh:deep-audit`, `mh:ideate`, `mh:post-mortem`, `mh:tech-humanize`, 6 stack pattern references
  (backend, frontend, TypeScript, Drizzle, MySQL, gRPC), 7 agent-support preloads.
- **Agents (12):** backend-architect, blind-spot-hunter, code-architect, ideate-critic,
  nextjs-reviewer, performance-optimizer, plan-reviewer, requirement-analyst, security-reviewer,
  silent-failure-hunter, summarizer, typescript-reviewer. Reviewers are read-only and never
  grant `Agent`.
- **Stop hooks:** `cost-tracker.sh` (per-session token cost to `~/.local/share/kbg/metrics/costs.jsonl`),
  `memory-audit-commit.sh` (commits a git-backed memory store, opt-in).

## How this plugin maps to a 6-layer harness

| layer | where it lives in mh |
|---|---|
| 1 Task contract | `docs/reference/spawn-brief.md` + the `NEEDS-DECISION` sentinel |
| 2 Context compiler | `docs/METHODOLOGY.md` (4 KB map) + `CLAUDE.md` + `hooks/session/injection-budget-check.sh` |
| 3 Tool gateway | `hooks/pretooluse-table.json` + `hooks/dispatch-pretooluse.py` (deny > ask > allow; table load failure = deny; a gate timeout = allow) |
| 4 Durable state | native auto-memory owns it; mh adds `skills/meta/memory-lint` + `costs.jsonl` |
| 5 Evidence gate | `scripts/run-gauntlet.sh` + `skills/meta/harness-audit` + gates `test-integrity` and `task-complete-separation` (maker never grades own work) |
| 6 Trace + recovery | `hooks/stop/cost-tracker.sh` + `skills/workflow/post-mortem` |

Source: "Harness Engineering: Build a Reliable AI Agent in 6 Layers" (2026-08-30).

## Install

```text
/plugin marketplace add wasikarn/matt-harness
/plugin install mh@wasikarn
claude plugin enable mh@wasikarn                 # from a terminal

# Required: matt-pocock's skills as their own plugin (routed by name, not bundled)
/plugin marketplace add mattpocock/skills
/plugin install mattpocock-skills@mattpocock

# Restart Claude Code, then once per project you want the harness active in:
/mattpocock-skills:setup-matt-pocock-skills

/mh:cost-report                                  # smoke test; skills are namespaced /mh:<name>
claude plugin list                               # both plugins "enabled"
```

The plugin ships `defaultEnabled: false`; add `"mh@wasikarn": true` to `settings.json` if
`enable` did not. Same-version edits never reach the cache: bump `plugin.json` before
`claude plugin update`. Uninstall: `/plugin uninstall mh@wasikarn`.

## Development

```bash
claude plugin validate . --strict
bash skills/meta/harness-audit/scripts/audit.sh
bash scripts/run-gauntlet.sh
git config core.hooksPath git-hooks   # relative path; pre-commit = fast gate, pre-push = gauntlet
```

Repo map and gotchas: `CLAUDE.md`. Design: `docs/reference/operating-model.md`. Frozen history:
`docs/research/`, `docs/post-mortems/`, `docs/plans/`. Pre-rebuild tree: git tag
`pre-rebuild-v0.68.673`.

## Attribution

Built on [mattpocock/skills](https://github.com/mattpocock/skills) (MIT), installed as its own
plugin and routed to by name. Mental-model catalog names from
[TJBoudreaux/cc-thinking-skills](https://github.com/TJBoudreaux/cc-thinking-skills) (MIT),
pointing upstream for write-ups. Earlier versions also adapted material from
[affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code),
[JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman),
[ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd), and
[thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) (all MIT/Apache-2.0); see the
`pre-rebuild-v0.68.673` tag for what was kept from each.

## License

MIT. See [`LICENSE`](LICENSE).
