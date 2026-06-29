---
name: prompt-optimizer
description: Analyze a draft prompt, diagnose gaps, match ECC components, and output a ready-to-paste optimized prompt. Advisory only. Use when the user wants to improve or audit a prompt before sending it to a model. Don't use for executing the underlying task or for runtime prompt engineering inside an agent loop.
---

# Prompt Optimizer

**Advisory only — never executes the task.** Analyze a draft prompt and return a ready-to-paste optimized version.

## Phase 0 — Project detection

Identify the current project type (language, framework, domain) from `CLAUDE.md`, `package.json`, or directory structure.

## Phase 1 — Intent classification

Classify the prompt intent:
- `create` — build something new
- `debug` — diagnose a problem
- `refactor` — restructure existing code
- `explain` — understand something
- `review` — assess quality or correctness
- `plan` — design an approach
- `research` — gather information

## Phase 2 — Scope assessment

Evaluate:
- Is the scope clear or ambiguous?
- Are constraints stated (language, framework, style guide)?
- Is the expected output format defined?
- Is there a success criterion?

Flag any of the above that are missing.

## Phase 3 — ECC component matching

Check if any ECC skills/agents/commands would handle this prompt well:

```bash
find ~/.claude/plugins/cache -name "SKILL.md" 2>/dev/null | xargs /usr/bin/grep -l "[keyword]" 2>/dev/null | head -10
```

List matching components with a one-line rationale for each.

## Phase 4 — Missing context

List what context would improve the result:
- File paths that should be provided
- Constraints to state explicitly
- Examples that would anchor the output
- Definition of done

## Phase 5 — Workflow / model recommendation

Suggest:
- **Model**: haiku / sonnet / opus (per `/model-route` heuristics)
- **Workflow**: single shot / iterative / multi-agent
- **Skill to invoke**: if an ECC/kbg skill matches, name it

## Output format

Produce exactly 5 sections:

```
## Intent
[classification + confidence]

## Gaps
[bulleted list of missing information]

## ECC matches
[table: skill/agent/command | rationale]

## Optimized prompt
[the ready-to-paste prompt, fenced in a code block]

## Workflow recommendation
[model + approach + skill to invoke if applicable]
```
