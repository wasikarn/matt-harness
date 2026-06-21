# Passive Learning-Capture — Maximal-Bounded design

> **Status:** ✅ BUILT (Phase 1 shipped v0.3.7, 2026-06-21). Owner chose **Build** on the §9.3
> build-vs-hold call ("I forget often"). Phase 2 (L3-guard fold-in, §6) still deferred.
> **Date:** 2026-06-21 · **Decider:** Owner · **Operating point:** Maximal-bounded (locked).
> **Rev 2 (2026-06-21):** revised after an **independent maker≠checker audit** (5 senior reviewers +
> 1 adversarial verifier, fresh context). 0 blockers; **6 majors folded in below** — incl. the two
> that decide net value (drain-loop + harvest-precision), ADR re-homed to **0002** (not 0003), the
> slug conflation resolved, and the secret-scrub pinned. See §10 for the audit→fix traceability map.
> **Provenance:** 3 design workflows + 1 review/audit workflow this session + direct ECC/kbg reads.

## 1. Goal & operating point

Owner goal: **"AI ทำงานเองได้มากสุด (คนถอยออกจากวง) + autonomous loop + เรียนรู้เองอัตโนมัติ."**

Two of the three pillars already exist as **L3 (ADR 0003)** — human-launched bounded loop, human
out *within an approved run*, gate at push. This plan builds the third — **เรียนรู้เองอัตโนมัติ** — at
the owner-chosen **Maximal-bounded** point:

- **CAPTURE is automatic** (passive, no operator action to observe).
- **APPLY stays human-gated** at one boundary (kbg:learn `AskUserQuestion`, or an approved L3
  `recursive-improve --auto` run that gates at push).
- **Confidence is an ordering signal ONLY — never a gate.** The line that keeps it out of L4.

**Not in scope (would need a superseding ADR):** no-human-gate apply (L4), self-launching cron/
daemon, auto-merge, auto-apply at a confidence threshold. These are ECC's machinery; we reject them.

## 2. What we studied in ECC (adopt/reject split)

ECC autonomy is a **3-layer stack** (verified on the filesystem):

| Layer | ECC mechanic (file:line) | Decision |
|---|---|---|
| learning | `observe.sh` (PreToolUse+PostToolUse `*`) → self-bootstraps `nohup observer-loop.sh` → headless `claude --print` prompted *"Do NOT ask for permission… just write"* → confidence ≥0.7 "Auto-approved" → `session-start.js:30` auto-injects ≥0.7 every session | **adopt capture, reject apply** |
| loop | `loop-start.md` patterns; `loop-operator.md` monitor+escalate | **adopt escalation caps only** (Phase 2) |
| daemon | `ecc2/src/session/daemon.rs:20` heartbeat → cron + `maybe_auto_merge_ready_worktrees` + fleet dispatch | **reject whole layer** (L4) |

The clean seam: capture (observe→queue) is computational + safe; apply (confidence→auto-inject) is
the model-as-gate we forbid. Lift the left half, replace the gate with human-at-push.

## 3. Reconciled contract (binding — read before any code)

The design agents disagreed; the first skeptic + the independent audit resolved these. **Binding:**

