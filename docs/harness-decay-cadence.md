# Harness Decay Cadence (build-to-delete)

A human-run review cadence that keeps this harness minimal as the models it
compensates for improve. Most components — a skill, an agent, a hook, an
always-on `additionalContext` block — exist to work around a *model limitation*
of the day. When the model gets better, some of those workarounds become dead
weight that still costs tokens and attention. This cadence names the practice of
finding and retiring them.

It **documents an existing practice**; it adds **no new machinery** and **no
auto-prune**. Both the measure and the delete decision are human-gated.

## The lens: every component compensates for an assumed model limitation

For each component, the load-bearing question is: *what model limitation does
this compensate for?* Record that assumption. Examples:

- a `decide` clarify-mode gate compensates for "the model guesses instead of asking";
- a verbose doctrine block compensates for "the model forgets the convention";
- a maker≠checker reviewer agent does **not** compensate for a limitation — see
  the guard below;
- text that defines **product behavior** — a voice/register spec
  (`output-styles/staff-eng.md`), a templated PR/command body, a team content
  standard — also does not compensate for a limitation: it keeps output
  consistent for the people consuming it. Cherny drew this exact line when the
  Claude Code team cut >80% of its own system prompt for the Claude 5
  generation (YC Startup School 2026): the cut targets capability scaffolding;
  consistency-defining text serves a different function and is never
  decay-eligible on "the model got smarter" grounds. It can still die for other
  reasons (the product changed) — just not through this lens. Claim-by-claim
  mapping: [`docs/research/prompt-cut-80-cherny-2026-08-09.md`](research/prompt-cut-80-cherny-2026-08-09.md).

When a model upgrade lands, the assumption behind a workaround may no longer
hold. That is the trigger to re-measure.

## Cadence

1. **Surface candidates** — run the audits that already exist; add no new tool:
   - `harness-audit` (`bash "${KBG_PLUGIN_ROOT}/skills/harness-audit/scripts/audit.sh" ["${KBG_PLUGIN_ROOT}"]`) for fleet
     health and dead / unloadable components;
   - `inventory` (`skills/inventory`) + a `BOUNDARY.md` drift snapshot it can
     emit and you commit — to catch a component that silently appeared or vanished;
   - the periodic `.scratch/skills-decay-audit-<date>/` sweeps (decommission
     candidate lists);
   - `workspace-surface-audit` (the owner's global capability-audit skill) as the
     **inverse lens**: it answers "what can the workspace/platform do *now*," and
     when the platform gains a capability a component used to polyfill, that
     component becomes decay-eligible. (Owner-only — it lives in `~/.claude`, not
     bundled with the plugin, so skip this lens on an external install. Its own job
     is setup/capability auditing, not decay detection — use its output as context,
     not as a decay detector.)
   - Claude Code's own in-session `/doctor` (the CLI-side `claude doctor` is
     install-health only; its help text names in-session `/doctor` as the full
     checkup — verified 2026-08-09). Anthropic ships it explicitly to rightsize
     skills and CLAUDE.md files (Thariq, 2026-07), making it a
     candidate-surfacer for the always-on-text class. Same posture as every
     lens here: its findings are candidates the operator reviews, not
     auto-applied fixes.
