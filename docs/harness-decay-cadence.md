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

- a `clarify-first` gate compensates for "the model guesses instead of asking";
- a verbose doctrine block compensates for "the model forgets the convention";
- a maker≠checker reviewer agent does **not** compensate for a limitation — see
  the guard below.

When a model upgrade lands, the assumption behind a workaround may no longer
hold. That is the trigger to re-measure.

## Cadence

1. **Surface candidates** — run the audits that already exist; add no new tool:
   - `harness-audit` (`bash skills/harness-audit/scripts/audit.sh [<root>]`) for fleet
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
2. **Disable-and-measure** — disable a candidate (hook profile off, or remove
   the always-on block) and run the work it was meant to catch. If quality holds
   without it, the limitation it compensated for is gone.
3. **Delete with a witness** — if the measure says it is dead weight, remove it
   through `decommission`: sign an `ABSENT_*` witness so the orphan (stray
   symlink, cron, launchd job) is caught later, not silently resurrected.
4. **Keep the assumption recorded** — if you keep it, note *why the limitation
   still holds*, so the next upgrade has a baseline to measure against.

This pairs with `recursive-improve` (the add/fix loop): recursive-improve closes
the loop on what to **build**; this cadence closes it on what to **delete**.

## Hard guard (load-bearing): never auto-delete maker≠checker

Decay reasoning must **never** retire a verifier on the argument that "the model
can verify its own work now." The maker≠checker separation exists for
**vouchability and independence** — a fresh-context checker catches what the
maker cannot see — not because the model is too weak to check. That is exactly
the boundary METHODOLOGY Rule 4's fresh-context-verification principle and the
autonomy invariant (`CONTEXT.md` §Invariants) protect. Collapsing the checker into the maker is the
rejected autonomous self-rewriter, not a decay win.

Both the **measure** and the **delete** decision stay human-gated. There is no
auto-prune: a decay finding is a candidate the human reviews, exactly like a
`recursive-improve` candidate. Automate past the point where you can still vouch
for the output and you ship agent slop.

**See [ADR 0002](0002-autonomy-invariant.md) for the rationale** — the autonomy invariant is irreversible, the "never auto-prune" guard is its concrete expression in decay reasoning, and the 5-iteration soft cap in `recursive-improve/SKILL.md:127` is a context-exhaustion backstop (not the primary gate).

## LLM-judge circularity (decay-perspective mirror)

The `2×2 harness mental model` documented in `CLAUDE.md` (after the
Hook architecture section) has a load-bearing consequence for
decay reasoning: **inferential-FB sensors share a model class with the
generator**, so they cannot be trusted to emit `permissionDecision`s.

