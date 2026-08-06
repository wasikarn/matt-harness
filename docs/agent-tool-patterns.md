# Agent tool patterns: allowlist vs denylist

**Status:** Convention reference. Owned by the harness. Subject to the [Permission re-audit cadence](./harness-decay-cadence.md#permission-re-audit) (quarterly).

The Claude Code vendor schema offers two patterns for restricting an agent's tool access:

- **`tools:` (allowlist)** — list the tools the agent **may** use. Anything not listed is implicitly blocked.
- **`disallowedTools:` (denylist)** — list the tools the agent **may not** use. Everything else is implicitly available.

The kbg-harness convention is to prefer **`tools:` (allowlist)** for new agents. This document explains why, when to consider the denylist alternative, and what each pattern looks like in practice.

## 1. `tools:` (allowlist) — the kbg-harness default

**What it is:** an explicit list in the agent's YAML frontmatter.

**Example** (from `agents/code-reviewer.md`):

```yaml
tools: Read, Grep, Glob, Bash
```

**What it means:** the agent may use `Read`, `Grep`, `Glob`, and `Bash`. It may **not** use `Write`, `Edit`, `NotebookEdit`, `WebFetch`, `WebSearch`, `Task`, or any other tool the vendor offers.

**What it excludes:** everything not in the list. The list is the contract.

**When to choose it:**

- The agent's job is read-only or has a tightly-scoped write surface (validators, reviewers, explorers).
- The team wants a single source of truth for "what can this agent do" — answer is the `tools:` line.
- The agent is a specialist (single domain) rather than a generalist (multi-domain with selective restrictions).

**Why we prefer it (every agent in this harness uses it):**

1. **Readable at a glance.** A reader of the agent's frontmatter sees the full capability set in one line. The constraint is the list, not the diff from a default.
2. **No implicit inheritance.** If the vendor's default toolset changes, the agent's tools don't change with it. The contract is stable.
3. **Safer default.** Adding a new tool to the vendor's default set is a **silent capability expansion** for denylisted agents but a **no-op** for allowlisted agents. We err on the side of explicit over implicit.
4. **Was paired with a runtime Bash-gate, now doctrine-only.** Validators (e.g. `code-reviewer`, `security-reviewer`) use `tools: [Bash]` for read-only inspection. `hooks/gates/validator-bash-guard.sh` blocked mutation at runtime through v0.4.18, but was deleted in the v0.6.0 "reset: rebuild from scratch" cut (`c4521023`) and never rebuilt — its deny-pattern logic and env-var bypass predate this harness's later no-env-var-bypass doctrine (see `verifier-protect.sh`), so a straight restore isn't compatible with current conventions. Today the read-only constraint is enforced by the allowlist (no `Write`/`Edit` grant) plus prompt doctrine only — there is no runtime backstop if a validator's prompt drifts toward a mutating Bash command.

**Tradeoffs (when allowlist is the wrong choice):**

- The agent inherits a large default toolset and only needs to block 1-2 specific tools. In that case, the denylist is shorter to write.
- The agent's toolset is expected to grow as the vendor adds new tools, and the team is OK with implicit expansion. (We do not recommend this — the loss of explicit-over-implicit usually costs more than the line saved.)

## 2. `disallowedTools:` (denylist) — the vendor alternative

**What it is:** an explicit list of tools the agent may **not** use.

**Example** (hypothetical; kbg-harness does not currently use this pattern):

```yaml
disallowedTools: Write, Edit, NotebookEdit
```

**What it means:** the agent inherits the vendor's default toolset minus `Write`, `Edit`, and `NotebookEdit`. It may use `Read`, `Grep`, `Glob`, `Bash`, `WebFetch`, `WebSearch`, `Task`, and anything else not in the denylist.

**What it excludes:** only the listed tools. Everything else is implicitly available.

**When to consider it:**

- The agent needs most of the default toolset, and the denylist is a small adjustment (1-3 tools).
- The agent is a generalist (multi-domain) and the team does not want to enumerate the full capability set in the frontmatter.
- The vendor schema explicitly supports it (it does — see `code.claude.com/docs/en/sub-agents`, the actual subagent frontmatter reference), and the team is OK with the implicit-inheritance tradeoff.

**Why kbg-harness does not currently use it:**

- Our agents are specialists, not generalists. The allowlist is shorter to write, not longer.
- The "implicit inheritance" property is an antipattern for us: when the vendor adds a new tool (e.g. a new MCP bridge), we want a human to decide whether each existing agent should pick it up. Allowlist makes that decision visible in the PR; denylist hides it.

## 3. Our convention

**Default for new agents:** use `tools:` (allowlist). Pick the smallest set of tools the agent needs to do its job. If the agent needs Bash, list it; if the agent is read-only, omit it.

**Reserve `disallowedTools:` for cases where:**

- The agent is a generalist and the allowlist would be longer than 6-7 tools, OR
- The team is explicitly opting into implicit-inheritance (rare; document the reason in the agent's frontmatter comment or `## Why this role exists` section).

**When modifying an existing agent's tools:**

1. Read the agent's `## Domain focus` and `## Cross-role boundaries` sections first — the right toolset usually follows from the domain.
2. Check the [Permission re-audit cadence](./harness-decay-cadence.md#permission-re-audit) — the last quarterly review date is at the top of that section.
3. If the change is non-trivial (adding `Write` to a read-only agent, etc.), document the rationale in the agent's `## Why this role exists` section.

**When reviewing a PR that adds a new tool to an existing agent:**

- The reviewer should sanity-check: "is this tool consistent with the agent's domain?" A `Write` tool on a `*-reviewer` agent is a red flag.
- Cross-reference [the F1 Bash-gate pattern](./harness-decay-cadence.md#permission-re-audit) — adding `Bash` to a non-validator agent is a load-bearing decision.

## 4. Examples from this harness

| Agent | `tools:` | Why this set |
|-------|----------|--------------|
| `code-reviewer` | `Read, Grep, Glob, Bash` | Read-only inspection + Bash for `git diff` / `git log`. No `Write`/`Edit` — review is observational, not mutational. |
| `build-error-resolver` | `Read, Write, Edit, Bash, Grep, Glob` | Implementation role — reads existing code + writes minimal fixes + runs the build. |
| `security-reviewer` | `Read, Bash, Grep, Glob` | Read-only audit + Bash for `git log`/manifest probes. No `Write` — review is observational. |

## 5. Cross-references

- **[Permission re-audit cadence](./harness-decay-cadence.md#permission-re-audit)** — quarterly review of `tools:` grants.
- **The no-model-self-start rule** (`CLAUDE.md`'s Operating model, under §Architecture) — the autonomy invariant is enforced by **allowlist-based tool grants**, expressed via `disable-model-invocation: true` on 12 carriers currently — 2 skills (`recursive-improve`, `score-decision`) + 10 commands, not 12 skills. 3 of the 12 are CRIT-guarded: `recursive-improve` (`audit.sh #39`), `score-decision` (`audit.sh #49`), and `ship-merge` (`audit.sh #44`, a command, not a skill — added 2026-07-20). The other 9 rely on check 30's WARN-only reason-presence check, which doesn't catch the flag being dropped outright. The allowlist convention is the substrate for the invariant's enforcement. (See `CLAUDE.md`'s Operating model, under §Architecture, for the invariant's prose form, and its "Skill/agent/command mechanics & routing" section for the current carrier list.)
- **F1 Bash-gate pattern (retired)** — `hooks/gates/validator-bash-guard.sh` ran a deny-pattern check on the then-14 validator-class agents through v0.4.18; deleted in the v0.6.0 reset and not rebuilt (see §4 point 4 above). Today's 6 validator-class agents (`code-architect`, `code-reviewer`, `python-reviewer`, `security-reviewer`, `silent-failure-hunter`, `typescript-reviewer`) have no runtime enforcement beyond the allowlist's `Bash` grant and prompt doctrine.
- **BOUNDARY.md** — the regenerator outputs a `Mutates` column that reflects `Edit`/`Write`/`Bash` grants (allows readers to see at-a-glance which agents can mutate state).
- **Skill template (`docs/skill-template/SKILL.md`)** — the skill template does not use `tools:` (skills are loaded into the parent agent, not invoked as separate contexts), but the allowlist convention still applies to the parent agent that loads the skill.
