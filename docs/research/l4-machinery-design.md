# L4/L5 autonomy machinery — buildable design (capability ≥ ECC)

> **Status:** 🟢 BUILT 2026-06-23 — the full 5-slice L4/L5 machinery (Slices 0–4, issues #17–#35)
> is implemented + gauntlet-green on `develop`. `KBG_AUTONOMY` stays OFF by default (flag-OFF
> byte-identical to L2/L3); arming an L4/L5 run is the owner's separate, later act. This doc was
> the *blueprint* [ADR 0004](../adr/0004-l4-autonomy.md) (Accepted 2026-06-22) deferred to a
> "staged, gauntlet-gated build"; each slice shipped committed gauntlet-green behind the
> hardening-before-enable rule (Slice N green before Slice N+1 starts).
> **Date:** 2026-06-22 · **Decider:** Owner · **Operating point:** L4 push-gated (#1+#3+#4, auto-push
> #2 dropped, Gate 2 + cage kept permanently).
> **Provenance:** three workflows this session — (1) a 5-reader file-cited trace of ECC's running loop
> (`affaan-m/ECC`), (2) an 11-agent map→design→adversarial-verify of the kbg build, (3) a 34-agent
> fresh-context staff-eng review (4 dims → adversarial-verify each finding against source → synthesis):
> verdict **capability ≥ ECC = yes-with-fixes**, 23 findings confirmed (2 blocker / 7 major / 8 minor), 3
> refuted. All file:line claims below were read on source; this revision folds in all 23 corrections — they
> convert nine prose safety-obligations into named, gating deliverables and tighten four imprecise
> framings, **without changing the architecture**. Per-slice blockers are recorded in §5–§8.5.

## 1. Goal & the capability bar

Owner goal: **"AI ทำงานเองได้มากสุด (คนถอยออกจากวง) + autonomous loop + เรียนรู้เองอัตโนมัติ"** — a
self-driving harness with the human out of the *launch* and *per-mutation* loops, matching ECC's
continuous-learning flywheel but in kbg's minimal, gated shape.

ECC's running loop is the **capability bar** (verified on source, §2). kbg must **match** each ECC
capability and **exceed** it on safety — but the safety-exceed is *load-bearing on computational gates
that do not exist yet* (`audit.sh --only`, audit #48/#49, the per-cycle cage re-assert, the outside-repo
launchd gate). Until those ship gauntlet-green they are **obligations, not guarantees**; §5–§10 make each
a named, gating deliverable rather than prose. The operating point (ADR 0004): adopt self-launch (#1),
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
| Cage denylist | `scripts/cage.txt` (1-63, 27 entries) | deny-by-default paths the `--auto` loop may never write | add F2/F3 anchors |
| Loop guard | `scripts/loop-guard.py` (1-273) | the single code-level enforcer: caps + cage matcher + `--max-flat`; never a model | flag predicate + TAMPER_VARS + R4 cap |
| Push gate (Gate 2) | `hooks/gates/push-gate.sh` (1-87) | denies push/merge of an unreviewed batch; `KBG_REVIEW_DONE=1` is the human override | flag predicate + TAMPER_PAT |
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

## 5. Slice 0 — predecessor hardening (F1/F2/F3/F4/R3/R4 + #48) · effort M

Pure hardening: ships **zero** new capability, only makes the existing L3 floor fire under an L4-only
flag. Must land first — it unblocks all three relaxations.

> **Key-encoding (2026-06-22 owner decision):** the per-level env keys `KBG_AUTONOMY_L3` / `_L4` / `_L5`
> are superseded by a **single on/off key `KBG_AUTONOMY` (`1` = armed, unset/`0` = OFF)**; this slice's F1
> builds the single-key reader. Below, `L3` / `L4` / `L5` are **era-labels** (which committed-code
> generation an armed run is), **not** separate key values — the level a run runs at is set by the
> committed slice code, not the operator. Recorded as a key-encoding note in ADR 0003/0004; only the
> representation changes, no prior decision. (Same change collapses the sibling `KBG_L3_REVIEW_DONE` →
> `KBG_REVIEW_DONE` — the "L3" there is the same vestigial level-in-the-name; it is honored under L4/L5.)

- **F1 — the inert-under-L4 gap (highest severity).** Four runtime enforcers hard-scope to
  `KBG_AUTONOMY_L3 == "1"` and go **inert** under an L4-only flag (L3 unset): `push-gate.sh:32`
  (`exit 0` → Gate 2 vanishes), `_lib.sh:40` (immunity off → gates re-disarmable), `loop-guard.py:57-58`
  (`L3_ACTIVE=False` → guard refuses to run), and **`block-dangerous-git.sh:50`** — the **4th site the
  ADR did not name** (rollback carve-out off → the loop wedges). **Fix:** a shared
  `autonomy_on()` helper reading the **single `KBG_AUTONOMY` key (0/1)** — the per-level
  `KBG_AUTONOMY_L3/L4` keys collapse into it (key-encoding note above). Sweep **every**
  `KBG_AUTONOMY_L3 == "1"` literal across `hooks/` + `scripts/`, routing all through `autonomy_on()`; add
  `KBG_AUTONOMY` to both tamper lists (`loop-guard.py:61-66` TAMPER_VARS + `push-gate.sh:54`
  TAMPER_PAT). Key still captured **once at import** so the loop cannot self-elevate mid-run. **No
  auto-push carve-out** — the gate simply also fires when armed. (Single key 0/1, **not** a `=3|4|5` level
  value: the level is build-state, not an operator dial; if per-environment ceilings ever become real,
  swapping 0/1 → a level scheme is a one-function change, because every read already routes through
  `autonomy_on()`.) **Installer fail-safe (guard 3):** `autonomy_on()` treats arming as real **only** from a
  per-repo `.claude/settings.local.json` in `CLAUDE_PROJECT_DIR` — a bare *user-global* `KBG_AUTONOMY=1`
  (which would reach every repo's hooks) arms **nothing**; #48(c) below CRITs any raw literal not routed
  through the helper, so the never-user-global rule is machine-enforced, not prose.
- **F2 — cage the grading corpus.** `cage.txt:42` covers `eval/datasets/**` but not
  `eval/regressions/**` or `tests/evals/**` — the corpus #3 grades against. Add both to
  `cage.txt` **and** the audit #43 `CAGE_ANCHORS` heredoc (`audit.sh:1680-1705`) in lockstep.
- **F3 — define + cage the scheduler config.** No path exists. Define `scripts/l4/scheduler.conf`
  (the only sanctioned self-launch config) and cage `scripts/l4/**` in both surfaces, so the loop can
  never edit its own launch cadence (kill-switch = delete the entry, ADR 0004 §kill-switch). **Cage the
  arming home (guard 4):** `.claude/settings.local.json` is the per-repo arming home (the legitimate
  per-environment home for `KBG_AUTONOMY` — *never* user-global, which reaches every repo's hooks; see
  `docs/reference/env-vars.md` §"Where to set them"). Add it to **both** `cage.txt` and the #43
  `CAGE_ANCHORS` heredoc in lockstep — a settings file the loop can write is the same self-elevation surface
  as the scheduler config (the loop must not arm itself by editing its own settings). Outside-repo
  `~/.claude/settings.json` is covered by the §8 Act-layer gate, not the cage.
- **F4 — installer fail-safe: anchor `REPO_ROOT` + affirm repo-identity (guards 1+2).**
  `loop-guard.py:52-53` sets `REPO_ROOT = SCRIPT_DIR.parent` (the plugin cache), but the loop's
  `git tag/commit/reset` + `Edit/Write` (`recursive-improve/SKILL.md`) run against session **CWD** = the
  operator's repo — so the cage and dirty-abort guard the **wrong tree**. (a) Derive `REPO_ROOT` from
  `git rev-parse --show-toplevel` of CWD and **STOP** if it fails; (b) affirmatively assert that tree is the
  genuine kbg-harness checkout (sentinel `.claude-plugin/plugin.json` `name=="kbg"` **and** a work-tree whose
  remote matches the harness) else STOP with *"L3/L4/L5 self-improves the kbg-harness itself, not your
  project — REPO_ROOT (`<path>`) is not a kbg-harness checkout."* Not an `is-this-KOBIG` env test (spoofable).
  This is what makes the repo-identity precondition **real** rather than incidental — today a flag-armed
  installer is stopped only because the cache has no `.git` (`_git_dirty()` fails closed), which is silent and
  evaporates once this bug is fixed. Machine-enforce via a #48-class audit leg; the §3 substrate plan
  (flag-predicate + TAMPER_VARS + R4 only) did not slate it.
- **R3 — computational-every-cycle.** Audit #43-#47 run only post-hoc today. Add
  `loop-guard.py precheck --assert-cage-intact` shelling a per-check runner so cage-completeness
  re-asserts inside the always-computational path each cycle; #3 cannot bypass it. **R3 is the single
  mechanism that keeps #3 (Slice 2) non-circular — so it is a *named gating precondition for Slice 2*,
  not just "part of Slice 0" (see §10).**
- **`audit.sh --only <id>` (new — first-class deliverable; R3 depends on it).** Today only
  `--staleness-only` exists (`audit.sh:21`); there is **no** `--only`. Build a real per-check dispatch (or
  extract #43's cage-completeness assertion into a standalone script both `audit.sh` and `precheck` call)
  that runs exactly the named check, preserves that check's skip/CRIT semantics, and exits non-zero on
  CRIT. R3 shells it every cycle, so it must **fail-CLOSED** — a shell-out error → STOP — and note that
  #43 re-reads `cage.txt`, making the per-cycle invocation self-referential (must not loop). Effort is
  non-trivial: `audit.sh` is a monolith. R3 cannot land until `--only` lands.
- **R4 — cumulative ceiling.** L3 caps are per-run from an operator-supplied `--state` that resets per
  launch; a self-launcher launches repeatedly and never trips them. Add cross-run
  `--max-runs-per-window` / `--max-wall-per-window` in `cmd_precheck`, persisted in a **separate**
  `scripts/l4/.window-state.json` (caged, so the loop cannot reset it).
- **Act-layer self-launch gate (the §8 blocker, pulled forward to Slice 0).** The launchd plist +
  kill-file live **outside the repo**, where `check-act` (a voluntary subcommand, not a PreToolUse
  interceptor) cannot reach. Build a mechanical PreToolUse Bash/Write gate that **DENIES** any write /
  `launchctl` mutation targeting the plist or kill-file while `KBG_AUTONOMY_L4=1`, covered by a #48-style
  **real-DENY** assertion. This is a **Slice-0 hard precondition**: #1 (Slice 3) is *not buildable* until
  this ships gauntlet-green — model-discipline is not a cage (§8, ADR 0004 §Acceptance).
- **audit #48 (new — proves F1 closed BOTH ways).** (a) With `KBG_AUTONOMY_L4=1` (L3 unset): CRIT unless
  the guard stays active and the push-gate **denies an actual `git push`** — proof the hole is closed. (b)
  With **both** flags unset: CRIT unless each of the four gates no-ops exactly as the L2 baseline — the
  *flag-OFF byte-identical* property the whole harness rides on (an OR-helper refactor is exactly what can
  regress it via empty-string truthiness / wrong default). Pair (b) with a critical-hooks test that runs a
  representative `git push` under no-flags and asserts the push-gate **exits 0** (does not deny). (c)
  **Enforce the F1 enumeration:** grep `hooks/` + `scripts/` for any raw `KBG_AUTONOMY` literal **not**
  routed through `autonomy_on()` and CRIT — so F1 is machine-enforced, not enumerate-and-trust (collapsing
  to one on/off key removes the `L3 OR L4 OR L5` disjunction that made the old per-level enumeration fragile).

**Blockers to close in the same commit:** (1) `CAGE_ANCHORS` is a curated **subset** of `cage.txt`,
not a mirror, and #43's anchor check is **directional** (anchors ⊆ cage) — so a path added to the cage
but missing from `CAGE_ANCHORS` passes **silently**, the exact F2/F3 partial-landing this slice exists to
prevent. Don't ship F2/F3 on a prose "add to both": add a **gating audit leg** (same shape Slice 2
requires) that CRITs if any new L4 anchor (`eval/regressions/**`, `tests/evals/**`, `scripts/l4/**`)
appears in one surface but not the other. (2) #48 must exercise the real push-DENY under an `L4=1` env,
not merely assert the tamper-var add.

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
  second writer. `check-act` runs as uniform discipline but does **not** constrain `memory/<slug>.md` —
  `memory/` is intentionally **uncaged** (the loop must write there). Slice 1's actual brakes are (a) the
  push-gate keeps the file local, (b) the blocker-A audit positively asserts no confidence operator in
  `l4-auto-keep.py`, (c) `check-act` still blocks any tamper-var or stray caged path the writer touches.
- **Reworked invariant (one atomic commit):** audit #47 ("confidence never gates") inverts
  **conditionally** — confidence may *order* an auto-keep only when `KBG_AUTONOMY_L4=1`; outside a run the
  CRIT stays. The #47 exemption clause and the blocker-A positive assertion **must ship in the same
  commit** — if the exemption lands first, a `confidence>=0.7` in the L4 writer is neither old-CRIT-blocked
  nor new-assertion-caught (a window that is exactly ECC's model-as-gate). "Order" stays orthogonal to
  "gate": the writer consumes the already-sorted `read-candidates.sh` LIST output and contains **no numeric
  confidence read at all** — order comes from the upstream sort, not a comparison in the writer.
- **vs ECC:** matches the capture→self-score→auto-apply pipeline; **exceeds** on three verifiable axes
  — local+push-gated (the writer has no push verb), caged (ECC's Haiku writer has no denylist), and
  **decay implemented** (`read-candidates.sh:74` literally computes `-0.02*weeks_since(last_seen)`).
- **Shortfall (acceptable):** kbg writes a memory *file* resident next session, not ECC's hot
  mid-session additionalContext inject; and #4 still rides the human Gate-1 launch. Both deliberate.
- **Blockers:** (A) an audit must **positively assert** `l4-auto-keep.py` contains **no** confidence
  comparison operator at all, written so that *removing* the assertion re-trips a CRIT (test the audit's
  own failure mode) — else the #47 exemption is a permanent hole a future edit could exploit; (B) reuse
  #48's real push-DENY-under-L4 assertion; (C) audit that the writer shells **no** `git push` / `gh` (same
  positive-assertion style as A) — defense in depth so no-auto-push is enforced at the writer, not only the
  gate.

## 7. Slice 2 — #3 model-as-gate · effort M

An LLM "good enough" verdict stands in for the **quality** portion of the gauntlet while the
**computational** checks (audit #43-#47, critical-hooks, plugin-validate) still run every cycle.
Trialed on exactly **one low-stakes prose skill**.

- **Mechanism:** a new ~60-line `scripts/l4/l4-quality-gate.sh` + an allowlist `l4-quality-trial.txt`,
  **to be invoked after** `run-gauntlet.sh` (which runs first, unconditionally) once the owner-gated
  trial begins (ADR 0004 §"Recommended staging order" stage 2). **As built today** the gate exists, is
  audited (#49), tested, and allowlisted, but is **not yet wired into the live `--auto` cycle** — it
  stays inert while `KBG_AUTONOMY` is OFF. The model verdict can only
  **veto a green** (force an extra rollback — the safe direction), **never bless a red**. Fail-CLOSED:
  missing/erroring/unparseable model output → rollback. The fresh-context read-only judge addresses the
  LLM-judge-circularity ECC's same-model loop has — but audit #45 guards reviewer-*agent* `tools:`, **not**
  a shell-script judge, so a new Slice-2 audit leg must positively assert `l4-quality-gate.sh` is
  structurally fail-closed and read-only: (a) it invokes the judge Read-only (no Write/Edit), (b) a
  missing/unparseable verdict resolves to **rollback** (assert the default), (c) it can force-rollback a
  green but **never** convert red→green. Do not rely on #45 to cover a judge it was not written for.
- **vs ECC:** matches Haiku self-scoring; **exceeds** because a deterministic gauntlet runs under every
  verdict and the judge is read-only.
- **Shortfall (acceptable now, real gap to close later):** one prose skill only — zero coverage for
  code/enforcement-surface candidates. Widen `l4-quality-trial.txt` incrementally, each addition
  re-audited.
- **Blocker:** machine-enforce the two-copy cage sync in the same commit (a new #49, or extend #43b):
  CRIT if `l4-quality-gate.sh` / `l4-quality-trial.txt` appear in `cage.txt` but not the
  `CAGE_ANCHORS` heredoc (or vice-versa) — a partial landing silently un-cages the loop's own judge.

## 8. Slice 3 — #1 self-launch · effort L (highest blast radius — LAST)

An in-cage scheduler replaces the human Gate-1 launch. **Not** `/loop` or `CronCreate`.

- **Mechanism:** a launcher (`scripts/l4/launch.sh`) invoked by a detached, persistent macOS
  **launchd** `StartInterval` plist; the launcher reads the caged `scripts/l4/scheduler.conf`, sets
  `KBG_AUTONOMY_L4=1`, and drives the **same** prose `--auto` cycle calling the **same**
  `loop-guard.py` subcommands (caps + cage + `--max-flat` reused unchanged once they fire on L3 OR
  L4). Cadence is throttled by R4's cumulative ceiling. Audit #32's frontmatter assertion
  (`disable-model-invocation: true`, `audit.sh:1085`) stays **UNCHANGED and keeps firing** — it is still
  correct under L4 because the **OS scheduler**, not the model, self-starts the shell script, so the flag
  is not contradicted. #32 is **additive, not loosened**: it *adds* an assertion that the caged,
  flag-gated launcher path is the **only** sanctioned self-start.
- **Precondition prose (Slice-3 sub-task):** the `--auto` loop body still keys its documented precondition
  off `KBG_AUTONOMY_L3=1` (`recursive-improve/SKILL.md:173`); no slice edits that prose. Update it (and any
  prose hardcoding `KBG_AUTONOMY_L3`) to "`KBG_AUTONOMY_L3=1` **OR** `KBG_AUTONOMY_L4=1` (an authorized
  autonomy run)" — the prose precondition is part of the L3-OR-L4 surface, not just the four runtime
  predicates, so the launcher's flag actually satisfies the loop's own gate.
- **Installer precondition (Slice-0 F4 dependency).** Self-launch is the highest-risk amplifier of the
  REPO_ROOT mis-anchor: an unattended loop with `REPO_ROOT` pointing at the cache while CWD is the
  installer's repo would autonomously mutate the **wrong tree**, with no human in the launch loop to catch
  it. §5 **F4** (anchor + repo-identity) is therefore a **hard precondition for Slice 3**, alongside the
  Act-layer gate below.
- **vs ECC:** matches "a run starts with no human invocation, on a cadence, surviving session exit";
  **exceeds** on the permanent push-gate (no auto-merge), the cage, a kill-file that defeats a
  self-reinstalling schedule, and the cumulative cap.
- **Shortfall (acceptable, by design):** no auto-merge, no parallel worktree fan-out, no continuous
  5min/30s cadence — the human push-review is the throughput bottleneck **on purpose**.
- **⚠️ BLOCKER — the deepest finding (outside-repo cage gap), now a Slice-0 precondition:** the launchd
  plist (`~/Library/LaunchAgents/com.kbg.l4-launcher.plist`) and the kill-file live **outside the repo**,
  where `check-act` (voluntary subcommand, not a PreToolUse interceptor) cannot reach — **no hook
  mechanically blocks writes there today.** The mechanical Act-layer guard (PreToolUse Bash/Write DENY on
  any write / `launchctl` mutation to the plist or kill-file while `KBG_AUTONOMY_L4=1`, mirroring how
  `push-gate.sh` denies push) is **built in Slice 0** (§5); #1 is **not buildable** until it ships
  gauntlet-green with a real-DENY test. Without it a self-launched loop could rewrite its own cadence and
  escape the kill-switch — model-discipline is not a cage. **(Substrate RESOLVED §11.1: launchd — the
  in-repo git-hook alternative was rejected as a false middle, so this Act-layer gate is *required*, not
  optional.)**

## 8.5 Slice 4 — #2 auto-push ship-gate (L5, opt-in *beyond* L4) · effort M (LAST)

[ADR 0005](../adr/0005-l5-auto-push.md) (Accepted) re-adopts auto-push **beyond** the L4 operating point in
§1: the human leaves the push loop and the computational gauntlet becomes the sole ship authority. Build
only after Slice 3 is gauntlet-green; the model stays **veto-only** (ADR 0005 — can force an extra rollback,
never *authorize* a ship), so the ship-gate stays computational, never a model.

- **Cross-remote ship-gate (guard 5).** With the human out of the push loop, the gauntlet grades the
  **cache**, never the installer's working tree — so an in-plugin pre-push gate must own ship authority.
  Compare push-destination `host+org` vs `origin` `host+org`, **DENY on divergence**, fail-closed, and
  default to an **empty** allowlist so an un-configured installer auto-pushes **nowhere**. This ports the
  owner's cross-org `settings.json` *mechanism* (origin-vs-destination divergence), **never** the
  `wasikarn`/`100-Stars-Co` literals — the line between portable in-plugin and the rejected Option-C (§12).
- **vs ECC:** matches ECC's auto-merge (stage 5) — but ECC's merge is gated by a computational conflict-free
  git check, and kbg's ship is gated by the full gauntlet **plus** this cross-remote DENY; the model
  authorizes neither.
- **Blocker:** ship with a real-DENY test (push to a divergent `host+org` under `KBG_AUTONOMY=1` → DENY) +
  a #48-class audit leg asserting the empty-allowlist default, in the same commit as the gate.

## 9. Capability verdict — where kbg ≥ ECC and < ECC (by design)

**kbg exceeds ECC (safety) — verifiable today:** an immutable deny-by-default cage the loop physically
cannot edit (ECC writes anywhere); a human push-gate at L2–L4 (ECC *can* auto-merge conflict-free
worktrees — opt-in config bool + a computational readiness check, not unconditional), replaced at L5
([ADR 0005](../adr/0005-l5-auto-push.md)) by a computational ship-gate (the gauntlet) — the human leaves
the push loop but the authorizing gate stays computational, never a model; a flag captured-once
so the loop cannot self-elevate (ECC's Haiku is told "just write"); decay implemented in code
(`read-candidates.sh:74`) where **ECC's confidence is write-once-by-Haiku — no decay implementation was
found in the 2026-06-21 on-disk read** (cited read, not a universal negative).

**kbg exceeds ECC (safety) — guaranteed only once the audits land gauntlet-green:** a computational
cumulative ceiling across self-launches (R4); audit #48 proving the gates fire *and stay inert* under the
flags; the per-cycle cage re-assert (R3) and the Slice-2 cage-sync (#49). These are **not present-tense
facts** until Slice 0/2 ship — they are the design's load-bearing obligations, tracked as named gating
deliverables in §5/§7/§10.

**kbg is less capable than ECC (throughput — intentional at L2–L4; partially closed at L5):** at L2–L4
no auto-merge / no parallel worktree fan-out and the human sits at the one irreversible (push) boundary;
L5 ([ADR 0005](../adr/0005-l5-auto-push.md)) re-adds auto-push/auto-merge behind the computational
ship-gate, removing the human from the push loop. Still intentional at every level: cadence throttled
well below ECC's heartbeat by R4; #3 trialed on one prose skill, not the whole corpus; and learnings
become resident **next-session** (kbg writes a `memory/` file), not injected **mid-session** (ECC
re-renders additionalContext every session).

## 10. Acceptance per slice (hardening-before-enable)

> **Gate-2 strengthening criterion RETIRED 2026-06-25** (the "strengthen Gate 2
> commensurately" bullet below): Gate-2 (`KBG_REVIEW_DONE=1` + `review_finding`) and
> `push-gate.sh` are retired — see the ADR 0004 "Gate-2 RETIRED" note. The underlying
> principle (maker≠checker; the gate that authorizes a ship stays computational, never a
> model) is **retained** — it is now satisfied by `block-dangerous-git.sh` scoped denials +
> `advisory-push-reminder.sh` (ECC-aligned: review is advisory, not enforced), not a
> review-done flag. The L4 model-as-gate relaxation (#3) this criterion backstopped never
> went live, so the criterion dissolves with it. The bullet text is kept below as the
> historical record.

Every slice ships committed + **gauntlet-green under the flag** (measure green *with* `KBG_AUTONOMY_L4=1`,
not only flag-OFF — the v0.3.10 lesson) **and** flag-OFF byte-identical (audit #48b) before the next is
built. Slice 0's audit #48 + R3 per-cycle assertion are the gating proof for everything after it.

- **R3 gates Slice 2 by name:** Slice 2 (#3) MUST NOT build until `loop-guard.py precheck
  --assert-cage-intact` is committed and a test proves a **holed cage forces STOP even when the model
  verdict is green** — the ordering is machine-checked (via #48), not prose-ordered.
- **Gate 2 is now the independent backstop for #3 — strengthen it commensurately:** under L4 the batch's
  *quality* judgment was made by an LLM (#3), so the single-model circularity moves one layer back, broken
  only by Gate 2 being fresh human context. Add a criterion: the session-audit-trail surfaced at Gate 2
  must include the **#3 model verdict per cycle**; a maker≠checker `kbg:review-pr` pass is **mandatory**
  (not optional) before `KBG_REVIEW_DONE=1` is honored under L4; record the Gate-2 review as a journal
  event so a **rubber-stamp streak is observable** at the quarterly decay sweep (mirrors ADR 0002
  §gate-discipline — without an observable, "must be a real review" is prose throughput pressure erodes).
- **Exit-condition trigger-2 needs a detector outside the cage.** ADR 0004's second exit trigger ("a
  security-gate loosening slipping past the cage") can only fire *after* the cage already failed silently —
  the cage cannot be its own detector. Add a cheap post-push tripwire (run #43-#47 against
  `origin/develop`) that CRITs if any cross-repo security gate's content changed in an L4-authored commit,
  living **outside** the cage's own assertion path.

## 11. Open decisions (owner)

1. **#1 self-launch substrate — RESOLVED 2026-06-22: launchd plist** (`StartInterval` → `launch.sh`).
   True cadence self-launch *is* the point of #1 (the human out of the *launch* loop) and the explicit
   ≥-ECC bar. The in-repo git-hook alternative was **rejected**: a git hook fires on git *events*, not a
   clock, so it cannot self-launch on a cadence and cannot cold-start with no session — a false middle,
   neither real autonomy nor simpler than human launch. The out-of-repo plist surface is closed by the
   **Slice-0 Act-layer gate** (§5/§8); the kill-switch stays in-repo (delete the caged `scheduler.conf`
   entry). **Bounded by staging:** Slice 3 is LAST and optional — if the Act-layer gate proves too hot,
   stop at Slice 2 and keep human Gate-1 launch. Consistent with the maximal-bounded posture: Gate 2 (push
   review) is permanent, so even under self-launch the human holds the one irreversible boundary.
2. **Build cadence** — build Slice 0 now (safe, flag-OFF byte-identical), or hold the whole build until
   the full design is reviewed end-to-end.
3. **`disable-model-invocation` on `recursive-improve`** stays. Audit #32's frontmatter assertion is
   **unchanged** (the OS, not the model, self-starts — see §8); #32 only *adds* an assertion that the
   caged, flag-gated launcher is the sole sanctioned self-start. The change is additive, not a loosening —
   confirm this framing.

## 12. External installers (scope + guard index)

The plugin is publicly installable (`claude plugin install kbg@kobig`, the **single delivery path** the
owner dogfoods, ADR 0001). A third party who installs it and sets the arming flag in **their own** repo on
**their own** machine is a real operator class the autonomy design must fail safe for. A 32-agent
fresh-context adversarial sweep (4 lenses → refute-by-default verify → synthesis, 2026-06-22) confirmed
**9 real gaps** (18 refuted/downgraded). Verdict: the author's proposed **"default-OFF + repo-identity
precondition"** is the right spine but **insufficient as stated** — it needs the 5 guards indexed below, now
threaded into their slice homes (§5 F1/F3/F4, §8, §8.5), **all in-plugin and self-contained** (none is the
rejected Option-C of porting the owner's dotfiles guards).

**Scope statement (the load-bearing precondition):** the L3/L4/L5 loop **self-improves the kbg-harness
checkout *itself*** — every cage path is repo-relative to the harness (`hooks/**`, `skills/`,
`docs/adr/**`), Observe reads `harness-audit`, candidates are the harness's own audit findings. It is **not**
a tool for improving the repo the installer opened. The "opt-in + owner's-tool/owner's-risk" basis (ADR
0004:156-158, 0005) is telos+ownership-based and **non-transferable** — it assumes the operator *is* the
author working *in* the harness repo, with a single-author, git-recoverable, disposable non-safety surface.

**What already protects a fresh install (verified):** default-OFF covers it entirely — flag unset ⇒ every
guard subcommand STOPs, push-gate `exit 0`, immunity off (all 9 findings `covered_by_default_off`). A
*flag-armed* installer is **also** stopped today, but **only incidentally**: the plugin cache has no `.git`
(`~/.claude/plugins/cache/kobig/kbg/<ver>/`), so `_git_dirty()` fails closed → STOP. That protection is
**silent and brittle** (no message; evaporates if a delivery path ever makes the cache a git repo, or once
the REPO_ROOT bug (§5 F4) is fixed). It must be replaced by an affirmative guard.

**The 5 guards — full spec now lives in the named slice (single source of truth); this is the index:**

| # | Guard | Slice home | Fails closed un-configured |
|---|---|---|---|
| 1 | Anchor `REPO_ROOT` to the *mutated* tree (`git rev-parse --show-toplevel` of CWD), STOP on failure | §5 **F4** | yes — STOP |
| 2 | Affirmative, message-bearing repo-identity precondition (is-this-kbg, not is-this-KOBIG) | §5 **F4** | yes — STOP |
| 3 | `autonomy_on()` reads *user-global* arming as fail-safe-OFF (per-repo `.claude/settings.local.json` only) | §5 **F1** | yes — arms nothing |
| 4 | Cage the arming home (`.claude/settings.local.json`), cage + `CAGE_ANCHORS` lockstep | §5 **F3** | n/a — cage entry |
| 5 | In-plugin cross-remote pre-push CRIT (origin-vs-destination divergence, empty default allowlist) | §8.5 **Slice 4** | yes — pushes nowhere |

Guards 1+2 also gate Slice 3 self-launch (§8) — an unattended loop amplifies the mis-anchor risk.

**Reject Option-C** (porting the owner's named-org deny-list / autoMode `hard_deny` into the plugin) as
public-distributable drift (a stated non-goal). The portable substitute for each owner guard is its
**mechanism, default-empty**: origin-vs-destination divergence (not the named orgs); repo-is-kbg (not
is-this-KOBIG); per-repo-only arming (not the owner's `defaultMode`). Each fails closed when the installer
has configured nothing.

**Present-tense (ships before any machinery):** the only live installer footgun is documentation — bare
`KBG_AUTONOMY` is read by **zero** shipped lines (every predicate keys on `KBG_AUTONOMY_L3`), yet
`env-vars.md` presented it as the live arming knob. Fixed 2026-06-22 (`env-vars.md` §"Where to set them"
note). Everything else here is **DESIGN-ONLY** (ADR 0004/0005 Accepted-not-Implemented; `audit.sh` has no
#43-#48; `recursive-improve` keeps `disable-model-invocation: true`) — Slice-0/4 build preconditions, not
shipped behavior.
