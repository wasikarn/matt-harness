# matt-harness whole-repo gap audit — 2026-09-20

Ran 5 parallel senior-lens agents (test-coverage, silent-failure, cross-file blind-spot,
schema/type-design, process/instrumentation) across the whole repo, not a single diff, each
required to name evidence-backed gaps and propose a closing design. Preceded by a clean
`mh:harness-audit` run (0 critical, 0 warnings — that check doesn't cover any of what follows,
it audits structure, not runtime behavior). All findings below are evidence-backed (grep,
live execution, or git history) — none are speculative.

## CRITICAL — fix first

### C1. `hooks/gates/irrecoverable.py` nested-spawn scanner: DoS bypasses the entire gate

**File:** `hooks/gates/irrecoverable.py:179-246` (`_nested_spawn()`), gated by `hooks/hooks.json:70`
(8s timeout).

A command consisting of many unclosed `claude (` anchors makes `_nested_spawn`'s char-by-char
scan run to end-of-string for every anchor — O(anchors × remaining-length), and **not bounded
by the existing 150,000-char length cap**. Live-reproduced:

```
n_anchor=300  time=7.463s
n_anchor=330  time=8.254s  ← exceeds the gate's own 8s hooks.json timeout
n_anchor=400  time=9.735s
```

Confirmed against Claude Code's own docs (fetched 2026-09-20): *"On PreToolUse, a timed-out
command hook lets the tool call continue"* — fail-**open**, not fail-closed. `_nested_spawn` runs
*before* every destructive-pattern check in the same file (`rm -rf`, `git push --force`,
`git reset --hard`, SQL `DROP`, all ~line 486+). A padded command that also contains a real
destructive payload would skip the entire gate for that call, not just the nested-spawn check.
This is the gate `docs/reference/operating-model.md:7` calls "the only place a rule is a
guarantee instead of a hope."

**Closing design:** add a shared work-budget counter to `_nested_spawn`'s token loop — the same
pattern `_blank_substitutions` already uses (`_DEPTH_SCAN_BUDGET`/`_DEPTH_BUDGET_BLOWN` at
~line 513) — and `deny("could not safely scan for a nested spawn — command too complex")` when
exhausted, instead of returning a bare `False`. Do this before touching the hooks.json timeout
value; raising the timeout alone doesn't fix an unbounded scan, it only moves the threshold.

## HIGH

### H1. `scripts/_lib/weighted-score.py`: `passThreshold`/`floorPct` unvalidated — Rule-14 scoring fails open
**Triple-confirmed independently** (live execution twice, static schema reading once — highest
confidence finding after C1). `floorPct`/`passThreshold` (lines 128, 167) skip the bool/finite
guard already applied to `score`/`max`/`weight`/`perturb`. Live-reproduced: `passThreshold:
-Infinity` makes a 1/10 score report `pass: true`; `floorPct: NaN` makes the floor check never
trip; `passThreshold: true` silently becomes a threshold of 1 (bool-as-int). This is `mh:deep-audit`
and `mh:idea-audit`'s sole arithmetic authority for a Final Verdict.
**Fix:** apply the existing numeric/finite/non-bool guard (already written for `perturb` at
lines 89-91) to `floorPct` (require `0 ≤ floorPct ≤ 1`) and `passThreshold` (require finite,
non-bool) immediately after they're read.

### H2. Same file: `score` not bounded to `[0, max]`
A `score: 15, max: 10` entry passes every existing check and inflates the ratio past 1.0 into
the total. **Fix:** `if not (0 <= s <= m): _die(...)` in the per-item validation loop, alongside
the existing `max <= 0` check.

### H3. `hooks/gates/irrecoverable.py` SQL destructive-statement check: 0 test coverage for 3 of 4 clients
The `mysql|psql|sqlite3|mariadb` / `DROP TABLE|DATABASE|SCHEMA|TRUNCATE` guard has tests only for
`mysql` + `DROP TABLE`. A regression dropping `"psql"` from the tuple, or a `TRUNCATE` regex
regression, ships silently. **Fix:** add `test_deny` cases for `psql`, `sqlite3`, `mariadb`,
and `TRUNCATE`, mirroring the existing mysql case.

