---
name: ideate
description: "Explicit user entry point for divergent ideation. Type `/ideate <problem>` to run the kbg:ideate skill with a clear opt-in signal, bypassing the auto-fire pre-flight gate. Advisory-only: it invokes the existing ideate skill rather than duplicating the algorithm."
disable-model-invocation: true
disable-model-invocation-reason: "This is a user-only slash command. The model should never invoke it unprompted because the skill already auto-fires on vague open-ended prompts. The command exists to give users an explicit, discoverable trigger."
---

# The ideate command

User-facing trigger for the `kbg:ideate` divergent-ideation skill.

When the user types `/ideate` followed by a problem statement, invoke the
`kbg:ideate` skill via the Skill tool with the user's text as the
problem. Do not re-implement the algorithm here; the skill owns Phase 1–3.

## Usage

```
/ideate How should we design a feature flag service?
/ideate What naming convention should we use for our event schemas?
/ideate We're seeing flaky CI; brainstorm root causes we haven't considered.
```

## Behaviour

1. Extract the problem text from the command invocation (everything after `/ideate`).
2. Call `Skill` with `name: "ideate"` and pass the problem text as the user prompt.
3. The skill's own pre-flight gate will see the explicit invocation and skip the
   self-judge Step 2 (per `skills/ideate/SKILL.md` Step 1).

## What this command does NOT do

- Does **not** duplicate the ideate algorithm (frames, scoring, deepening).
- Does **not** auto-fire on vague prompts (that is the skill's job).
- Does **not** bypass the daily-budget or convergence warnings surfaced by
  the SessionStart hooks; those still appear in the brief.
