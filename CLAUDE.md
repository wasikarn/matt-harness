# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Validation (run before committing)

```bash
claude plugin validate --strict
```

Plugin manifest is the primary validation gate. `scripts/run-gauntlet.sh` runs plugin-validate + full shell-lint + JSON lint + harness-audit + the hook behavioral suite (`hooks/tests/test-gates.sh` + `test-flow-nudge.sh` + `test-session-stop.sh` — deny-gate + advisory-sensor + session/stop-hook unit tests) in parallel. The broader fleet critical-hooks suite and the eval dataset gate are pending rebuild.

## Adding or removing a surface

Auto-discovered directories: `agents/`, `skills/`, `commands/`, `hooks/`, `output-styles/`, `themes/`. See `.claude/skills/add-surface/SKILL.md` for the step-by-step (manifest bump, validation, BOUNDARY.md regen).

## Git hooks

Hooks live in `git-hooks/` (not `.git/hooks/`). Wire once per clone:

```bash
git config core.hooksPath git-hooks
```

pre-commit: fast gate — syntax/lint (`bash -n` + shellcheck), JSON validation, CRITICAL harness-audit (graceful-skip if absent).
pre-push: full gauntlet (all validation layers in parallel).

## Composer-not-creator doctrine

Before writing a new skill, command, or agent from scratch, check sources in this order: **(1)**
`mattpocock/skills` first — `claude plugin list` / the Skill tool's own available-skills list for
what's already installed under the `mattpocock-skills` plugin, plus the local clone at
`/Users/kobig/Codes/Personals/mattpocock-skills` for what's upstream-available but not yet
installed. This is a **Matt-Pocock-first harness** (21 of his skills installed as the
`mattpocock-skills@mattpocock` plugin, namespaced `mattpocock-skills:<name>` — see README.md Quick
Start; migrated off the earlier unnamespaced `gh skill` installs 2026-07-17); checking
ECC/superpowers before matt's own repo gets the priority backwards. **(2)** the upstream ECC repo
at `/Users/kobig/Codes/Personals/ECC` and
the vendored superpowers checkout at `/Users/kobig/Codes/Personals/superpowers`. **(3)** sibling
harnesses under `/Users/kobig/Codes/Personals/` worth a structural-pattern check even when they're
not kbg's primary composer sources (e.g. `oh-my-claudecode` — cherry-picked before, ask if
unsure which repos currently qualify). Cherry-pick and adapt from whichever source fits; create
kbg-native surfaces only when none do. Confirmed gap (2026-07-17): `code-implementer`/`/implement`
were built checking only (2), skipping (1) — collided with matt's own `engineering/implement`
skill, caught by the user, not by this checklist. (A hand-pinned HEAD hash is structurally doomed
to re-stale; the path is the stable anchor — run `git rev-parse HEAD` there when you need the
current commit.)

## Architecture

The plugin ships as `kbg@kobig` from the `wasikarn/kbg-harness` GitHub repo. Claude Code loads all surfaces from `~/.claude/plugins/cache/kobig/kbg/<version>/` at startup. Nothing is symlinked.

**Doctrine injection:** `hooks/session/doctrine-bootstrap.sh` fires on SessionStart and injects `docs/METHODOLOGY.md` (decision-sizing triad + reasoning scaffold) into session context via `$CLAUDE_PLUGIN_ROOT` (the plugin install dir; the older `$CLAUDE_PLUGIN_DIR` name is not a real CC variable and expands empty).

**Operating model:** deny the irrecoverable set computationally (gates in `hooks/gates/`), advise on the rest (sensors in `hooks/advisory/`). Advisory sensors never emit `permissionDecision`. The L2–L5 autonomy ladder is retired.

**Why — the unifying crux:** the gate is a *verifier* (deterministic shell returning a branchable **score**), the model is the *maker*, and the maker can never grade its own work — an LLM judging its own output is circular ("two optimists agreeing"). So advisory sensors journal but never gate, and the autonomy ladder had to retire: a model-as-gate is the maker appointing its own verifier. **Score, not feel** — every loop's stop condition must be a number a deterministic gate can branch on, never a vibe the model rationalizes. (This is the agent-loop verifier-separation principle; see `docs/research/` + the retired L2–L5 build for the proven failure it prevents.)