2. **Disable-and-measure** — disable a candidate (hook profile off, or remove
   the always-on block) and run the work it was meant to catch. If quality holds
   without it, the limitation it compensated for is gone. "Quality holds" is a
   **score, not a recollection** (`CLAUDE.md`'s "Score, not feel"): prefer an
   existing deterministic check as the measure — the behavioral test suite, a
   harness-audit check, a skill's own `evals/` set — over an impression that
   nothing broke. The Claude Code team's own >80% cut was validated as "no
   measurable loss on our coding evaluations," not by feel. Lifespan asymmetry
   (Cherny): behavior rules decay with the model generation that necessitated
   them, but eval/measure sets are the one component class that *accumulates*
   across generations — a set retires on **saturation** (the model aces every
   case, roughly 1–3 generations), not on the upgrade cadence that retires
   rules, and its replacement starts from what the current model still gets
   wrong.
3. **Delete with a witness** — if the measure says it is dead weight, remove it
   through `decommission`: sign an `ABSENT_*` witness so the orphan (stray
   symlink, cron, launchd job) is caught later, not silently resurrected.
4. **Keep the assumption recorded** — if you keep it, note *why the limitation
   still holds*, so the next upgrade has a baseline to measure against.

On a major model upgrade there is an aggressive variant of step 2 — Cherny's
full-class ablation: strip a whole candidate class at once (he recommends users
strip their CLAUDE.md/skills/hooks roughly every 6 months), run real work
without guessing in advance what needs guidance, and re-add only what the model
repeatedly fumbles. Same measure-then-keep loop, run from zero instead of from
the accumulated state — and the same human gate on every re-add decision.

This pairs with `recursive-improve` (the add/fix loop): recursive-improve closes
the loop on what to **build**; this cadence closes it on what to **delete**.

## Hard guard (load-bearing): never auto-delete maker≠checker

Decay reasoning must **never** retire a verifier on the argument that "the model
can verify its own work now." The maker≠checker separation exists for
**vouchability and independence** — a fresh-context checker catches what the
maker cannot see — not because the model is too weak to check. That is exactly
the boundary the no-model-self-start rule (`CLAUDE.md`'s Operating model, under
§Architecture) protects. Collapsing the checker into the maker is the
rejected autonomous self-rewriter, not a decay win.

Both the **measure** and the **delete** decision stay human-gated. There is no
auto-prune: a decay finding is a candidate the human reviews, exactly like a
`recursive-improve` candidate. Automate past the point where you can still vouch
for the output and you ship agent slop.

**See `CLAUDE.md`'s Operating model** (under §Architecture) — the L2–L5
bounded-autonomy ratchet was retired in the v0.6.0 "reset: rebuild from
scratch" cut, but the no-model-self-start rule survives as the judgment-preservation
principle (operator judgment is load-bearing; never auto-prune a verifier). The
"never auto-prune" guard is that principle's concrete expression in decay reasoning
and holds unchanged: the harness denies the irrecoverable set computationally and
advises on the rest, but a decay finding is always a candidate the operator reviews
— no autonomy flag, no auto-prune. The iteration soft cap in `recursive-improve/SKILL.md`
is a context-exhaustion backstop (not the primary gate).

## LLM-judge circularity (decay-perspective mirror)

`CLAUDE.md`'s "Why — the unifying crux" (under §Architecture) has a
load-bearing consequence for decay reasoning: **an inferential sensor shares
a model class with the generator**, so it cannot be trusted to emit
`permissionDecision`s — an LLM judging its own output is circular ("two
optimists agreeing").

Böckeler (Thoughtworks, [harness-engineering
2026-04](https://martinfowler.com/articles/harness-engineering.html))
frames a coding-agent harness as a 2×2 of **direction** (feedforward /
feedback) × **execution type** (computational / inferential). The
article's warning is symmetric: feedback-only = "agent that keeps
repeating the same mistakes"; feedforward-only = "agent that encodes
rules but never finds out whether they worked." The **inferential-FB cell**
carries a specific decay hazard: a "smart" sensor that uses the same model
class to judge work the model just produced inherits the generator's blind
spots and can quietly self-confirm. A `permissionDecision: deny` from such a
sensor is also a model-as-own-gate — the covert self-authorization pattern
`CLAUDE.md`'s Operating model retires.

**kbg's current posture, captured at the decay layer:**

1. The only two hook categories that exist today are `hooks/gates/`
   (computational, deny/ask, enforcing) and `hooks/advisory/` (journal only,
   never a `permissionDecision`) — see `hooks/hooks.json` for the live
   inventory. A prior, larger inferential-FB sensor set (`verification-gate.sh`,
   `fabrication-verdict-log.sh`, and the coverage tooling below) was removed
   in the v0.6.0 "reset: rebuild from scratch" cut and has not been rebuilt;
   today's advisory layer is thinner than this section originally described.
2. The harness-audit checks are the **computational** FB that does the
   enforcement — the cell that *can* be trusted to emit `permissionDecision`s
   because it is deterministic, fast, and cheap.
3. When a model upgrade lands, the **first** lens to apply is on any
   inferential-FB component that exists at the time: is the upgrade a
   stronger *generator* or a stronger *judge*? If only the former, the
   inferential-FB layer should get *thinner*, not thicker — the right decay
   move is to retire the sensor, not to lean on it.

This is the decay-perspective mirror of `CLAUDE.md`'s operating-model
discussion. The full comparison lives in
[`docs/research/harness-engineering-2026-04.md`](research/harness-engineering-2026-04.md).

## Irreversible-action class (gates the harness already has)

The corpus converges on a class-name: **irreversible actions** (destructive
commands, hardcoded-path leaks, edits to the code that judges the model)
deserve a human gate. kbg-harness currently has 7 gate scripts under
`hooks/gates/` (10 PreToolUse hook entries — three gates register on two
matchers each):

- **Irrecoverable Bash patterns** — `hooks/gates/irrecoverable.sh` (PreToolUse
  on Bash; `exit 2`-blocks the destructive-command class + the develop-only
  branching doctrine, `deny` not `ask` — see `docs/reference/hook-lifecycle-
  contracts.md`'s hook-by-hook table for the exact pattern list, don't
  restate it here).
- **Verifier tamper-protection + hardcoded paths** —
  `hooks/gates/verifier-protect.sh` (PreToolUse on Write|Edit|NotebookEdit
  AND on Bash — the latter catches Bash-mediated writes like `tee`/`sed -i`/
  `cp`/`mv` to verifier surfaces). Emits `permissionDecision: ask` for edits
  to `hooks/gates/**`, `hooks/advisory/**`, `hooks/hooks.json`, and
  `skills/harness-audit/scripts/{audit.sh,checks/**}` — the class is "the
  model editing the code that judges it." **Also folds the former standalone
  `path-hardcode.sh`** (deleted 2026-07-03): an `exit 2` deny leg blocks a
  literal `/Users/<name>` written into a `.sh`/`.py` file before the ask —
  `$HOME`/`~` pass through.
- **DB-write** — `hooks/gates/db-write-gate.sh` (PreToolUse on
  `mcp__.*__execute_sql.*`; emits `permissionDecision: ask` on any
  non-proven-read SQL statement — a read-allowlist, not a write-blocklist, so
  an unrecognized statement asks rather than slips. Restored after the v0.6.0
  reset deleted the prior version).
- **Task self-completion** — `hooks/gates/task-complete-separation.sh`
  (PreToolUse on TaskUpdate; `exit 2`-denies `TaskUpdate(status=completed)`
  when `agent_type` is present — maker≠checker: a subagent cannot mark its own
  task completed; only the main session completes).
- **Atlassian MCP cold-start** — `hooks/gates/atlassian-mcp-gate.sh`
  (PreToolUse on Skill AND `mcp__.*`; the Skill matcher marks the session
  jira-acli-engaged when a `jira-acli:*` skill loads, and the `mcp__.*` matcher
  blocks a direct Atlassian/Jira/Confluence MCP call before that mark exists —
  forcing routing through jira-acli's templates. Cold-start guard, not a
  per-call router: later calls allow once engaged).
- **Guarded-worktree writes** — `hooks/gates/worktree-guard.py` (PreToolUse on
  Write|Edit|NotebookEdit AND on Bash; opt-in via `KBG_GUARDED_WORKSPACE`:
  redirects Write/Edit on a guarded sub-repo main checkout into a session
  worktree, denies the Bash-mediated equivalent. Off by default everywhere —
  no workspace path ships in this public plugin. Bash early-exit skips the
  python3 cold-start when the var is unset).

There is no dedicated secret-read or config-edit gate today — those remain
candidate classes for a future gate. (A DB-write gate now exists, above.)

**Pattern for future gates**: any new gate should be keyed on the **class**
of mutation, not on a specific tool. `irrecoverable.sh` matches a family of
destructive Bash patterns rather than one exact command string — the analog
for a future `deploy-gate` would match `Bash` invocations of `kubectl
apply`, `terraform apply`, etc. (class: infrastructure mutation), following
the same one-script-per-class shape.

The pattern lives in the existing decay cadence because the gates
themselves live in `hooks/`; this section is the map of which class each
existing gate covers, so a future contributor can find the right
precedent before adding a new one.

`deny` (exit 2) is what `irrecoverable.sh`, `task-complete-separation.sh`,
`worktree-guard.py` (its Bash deny leg),
and `verifier-protect.sh`'s path-hardcode leg use — reserved for
actions the model should never be trusted to do even with human in-the-loop
confirmation. `ask` (`permissionDecision: ask`) is what `verifier-protect.sh`
(verifier edits), `db-write-gate.sh`, and `atlassian-mcp-gate.sh` use — a live
approve/deny prompt for edits/calls that are sometimes legitimate but always
deserve a human look. Read the scripts themselves under `hooks/gates/` for the
exact pattern list.

### Refused extension: mandatory verification of every reasoning event

2026-07-01: a "verifier-first runtime" ask wanted the deny-gate model above
generalized from *irreversible actions* to *every reasoning event* —
auto-classify decision criticality, auto-select a verification policy,
confidence-based gating, retry/re-plan/escalate on failure. Refused as
specified:

- classifying criticality or "verifying reasoning" at runtime needs either
  an LLM doing the classifying (unverified reasoning gating reasoning —
  the model grading itself, see `CLAUDE.md`'s "unifying crux") or
  deterministic semantic understanding of free-form text (not buildable).
- confidence-based gating uses model self-report as the gate signal — same
  crux, "two optimists agreeing."
- mandatory-verify-everything plus auto retry/re-plan/escalate is the
  L2–L5 autonomy ladder under a new name — retired by ADR 0006, do not
  re-arm.

The gates above already are "verification an agent can't skip" for the one
class that's actually verifiable by a deterministic script: irreversible
actions. Extend by the existing pattern above (new gate = new
*irreversible-action class*, found from a real gap) — not by building a
runtime classifier for reasoning in general.

## Gate discipline review (judgment vs ceremony)

*Pairs with the quarterly sweep above; see `CLAUDE.md`'s Operating model (under
§Architecture) for the rationale on gate discipline.*

The gates mapped above (irrecoverable Bash patterns, hardcoded paths,
verifier tamper-protection — plus the `recursive-improve` Step 3 gate) earn
their place only by carrying judgment. A gate the operator approves every time without a recorded change of
decision is **ceremony**, not judgment — and ceremony trains the atrophy the
no-model-self-start rule's judgment-preservation principle exists to prevent.
This review is the exit condition for the gate *implementation* (the principle
itself stays irreversible).

One question, folded into the quarterly pass: **which gates did the operator
rubber-stamp this quarter?** There is no dedicated approval log today — the
`governance-events.jsonl` + verification-gate journal this section originally
pointed to were removed in the v0.6.0 reset and not rebuilt. Until a log
exists, this is a recall-based review, not a reading task; a durable
`ask`-decision log is itself a candidate the next build-to-delete pass should
weigh. For each gate:

- **fired and changed an outcome at least once** → judgment gate, keep.
- **fired but always approved unchanged** → ceremony *candidate* (not an
  auto-delete). Ask "would I ever deny here?". If no: the gate is mis-scoped (too
  broad, catching non-judgment mutations) or the limitation it guarded is gone —
  narrow it, or `decommission` with an `ABSENT_*` witness, same flow as a stale
  component.
- **never fired** → already covered by the harness-coverage silent-cell review
  below.

Removing a ceremony gate is **not** a move toward any autonomy level; it is the
build-to-delete sweep applied to gates — keep every remaining gate one the
operator actually deliberates at. Measure and delete stay human-gated, no
auto-prune. **Carve-out:** the maker≠checker hard guard above still binds — never
retire a *verifier* on a rubber-stamp argument. A verifier's value is
independence, not the operator's deliberation at a gate, so it is never a ceremony
candidate.

## Permission re-audit

*last_reviewed: 2026-06-11 (initial section, written as part of the
2026-06-11 Harness-Loop-Engineer audit response; revisit quarterly
or on model upgrade).*

last_permission_review: 2026-06-12 — re-audited against the close of the 2026-06-12 audit epic (F1-F12, D1-D10 all shipped; 5 commits `2d3c743`, `a20200b`, `4d2ad91`, `f0d59a7`, `7194037`). No `tools:` lines added or modified during the epic; F1 added a hook, not frontmatter; F3/D1 added 2 commands; F5 added voice blocks (frontmatter `description` only).

The decay lens above asks "does this component still earn its place?". A
sibling question: **has this component accrued tool access it no longer needs?**
That second question is the permission re-audit, and it lives here because the
same human-gated cadence applies. Two surfaces carry tool grants:

- **Per-agent `tools:` frontmatter** under `agents/*.md` (each token is an
  explicit allowlist the agent's prompt then inherits as a real tool);
- **The harness settings allowlist** at `dotfiles/claude/settings.json` in the
  sibling `dotfiles` repo, not this one (a second, broader allowlist applied
  to every session in this harness).

**Convention:** when adding a new agent, follow [`docs/agent-tool-patterns.md`](./agent-tool-patterns.md) — prefer allowlist (`tools:`) over denylist (`disallowedTools:`) unless documenting the exception. The allowlist convention is the substrate for keeping tool-grant expansion operator-visible (the no-model-self-start rule's judgment-preservation principle, `CLAUDE.md`'s Operating model under §Architecture).

A tool grant is a *permission expansion surface* — it widens what the model
can do without a human gate. When the model improves or a feature gets
removed, a previously-needed grant becomes decay-eligible in exactly the same
sense a hook does. The fix is the same: human-gated measure-then-delete
through the `decommission` flow with an `ABSENT_*` witness.

### Cadence

- **Quarterly** — pair with the build-to-delete sweep above so a single
  human pass clears both "stale" and "over-permissioned" candidates in one
  sitting.
- **On model upgrade** — Claude 4.x → 5.x, Sonnet → Opus, etc. New tiers
  shift the implicit trust surface; re-walk every grant against the new
  capability profile.
- **On agent merge** — the new agent's `tools:` line is reviewed at merge
  time, but the *cumulative* surface (this agent + everything else) deserves
  a fresh look at the same milestone.

### Surface check (copy-pasteable)

From the repo root, this one-liner lists every tool-grant delta since the
last permission review:

```bash
git diff <last-review-sha>..HEAD -- agents/ dotfiles/claude/settings.json \
  | grep -E '^\+.*tools:|^\+.*"allow"'
```

Walk the output line-by-line: for each added token, ask (a) is the agent /
session actually using it, and (b) does the human-gate posture survive if
the model uses it without checking? If both yes, keep. If either no, revoke
the grant and note why in the commit message — no dedicated ticket machinery
exists for this today.

### Why this is here, not in `harness-audit`

`harness-audit` is a deterministic, machine-checkable surface — the
*enforcement* layer. The permission re-audit is a *judgment* call: "is this
grant still earned?" is a question only a human can answer well, and the
answer depends on model-version state and recent work patterns that
don't reduce to a regex. The audit's role is to keep the *envelope*
honest (no duplicate `tools:` tokens — check #10; every agent has explicit
`tools:` — check #9; every token a real Claude Code tool — check #24); the
re-audit's role is to keep the *contents* honest on the human cadence
above. They are complements, not substitutes.

## Trigger-health re-audit (suppressed-demand lens)

Same quarterly cadence as the sections above. Two tiers, deliberately unequal
cost — do not conflate them.

- **Tier A — trigger health (cheap, tool-run; the default action).**
  Re-run `python3 scripts/measure-autotrigger.py`. Look for the
  *suppressed-demand* pattern on `decide`, `grilling`, `orchestrate`:
  **0-or-low `auto_fire` + nonzero `manual`/`slash_exec`** — the fingerprint
  of a skill the model wants but whose description no longer matches (the
  exact v0.43.5 failure: commit `fdee904` silently stripped `decide`'s
  quoted trigger phrases during a de-scope edit). If the pattern appears,
  read the skill's `description` for lost trigger phrases and restore them
  (fix pattern: commits `9058eec`, `639dd0a`). The tool has no false-positive
  detection, no semantic near-miss detection, no before/after delta, and no
  persisted history across runs — treat its output as a single-run pattern
  check, not a threshold to automate against.
- **Tier B — routing quality (expensive, manual; conditional, not
  scheduled).** The tool counts *how often* a skill fires; it cannot judge
  whether `decide` picked the *right mode*. Only pursue this if Tier A looks
  healthy and misrouting is still suspected: hand-sample real `decide`
  transcripts from `~/.claude/projects/*.jsonl` and re-score via
  `kbg:score-decision`. No tool automates this step. Per the 2026-07-10
  Decision Score (19/100, FAIL), a mode-routing logic change is premature
  until several more real `decide` transcripts accumulate (n=1 at that
  writing) — don't reopen that question on a hunch; reopen it on volume.

**Current status (2026-07-10):**

- `decide` — trigger phrases restored in v0.43.5; watch next quarterly pass.
- `grilling`, `orchestrate`, `score-decision` — measured healthy or
  intentionally silent at last check; no edit made, by design. This
  Tier-A check is *when* to re-examine them, not a signal to touch them now.

## Harness-coverage quarterly review (retired)

*Retired 2026-07-01.* This section originally described a
`scripts/evals/harness-coverage.py` tool that emitted a 2×2 matrix of hook
events × {computational, inferential} × {feedforward, feedback}, with a
sub-60%-of-expected-fire-count decay threshold. That tool and its design doc
were removed in the v0.6.0 "reset: rebuild from scratch" cut and have not
been rebuilt — there is currently no automated silent-cell detection.

The underlying question is still worth asking by hand on the same quarterly
cadence as the sections above: **is each hook category still doing real
work, or has a hook gone silent** (routed around by a newer surface,
firing on a condition that no longer occurs, or simply forgotten)? Until the
coverage tool is rebuilt, answer it by reading `hooks/hooks.json` end to end
against recent session behavior — there is no cell-level automation to lean
on. Any rebuild of this tool stays operator-run and report-only, same as
every other cadence in this file: no cron, no scheduled hook event, no
model-as-own-gate — a coverage-driven auto-prune would be the same
LLM-judge-circularity hazard this whole file guards against, one layer up.
