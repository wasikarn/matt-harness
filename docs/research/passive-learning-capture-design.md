# Passive Learning-Capture — Maximal-Bounded design

> **Status:** PLAN (not built). Design only — no code, no version bump yet.
> **Date:** 2026-06-21 · **Decider:** Owner · **Operating point:** Maximal-bounded (locked).
> **Provenance:** 3 workflows this session (kbg-vs-ECC compare → 3-kernel → this 4-slice+skeptic
> design) + direct reads of ECC source. The skeptic's verdicts OVERRIDE the original slice
> proposals where they conflicted (sensor cell, queue location/format, scope key).

## 1. Goal & operating point

Owner goal: **"AI ทำงานเองได้มากสุด (คนถอยออกจากวง) + autonomous loop + เรียนรู้เองอัตโนมัติ."**

Of the three pillars, two already exist as **L3 (ADR 0003)** — human-launched bounded loop,
human steps out *within an approved run*, gate at push. This plan builds the third pillar —
**เรียนรู้เองอัตโนมัติ** — at the **maximal-bounded** operating point the owner chose:

- **CAPTURE is automatic** (passive, no operator action to observe).
- **APPLY stays human-gated** at exactly one boundary (kbg:learn `AskUserQuestion`, or an
  approved L3 `recursive-improve --auto` run that gates at push).
- **Confidence is an ordering signal ONLY — never a gate.** This is the single line that keeps
  it out of L4 / model-as-gate territory.

**Not in scope (would need ADR 0004):** no-human-gate apply (L4), self-launching cron/daemon,
auto-merge, auto-apply at a confidence threshold. These are ECC's machinery; we reject them.

## 2. What we studied in ECC (and the adopt/reject split)

ECC's autonomy is a **3-layer stack** (verified on the filesystem):

| Layer | ECC mechanic (file:line) | Decision |
|---|---|---|
| learning | `observe.sh` (PreToolUse+PostToolUse `*`) → self-bootstraps `nohup observer-loop.sh` daemon → headless `claude --model haiku --print` prompted *"Do NOT ask for permission… just write"* → confidence ≥0.7 = "Auto-approved" → `session-start.js:30` auto-injects ≥0.7 into every session | **adopt capture half, reject apply half** |
| loop | `loop-start.md` patterns `sequential\|continuous-pr\|rfc-dag\|infinite`; `loop-operator.md` monitor+escalate | **adopt escalation caps only** (Phase 2) |
| daemon | `ecc2/src/session/daemon.rs:20` heartbeat loop → `maybe_run_due_schedules` (cron) + `maybe_auto_merge_ready_worktrees` + auto-dispatch fleet | **reject whole layer** (L4) |

**The clean seam:** ECC's flywheel splits — capture (observe→queue) is computational + safe;
apply (confidence→auto-inject) is the model-as-gate we forbid. We lift the left half, replace
the gate with human-at-push.

Two **computational** gems worth lifting verbatim (Phase 2, into the L3 run):
- `session-guardian.sh` — 3-gate throttle (active-hours / project-cooldown / idle), cheapest-first, **fail-open**.
- `loop-operator` escalation set — no-progress×2 / retry-storm (same stack-trace) / cost-drift / merge-conflict.

## 3. The reconciled contract (skeptic fixes applied — read this before any code)

The 4 design agents disagreed on 3 things; the adversarial skeptic resolved them against the
filesystem. **These resolutions are binding:**

| # | Issue | RESOLUTION (binding) | Why |
|---|---|---|---|
| 1 | queue location | `~/.claude/projects/<git-toplevel-slug>/memory/_candidates/queue.jsonl` — **out of repo** | Slice-1's repo-relative path broke "never touches repo" + put the queue in the L3 cage's writable reach (`memory-lint.py:64` confirms the store is out-of-repo) |
| 2 | scope key | git-**toplevel-path-slug** (`/`→`-`), **not** git-remote-hash | kbg's actual convention (`find-transcript.sh:13`, `memory-lint.py:62`); ECC's remote-hash would make apply read the wrong dir → silent zero candidates |
| 3 | sensor 2×2 cell | **computational-FB** + audit #47 source-grep | mechanism is regex/heuristic (cost-capture precedent), NOT LLM. Mislabeling inferential-FB to back-door audit #34 corrupts the coverage grid. #47 greps the hook source directly = the real guard |
| 4 | storage format | **JSONL queue rows** (append/dedupe/cap/rotate); promotion builds the real `.md` | per-candidate `.md` files (Slice-2) over-engineer a staging queue; markdown-reuse only matters at promotion, which kbg:learn's writer does anyway |
| 5 | confidence | **omitted at capture**; computed at review time from `seen_count`+recency, used to ORDER the review list | keeps confidence provably non-gating (the ECC trap) |

