# Nine-agent gate/architecture/security audit (2026-09-20)

**Trigger:** starting from `kyrox-hanako-loops-graphs-post-audit-2026-09-20.md`'s verified finding
that this repo's "Graph — thin" gap (from `loop-graph-engineering-trend-audit-2026-08-02.md`) has
no real Anthropic-authority citation, the operator asked for a deeper drill-down and then a
5-agent (later expanded to 9-agent) audit of `matt-harness` itself for concrete improvement
points. All 9 agents ran read-only (Read/Grep/Glob/Bash only); several empirically verified
findings by running real payloads against the live gate scripts rather than reasoning from the
code alone. No files were edited by any agent.

**Ground truth check, run directly (not by an agent):** `bash skills/meta/harness-audit/scripts/audit.sh`
→ 0 CRIT, 0 WARN, 4 INFO. `bash scripts/run-gauntlet.sh` → PASS on validate, lint, and tests.
**Every finding below is invisible to this repo's own pre-commit validation.** That is itself the
top-line finding: the gates that are supposed to make this harness's safety guarantees mechanical
have live, low-effort bypasses that nothing in the repo's automated checks catches.

## Agents run

| # | Agent | Scope | Verdict |
|---|---|---|---|
| 1 | `mh:code-architect` | Rule 13 flow-control gap | Verdict shape + round cap are prompt-only, not code-enforced |
| 2 | `mh:blind-spot-hunter` | Validator-independence enforcement | 7 findings, 1 HIGH |
| 3 | `mh:silent-failure-hunter` | `hooks/gates/*.py` silent-pass bugs | 2 HIGH, 3 MEDIUM, 1 LOW |
| 4 | `mh:test-gap-analyzer` | Loop-cap & verdict-shape test coverage | 3 confirmed gaps |
| 5 | `mh:performance-optimizer` | Loop cost/round ceilings | Skills are capped; operator-level re-review loop isn't |
| 6 | general-purpose (security mindset) | Adversarial security review of gates | 5 HIGH/MEDIUM, empirically confirmed |
| 7 | `mh:backend-architect` | Gate architecture consistency | Live-confirmed bypass + no shared payload lib |
| 8 | `mh:silent-failure-hunter` (2nd pass) | `scripts/_lib/*`, `skills/**/scripts/*.py` | 1 HIGH (`rank.py`), 3 MEDIUM |
| 9 | `mh:code-architect` (2nd pass) | `agents/*.md` consistency | Description/body contradiction, duplicate "the one" claim |

---

## CRITICAL — live, low-effort bypasses of the core safety gates

These undermine `docs/reference/operating-model.md`'s central claim ("deny the irrecoverable set
computationally... the only place a rule is a guarantee instead of a hope"). All were run against
the actual files and confirmed to execute the denied action.

1. **`hooks/gates/irrecoverable.py:170-174` — nested-Claude-spawn block bypassed by a plain prefix
   wrapper.** `claude -p "..."` is denied; `env claude -p "..."`, `command claude -p "..."`,
   `sudo claude -p "..."`, and a bare `\claude -p "..."` are all **allowed**, confirmed live. The
   file already has a `PREFIX_WRAPPERS` unwrap for `rm`/`git` a few dozen lines below — it's just
   never applied to this check. Worst finding in the set: this is the hard maker≠checker
   architectural boundary, not a courtesy gate.
