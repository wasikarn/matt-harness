---
name: your-skill-name
description: "Action + scenario + quoted triggers. Use when the user says 'X', 'Y', or when Z happens. Do NOT use for: A (use /other), B (use /other), C (spawn other-agent)."
# Optional: disable-model-invocation: true   # Set only for manual-only / destructive / signed workflows
# Optional: context: fork                     # Set only if skill should immediately fork to an agent (rare)
# Optional: model_limitation: "<capability this skill assumes the model has>"
#   e.g. "code-diff grounding (must be able to read a unified diff accurately)"
#   e.g. "json-schema validation (must enforce enum constraints when emitting)"
#   e.g. "long-context retention (must keep the full file in working memory)"
#   Set only for skills whose value depends on a model capability that
#   could change on a model upgrade. The Q3-a quarterly sweep (see
#   docs/harness-decay-cadence.md) walks every skill with this field.
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

## Model Limitation Assumption

If this skill depends on a model capability that could change on a model
upgrade, document it in the `model_limitation:` frontmatter field. The
Q3-a quarterly sweep (see `docs/harness-decay-cadence.md`) walks every
skill with this field and prompts the human to re-verify.

**Example**: a skill that grades PR findings by criticality should declare
`model_limitation: "nuanced criticality judgment (must distinguish Critical
from Important for code-review findings, not collapse them)"`. If a
future model collapses all severities to the same label, the skill
degrades silently — the Q3-a sweep surfaces this for the human to disable
or replace.

## Integration Notes (Project-Specific)

- Link to METHODOLOGY rules this skill aligns with
- Link to other skills/commands this composes with
- Any project-specific conventions or directories
