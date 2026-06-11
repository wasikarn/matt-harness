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

## Irreversible-action class (gates the harness already has)

The corpus converges on a class-name: **irreversible actions** (writes to
external state, reads of secrets, edits of config or doctrine) deserve a
human gate. kbg-harness already has 4 class-shaped gates:

- **DB writes** — `hooks/db-write-gate.sh` (gates `mcp__*__execute_sql_*`
  non-SELECT writes; SELECT/EXPLAIN/information_schema pass through)
- **Secret reads** — `hooks/secret-read-guard` (in `hooks/hooks.json`)
- **Config edits** — `hooks/config-change-log` + `hooks/config-protection`
  (gates Edit/Write on config files)
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

## Permission re-audit

*last_reviewed: 2026-06-11 (initial section, written as part of the
2026-06-11 Harness-Loop-Engineer audit response; revisit quarterly
or on model upgrade).*

The decay lens above asks "does this component still earn its place?". A
sibling question: **has this component accrued tool access it no longer needs?**
That second question is the permission re-audit, and it lives here because the
same human-gated cadence applies. Two surfaces carry tool grants:

- **Per-agent `tools:` frontmatter** under `agents/*.md` (each token is an
  explicit allowlist the agent's prompt then inherits as a real tool);
- **The harness settings allowlist** at `dotfiles/claude/settings.json` (a
  second, broader allowlist applied to every session in this harness).

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
