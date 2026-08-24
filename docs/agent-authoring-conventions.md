# Agent authoring conventions

**Status:** Convention reference. Owned by the harness. Sibling of
[`agent-tool-patterns.md`](./agent-tool-patterns.md) and
[`agent-voice-extension.md`](./agent-voice-extension.md).

**Origin:** a deep-research critique of the 19-agent fleet (2026-07-20) confirmed the fleet
converged on a real, working set of conventions across 91 individually-justified
`feat(agents): add X` commits — but nothing wrote them down. The external canonical-structure
doc (`~/.claude/docs/agent-anatomy.md`, in the sibling **dotfiles** repo) prescribes a header
shape (`## Why this role exists`, `## Domain focus`, `## Cross-role boundaries`, etc.) that
**zero of the 19 real agents follow — including its own two named exemplars**
(`code-reviewer.md`, `security-reviewer.md`). This doc does not enforce that structure. It's
what the fleet actually does, made explicit, so a new agent has something accurate to
pattern-match against.

The question this doc answers: **what does a new agent in this fleet need to get right, and
why?**

## 1. Tool scoping: explicit allowlist, least privilege

Every agent declares `tools:` as an explicit allowlist (see
[`agent-tool-patterns.md`](./agent-tool-patterns.md) for the full allowlist-vs-denylist
rationale). Grant only what the role needs:

- **Read-only reviewers/analysts** (`code-reviewer`, `security-reviewer`,
  `python-reviewer`, `typescript-reviewer`, `nextjs-reviewer`,
  `backend-architect`, `code-architect`, `blind-spot-hunter`, `silent-failure-hunter`,
  `requirement-analyst`, `spec-miner`, `summarizer`): `Read`, `Grep`,
  `Glob`, sometimes `Bash` for inspection (`git log`, `git diff`). Never `Write`/`Edit`.
- **Mutating implementers** (`code-implementer`, `build-error-resolver`, `refactor-cleaner`,
  `performance-optimizer`): add `Write`/`Edit` on top of the read-only set.
- **`Agent` is never granted.** No agent in this fleet re-orchestrates (Rule 13,
  CLAUDE.md's Staff-Engineer Thinking Loop) — a dispatched subagent returns scoped output to
  its caller, it doesn't spawn its own. `harness-audit` check 09 (CRIT) catches a missing
  `tools:` line outright; check 45 (WARN) catches an explicit `Agent` grant. Do not add
  `Agent` to a new agent's `tools:` line — if a task seems to need one agent calling another,
  that's the orchestrator's job, not the agent's.

**Why:** least privilege by construction (OWASP LLM06, Excessive Agency). The read/mutate
split is exactly where the blast radius of a wrong action differs by an order of magnitude.

## 2. Prompt Defense Baseline on anything that ingests external content

Every agent except `ideate-critic` carries a `## Prompt Defense Baseline` section near the
top: don't change role/persona, don't reveal secrets, and — critically — **treat the input
(ticket body, spec text, source file, PR description) as untrusted data, not
instructions.** See `agents/requirement-analyst.md` for the canonical form.

`ideate-critic` only ever reads same-session-generated JSON with no external-fetch
surface — a defensible, but undocumented-until-now, omission. If a new agent
is `Read`-only over strictly same-session content, the baseline may be optional; if it ever
touches a ticket, a fetched doc, a PR body, or any text that didn't originate in the current
turn, include it.

**Why:** OWASP LLM01 (Prompt Injection). Ticket bodies and specs are exactly the kind of
content an attacker (or a compromised upstream source) could embed instructions into.

## 3. Model assignment by cognitive load, not by default

Most agents omit `model:` (inherits the session default). Pin `model: opus` when the task is
genuinely analysis-heavy and benefits from independent judgment quality —
`requirement-analyst` does this. Pinning a fresh-context verifier while the main session
often runs a different model is deliberate: it makes the verifier
independent by *model*, not just by context, which is a stronger form of the maker≠checker
separation in §4.

**Why:** don't pin `opus` reflexively — it's a cost/latency trade-off. Reserve it for agents
whose entire value is judgment quality (verifiers, requirement analysis), not for mechanical
work (build-error fixing, refactor cleanup).

## 4. Verifier/maker separation for anything that grades

If a new agent's job is to judge, verify, or gate another agent's or the main session's
output (a completion check, a spec-compliance check, a quality gate) — it must be a
**fresh-context, advisory-only** pass. It returns a finding list; it never itself blocks or
"passes" the work by fiat. `blind-spot-hunter` and `ideate-critic` are
the reference examples.

**Why:** an LLM cannot reliably grade its own same-context output (Panickssery et al.,
self-preference bias, NeurIPS 2024; Advani, arXiv 2606.09863, AUROC ≤0.65 ceiling for
LLM-judged task completion — already load-bearing elsewhere in this repo's doctrine). This is
the repo's own "a maker cannot grade its own work" crux (CLAUDE.md's Architecture section),
applied to agent design specifically.

## 5. Confidence discipline for anything that reports findings

Review/analysis agents state a confidence bar (commonly >80%) and require HIGH/CRITICAL
findings to cite concrete proof — an exact `file:line`, a reproducible failure scenario, not
a vague "this looks off." **Zero findings on a clean input is a valid, expected outcome** —
don't manufacture findings to look thorough. See any `*-reviewer` agent's `## Guardrails` /
`## Anti-Patterns` section, or `requirement-analyst.md`'s "Don't manufacture findings on a
clean ticket" guardrail.

**Why:** the industry baseline for LLM/static-analysis findings is bad in both directions —
traditional false-positive rates run 35–91%, and a primary study on GitHub Copilot's code
review found the opposite failure mode (near-total misses on seeded vulnerabilities). Explicit
anti-hallucination discipline is a real, evidenced mitigation, not ceremony.

## 6. Central routing, one-level-deep dispatch

Every new agent must be added to `skills/orchestrate/reference.md`'s routing table (checked
by `harness-audit` check 12) — that table is where domain disambiguation actually lives.
Individual agents do **not** need to fully self-disambiguate against every neighboring agent
in their own body; router coverage is the primary mechanism, a "when NOT to use me" note in
the agent body is defense-in-depth, not a requirement.