When hooks are wired: gates/ (deny), advisory/ (journal), session/ (inject), stop/ (cost tracking).

## Skill authoring doctrine (matt-pocock)

When creating or editing a skill under `skills/`, follow matt-pocock's `writing-great-skills` doctrine — canonical: the `mattpocock-skills:writing-great-skills` skill (installed as the `mattpocock-skills` plugin, not vendored in this repo since v0.46.0 — see README.md Quick Start; leading word, ≤25-word description, completion criterion, no-op test, two-cuts, failure-mode guard).

The `docs/skill-template/SKILL.md` template carries this checklist as a `## Design checks` section — but `harness-audit` check 36 does **not** check for that heading's presence. It checks 4 of the 6 doctrine elements via INFO-only regex proxies against each skill's live description/body (leading-word vocabulary, ≤25-word count, completion-criterion phrasing, a no-op-test line-count heuristic); "two-cuts" and "failure-mode guard" have no shell check — a failure-mode regex proxy was tried and retired 2026-07-16 (vacuous before a reset-bug fix, 5/5 false-positive after: every flagged skill already named its failure mode in a prose section or bullet list the numbered-window proxy couldn't see). INFO findings never fail the gate. Confirmed 2026-07-10: only 2/33 native skills (`pr`, `task-prep`) actually carry a `## Design checks` section — the template's checklist is documentation, not an enforced requirement.

**Named Model footers:** a skill/command/agent that makes load-bearing reasoning/judgment choices may end with a `## Named Model` footer citing cc-thinking-skills lenses. Apply the 3-condition rubric from `memory/mental-models-sweep-v0302-2026-07-03.md`: (1) load-bearing reasoning gap, (2) name-a-lens benefit for the operator, (3) honesty posture preserved (footer is a scaffold + catalog pointer, never "this lens proves correctness"). The curated catalog is `docs/reference/reasoning-models.md`; the 39 raw models live under `docs/reference/thinking-skills/skills/`.

**Suggested next step footers:** a workflow surface (command or workflow skill run as a discrete step) may end its Output/Summary phase with a `Suggested next step:` marker — outcome-branched (`situation → action`), citing skills as `kbg:<name>` and commands as `/<name>`. Skills are ALWAYS cited `kbg:`-form (never `/name`) — get this right at authoring time: `harness-audit` check 40 only catches rename/deletion drift on refs already in `kbg:` form, it does **not** scan for a skill mis-cited in slash form (confirmed: this exact bug shipped twice — `commands/pr.md` and `diagnosing-bugs/SKILL.md` both cited a skill as `/name` undetected until a manual survey caught it, v0.35.0). Passive suggestion only — never "invoke X now" / auto-chain (that collides with the no-model-self-start doctrine). Skip self-contained reference/pattern/catalog surfaces (a forced footer there is the retired canonical-sections ceremony, 2026-06-16) and terminal workflows (post-mortem, ship-release terminus).

**Escalation to `AskUserQuestion`:** a branch belongs in the passive footer only while it's anticipatory — conditional on a fact not yet known (did the reviewer comment, did CI go red). If every branch is already true/decidable right now and there's no sensible default, that's a present-tense fork, not a suggestion — surface it via `AskUserQuestion` (per `output-styles/staff-eng.md`'s decision-question rule: one-line consequence per option) instead of text the user might not read. Model: obra/superpowers' `finishing-a-development-branch` skill, which ends by presenting exactly N concrete options (merge/PR/keep/discard) and blocking for the pick — not superpowers' separate (and rejected) `using-superpowers` auto-chain directive. None of kbg's shipped footers (v0.35.0/.1) currently qualify — they're all anticipatory-conditional — so this is a criterion for future surfaces, not a rewrite of what shipped.

## Branching model

Single branch: `develop` only. No feature branches. Commit and push direct.

**Computationally enforced** by `gate:worktree:develop-only` (`WorktreeCreate` event) and the `git worktree add -b` block in `gate:bash:irrecoverable` (`PreToolUse:Bash`). Both gates are opt-in per repo via the `/.kbg-no-worktree` sentinel — present in the kbg-harness repo, absent from tathep/ECC/scratch repos (which keep their existing `gate:write:worktree-guard` redirect). Detached `review-pr-<N>` worktrees in `$TMPDIR` are explicitly allowlisted so the Phase 2 PR-by-number review path keeps working.