### H4. Same file: the malformed-JSON-with-dangerous-substring fail-closed branch is never exercised
`irrecoverable.py`'s own docstring documents a two-layer contract (`.sh` allows on malformed
stdin with no destructive token; `.py` denies on malformed `tool_input`) but no test fixture ever
reaches the python layer with malformed JSON that *also* contains a candidate substring — the
one test for malformed stdin has no destructive token in it, so it never leaves the `.sh` fast
path. **Fix:** add a truncated-JSON-with-`rm -rf` fixture asserting exit 2.

### H5. `hooks/gates/codex-setup-guard.py`: zero test coverage of any kind
Guards ADR-0001's deliberate decision to keep the Stop-time LLM-judgment review gate disabled.
No test file exists anywhere in `tests/`. **Fix:** new `tests/hooks/test-codex-setup-guard.sh`,
same shape as `test-config-write-guard.sh` (ask on `--enable-review-gate`, allow otherwise,
allow on non-`codex:setup` skill, allow on malformed stdin).

### H6. `hooks/stop/memory-audit-commit.sh`: swallows git add/commit failures silently
Both `git add`/`git commit` redirect stderr and never check exit codes. If any commit
precondition fails (missing `user.name`, GPG signing unavailable, a stale `index.lock` from a
concurrent session — this repo documents running concurrent sessions on a shared tree), the
memory store silently stops being versioned, forever, with no signal until someone needs the
rollback this hook exists to provide. No test file exists for this hook. **Fix:** check both
exit codes; on failure, write a marker file with the captured stderr, surfaced by the existing
`memory-health-nudge.sh` at next SessionStart.

### H7. `hooks/stop/cost-tracker.sh`: jq failures indistinguishable from the legitimate empty case
`usages=$(jq ... 2>/dev/null) || usages=''` produces identical output whether a session
legitimately ran no priced turns, or `jq`'s filter broke. Cost data is inherently unverifiable
by the operator in the moment, so a broken filter could silently zero out spend tracking for an
arbitrary stretch. No fixture test exists. **Fix:** capture jq's exit code separately; on
nonzero, emit a stderr diagnostic or a `{"error": "jq_failed", ...}` sentinel row.

### H8. G1 ("price the third handoff cost") measurement is now permanently unreachable
`docs/research/delegation-criteria-field-survey-2026-09-04.md`'s top-priority gap — every open
question about handoff caps, model downgrades, and routing thresholds waits on this number. The
`verify_tokens` field it depends on was added at `6603c384` and **removed one commit later** at
`2cac98c8` (v1.1.0, 2026-09-05) — the same commit that also removed the `[role:]` orchestrate
tag (already known from the Jev-adoption-revisit pass earlier today). Two separate measurement
pipelines died in the same commit. **Fix:** `git show 6603c384` and restore the deleted diff —
this is a revert, not new work. If the question no longer matters, close it explicitly in
`docs/decision-log.md` instead of leaving the gate silently unreachable.

**Correction (2026-09-21):** "removed one commit later" is wrong — `git rev-list --count
6603c384..2cac98c8^` is 42 commits, ~45 h apart (2026-09-04 01:24 → 2026-09-05 22:13). The
add/remove pair and the conclusion stand; only the distance was overstated.

### H9. `skill-usage.jsonl` telemetry dark for 15 days repo-wide
Removed at `a1055f64` (v1.0.1, 2026-09-05), justified as "`/skill-doctor` covers it" — but
`/skill-doctor` (a real CC v2.1.261 feature) appears to be per-session, not the persistent
cross-session log MEMORY.md's own usage claims depend on. Zero rows since 2026-09-05T14:26:54Z.
**Fix:** restore `skill-usage-telemetry.sh` (44 lines, in git history) as a durable cross-session
log independent of `/skill-doctor`.

## MEDIUM

- **M1.** `deep-audit`'s checker schema: `pass:true` isn't cross-checked against `scope_ok`/
  `unexpected_files` — `{"pass":true, "scope_ok":false, "unexpected_files":["secrets.env"]}` is
  schema-valid and printed unchanged. `compliance-audit`'s sibling schema already avoids this by
  never letting the verifier self-report `pass` at all. **Fix:** either drop `pass` from the
  checker schema the same way, or add the rule "`pass` must be false whenever `scope_ok` is false
  or `unexpected_files` is non-empty" to `check-verdict.py`.
