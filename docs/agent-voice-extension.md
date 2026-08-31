# Agent voice extensions: when (and when not) to wrap a personality in a command

**Status:** Convention reference. Owned by the harness. Sibling of [`agent-tool-patterns.md`](./agent-tool-patterns.md).
**Origin:** F5 voice blocks shipped in Phase 3 (commit `4d2ad91`) against the fleet at the time. Of the current 13-agent fleet, `ideate-critic` is the one agent that carries a `## Voice` section with `senior-eng` personality (uncertainty, tradeoff, reasoning, pattern recognition) inline. Phase 4 D6 (deferred from the 2026-06-12 audit spec) considered wrapping those personalities in `/debug`, `/architect`, `/perspectives` commands. Owner chose to **fold into this doc** rather than ship commands — F5 stays the single source of truth for "what does this agent sound like."

The question this doc answers: **when a user types `/<personality>`, what should happen, and what shouldn't we build?**

## 1. The default: don't build a personality command

**The matt-harness default is: do not add a slash command just to invoke an agent's personality.** The agent's `## Voice` block (shipped in F5) is already the personality. Adding a command on top creates three problems:

1. **Surface bloat** — every personality command is a discoverability weight. The user has to remember `/architect` exists, then remember what it routes to. Routing the request to `code-architect` directly (via the orchestrator or the user typing `@code-architect`) already gets the personality.
2. **Personality drift** — the command's frontmatter and the agent's voice block can diverge silently. The F5 contract says "personality is in the agent's `## Voice` block." A command wrapper is a second place to keep in sync.
3. **ROUTER bypass** — the orchestrator (`skills/workflow/orchestrate/SKILL.md`) routes by domain (`code-architect` for "design this", `security-reviewer` for "audit this for vulns"). A personality command skips the router, which means the user's `/architect` request might land on a domain that doesn't match (e.g. user types `/architect` for a backend scaling question, gets a system-design personality, but the right agent is `platform-engineer`).

**Rule of thumb:** if the personality command would just be `<verb> → invoke <agent> with no transformation`, don't ship it. The agent already exists.

## 2. When a personality command IS worth shipping

There are three situations where a command wrapper earns its place over direct agent invocation. Each makes the command a **transformation**, not a routing shortcut.

### 2.1 The command adds a structured ritual the agent doesn't have

The command's value is a **procedure** the agent doesn't carry in its own body.

**Example: a hypothetical `/debug` command.**
- **What it would do:** invoke `diagnosing-bugs` (the disciplined-diagnosis skill) — reproduce → minimise → hypothesise → instrument → fix → regression-test.
- **Why a command is justified:** the user wants a 6-step **procedure**, not a 10-year-context senior-debugger voice. The skill `diagnosing-bugs` carries the procedure. A `/debug` command would be the entry point that triggers the skill, then routes the output to whichever engineer is appropriate.
- **Without the command:** the user types "debug this", the orchestrator routes to a generic agent, the procedure has to be invoked explicitly via `diagnosing-bugs` or remembered by the user.

**This is the strongest case for a personality command** — the personality (patient, evidence-driven) is in the agent, but the ritual lives in the command.

### 2.2 The command pre-loads context the agent would otherwise have to gather

The command's value is **prompt engineering** — it pre-loads files, env state, or focus areas so the agent starts with full context.

**Example: a hypothetical `/architect` command for a specific project.**
- **What it would do:** pre-load `docs/architecture.md`, the deployment topology, the team's module ownership map, and the 3 most recent architecture-decision records; then invoke `code-architect` with that context.
- **Why a command is justified:** without the pre-load, `code-architect`'s voice block already says "I'd want to see the deploy pipeline + the existing module boundaries before I commit to this shape" — meaning the agent will ask for it. The command pre-empts the ask.
- **Without the command:** the user invokes `code-architect` directly, gets the "I'd want to see…" question, has to provide the files. Two turns.

**This case is weaker than 2.1** — it's a quality-of-life wrapper, not a new capability. The default should still be "no command."

### 2.3 The command enforces an output shape the agent's voice doesn't promise

The command's value is a **deliverable contract** — a specific output format the user needs.

**Example: a hypothetical `/perspectives` command for a decision review.**
- **What it would do:** invoke `critical-eval` (or `probe`) to stress-test a decision, then **format the output as a structured ADR-shaped critique** (claim, counter-claim, evidence, verdict).
- **Why a command is justified:** the agent's voice block says "stress-test reasoning" but doesn't promise the output shape. The command gives the user a stable interface.
- **Without the command:** the user asks for a stress-test, gets prose, has to ask "can you put that in a table" or similar.

**This is the weakest of the three cases** — it overlaps with the existing 22 commands (`ship-merge`, `pr`, etc.) which already encode output shape. If you find yourself wanting a `/perspectives` command, the right move is usually to extend `critical-eval`'s output-format guidance or write a new command that **isn't** personality-flavored.

## 3. Recipe: how to build a personality command the right way

