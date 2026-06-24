---
article: martinfowler.com/articles/harness-engineering.html
lenses-crossed: [angle-1, angle-2, angle-3, angle-4, critique-cost, critique-gaps]
comparison: kbg-harness-0.1.18
date: 2026-06-15
---

# kbg-harness × Böckeler — apply/gap map

## 1. Three-circle model mapping

| Circle (L309, L318) | kbg-harness counterpart |
|---|---|
| **Model** | Claude (Opus/Sonnet) — out of scope |
| **Builder harness** | Claude Code CLI + plugin runtime; `~/.claude/plugins/cache/kobig/kbg/0.1.18/` (CLAUDE.md:13-24) + 14-event hook lifecycle (`hooks/hooks.json:3-449`) |
| **User harness** | The `kbg@kobig` plugin — 28 agents, 34 skills, 16 commands, 38 hooks + doctrine on SessionStart (`hooks/session/doctrine-bootstrap.sh`, CLAUDE.md:26-30) |

## 2. Maintainability axis (L354-446)

- **Coding conventions** (inferential FF) → `METHODOLOGY.md` (13 rules) + 34 skill `description:` blocks (audit.sh:288-301)
- **Code mods** (computational FF) → **No kbg-harness counterpart found** — no OpenRewrite / AST codemods
- **Structural tests** (computational FB) → `tests/hooks/runners/test-critical-hooks.sh` (204 assertions) + `eval/run-eval.py --gate` (run-eval.py:704) + `audit.sh` CRIT/WARN/INFO
- **Review instructions** (inferential FB) → `agents/code-reviewer` + 8 sub-skills via `kbg:review-pr`

**Sensors kbg does NOT have**: no dead-code detector, no test-quality grader, no mutation testing, no AI `response-quality-sampling` (angle-1 §4). LLM-judge → agents — critique-cost §3 circularity risk.

## 3. Architecture fitness axis (L451-491)

- **Performance requirements** → `skills/perf/SKILL.md`; the only *enforced* standard is `METHODOLOGY.md:113-118` "Token Budgets Are Not Advisory" (4k/task, 30k/session), observable via `audit.sh`
- **Logging standards** → `hooks/JOURNAL-SCHEMA.md` (JSONL contract) + 5 journaling hooks
- **Module boundaries** → `BOUNDARY.md` (auto-regen, CLAUDE.md:47-49) + `last_permission_review` cadence (audit.sh:1075-1103) + file-ownership table (BOUNDARY.md:289-321) — *social + audited*, not ArchUnit-typed

**Ambient affordances** (L488-498): kbg is *configuration* (YAML/Markdown/sh), not strongly-typed. The harnessability is **plugin-shape itself** — 14-event hook surface, 1536-char description budget (audit.sh:484-493), JSON manifest contracts. Strongly-typed affordance does not transfer.

## 4. Behaviour axis (L468-478)

- **Functional spec** → `skills/accept-task/SKILL.md` → `.scratch/<slug>/ACCEPTANCE.md`
- **Test suite** → `eval/run-eval.py` + 204 critical-hooks tests
- **Mutation testing** → **No kbg-harness counterpart found** — angle-3 §5: article's underspecified lever
- **Approved fixtures** → `eval/datasets/*.json` (kbg treats datasets as goldens)
- **Human review** → `/ship-task` Phase 5 acceptance gate + `kbg:review-pr`

**"Human clearly specified"** (L448) is the article's deepest honesty. kbg closes it via `accept-task` as **front-loaded spec capture** + `/ship-task` as grader. The 5-state `run-acceptance.py` exit is kbg's analog to "spec quality as a regulation axis."

## 5. Feedforward/Feedback × Computational/Inferential 2×2