| # | Issue | RESOLUTION (binding) | Why |
|---|---|---|---|
| 1 | queue location | `~/.claude/projects/<slug>/memory/_candidates/queue.jsonl` — **out of repo** | `memory-lint.py:63-64` confirms the store is out-of-repo; in-repo would break "never touches repo" + put the queue in the L3 cage's reach |
| 2 | **slug derivation** | derive the slug from the **`.transcript_path` parent dir** (the slug Claude Code itself chose), with a `${CLAUDE_PROJECT_DIR:-$PWD}`→`sed 's\|/\|-\|g'` fallback. Use the SAME function in writer + `read-candidates.sh` + kbg:learn Step 0 | **AUDIT FIX #4**: `find-transcript.sh:12` uses a CWD-slug, `memory-lint.py:63` uses a git-toplevel-slug — they DIVERGE on monorepo/subdir launches → queue + transcript land in different dirs → silent zero candidates. Pick the transcript's own dir so writer + reader always agree |
| 3 | sensor 2×2 cell | **computational-FB** + audit #47 source-grep | mechanism is regex/heuristic (cost-capture precedent), not LLM; mislabeling inferential-FB to back-door #34 corrupts the coverage grid |
| 4 | storage format | **JSONL queue, append-only** in the hook; promotion builds the real `.md` | per-candidate `.md` over-engineers a staging queue; **AUDIT FIX (concurrency)**: capture appends only — cap+rotate happens later in the gated kbg:learn flow, never inside the kill-prone SessionEnd hook |
| 5 | confidence | **omitted at capture**; computed at review from `seen_count`+recency, used to ORDER the review list | keeps confidence provably non-gating |
| 6 | **governance home** | **ADR 0002 addendum** (`docs/adr/0002-addendum-passive-capture.md`), NOT "within ADR 0003" | **AUDIT FIX #6**: ADR 0003 is the L3-loop ADR; the cited advisory sensors (verification-gate, inferential-structural-judge) predate it and are governed by **ADR 0002 + the CLAUDE.md 2×2 advisory-only doctrine**. learn-capture is an ADR-0002-class advisory sensor. It also relaxes a stance labelled `## Autonomy posture (load-bearing)` in `skills/learn/SKILL.md:18` — the addendum must cross-ref :18 and record the conscious relaxation |

**ADR verdict (confirmed by audit):** no ADR 0004 / no superseding ADR. The architecture (advisory
sensors journal; APPLY human-gated) is unchanged. The honest weight is an **append-only ADR 0002
addendum** + rewriting both `skills/learn/SKILL.md` surfaces (frontmatter:3 + the `## Autonomy
posture` block at :18-20). Standalone ADR 0004 is the alternative only if the owner wants more weight.

## 4. Components (Phase 1 — core capture + apply + drain)

