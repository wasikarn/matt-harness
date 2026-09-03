# mattpocock-skills integration map

**Status:** Machine-parsed ledger. Harness-audit check 50 (sub-check C) parses this table: every
skill promoted by the installed plugin's own `plugin.json` `skills` array must have a row here, and
the `invocation` column must match the installed frontmatter (`user` ⟺ `disable-model-invocation:
true`, else `model`). Upstream adds/renames a skill → check 50 WARNs until this file routes it or
records why not. Re-verify whenever the `mattpocock-skills` cache version changes (same habit as
the third-party same-version stale trap in root `CLAUDE.md`).

Harness-audit check 67 (GH #119) reads this same table's column 1 for a second purpose: computing
the "composer-not-creator" doctrine (root `CLAUDE.md`) at creation time — WARN when a new
skill/agent's own name or description looks like it might duplicate one of these skill names, unless
the file carries the literal marker `composer-not-creator: checked, genuinely new`. Purely a static
read of this checked-in table, not the live plugin cache — a row added or renamed here changes what
check 67 flags on the very next audit run.

**Format contract:** column 1 = skill name exactly as installed; column 2 = `model` or `user`
(nothing else); column 3 = free prose — the kbg surface(s) that route/name it, or an explicit
deferral with a reason. Gated (`user`) skills are cited in kbg surfaces as the literal slash form
`/mattpocock-skills:<name>` per `docs/METHODOLOGY.md`'s "disable-model-invocation surfaces are
user-only" section (lines 49-55).

"Deferred" rows follow the standing v0.46.0 separate-fleet design: matt's internal chaining map is
owned by `/mattpocock-skills:ask-matt`, and kbg doesn't duplicate it — a row goes from deferred to
routed only when a kbg surface has a concrete reason to name the skill.

**No-counterpart agents, re-verified 2026-09-01:** `agents/performance-optimizer.md` has no
matt-skill counterpart for its own lane — deliberately unrouted, not a gap. (`a11y-architect.md`
and `build-error-resolver.md`, the other two agents this paragraph originally named, 2026-08-31,
were themselves deleted in an earlier sweep — dropped from this list rather than left as dead
citations.)

| skill | invocation | kbg touchpoint / deferral |
|---|---|---|
| ask-matt | user | the actual routing layer — `docs/reference/adding-a-surface.md`'s "Finding a surface" section sends routing questions to `/mattpocock-skills:ask-matt` directly (kbg's own routers, `ask-kbg` + `kbg-help`, removed 2026-08-24 #80) |
| code-review | model | adopted — the review surface since the kbg review pipeline retired (2026-08-24 #82); shares its bare name with Claude Code's own first-party bundled skill (`/code-review`, alias `/review`) — namespacing means no real conflict, but bare `/code-review` typed from muscle memory resolves to Anthropic's skill, not matt's. Confirmed collision, resolved as by-design (2026-09-01, #118): reproduced live — Skill-calling this from inside a dispatched subagent has BOTH its internal Standards/Spec dispatches denied by `hooks/gates/agent-recursion-guard.sh` (caller carries `agent_id`), producing no report at all. Deliberately not carved out (the gate can't distinguish documented internal fan-out from rogue re-orchestration, and any discriminant would be forgeable). Hard rule: invoke `mattpocock-skills:code-review` from the main session only, never from inside a dispatched subagent |
| codebase-design | model | routed — `docs/METHODOLOGY.md`'s plan-mode paragraph names it for deep-module vocabulary mid-blueprint; `agents/code-architect.md` and `agents/backend-architect.md` boundary lines point to it for the same reason; kbg's native design agents are `mh:code-architect` / `mh:backend-architect` for the blueprint itself |
| diagnosing-bugs | model | `docs/agent-voice-extension.md`, `skills/workflow/post-mortem/SKILL.md` (input-contract source since `commands/fix-bug` retired, 2026-08-24 #86) |
| domain-modeling | model | `docs/agents/domain.md`, `docs/reference/judgment-ladder.md`, `docs/reference/strategic-judgment.md` |
| grill-with-docs | user | `docs/agents/domain.md` (path into domain-modeling) |
| implement | user | `hooks/advisory/flow-nudge.sh` spec-flow chain (terminal step — `agents/code-implementer.md`, the kbg agent that implemented autonomously, was retired 2026-08-24 #86; the spec-to-ship path now ends at the user typing `/mattpocock-skills:implement`); see Reverse handoffs §4 |
| improve-codebase-architecture | user | `docs/agents/domain.md` (path into domain-modeling); `docs/METHODOLOGY.md`'s plan-mode paragraph names it for a whole-repo architecture pass; see Reverse handoffs §3 |
| prototype | model | deferred — no mh surface produces throwaway spikes; the build/don't-build call is Rule 2's territory instead |
| research | model | `skills/workflow/orchestrate/reference.md`, `docs/reference/strategic-judgment.md`, `contexts/research.md` ("not this frame's job" line, if the companion plugin is installed); see Reverse handoffs §2. Same main-session-only rule as `mattpocock-skills:code-review` (#118): this skill spins up its own background agent, which `agent-recursion-guard.sh` denies from inside a dispatched subagent |
| resolving-merge-conflicts | model | deferred — `hooks/gates/merge-door.sh` / `mh:ship-merge` own the merge decision; this skill owns the conflict edit itself — adjacent, with one known runtime friction: its step 5 "stage everything" hits `gate:bash:irrecoverable`'s `git add -A` deny (mh doctrine deliberately wins; stage by name per the deny message's own hint) |
| setup-matt-pocock-skills | user | `README.md` Quick Start step 4. Durable generated output: `docs/agents/{issue-tracker,domain,triage-labels}.md` — re-running the skill regenerates these three files from scratch, wiping any mh customization (including their provenance header) each time; re-add it by hand after a re-run |
| tdd | model | `skills/review/production-audit/SKILL.md` |
| to-spec | user | `hooks/advisory/flow-nudge.sh` spec chain (user-typed step) |
| to-tickets | user | `hooks/advisory/flow-nudge.sh` spec chain (user-typed step) |
| triage | user | routed — `docs/agents/triage-labels.md`'s provenance header names `/mattpocock-skills:triage` as a runtime reader of that file; the `parked` label documented there is the actual cross-reference, see Reverse handoffs §1 (user-typed issue router; former `kbg-help` touchpoint removed 2026-08-24 #80) |
| wayfinder | user | `skills/workflow/orchestrate/SKILL.md` (boundary: multi-session decision maps) |
| wizard | model | routed — `docs/METHODOLOGY.md`'s disable-model-invocation section names it for a human-only multi-step procedure the model would otherwise have to spell out by hand (model-invoked deliberately, so the agent can reach for it mid-build the moment it hits a step only a human can perform — PR #680; the skill walks a human through that step, it isn't itself human-only) |
| grill-me | user | routed — `docs/METHODOLOGY.md` Rule 3 names it for a live batched interview; `agents/requirement-analyst.md`'s boundary line distinguishes it from analyzing an already-written requirement (batched grilling interview) |
| grilling | model | `hooks/advisory/flow-nudge.sh` spec-chain entry + base plan-first route, `README.md`. Same main-session-only rule as `mattpocock-skills:code-review` (#118): its research step dispatches a sub-agent, which `agent-recursion-guard.sh` denies from inside a dispatched subagent |
| handoff | user | `BOUNDARY.md`'s generated route (`skills/inventory/scripts/inventory-boundary.sh`) |
| teach | user | routed — `output-styles/crisp.md`'s "teach the durable frame" bullet names it as the on-demand tool for turning a one-off explanation into something durable and reusable |
| to-questionnaire | user | routed — `docs/METHODOLOGY.md` Rule 3 names it for turning a settled decision into a written stakeholder questionnaire |
| wait-what | user | `output-styles/crisp.md`'s repair bullet (re-pitch last reply) |
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

## Upstream watch list

Unregistered in matt's own `plugin.json` — local-clone-only (`~/Codes/Personals/mattpocock-skills`
`skills/in-progress/*`, `skills/misc/*`), matt's own stated policy that these can vanish or reshape
without warning before graduating. Not in the ledger table above because they aren't installed
skills yet; tracked here so a future integration pass doesn't start from zero.

- **`implement-spec`, `retro`** — both are themselves delegation-pattern designs; worth adopting
  their stated principle regardless of graduation status: coding standards belong to the
  reviewer, not the implementer, because the implementer already carries the most context
  pressure.
- **`claude-handoff`** — session state capture, predecessor shape to the now-graduated
  `/mattpocock-skills:handoff`.
- **`setup-ts-deep-modules`** — transferable pattern regardless of TS-specificity: prove the
  rules bite, don't just document them.
- **`git-guardrails-claude-code`** — study-only. Root `CLAUDE.md` already forbids running its
  setup in this repo (its unconditional `git push` block conflicts with this repo's own
  push-confirmation workflow).
