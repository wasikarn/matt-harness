# Agent tool patterns: allowlist vs denylist

**Status:** Convention reference. Owned by the harness. Subject to the [Permission re-audit cadence](./harness-decay-cadence.md#permission-re-audit) (quarterly).

The Claude Code vendor schema offers two patterns for restricting an agent's tool access:

- **`tools:` (allowlist)** — list the tools the agent **may** use. Anything not listed is implicitly blocked.
- **`disallowedTools:` (denylist)** — list the tools the agent **may not** use. Everything else is implicitly available.

The kbg-harness convention is to prefer **`tools:` (allowlist)** for new agents. This document explains why, when to consider the denylist alternative, and what each pattern looks like in practice.

---

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

**Why we prefer it (27/28 agents in this harness use it):**

1. **Readable at a glance.** A reader of the agent's frontmatter sees the full capability set in one line. The constraint is the list, not the diff from a default.
2. **No implicit inheritance.** If the vendor's default toolset changes, the agent's tools don't change with it. The contract is stable.
3. **Safer default.** Adding a new tool to the vendor's default set is a **silent capability expansion** for denylisted agents but a **no-op** for allowlisted agents. We err on the side of explicit over implicit.
4. **Pairs with the F1 Bash-gate.** Validators (e.g. `code-reviewer`, `security-reviewer`) use `tools: [Bash]` for read-only inspection but rely on `hooks/validator-bash-guard.sh` to block mutation. The allowlist surfaces "this agent has Bash" in the frontmatter; the Bash-gate is the read-only-by-behavior layer.

**Tradeoffs (when allowlist is the wrong choice):**

- The agent inherits a large default toolset and only needs to block 1-2 specific tools. In that case, the denylist is shorter to write.
- The agent's toolset is expected to grow as the vendor adds new tools, and the team is OK with implicit expansion. (We do not recommend this — the loss of explicit-over-implicit usually costs more than the line saved.)

---

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
- The vendor schema explicitly supports it (it does — see `code.claude.com/docs/en/agents`), and the team is OK with the implicit-inheritance tradeoff.

**Why kbg-harness does not currently use it:**

- Our agents are specialists, not generalists. The allowlist is shorter to write, not longer.
- The "implicit inheritance" property is an antipattern for us: when the vendor adds a new tool (e.g. a new MCP bridge), we want a human to decide whether each existing agent should pick it up. Allowlist makes that decision visible in the PR; denylist hides it.

---

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

---

## 4. Examples from this harness

| Agent | `tools:` | Why this set |
|-------|----------|--------------|
| `code-reviewer` | `Read, Grep, Glob, Bash` | Read-only inspection + Bash for `git diff` / `git log`. No `Write`/`Edit` — review is observational, not mutational. |
| `backend-engineer` | `Read, Grep, Glob, Edit, Write, Bash` | Implementation role — needs to read existing code + write new code + run commands. |
| `security-reviewer` | `Read, Grep, Glob, Bash, WebFetch, WebSearch` | Read-only audit + Bash for `git log`/manifest probes + Web for CVE lookups. No `Write` — review is observational. |
| `incident-commander` | `Read, Grep, Glob, Bash, WebFetch` | Read-only situational awareness + Bash for triage commands (e.g. `kubectl get`, `aws s3 ls`). Mutations go through `devops-engineer` or `platform-engineer` per role boundaries. |

---

## 5. Cross-references

- **[Permission re-audit cadence](./harness-decay-cadence.md#permission-re-audit)** — quarterly review of `tools:` grants.
- **[ADR 0002 — Autonomy invariant](./adr/0002-autonomy-invariant.md)** — the autonomy invariant is enforced by **allowlist-based tool grants** (Pillar 1: deterministic via `audit.sh #32` on `recursive-improve`'s `disable-model-invocation: true`). The allowlist convention is the substrate for the invariant's enforcement.
- **[F1 Bash-gate pattern](./harness-decay-cadence.md#permission-re-audit)** — the `hooks/validator-bash-guard.sh` hook applies to the 7 validator-class agents and is the runtime enforcement of "validators are read-only" beyond the allowlist's `Bash` grant.
- **BOUNDARY.md** — the regenerator outputs a `Mutates` column that reflects `Edit`/`Write`/`Bash` grants (allows readers to see at-a-glance which agents can mutate state).
- **Skill template (`docs/skill-template/SKILL.md`)** — the skill template does not use `tools:` (skills are loaded into the parent agent, not invoked as separate contexts), but the allowlist convention still applies to the parent agent that loads the skill.
