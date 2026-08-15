# kbg — Claude Code Harness

[![Version](https://img.shields.io/badge/version-v0.68.308-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml/badge.svg)](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml)

A personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) harness packaged as an installable plugin (`kbg@kobig`). Drop it in and you get a fleet of specialist agents, workflow skills, and slash commands (see [What You Get](#what-you-get) for current counts), plus matt-pocock's skills installed as their own plugin (`mattpocock-skills@mattpocock`, see Quick Start), an output-style register, and a terminal theme. No symlink farm, no manual wiring: components auto-discover from the plugin cache.

Built on the **composer-not-creator** principle: the best upstream harness tools ([ECC](https://github.com/affaan-m/everything-claude-code), [mattpocock/skills](https://github.com/mattpocock/skills)) bundled into one plugin, extended only where the underlying backend stack demands it.

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

kbg-harness isn't just a folder of skills and agents — its one structural rule is a strict
split between what's allowed to **block** an action and what's only allowed to **advise**
on it:

- **Gates** (`hooks/gates/`) are deterministic, non-LLM checks. They can deny an action.
- **Advisory sensors** (`hooks/advisory/`) are LLM-backed. They journal — they can never
  deny.

The reason: an LLM grading work the same model class just produced is circular — "two
optimists agreeing." So no model here ever gates its own output; only a script that can't
rationalize gets veto power. Every loop in the harness has to end at a **score** a
deterministic check can branch on, not a feeling the model talks itself into.

This rule is built from three named coding-agent disciplines — harness engineering, loop
engineering, and graph engineering — each independently researched and adopted to a
different degree, not taken on faith. See [Engineering Doctrine](#engineering-doctrine) for
what's structural, what's vocabulary-only, and what's an open gap the harness admits to
rather than hides.

---

## Quick Start

Run these commands inside Claude Code:

```text
# 1. Register the marketplace source (once per machine)
/plugin marketplace add wasikarn/kbg-harness

# 2. Install (default scope is user-wide — see the scope note below before
#    trying kbg out on just one repo)
/plugin install kbg@kobig

# 3. Enable (from a terminal — needs Claude Code v2.1.154+; earlier versions
#    auto-enable on install and can skip this step):
claude plugin enable kbg@kobig

# 4. Required — install matt-pocock's skills as their own plugin (kbg's hooks,
#    commands, and remaining skills route to these by namespaced name; they
#    are not bundled in the kbg plugin).
/plugin marketplace add mattpocock/skills
/plugin install mattpocock-skills@mattpocock

# 5. Run once per repo (issue tracker, triage labels, doc layout) — the
#    leading slash is required, this skill can't be model-invoked. If step 4's
#    install summary said "Run /reload-plugins to activate" (it can, for a
#    plugin this size), run that first — otherwise this command resolves as
#    unrecognized in the same session:
/mattpocock-skills:setup-matt-pocock-skills

# 6. Restart Claude Code (plugin cache loads on startup)

# 7. Smoke-test — plugin commands are namespaced like skills, /kbg:<name> not /<name>
/kbg:kbg-help

# 8. Verify the install actually took (from a terminal, no session needed):
claude plugin list                # kbg@kobig AND mattpocock-skills@mattpocock both "enabled"
claude plugin details kbg@kobig   # component inventory + token cost — folds all flat-file
                                   # commands/*.md into one "Skills" count and doesn't list
                                   # directory-form commands (ship/ideate/address-review) at
                                   # all, so this won't confirm those 3 specifically; use
                                   # step 7's smoke test for a real functional check instead
```

> **Note:** The plugin ships with `defaultEnabled: false`. Step 3 is required.
>
> **Note:** Step 4 is required, not optional. Several of kbg's own skills,
> commands, and hooks route to matt-pocock's skills by namespaced name
> (`mattpocock-skills:<name>`). A fresh clone/install is not self-contained
> without them. Installed as a plugin — not vendored, not `gh skill`-installed
> (migrated off `gh skill` 2026-07-17). Re-sync with
> `claude plugin update mattpocock-skills@mattpocock`.
>
> **Note — install scope:** step 2 with no `--scope` flag installs at **user
> scope** — kbg's deny-gates (`hooks/gates/irrecoverable.sh`: blocks `rm -rf`,
> `git add -A`/`git add .`, `--no-verify`, hardcoded `/Users/<name>` paths)
> then apply to **every** project you open in Claude Code, not just the one
> you're evaluating kbg against. To try it scoped to one repo first, use
> `/plugin install kbg@kobig --scope project` (or `--scope local`) instead.

**Uninstall:** `/plugin uninstall kbg@kobig`  
**Disable (keep installed):** `claude plugin disable kbg@kobig`

After changing any surface, follow the release cycle in [Adding a Component](#development) below (bump both manifest versions → validate → commit → push → update → restart).

---

## What You Get

| Component | Count | How to invoke |
|---|---|---|
| **Skills** | 36 | `kbg:<skill>` — e.g. `kbg:pr`, `kbg:orchestrate` (matt-origin skills install as a separate namespaced plugin — e.g. `mattpocock-skills:grilling`) |
| **Agents** | 20 | Spawned by Claude or via the `Task` tool — e.g. `code-architect` |
| **Commands** | 24 | `/kbg:<command>` — e.g. `/kbg:ship`, `/kbg:address-review`, `/kbg:fix-bug` (namespaced identically to skills — see Quick Start step 7) |
| **Output Styles** | 1 | `staff-eng` — sole live-response register, self-calibrates terse vs full framing by stakes |
| **Contexts** | 3 | `dev` · `review` · `research` — loaded by `/frame` to set session posture |
| **Themes** | 1 | `catppuccin-mocha` |

> Hooks: SessionStart doctrine injection (METHODOLOGY.md), PreToolUse gates in `hooks/gates/`, advisory sensors in `hooks/advisory/`, and cost tracking in `hooks/stop/`. The operating model: gates deny the irrecoverable set; sensors journal but never gate.

---

## Engineering Doctrine

kbg-harness's design draws on three named disciplines for coding-agent systems. Each was
independently researched (primary sources cited below, not paraphrased secondhand) before
anything was adopted — and each was adopted to a different degree. This section is here so
that anyone evaluating the harness before installing it knows exactly what's structural,
what's vocabulary-only, and what's an open gap the harness admits to rather than hides.

### Harness engineering — the architectural spine

**Source:** Birgitta Böckeler (Thoughtworks, via Martin Fowler's site,
[April 2026](https://martinfowler.com/articles/harness-engineering.html)) — a coding-agent
harness modeled as a 2×2 of **direction** (feedforward / feedback) × **execution type**
(computational / inferential). Her core warning: an *inferential* judge (an LLM) grading
work the *same model class* just produced is circular, and should never be trusted to gate.
kbg's own shorthand for that circularity — "two optimists agreeing" — doesn't appear in the
article itself; it's this repo's coined phrase for the idea, not a quote.

**Where it's used:**
- This is the reason `hooks/` splits into `hooks/gates/` (deterministic, non-LLM, can deny)
  and `hooks/advisory/` (LLM-backed, journals only, can never emit a blocking decision) — the
  computational/inferential split *is* Böckeler's 2×2, applied as the harness's core
  operating rule (CLAUDE.md's "Why — the unifying crux," under §Architecture).
- `docs/harness-decay-cadence.md` re-applies the same 2×2 specifically to staleness/decay
  reasoning — when a sensor should be trusted to fire, retired, or thickened as models change.
- Grounding: `docs/research/harness-engineering-2026-04.md` plus two adversarial
  follow-up critiques (`*-critique-cost.md`, `*-critique-gaps.md`) that pressure-tested the
  article before it was adopted.

**Verdict:** substantially adopted — not a citation, the structural backbone of how hooks
are split and why an LLM is never wired to `permissionDecision: deny`.

### Loop engineering — vocabulary kept, the autonomous endpoint rejected

**Sources:** Sydney Runkle's ["Art of Loop
Engineering"](https://x.com/sydneyrunkle/article/2066928783534289358) (agent loop /
verification loop / event-driven loop / hill-climbing loop) and
[@0xCodez's 14-step roadmap](https://x.com/0xCodez/article/2066867539305459732)
(harness → loop → self-improving system).

**Where it's used:**
- kbg keeps the L1/L2 vocabulary — bounded loops with a human in it — but explicitly
  rejects both sources' endpoint: an L3/L4 loop that restarts itself with no human turn.
  This is the "no-model-self-start" rule (CLAUDE.md's Operating model), and it's why the
  earlier L2–L5 "bounded-autonomy ratchet" build was retired rather than finished.
- Concretely: `/kbg:ship`'s Phase 7 fix loop is explicit that "there is no autonomous loop —
  each iteration requires explicit user re-invocation." Rule 4 ("define done, loop until
  verified") governs the *inside* of one bounded pass, never a chain of passes that starts
  itself.
- Full keep/discard analysis of both sources lives in `BOUNDARY.md`'s cross-references
  section.

**Verdict:** the loop vocabulary and L1/L2 patterns are load-bearing; the L3/L4 unattended
conclusion both sources argue toward is a deliberate non-goal, not an oversight.

### Graph engineering — naming what already ran, not a new mechanism

**Source:** eigent.ai's ["Graph Engineering for AI
Agents"](https://www.eigent.ai/blog/graph-engineering-ai-agents), traced back to its actual
academic root (GraphBit, [arXiv:2605.13848](https://arxiv.org/abs/2605.13848)) plus prior art
(LangGraph, AutoGen, CrewAI) — because the blog post's own 4-way failure taxonomy turned out
to repackage separately well-studied problems (specification gaming, goal
misgeneralization, MAS coordination conflict) under new labels rather than contribute new
science.

**Where it's used:**
- `docs/reference/graph-model.md` formalizes kbg's existing dispatch/verification structure
  as an explicit graph: 5 node types (Skill, Agent, Command, Gate, Advisory sensor) and 4
  typed edges (`routes-to`, `depends-on`, `verifies`, `hands-off-to`). It adds no new
  mechanism — it names structure that was already running, scattered across
  `skills/orchestrate/SKILL.md` and `BOUNDARY.md`, in one place.
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

### Commands

| Command | What it does |
|---|---|
| `/kbg:ship` | Land a code change end-to-end: classify, implement, test, review, fix-loop, merge |
| `/kbg:fix-bug` | Guided 7-phase bug-fix with diagnostic + test-first patterns |
| `/kbg:security-scan` | AgentShield scan of harness surfaces via the `security-reviewer` agent |
| `/kbg:ship-merge` · `/kbg:ship-release` | Pre-merge gate · end-to-end release ceremony |

### Skills

| Skill | When to reach for it |
|---|---|
| `kbg:pr` | Create a GitHub PR — templated body, previewed for confirmation before creation |
| `kbg:decide` | Judgment Ladder: `clarify` / `probe` / `decide` / `strategize` / `critique` modes |
| `kbg:score-decision` | Weighted numeric verdict for a decision — pass/fail + confidence + trace |
| `mattpocock-skills:grilling` | Relentless interview to stress-test a plan before building |
| `kbg:orchestrate` | Triage competing tasks → route each to inline / parallel / sequential / drop |
| `kbg:agent-architecture-audit` | 12-layer diagnostic for wrapper regression, memory pollution, repair loops |
| `kbg:context-budget` | Token usage audit — finds bloat and produces prioritized savings |
| `kbg:security-auditor` | OWASP Top 10, secrets scanning, threat-model + remediation |
| `kbg:production-audit` | Local-evidence production readiness check — no external service required |
| `kbg:harness-audit` | Deterministic fleet/schema/structural audit of this plugin |

### Agents

Agents run in a delegated sub-task context. Claude spawns them automatically, or you can request one explicitly via the `Task` tool.

| Agent | Role |
|---|---|
| `code-architect` | System design, module boundaries, and dependency decisions |
| `code-implementer` | Detects the stack, loads the matching `kbg:*-patterns` skill, writes the smallest-scope diff, verifies |
| `backend-architect` | API contracts, service boundaries, data ownership, caching, reliability — the systems-design layer above framework-narrow `*-patterns` skills |
| `security-reviewer` | OWASP Top 10, secrets detection, auth flows, and injection risks |
| `code-reviewer` | Quality, correctness, patterns, and missing edge cases |
| `blind-spot-hunter` | Post-review adversarial hunter for cross-file, framework-behavior, and data-flow blind spots normal review misses |
| `performance-optimizer` | Bottleneck analysis, profiling strategy, and optimization trade-offs |
| `refactor-cleaner` | Dead code removal, simplification, and naming cleanup |
| `silent-failure-hunter` | Finds errors swallowed by catch-all handlers or missing error returns |
| `spec-miner` | Extracts implicit requirements from code when no spec doc exists |
| `requirement-analyst` | Senior-level requirement analysis of a ticket/spec/PRD — ambiguities, missing ACs, edge cases, readiness verdict |
| `plan-reviewer` | Adversarial review of an implementation plan before code exists — requirement coverage, risk, edge cases, testability |
| `typescript-reviewer` · `python-reviewer` · `nextjs-reviewer` | Language/framework-specific review — type safety, idioms, async correctness, Next.js App Router rendering/caching |
| `build-error-resolver` | Fixes build/type errors with minimal diffs |
| `summarizer` | Clarity/compression specialist — condenses long content into filler-free output for any audience |
| `ideate-critic` | Fresh-context critic for `/kbg:ideate` Phase 2 — scores, clusters, and deepens divergent ideas |
| `task-prep-checker` | Fresh-context verifier for a `task-prep` handoff prompt — runs the golden-rule colleague test |

### Backend Stack Patterns

Stack-specific pattern skills, kbg-native.

| Skill | When to reach for it |
|---|---|
| `kbg:drizzle-patterns` | Drizzle ORM schema, migrations, relations, and query patterns for PostgreSQL / MySQL / SQLite |
| `kbg:grpc-node-patterns` | gRPC client/server with `@grpc/grpc-js`, TypeScript codegen, streaming, and error codes |
| `kbg:mysql-patterns` | MySQL / MariaDB schema, indexing, transactions, replication, and pool patterns |

---

## Repository Layout

```text
kbg-harness/
├── .claude-plugin/       # plugin.json + marketplace.json (both must be bumped on each release)
├── agents/               # 20 specialist subagents (.md each)
├── skills/               # 36 workflow skills (SKILL.md per directory)
├── commands/             # 23 slash commands
├── hooks/                # gates/ (deny) · advisory/ (journal) · session/ (inject) · stop/ (cost)
├── output-styles/        # staff-eng — sole live-response register
├── contexts/             # dev / review / research session frames
├── themes/               # catppuccin-mocha.json
├── scripts/              # Validation helpers (run-gauntlet.sh — full parallel gauntlet)
├── docs/
│   ├── onboarding.md     # 10-minute cold-start
│   └── reference/        # thinking-skills library, reasoning-models.md, env-vars.md
├── git-hooks/            # pre-commit (lint + JSON + syntax) · pre-push (gauntlet)
├── CLAUDE.md             # Project instructions for Claude Code instances
└── CHANGELOG.md          # Release notes
```

---

## Development

### Validation

```bash
# Only live validation gate
claude plugin validate --strict .

# Full gauntlet (plugin-validate + shell-lint + JSON lint + harness-audit +
# the 12-file hook/skill behavioral test suite — see CLAUDE.md's Validation
# section for the full file list)
bash scripts/run-gauntlet.sh
```

### Git Hooks

Hooks live in `git-hooks/` (not `.git/hooks/`). Wire once per clone:

```bash
git config core.hooksPath git-hooks
```

| Hook | What it runs |
|---|---|
| `pre-commit` | `bash -n` + shellcheck, JSON validation, harness-audit |
| `pre-push` | Full gauntlet |

### Adding a Component

1. Create the file following the pattern of an existing component in the same directory.  
   - **Skill** → `skills/<name>/SKILL.md` with `name` + `description` (≤ 25 words) frontmatter  
   - **Agent** → `agents/<name>.md` with `name`, `description` (≤ 25 words), `tools` frontmatter  
   - **Command** → `commands/<name>.md` with frontmatter  
2. Bump `version` in **both** `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
3. `claude plugin validate --strict .`
4. Commit and push.
5. `claude plugin update kbg@kobig` → restart Claude Code.

---

## Documentation

| File | What's in it |
|---|---|
| [`docs/onboarding.md`](docs/onboarding.md) | 10-minute cold-start guide |
| [`docs/reference/reasoning-models.md`](docs/reference/reasoning-models.md) | 39 vendored mental models (cc-thinking-skills) |
| [`docs/reference/env-vars.md`](docs/reference/env-vars.md) | Operator-tunable environment variables |
| [`docs/reference/graph-model.md`](docs/reference/graph-model.md) | Orchestration graph formalization — nodes, typed edges, anchors (see [Engineering Doctrine](#engineering-doctrine)) |
| [`docs/research/harness-engineering-2026-04.md`](docs/research/harness-engineering-2026-04.md) | Primary-source grounding for the gates/advisory split |
| [`docs/harness-decay-cadence.md`](docs/harness-decay-cadence.md) | Harness-engineering 2×2 applied to sensor staleness/decay |
| [`CLAUDE.md`](CLAUDE.md) | Architecture and non-obvious gotchas for Claude Code instances |
| [`CHANGELOG.md`](CHANGELOG.md) | Release notes |

---

## Attribution

kbg-harness aggregates components from these upstream projects under their respective licenses.

> **Point-in-time snapshot (counts as of 2026-07-18), not live-derived.** There is no
> `origin:` frontmatter field on surface files to auto-regenerate this table: it's a
> manual tally. To browse what's actually shipping today: `ls skills/`, `ls agents/`,
> `ls commands/` (real current fleet: 36 skills · 20 agents · 24 commands).

| Source | License | Adopted |
|---|---|---|
| [mattpocock/skills](https://github.com/mattpocock/skills) | MIT | Installed as the `mattpocock-skills` plugin (not vendored — see Quick Start), 0 kbg-modified |
| [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) | MIT | 85 skills · 48 agents · 64 commands · 3 contexts |
| [TJBoudreaux/cc-thinking-skills](https://github.com/TJBoudreaux/cc-thinking-skills) | MIT | 39 mental models vendored into `docs/reference/thinking-skills/skills/` (on-demand reference, not an auto-discovered skill) |
| [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) | MIT | 3 voice rules folded into `output-styles/staff-eng.md` (v0.68.126) |
| [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) | MIT | Tokenizer-fact justification in `output-styles/staff-eng.md` + a terminal-token status-code convention in `docs/agent-authoring-conventions.md` §8 (v0.68.127); `compress-docs` skill's safety pattern — verify-before-overwrite, frontmatter handling, sensitive-file refusal — adapted from `caveman-compress` (v0.68.128, compression technique itself is kbg-native, not caveman-grammar); symlink guard on `hooks/stop/cost-tracker.sh`'s `costs.jsonl` append, adapted from `caveman-config.js`'s `safeWriteFlag` hardening (v0.68.129) |
| [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | MIT | YAGNI ladder + `ponytail:` shortcut-marker convention + root-cause-fix rule, revived into `contexts/dev.md` |
| [thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) | Apache-2.0 | `docs/merge-rubric.md`'s real-fix-vs-failure-tolerance-machinery rubric adapted into a new Fix-Authenticity Lens in `agents/code-reviewer.md` (v0.68.130) |
| kbg-native | MIT | 36 skills · 20 agents · 24 commands |

---

## License

MIT. See [`LICENSE`](LICENSE).
