---
name: adr
description: "adr"
disable-model-invocation: true
disable-model-invocation-reason: "records an architectural decision — the user commits to writing an ADR"
---

# ADR

Record decisions that future engineers will need to understand. An ADR is not a victory lap — it's a warning sign and a map.

**When to use:** Framework choices, data model changes, dependency introductions, pattern retirements.

**When NOT to use:** Trivial choices, documenting existing code, decisions with only one viable option.

---

## Procedure

1. **Gate Check** — Confirm 3-condition threshold (METHODOLOGY 3-condition ADR):
   - Hard to reverse?
   - Surprising without context?
   - Result of real trade-off?
   Any 'no' → STOP. Use comment or README instead.

2. **Gather Context** — Date, deciders, stakeholders consulted, constraints, problem statement. Include the gate check rationale in the Context section so future readers understand why this decision warranted an ADR. When a domain-specific technical conflict disqualifies an option (e.g., long-running transactions incompatible with transaction-mode pooling), explain the mechanism so readers understand the exemption rationale without external knowledge.

3. **Document Alternatives** — List 2–4 seriously considered options (include status quo AND the chosen option). For each: description, pros, cons, risks. The chosen option must appear in the table so readers can compare it side-by-side with rejected options. Be honest about chosen option's downsides.

4. **State Decision** — "We will X." Rationale, consequences, mitigations. State the **revisit trigger**: the one condition that, if it changed, would flip this decision (e.g. "if write throughput exceeds 10k/s, revisit"). A decision with no reversal condition is either trivial or untested.

5. **Write ADR** — Markdown in `docs/adr/` or `adr/`:
   ```markdown
   # ADR-NNN: Title
   - Status: proposed
   - Date: YYYY-MM-DD
   - Deciders: @name
   - Consulted: @name
   ## Context
   ## Decision
   ## Consequences
   ## Alternatives Considered
   | Alternative | Pros | Cons | Risks |
   ## Mitigations
   ## Revisit Trigger
   ## Links
   ```
   Status = proposed initially. Move to `accepted` only after review.

6. **Review & Accept** — Share with stakeholders. Incorporate feedback. Change status to `accepted`. Notify affected teams.

7. **Maintain** — Mark deprecated/superseded as system evolves. Update constraints or mitigations. Maintain index at `docs/adr/README.md`.

Done.

## Constraints

- Alternatives must be real, not strawmen.
- Status is truth: proposed → accepted → deprecated → superseded.
- Write for readers 6 months from now who don't have your context.

## METHODOLOGY

- **Rule 1:** Phase 1 gate exists because over-documenting dilutes signal.
- **Rule 7:** Surface stakeholder conflicts in the ADR.
- **Rule 12:** If implementation contradicts accepted ADR, the ADR is wrong — update or deprecate.

## Related

- `/deep-dive` — research before the decision
- `/feature-dev` — implementing the accepted ADR
- `kbg:migrate` — when an ADR leads to deprecation and migration

## Input Contract

- **Trigger phrases:** See `description` in SKILL.md frontmatter.
- **Required context:** The skill expects the user to provide the task scope, target files, or relevant domain context.
- **Optional context:** Prior session summaries, acceptance contracts, or memory pointers may improve output quality.

## Output Format

- **Primary artifact:** Varies by skill — typically a plan, script invocation, structured report, or file modification.
- **Structured sections:** When applicable, output uses markdown sections, tables, or code blocks for clarity.
- **Reference style:** Links to related memories use `[[name]]` wikilink syntax.

## Failure Modes

- **No-op:** Skill exits without action if preconditions are not met (e.g., missing context, already satisfied criteria).
- **Partial output:** If the task scope exceeds what the skill can safely automate, it returns a plan and defers execution to a scoped sub-agent.
- **Human gate:** Any destructive or irreversible action requires explicit user confirmation before proceeding.