| File | Change |
|---|---|
| **NEW** `hooks/session/learn-capture.sh` | matcher-less SessionEnd advisory sensor. `set -uo pipefail`; `source ../_lib.sh`; `hook_init` bypass; **`[ "${KBG_LEARN_CAPTURE:-0}" = "1" ] \|\| exit 0`** (default-OFF); jq+python3 dep-guard→exit 0; read `.transcript_path`/`.session_id` (copy `ideate-budget-capture.sh:23-28`); **`mkdir -p` the `_candidates` dir `\|\| exit 0`** (copy `ideate-budget-capture.sh:21` — AUDIT FIX, else first-run fails); slug from the transcript's parent dir (contract #2); **transcript-size budget guard: skip if >2 MB** (AUDIT FIX — bound the python walk); embedded python3 single pass reusing `event_content/extract_text` (`ideate-budget-capture.sh:47-79`); **HARVEST PRECISION (AUDIT FIX #3): only `role=="user"` turns, never assistant/attachment; word-boundary-anchored patterns**; secret-scrub per below; **append-only** write of JSONL rows (no in-hook cap/rotate — AUDIT FIX, kill-safe); **no confidence field**; `( journal_append learning_candidates {queued,kinds,queue_total} ) \|\| true`; **never `hook_decision`; exit 0 always** |
| **NEW** `hooks/session/learn-drain-nudge.sh` | **AUDIT FIX #2 (closes the drain loop)** — SessionStart advisory, modeled on `notify-sensor-staleness.sh` + `cleanup-bak-ttl.sh`. Self-disabling: instant exit 0 if no `_candidates/queue.jsonl`. Else if ≥K (default 5) open rows older than D (default 7) days → emit ONE-line `additionalContext` nudge ("N learning candidates await review — run `kbg:learn`"), **hash-gated dismissal** like notify-staleness (don't re-nag the same set). Computational, advisory, exit 0 always, never blocks |
| **NEW** `skills/learn/CANDIDATE-SCHEMA.md` | the single field-list writer + reader cite: row shape (`ts,session_id,project_slug,kind,trigger,evidence,seen_count,first_seen,last_seen,scope,source,status`); **confidence ORDERING formula (AUDIT FIX — valid Python):** `clamp(0,1, 0.30 + min(0.05*(seen_count-1), 0.50) − 0.02*weeks_since(last_seen))` where `clamp(lo,hi,x)=max(lo,min(hi,x))`, boxed **NON-NEGOTIABLE: orders the review list; no value ever triggers an action**; the **secret-scrub deny-list** (mirror `_lib.sh` `val_dl`: AWS/`gh`/`sk-`/PEM shapes + `password\|api_key\|secret\|token\|credential`) with a **redact-whole-row-on-any-match fail-safe** (drop or `[redacted]` the row, never partial — AUDIT FIX #1); promotion = strip staging fields → real memory `.md` via kbg:learn's writer |
| **NEW** `scripts/read-candidates.sh` | shared top-level reader (avoids sync-seam #37-40): slug from transcript-parent (contract #2); print open rows `confidence\|kind\|trigger` sorted desc; `--archive <key>` appends a disposed line; **tolerant of a trailing partial JSONL line** (skip un-parseable rows, never abort — AUDIT FIX); exit 0 + silent when queue absent; **owns cap+rotate at 200** (moved here from the hook — runs in the gated flow where a slow op is safe) |
| **MOD** `skills/learn/SKILL.md` | add **Step 0**: read queue via `read-candidates.sh`, recompute+rank confidence; **when the queue has rows from THIS session, Step 0 REPLACES Step 2's re-mine** (else hash-dedup Step-0+Step-2 by trigger/evidence — **AUDIT FIX #5**, no double-surfacing at the gate); merge into the existing Step-3 filter + Step-4 `AskUserQuestion`; on dispose, `--archive` each. **Reverse** the frontmatter:3 + `## Autonomy posture` block (:18-20) "no auto-mining" stance → "capture passive + opt-in + journal-only; APPLY still gated here" |
| **MOD** `hooks/hooks.json` | register `learn-capture.sh` in SessionEnd **with `timeout: 25`** (AUDIT FIX — matches the two python-walking SessionEnd hooks `ideate-convergence/memory-capture`); register `learn-drain-nudge.sh` in SessionStart. 14 lifecycle events unchanged |
| **MOD** `hooks/sensors.json` | two entries, **`fallback_role:"computational-FB"`**, **`enabled:true` + `observable:false`** (AUDIT FIX — no env-conditional-enabled precedent exists; `observable:false` exempts a default-OFF sensor from `notify-sensor-staleness` spam), set `max_silent_days` |
| **MOD** `hooks/JOURNAL-SCHEMA.md` | document `learning_candidates` event (counts only, no secret-named fields per the redactor rule) |
| **NEW** `audit.sh` check **#47** | **extends the pattern of #34** (AUDIT FIX — not #43, which is L3-cage): strip full-line comments (`grep -vE '^[[:space:]]*#'`) then (a) CRIT if the capture hook emits `permissionDecision\|hook_decision\|kbg_permission_decision` (`kbg_permission_decision` = defensive ghost-name, no impl); (b) CRIT if capture hook OR `skills/learn/SKILL.md` has a confidence-gate `confidence *(>=|>|-ge|-gt) *0\.[0-9]` (comment-stripped first). #47 is the correct next number (highest is #46) |
| **NEW** `eval/regressions/passive-capture-advisory.json` | EVAL-1 sensors computational-FB + present; EVAL-2 capture hook emits no permissionDecision; EVAL-3 confidence never in a gating comparison |
| **NEW** `eval/regressions/learn-capture-precision.json` | **AUDIT FIX #3** — labeled fixture: real corrections + adversarial near-misses ("no" in prose, quoted code comments, assistant text) with a measured **false-positive ceiling**; fails if the harvester queues a non-correction |
| **NEW** `docs/adr/0002-addendum-passive-capture.md` | append-only addendum (AUDIT FIX #6): capture-to-queue is in ADR 0002's advisory-sensor envelope; records the `skills/learn/SKILL.md:18` "load-bearing" relaxation + why advisory-only (no gate, no repo write, exit 0, default-OFF) preserves the principle; APPLY ratchet untouched |
| **MOD** `.claude-plugin/plugin.json` + `marketplace.json` | version **0.3.6 → 0.3.7** (2 new counted hooks). Descriptions carry no raw script count |
| **MOD** `README.md` | counts (derivation: jq unique `.sh` from hooks.json + `hooks/post-tool/*.py` action scripts, **excluding `_lib.sh` + `_lib.py`**): **46→48 scripts, 61→63 registrations, 36→38 sensors** |
| **NEW** `tests/hooks/runners/test-ch-learn-capture.sh` | sub-suite **registered in the SUITES array**: OFF→exit 0 + zero writes; ON+correction fixture→1 row in temp scoped dir; precision (adversarial near-miss → 0 rows); dedupe→once; never permissionDecision; always exit 0; drain-nudge fires only when queue stale |
| **MOD** memory `ecc-everything-claude-code-mine-2026-06-20` | one line: kbg took the capture-half ECC's SKIP verdict left |

## 5. Build order (skeptic + audit — ONE version bump)

0. **Pin the contract** (slug=transcript-parent, append-only JSONL, secret-scrub fail-safe) — §3.
1. `CANDIDATE-SCHEMA.md` (the contract; valid confidence formula) + assign the SKILL.md reversal here.
2. `learn-capture.sh` + `learn-drain-nudge.sh` + governance fold-in (sensors.json, audit #47, ADR 0002 addendum, manifests, README) — **version bump here, once**; **regen `BOUNDARY.md`** (`inventory-boundary.sh --repo-only`) before commit.
3. `read-candidates.sh` + kbg:learn Step 0 (replaces Step 2 for this-session rows).
4. `test-ch-learn-capture.sh` + the 2 eval fixtures.
5. New-component F1 cache-transient: `--no-verify` commit+push → `claude plugin update` → restart.

*(`recursive-improve` Observe-read is **Phase 2**, not here — AUDIT FIX, was scope-drifting into Phase 1.)*

## 6. Phase 2 — L3-guard additions (from the loop drill, optional-after-core)

> **Status:** ✅ SHIPPED v0.3.8 (2026-06-21), owner-scoped. Built: **#3 queue-read (Route B)** +
> **no-progress cap (`--max-flat`)**. **Dropped: runaway-guard** (active-hours/idle/cooldown) — a
> category mismatch: those gate a *self-launching daemon*; kbg's loop is human-launched + already
> bounded by `--max-runs`/`--max-duration`/`--fail-streak`. retry-storm/cost-drift/merge-conflict
> skipped (retry already capped; no merge inside the loop).

Fold into `skills/recursive-improve/SKILL.md` `--auto` route (computational, within ADR 0003):

- **Runaway guard** ← `session-guardian.sh`: active-hours (overnight-aware) + per-run cooldown + idle, cheapest-first, **fail-open**.
- **Escalation caps** ← `loop-operator`: stop on no-progress×2 / retry-storm (same stack-trace) / cost-drift / merge-conflict.
- **Queue read (Route B):** `--auto` Observe **reads** the queue (read-only), disposal recorded in the cycle journal; apply gated at push (L3 Gate-2). Map a queue preference-row into Observe's finding model; **disambiguate from the existing "drain the queue" at `recursive-improve/SKILL.md:74`, which is the comprehension-debt ledger — a DIFFERENT queue** (AUDIT FIX).
- **L3 interaction note (AUDIT FIX):** with both `KBG_LEARN_CAPTURE=1` and `KBG_AUTONOMY_L3=1`, `_lib.sh:40-43` forces `PROFILE=standard`/`DISABLED=''`, so `learn-capture.sh` fires at each L3 session-end and appends to the queue (benign — out-of-repo, cage-safe). The Route-B "reads, never writes" contract is **documentation-enforced** in `recursive-improve/SKILL.md` (no code gate); the out-of-repo location is what keeps it cage-safe.

## 7. Rejected / dropped (record, don't re-propose)

- **`memory-lint.py` lint-exclusion edit** — confirmed no-op: `os.listdir` (`:77`) is flat + filters `*.md`, so a `_candidates/` subdir is already invisible. Drop the edit.
- **inferential-FB sensor classification** — mislabel to back-door audit #34; use computational-FB + #47.
- **git-remote-hash scope** + **CWD-only slug** — both diverge from the transcript-parent slug (contract #2).
- **PostToolUse trigger** — only earns its keep feeding a self-launched daemon (forbidden). SessionEnd single-pass is enough.
- **in-hook cap/rotate** — kill-unsafe in SessionEnd; moved to `read-candidates.sh` (gated flow).
- **ECC apply half entirely** — observer daemon, headless "do not ask" writes, ≥0.7 auto-inject, auto-promote, `/evolve` self-writing files, ecc2 cron + auto-merge. L4 / model-as-gate.

## 8. Verification

- `scripts/run-gauntlet.sh` 4/4 (plugin-validate + audit 0C/0W incl. #47 + critical-hooks incl. `test-ch-learn-capture` + eval gate incl. both new fixtures).
- **Precision floor (AUDIT FIX #3):** `learn-capture-precision.json` must hold a false-positive ceiling — a queue full of regex garbage inverts the feature's value.
- Manual: `KBG_LEARN_CAPTURE=1`, a session with a "no, use X not Y" correction → one row in the out-of-repo queue → next SessionStart drain-nudge surfaces "1 candidate awaits" → `kbg:learn` shows it in the gate → approve → real memory `.md` written, row archived. Adversarial: a session with "no" in prose only → **zero** rows.
- Confirm: queue never in `git status`; capture never blocks; confidence never gates; drain-nudge never nags twice for the same set.

## 9. Open decisions

1. **Reject disposition** — archive `status:rejected` (re-openable, never `rm`) vs hard-drain. *Rec: archive.*
2. **Phase 2 timing** — core capture+drain first; L3-guards as a follow-up. *Rec: core first.*
3. **Build-vs-hold (the real call, now arguable both ways):**
   - **Value case (for):** with the drain-nudge (#2) + precision floor (#3) folded in, capture closes the loop kbg:learn leaves open — corrections you'd otherwise forget by the time you next run kbg:learn get queued + resurfaced, with secrets scrubbed and garbage filtered.
   - **YAGNI case (against):** it adds 2 hooks + 2 scripts + schema + audit #47 + ADR addendum + a doctrine reversal, for a single-author harness where `kbg:learn` already does this on demand. If you reliably run kbg:learn at session end anyway, passive capture is overhead.
   - **The deciding question:** *do you actually forget to run kbg:learn?* If yes → build (the drain-nudge is the whole point). If no → hold; the feature is YAGNI.
   - **DECISION (2026-06-21):** Owner answered "I forget often" → **BUILD**. Phase 1 shipped v0.3.7
     (capture hook default-OFF, drain-nudge, read-candidates, kbg:learn Step 0, audit #47, ADR 0002
     addendum, 2 eval fixtures, 12-test sub-suite). Independent code review post-build: 0 Critical,
     all 6 invariants verified, 1 Major + 4 Minor folded (drain-nudge `_lib` bypass, cap/rotate
     open-row protection, precision tightening, emit-before-record). Gauntlet 4/4.

## 10. Audit → fix traceability (Rev 2)

| Major | Audit finding | Folded into |
|---|---|---|
| #1 secret-scrub | `_lib` redactor only runs inside `journal_append`, not direct writes; prose snippets leak | §4 CANDIDATE-SCHEMA deny-list + redact-whole-row fail-safe |
| #2 drain-loop | archive-rotate silently drops un-reviewed candidates; no resurfacing | §4 NEW `learn-drain-nudge.sh` (SessionStart) + §8 manual test |
| #3 harvest precision | regex can't tell a real correction from "no" in prose; no precision test | §4 role==user + word-boundary + NEW `learn-capture-precision.json` |
| #4 slug conflation | CWD-slug vs git-toplevel-slug diverge → silent zero candidates | §3 contract #2 — derive from transcript-parent, one shared fn |
| #5 double-mine | Step 0 + Step 2 surface the same correction twice | §4 Step 0 replaces Step 2 for this-session rows |
| #6 ADR home | filed "within ADR 0003" but it's an ADR-0002-class advisory sensor relaxing a load-bearing stance | §3 + §4 — ADR 0002 addendum, cross-ref SKILL.md:18 |
| minors | timeout, mkdir, append-only/concurrency, sensors.json concrete value, #47 framing, formula, off-by-one citations, build-order scope, BOUNDARY regen, count derivation | folded across §3–§8 |
| false alarm | "README stale at 45" — REFUTED, it's correctly 46 (44 `.sh` + 2 `.py`); delta is 46→48 for 2 new hooks | §4 README row |
