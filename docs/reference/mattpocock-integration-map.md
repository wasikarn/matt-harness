# mattpocock-skills integration map

**Status:** Machine-parsed ledger. Harness-audit check 50 (sub-check C) parses this table: every
skill promoted by the installed plugin's own `plugin.json` `skills` array must have a row here, and
the `invocation` column must match the installed frontmatter (`user` ⟺ `disable-model-invocation:
true`, else `model`). Upstream adds/renames a skill → check 50 WARNs until this file routes it or
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
| ask-matt | user | no kbg touchpoint — routing questions go to `/mattpocock-skills:ask-matt` directly (kbg's own routers, `ask-kbg` + `kbg-help`, removed 2026-08-24 #80) |
| code-review | model | adopted — the review surface since the kbg review pipeline retired (2026-08-24 #82) |
| codebase-design | model | deferred — ask-matt's map owns it; kbg's native design agents are `mh:code-architect` / `mh:backend-architect` |
| diagnosing-bugs | model | `docs/agent-voice-extension.md`, `skills/post-mortem/SKILL.md` (input-contract source since `commands/fix-bug` retired, 2026-08-24 #86) |
| domain-modeling | model | `docs/agents/domain.md`, `docs/reference/judgment-ladder.md`, `docs/reference/strategic-judgment.md` |
| grill-with-docs | user | `docs/agents/domain.md` (path into domain-modeling) |
| implement | user | `hooks/advisory/flow-nudge.sh` spec-flow chain (terminal step — `agents/code-implementer.md`, the kbg agent that implemented autonomously, was retired 2026-08-24 #86; the spec-to-ship path now ends at the user typing `/mattpocock-skills:implement`) |
| improve-codebase-architecture | user | `docs/agents/domain.md` (path into domain-modeling) |
| prototype | model | deferred — ask-matt's map owns it |
| research | model | `skills/orchestrate/reference.md`, `docs/reference/strategic-judgment.md` |
| resolving-merge-conflicts | model | deferred — ask-matt's map owns it |
| setup-matt-pocock-skills | user | `README.md` Quick Start step 4 |
| tdd | model | `skills/production-audit` |
| to-spec | user | `hooks/advisory/flow-nudge.sh` spec chain (user-typed step) |
| to-tickets | user | `hooks/advisory/flow-nudge.sh` spec chain (user-typed step) |
| triage | user | deferred — ask-matt's map owns it (user-typed issue router; former `kbg-help` touchpoint removed 2026-08-24 #80) |
| wayfinder | user | `skills/orchestrate/SKILL.md` (boundary: multi-session decision maps) |
| wizard | model | deferred — ask-matt's map owns it (human-only provisioning steps) |
| grill-me | user | deferred — ask-matt's map owns it (batched grilling interview) |
| grilling | model | `hooks/advisory/flow-nudge.sh` spec-chain entry + base plan-first route, `README.md` |
| handoff | user | deferred — ask-matt's map owns it (no kbg equivalent) |
| teach | user | deferred — ask-matt's map owns it |
| to-questionnaire | user | deferred — ask-matt's map owns it (decision → stakeholder questionnaire) |
| wait-what | user | deferred — ask-matt's map owns it (re-pitch last reply) |
| writing-for-agents | model | root `CLAUDE.md` § Skill authoring doctrine, `docs/skill-authoring-conventions.md` (canonical authoring doctrine; renamed from writing-great-skills in matt v1.2.0) |
