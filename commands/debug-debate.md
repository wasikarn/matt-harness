---
name: debug-debate
description: "Resolve a technical disagreement by spawning parallel debate agents: Advocate, Skeptic, and Synthesizer debate the topic in isolation, then the lead produces a consensus matrix with ranked risks. Use when the user asks 'which is better', 'should we use X or Y', 'debug debate', 'debate', 'ถกเถียง', 'ประชุมถก', or 'debate ทีม'. or when the user says 'ถกเถียง', 'debate', 'ประชุมถก'. Don't use for: implementation work (use /feature-dev), research (use /deep-dive), or prioritization (use kbg:orchestrate)."
argument-hint: Debate topic or question
---

# /debug-debate — Parallel technical debate

Spawn isolated debate agents to argue a technical decision from multiple angles, then synthesize a consensus matrix with ranked risks and a recommendation.

This command is a **multi-agent analysis wrapper**. The actual analysis is done by read-only debate agents dispatched in parallel; the lead (you) acts as moderator — you do not argue, you synthesize and present.

## Lead-moderator contract

You are the moderator. Three doctrine rules:

1. **You do not take sides.** You dispatch agents, read their arguments, and produce an impartial consensus matrix.
2. **Sonnet for debate agents.** Debate agents run `model: "sonnet"` (analysis, not implementation). You stay on Opus for synthesis + judgment.
3. **Isolated context.** Each debate agent receives ONLY the topic and their role. They do NOT see each other's responses. This prevents anchoring and groupthink.

---

## Step 1 — Parse topic + configure agents

**Goal:** extract the debate topic and agent count from `$ARGUMENTS`.

**Actions:**
1. Parse `$ARGUMENTS`:
   - **Topic:** everything before `--agents` or `--timebox`. If no non-flag text remains, ask the user for the topic.
   - **`--agents=N`:** integer, default `3`. Valid values: `2`, `3`, `4`.
   - **`--timebox=T`:** duration, default `10min`. Soft limit — agents return when done; if they exceed it, surface a timeout note and use partial results.
2. Generate a slug from the topic (lowercase, alphanum + hyphens, ≤60 chars). Example: `Should we use PostgreSQL or MongoDB for the analytics warehouse?` → `postgres-vs-mongodb-analytics-warehouse`.
3. **If topic is missing:** `AskUserQuestion` single-select:
   - `Enter a topic now`
   - `Cancel`
   If cancelled, stop.

**Agent selection table:**

| `--agents` | Agent A (Advocate) | Agent B (Skeptic) | Agent C (Synthesizer) | Agent D (Cost Analyst) |
|---|---|---|---|---|
| `2` | `backend-engineer` or `platform-engineer` | `security-reviewer` or `silent-failure-hunter` | — | — |
| `3` (default) | `backend-engineer` or `platform-engineer` | `security-reviewer` or `silent-failure-hunter` | `code-architect` or `product-analyst` | — |
| `4` | `backend-engineer` or `platform-engineer` | `security-reviewer` or `silent-failure-hunter` | `code-architect` or `product-analyst` | `data-engineer` or `finops-engineer` |

Pick the agent that best matches the domain of the topic (e.g. `platform-engineer` for infrastructure decisions, `backend-engineer` for API/schema decisions). If the topic is cost/performance heavy, prefer `data-engineer`/`finops-engineer` for Agent D.

---

## Step 2 — Spawn debate agents (parallel)

**Goal:** dispatch all debate agents simultaneously. They are read-only (analysis, no Edit/Write/Bash) → **no AskUserQuestion gate required** per `skills/orchestrate/SKILL.md` § Ungated dispatch.

**For each assigned agent, fill this F9 debate template.** Only the title, **What**, **Focus**, and **Position** change per role — the rest is shared:

