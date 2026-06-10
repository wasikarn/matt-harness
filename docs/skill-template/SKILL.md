---
name: your-skill-name
description: "Action + scenario + quoted triggers. Use when the user says 'X', 'Y', or when Z happens. Do NOT use for: A (use /other), B (use /other), C (spawn other-agent)."
# Optional: disable-model-invocation: true   # Set only for manual-only / destructive / signed workflows
# Optional: context: fork                     # Set only if skill should immediately fork to an agent (rare)
---

# Your Skill Title

One-line summary of what this skill does and why it exists.

**When to use:** Trigger conditions — what user utterances, scenarios, or task shapes activate this skill.

**When NOT to use:** Anti-triggers — what scenarios should redirect elsewhere, with specific deferrals.

---

## Input Contract

What this skill consumes, and what to do when an input is missing — never assume the user pasted everything.

- **Needs:** <inputs the skill consumes — file paths, a diff, an error message>
- **When an input is missing:** gather it autonomously (read the file, run `git diff`) OR ask once with a specific question — never silently guess.
- **Defaults:** <what the skill assumes when unspecified, e.g. "review unstaged `git diff` by default">

## Procedure

1. **Step one**
   - Concrete action
   - Concrete action
   - Success criterion: <verifiable check>

2. **Step two**
   - Concrete action
   - **Gate**: if <condition> → stop / redirect / ask user
   - Success criterion: <verifiable check>

3. **Step three**
   - Concrete action
   - Success criterion: <verifiable check>

## Output Format

Enforce structure with explicit fields, not a prose description — downstream consumers break when the output shape drifts between runs.

```
<explicit field names with types — e.g.>
- **Severity:** Critical | High | Medium | Low
- **Location:** file:line
- **Finding:** <one line: what, and why it matters>
```

## Failure Modes to Avoid

- **Failure mode 1**: What goes wrong and how to prevent it.
- **Failure mode 2**: What goes wrong and how to prevent it.
- **Constraint drifts at the decision point**: a negative constraint ("do NOT skip X", "diagnose before fixing") stated once at the top gets forgotten right when the answer looks obvious. Restate it inline at the step where the drift happens — not only in a header.

## Integration Notes (Project-Specific)

- Link to METHODOLOGY rules this skill aligns with
- Link to other skills/commands this composes with
- Any project-specific conventions or directories