|  | **Computational** | **Inferential** |
|---|---|---|
| **Feedforward** | PreToolUse gates (`block-dangerous-git.sh:86-89`, `block-bash-doctrine-write.sh`, `block-alias-shadowing.sh`, `secret-scan.sh`) — emit `permissionDecision: deny/ask` | Doctrine injection (`doctrine-bootstrap.sh:7-9`, `iron-rule-reminder.sh`, `orchestrator-nudge.sh`) |
| **Feedback** | `post-edit-audit.sh:1-2` · `security-diff-review.py:1-2` · `audit.sh` 38 checks · `test-critical-hooks.sh` 204 assertions | `verification-gate.sh:1-2` (SessionEnd, *advisory* — ADR 0002 §L115) · `fabrication-verdict-log.sh` (Stop) · `kbg:review-pr` |

All inferential-feedback sensors are **advisory by design** — `verification-gate.sh` "journals but NEVER emits a `permissionDecision`" (ADR 0002 §L115). Addresses critique-cost §3 (LLM-judge-circularity) at the cost of a thinner sensor stack.

## 6. Steering loop (L388-394)

- **Steering loop** = `kbg:recursive-improve` skill (6-step cycle, 5-iteration cap — ADR 0002:98-100). Human `AskUserQuestion` at Step 3 is load-bearing.
- **AI-in-the-loop dispatch** = `scripts/orchestrate-dispatch.py:1-60` (deterministic DAG resolver). **Does NOT spawn agents** (orchestrate-dispatch.py:38-46) — that would be a covert L4 loop (ADR 0002).

## 7. ADRs the article would prescribe (vs kbg's decisions)

1. **Single delivery = plugin (ADR 0001)** — forecloses template versioning (L521). Plugin cache is the *only* install path. *Article supports; kbg goes harder.*
2. **Autonomy invariant (ADR 0002)** — forecloses L3/L4 (critique-gaps §6). Explicit divergence, not absence.
3. **No `disallowedTools:` for agents** (`docs/agent-tool-patterns.md`) — kbg uses `tools:` allowlists. *Contradicts* critique-cost §5 ("harness work is removing affordances") — kbg chose *add structure*.
4. **F7 test-claim gate** (task-lifecycle.sh:166-231) — sensor for the behaviour axis's biggest gap. *Article silent; kbg defines the anti-pattern.*
5. **Bypass-audit-log on every PreToolUse** (hooks.json:64-73) — silent hook-bypass is journaled. *L342 misses the symmetric failure; kbg closes it.*

## 8. Concrete gaps (article prescribes, kbg missing)

1. **Mutation testing** — none in `eval/` (angle-3 §5: article's biggest underdefined lever). Would live in `eval/mutation/`, plug into `run-eval.py --gate`.
2. **Property-based / fuzz tests** — no Hypothesis/fast-check; would live in `eval/property/`.
3. **Sandbox** (critique-gaps §4) — no Firecracker/nsjail; F7 is the only behaviour-FB layer.
4. **Inferential structural tests** — no LLM-judge for "is this diff over-engineered?"; `kbg:review-pr` is a *task*, not a *sensor*. Would be `agents/over-engineering-judge` on SessionEnd.
5. **Sensor-fire notification** — audit.sh *reports* staleness (audit.sh:773-880) but no human is *notified*; a SessionStart/Slack hook would close L553.

## 9. Concrete over-engineering (critique-cost lens)

1. **The 38 hook scripts** — many narrow (e.g. `block-alias-shadowing.sh`); critique-cost §4 "build to delete" asks: do all 38 fire often enough to justify their file? kbg's defence: autonomy invariant requires self-diagnosing surface.
2. **`audit.sh`'s 38 sub-checks** — most CRIT by default; critique-cost §4 sensor-fatigue. kbg's defence: F1/F2 dual-pillar is the cheapest way to make the autonomy invariant machine-checkable.
3. **The per-skill strategy ladder in `run-eval.py:60-519`** — six strategies. The article would consolidate to one strategy + YAML schema. kbg's defence: each strategy exists because a real fixture demanded it (run-eval.py:436-461).
