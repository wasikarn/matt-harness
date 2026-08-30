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
`/mattpocock-skills:<name>` per `docs/METHODOLOGY.md`'s "disable-model-invocation surfaces are
user-only" section (lines 45-47).

"Deferred" rows follow the standing v0.46.0 separate-fleet design: matt's internal chaining map is
owned by `/mattpocock-skills:ask-matt`, and kbg doesn't duplicate it — a row goes from deferred to
routed only when a kbg surface has a concrete reason to name the skill.

| skill | invocation | kbg touchpoint / deferral |
|---|---|---|
| ask-matt | user | the actual routing layer — `CLAUDE.md`'s "Finding a surface" section sends routing questions to `/mattpocock-skills:ask-matt` directly (kbg's own routers, `ask-kbg` + `kbg-help`, removed 2026-08-24 #80) |
| code-review | model | adopted — the review surface since the kbg review pipeline retired (2026-08-24 #82); shares its bare name with Claude Code's own first-party bundled skill (`/code-review`, alias `/review`) — namespacing means no real conflict, but bare `/code-review` typed from muscle memory resolves to Anthropic's skill, not matt's |
| codebase-design | model | deferred — ask-matt's map owns it; kbg's native design agents are `mh:code-architect` / `mh:backend-architect` |
| diagnosing-bugs | model | `docs/agent-voice-extension.md`, `skills/workflow/post-mortem/SKILL.md` (input-contract source since `commands/fix-bug` retired, 2026-08-24 #86) |
| domain-modeling | model | `docs/agents/domain.md`, `docs/reference/judgment-ladder.md`, `docs/reference/strategic-judgment.md` |
| grill-with-docs | user | `docs/agents/domain.md` (path into domain-modeling) |
| implement | user | `hooks/advisory/flow-nudge.sh` spec-flow chain (terminal step — `agents/code-implementer.md`, the kbg agent that implemented autonomously, was retired 2026-08-24 #86; the spec-to-ship path now ends at the user typing `/mattpocock-skills:implement`) |
| improve-codebase-architecture | user | `docs/agents/domain.md` (path into domain-modeling) |
| prototype | model | deferred — ask-matt's map owns it |
| research | model | `skills/workflow/orchestrate/reference.md`, `docs/reference/strategic-judgment.md` |
| resolving-merge-conflicts | model | deferred — ask-matt's map owns it |
| setup-matt-pocock-skills | user | `README.md` Quick Start step 4 |
| tdd | model | `skills/review/production-audit/SKILL.md` |
| to-spec | user | `hooks/advisory/flow-nudge.sh` spec chain (user-typed step) |
| to-tickets | user | `hooks/advisory/flow-nudge.sh` spec chain (user-typed step) |
| triage | user | deferred — ask-matt's map owns it (user-typed issue router; former `kbg-help` touchpoint removed 2026-08-24 #80) |
| wayfinder | user | `skills/workflow/orchestrate/SKILL.md` (boundary: multi-session decision maps) |
| wizard | model | deferred — ask-matt's map owns it (model-invoked deliberately, so the agent can reach for it mid-build the moment it hits a step only a human can perform — PR #680; the skill walks a human through that step, it isn't itself human-only) |
| grill-me | user | deferred — ask-matt's map owns it (batched grilling interview) |
| grilling | model | `hooks/advisory/flow-nudge.sh` spec-chain entry + base plan-first route, `README.md` |
| handoff | user | deferred — ask-matt's map owns it (no kbg equivalent) |
| teach | user | deferred — ask-matt's map owns it |
| to-questionnaire | user | deferred — ask-matt's map owns it (decision → stakeholder questionnaire) |
| wait-what | user | deferred — ask-matt's map owns it (re-pitch last reply) |
| writing-for-agents | model | root `CLAUDE.md`'s Skill authoring doctrine section, `docs/skill-authoring-conventions.md` (canonical authoring doctrine; renamed from writing-great-skills in matt v1.2.0) |

## Reverse handoffs

Places where matt names a real, undocumented gap in his own docs and an mh mechanism happens to
answer it — not designed as a fix, discovered by reading matt's own text closely. Written up
2026-08-30 after two of these were found once, forgotten (no memory, no doc, no git trace), and had
to be rediscovered from scratch on a second sweep. Each entry: matt's own quote, mh's answer, and
the caveat stated plainly — a partial answer written up as partial, not as a clean win.

1. **triage's missing "deferred/not-now" state ↔ mh's `parked` label.** Matt's own
   `docs/engineering/triage.md`: *"Five states aren't enough... Matt has agreed the blocked case is
   real... None of it has shipped. The workaround people use is a repo-local extra label."* mh's
   `docs/agents/triage-labels.md`'s `parked` label is exactly that workaround. Partial: answers 1 of
   matt's 3 named shapes (deferred/not-now), not `blocked`-on-issue or awaiting-verification.

2. **research's no cross-session reuse ↔ mh's qmd-first rule.** Matt's own
   `docs/engineering/research.md`: *"Does a later session reuse what an earlier run found? No...
   The shipped skill does not solve it."* mh's `CLAUDE.md` "Research: check qmd before web search"
   section is a standing, automatic semantic-search-first rule — qualitatively past "fetch it
   again." Caveat: `qmd` isn't bundled with the plugin, operator-environment-dependent.

3. **improve-codebase-architecture's CDN-fragile HTML report ↔ mh's diagram-design doctrine.**
   Matt's own `docs/engineering/improve-codebase-architecture.md`: *"The report loads Tailwind and
   Mermaid from CDNs, so it needs network access when you open it, and it breaks silently when
   something blocks those scripts... This is an open issue and a real rough edge."* — and names the
   fix himself: *"The workaround is to ask for inline CSS and hand-built SVG diagrams instead of
   the CDN scaffold."* mh's user-global CLAUDE.md points at the third-party `diagram-design` skill,
   whose output is exactly that self-contained single HTML file. Caveat: third-party plugin, and it
   replaces the diagram half of matt's report shape, not the whole report.

4. **implement's no parallel-session support ↔ mh's worktree-guard.py.** Matt's own
   `docs/engineering/implement.md`: *"one field report describes a `git commit --amend` in one
   session landing on another session's commit, a stash vanishing from `refs/stash`, and commits
   landing on the wrong branch, all in a single afternoon across three issues."* mh's
   `hooks/gates/worktree-guard.py` auto-redirects concurrent-session writes into per-session
   worktrees. Three caveats, and the third is matt's own: opt-in via `MH_GUARDED_WORKSPACE` (no
   default); Bash-mediated writes — the exact `--amend` case — deny rather than redirect; and matt
   rules the whole worktree approach a partial answer, *"note that `refs/stash` is shared across
   worktrees too, so worktrees alone do not fix the stash case."* mh's answer is worktree-based, so
   it inherits that limit unchanged.
