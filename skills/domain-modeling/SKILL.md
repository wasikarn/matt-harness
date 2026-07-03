---
name: domain-modeling
description: Build and sharpen a project's domain model and ubiquitous language. Use when pinning down domain concepts. Don't use for one-off vocabulary lookups.
metadata.origin: matt-pocock
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active* discipline — challenging terms, inventing edge-case scenarios, and writing the glossary and decisions down the moment they crystallise. (Merely *reading* `CONTEXT.md` for vocabulary is not this skill — that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.)

## File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files lazily — only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch these up — capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` should be totally devoid of implementation details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

1. verify the model before committing — confirm each entity earns its place by a real behavior, not a guess.
   If an entity drifts toward speculative future needs, skip it: modeling what isn't proven fails the model as surely as missing what is. never add an entity without a behavior that exercises it.

---

## Completion criterion

Done when:
- `CONTEXT.md` lists every resolved term and the contradictions you named.
- Every new ADR satisfies the 3-criteria gate (hard to reverse, surprising without context, result of a real trade-off) or is explicitly skipped with reason.
- Any code/glossary contradiction is named or fixed.

## Named Model

This skill is a sense-making surface, not a correctness oracle. The lenses it draws on (cc-thinking-skills):

- *cynefin* — where is this domain on the clear→complicated→complex map? That determines whether a precise glossary is even possible.
- *reversibility* / *opportunity-cost* — frame the 3-criteria ADR gate: irreversible + surprising + traded-off decisions deserve an ADR.
- *systems-thinking* — context boundaries: which terms belong inside this bounded context and which leak across seams.

Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.
