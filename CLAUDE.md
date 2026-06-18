# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **personal Claude Code harness** delivered as an installable plugin (`kbg@kobig`). It is not a traditional software project with build artifacts — it is a configuration-and-doctrine package that the Claude Code plugin system auto-discovers and loads into sessions.

The repo contains 6 auto-discovered component directories (`agents/`, `skills/`, `commands/`, `hooks/`, `output-styles/`, `themes/`) plus doctrine files (`METHODOLOGY.md`, `RTK.md`, `ACLI.md`, `DBGATE.md`) and supporting infrastructure (eval harness, audit scripts, governance journal schema).

## Architecture requiring multi-file reading

### Plugin delivery model (the "single path")

There is **one delivery path**: the plugin cache at `~/.claude/plugins/cache/kobig/kbg/<version>/`. The owner dogfoods the same plugin that external installers use. There is no separate "owner" path. See `docs/adr/0001-personal-harness-as-plugin.md` for the irreversible decision.

**Cache-invalidation is manual and load-bearing:** when you add/modify/remove any plugin-delivered surface (agent, skill, command, hook, output-style, theme), you MUST:
1. Bump version in **both** `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
2. Update description counts in both manifests (skills/agents/commands/hooks) — only when **adding/removing** a component (a pure modify changes no count)
3. Commit + push
4. Run `claude plugin update kbg@kobig`
5. Restart Claude Code

Skipping step 1 or 2 causes the plugin cache to stale-load the old version, and `harness-audit` (check #31.2) will CRIT-flag the version mismatch.

### Context hierarchy (L1 / L2 / L3)

kbg-harness organizes context in three tiers — borrow-from Wang 2026 "Vertical Agent" L1/L2/L3 cache model:

| Tier | What | When |
|------|------|------|
| **L1** (always resident) | METHODOLOGY / RTK / ACLI / DBGATE + CLAUDE.md + MEMORY.md + a one-line pointer to `docs/reference/reasoning-models.md` | Injected every session by `doctrine-bootstrap.sh`; zero discovery cost |
| **L2** (on demand) | Individual SKILL.md files, command `.md` files, agent specs | One invocation (`kbg:<skill>`) or skill-nudge keyword match; low discovery cost |
| **L3** (escape hatch) | BOUNDARY.md + raw source (`skills/`, `agents/`, `commands/`, `hooks/`) + `docs/reference/` (including vendored thinking-skills) | Explicit read; use `kbg:harness-nav` for guided mining when L2 misses |

**Navigation rule:** when the right skill is unknown, reach for `kbg:harness-nav` (the L3 mining skill with grep recipes) rather than reading all SKILL.md files blindly. If L3 confirms no coverage, do the task inline.

### Doctrine injection (mandatory, no opt-in)

`hooks/session/doctrine-bootstrap.sh` is a **matcher-less SessionStart hook** (registered in `hooks/hooks.json`) that injects `METHODOLOGY.md` / `RTK.md` / `ACLI.md` / `DBGATE.md` as `additionalContext` on **every** SessionStart sub-event (`startup`, `resume`, `clear`, `compact`). No manual `@import` needed. The hook self-suppresses if `~/.claude/CLAUDE.md` still `@import`s doctrine (it does not, post-cutover).

**Do not** add speculative configurability to doctrine files — this is a personal harness, not a product. METHODOLOGY Rule 2: "No speculative configurability."

### The autonomy invariant (load-bearing, ADR 0002)

No autonomous or unattended self-repair loop. Every self-improvement iteration stops at a human `AskUserQuestion` gate before any mutation. `recursive-improve/SKILL.md` carries `disable-model-invocation: true` so the model cannot self-start it.

**Implications for development:** if a feature requires an unattended loop, cron trigger, or model-as-own-gate, the answer is **"out of scope by design"** — do not amend ADR 0002. The autonomy invariant is a judgment-preservation choice, not a capability gap.

### Hook architecture (two conventions)

Hooks are shell scripts registered in `hooks/hooks.json`. There are two distinct hook conventions:

1. **PreToolUse gates** — emit JSON `permissionDecision` (`deny`/`ask`/`none`) on stdout. Must exit 0 (per vendor spec, exit 2 discards the JSON). Assert the emitted decision string, not the exit code.
2. **TaskCompleted enforcement** (`hooks/lifecycle/task-lifecycle.sh` F7) — uses **exit 2 + stderr feedback** (different convention from PreToolUse). The 12 F7 tests in `tests/hooks/runners/test-critical-hooks.sh` use `check_task` (asserts exit code + stderr substring).

All hooks that shell out to external tools (`rtk`, `qmd`, `code-review-graph`) must degrade gracefully when absent (`command -v` guard, silent no-op). No bundled dependencies.

### Harness as a 2×2 mental model (why 14 hook events exist)

Böckeler (Thoughtworks, [harness-engineering 2026-04](https://martinfowler.com/articles/harness-engineering.html)) models a coding-agent harness as a 2×2 of **direction** × **execution type**:

| | **Computational** (deterministic, fast, cheap) | **Inferential** (semantic, slow, non-deterministic) |
|---|---|---|
| **Feedforward** (steer *before* the act) | PreToolUse gates that deny/ask | Doctrine injection + skill `description:` triggers |
| **Feedback** (observe *after* the act) | PostToolUse audits, critical-hooks tests, `audit.sh` checks | `kbg:review-pr`, `verification-gate.sh` (advisory), `fabrication-verdict-log.sh` |

**Why this is load-bearing for kbg:** the article warns that one without the other is broken — feedback-only = "agent that keeps repeating the same mistakes"; feedforward-only = "agent that encodes rules but never finds out whether they worked" (L345). The 14 hook events in `hooks/hooks.json` are kbg's answer to populating every cell:

- **Computational FF** → `block-dangerous-git.sh`, `secret-scan.sh`, `block-alias-shadowing.sh`, `block-bash-doctrine-write.sh`, `config-protection.sh`, `db-write-gate.sh`, `secret-read-guard`, `doctrine-edit-gate`
- **Inferential FF** → `doctrine-bootstrap.sh` (matcher-less SessionStart injects METHODOLOGY/RTK/ACLI/DBGATE), `iron-rule-reminder.sh`, `orchestrator-nudge.sh`
- **Computational FB** → `post-edit-audit.sh`, `security-diff-review.py`, `test-critical-hooks.sh` (the critical-hooks suite), `audit.sh` (the audit checks)
- **Inferential FB** → `verification-gate.sh` (SessionEnd, **journals but NEVER emits `permissionDecision`** — see [LLM-judge circularity](#llm-judge-circularity-why-inferential-sensors-are-advisory) below), `fabrication-verdict-log.sh` (Stop), `kbg:review-pr` (command), `inferential-structural-judge` (SessionEnd, advisories on diff shape — over-engineering / arch-drift / test-pattern / doctrine-conformance; designed in `docs/research/inferential-structural-judge-design.md`)

**Anti-pattern:** don't add an inferential-FB sensor that emits a `permissionDecision` — same model class across generation, judgment, and meta-engineering is a single-model failure mode. The 2×2 framing is the *justification* for the `verification-gate.sh` "advisory only" invariant (ADR 0002 §L115).

### LLM-judge circularity (why inferential sensors are advisory)

The 2×2 cell most at risk of a covert failure is **inferential FB**: a "smart" sensor that uses the same model class to judge work the model just produced. Three failure modes:

1. **Shared blind spots.** A judge inherits the generator's blind spots. A model that mis-diagnoses a bug cannot catch itself mis-diagnosing that bug.
2. **Self-confirming verdicts.** Inferential-FB sensors on a "happy path" of similar-generation-then-judge sessions can quietly converge to "everything is fine."
3. **Covert L4 loop.** A `permissionDecision: deny` from an inferential-FB sensor is a model-driven mutation gate — the autonomy invariant (ADR 0002) forbids it.

**kbg's posture:** all inferential-FB sensors in `hooks/` are **advisory only** — they journal, they do not block. The critical-hooks suite + the audit checks are the *computational* FB that does the enforcement. This is the symmetric counterpart of the 2×2's load-bearing warning: we get the L345 feedback loop by leaning on the computational-FB column, not by adding inferential-FB `permissionDecision`s.

The `.scratch/research/harness-engineering-2026-04.md` 1-pager (cross-referenced from `docs/harness-decay-cadence.md`) is the full comparison and 3-now/3-later action list.

### BOUNDARY.md regeneration (and the XREF trap)

`BOUNDARY.md` is auto-regenerated by `skills/inventory/scripts/inventory-boundary.sh --repo-only`. Any hand-edited section you add to `BOUNDARY.md` will be **silently deleted on the next regen** unless you also add a corresponding `XREF{N}` heredoc block in the regenerator script. See `inventory-boundary.sh:178-227` for the XREF2 pattern (Team-ready blocks + Agent Teams sections).

### Coordination-as-code (`scripts/orchestrate-dispatch.py`)

The dispatcher is the deterministic rendering half of the coordination contract; the lead (`/team-build`) is the judgment half. It reads workflow specs (JSON/YAML), validates schema (no cycles / no bad refs / no missing fields), resolves DAG into waves, flags F8.5 fan-out overflow, and emits plans. It does **NOT** spawn LLM agents — agent-typed stages are emitted as "would-spawn" lines that the lead dispatches per the F9 template. Putting LLM dispatch inside the dispatcher would be a covert L4 loop, which the autonomy invariant forbids.

### Error-handling convention (`skills/_lib/err.sh`)

Shell scripts under `skills/` use a shared error-handling contract defined in `skills/_lib/err.sh`:

- **`set -euo pipefail`** as the first executable line in every skill script that does I/O.
- **`err_die <message> [code]`** for unrecoverable failures — always prints `ERROR:` to stderr with a clear reason.
- **`err_warn <message>`** for non-fatal problems the operator should know about.
- **`err_usage <message>`** for bad arguments (exits 2).
- **`require_cmd <command>`** for mandatory dependencies; degrades gracefully for optional ones via `command -v`.
- **`temp_register <path>`** + automatic `EXIT` trap cleanup for temp files.

**Why this matters:** fail-open bash scripts silently produce green-but-empty audit results (the 2026-06-12 audit found that `globstar` and `set -uo pipefail` without `-e` masked zero-file scans). The contract keeps failures loud and readable without adding speculative retry/circuit-breaker machinery.

**Hook exception:** hooks remain on `set -uo pipefail` (no `-e`) because PreToolUse gates must emit a valid JSON `permissionDecision` and exit 0 even when internal tools fail; a non-zero exit would discard the JSON per the vendor spec. Hooks may still source `err.sh` for `err_warn` and readable stderr, but must never let an unhandled error change the exit code. TaskCompleted hooks use the exit-2 + stderr convention documented above.

**Test coverage:** `tests/skills/_lib/run-tests.sh` guards `err.sh` helpers; add cases there when extending the contract.

## Commands to develop in this codebase

### Validation (the "build" equivalent)

Git hooks run the right layer at the right lifecycle:

```bash
# On every commit: syntax/lint checks + self-audit + affected eval fixtures only
# (installed as core.hooksPath=git-hooks)
bash git-hooks/pre-commit