## Non-obvious gotchas

- **Hardcoded home paths blocked:** `.sh`/`.py` files must use `$HOME` or `~`, never `/Users/<name>`. The pre-commit gate will reject the commit.
- **`defaultEnabled: false`:** plugin ships disabled. After install, add `"kbg@kobig": true` to Claude Code `settings.json`, then restart.
- **Output style:** `output-styles/staff-eng.md` is the sole live-response register — self-calibrates terse vs full decision-framing by stakes, not by switching files (the old `senior-eng.md`/`staff-eng.md` two-file split was collapsed 2026-07-02; the internal "Calibrate to stakes" rule replaces the escalation/fallback dance). `force-for-plugin: true` auto-activates it whenever `kbg@kobig` is enabled, overriding the user's own `outputStyle` setting — no `/output-style` selection needed, but it also means you can't run a different style while this plugin is on without disabling it first.
- **Working frames:** `contexts/` holds `dev.md`, `review.md`, `research.md` — loaded by `/frame` to set session posture.
- **`grep` is aliased** to `rtk grep` in this environment. Use `/usr/bin/grep` or `awk` for count/stat operations.
- **Cache-invalidation:** same-version edits are no-ops. Always bump both manifests before `claude plugin update`. CLAUDE.md-only edits skip the bump — it's dev-facing repo guidance, not cached plugin content (only `agents/`/`skills/`/`commands/`/`hooks/`/`output-styles/`/`themes/` ship per-version).
- **`BOUNDARY.md` regen:** the script writes to STDOUT, not the file. The `> BOUNDARY.md` redirect is required every time.
- **Never `rm -rf`:** use `trash` for deletions.
- **Never `--no-verify`** on commits or pushes.
- **Stage by name:** never `git add -A` or `git add .`.
- **Skill descriptions load on every Task spawn** (~words×1.3 tokens). Keep descriptions ≤25 words.
- **Thinking models:** default is the triad + `advisor()` inline (METHODOLOGY Rule 1) — `kbg:decide` is on-demand only, for genuinely hard/contested-diagnosis choices (de-scoped 2026-07-02, v0.21.4: 0 real-world invocations vs 55 `advisor()` calls across 182 sessions). The 39 on-demand mental-model files live in `docs/reference/thinking-skills/skills/` (never move to `skills/` — would break fleet count).
- **`disable-model-invocation: true`:** carried by 2 skills currently — `recursive-improve` and `score-decision` (re-check via `grep -rl "disable-model-invocation: true" skills/*/SKILL.md`; the count drifted hard after v0.46.0 moved 17 flag-carrying matt-origin skills out of this repo, and nobody updated this line). Only `recursive-improve/SKILL.md` is **CRIT**-guarded against the flag being silently dropped (`harness-audit` check 39, hardcoded to that one file — the highest-blast-radius surface, an unattended repair loop). Check 30 only WARNs that a `-reason` field exists on whichever skills currently carry the flag; it does not catch the flag disappearing from `score-decision`, the only other one.
- **`review_mode` in `ship-merge`:** `review-pr` tags its state write `pr-by-number` (isolated worktree) or `own-branch` (self-review). `ship-merge` caps the Critical-findings score at the fatal-weakness floor on sensitive-path diffs reviewed `own-branch` — an automation-bias guard against trusting a same-session self-review's severity tiering. "Sensitive-path" covers both auth/secret/credential/payment/billing/token AND the harness's own verifier/gate code (`hooks/gates/**`, `hooks/hooks.json`, `skills/harness-audit/scripts/{audit.sh,checks/**}` — the same list `hooks/gates/verifier-protect.sh` protects).
- **`orchestrate` vs `kbg:decide`:** orchestrate decides whether/how to spend effort on an ask (inline/parallel/sequential/drop, which surface receives it) *before* it's understood as a bounded decision; `decide` reasons through a bounded question once you're already committed to answering it. A pile of competing asks routes through `orchestrate` first; a single reversible-choice question goes straight to `decide`.
- **`SKILL.md` frontmatter ≠ `agents/*.md` frontmatter:** the real skill-file field for tool control is `allowed-tools` (pre-approves without asking; there's no hard-restriction field for skills), not `tools:` — that's the `agents/*.md` subagent field (hard-restricts to a fixed set). Confirmed against the official 16-field `skills.md` reference and the shipped CLI binary's own compiled schema key list. `metadata` / `metadata.origin` / `disable-model-invocation-reason` are non-standard-but-harmless kbg conventions — Claude Code tolerates unrecognized frontmatter keys (confirmed via changelog + `plugin.json`'s own documented "unrecognized fields → warning, not error" policy), they just carry zero behavioral effect.
- **`/goal` vs `goal-craft`:** `/goal` is Claude Code's own native completion-condition loop (v2.1.139+, session-scoped, judged each turn by a separate small model that reads only the transcript). kbg never wraps or auto-invokes `/goal` itself — the user always types `/goal` themselves, no exceptions. `skills/goal-craft/SKILL.md` only composes a paste-ready condition string (mandatory one-way-door screen + turn bound) and, as of 2026-07-08, is model-invocable (its `disable-model-invocation` flag was removed on user request) — the model may draft a condition unprompted, but the string is inert until the user pastes it after `/goal`. Auto-dispatch of `/goal` itself (`claude -p "/goal ..."`) is still a deliberate non-goal — it forks a separate headless session and reopens the retired L4/L5 "no model self-start" invariant.

