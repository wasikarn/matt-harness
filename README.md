# matt-harness — Claude Code Harness

[![Version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fwasikarn%2Fmatt-harness%2Fdevelop%2F.claude-plugin%2Fplugin.json&query=%24.version&label=version&color=blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/wasikarn/matt-harness/actions/workflows/validate.yml/badge.svg)](https://github.com/wasikarn/matt-harness/actions/workflows/validate.yml)

A personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) harness packaged as
an installable plugin (`mh@kobig`): a fleet of specialist agents, workflow skills, deny-gates
and advisory sensors, an output-style register, and a terminal theme. No symlink farm, no
manual wiring — components auto-discover from the plugin cache. Matt Pocock's skills install
alongside it as their own plugin (`mattpocock-skills@mattpocock`, see [Quick Start](#quick-start)).

Built on the **composer-not-creator** principle: the best upstream harness tools
([mattpocock/skills](https://github.com/mattpocock/skills),
[ECC](https://github.com/affaan-m/everything-claude-code)) composed into one plugin, extended
only where the underlying backend stack demands it.

> **Unofficial project — not affiliated with Matt Pocock.** matt-harness is an independent,
> community-built harness. It wraps [Matt Pocock's `mattpocock-skills`
> plugin](https://github.com/mattpocock/skills) as its primary skill source (see Quick Start
> step 4), but it is not an official Matt Pocock project, and Matt Pocock is not affiliated
> with or endorsing this repo. Full upstream credit list: [Attribution](#attribution).

---

## Table of Contents

- [Why It's Built This Way](#why-its-built-this-way)
- [Quick Start](#quick-start)
- [What You Get](#what-you-get)
- [Engineering Doctrine](#engineering-doctrine)
- [Spotlight](#spotlight)
- [Repository Layout](#repository-layout)
- [Development](#development)
- [Documentation](#documentation)
- [Attribution](#attribution)
- [License](#license)

---

## Why It's Built This Way

matt-harness isn't just a folder of skills and agents — its one structural rule is a strict
split between what's allowed to **block** an action and what's only allowed to **advise**:

- **Gates** (`hooks/gates/`) are deterministic, non-LLM checks. They can deny an action.
- **Advisory sensors** (`hooks/advisory/`) are LLM-backed. They journal — they can never deny.

The reason: an LLM grading work the same model class just produced is circular — "two
optimists agreeing." So no model here ever gates its own output; only a script that can't
rationalize gets veto power. Every loop in the harness has to end at a **score** a
deterministic check can branch on, not a feeling the model talks itself into.

This rule is built from three named coding-agent disciplines — harness engineering, loop
engineering, and graph engineering — each independently researched and adopted to a
different degree, not taken on faith. [Engineering Doctrine](#engineering-doctrine) says
what's structural, what's vocabulary-only, and what's an open gap the harness admits to
rather than hides.

---

## Quick Start

Run these commands inside Claude Code:

```text
# 1. Register the marketplace source (once per machine)
/plugin marketplace add wasikarn/matt-harness

# 2. Install (default scope is user-wide — see the scope note below before
#    trying it out on just one repo)
/plugin install mh@kobig

# 3. Enable (from a terminal — needs Claude Code v2.1.154+; earlier versions
#    auto-enable on install and can skip this step):
claude plugin enable mh@kobig

# 4. Required — install matt-pocock's skills as their own plugin (mh's hooks
#    and skills route to these by namespaced name; they are not bundled):
/plugin marketplace add mattpocock/skills
/plugin install mattpocock-skills@mattpocock

# 5. Run once per repo (issue tracker, triage labels, doc layout) — the
#    leading slash is required, this skill can't be model-invoked. If step 4's
#    install summary said "Run /reload-plugins to activate", run that first —
#    otherwise this command resolves as unrecognized in the same session:
/mattpocock-skills:setup-matt-pocock-skills

# 6. Restart Claude Code (plugin cache loads on startup)

# 7. Smoke-test — plugin skills are namespaced, /mh:<name> not /<name>
/mh:cost-report

# 8. Verify the install took (from a terminal, no session needed):
claude plugin list                # both plugins "enabled"
claude plugin details mh@kobig   # component inventory + token cost
```

> **Note:** The plugin ships with `defaultEnabled: false`. Step 3 is required.
>
> **Note:** Step 4 is required, not optional. Several of mh's own skills and
> hooks route to matt-pocock's skills by namespaced name
> (`mattpocock-skills:<name>`). A fresh install is not self-contained without
> them. Re-sync with `claude plugin update mattpocock-skills@mattpocock`.
>
> **Note — install scope:** step 2 with no `--scope` flag installs at **user
> scope** — the deny-gates (`hooks/gates/irrecoverable.sh`: blocks `rm -rf`,
> `git add -A`/`git add .`, `--no-verify`, hardcoded `/Users/<name>` paths)
> then apply to **every** project you open in Claude Code, not just the one
> you're evaluating. To try it scoped to one repo first, use
> `/plugin install mh@kobig --scope project` (or `--scope local`) instead.

**Uninstall:** `/plugin uninstall mh@kobig`  
**Disable (keep installed):** `claude plugin disable mh@kobig`

---

## What You Get

Live fleet size — real current fleet: 58 skills · 17 agents — machine-synced by
`skills/inventory/scripts/sync-fleet-counts.sh`, so the counts on this line don't rot.

| Component | How to invoke |
|---|---|
| **Skills** | `mh:<skill>` — e.g. `mh:pr`, `mh:orchestrate` (matt-origin skills live in their own namespace — e.g. `mattpocock-skills:grilling`) |
| **Agents** | Spawned by Claude or via the `Task` tool — e.g. `mh:code-architect` |
| **Output style** | `staff-eng` — sole live-response register, self-calibrates terse vs full framing by stakes |
| **Contexts** | `dev` · `review` · `research` — loaded by `mh:frame` to set session posture |
| **Theme** | `catppuccin-mocha` |

> Hooks: SessionStart doctrine injection (METHODOLOGY.md), PreToolUse gates in
> `hooks/gates/`, advisory sensors in `hooks/advisory/`, cost tracking in `hooks/stop/`.
> The operating model: gates deny the irrecoverable set; sensors journal but never gate.

---

## Engineering Doctrine

matt-harness's design draws on three named disciplines for coding-agent systems. Each was
independently researched (primary sources cited below, not paraphrased secondhand) before
anything was adopted — and each was adopted to a different degree. This section exists so
anyone evaluating the harness knows exactly what's structural, what's vocabulary-only, and
what's an open gap.

### Harness engineering — the architectural spine

**Source:** Birgitta Böckeler (Thoughtworks, via Martin Fowler's site,
[April 2026](https://martinfowler.com/articles/harness-engineering.html)) — a coding-agent
harness modeled as a 2×2 of **direction** (feedforward / feedback) × **execution type**
(computational / inferential). Her core warning: an *inferential* judge (an LLM) grading
work the *same model class* just produced is circular, and should never be trusted to gate.
("Two optimists agreeing" is this repo's coined shorthand for that idea, not a quote from
the article.)

**Where it's used:**
- This is why `hooks/` splits into `hooks/gates/` (deterministic, non-LLM, can deny) and
  `hooks/advisory/` (LLM-backed, journals only, can never emit a blocking decision) — the
  computational/inferential split *is* Böckeler's 2×2, applied as the harness's core
  operating rule (CLAUDE.md's "Why — the unifying crux," under §Architecture).
- `docs/harness-decay-cadence.md` re-applies the same 2×2 to staleness/decay reasoning —
  when a sensor should be trusted to fire, retired, or thickened as models change.
- Grounding: `docs/research/harness-engineering-2026-04.md` plus two adversarial follow-up
  critiques (`*-critique-cost.md`, `*-critique-gaps.md`) that pressure-tested the article
  before it was adopted.

**Verdict:** substantially adopted — not a citation, the structural backbone of how hooks
are split and why an LLM is never wired to `permissionDecision: deny`.

### Loop engineering — vocabulary kept, the autonomous endpoint rejected

**Sources:** Sydney Runkle's ["Art of Loop
Engineering"](https://x.com/sydneyrunkle/article/2066928783534289358) (agent loop /
verification loop / event-driven loop / hill-climbing loop) and
[@0xCodez's 14-step roadmap](https://x.com/0xCodez/article/2066867539305459732)
(harness → loop → self-improving system).

**Where it's used:**
- The harness keeps the L1/L2 vocabulary — bounded loops with a human in them — but
  explicitly rejects both sources' endpoint: an L3/L4 loop that restarts itself with no
  human turn. This is the "no-model-self-start" rule (CLAUDE.md's Operating model), and
  it's why the earlier L2–L5 "bounded-autonomy ratchet" build was retired rather than
  finished.
- Concretely: every fix/review loop that remains requires explicit user re-invocation per
  pass. METHODOLOGY Rule 4 ("define done, loop until verified") governs the *inside* of one
  bounded pass, never a chain of passes that starts itself.
- Full keep/discard analysis of both sources lives in `BOUNDARY.md`'s cross-references
  section.

**Verdict:** the loop vocabulary and L1/L2 patterns are load-bearing; the L3/L4 unattended
conclusion both sources argue toward is a deliberate non-goal, not an oversight.

### Graph engineering — naming what already ran, not a new mechanism

**Source:** eigent.ai's ["Graph Engineering for AI
Agents"](https://www.eigent.ai/blog/graph-engineering-ai-agents), traced back to its actual
academic root (GraphBit, [arXiv:2605.13848](https://arxiv.org/abs/2605.13848)) plus prior
art (LangGraph, AutoGen, CrewAI) — because the blog post's own 4-way failure taxonomy turned
out to repackage separately well-studied problems (specification gaming, goal
misgeneralization, MAS coordination conflict) under new labels rather than contribute new
science.

**Where it's used:**
- `docs/reference/graph-model.md` formalizes the existing dispatch/verification structure
  as an explicit graph: node types (Skill, Agent, Gate, Advisory sensor) and 4 typed edges
  (`routes-to`, `depends-on`, `verifies`, `hands-off-to`). It adds no new mechanism — it
  names structure that was already running, scattered across
  `skills/workflow/orchestrate/SKILL.md` and `BOUNDARY.md`, in one place.
- Only one edge type — `verifies`, what the gates in `hooks/gates/` already do — is
  mechanically enforced the way GraphBit enforces typed edges (a non-LLM engine decides).
  The rest (which route an orchestrator picks, whether an upstream artifact was copied
  correctly into the next spawn prompt, whether a skill's stated handoff is honored) are
  **prompt-discipline**: the doc says so plainly rather than implying they're checked.
- No external anchor exists yet — a held-out eval set the harness didn't author, or a real
  usage metric. Documented as an open question in `graph-model.md`, not silently closed.

**Verdict:** vocabulary borrowed to document an existing structure clearly; the structure
predates the term, and the doc is explicit that this is naming, not new capability.

---

## Spotlight

### Skills

| Skill | When to reach for it |
|---|---|
| `mh:pr` | Create a GitHub PR — templated body, previewed for confirmation before creation |
| `mh:security-scan` | AgentShield scan of harness surfaces via the `security-reviewer` agent |
| `mh:ship-merge` · `mh:ship-release` | Pre-merge gate · end-to-end release ceremony |
| `mh:score-decision` | Weighted numeric verdict for a decision — pass/fail + confidence + trace |
| `mattpocock-skills:grilling` | Relentless interview to stress-test a plan before building |
| `mh:orchestrate` | Triage competing tasks → route each to inline / parallel / sequential / drop |
| `mh:agent-architecture-audit` | 12-layer diagnostic for wrapper regression, memory pollution, repair loops |
| `mh:context-budget` | Token usage audit — finds bloat and produces prioritized savings |
| `mh:security-auditor` | OWASP Top 10, secrets scanning, threat-model + remediation |
| `mh:production-audit` | Local-evidence production readiness check — no external service required |
| `mh:harness-audit` | Deterministic fleet/schema/structural audit of this plugin |

### Agents

Agents run in a delegated sub-task context. Claude spawns them automatically, or you can
request one explicitly via the `Task` tool.

| Agent | Role |
|---|---|
| `mh:code-architect` | System design, module boundaries, and dependency decisions |
| `mh:backend-architect` | API contracts, service boundaries, data ownership, caching, reliability — the systems-design layer above framework-narrow `*-patterns` skills |
| `mh:security-reviewer` | OWASP Top 10, secrets detection, auth flows, and injection risks |
| `mh:blind-spot-hunter` | Post-review adversarial hunter for cross-file, framework-behavior, and data-flow blind spots normal review misses |
| `mh:plan-reviewer` | Adversarial review of an implementation plan before code exists |
| `mh:performance-optimizer` | Bottleneck analysis, profiling strategy, and optimization trade-offs |
| `mh:refactor-cleaner` | Dead code removal, simplification, and naming cleanup |
| `mh:silent-failure-hunter` | Finds errors swallowed by catch-all handlers or missing error returns |
| `mh:spec-miner` | Extracts implicit requirements from code when no spec doc exists |
| `mh:requirement-analyst` | Senior-level requirement analysis of a ticket/spec/PRD — ambiguities, missing ACs, edge cases, readiness verdict |
| `mh:typescript-reviewer` · `mh:python-reviewer` · `mh:nextjs-reviewer` | Language/framework-specific review — type safety, idioms, async correctness, Next.js App Router rendering/caching |
| `mh:build-error-resolver` | Fixes build/type errors with minimal diffs |
| `mh:summarizer` | Clarity/compression specialist — condenses long content into filler-free output |
| `mh:ideate-critic` | Fresh-context critic for `mh:ideate` Phase 2 — scores, clusters, and deepens divergent ideas |

### Backend Stack Patterns

Stack-specific pattern skills, harness-native.

| Skill | When to reach for it |
|---|---|
| `mh:drizzle-patterns` | Drizzle ORM schema, migrations, relations, and query patterns for PostgreSQL / SQLite |
| `mh:grpc-node-patterns` | gRPC client/server with `@grpc/grpc-js`, TypeScript codegen, streaming, and error codes |
| `mh:mysql-patterns` | MySQL / MariaDB schema, indexing, transactions, replication, and pool patterns |

---

## Repository Layout

```text
matt-harness/
├── .claude-plugin/       # plugin.json + marketplace.json (both bumped on every release)
├── agents/               # specialist subagents (.md each)
├── skills/               # SKILL.md per directory, grouped by bucket:
│                         #   meta/ review/ workflow/ patterns/ agent-support/ design/
├── hooks/                # gates/ (deny) · advisory/ (journal) · session/ (inject) · stop/ (cost)
├── output-styles/        # staff-eng — sole live-response register
├── contexts/             # dev / review / research session frames
├── themes/               # catppuccin-mocha.json
├── scripts/              # validation helpers (run-gauntlet.sh — full parallel gauntlet)
├── docs/                 # onboarding, METHODOLOGY, reference/, research/, adr/
├── git-hooks/            # pre-commit (lint + JSON + LOC gate) · pre-push (gauntlet)
├── BOUNDARY.md           # generated index of every surface — read this first
├── CLAUDE.md             # project instructions for Claude Code instances
└── CHANGELOG.md          # release notes
```

---

## Development

### Validation

```bash
# Primary validation gate
claude plugin validate . --strict

# Full gauntlet (plugin-validate + shell-lint + JSON lint + harness-audit +
# the behavioral test suite — CLAUDE.md's Validation section is the
# authoritative file list; no count stated here, counts drift)
bash scripts/run-gauntlet.sh
```

### Git Hooks

Hooks live in `git-hooks/` (not `.git/hooks/`). Wire once per clone:

```bash
git config core.hooksPath git-hooks
```

| Hook | What it runs |
|---|---|
| `pre-commit` | `bash -n` + shellcheck, JSON validation, harness-audit, new-file LOC gate |
| `pre-push` | Full gauntlet |

### Adding a Component

The authoritative step-by-step (including fleet-count sync, `BOUNDARY.md` regen, and the
cache-refresh ordering gotcha) is CLAUDE.md's **"Adding or removing a surface."** The short
version:

1. Create the file following the pattern of an existing component in the same directory.
2. Bump `version` in **both** `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
   — same-version edits to a cached plugin are silent no-ops.
3. `claude plugin validate . --strict`, then `bash skills/inventory/scripts/sync-fleet-counts.sh`.
4. `claude plugin update mh@kobig`, commit, push, restart Claude Code.

---

## Documentation

| File | What's in it |
|---|---|
| [`BOUNDARY.md`](BOUNDARY.md) | Generated index of every agent, skill, and hook, grouped by bucket |
| [`docs/onboarding.md`](docs/onboarding.md) | 10-minute cold-start guide |
| [`docs/reference/operating-model.md`](docs/reference/operating-model.md) | Gates-deny / sensors-advise doctrine, self-contained excerpt |
| [`docs/reference/reasoning-models.md`](docs/reference/reasoning-models.md) | 39 named mental models (cc-thinking-skills), pointing upstream for full write-ups |
| [`docs/reference/env-vars.md`](docs/reference/env-vars.md) | Operator-tunable environment variables |
| [`docs/reference/graph-model.md`](docs/reference/graph-model.md) | Orchestration graph formalization — nodes, typed edges, anchors (see [Engineering Doctrine](#engineering-doctrine)) |
| [`docs/research/harness-engineering-2026-04.md`](docs/research/harness-engineering-2026-04.md) | Primary-source grounding for the gates/advisory split |
| [`docs/harness-decay-cadence.md`](docs/harness-decay-cadence.md) | Harness-engineering 2×2 applied to sensor staleness/decay |
| [`CLAUDE.md`](CLAUDE.md) | Architecture and non-obvious gotchas for Claude Code instances |
| [`CHANGELOG.md`](CHANGELOG.md) | Release notes |

---

## Attribution

matt-harness aggregates components from these upstream projects under their respective
licenses.

> **Point-in-time snapshot (counts as of 2026-07-18), not live-derived.** There is no
> `origin:` frontmatter field on surface files to auto-regenerate this table: it's a manual
> tally. The kbg-native row is the exception — machine-synced to the live fleet count.

| Source | License | Adopted |
|---|---|---|
| [mattpocock/skills](https://github.com/mattpocock/skills) | MIT | Installed as the `mattpocock-skills` plugin (not vendored — see Quick Start), 0 modified |
| [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) | MIT | 85 skills · 48 agents · 64 commands · 3 contexts |
| [TJBoudreaux/cc-thinking-skills](https://github.com/TJBoudreaux/cc-thinking-skills) | MIT | 39 mental models cataloged by name in `docs/reference/reasoning-models.md`, pointing to the upstream repo for full write-ups (no local vendored copy since ticket 94) |
| [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) | MIT | 3 voice rules folded into `output-styles/staff-eng.md` (v0.68.126) |
| [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) | MIT | Tokenizer-fact justification in `output-styles/staff-eng.md` + a terminal-token status-code convention in `docs/agent-authoring-conventions.md` §8 (v0.68.127); `compress-docs` skill's safety pattern — verify-before-overwrite, frontmatter handling, sensitive-file refusal — adapted from `caveman-compress` (v0.68.128); symlink guard on `hooks/stop/cost-tracker.sh`'s `costs.jsonl` append, adapted from `caveman-config.js`'s `safeWriteFlag` hardening (v0.68.129) |
| [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | MIT | YAGNI ladder + `ponytail:` shortcut-marker convention + root-cause-fix rule, revived into `contexts/dev.md` |
| [thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) | Apache-2.0 | `docs/merge-rubric.md`'s real-fix-vs-failure-tolerance-machinery rubric adapted into a Fix-Authenticity Lens in `agents/code-reviewer.md` (v0.68.130; both retired 2026-08-24, #82, with the review pipeline — `mattpocock-skills:code-review` is now the review surface) |
| kbg-native | MIT | 58 skills · 17 agents |

---

## License

MIT. See [`LICENSE`](LICENSE).