**ADR call (skeptic, definitive):** **WITHIN ADR 0003 — no ADR 0004.** Capture-to-queue is the
same class as `verification-gate.sh` / `inferential-structural-judge` (SessionEnd advisory
sensors that journal without a gate). The irreversible boundary ADR 0003 protects (push /
promotion of a behavior change) stays human-gated. But it **does reverse a documented stance**
(`skills/learn/SKILL.md:20` + frontmatter:3 "no SessionEnd auto-mining") → an **append-only ADR
0003 addendum** is the honest minimum, plus rewriting both SKILL.md surfaces.

## 4. Components (Phase 1 — core capture + apply)

| File | Change |
|---|---|
| **NEW** `hooks/session/learn-capture.sh` | matcher-less SessionEnd advisory sensor. `set -uo pipefail`; `source ../_lib.sh`; `hook_init` bypass; **`[ "${KBG_LEARN_CAPTURE:-0}" = "1" ] \|\| exit 0`** (default-OFF opt-in); jq+python3 dep-guard → exit 0 if missing; read `.transcript_path`/`.session_id` (copy `ideate-budget-capture.sh:23-28`); resolve project root → path-slug; **transcript-size budget guard** (skip if >N bytes); embedded python3 single pass reusing `event_content/extract_text` walker → regex-harvest `correction` / `preference` / `repeated-workflow` (≥3×); secret-scrub each snippet; write rows to the out-of-repo `_candidates/queue.jsonl`; **no confidence field**; dedupe (session + vs queue) + cap (15/session, 200 queue, archive-rotate); `( journal_append learning_candidates {queued,kinds,queue_total,capped} ) \|\| true`; **never `hook_decision`; exit 0 always** |
| **NEW** `skills/learn/CANDIDATE-SCHEMA.md` | the single field-list both writer + reader cite: row shape (`ts,session_id,project_slug,kind,trigger,evidence,seen_count,first_seen,last_seen,scope,source,status`); the confidence **ordering** formula `clamp(0,1, 0.30 + 0.05*(seen_count-1, cap +0.50) − 0.02*weeks_since(last_seen))` with a boxed **NON-NEGOTIABLE: confidence orders the review list; no value ever triggers an action**; promotion = strip staging fields → real memory `.md` via kbg:learn's writer |
| **NEW** `scripts/read-candidates.sh` | shared top-level reader (avoids sync-seam #37-40): resolve project path-slug; print open rows as `confidence\|kind\|trigger` sorted desc; `--archive <key>` appends a disposed line; **exit 0 + silent when queue absent** (degrade gracefully — default-OFF) |
| **MOD** `skills/learn/SKILL.md` | add **Step 0**: if queue has open rows, read via `read-candidates.sh`, recompute+rank confidence, merge into the existing Step-3 filter + Step-4 `AskUserQuestion` gate; on dispose, `--archive` each (saved or rejected). **Reverse** the line-20 + frontmatter:3 "no auto-mining" stance → "capture passive + opt-in + journal-only; APPLY still gated here" |
| **MOD** `hooks/hooks.json` | register `learn-capture.sh` in the SessionEnd array (no matcher). 14 lifecycle events unchanged (registration under existing event) |
| **MOD** `hooks/sensors.json` | new sensor, **`fallback_role:"computational-FB"`**, `must_fire_in_session:false`, `enabled` per env. (NOT inferential-FB — see contract #3) |
| **MOD** `hooks/JOURNAL-SCHEMA.md` | document `learning_candidates` event (counts only, no secret-named fields per redactor rule) |
| **NEW** `skills/harness-audit/scripts/audit.sh` check **#47** | hermetic-on-presence (mirrors #43): (a) resolve capture hook by sensors.json name, CRIT if non-comment lines contain `permissionDecision\|hook_decision\|kbg_permission_decision`; (b) CRIT if capture hook OR `skills/learn/SKILL.md` contains a confidence-threshold gate `confidence *(>=|>|-ge|-gt) *0\.[0-9]` (anchor operator-then-decimal to avoid prose false-positives) |
| **NEW** `eval/regressions/passive-capture-advisory.json` | EVAL-1 sensor is computational-FB + present; EVAL-2 capture hook emits no permissionDecision; EVAL-3 confidence never appears in a gating comparison |
| **NEW** `docs/adr/0003-addendum-passive-capture.md` | append-only addendum: capture-to-queue is in ADR 0003's advisory-sensor envelope; records the kbg:learn reversal; APPLY ratchet untouched |
| **MOD** `.claude-plugin/plugin.json` + `marketplace.json` | version **0.3.6 → 0.3.7** (new counted component). Descriptions carry no raw script count — only "14 lifecycle events" (unchanged) |
| **MOD** `README.md` | re-derive via jq+audit (NOT `_provenance`): 46→47 scripts, 61→62 registrations, 36→37 sensors |
| **MOD** `tests/hooks/runners/test-critical-hooks.sh` | sub-suite: OFF→exit 0 + zero writes; ON+correction fixture→1 row in temp scoped dir; dedupe→once; cap→exactly 15; never permissionDecision; always exit 0 |
| **MOD** memory `ecc-everything-claude-code-mine-2026-06-20` | one line: kbg took the capture-half ECC's SKIP verdict left, so a future audit doesn't read the old SKIP as forbidding this |

## 5. Build order (skeptic — ONE version bump)

0. **Pin the contract** (location + scope-key + JSONL schema) — §3 above. Unblocks everything.
1. `CANDIDATE-SCHEMA.md` (the contract) + assign the SKILL.md reversal here (avoid 3-way edit conflict).
2. `learn-capture.sh` + governance fold-in (sensors.json, audit #47, ADR addendum, manifests, README) — **version bump happens here, once.**
3. `read-candidates.sh` + kbg:learn Step 0 + recursive-improve Observe read.
4. New-component F1 cache-transient: `--no-verify` commit+push → `claude plugin update` → restart.

## 6. Phase 2 — L3-guard additions (from the loop drill, optional-after-core)

Fold into `skills/recursive-improve/SKILL.md` `--auto` route (computational, within ADR 0003):

- **Runaway guard** ← `session-guardian.sh` pattern: active-hours window (overnight-aware) +
  per-run cooldown + idle detection, cheapest-first, **fail-open**. Gates whether an `--auto`
  iteration proceeds.
- **Escalation caps** ← `loop-operator` set: stop the run on no-progress×2 checkpoints /
  retry-storm (repeated identical stack-trace) / cost-drift past budget / merge-conflict.
  ADR 0003 mentions caps but doesn't enumerate them — this is the proven set.

Route B invariant: `--auto` Observe **reads** the queue, **never writes** it; disposal recorded
in the cycle journal; apply still gated at push (L3 Gate-2). The out-of-repo queue location
(contract #1) is what makes this cage-safe.

## 7. Rejected / dropped (record, don't re-propose)

- **`metadata.candidate` lint-exclusion edit to `memory-lint.py:79`** — no-op: `os.listdir` is
  flat, never recurses, so a `_candidates/` subdir is already invisible. Drop the edit.
- **inferential-FB sensor classification** (Slice-4) — mislabel to back-door audit #34; corrupts
  the coverage grid. Use computational-FB + audit #47.
- **git-remote-hash scope key** (ECC idea) — diverges from kbg's path-slug → silent failure.
- **PostToolUse trigger** — ECC-style per-call fire only earns its keep feeding a self-launched
  daemon (forbidden). SessionEnd single-pass is enough.
- **ECC apply half entirely** — observer daemon, headless "do not ask permission" writes,
  ≥0.7 auto-inject, auto-promote, `/evolve` self-writing files, ecc2 cron + auto-merge. All L4 /
  model-as-gate → ADR 0004 territory, out of scope.

## 8. Verification

- `scripts/run-gauntlet.sh` 4/4 (plugin-validate + audit 0C/0W incl. new #47 + critical-hooks incl. new sub-suite + eval gate incl. new fixture).
- Manual: `KBG_LEARN_CAPTURE=1`, run a session with a "no, use X not Y" correction → one row in the out-of-repo queue → `kbg:learn` surfaces it in the `AskUserQuestion` gate → approve → real memory `.md` written, row archived.
- Confirm: queue file never appears in `git status` (out of repo); capture never blocks; confidence never gates.

## 9. Remaining open decisions (small)

1. **Reject disposition** — archive `status:rejected` (re-openable) vs hard-drain. *Rec: archive (re-openable, never `rm`; matches use-trash preference).*
2. **Phase 2 timing** — bundle L3-guards with Phase 1, or ship core capture first then guards. *Rec: core first (Slices 1-3), guards as a follow-up — smaller blast radius per ship.*
3. **Build now vs hold** — this doc is plan-only; building touches doctrine (ADR addendum + kbg:learn reversal + counted component). Needs explicit go.
