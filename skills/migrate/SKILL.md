---
name: migrate
description: "Deprecate and migrate legacy code, APIs, or dependencies safely. Use when the user says 'migrate to v2', 'upgrade from X to Y', 'deprecate this API', 'extract this module', or when retiring systems, upgrading major versions, or migrating databases. Don't use for: new features (/feature-dev), hot bug fixes (/fix-bug, kbg:hotfix), refactors without a deprecation target, or when rollback is impossible."
disable-model-invocation: true
---

# Migrate

Move from old to new without breaking production. Migration is risk management first, code second.

**When to use:** Legacy deprecation, version upgrades, database migrations, module extraction.

**When NOT to use:** New features, bug fixes, pure refactors, or when rollback is impossible.

---

## Procedure

1. **Gate** — Answer 5 go/no-go questions. Any 'no' → STOP.
   - Can we freeze changes to the legacy surface during migration?
   - Do we have a complete inventory of callers/consumers?
   - Is the new target proven in production (canary, shadow, or non-critical path)?
   - Can we roll back any step in <5 minutes?
   - Is the cost of staying on legacy higher than the cost of migration (including opportunity cost)?
   - **Any 'no' → /deep-dive on the blocker, or stop entirely.**

2. **Inventory** — Find all call sites, detect zombies, map dependencies, audit test coverage.
   - **Caller inventory**: `code-review-graph` MCP (callers, dependents) + `grep` for dynamic references.
   - **Zombie detection**: For each callee, check if it's actually invoked in production paths. Dead code = skip. Flag for `decommission` skill, not migration.
   - **Dependency map**: What does the legacy surface depend on? What depends on it? Cycles = migration must break them first.
   - **Test coverage audit**: Untested callers are high-risk — need coverage before migration or explicit shadow validation.
   - Output: Inventory list with columns: Symbol, Caller Count, Tested?, Active?, Priority (High/Medium/Skip).

3. **Pattern** — Pick the safest pattern for coupling strength and timeline.

   | Pattern | When | Risk | Timeline | Rollback |
   |---|---|---|---|---|
   | **Feature Flag** | Gradual rollout, A/B testing, canary | Low | Hours–days | Toggle off |
   | **Strangler Fig** | Incremental extraction, parallel run | Medium | Weeks–months | Proxy back to legacy |
   | **Adapter** | Legacy must stay alive indefinitely | Low | Days | Remove adapter |
   | **Big Bang** | Small scope, offline data, known downtime | **High** | Hours | Full restore |

   - **Default**: Strangler Fig for code migration. Feature Flag for behavior migration. Adapter for external API migration.
   - **Big Bang is banned** unless: scope <3 files, downtime is acceptable and scheduled, rollback is a database snapshot restore, and user explicitly approves.

4. **Scaffold** — Build new module independently. Write bridge tests (old output == new output). Shadow/dual-write if applicable. Do NOT delete legacy yet.

5. **Cut Over** — One slice at a time. Monitor error rate, latency, output diff. Rollback trigger: anomaly = toggle back immediately.
   - **AskUserQuestion** single-select: "Cut-over: pattern = [feature flag / strangler / adapter / big bang], slice = [description], rollback = [<5 min / known path]. Proceed?"
     - `Cut over now (Recommended when monitoring is ready and rollback path is tested)` — redirect traffic to the new surface
     - `Abort — anomaly detected (Recommended when error rate or latency diverged during shadow)` — toggle back immediately
6. **Decommission** — Safe window (7d standard, 24h trivial <1 file, 30d data). Verify zero legacy traffic. Delete surgically. Archive if needed.
   - **AskUserQuestion** single-select: "Decommission: legacy traffic = [zero / residual], safe window = [7d / 24h / 30d]. Proceed with permanent deletion?"
     - `Delete legacy now (Recommended when traffic is zero and the safe window has passed)` — remove legacy artifacts
     - `Keep legacy (Recommended when residual traffic is detected or the safe window hasn't passed)` — delay decommission

7. **Verify** — Regression test, performance baseline, remove scaffolding, update docs.

---

## Constraints

- Never big-bang at scale.
- Churn Rule: freeze surface during migration.
- Zombie first: identify dead callers before migrating.
- Rollback beats forward.
- Validation before declaration.

## METHODOLOGY

- **Rule 1:** Think before coding. Phase 0 exists because most migration failures start with "we'll figure it out as we go."
- **Rule 2:** Strangler over big-bang.
- **Rule 3:** One caller at a time. Don't refactor the whole module while migrating it.
- **Rule 10:** Each phase ends with go/no-go.
- **Rule 12:** Anomaly during cut-over = rollback immediately.

## Related

- `/feature-dev` — greenfield work
- `/fix-bug` — regression during migration
- `kbg:hotfix` — if migration causes outage
- `/deep-dive` — when Phase 0 answers 'unknown'
- `decommission` skill — for zombie code, not migration targets

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