If you've decided a personality command is justified (you've ruled out "the agent already does this"), here's the pattern:

### Frontmatter contract

```yaml
---
description: <one-line: what the command does, not what the agent is>
argument-hint: <what the user provides>
agent: <the personality the command routes to>
allowed-tools: <smallest set the command needs; usually Read-only>
---
```

- `description` is the **transformation**, not the personality. A bad description: "Senior architect assistant." A good description: "Run the architecture-design ritual: pre-load context, then invoke code-architect with the deployment topology + recent ADRs in scope."
- `agent` is the personality the command routes to. The voice is the agent's, not the command's.
- `allowed-tools` is the **command's** tool set — usually narrower than the agent's, because the command is a thin entry point. If the command needs `Write`, that's a red flag — the command should not mutate, the invoked agent might.

### Body contract

1. **State the ritual** in 1-2 sentences. The user is here for the procedure, not the personality.
2. **Pre-load the context** the agent would otherwise gather (case 2.2) — list the files/env state the command reads first.
3. **Invoke the agent by name** with the loaded context. Do not re-state the agent's voice block in the command body — that's drift waiting to happen.
4. **State the output shape** (case 2.3) if the user expects a specific deliverable.

### Anti-patterns

- **Do not restate the F5 voice block in the command body.** The voice is in the agent; repeating it in the command is drift bait.
- **Do not add a new `## Voice` block to the command.** Commands don't have personalities; agents do. The personality comes from `agent:` routing.
- **Do not skip the orchestrator.** If the command could route through `orchestrate` (which picks the right agent by domain), let it. The personality command is a shortcut, not a parallel router.

## 4. Worked examples (per the D6 spec, mapped to matt-harness)

The 2026-06-12 audit spec (delta-vs-REPORT-v2.md:109) named three example personality commands: `/debug`, `/architect`, `/perspectives`. Per owner decision (2026-06-12), **none of these are shipped as commands.** Below is the recipe if/when they ever are.

### `/debug` — case 2.1 (ritual)

```yaml
---
description: Run disciplined-diagnosis on a reported bug: reproduce → minimise → hypothesise → instrument → fix → regression-test
argument-hint: <bug-report-or-symptom>
agent: backend-engineer   # or whichever domain owns the bug
allowed-tools: Read, Grep, Glob, Bash
---
```

The command's body invokes the `mattpocock-skills:diagnosing-bugs` skill (installed as the `mattpocock-skills` plugin, not vendored since v0.46.0) as the procedure; the `agent:` field carries the domain-specific voice. The command is justified because the 6-step procedure is a ritual the agent doesn't carry inline.

### `/architect` — case 2.2 (context pre-load)

```yaml
---
description: Pre-load project context (architecture docs, deploy topology, recent ADRs) and invoke code-architect for an architecture decision
argument-hint: <decision-or-shape>
agent: code-architect
allowed-tools: Read, Grep, Glob
---
```

The command pre-loads context the agent's voice block would otherwise ask for. Marginal — could also be solved by adding the pre-load to `code-architect`'s own `## Pre-loaded context` section. The command version is preferred only if the pre-load is **per-project** and the project owner wants to maintain it without touching the agent.

### `/perspectives` — case 2.3 (output shape)

```yaml
---
description: Stress-test a decision under multiple adversarial lenses and return an ADR-shaped critique (claim, counter-claim, evidence, verdict)
argument-hint: <decision-or-claim>
allowed-tools: Read, Grep, Glob
---
```

The command's value is the **output shape** (ADR-shaped critique), not a new capability — `mattpocock-skills:grilling` already stress-tests reasoning adversarially (this hypothetical isn't an `agent:`, since `critical-eval` was never a standalone agent). The risk: this overlaps with the existing `domain-modeling` ADR ritual, which is the right skill for "draft an ADR." If you find yourself wanting `/perspectives`, the right move is usually `mattpocock-skills:grilling` or `domain-modeling` instead.

## 5. Cross-references

- **[F5 voice blocks](./agent-tool-patterns.md#5-cross-references)** — the personality surface this doc protects. Agents with `## Voice` blocks are documented in `agents/*.md`; this doc governs whether and how to wrap one in a command.
- **[F5 ship commit `4d2ad91`](../CHANGELOG.md)** — the Phase 3 commit that added voice blocks; the D6 decision was made in the context of what that commit shipped.
- **[orchestrate router](../skills/workflow/orchestrate/SKILL.md)** — the domain-routing layer. A personality command should not duplicate this routing; it should layer on top (pre-load context, enforce output shape) or below (trigger a procedure).
- **[diagnose skill](https://docs.claude.com)** (plugin-shipped, not in this harness) — the disciplined-diagnosis procedure referenced in the `/debug` worked example.
- **2026-06-12 audit spec, D6** (local scratch file, not in repo) — the originating finding. Closed by this doc; SPEC.md's item D6 marked RESOLVED → FOLDED INTO F5 EXTENSION.