Böckeler (Thoughtworks, [harness-engineering
2026-04](https://martinfowler.com/articles/harness-engineering.html))
frames a coding-agent harness as a 2×2 of **direction** (feedforward /
feedback) × **execution type** (computational / inferential). The
article's L345 warning is symmetric: feedback-only = "agent that keeps
repeating the same mistakes"; feedforward-only = "agent that encodes
rules but never finds out whether they worked." kbg populates all
four cells — but the **inferential-FB cell** carries a specific decay
hazard: a "smart" sensor that uses the same model class to judge work
the model just produced inherits the generator's blind spots and can
quietly self-confirm. A `permissionDecision: deny` from such a sensor
is also a model-as-own-gate — covert L4, autonomy-invariant
forbidden.

**kbg's posture, captured at the decay layer:**

1. All inferential-FB sensors in `hooks/` are **advisory only** — they
   journal, they do not block. `verification-gate.sh` (SessionEnd) and
   `fabrication-verdict-log.sh` (Stop) are the load-bearing examples;
   the full inventory is in the CLAUDE.md 2×2 section.
2. The 204 critical-hooks tests + 38 audit checks are the
   **computational** FB that does the enforcement — the cell that
   *can* be trusted to emit `permissionDecision`s because it is
   deterministic, fast, and cheap.
3. When a model upgrade lands, the **first** lens to apply is on
   inferential-FB components: is the upgrade a stronger *generator* or
   a stronger *judge*? If only the former, the inferential-FB
   layer gets *thinner*, not thicker — the right decay move is to
   retire the sensor, not to lean on it. If both, the sensor is
   decay-eligible on the same "coherence tax" axis as any other
   non-load-bearing control.

This is the decay-perspective mirror of the CLAUDE.md 2×2 section.
The 1-pager at `.scratch/research/harness-engineering-2026-04.md`
holds the full comparison (3-now / 3-later actions).

## Irreversible-action class (gates the harness already has)

The corpus converges on a class-name: **irreversible actions** (writes to
external state, reads of secrets, edits of config or doctrine) deserve a
human gate. kbg-harness already has 4 class-shaped gates:

- **DB writes** — `hooks/db-write-gate.sh` (gates `mcp__*__execute_sql_*`
  non-SELECT writes; SELECT/EXPLAIN/information_schema pass through)
- **Secret reads** — `hooks/secret-read-guard` (in `hooks/hooks.json`)
- **Config edits** — `hooks/config-protection.sh` (PreToolUse gate,
  `hook_decision ask` on existing linter/formatter configs; blocks
  the model from editing established config without human approval).
  `hooks/config-change-log.sh` is a separate append-only audit trail
  for external `ConfigChange` events (logger, not a gate — fires
  after the fact, no `permissionDecision`, no enforcement).
- **Doctrine edits** — `hooks/doctrine-edit-gate` +
  `hooks/block-bash-doctrine-write` (gates Edit/Write on METHODOLOGY/CONTEXT/
  RTK/ACLI/DBGATE)

**Pattern for future gates**: any new gate should be keyed on the
**class** of mutation, not on a specific tool. `db-write-gate` matches
`mcp__*__execute_sql_*` across servers (class: database mutation) — the
analog for a future `deploy-gate` would match `Bash` invocations of
`kubectl apply`, `terraform apply`, etc. (class: infrastructure mutation).

The pattern lives in the existing decay cadence because the gates
themselves live in `hooks/`; this section is the map of which class each
existing gate covers, so a future contributor can find the right
precedent before adding a new one.

`ask` is the default for human-supervised irreversible mutations; `deny`
is reserved for actions the model should never be trusted to do even
with human in-the-loop confirmation (e.g. secret-reads,
doctrine-via-Bash). See `secret-read-guard.sh:36-41` and
`block-bash-doctrine-write.sh:3-4` for the rationale pattern.

## Permission re-audit

*last_reviewed: 2026-06-11 (initial section, written as part of the
2026-06-11 Harness-Loop-Engineer audit response; revisit quarterly
or on model upgrade).*

last_permission_review: 2026-06-12 — re-audited against the close of the 2026-06-12 audit epic (F1-F12, D1-D10 all shipped; 5 commits `2d3c743`, `a20200b`, `4d2ad91`, `f0d59a7`, `7194037`). No `tools:` lines added or modified during the epic; F1 added a hook, not frontmatter; F3/D1 added 2 commands; F5 added voice blocks (frontmatter `description` only). The `usage-monitor` skill + capture hook shipped in D9 (Phase 4b) inherit the read-only `KBG_USAGE_MONITOR=1` opt-in posture; no new tool grants.

The decay lens above asks "does this component still earn its place?". A
sibling question: **has this component accrued tool access it no longer needs?**
That second question is the permission re-audit, and it lives here because the
same human-gated cadence applies. Two surfaces carry tool grants:

- **Per-agent `tools:` frontmatter** under `agents/*.md` (each token is an
  explicit allowlist the agent's prompt then inherits as a real tool);
- **The harness settings allowlist** at `dotfiles/claude/settings.json` (a
  second, broader allowlist applied to every session in this harness).

**Convention:** when adding a new agent, follow [`docs/agent-tool-patterns.md`](./agent-tool-patterns.md) — prefer allowlist (`tools:`) over denylist (`disallowedTools:`) unless documenting the exception. The allowlist convention is the substrate for the autonomy invariant's enforcement (ADR 0002).

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
the model uses it without checking? If both yes, keep. If either no, file
a `decommission` ticket and revoke via the same `ABSENT_*` witness
machinery.

### Why this is here, not in `harness-audit`

`harness-audit` is a deterministic, machine-checkable surface — the
*enforcement* layer. The permission re-audit is a *judgment* call: "is this
grant still earned?" is a question only a human can answer well, and the
answer depends on model-version state and recent work patterns that
don't reduce to a regex. The audit's role is to keep the *envelope*
honest (no duplicate `tools:` tokens, every token a real Claude Code
tool — see `harness-audit/scripts/audit.sh` checks #6 / #22); the
re-audit's role is to keep the *contents* honest on the human cadence
above. They are complements, not substitutes.
