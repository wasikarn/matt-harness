# mattpocock-skills integration map

**Status:** Machine-parsed ledger. Harness-audit check 55 (sub-check C) parses this table: every
skill promoted by the installed plugin's own `plugin.json` `skills` array must have a row here, and
the `invocation` column must match the installed frontmatter (`user` ⟺ `disable-model-invocation:
true`, else `model`). Upstream adds/renames a skill → check 55 WARNs until this file routes it or
records why not. Re-verify whenever the `mattpocock-skills` cache version changes (same habit as
the third-party same-version stale trap in root `CLAUDE.md`).

**Format contract:** column 1 = skill name exactly as installed; column 2 = `model` or `user`
(nothing else); column 3 = free prose — the kbg surface(s) that route/name it, or an explicit
deferral with a reason. Gated (`user`) skills are cited in kbg surfaces as the literal slash form
`/mattpocock-skills:<name>` per root `CLAUDE.md` § Disable-Model-Invocation Surfaces.

"Deferred" rows follow the standing v0.46.0 separate-fleet design: matt's internal chaining map is
owned by `/mattpocock-skills:ask-matt`, and kbg doesn't duplicate it — a row goes from deferred to
routed only when a kbg surface has a concrete reason to name the skill.

| skill | invocation | kbg touchpoint / deferral |
|---|---|---|
| ask-matt | user | `commands/ask-kbg.md` — "The other fleet" defers matt's map to it (with staleness caveat) |
| code-review | model | deferred — ask-matt's map owns it; kbg's native review path is `kbg:code-reviewer` / `kbg:review-pr` |
| codebase-design | model | deferred — ask-matt's map owns it; kbg's native design agents are `kbg:code-architect` / `kbg:backend-architect` |
| diagnosing-bugs | model | `skills/task-prep` (hypothesis-as-task route), `docs/agent-voice-extension.md` |
| domain-modeling | model | `skills/decide` (ADR handoff), `docs/agents/domain.md`, `docs/reference/judgment-ladder.md`, `docs/reference/strategic-judgment.md` |
| grill-with-docs | user | `docs/agents/domain.md` (path into domain-modeling) |
| implement | user | `agents/code-implementer.md` (boundary: kbg agent implements autonomously; matt's is user-typed) |
| improve-codebase-architecture | user | `docs/agents/domain.md` (path into domain-modeling) |
| prototype | model | deferred — ask-matt's map owns it |
| research | model | `commands/kbg-help.md` (DEFINE row), `skills/orchestrate/reference.md`, `docs/reference/strategic-judgment.md` |
| resolving-merge-conflicts | model | deferred — ask-matt's map owns it |
| setup-matt-pocock-skills | user | `README.md` Quick Start step 4 |
| tdd | model | `skills/task-prep` (TDD-shape route), `skills/production-audit` |
| to-spec | user | `hooks/advisory/flow-nudge.sh` spec chain (user-typed step) |
| to-tickets | user | `hooks/advisory/flow-nudge.sh` spec chain (user-typed step) |
| triage | user | `commands/kbg-help.md` (PLAN row; user-typed issue router) |
| wayfinder | user | `skills/orchestrate/SKILL.md` (boundary: multi-session decision maps) |
| wizard | model | `commands/ask-kbg.md` matt-only list (human-only provisioning steps) |
| grill-me | user | `commands/ask-kbg.md` matt-only list (batched grilling interview) |
| grilling | model | `hooks/advisory/flow-nudge.sh` spec-chain entry, `skills/task-prep` (idea-shape route), `README.md` |
| handoff | user | `commands/ask-kbg.md` "Crossing sessions" (no kbg equivalent) |
| teach | user | deferred — ask-matt's map owns it |
| to-questionnaire | user | `commands/ask-kbg.md` matt-only list (decision → stakeholder questionnaire) |
| wait-what | user | `commands/ask-kbg.md` matt-only list (re-pitch last reply) |
| writing-for-agents | model | root `CLAUDE.md` § Skill authoring doctrine, `docs/skill-authoring-conventions.md` (canonical authoring doctrine; renamed from writing-great-skills in matt v1.2.0) |