```
# Task: <role> — <one-line mandate>

## What
<role-specific deliverable, from the table below>

## Where
Debate topic: "<topic>"

## Focus
<role-specific lens, from the table below>

## Deliverable
A structured argument with the four required fields.

## FILES YOU OWN
None — analysis task. Read-only exploration of docs/codebase permitted if relevant.

## UPSTREAM CONTRACTS
None — isolated debate. You do NOT see other agents' arguments.

## Done-when
- [ ] `position` is filled (<position>)
- [ ] `key_points[]` has ≥3 points with reasoning and citations (file:line, doc URL, or commit sha)
- [ ] `risks[]` has ≥2 risks with severity (high/medium/low) and mitigation note
- [ ] `recommendation` is actionable and specific
```

**Per-role fill** — active roles by `--agents`: `2` → A+B · `3` → A+B+C · `4` → A+B+C+D:

| Role | `position` | What | Focus |
|---|---|---|---|
| **A — Advocate** | `FOR` | Argument FOR the first/default option | Correctness, maintainability, team-velocity; argue from first principles and cite real patterns |
| **B — Skeptic** | `AGAINST` | Argument AGAINST the first/default option; find edge cases, hidden costs, failure modes | Risk discovery, operational failure modes, security, hidden long-term cost; deliberately contrarian |
| **C — Synthesizer** | `HYBRID` or `RANKED` | Evaluation of BOTH sides, then a hybrid or ranked recommendation | Balanced trade-off analysis; when a hybrid/phased approach beats picking one winner |
| **D — Cost Analyst** | `COST-OPTIMIZED` or `PERFORMANCE-OPTIMIZED` | Cost + performance analysis of the options | Infra cost, query perf, ops overhead, scalability economics; quantify, flag uncertainties |

**Spawn each agent** with `Task` tool:
- `subagent_type: <selected agent type>`
- `prompt: <the role-specific F9 template, fully filled with the topic>`

**Wait for all agents to return.** Track timebox per agent. If any agent exceeds `--timebox`, surface a timeout note and use whatever partial results they produced.

**Anti-patterns:**
- **Let agents see each other's arguments.** Isolation is the entire point. If the runtime leaks context, stop and restart in a fresh session.
- **Spawn sequentially.** Parallelism is required for independent analysis.
- **Use Opus for debate agents.** Sonnet is sufficient for read-only analysis; Opus is reserved for the lead's synthesis.

---

## Step 3 — Synthesize consensus matrix

**Goal:** read all agent responses and produce an impartial consensus matrix.

**Actions:**
1. Read every returned argument. Verify each has `position`, `key_points[]`, `risks[]`, `recommendation`.
2. Build the consensus matrix with these exact sections:

### Output format

Save the consensus matrix as a markdown report with these headers:

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
- ...

## Disagreement

- <point where agents contradict each other, with citations>
- ...

## Risk Matrix

| Risk | Severity | Raised By | Mitigation |
|---|---|---|---|
| <risk 1> | high / medium / low | Agent B | ... |
| ... | ... | ... | ... |

## Recommendation

**Confidence:** high / medium / low

**Rationale:** <2-3 sentences synthesizing the arguments>

**Next Steps:** <concrete actions>

**Dissent:** <if any agent strongly disagrees, note it here>
```

3. **Weight the Synthesizer higher** if Agent C was used. Their hybrid/ranked recommendation should anchor the final recommendation unless the lead finds a clear flaw in their reasoning.
4. **Risk ranking:** every risk gets `high` (blocks adoption without mitigation), `medium` (manageable with monitoring), or `low` (cosmetic or unlikely). The severity is set by the agent that raised it; if multiple agents disagree on severity, note the conflict.
5. **Confidence level:**
   - `high` — all agents converge on the same recommendation, risks are low or mitigated
   - `medium` — the Synthesizer recommends X but the Skeptic raised serious unmitigated risks
   - `low` — agents fundamentally disagree, or the topic lacks enough information to decide

---

## Step 4 — User resolution

**Goal:** present the consensus matrix and let the user decide.

**Actions:**
1. Present the `## Recommendation` section to the user (not the full raw agent outputs — the matrix is the deliverable).
2. `AskUserQuestion` single-select:
   - `Adopt the recommendation (Recommended)`
   - `Request more analysis on a specific point`
   - `Reject — pick a different option`

