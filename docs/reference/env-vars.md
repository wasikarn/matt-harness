# Environment variables — kbg-harness reference

Every operator-tunable env var the harness reads, with its default and the surface that reads it.
Re-derive the live set with:

```bash
/usr/bin/grep -rhoE 'KBG_[A-Z0-9_]+' --include='*.sh' --include='*.py' hooks/ skills/ scripts/ | sort | uniq -c | sort -rn
```

**Scope:** this lists the **user-facing knobs** only. Internal bash→python IPC vars
and the vendor path vars Claude Code injects (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_SKILL_DIR`,
`CLAUDE_PROJECT_DIR`, `CLAUDE_SESSION_ID`) are implementation detail — set nothing, read nothing.

## Where to set them (scope safety)

Claude Code's settings `env` block injects vars into the session **and the subprocesses it spawns,
including hooks** (verified against the settings docs). Scope precedence is **Local
(`.claude/settings.local.json`) > Project (`.claude/settings.json`) > User (`~/.claude/settings.json`)**.
That makes *user-global* settings reach **every repo you open** — so the home depends on the key's class:

| Key class | Settable where | Why |
|---|---|---|
| **Tuning** (`KBG_IDEATE_*`) | User-global `env` is fine — but only override one you *actually* change often (defaults are sensible; pre-populating a default just creates drift). | No safety impact; convenience only. (On some setups `~/.claude/settings.json` is a symlink into a dotfiles repo — `readlink -f` it before editing; if so, that edit commits to *that* repo, not this one.) |
| **Safety-gate config** (`KBG_GUARDED_WORKSPACE`) | User-global `env` is the *only* placement that reliably reaches every session — a multi-repo client workspace typically has no per-sub-repo `.claude/settings.json` of its own, so a project-scoped setting at the workspace root is never read when a session opens directly in a sub-repo. | Unset = the gate is a total no-op (the shipped default for every user of this public plugin). This is deliberately NOT documented as a value in this repo — it names a real path outside the plugin's own source. |

## Autonomy flags — RETIRED 2026-06-26 (ADR 0006)

The `KBG_AUTONOMY` arming key, the `KBG_REVIEW_DONE` Gate-2 override, and the old per-level
`KBG_AUTONOMY_L3` / `KBG_L3_REVIEW_DONE` names are all retired. There is no autonomy flag and no
enforced maker-checker ship-gate. The harness denies the irrecoverable set computationally (the
PreToolUse gates in `hooks/gates/`, no operator flag) and advises on the rest; the operator is the
authority at every irreversible boundary. Do not re-arm.

## Worktree-guard cluster (opt-in, off by default)

Read by `hooks/gates/worktree-guard.py` (redirects Edit/Write off a protected main
checkout into a session worktree) and the `bash -c` early-exit wrapper around it in
`hooks/hooks.json`. This gate ships generic — no client name or workspace path in this
repo's source — and is a **total no-op for every user of this public plugin** unless
`KBG_GUARDED_WORKSPACE` is explicitly set.

| Var | Default | Effect |
|---|---|---|
| `KBG_GUARDED_WORKSPACE` | **none — gate is off when unset** | Absolute path to the workspace root to protect. Must be absolute: the gate's own kill-switch (`classify()` in `worktree-guard.py`) treats an unset or non-absolute value as "off", not "guard the current directory" — a relative/empty value resolving via `realpath` to the current working tree was the exact bug this guards against. |
| `KBG_WORKTREE_ROOT` | `~/.worktrees` | Where auto-created session worktrees live. Generic default, never client-specific. |
| `KBG_WORKTREE_BASE` | unset (current HEAD) | Branch to fetch and base a new worktree on, e.g. `=main` for a hotfix session. |
| `KBG_ALLOW_MAIN_EDIT` | unset | One-off escape hatch: `=1` skips the guard for the current call. Not a standing config value — don't pre-populate it in `env`. |

## Token-optimization settings (set in `~/.claude/settings.json` → `env`)

Recommended values for context/cost efficiency, sourced from ECC token-optimization guide:

| Var | Recommended | Effect |
|---|---|---|
| `MAX_THINKING_TOKENS` | `10000` | Extended thinking reasoning budget; current live default is already `10000` (the older `31,999` "ultrathink" ceiling was a prior Claude Code version — confirmed against `code.claude.com/docs/en/env-vars`, 2026-07-31). Setting it to `10000` today is a no-op, not a cost-cutting change. Set to `0` to disable extended thinking for trivial tasks; raise it above 10000 if a task needs deeper reasoning than the default budget. Toggle with **Option+T** (macOS). |
| `CLAUDE_CODE_SUBAGENT_MODEL` | (per current fleet) | Model for subagents spawned via the Task tool. Pick a cheap tier for exploration/file reading; switch the main session to a stronger model for complex reasoning without changing this. |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `50` | Compacts at 50% context used instead of the CC default 95%. Compacts **earlier** = better summarization quality in long sessions. ECC recommended. |

Use the right model per task mid-session:
```
/model haiku    # quick lookups, file reading
/model sonnet   # day-to-day coding (default)
/model opus     # complex architecture, multi-step reasoning
```

## Context Window Management (ECC, stale — see correction below)

The section below is the original ECC token-optimization guidance and predates Claude Code's
current default: MCP tool search. Confirmed live against `code.claude.com/docs/en/mcp`
("Scale with MCP tool search") and `docs/en/costs` ("Reduce MCP server overhead"),
2026-07-31 (`docs/research/official-docs-audit-2026-07-31.md`) — with tool search on (the
default), only tool names + server instructions load at session start; full schemas defer
until Claude actually searches for and uses a tool. Anthropic states explicitly: "Claude Code
doesn't impose a fixed per-server tool cap; the practical limit is your context window
budget." The specific numeric limits below (10 servers / 80 tools, linear scaling) describe
the pre-tool-search architecture and should not be treated as current hard limits. Sonnet 5's
default context window is also 1M, not 200k (see Model Configuration above) — re-derive the
"fully-loaded setup" estimate against whichever window is actually active.

Each loaded MCP server's tool descriptions still consume some tokens (tool names + server
instructions, upfront) — a very large server count is still worth trimming for cleanliness,
just not because of the linear-scaling/hard-cap math below.

**Historical limits this section originally recommended (now stale, kept for context):**
- ~~10 MCP servers active — beyond this, tool-description overhead is measurable~~
- ~~80 tools total active — token cost scales linearly with tool count~~

Use `/mcp` in-session to disable unused servers if you notice real context pressure. Prefer
keeping heavy-schema MCPs (Figma, Atlassian, MongoDB) inactive unless actively needed.

**Agent teams cost:** each teammate agent consumes tokens independently. Agent teams are opt-in and off by default — set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"` to enable them; `"0"` (or unset) keeps them off, it doesn't disable an active default.

### Strategic Compaction

Use `/compact` at **logical breakpoints** — don't rely on auto-compaction at 95%.

| Compact? | When |
|---|---|
| ✅ Yes | After research/exploration, before implementation |
| ✅ Yes | After completing a milestone, before starting the next |
| ✅ Yes | After debugging, before continuing feature work |
| ✅ Yes | After a failed approach, before trying a new one |
| ❌ No | Mid-implementation (you'll lose variable names, file paths, partial state) |

Context management is native: use the `/compact` command and auto-compaction.

## Special — infrastructure vars (not user knobs)

- **`KBG_PLUGIN_ROOT`** — deliberate alias of the vendor `CLAUDE_PLUGIN_ROOT`, re-exported so docs and
  scripts resolve the plugin root from any working directory (the vendor var is only set inside hook
  shells). ~483 references; treat as fixed infrastructure.
- **`KBG_CACHE_DIR`** — plugin cache directory used by the gauntlet/audit scripts.
- **`KBG_GAUNTLET_PLUGIN_CACHE`** — cache path override for `run-gauntlet.sh` validation.
- **`CLAUDE_PLUGIN_ROOT`** / **`CLAUDE_SKILL_DIR`** / **`CLAUDE_PROJECT_DIR`** / **`CLAUDE_SESSION_ID`** —
  vendor-injected path vars; implementation detail, set nothing.