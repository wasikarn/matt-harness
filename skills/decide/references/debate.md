# Debate lens (parallel technical debate)

This is the detailed reference for the `debate` mode of `kbg:decide`. It was formerly the standalone `/debug-debate` command. Use it for technical disagreements where the user wants to see multiple sides before choosing.

## When this runs

`kbg:decide` selects `debate` mode when the user asks something like "which is better", "should we use X or Y", "debug debate", "debate", "ถกเถียง", "ประชุมถก", or asks for a structured argument between options.

## Lead-moderator contract

You are the moderator. Three doctrine rules:

1. **You do not take sides.** You dispatch agents, read their arguments, and produce an impartial consensus matrix.
2. **Sonnet for debate agents.** Debate agents run `model: "sonnet"` (analysis, not implementation). You stay on Opus for synthesis + judgment.
3. **Isolated context.** Each debate agent receives ONLY the topic and their role. They do NOT see each other's responses.

## Step 1 — Parse topic + configure agents

1. Parse `$ARGUMENTS`:
   - **Topic:** everything before `--agents` or `--timebox`.
   - **`--agents=N`:** integer, default `3`. Valid: `2`, `3`, `4`.
   - **`--timebox=T`:** duration, default `10min`.
2. Generate a slug from the topic (lowercase, alphanum + hyphens, ≤60 chars).
3. If topic is missing, ask the user.

**Agent selection table:**

| `--agents` | Agent A (Advocate) | Agent B (Skeptic) | Agent C (Synthesizer) | Agent D (Cost Analyst) |
|---|---|---|---|---|
| `2` | `backend-engineer` or `platform-engineer` | `security-reviewer` or `silent-failure-hunter` | — | — |
| `3` (default) | `backend-engineer` or `platform-engineer` | `security-reviewer` or `silent-failure-hunter` | `code-architect` or `product-analyst` | — |
| `4` | `backend-engineer` or `platform-engineer` | `security-reviewer` or `silent-failure-hunter` | `code-architect` or `product-analyst` | `data-engineer` or `finops-engineer` |

## Step 2 — Spawn debate agents (parallel)

For each assigned agent, fill the F9 debate template:

```
# Task: <role> — <one-line mandate>

## What
<role-specific deliverable>

## Where
Debate topic: "<topic>"

## Focus
<role-specific lens>

## Deliverable
A structured argument with the four required fields.

## FILES YOU OWN
None — analysis task. Read-only exploration of docs/codebase permitted if relevant.

## UPSTREAM CONTRACTS
None — isolated debate. You do NOT see other agents' arguments.

## Done-when
- [ ] `position` is filled (<position>)
- [ ] `key_points[]` has ≥3 points with reasoning and citations
- [ ] `risks[]` has ≥2 risks with severity (high/medium/low) and mitigation note
- [ ] `recommendation` is actionable and specific
```

**Per-role fill:**

| Role | `position` | What | Focus |
|---|---|---|---|
| **A — Advocate** | `FOR` | Argument FOR the first/default option | Correctness, maintainability, team velocity; first principles |
| **B — Skeptic** | `AGAINST` | Argument AGAINST the first/default option; edge cases, hidden costs | Risk discovery, operational failure modes, security, long-term cost |
| **C — Synthesizer** | `HYBRID` or `RANKED` | Evaluation of BOTH sides, then a hybrid or ranked recommendation | Balanced trade-off analysis |
| **D — Cost Analyst** | `COST-OPTIMIZED` or `PERFORMANCE-OPTIMIZED` | Cost + performance analysis of the options | Infra cost, query perf, ops overhead, scalability economics |

Spawn each agent with `Task`. Wait for all agents to return. Track timebox per agent; if an agent exceeds it, surface a timeout note and use partial results.

## Step 3 — Synthesize consensus matrix

Output format:

```markdown
# Debate: <topic>

> Slug: `<slug>`
> Agents: <count>
> Date: <ISO date>

## Positions

| Agent | Role | Position | Key Points |
|---|---|---|---|
| A | Advocate | ... | ... |
| B | Skeptic | ... | ... |
| C | Synthesizer | ... | ... |

## Agreement

- <point that ≥2 agents agree on>

## Disagreement

- <point where agents contradict each other, with citations>

## Risk Matrix

| Risk | Severity | Raised By | Mitigation |
|---|---|---|---|
| <risk 1> | high / medium / low | Agent B | ... |

## Recommendation

**Confidence:** high / medium / low
**Rationale:** <2–3 sentences>
**Next Steps:** <concrete actions>
**Dissent:** <if any agent strongly disagrees, note it here>
```

Weight the Synthesizer higher if Agent C was used. Risk severity is set by the agent that raised it; if agents disagree on severity, note the conflict.

**Confidence:**
- `high` — all agents converge, risks are low or mitigated
- `medium` — Synthesizer recommends X but Skeptic raised serious unmitigated risks
- `low` — agents fundamentally disagree, or the topic lacks enough information

## Step 4 — User resolution

Present the `## Recommendation` section. Then `AskUserQuestion`:

- `Adopt the recommendation (Recommended)`
- `Request more analysis on a specific point`
- `Reject — pick a different option`

**Adopt:** log `DEBATE-RESOLVED: <slug> → <recommendation>`, offer to create a task file, stop.

**Request more analysis:** spawn a targeted follow-up agent (`deep-dive` or `diagnose`), append findings as `## Follow-up Analysis`, re-present `AskUserQuestion`.

**Reject:** log `DEBATE-REJECTED: <slug> → user override`, stop.

## Step 5 — Archive

Write the full consensus matrix (with raw agent outputs as appendices if useful) to `.scratch/debate-<slug>.md` with frontmatter:

```yaml
---
topic: "<topic>"
slug: "<slug>"
agents: <count>
date: <ISO date>
resolution: <adopted / rejected / pending>
---
```

## What debate mode does NOT do

- Does NOT implement the recommendation.
- Does NOT conduct open-ended research (use `decide` → `probe` mode).
- Does NOT prioritize among multiple competing tasks (use `kbg:orchestrate`).
- Does NOT write code.
- Does NOT skip the Synthesizer weighting.
