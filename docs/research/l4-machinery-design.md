# L4-push-gated machinery — buildable design (capability ≥ ECC)

> **Status:** 🟡 DESIGN ONLY — not built, no L4 machinery exists, all flags OFF. This is the
> implementation design that [ADR 0004](../adr/0004-l4-autonomy.md) (Accepted 2026-06-22) defers to a
> "separate, staged, gauntlet-gated build." Accepting the ADR is the *decision*; this doc is the
> *blueprint*. Nothing here ships until each slice is committed gauntlet-green behind the
> hardening-before-enable rule and the owner sets `KBG_AUTONOMY_L4=1`.
> **Date:** 2026-06-22 · **Decider:** Owner · **Operating point:** L4 push-gated (#1+#3+#4, auto-push
> #2 dropped, Gate 2 + cage kept permanently).
> **Provenance:** two design workflows this session — (1) a 5-reader file-cited trace of ECC's running
> loop (`affaan-m/ECC`), (2) an 11-agent map→design→adversarial-verify of the kbg build. All file:line
> claims below were read on source. Every slice came back **`sound-with-fixes`** (zero `unsound`); the
> per-slice blockers are recorded in §5–§8.

## 1. Goal & the capability bar

Owner goal: **"AI ทำงานเองได้มากสุด (คนถอยออกจากวง) + autonomous loop + เรียนรู้เองอัตโนมัติ"** — a
self-driving harness with the human out of the *launch* and *per-mutation* loops, matching ECC's
continuous-learning flywheel but in kbg's minimal, gated shape.

ECC's running loop is the **capability bar** (verified on source, §2). kbg must **match** each ECC
capability and **exceed** it on safety. The operating point (ADR 0004): adopt self-launch (#1),
model-as-gate (#3), auto-inject (#4); **drop** auto-push (#2) so a human reviews every batch at the
permanent **Gate 2** before it reaches `origin`; keep the **cage** the loop can never edit.

## 2. The capability bar — ECC's loop (file-cited)

ECC runs a closed 5-stage loop, ungated end-to-end (bounded only by default-OFF config bools + soft
rate gates). Verified on `affaan-m/ECC`:

| # | Stage | Mechanism | Gate |
|---|---|---|---|
| 1 | CAPTURE | `observe.sh` on PostToolUse/PreToolUse `*` writes every tool call → `observations.jsonl` (out-of-repo) | none |
| 2 | SCORE+STORE | `observer-loop.sh` spawns Haiku (`claude --model haiku --allowedTools Read,Write`) that writes instinct `.md` + self-assigns `confidence` by frequency (3-5=0.5, 6-10=0.7, 11+=0.85), write-once | none |
| 3 | INJECT | `session-start.js:378` filters `confidence ≥ 0.7`, top-6, injects as "Active instincts:" additionalContext **every** session | none (model-as-gate) |
| 4 | SELF-LAUNCH | `observe.sh` lazy `nohup`-spawns a detached `observer-loop` (survives session exit, Haiku told *"Do NOT ask for permission… just write"*); `ecc2/daemon.rs` unbounded heartbeat (30s) runs cron + auto-merge | none (default-OFF flag + soft rate gates) |
| 5 | APPLY/MERGE | `daemon.rs:397` auto-merges every conflict-free worktree via `git merge --no-edit`; readiness is a computational git state-machine | none (config bool only) |

Two fragilities kbg must **not** copy: everything ships default-OFF (so out-of-box ECC is not
self-driving — you arm it), and the confidence **decay/adjust rules are doc-only, implemented
nowhere** — `confidence` is write-once-by-Haiku and never decays in code.

## 3. The substrate kbg already has (the build extends, does not duplicate)

The L4 build is **not** new parallel machinery — it extends three flag-scope predicates and two data
lists already shipped for L3. Mapped on source:

| Component | Path | Role | L4 change |
|---|---|---|---|
| Cage denylist | `scripts/l3-cage.txt` (1-64, 27 entries) | deny-by-default paths the `--auto` loop may never write | add F2/F3 anchors |
| Loop guard | `scripts/l3-loop-guard.py` (1-273) | the single code-level enforcer: caps + cage matcher + `--max-flat`; never a model | flag predicate + TAMPER_VARS + R4 cap |
| Push gate (Gate 2) | `hooks/gates/l3-push-gate.sh` (1-87) | denies push/merge of an unreviewed batch; `KBG_L3_REVIEW_DONE=1` is the human override | flag predicate + TAMPER_PAT |
| Hook immunity | `hooks/_lib.sh:34-43` | forces every hook live (defeats `CLAUDE_HOOK_PROFILE=off`) during an authorized run | flag predicate |
| Rollback carve-out | `hooks/gates/block-dangerous-git.sh:41-52` | lets the loop `git reset --hard` its own pre-cycle tag | flag predicate (**4th F1 site — see §5**) |
| Capture half | `hooks/session/learn-capture.sh` + `scripts/read-candidates.sh` | SessionEnd stages candidates to an out-of-repo queue; confidence is **ordering-only** | inversion point for #4 |
| Apply half | `skills/learn/SKILL.md` (Step 4 AskUserQuestion) | the only memory-writing path; human-gated | the gate #4 skips inside a run |
| `--auto` loop body | `skills/recursive-improve/SKILL.md:164-233` | prose the model executes; `disable-model-invocation: true` | the line #1 + audit #32 rework |
| Route-B queue-read | `scripts/pr/recursive-improve-observe.py:278-299` | surfaces top-3 confidence candidates into the loop, read-only | where #4 auto-keep consumes+disposes |
| Audits #32/#43-#47 | `skills/harness-audit/scripts/audit.sh` (1049-1108, 1658-1805) | computational guardrails | rework #32/#47, extend #43/#44, add #48/#49 |

**Confirmed absent:** no scheduler / cron / launchd / self-launch primitive exists anywhere (`/loop`
+ `CronCreate` are CLAUDE.md "Deliberate non-goals"). #1 self-launch is greenfield and must be built
**in-cage**, not imported from the vendor `/loop` or `CronCreate`.

## 4. Staging (ADR 0004 — lowest blast radius first)

**Slice 0 hardening → #4 auto-inject → #3 model-gate → #1 self-launch.** The push gate (Gate 2) is ON
at every stage; with `KBG_AUTONOMY_L4` unset, behaviour is byte-identical to today's L3/L2.

## 5. Slice 0 — predecessor hardening (F1/F2/F3/R3/R4 + #48) · effort M

Pure hardening: ships **zero** new capability, only makes the existing L3 floor fire under an L4-only
flag. Must land first — it unblocks all three relaxations.

- **F1 — the inert-under-L4 gap (highest severity).** Four runtime enforcers hard-scope to
  `KBG_AUTONOMY_L3 == "1"` and go **inert** under an L4-only flag (L3 unset): `l3-push-gate.sh:32`
  (`exit 0` → Gate 2 vanishes), `_lib.sh:40` (immunity off → gates re-disarmable), `l3-loop-guard.py:57-58`
  (`L3_ACTIVE=False` → guard refuses to run), and **`block-dangerous-git.sh:50`** — the **4th site the
  ADR did not name** (rollback carve-out off → the loop wedges). **Fix:** a shared
  `kbg_autonomy_active()` helper firing on `L3 OR L4`; sweep **every** `KBG_AUTONOMY_L3 == "1"` literal
  across `hooks/` + `scripts/`, not only the three named; add `KBG_AUTONOMY_L4` to both tamper lists
  (`l3-loop-guard.py:61-66` TAMPER_VARS + `l3-push-gate.sh:54` TAMPER_PAT). Flag still captured **once
  at import** so the loop cannot self-elevate mid-run. **No auto-push carve-out** — the gate simply
  also fires under L4.
- **F2 — cage the grading corpus.** `l3-cage.txt:42` covers `eval/datasets/**` but not
  `eval/regressions/**` or `tests/evals/**` — the corpus #3 grades against. Add both to
  `l3-cage.txt` **and** the audit #43 `CAGE_ANCHORS` heredoc (`audit.sh:1680-1705`) in lockstep.
- **F3 — define + cage the scheduler config.** No path exists. Define `scripts/l4/scheduler.conf`
  (the only sanctioned self-launch config) and cage `scripts/l4/**` in both surfaces, so the loop can
  never edit its own launch cadence (kill-switch = delete the entry, ADR 0004 §kill-switch).
- **R3 — computational-every-cycle.** Audit #43-#47 run only post-hoc today. Add
  `l3-loop-guard.py precheck --assert-cage-intact` shelling `audit.sh --only 43` (new `--only` filter)
  so cage-completeness re-asserts inside the always-computational path each cycle; #3 cannot bypass it.
- **R4 — cumulative ceiling.** L3 caps are per-run from an operator-supplied `--state` that resets per
  launch; a self-launcher launches repeatedly and never trips them. Add cross-run
  `--max-runs-per-window` / `--max-wall-per-window` in `cmd_precheck`, persisted in a **separate**
  `scripts/l4/.window-state.json` (caged, so the loop cannot reset it).
- **audit #48 (new).** Invoke the guard `selftest` + the push-gate with `KBG_AUTONOMY_L4=1` (L3 unset)
  and CRIT unless the guard stays active and the push-gate **denies an actual `git push`** — the
  audit-side proof the F1 hole is closed.

**Blockers to close in the same commit:** (1) `CAGE_ANCHORS` is a curated **subset** of `l3-cage.txt`,
not a mirror — so "assert the two lists agree" is wrong; add the 3 new anchors to **both** explicitly.
(2) #48 must exercise the real push-DENY under an `L4=1` env, not merely assert the tamper-var add.

**Kill-switch:** computational, never a model — unset `KBG_AUTONOMY_L4` (guard fail-closes at next
process start) or delete the caged `scripts/l4/scheduler.conf` entry; R4 window caps auto-STOP a
runaway before a human intervenes.

## 6. Slice 1 — #4 auto-apply/auto-inject · effort M

A captured high-confidence candidate auto-becomes a durable `memory/<slug>.md` write **without** the
`kbg:learn` Step-4 AskUserQuestion gate — but **local-only, push-gated, confidence-ordered** (never
confidence-*gated* in the ECC sense), and **only inside an authorized L4 run**.

- **Mechanism:** a new ~120-line writer (e.g. `scripts/l4/l4-auto-keep.py`) consumes top-confidence
  rows via the existing `read-candidates.sh` LIST mode, writes the memory file through the **same**
  Step-5 write path, then disposes each via the existing `read-candidates.sh --archive promoted`. No
  second writer. The headless write routes through `l3-loop-guard.py check-act`, so the cage binds.
- **Reworked invariant:** audit #47 ("confidence never gates") inverts **conditionally** — confidence
  may order an auto-keep only when `KBG_AUTONOMY_L4=1`; outside a run the CRIT stays.
- **vs ECC:** matches the capture→self-score→auto-apply pipeline; **exceeds** on three verifiable axes
  — local+push-gated (the writer has no push verb), caged (ECC's Haiku writer has no denylist), and
  **decay implemented** (`read-candidates.sh:74` literally computes `-0.02*weeks_since(last_seen)`).
- **Shortfall (acceptable):** kbg writes a memory *file* resident next session, not ECC's hot
  mid-session additionalContext inject; and #4 still rides the human Gate-1 launch. Both deliberate.
- **Blockers:** (A) an audit must **positively assert** `l4-auto-keep.py` contains **no** confidence
  comparison operator at all (else the #47 exemption is a permanent hole a future edit could exploit);
  (B) reuse #48's real push-DENY-under-L4 assertion.

## 7. Slice 2 — #3 model-as-gate · effort M

An LLM "good enough" verdict stands in for the **quality** portion of the gauntlet while the
**computational** checks (audit #43-#47, critical-hooks, plugin-validate) still run every cycle.
Trialed on exactly **one low-stakes prose skill**.

- **Mechanism:** a new ~60-line `scripts/l4/l4-quality-gate.sh` + an allowlist `l4-quality-trial.txt`,
  invoked **after** `run-gauntlet.sh` (which runs first, unconditionally). The model verdict can only
  **veto a green** (force an extra rollback — the safe direction), **never bless a red**. Fail-CLOSED:
  missing/erroring/unparseable model output → rollback. The fresh-context read-only judge leans on the
  existing audit #45 (maker≠checker) to close the LLM-judge-circularity ECC's same-model loop has.
- **vs ECC:** matches Haiku self-scoring; **exceeds** because a deterministic gauntlet runs under every
  verdict and the judge is read-only.
- **Shortfall (acceptable now, real gap to close later):** one prose skill only — zero coverage for
  code/enforcement-surface candidates. Widen `l4-quality-trial.txt` incrementally, each addition
  re-audited.
- **Blocker:** machine-enforce the two-copy cage sync in the same commit (a new #49, or extend #43b):
  CRIT if `l4-quality-gate.sh` / `l4-quality-trial.txt` appear in `l3-cage.txt` but not the
  `CAGE_ANCHORS` heredoc (or vice-versa) — a partial landing silently un-cages the loop's own judge.

## 8. Slice 3 — #1 self-launch · effort L (highest blast radius — LAST)

An in-cage scheduler replaces the human Gate-1 launch. **Not** `/loop` or `CronCreate`.

- **Mechanism:** a launcher (`scripts/l4/launch.sh`) invoked by a detached, persistent macOS
  **launchd** `StartInterval` plist; the launcher reads the caged `scripts/l4/scheduler.conf`, sets
  `KBG_AUTONOMY_L4=1`, and drives the **same** prose `--auto` cycle calling the **same**
  `l3-loop-guard.py` subcommands (caps + cage + `--max-flat` reused unchanged once they fire on L3 OR
  L4). Cadence is throttled by R4's cumulative ceiling. Audit #32 is **redesigned** to forbid
  self-start *outside* an authorized L4 run (flag-gated), not deleted.
- **vs ECC:** matches "a run starts with no human invocation, on a cadence, surviving session exit";
  **exceeds** on the permanent push-gate (no auto-merge), the cage, a kill-file that defeats a
  self-reinstalling schedule, and the cumulative cap.
- **Shortfall (acceptable, by design):** no auto-merge, no parallel worktree fan-out, no continuous
  5min/30s cadence — the human push-review is the throughput bottleneck **on purpose**.
- **⚠️ BLOCKER — the deepest finding (outside-repo cage gap):** the launchd plist
  (`~/Library/LaunchAgents/com.kbg.l4-launcher.plist`) and the kill-file live **outside the repo**;
  `check-act` is a voluntary model-discipline call, **not** a PreToolUse interceptor — so **no hook
  mechanically blocks writes to those paths today.** Before enabling #1, add a mechanical Act-layer
  guard: a PreToolUse Bash/Write gate that DENIES any write / `launchctl` mutation targeting the plist
  or kill-file while `KBG_AUTONOMY_L4=1` (mirroring how `l3-push-gate.sh` mechanically denies push).
  Without it, a self-launched loop could rewrite its own launch cadence — escaping the kill-switch.

## 9. Capability verdict — where kbg ≥ ECC and < ECC (by design)

**kbg exceeds ECC (safety):** an immutable deny-by-default cage the loop physically cannot edit (ECC
writes anywhere); a permanent human push-gate (ECC auto-merges conflict-free worktrees); a flag
captured-once so the loop cannot self-elevate (ECC's Haiku is told "just write"); a computational
cumulative ceiling across self-launches (ECC has only soft rate gates); decay implemented in code (ECC
left it doc-only); audit #48 proving the gates fire under the new flag (ECC asserts nothing about its
own guards).

**kbg is less capable than ECC (throughput — intentional):** no auto-merge / no parallel worktree
fan-out; cadence throttled well below ECC's heartbeat by R4; #3 trialed on one prose skill, not the
whole corpus. Each is the deliberate cost of keeping the human at the one irreversible boundary.

## 10. Acceptance per slice (hardening-before-enable)

Every slice ships committed + **gauntlet-green under the flag** (measure green *with* `KBG_AUTONOMY_L4=1`,
not only flag-OFF — the v0.3.10 lesson) before the next is built. Slice 0's audit #48 + R3 per-cycle
assertion are the gating proof for everything after it.

## 11. Open decisions (owner)

1. **#1 self-launch substrate** — launchd plist on macOS is the proposed persistence mechanism; it is
   the riskiest piece (the §8 outside-repo cage gap). Confirm launchd, or pick an alternative (e.g. a
   git-hook-triggered launcher) before Slice 3.
2. **Build cadence** — build Slice 0 now (safe, flag-OFF byte-identical), or hold the whole build until
   the full design is reviewed end-to-end.
3. **`disable-model-invocation` on `recursive-improve`** stays (audit #32 redesign gates self-start on
   the L4 flag, it does not drop the requirement) — confirm this framing.
