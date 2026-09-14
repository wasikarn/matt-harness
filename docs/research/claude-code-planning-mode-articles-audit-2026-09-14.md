# Claude Code planning-mode articles adoption audit (2026-09-14)

**Date:** 2026-09-14
**Source:** Two claudefa.st blog posts by Abdullah Mobayad, saved verbatim to a session scratchpad
before analysis (not re-fetched mid-audit): *"Claude Code Planning Mode: Shift+Tab Twice"*
(published 9/11/2026) and *"Claude Code Auto Planning: Let AI Architect Your Solution"* (published
9/14/2026). No local clone, no pinned revision — these are single blog pages, not a repo.
**Verdict:** Decline. The articles' core recommendation — force plan mode via an
`--append-system-prompt` prompt-injection trick that steers Claude to call `exit_plan_mode` before
every Write/Edit/Bash — is technically inferior to a real, documented CLI mechanism
(`--permission-mode plan` / `permissions.defaultMode`) this operator's own global config already
adopted the same day this audit ran, sourced from official docs rather than a blog. Separately,
matt-harness already designed and explicitly declined the hook-shaped equivalent of this idea
(`CHANGELOG.md:11139`) and already reconciled a near-identical externally-sourced "mandatory plan
mode" proposal against `METHODOLOGY.md` Rule 1 (`CHANGELOG.md:10731`). Several of the articles'
technical claims are also stale or wrong against the installed Claude Code v2.1.270 binary.

Every claim below about the sources is what they describe as of this read, not a verified fact
about the sources' claims as they may read today.

## Method

Ran `mh:idea-audit`: two isolated `general-purpose` analysts in parallel (Agent A — claims
extraction + verification against the installed Claude Code CLI and this repo's own docs; Agent B —
repo-fit analysis, no claim-truth judgment), then one adversarial re-check. The Codex primary
(`gpt-5-sol`) failed to dispatch (invalid model slug, no output produced) — fell back to a
`general-purpose` attacker per the skill's fallback rule; **independence is reduced for this
pass**, same model family as the two analysts. No prior `docs/research/*.md` covers these exact
two articles; the closest existing coverage is `plan-mode-nudge-audit-2026-08-05.md`, which this
audit's table shape is copied from.

## Claim-by-claim: source technical claims vs. installed Claude Code v2.1.270

Legend: `MATCH` = claim confirmed against primary evidence · `PARTIAL` = partially confirmed ·
`GAP` = claim not found / contradicted by primary evidence · `N-A` = not applicable to this repo.

| # | Claim | Verified? | This repo's posture | Verdict |
|---|---|---|---|---|
| 1 | Shift+Tab twice enters plan mode | Yes — observed directly | Official docs: `default → acceptEdits → plan`, 2 presses from Manual mode (3 if the session defaults to `auto`, e.g. Pro/Max/Team) | PARTIAL |
| 2 | Shift+Tab again exits plan mode without approving | Yes — observed directly | Matches official docs verbatim | MATCH |
| 3 | Plan mode allows Read/Glob/Grep/WebSearch/WebFetch/TodoWrite; blocks Edit/Write/NotebookEdit | Yes — observed directly | Matches current official tools-reference table | MATCH |
| 4 | Plan mode also allows LS, NotebookRead, TodoRead, and blocks Bash and MultiEdit | Partially wrong | `TodoRead` is fully gone (0 hits, real 2.1.270 binary). `LS`/`NotebookRead`/`MultiEdit` are absent from the *public* docs table but still live as internal permission-set identifiers in the real binary (`strings`: `MultiEdit`=9, `NotebookRead`=7, `LS` in a literal `Set([...,"MultiEdit","LS"])`). Bash is **not** flatly blocked — official docs state plan mode runs shell commands for read-only exploration; only non-read-only commands hit the normal permission flow | GAP |
| 5 | `--append-system-prompt` CLI flag exists, added in Claude Code v1.0.51 | Yes — observed directly | `claude --help` (v2.1.270) lists it verbatim; npm tarball diff (1.0.30/1.0.50 absent, 1.0.51 present as a real `.addOption(...)`) confirms the version floor | MATCH |
| 6 | The flag "triggers the hidden `exit_plan_mode` tool" | Wrong casing, real mechanism | The real, user-facing tool name is `ExitPlanMode` (PascalCase, 27 substring hits in user-facing sentences like `"call ExitPlanMode again"`); `exit_plan_mode` (7 hits) survives only inside telemetry-event slugs (`permission_exit_plan_mode_v2`), not as a callable tool identifier. It is also not "hidden" — `ExitPlanMode` is in the public tools-reference table | GAP |
| 7 | Each new user message needs fresh plan-mode approval under the trick; previous approvals don't carry over | Not independently checkable | Contrasts with official *built-in* plan mode, where approving a plan exits plan mode and carries over for that plan's execution — this claim is specific to the unofficial re-injection trick, plausible but unverifiable from outside | N-A |
| 8 | (Not in the two articles; independently verified because it changes the adoption decision) A real, documented alternative to the trick exists: `--permission-mode plan` / `permissions.defaultMode: "plan"` | Yes — observed directly, twice | `claude --help` lists `--permission-mode` with `"plan"` as a valid choice; the real binary's validation string spells out `"plan" (analysis only)` next to `permissions.defaultMode` as a live settings key. The operator's own global `~/.claude/CLAUDE.md` independently added a "Forcing plan mode" section citing these same two surfaces, sourced from official docs, the same day this audit ran | N-A |