- **M2.** `idea-audit`'s attacker schema has **no** enforcement script at all — deep-audit's
  byte-identical `{pass, findings[], checked[]}` shape gets a full `check-verdict.py`; idea-audit's
  gets only prose in SKILL.md. **Fix:** copy `deep-audit/scripts/check-verdict.py` to
  `idea-audit/scripts/check-verdict.py` — the code to copy already exists and is tested.
- **M3.** `compliance-audit` verifier: `accepted:true` is self-reported with no schema-level
  citation requirement (SKILL.md demands one in prose only). **Fix:** require `note` to carry a
  citation shape whenever `accepted:true`, reusing idea-audit's own citation regex.
- **M4.** Same schema: `verdict` enum has no "cannot verify" state, forcing a guess on genuinely
  ambiguous requirements. **Fix:** add `UNVERIFIABLE`, treat like `MISSING` in `compute_pass`.
- **M5.** Same schema: `gauntlet.command`/`sha`/`output_tail` accept empty strings — a schema-valid
  "green" gauntlet with zero receipts. **Fix:** add `"pattern": "\\S"` (codex-structured-output-safe,
  unlike `minLength`) to each field; validate `sha` against the host's pinned commit.
- **M6.** checker/attacker `findings[]`/`checked[]`: `summary`/`evidence`/`claim` accept empty
  strings — the vacuous-accept class `minItems:1` was added to close, one field down. **Fix:**
  same `pattern: "\\S"` treatment.
- **M7.** `irrecoverable.py`'s `_mid_merge()` swallows any exception (git missing, permission
  error, its own 3s timeout) and returns `False`, producing a misleading "not mid-merge" deny
  reason that's indistinguishable from a genuine non-merge state. **Fix:** one stderr line inside
  the `except` naming that the check itself failed.
- **M8.** `cost-tracker.sh` has no `$HOME` guard before `mkdir -p`/append, despite this exact
  failure class already having bitten the repo once (`.gitignore`'s own documented incident,
  2026-08-28) and a sibling script (`hooks/gates/_journal.py`) already carrying the fix. **Fix:**
  port `_journal.py`'s guard (skip metrics if `$HOME` unset/non-absolute).
- **M9.** `memory-health-nudge.sh`: a genuine `memory-lint.py` crash is detected internally but
  never surfaced — the hook exits silently with no message, indistinguishable from "clean."
  **Fix:** print one line to session context when a crash is detected.
- **M10.** `hooks/gates/test-integrity.py`: an unreadable pre-existing test file on the `Write`
  path silently **allows** — inconsistent with this same file's own outer handler (ask on any
  other unclassifiable case) and with sibling gate `config-write-guard.py`'s explicit precedent
  (unreadable original = ask). **Fix:** change to `emit_ask(...)`.
- **M11.** `subagent-git-guard` missed a hardening fix (truthiness→presence check on `agent_id`,
  removal of a bypassable raw-text fast path) that its two named siblings
  (`subagent-spawn-guard`, `task-complete-separation`) received in the same commit window —
  confirmed via git archaeology, one commit even touched this file for an unrelated reason and
  still missed it. No live-payload evidence the gap is currently exploitable, but it's a silent
  allow with no test coverage of the empty/null/escaped-key shape. **Fix:** `if "agent_id" not in
  d` (matching siblings); add a `harness-audit` check that greps all three gates for the fixed
  pattern so the "three subagent-scoped gates, one posture" invariant in `operating-model.md`
  becomes mechanically checked instead of just stated.
- **M12.** `mh:idea-audit` and `mh:ste-lint` are deliberately excluded from `plugin.json`'s
  shipped skill list (confirmed via `claude plugin details mh@wasikarn` — 10 skills, not 12), but
  `README.md`, `docs/reference/codex-integration-map.md`, and 5 eval-test assertions still
  reference them as live, invocable skills under `mh:` ids that resolve to nothing on any other
  installed copy. Works only on this machine because of a local symlink under a *different* id.
  **Fix:** add a `harness-audit` check cross-referencing `plugin.json`'s skill list against every
  `mh:<name>` reference in docs/evals/tests; correct the two docs; re-add or retarget the 5 evals.
