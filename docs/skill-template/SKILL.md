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
#   could change on a model upgrade. The quarterly cadence (see
#   docs/harness-decay-cadence.md) walks every skill with this field.
---

## Design checks (matt-pocock authoring doctrine)

Run before publishing. Each item must be checkable. See CLAUDE.md's "Skill authoring doctrine" section for the full rule.

- [ ] **Leading word** — frontmatter description opens with a coined term that recruits a pretrained prior.
- [ ] **≤25 words** in description (trim, do not remove triggers).
- [ ] **One trigger** per branch in description (no synonym-rewrite).
- [ ] **Completion criterion** on every procedure step (resists premature completion).
- [ ] **No-op test** passed — each sentence changes behaviour vs default; remove the ones that don't.
- [ ] **Two-cut check** — split-by-invocation or split-by-sequence only when the cut earns it; otherwise sharpen the criterion (kbg is MAXIMAL-BOUNDED).
- [ ] **Evals-first** — before drafting the body, write 3 concrete example requests this skill
  should handle (what's asked, what files/context it needs, what correct behavior looks like)
  and check whether Claude already handles them acceptably WITHOUT the skill. If it does, the
  skill may not need to exist; only write instructions that close the gaps the baseline
  actually showed. Not a formal eval harness (native `claude plugin eval` covers that for
  downstream products) — a lighter authoring-time discipline. See
  `docs/skill-authoring-conventions.md`.
- [ ] **Degrees of freedom** — match instruction specificity to how much a wrong deviation
  costs: prose heuristics for a genuinely open judgment call with several valid approaches, a
  parameterized script/pseudocode for a semi-structured task, an exact script with no deviation
  allowed for a fragile or high-stakes operation. Don't over-specify a judgment call or
  under-specify a fragile one. See `docs/skill-authoring-conventions.md`.
- [ ] **Failure mode** named at the drift step inline, not only in a header.
- [ ] **Provenance** — if imported from matt-pocock, ECC, or another upstream, add a nested
  `metadata:` map to frontmatter (`metadata:` on its own line, `  origin: <upstream>` indented
  under it — NOT the flat dotted key `metadata.origin: <upstream>`, which YAML treats as a
  literal top-level key named `metadata.origin`, not a nested field; `skills/review/pr/SKILL.md`
  shipped that exact mistake until fixed 2026-08-29). See `skills/meta/compress-docs/SKILL.md`
  for the correct shape.
- [ ] **Named Model footer** — if the skill makes load-bearing reasoning/judgment choices, add a `## Named Model` footer citing cc-thinking-skills lenses from `docs/reference/reasoning-models.md`, framed as a scaffold (not proof of correctness). Skip for purely mechanical/catalog surfaces. **Same edit, update the catalog row too**: `reasoning-models.md`'s unified index table only reflects reality if every new footer updates the cited model's `status`/`kbg home` cells there — confirmed drift 2026-07-14 (`theory-of-constraints`/`leverage-points` sat marked "considered — no live anchor" for 11 days after `agents/performance-optimizer.md` applied them in v0.30.2).
- [ ] **Suggested next step** — if this is a workflow skill a user runs as a discrete step, end its Output/Summary
  phase with `**Suggested next step:**` (optionally prefixed by that phase's own step number, e.g. `4. **Suggested
  next step:**`) followed by one outcome-branched bullet per case: `- <outcome> → \`mh:<name>\`` for a model-invocable
  skill, or the literal `/mh:<name>` / `/mattpocock-skills:<name>` for a gated one (`disable-model-invocation: true`)
  the user must type themselves. Passive suggestion only — never "invoke X now" or auto-chain. Skip for
  reference/pattern/catalog surfaces and terminal workflows. `commands/` retired 2026-08-25 (#112); there is no
  command form to cite anymore. Full convention + canonical example: `docs/skill-authoring-conventions.md`.

# Your Skill Title

One-line summary of what this skill does and why it exists.

**When to use:** Trigger conditions — what user utterances, scenarios, or task shapes activate this skill.

**When NOT to use:** Anti-triggers — what scenarios should redirect elsewhere, with specific deferrals.

---

<!-- The sections below are OPTIONAL. The blanket "every skill MUST carry
Input Contract / Output Format / Failure Modes" rule was retired 2026-06-16
(audit #31.1) — it manufactured byte-identical filler across 29/37 skills.
Include a section ONLY where the skill has a real I/O contract worth stating
(CLAUDE.md's "Adding or removing a surface" section). Default copy = frontmatter + title +
When-to-use. Delete what you don't fill in. -->

## Input Contract

What this skill consumes, and what to do when an input is missing — never assume the user pasted everything.

- **Needs:** <inputs the skill consumes — file paths, a diff, an error message. If the skill also depends on an external tool or connector to function at all (an authenticated `gh` CLI, an issue-tracker MCP server, a browser-rendering path), name it here too — `allowed-tools` only grants permission to call a tool, it says nothing about whether that tool is installed or authenticated. Only add this when a real prerequisite exists; most skills have none.>
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
quarterly cadence (see `docs/harness-decay-cadence.md`) walks every
skill with this field and prompts the human to re-verify.

**Example**: a skill that grades PR findings by criticality should declare
`model_limitation: "nuanced criticality judgment (must distinguish Critical
from Important for code-review findings, not collapse them)"`. If a
future model collapses all severities to the same label, the skill
degrades silently — the quarterly cadence surfaces this for the human to
disable or replace.

## Integration Notes (Project-Specific)

- Link to METHODOLOGY rules this skill aligns with
- Link to other skills/commands this composes with
- Any project-specific conventions or directories