**Methodology gotcha, worth flagging for future audits on this machine, not a defect in the
findings above:** `claude` on `PATH` resolves to a Superset wrapper shell script, not the real
binary — running `strings` on the wrapper yields zero hits for every tool name. Every check above
was run against the real binary the wrapper execs to (a versioned path under the local Claude Code
install directory); `claude --help`'s functional output forwards through the wrapper correctly, so
only raw `strings`-based checks need the resolved path.

## Shipped

Nothing — this is a read-only research pass. Nothing in matt-harness changed as a result.

## Deliberately not shipped

- **The `--append-system-prompt` auto-planning trick, as a matt-harness convention or hook.** —
  `CHANGELOG.md:11139` (a stateful `PreToolUse:Edit|Write` checkpoint was explicitly designed and
  not built, citing Rule 2's false-positive-ask risk) and `CHANGELOG.md:10731` (a near-identical
  externally-sourced "mandatory plan mode" proposal already reconciled against `METHODOLOGY.md`
  Rule 1 and lost). Labeled: **premise dead** — the repo already litigated this exact shape once
  and the real CLI mechanism supersedes the trick technically.
- **A deterministic hook that force-gates plan mode before every Write/Edit/Bash.** —
  `hooks/advisory/flow-nudge.sh` (the repo's actual prior plan-mode nudge hook) was deleted in
  commit `10b6230f`, whose message explicitly lists "all advisory nudges" among the deletions;
  `skills/review/compliance-audit/SKILL.md:72-74,172` explicitly forbids entering plan mode for
  that skill, so an unconditional gate would break a live skill. Labeled: **declined on evidence**.
- **Correcting `docs/research/native-tools-claude-code-vs-codex-2026-09-06.md`'s tool-name
  casing/allowlist based on this pass's fresher binary check.** — out of this audit's scope (a
  different source, a different date); flagged below as an open question instead of edited
  unilaterally. Labeled: **deferred**.

## Decision score (METHODOLOGY Rule 14)

| Criterion | Weight | Score | Reason |
|---|---|---|---|
| Primary-source fidelity | 35 | 55 | Largest weight — a confident adoption decision can't rest on unchecked claims. Of 8 checkable claims, 3 MATCH, 2 PARTIAL/contextual, 2 GAP (Bash-blocked claim, `exit_plan_mode` casing), 1 N-A; both GAPs are load-bearing to the articles' central "hidden mechanism" pitch |
| Marginal value over existing doctrine | 25 | 5 | The operator's own global `CLAUDE.md` already documents the correct, more current, officially-sourced mechanism (`--permission-mode plan` / `permissions.defaultMode`) and explicitly rejects "a system-prompt-injection hack" the same day this audit ran — there is nothing left for the articles' trick to add |
| Architecture/doctrine fit | 20 | 10 | `--append-system-prompt` is a CLI launch flag, not a `hooks.json` `PreToolUse`-gateable surface; the deterministic hook-shaped equivalent was already designed and declined (`CHANGELOG.md:11139`); a near-identical proposal already lost against Rule 1 (`CHANGELOG.md:10731`); an unconditional gate would break `compliance-audit`'s explicit plan-mode exclusion |
| Risk-adjusted cost if adopted anyway | 10 | 15 | Building the hook-equivalent would touch the gate-canary/audit surface and need explicit `compliance-audit` compatibility handling — real but bounded, reversible cost for zero identified benefit |
| Evidence-base confidence / verification rigor | 10 | 75 | Two isolated analysts plus one adversarial re-check with binary-`strings`, `git log`, and `CHANGELOG` line citations — solid, but the adversarial pass lost model-family independence (Codex dispatch failed, fell back to same-family Claude) |

Weighted sum: 0.35(55) + 0.25(5) + 0.20(10) + 0.10(15) + 0.10(75) = 19.25 + 1.25 + 2.0 + 1.5 + 7.5 =
**31.5/100**. Pass threshold 70, fatal-weakness floor: any single criterion below 40% of its own
max. Marginal value (5/100, floor 40) and architecture fit (10/100, floor 40) both trip the floor
independently of the weighted sum. **FAIL — decline.** Confidence: high (two independent analysts,
one same-family adversarial re-check with real citations, and corroboration from a same-day,
independently-produced official-docs-sourced config change reaching the identical real-mechanism
conclusion via a different path).

## Open questions

- Whether `docs/research/native-tools-claude-code-vs-codex-2026-09-06.md`'s tool-name findings
  used the real binary or the Superset wrapper — revisit only if that doc's own tool-name claims
  are next relied on for a decision, not from re-reading it speculatively.
- `CHANGELOG.md:11139`'s stated revisit trigger ("if the implement-without-plan pattern persists
  after ~5-10 non-trivial sessions") — unevaluated by this audit; revisit only if that specific
  pattern is observed recurring, not on a schedule.

<!-- Reserved: a later pass appends a dated correction here, never rewrites the sections above. -->