## Recent versions

Quick orientation for the last few releases. For full notes see `CHANGELOG.md`.

Cap this list at 10 bullets. Keep the last 3-5 releases as individual entries; fold older ones into version-range bullets (`vX.Y.a–vX.Y.b` or `vX.Y.x`) by theme. Adding an 11th bullet means dropping the oldest — `CHANGELOG.md` is the full record, this section is orientation only.

- **v0.58.11** — User switched matt-pocock's skills from unnamespaced `gh skill` installs to the official `mattpocock-skills@mattpocock` Claude Code plugin (namespaced `mattpocock-skills:<name>`, no opt-out — verified against code.claude.com/docs/en/plugins.md). Phase A of a 2-phase migration (per `advisor()` pressure-testing): rewrote kbg's own bare-name references — README.md Quick Start + Attribution table, CLAUDE.md's composer-not-creator + skill-authoring sections, `docs/agent-voice-extension.md`, the flow-nudge/hooks.json/hook-lifecycle-contracts nudge-text sync-seam, `commands/ask-kbg.md` + `kbg-help.md` — to the namespaced form. Removing the 21 old `gh skill` copies is deliberately deferred to a later, restart-gated turn: doc correctness doesn't depend on the plugin being live this session, but destructive removal does, so it's sequenced after a post-restart resolution check to keep rollback free (a failed verify means "don't remove," not "revert a push").
- **v0.58.8-v0.58.10** — Added `agents/code-implementer.md`: the fleet had 7 reviewers plus design/analysis agents but no general implementer writing feature code end-to-end, while framework expertise already sat in 12 `kbg:*-patterns` skills nothing dispatchable composed with. Surveyed ECC (reviewers/build-resolvers only) and superpowers (discipline template, not a persistent agent) — no fit; cherry-picked `oh-my-claudecode`'s `agents/executor.md` as the structural model. Detects the stack, loads the matching `*-patterns` skill via `Skill`, writes smallest-scope/highest-rigor diffs, adversarially self-reviews before handoff as a maker-side quality pass — explicitly NOT the DONE gate, per the verifier-separation crux (`code-reviewer` + gauntlet stay authoritative). Completes `code-architect`→`code-implementer`→`code-reviewer`. One generic agent, not 12 per-framework ones. Live-verified post-restart: the real restricted-tools agent successfully invoked `Skill` and loaded a `*-patterns` skill. v0.58.9 added a cross-project "type-safety first" rule (no `any`/unsafe casts, model invariants as types) and a companion `commands/implement.md` — which v0.58.10 then deleted after the user caught a naming collision with matt-pocock's own pre-existing `implement` skill (a composer-not-creator doctrine gap: only ECC/superpowers were checked, not matt's repo). Fix: installed matt's real `implement` skill and rewrote CLAUDE.md's composer-not-creator section to check `mattpocock/skills` first.
- **v0.58.7** — Closed a gap found while field-testing the `requirement-analyst`→`code-architect`→Plan-Mode chain against v0.58.5's own token-optimizer pass (a "should we build a Planner Subagent" investigation that concluded no — see memory `planner-subagent-descoped-2026-07-17.md`): `docs/common-mistakes.md` embeds 2 `grep -c` self-check assertions against `orchestrate/SKILL.md` that nothing re-ran when the file changed. Added check 43 — extracts the pattern from the doc itself instead of hardcoding it a second time, same defect class as checks 37-40. WARN, currently clean.
- **v0.58.6** — Closed a real fleet-tooling gap: no surface computed SKILL.md body size fresh (`--health` reports session token *cost*, not file size; `inventory` lists surfaces with no size field). Added check 42 (INFO, fleet-relative threshold from the fleet's own p90 distribution) — currently fires on `orchestrate` and `review-pr`. Wired into `/kbg-help`'s discovery table.
- **v0.58.5** — Token-optimizer pass on `orchestrate/SKILL.md` (grown heavily across v0.58.0-v0.58.4): 4 fixes, moved detail into `reference.md` (worked example, backend-identity verification, considered-and-deferred evidence) and trimmed a near-duplicate paragraph. 35,284 → 31,570 chars (~11%), no content lost — moved or already covered in `CHANGELOG.md`.
- **v0.58.4** — User pushed for direct write access for allowlisted external-model delegation. Live-verified the Ollama-launched session shares kbg's full gate stack (not sandboxed, as previously assumed) — gates present but scoped (a narrow deny-list, not blanket write-approval). Cherry-picked patterns from a sibling harness (`oh-my-claudecode`): worktree isolation and schema-validated-verdict-not-direct-action are transplantable; per-provider bypass-flags and conflict-only auto-merge explicitly are not. Decision: propose-only stays (deferred, not refused) — no concrete task has hit the ceiling yet, and the one live write-mode trial that exists (`kimi-k2.7-code:cloud`) is a measured failure. Shipped a diff+`git apply` mechanic for the common code-change case as the one thing that did ship.
- **v0.58.0-v0.58.3** — External-model delegation via Ollama built out end-to-end: propose-only dispatch primitive (v0.58.0, `--permission-mode plan` the only guardrail verified to hold after 2 failed alternatives), `minimax-m3:cloud` live-verified and promoted to default (v0.58.2, incl. catching and fixing a broken `settings.json` symlink), model-selection heuristic + a hardened dispatch script (v0.58.3). v0.58.1 in the same run retired `harness-audit` check 36's failure-mode sub-check — 5/5 live findings were false-positives on skills that were already doctrine-compliant.
- **v0.57.0-v0.57.2** — Added `backend-architect` (systems-design agent above the framework-narrow `*-patterns` skills), then 2 same-day fixes: a scope self-contradiction in its own file, and `flow-nudge.sh`'s English-only regex silently never firing on Thai prompts.
- **v0.55.0-v0.56.0** — Added `summarizer` (clarity/compression specialist, grounded in BLUF/Minto-pyramid/Zinsser-Strunk&White). Fresh-context adversarial verification caught 3 of 5 named-principle citations imprecise and fixed them. Separately, a 110-agent research pass found decision-framing vocabulary ("one-way door", "blast radius") leaking into replies with no decision in them — fixed with a before/after example in `staff-eng.md`, mirrored in dotfiles' global CLAUDE.md.
- **v0.53.0-v0.54.1** — Agent domain-expertise deepening pass on 6 sub-bar agents (security/python/silent-failure/code-architect/refactor/build-error) + added `nextjs-reviewer`. A 5-agent fresh-context verification pass over both found real errors — `nextjs-reviewer` had a flagship claim stated backwards (Next.js 15+ `fetch()` cache default) and a stale Edge-runtime default; `security-reviewer` had 3 wrong CWE mappings.

Older releases: see `CHANGELOG.md` for the full record.