- **M13.** `rank.py` (ideate): zero validation against its own documented stdin/stdout contract —
  weakest of all five audited contracts (2/10 enforcement). Out-of-range scores, bool-coerced
  values, and a falsy-but-meaningful empty-string `trap` all pass silently. **Fix:** port
  `weighted-score.py`'s `_die`-style guards; change `trap` check to `is not None`.
- **M14.** The `harness-coverage` gap-detection mechanism that would have caught H8/H9 (a 12-cell
  `populated`/`intentional_gap`/`coverage_hole`/`stale` grid) was built and shipped once at v0.2.4
  (2026-06-16), then lost in an unrelated "reset: rebuild from scratch." A redesign doc exists
  (`docs/research/harness-coverage-metric-design.md`, frozen) but was never re-implemented — not
  a declined idea, just lost. **Fix (lazy version):** a short static list — decision / doc /
  expected mechanism / current status — for the handful of measurement-dependent gates this audit
  found, checked once per `mh:harness-audit` run. Lands in `docs/reference/`, not the frozen
  research dir.

## LOW

- checker/attacker `pass` has no "did not complete" state (verifier schema already establishes
  `["boolean","null"]` as this repo's own pattern for a real three-state field).
- `weighted-score.py` has 4 more documented-but-untested fail-closed branches (negative weight,
  `primaryId` not found, malformed score entry, empty `scores` list) — each a one-line selftest add.
- `idea-audit/scripts/check-citations.py`'s citation-shape regex accepts a numeric ratio
  (`2.5:1`) as a false-positive citation.
- SessionStart's python3-missing degradation banner names 5 of 7 fail-open gates (misses
  `subagent-spawn-guard`, `codex-setup-guard`, added after the banner text was written) — the
  word "Every" reads as exhaustive when it isn't. Fix: derive the list from `hooks/gates/*.sh`
  instead of hardcoding it.
- Eval-case count is stated as 29 in `README.md`/`operating-model.md`, actually 70 (confirmed by
  direct count) — understates coverage by more than half in the doc whose job is to state it.
- `spawn-brief.md`'s `Ruling:` marker has no consumer anywhere in the repo — same root-cause
  class as the `[role:]` tag, a different instance, never wired to anything.
- Stale `mh:handoff`-era comments in `scripts/_lib/*.sh` headers name three files/scripts that no
  longer exist (skill removed v1.1.94, correctly marked deprecated in its ADR — only the comments
  didn't follow).
- `test-eval-cases.sh`'s hard assertion that 5 idea-audit/ste-lint eval cases require `skill:
  "mh:idea-audit"` may be structurally unpassable given M12 — **unverified**, needs one real
  `claude plugin eval` run to confirm which manifest-loading branch a path target takes.
- MEMORY.md per-session load cost is still unmeasured (a gap noted in a 2026-08-07 doc), but the
  file is currently under its own soft target, so nothing is blocked today.

## Priority order for closure

1. **C1** (nested-spawn DoS) — real, live-reproduced, confirmed-exploitable gate bypass. Fix first.
2. **H1/H2** (weighted-score.py threshold + score-bound validation) — triple-confirmed, cheap fix,
   affects every Rule-14 verdict in the repo.
3. **H3–H9** — each is a small, independent, well-specified fix; no ordering dependency between them.
4. **M1–M14** — independent; M11/M12 touch gate/manifest consistency and are worth bundling with
   a new `harness-audit` check each, per their fix notes above, so the class doesn't recur silently.
5. **LOW** — batch into a single low-effort cleanup pass whenever convenient.

None of these require a one-way-door decision to fix — every proposed change is a local,
reversible code/test edit. The only genuine judgment call is H8/H9 (restore old instrumentation
vs. explicitly close the gate in `docs/decision-log.md`) and M14 (build the lazy coverage-status
list vs. accept the risk of more silent drift).