**If "Adopt":**
- Log the decision: `DEBATE-RESOLVED: <slug> → <recommendation>`
- Offer to create a task file (`.claude/tasks/<slug>.md`) if the recommendation requires implementation.
- Stop.

**If "Request more analysis":**
- Ask the user which specific point needs deeper analysis.
- Spawn a **targeted follow-up agent** with the F9 template:
  - `subagent_type:` `deep-dive` or `diagnose` (depending on the point — architectural gaps → `deep-dive`, failure-mode concerns → `diagnose`)
  - Prompt includes:
    - The specific point to analyze
    - The original debate topic
    - The relevant agent arguments (only the ones pertaining to the point)
    - `Done-when`: a brief answering the specific question, with citations
- When the follow-up agent returns, append its findings to the consensus matrix as `## Follow-up Analysis` and re-present `AskUserQuestion`.

**If "Reject":**
- Ask the user which option they prefer and why.
- Log: `DEBATE-REJECTED: <slug> → user override`
- Stop.

---

## Step 5 — Archive

**Goal:** save the debate report for future reference.

**Actions:**
1. Write the full consensus matrix (including raw agent outputs as appendices if useful) to `.scratch/debate-<slug>.md`.
2. Frontmatter:
   ```yaml
   ---
   topic: "<topic>"
   slug: "<slug>"
   agents: <count>
   date: <ISO date>
   resolution: <adopted / rejected / pending>
   ---
   ```
3. Report to the user: `Debate archived to .scratch/debate-<slug>.md`

---

## Step 5 done-when (final)

The debate is complete when:

- [ ] Topic is parsed and slug is generated
- [ ] All debate agents spawned in parallel and returned (or timed out with partial results)
- [ ] Consensus matrix is produced with all five required sections (`## Positions`, `## Agreement`, `## Disagreement`, `## Risk Matrix`, `## Recommendation`)
- [ ] User resolution is captured (adopt / more analysis / reject)
- [ ] If follow-up analysis was requested, the follow-up agent returned and the matrix was updated
- [ ] Report is saved to `.scratch/debate-<slug>.md`

---

## What this command does NOT do

- Does NOT implement the recommendation. Use `/feature-dev` or spawn a `backend-engineer` agent for implementation.
- Does NOT conduct open-ended research. Use `/deep-dive` for research briefs.
- Does NOT prioritize among multiple competing tasks. Use `kbg:orchestrate` for prioritization.
- Does NOT write code. Debate agents are read-only; the lead is the moderator.
- Does NOT skip the Synthesizer weighting. If `--agents=3` or `4`, the Synthesizer's recommendation anchors the final verdict unless the lead finds a clear flaw.

---

## Cross-references

- **F9 spawn-prompt template** — `skills/orchestrate/SKILL.md` § Spawn-prompt template. Adapted here for read-only debate roles.
- **Ungated dispatch** — `skills/orchestrate/SKILL.md` § Ungated dispatch. Read-only agents (no Edit/Write/Bash) do not require `AskUserQuestion`.
- **Bounded fan-out (F8.5)** — `skills/orchestrate/SKILL.md` § Bounded fan-out. `/debug-debate` caps at 4 agents, well under the 5 hard cap.
- **Lead doctrine (F8)** — `skills/orchestrate/SKILL.md` § Lead-coordinator doctrine. The moderator is a lead in synthesis mode, not implementation mode.
- **`/deep-dive`** — `commands/deep-dive.md`. For research briefs, not structured debate.
- **`/feature-dev`** — `commands/feature-dev.md`. For implementation after the debate concludes.
- **METHODOLOGY:** Rule 2 (Simplicity first) — default 3 agents is the sweet spot. Rule 4 (Goal-driven) — every debate agent has explicit done-when criteria. Rule 7 (User decides) — the final resolution is a user `AskUserQuestion`, not a model decree.