# On every push: full parallel gauntlet
bash git-hooks/pre-push

# Manual fast parallel gauntlet (same as pre-push)
bash scripts/run-gauntlet.sh

# Skip the slow critical-hooks suite for a quick local check
bash scripts/run-gauntlet.sh --fast
```

Single-layer debugging (run these directly to isolate a failure):

```bash
# Plugin manifest strict validation (catches schema/manifest drift)
claude plugin validate --strict .

# Critical-hooks smoke tests (the primary safety gate)
bash tests/hooks/runners/test-critical-hooks.sh

# Harness self-audit (0 Critical / 0 Warnings = clean)
bash skills/harness-audit/scripts/audit.sh .

# Eval harness (dataset + regression fixtures; --gate exits non-zero on failure)
python3 eval/run-eval.py --dataset eval/datasets/ --regression --gate
```

The pre-push gauntlet runs four layers in parallel: plugin-validate, self-audit,
critical-hooks suite, and the full eval gate. The critical-hooks suite itself
runs its 10 sub-suites in parallel, and the eval gate runs fixtures concurrently
via `eval/run-eval.py --workers` (default: min(8, CPU count)). The pre-commit hook
runs syntax/lint checks, the self-audit, and affected eval fixtures in parallel.
All four gauntlet layers must pass before any commit that touches hooks, skills,
agents, commands, or manifests.

### Running a single test

There is no "single test" runner for the critical-hooks suite — it is a single bash script that runs all assertions sequentially. To debug one assertion, extract the `check()` or `check_task()` call plus its preceding `json='...'` payload and run it in isolation:

```bash
HOOKS="$(pwd)/hooks"
json='{"tool":"Bash","input":{"command":"rm -rf /"}}'
printf '%s' "$json" | bash "$HOOKS/block-dangerous-git.sh"
```

For eval fixtures, filter by dataset or tag:
```bash
python3 eval/run-eval.py --dataset eval/datasets/harness-audit.json
python3 eval/run-eval.py --regression --tag task-completed
```

### After modifying any plugin surface

```bash
# Update plugin cache (must restart Claude Code after)
claude plugin update kbg@kobig
```

### Regenerate BOUNDARY.md

```bash
bash skills/inventory/scripts/inventory-boundary.sh --repo-only
```

### Adding a new component

1. **Agent:** create `agents/<name>.md` with frontmatter (`name`, `description`, `tools` allowlist). No registration needed — auto-discovered.
2. **Skill:** create `skills/<name>/SKILL.md` with frontmatter (`name`, `description`). Add a `## Input Contract` / `## Output Format` / `## Failure Modes` section **only where the skill has a real I/O contract worth stating** — these are no longer mandated fleet-wide (the blanket #31.1 requirement was retired 2026-06-16; it manufactured byte-identical boilerplate). Optionally add `tests/evals/skills/<name>/evals.json` for eval coverage.
3. **Command:** create `commands/<name>.md` with frontmatter (`name`, `description`). Set `disable-model-invocation` per the criterion below (not a blanket "all commands"). Update `plugin.json` + `marketplace.json` description counts. (`commands/` is officially a *legacy* dir — [docs](https://code.claude.com/docs/en/plugins) say "use skills/ instead"; kbg keeps it for the user-verb surface. Do **not** add a `type:` field — it is not in the official frontmatter schema and nothing reads it.)

#### `disable-model-invocation` — per-surface, with a recorded reason

Official semantics ([docs/en/skills](https://code.claude.com/docs/en/skills)): the flag makes a skill/command **user-only** — "restricts a skill so only the user can invoke it, preventing Claude from running it automatically" (it also drops the description from model context). The model *can* otherwise invoke commands via the Skill tool, so the flag is the only thing that makes a surface user-only. The vendor's own test: *flag it iff Claude deciding to run it **unprompted, because the work looks ready**, would be wrong* (their `/deploy` example).

Choose **per surface** and **record why** in a `disable-model-invocation-reason:` frontmatter line — audit **#35 WARNs** on any flag without one. (The reason requirement is what stops the retired "all commands flagged" blanket from creeping back as undocumented dir-of-origin residue — an adversarial review found several flags were exactly that.)

- **Set it** when autonomous invocation would cross an **irreversible / external (network, tracker, production) / destructive / governance** boundary the operator has not stood at — e.g. `ship-*` (server-side merge/release), `create-jira-*` (tracker write), `decommission` + `team-cleanup` (destructive), `dismiss-stale` (the model must not mute its own safety alert).
- **Leave it off** for **read-only reporters, analysis, and capabilities the model uses to fulfil an explicit request** — *even if they mutate the local tree or spawn agents.* Writing code (`backend-dev`), reviewing (`review-pr`, ~8 agents), researching (`research-brief`), running a bulk op the user asked for (`acli`) are the model's core job; gating them cripples the assistant. Agent-spawn **cost** is governed by the fan-out cap (F8.5 / the dispatcher), **not** by this flag — never flag a surface merely because it spawns agents.

**Safety vs taste (do not conflate).** For ~25 surfaces this flag is reversible UX taste — flip it per the recorded reason. For **`recursive-improve` alone** it is a load-bearing instance of the autonomy invariant, guarded by audit **#32 (CRIT)** and recorded in **[ADR 0002](docs/adr/0002-autonomy-invariant.md)**. Never reason about `recursive-improve`'s flag through this taste criterion — #32 governs it.

#### Naming new surfaces — `noun-verb`, reuse the verb

Most surfaces are named by their action (`ship-*`, `team-*`, `create-jira-*`). The **`harness-*`** cluster is the one place a single noun carries several verbs (`harness-audit` / `harness-health` / `harness-coverage` / `harness-nav`). When you add to a noun-group, **reuse an existing verb before coining a new one** and keep `noun-verb` order, so the cluster stays guessable from one example. This is for **new** surfaces only — do **not** rename the existing fleet to fit a grammar (churn the harness does not need). The duplicate-surface audit (**#20.5**) catches a new name whose description collides with an existing surface's.
4. **Hook:** create `hooks/<name>.sh`, add entry to `hooks/hooks.json`. Add tests to `tests/hooks/runners/test-critical-hooks.sh` if it is a PreToolUse or TaskCompleted gate.
5. **After any of the above:** bump manifest versions, validate, commit, push, update cache, restart:
   ```bash
   # Bump version in BOTH manifests, then:
   claude plugin validate --strict .                     # 1. validate manifest
   bash tests/hooks/runners/test-critical-hooks.sh              # 2. hook tests
   bash skills/harness-audit/scripts/audit.sh .         # 3. self-audit
   python3 eval/run-eval.py --dataset eval/datasets/ --regression --gate  # 4. eval gate
   git add -A && git commit -m "feat: ..." && git push origin develop   # 5. commit + push
   claude plugin update kbg@kobig                        # 6. update cache
   # 7. restart Claude Code
   ```

### Branch model

Single-branch (`develop` only). Commit + push direct. No feature branches. See `memory/branching-model.md`.

## Key files that span multiple concerns

| File | What it does | Read before modifying |
|------|-------------|----------------------|
| `hooks/hooks.json` | Registers all hooks across 14 lifecycle events. Determines which shell scripts fire on which event/matcher. | Any hook change |
| `hooks/_lib.sh` | Shared helpers (`hook_audit_log`, `journal_append`, `kbg_permission_decision`). Sourced by most hooks. | Any hook change |
| `hooks/JOURNAL-SCHEMA.md` | Governance evidence journal schema. Defines JSONL event format for audit trails. | Any hook that journals |
| `eval/run-eval.py` | Eval harness entry point. Reads datasets + regression fixtures, computes pass/fail, emits machine-readable JSON. | Any eval addition |
| `skills/inventory/scripts/inventory-boundary.sh` | BOUNDARY.md regenerator. Contains XREF heredoc blocks that preserve hand-edited sections across regen. | Any BOUNDARY.md edit |
| `scripts/orchestrate-dispatch.py` | Workflow spec validator + DAG resolver + plan emitter. Enforces F8.5 fan-out cap. | Any orchestrate skill change |
| `scripts/auth-health-check.py` | gh/MCP/plugins health probe. 3-state exit contract (0=healthy, 1=degraded, 2=broken). | Any auth/MCP/plugin change |
| `scripts/evals/run-acceptance.py` | Deterministic acceptance runner against locked `ACCEPTANCE.md` contracts. 5 exit codes (PASS/FAIL/INVOCATION/PARSE/BLOCK). | Any pre-ship-verify change |
| `docs/harness-decay-cadence.md` | Quarterly build-to-delete + permission re-audit cadence. `last_permission_review:` marker is machine-checked by audit. | Any agent `tools:` change |

## Deliberate non-goals (do not add)

- No public-marketplace publish, no CI release train (`.github/workflows/validate.yml` is a conformance gate, not a release train).
- No bundled MCP/LSP servers.
- No L3/L4 autonomy primitives (`/loop`, `CronCreate`, Evo meta-loop, Ollie flywheel).
- No Option B (public-distributable) machinery.
