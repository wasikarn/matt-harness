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

## Design checks (matt-pocock authoring doctrine)

Run before publishing. Each item must be checkable. See CLAUDE.md § "Skill authoring doctrine" for the full rule.

- [ ] **Leading word** — frontmatter description opens with a coined term that recruits a pretrained prior.
- [ ] **≤25 words** in description (trim, do not remove triggers).
- [ ] **One trigger** per branch in description (no synonym-rewrite).
- [ ] **Completion criterion** on every procedure step (resists premature completion).
- [ ] **No-op test** passed — each sentence changes behaviour vs default; remove the ones that don't.
- [ ] **Two-cut check** — split-by-invocation or split-by-sequence only when the cut earns it; otherwise sharpen the criterion (kbg is MAXIMAL-BOUNDED).
- [ ] **Failure mode** named at the drift step inline, not only in a header.
- [ ] **Provenance** — if imported from matt-pocock, ECC, or another upstream, add `metadata.origin: <upstream>` to frontmatter.
- [ ] **Named Model footer** — if the skill makes load-bearing reasoning/judgment choices, add a `## Named Model` footer citing cc-thinking-skills lenses from `docs/reference/reasoning-models.md`, framed as a scaffold (not proof of correctness). Skip for purely mechanical/catalog surfaces. **Same edit, update the catalog row too**: `reasoning-models.md`'s unified index table only reflects reality if every new footer updates the cited model's `status`/`kbg home` cells there — confirmed drift 2026-07-14 (`theory-of-constraints`/`leverage-points` sat marked "considered — no live anchor" for 11 days after `agents/performance-optimizer.md` applied them in v0.30.2).
- [ ] **Suggested next step** — if this is a workflow skill a user runs as a discrete step, end with a `Suggested next step:` marker (outcome-branched; skills `kbg:<name>`, commands `/<name>`). Skip for reference/pattern/catalog surfaces and terminal workflows.

# Your Skill Title

One-line summary of what this skill does and why it exists.

**When to use:** Trigger conditions — what user utterances, scenarios, or task shapes activate this skill.

**When NOT to use:** Anti-triggers — what scenarios should redirect elsewhere, with specific deferrals.

---

<!-- The sections below are OPTIONAL. The blanket "every skill MUST carry
Input Contract / Output Format / Failure Modes" rule was retired 2026-06-16
(audit #31.1) — it manufactured byte-identical filler across 29/37 skills.
Include a section ONLY where the skill has a real I/O contract worth stating
(CLAUDE.md § "Adding a new component"). Default copy = frontmatter + title +
When-to-use. Delete what you don't fill in. -->

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