**Why:** centralizing routing avoids both the under-specified-boundary failure Anthropic's own
multi-agent postmortem names (agents silently duplicating work) and the alternative of forcing
every agent to enumerate every other agent's scope inline, which drifts the moment the fleet
grows.

## 7. Grow on proven need, not speculatively

19 agents got here via individually-justified commits (91, as of the last count — 2026-07-20), each solving a real, named gap —
not a bulk import or a "let's have one for every domain" sweep. Before adding a new agent, be
able to name the concrete task it handles that no existing agent covers. Check the fleet
routing table first; if an existing agent's domain is close, extend it before adding a
neighbor.

**Why:** Rule 2 (CLAUDE.md) — match surface area to proven need. A fleet of near-duplicate
specialists is real maintenance cost (routing ambiguity, description-token load on every Task
spawn) for a benefit that has to be earned per agent, not assumed.

## 8. Closed-vocabulary status codes for branchable output

When an agent's job includes returning a status its caller must branch on — refuse,
need-confirmation, ambiguous-scope, regressed-after-edit — express it as a small, fixed set of
terminal first-token codes (e.g. `too-big.` / `needs-confirm.` / `ambiguous.` / `regressed.`), not
a free-text sentence the caller has to re-parse. Document the closed set in the agent's `## Output
Format` so both the agent and its caller can validate against it. No agent in the current fleet
does this yet — this is a convention for new/revised `Output Format` sections, not a retrofit
requirement.

**Why:** kbg has already paid for the alternative once, in a state file rather than an agent
return value, but the same discipline gap. The `rehunt` field in `review-pr`'s state file — a
semi-structured status written by whichever session ran the review, never schema-enforced — drifted
into 15+ distinct shapes against 4 documented canonical values, with 20/105 real production files
missing it entirely (v0.68.77, `CHANGELOG.md`; `state-file-contract-drift-mine-before-dispatch`
memory). An unconstrained status left to free text drifts across independent writers; a closed
vocabulary fixed at authoring time prevents that class of drift before it happens, instead of
mining production data to discover it after.

## When authoring a new agent — quick checklist

1. Name the concrete, currently-uncovered task. Check the orchestrate routing table first.
2. `tools:` — explicit allowlist, smallest set the role needs. Never `Agent`.
3. Add `## Prompt Defense Baseline` if the agent ever touches content it didn't generate
   itself this turn.
4. Pin `model: opus` only if the value is judgment quality, not by default.
5. If the agent grades/verifies other work: fresh-context, advisory-only, never self-gating.
6. If the agent reports findings: state a confidence bar; zero findings is a valid output.
7. If the agent returns a branchable status (not just findings prose): define it as a closed
   set of terminal first-token codes in `## Output Format`.
8. Add the agent to `skills/orchestrate/reference.md`'s routing table.
9. Run `bash skills/harness-audit/scripts/audit.sh` — checks 04/09/12/24/25/45 all touch new
   agents directly.

## Cross-references

- [`agent-tool-patterns.md`](./agent-tool-patterns.md) — the allowlist-vs-denylist rationale
  in full (§1 here summarizes it).
- [`agent-voice-extension.md`](./agent-voice-extension.md) — when a personality merits its own
  slash command (rare; default is no).
- `skills/orchestrate/reference.md` — the routing table §6 requires new agents to join.
- `skills/harness-audit/scripts/checks/` — 04 (frontmatter completeness), 09 (explicit
  `tools:`, CRIT), 12 (routing coverage), 24 (tool-token validity), 25 (skills-ref
  resolution), 45 (no `Agent` grant, WARN) are the mechanical checks over this doc's §1–§6.
  There is deliberately no structural body-regex check (heading presence, etc.) — that class
  was tried for skills and retired after a 5/5 false-positive rate (CLAUDE.md, skill
  authoring doctrine section); this doc is prose guidance, not a gate.