2. **`hooks/gates/subagent-git-guard.py:92-96` — the same prefix-wrapper gap** on the
   subagent git-stash/reset/clean gate (issue #135's protection). `env git reset`,
   `command git reset`, `nice git reset`, `\git reset` all bypass it, confirmed live.
3. **`hooks/gates/irrecoverable.py` — git flag-abbreviation bypass.** Exact-string checks miss
   git's own option-abbreviation feature. Confirmed live to actually execute:
   `--no-veri` (skips hooks), `--ha` (hard reset), `--amen` (rewrites history), `--for` (force
   clean), `branch --forc` (force-deletes an unmerged branch), `--discard-ch`. `--push --forc` is
   *not* exploitable (git itself rejects it as ambiguous with `--force-with-lease`).
4. **`hooks/gates/irrecoverable.py:736-739` — `-c core.hookspath=` (lowercase) bypasses the
   hooksPath-edit block.** Git config keys are case-insensitive; this branch does an exact-case
   `startswith`, while the sibling `config` subcommand branch correctly lowercases. Confirmed
   end-to-end with a planted marker-writing hook that the lowercase key really redirects git's
   hook execution.
5. **`hooks/gates/test-integrity.py:161` — the "redefining `check()` is a closed gap" protection
   is itself defeatable two ways**, both confirmed against the real script: (a) append a second
   `check() { :; }` after the real one — bash runtime uses the later definition, the regex only
   sees the first, so a weakened check is invisible; (b) a decoy nested `{ ... }` brace inside
   `check()`'s body truncates the diff's capture early, hiding a real weakening placed after it.
6. **`hooks/gates/subagent-git-guard.py:34-35` — `if not agent_id` truthiness check.** An
   empty-string or null `agent_id` (key present, value falsy) is treated as "not a subagent" and
   the gate exits allow. This is the *exact* bug class fixed in two sibling gates
   (`subagent-spawn-guard.py:38`, GH #154; `task-complete-separation.py:57`, GH #155) with an
   explicit "presence, not truthiness" fix — `subagent-git-guard.py` predates both fixes and was
   never swept along. **Confirmed to span 4 sites across 2 files, not 3/1**: `irrecoverable.py:248`
   and `:567`'s nested-spawn checks use the identical `if d.get("agent_id") and ...` pattern.
7. **`hooks/gates/test-integrity.py:213-214` — inner `except Exception: sys.exit(0)`** silently
   allows when the old side of an edit can't be read (permission error, TOCTOU race, directory),
   directly contradicting the same file's outer handler seven lines later, which fails toward
   asking on the identical class of problem ("cannot classify this edit... approve manually or
   deny"). A `Write` that guts a test's assertions goes through with zero signal in this path.
8. **`hooks/gates/subagent-git-guard.sh:19-21` — unicode-escape bypass at the shell fast-path
   layer.** `subagent-spawn-guard.sh` removed this exact raw-substring `case` match (a
   `agent_id`-escaped key is valid JSON, decodes to the same key, but isn't in the raw text)
   citing GH #154; `subagent-git-guard.sh` still has it. Live-confirmed: an escaped-key payload is
   **allowed** (rc=0) by `subagent-git-guard.sh` and correctly **denied** (rc=2) by
   `subagent-spawn-guard.sh` for the equivalent payload.

**MEDIUM, same family:**
- `git add -Av`/`-vA` (bundled flags), `--al` (abbreviation), `./`, `:/` all bypass the
  staging-everything check (`irrecoverable.py:844`) that only matches `-A`/`--all`/`.` exactly.
  Lower severity — staging is reversible via `git reset`.
- `test-integrity.py`'s `PATH_RE` runs on the literal payload path with no symlink/realpath
  resolution — editing a tracked test through a differently-named symlink skips the gate entirely.
- `irrecoverable.py`'s `_mid_merge()` trusts a forgeable on-disk file
  (`git rev-parse HEAD > .git/MERGE_HEAD` fools it into unlocking `git add -A`).

---

## HIGH — process/architecture gaps (not exploits, but the doctrine doesn't hold)

9. **Rule 13's validator contract has no evidence field, and its own wording forbids adding
   one.** `docs/reference/spawn-brief.md:28` requires the verdict shape "and nothing else," while
   `docs/METHODOLOGY.md:28` requires "one checkable fact" — the return shape has no field to carry
   it. A vacuous pass (`{"pass":true,"findings":[],"scope_ok":true,"unexpected_files":[]}`) and a
   real one are byte-identical. Three sibling skills (`deep-audit`, `idea-audit`,
   `compliance-audit`) already closed this exact gap with a `checked[]`/`requirements` field after
   a live 2026-09-19 incident — the generic contract every *other* Rule 13 dispatch uses was never
   updated. **Live-verified**: `deep-audit`'s own `check-verdict.py` accepts a `checked[]` entry
   with empty-string claim/evidence; the sibling `idea-audit` script rejects the identical payload.
10. **`hooks/gates/` has no shared payload/identity library.** "Is this a subagent" is an
    unwritten contract carried only in 4 separate header comments. This is *why* the agent_id fix
    (finding 6) landed incompletely twice — two independent fix rounds (#154, #155) each patched
    one gate and missed the others, and nothing forces the next one to check. Recommended: a
    ~20-line `hooks/gates/_payload.py` with `load_payload()`/`is_subagent()`/`agent_label()`,
    parsing/identity only — never the verdict or fail-direction, so it doesn't fight
    `operating-model.md`'s explicit "don't homogenize gate behavior" line. First adopters:
    `irrecoverable.py` and `subagent-git-guard.py` (both have live bugs).
11. **`requirement-analyst.md` has the identical "no schema, no validating script" gap that
    `plan-reviewer.md` has — and both files' own text falsely claims to be "the one" such surface**
    (`plan-verdict-check.py:4-5` and `plan-reviewer.md:252-253` both say this, verbatim). A
    dispatcher who reads either line concludes the rest of the fleet is covered.
    `requirement-analyst`'s verdict gates whether implementation work starts at all — higher
    consequence than a plan review.
12. **`skills/workflow/ideate/scripts/rank.py` has no input validation**, despite its own
    docstring claiming to mirror `weighted-score.py`'s contract — which *was* hardened (explicit
    bool/NaN/Infinity rejection) while `rank.py` wasn't. A malformed or bool-typed score from the
    model silently corrupts the idea shortlist ordering with zero error.
13. **`performance-optimizer.md`'s frontmatter description contradicts its own body** about when
    to route to it ("not for speculative tuning" vs. "audit performance with no repro → here").
    This is the one agent in the 10-agent fleet holding `Write`/`Edit` (deliberate, documented),
    so a mis-route has write consequences, and it has zero eval coverage — the only agent with none.
14. **`subagent-git-guard.py:135` and 3 gates' wrappers lack `irrecoverable.sh`'s exit-code
    normalization.** Confirmed against `code.claude.com/docs/en/hooks.md`: "a hook that exits with
    a code other than 0 or 2 and prints no JSON decision doesn't block." An uncaught crash in these
    3 gates' post-parse logic (any bug, not just the ones found here) silently allows the guarded
    action instead of failing closed.

---

## MEDIUM

15. `config-write-guard.py` / `codex-setup-guard.py` — documented fail-open on crash, but zero
    diagnostic (no stderr, no journal entry), unlike every sibling gate's parse-guard.
16. Rule 13's "stop after 3 rounds" is purely instructional — zero code counts fix-loop rounds.
    The one file that name-drops the doctrine (`hooks/sensors/failure-diagnose-nudge.py`) actually
    caps at 1, not 3 — a stale docstring from v1.1.55's own cap change.
17. `plan-reviewer.md`'s YAML→JSON verdict hand-translation is untested; `fragments_lock_acquire`'s
    5-attempt retry and its documented lock-contention fallback are both untested (no test forces
    either branch).
18. The operator-level "re-run deep-audit after every fix round" pattern (12 confirmed instances in
    memory) has no round/time/$ cap — it relies entirely on `advisor()`'s judgment call. Verified
    against `code.claude.com/docs/en/advisor.md`: advisor timing is explicitly "model-driven rather
    than rule-based," so this is not a guaranteed check.
19. `idea-audit`'s attacker is instructed to skip claims Agent A tagged "observed directly"
    (self-graded exemption at claim granularity) and owes only one `checked[]` receipt for an
    entire pasted report (coverage gap, not just an exemption gap).
20. Fleet ships 3 incompatible clean-verdict vocabularies across 10 agents (`CLEAN`/`COVERED`/
    `SOUND` bare tokens, 4-value YAML `verdict:`, and a JSON object with no verdict field at all) —
    `agent-authoring-conventions.md` §8 asks for one fixed set; nothing enforces convergence.
21. `silent-failure-hunter`'s real concurrency/race-condition coverage (a full numbered hunt
    target in its body) is invisible in its own frontmatter description — 4 of the 10 agents touch
    concurrency in their bodies, 0 advertise it, so an orchestrator asking for a "race condition
    review" won't route to any of them.
22. `memory-lint.py` — 2 silent `except OSError: pass`/`continue` on secondary-artifact writes
    (supersedes-note, wikilink rewrite); the main pointer-collapse action reports success
    regardless of whether the secondary write landed.
23. `model-bench-diff.py` — `.get(key, 0.0)` on fields the module's own docstring calls "always
    present" masks "field missing / corrupted result file" as "score is exactly zero," which could
    silently steer a model-selection decision.
24. Dormant: a `context: fork` skill could let a subagent bypass the `Agent`-tool spawn-guard
    entirely (the spawn-guard matcher only watches the `Agent` tool, not `Skill`). No skill in this
    repo or any installed plugin currently sets `context: fork`, but `harness-audit` check
    54:45-46 recommends the field as the sanctioned way to pin a model — the path is unused, not
    closed.
25. Two lenses missing across the whole 10-agent review fleet: dependency/supply-chain review, and
    documentation-accuracy-vs-code review — the latter is, concretely, the exact class of defect
    findings 11 and 13 in this report are, found by hand because no agent owns it.
26. `harness-audit` check 32 (the Write/Edit-grant invariant on review agents) keys on the agent's
    **filename** substring (`*reviewer*|*analyzer*|...`), not the declared `bucket:` frontmatter
    field. Latent: a future `bucket: review` agent named e.g. `dependency-scanner` or
    `race-detector` would carry a `Write` grant past this check with a clean audit.

---

## LOW

27. Diagnostic/logging format drift across gates (`—` vs `--`, hardcoded vs. dynamic `tool_name`
    in journal entries) — cosmetic, no behavioral effect.
28. `docs/METHODOLOGY.md` currently has no "Rule 2," though numerous `docs/research/*.md` files
    still cite it as the YAGNI/no-speculative-build rule — drift between doctrine and its own
    historical citations.
29. `deep-audit`'s step-5 re-validator brief doesn't inherit step-3's "withhold the maker's own
    reasoning" rule, and has no `checked[]` field to withhold into (same root cause as finding 9).
30. Nothing mechanically requires that a validator ran at all before a task is marked complete —
    acknowledged directly in `operating-model.md:21` ("everything not in that [gate] table is
    advice") and not proposed as a fix here, since the cheap version (session-scoped round
    tracking) is the exact shape of change already rejected twice (#135, #137 — see design note
    below).

---

## Design note: "auto-apply the attacker/adversarial pattern via hooks?"

Raised mid-session by the operator. Full reasoning:

- **Hooks cannot call tools** for `command`/`http`/`prompt` hook types (confirmed against
  `code.claude.com/docs/en/hooks-guide.md`'s Limitations section) — but a `type: agent` hook is a
  real subagent dispatch, and `SubagentStop` hooks *can* block (`decision: "block"` sends the
  subagent back to redo its own output). This corrects an assumption `mh:code-architect`'s finding
  1 made, sourced from a stale in-repo research doc claiming SubagentStop is observation-only.
- **Tier 1 (recommended, ship it): a deterministic verdict-shape gate.** A `command` hook on
  `SubagentStop`/`PostToolUse(Agent)` that parses the returned verdict JSON and rejects a vacuous
  or self-contradictory one (closes finding 9), `decision: block`-ing the same subagent to redo it.
  Stateless — no cross-call bookkeeping, so it doesn't hit the #135/#137 objection. Mirrors the
  `check-verdict.py` pattern that already exists, just invoked automatically instead of by prose
  convention.
- **Tier 2 (real, but a genuine tradeoff — needs an explicit decision, not a default-on ship): a
  `type: agent` hook on `PostToolUse(Agent)` that dispatches an actual attacker/validator agent.**
  It receives only `tool_input`+`tool_response`, not the parent transcript, which naturally
  satisfies the CoVe withholding rule. But: sync blocking taxes every single Agent dispatch with
  attacker latency (a real attacker pass took 16+ minutes in this session; the default agent-hook
  timeout is 60s); async can't block, so it degrades to a nudge-with-evidence; there is no
  trustworthy signal to discriminate "this dispatch needs adversarial follow-up" from noise
  (Explore lookups, the review agents' own dispatches); and an always-on auto-spawn is in real
  tension with `operating-model.md`'s explicit "no autonomous loop: the model never starts work on
  its own" line — worth flagging squarely rather than arguing around.
- **Tier 3 (declined): an ask-gate on task-completion keyed off `git diff` shape.** Weaker
  guarantee than Tier 1 (a human can click through), and "2+ files since when" has no clean
  baseline in a repo that commits mid-wave.
- **Off the table**: session-scoped round counters (the exact shape #135/#137 already rejected),
  and a Stop-hook that autonomously spawns a full attacker wave (flatly violates "no autonomous
  loop").

---

## Recommended next step

Findings 1-8 (CRITICAL) are live bypasses of gates whose entire purpose is to make specific
actions *impossible*, not merely discouraged — and per the ground-truth check at the top, none of
them are caught by this repo's own `harness-audit` or `gauntlet`. Most have small, mechanical
fixes (apply the existing `PREFIX_WRAPPERS` unwrap that already exists in `irrecoverable.py` to
the two checks that skip it; presence-check `agent_id` at the 2 remaining sites the same way
GH #154/#155 already did; lowercase the `hookspath=` compare). Two (flag-abbreviation matching,
`test-integrity.py`'s regex-based `check()` diff) need more careful rework, not a one-liner.

This report is a record, not a fix — nothing above has been changed. Recommend fixing 1-8 next,
scoped narrowly to the gate files named, before triaging the architecture-level findings (9-14).
