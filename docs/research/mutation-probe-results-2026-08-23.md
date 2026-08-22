# Mutation-testing probe — results (2026-08-23)

Executes the plan approved 2026-08-23 (probe ladder from
`mutation-testing-deterministic-verifier-2026-08-23.md` §4, revised after kbg:plan-reviewer
found 6 High blockers). Everything ran in `.scratch/mutation-probe-2026-08-23/` on skeleton
copies; no tracked file was mutated.

## Reproducibility header

| Item | Value |
|---|---|
| Repo commit | `9fbfcfa776824eb7a59aacce7a8bad92bc81cad9` |
| Engine | `mutation_test` 1.8.0 (dart pub global activate mutation_test; dart 3.12.2) |
| Rules | `rules.xml` (Python, 15 rules), `rules-bash.xml` (bash, 15 rules) — committed alongside this doc |
| Invocation | from probe root: `mutation_test -r <rules> -f md -o <report-dir> <input>.xml` (working-directory="." pinned in every `<command>`) |
| SUT shasums | memory-lint.py `1ea3051c…`, verify-preserved.py `9e3c018a…`, test_memory_lint.py `96748fb2…`, test_verify_preserved.py `7435d10c…` (full values in `shasums-baseline.txt`, copies verified byte-identical to tracked originals before each run and re-verified restored after) |

## Phase A — engine selection (evidence, not assertion)

**mutmut 3.5.0 rejected on demonstrated failure:** it DID mutate the dash-named file (2,734
mutants generated) and the module-key bridge (renaming the test's synthetic
`spec_from_file_location` name to `skills.memory-lint.scripts.memory-lint`) fixed key matching —
but per-test attribution never populated: all 2,734 mutants classified "no tests" and zero test
runs executed. mutmut's test-selection model cannot attribute coverage through a
`spec_from_file_location` + `__main__`-driven suite. Exact config and error preserved
(`pyproject.toml` in the probe dir).

**domohuhn/mutation-test 1.8.0 adopted.** Curated rules; `--rules` drops builtin rules (and
builtin excludes — restated locally). Exclusions: strings, comments/docstrings, print/echo
lines (the verified ~27%-FP string-mutation lesson), `while` conditions (hang guard).

## Phase B — harness self-checks (all passed)

- Baseline double-runs: every suite exits 0 twice on unmutated copies (memory-lint, verify-preserved, test-gates, test-worktree-guard).
- Kill-direction meta-check: lines-scoped run on `memory-lint.py:248` (`and`→`or` in `collect_state`) — killed; SUT restored (shasum verified).
- Bash smoke-kill: `irrecoverable.sh:26` fast-path `exit 0`→`exit 2` — killed by the gates suite. (The first smoke target `:433` survived — no test triggers the internal-error branch. It is NOT a harmless survivor: the triage later proves it a real fail-open; see findings.)
- Survivor-direction: the verify-preserved positive control produced the predicted survivors (below).

## Phase C/D — Python probe results

| SUT | Mutants | Killed | Survived | Timeouts | Wall time |
|---|---|---|---|---|---|
| memory-lint.py (1,520 ln, 30-test suite) | 160 | 107 (67%) | 53 | 0 | 67s |
| verify-preserved.py (163 ln, 10 asserts) | 21 | 2 | 19 (90%) | 0 | 0.7s |

### verify-preserved.py triage (19 survivors, agent-triaged + re-run-verified)

- **2 weak-oracle (real):** `diff_counts` L106/L109 — the predicted `test_verify_preserved.py:53`
  `is not None`-only assert lets flipped missing/added logic through. Missing asserts: exact
  `missing`/`added` values.
- **15 not-covered:** the entire fence-close body of `extract_code_blocks` (no fenced input in any
  assert) and ALL of `main()` (never invoked — `__main__` guard false under import, no E2E test).
- **2 FALSE survivors (engine over-report):** L51 and L102 were re-run manually and are actually
  killed. Measured false-survivor rate here: 2/19 (~10%). See Engine caveats.
- Highest-value fix: one fenced-input assert kills 6 of 7 fence-branch survivors; `main()` needs a
  subprocess E2E test, not asserts.
- Verdict: the 90% headline overstates oracle weakness — the real story is **coverage** (15
  not-covered), plus 2 genuine weak oracles.

### memory-lint.py triage (53 survivors, agent-triaged with 6 empirical re-runs + 1 independent spot-check)

**Counts: 37 not-covered · 13 weak-oracle · 2 equivalent · 1 false-survivor.**

The dominant gap is coverage, concentrated in ONE feature: the entire `--auto-archive` action
path (`class_b_near_budget_collapse`, `class_c_dangling_link_rewrite`, `apply_action_plan`,
`print_plan`, `run_action_mode`) = 30 of 37 not-covered survivors; the other 7 are
staleness-advisory, `run_detector` text output, and the `--classify-unindexed` CLI path.

Top weak-oracles (each names its missing assertion):

1. **L777 ×2 — fold-attribution truthy-only** (`_git_fold_commits`): `or`→`and` flips that credit
   added/context diff lines as folds survive, because tests only truthy-check the fold sha, never
   assert WHICH commit/lines. Fold attribution is `--classify-unindexed`'s whole safety claim.
2. **L468 — stopword filter inversion** (`_tokenize`): keep-ONLY-stopwords tokenizer passes the
   full suite. **Independently re-verified by hand this session** (mutant applied → 30/30 tests
   green → restored, baseline green). Missing assert: a pair sharing only stopwords must not
   surface as a contradiction candidate — this guards the documented 296-false-candidates
   regression the filter exists to prevent.
3. **L452/L454 — symmetric fixture** (`template_compliance_findings`): the 1-with/1-without Why/How
   fixture yields count=1 under the inverted condition too; needs an asymmetric fixture.
4. Boundary flips at exact thresholds survive across the file (`pct >= 80` L349, `overlap >=`
   L515, `>= 2` L623, `remaining <=` L1199 ×2): no fixture sits exactly ON any threshold.

Equivalent: L1180 ×2 (guard at L1175 already returned; state unreachable — argued and verified).
False survivor: L713 (`capture_output=True→False`) — straight re-run kills it; engine
over-report, consistent with the verify-preserved false-survivor pair.

## Phase E — bash/gate probe results

Gate opened on evidence: verify-preserved's 90% survival control + confirmed weak oracles in
Phase C. Per-SUT preconditions all passed (baseline double-runs; smoke-kill `irrecoverable.sh:26`
`exit 0`→`exit 2` killed by the suite).

| SUT | Rules | Mutants | Killed | Survived | Timeouts | Wall time |
|---|---|---|---|---|---|---|
| worktree-guard.py (498 ln, via test-worktree-guard.sh) | python | 111 | 54 (49%) | 57 (51%) | 0 | 2m50s |
| irrecoverable.sh (435 ln, via test-gates.sh) | bash+python combined — its core matching is a Python heredoc | 159 | 75 (47%) | 84 (53%) | 0 | 22m35s |

Engine note: combining `-r rules-bash.xml -r rules.xml` requires exactly one `<threshold>`
element across all inputs — the bash rules file carries none for this reason.

### worktree-guard.py triage (57 survivors — the probe's headline finding)

**Counts: 17 gate-critical weak-oracle · 11 weak-oracle · 27 not-covered · 2 equivalent ·
0 false-survivor.** Every gate-critical classification was empirically PROVEN fail-open: the
agent crafted fixtures and ran original-vs-mutant — original exits 2 (deny), mutant exits 0
(allow) — and re-ran all 17 through the full suite (all genuinely survive).

**The 17 proven fail-open mutants, clustered:**

| Cluster | Lines | Proven bypass scenario (no test covers it) |
|---|---|---|
| `classify()` core worktree/branch logic | 367 ×3, 369 ×2 | (a) main checkout on a NON-protected branch treated as safe worktree → ALLOWED — defeats the gate's whole one-repo-one-tree premise; (b) a worktree ON `develop`/`main` inside the workspace → ALLOWED. Every fixture repo sits on develop/main and every fixture worktree lives outside `$WS`, so nothing catches inversion of either condition. |
| `sed` in-place detection | 225, 230 | `sed --in-place 's/…/…' <file>` (GNU long form) and `sed -i -e 's/…/…' <file>` (routine `-e` form) both ALLOWED under mutation; suite only tests short `sed -i "" "s/…/…" file`. |
| `cp/mv/install -t` family | 241, 246 ×2, 251, 252, 253 | `cp -t <protected-dir> src`, glued `cp -t<dir> src`, combined `cp -at <dir> src` → ALLOWED; no `-t` variant tested. |
| `tar` extraction | 274 ×2, 275 | `tar -x -C <protected-dir>` and `tar xf /external.tar` with protected cwd (implicit `.` target) → ALLOWED; suite's tarball lives inside the repo, masking the cwd case. |
| `dd` | 330 | `dd if=… of=<protected-file>` → ALLOWED; dd never tested. |

Non-critical remainder: 27 not-covered (mostly untested idioms whose backstops still deny —
verified by ~30 direct probes — plus unreached error paths), 11 weak-oracle (over-deny or
message-only effects), 2 equivalent (`git_ok` capture/text flags).

Missing tests named by the triage: sub-repo on branch `feature` expect deny; `worktree add` on
`develop` inside `$WS` expect deny; worktree on non-protected branch inside `$WS` expect allow;
`sed -i -e`, `sed --in-place`, `cp -t`/`-at`/glued, `tar -C` + external-tarball, `dd of=` cases.

### irrecoverable.sh triage (84 survivors)

**Counts: 56 gate-critical (36 fail-open · 17 fail-closed · 3 gate-hang/infinite-loop) ·
9 weak-oracle · 16 not-covered · 3 equivalent · 0 false-survivor.**

**Verification asymmetry — read the headline with this caveat.** Survival of all 84 is
established by the engine's per-mutant full-suite run. Independent full-suite re-verification
covered **19 of the 56 gate-critical** (18 by the triage agent + line 433 re-run by me this
session directly) — all 19 survived, 0 false. The other **37 gate-critical rest on the engine
report + ~260 targeted single-input probes, not an independent full-suite re-run** — carrying the
residual false-survivor risk measured elsewhere in this probe (0/17 worktree-guard, 2/19
verify-preserved ≈ up to ~10%). So "56" is an upper bound; "≥19 proven" is the floor.

**Grounding the class (verified by me this session):** the unmutated gate correctly denies
`sudo rm -rf`, `env FOO=1 rm -rf`, `nice -n 5 rm -rf`, `git -c core.hooksPath=/evil commit`,
`git branch -D foo`, and a non-string `command` payload (all exit 2). **`test-gates.sh` contains
ZERO occurrences** of `sudo`, `env`/`nice`, `xargs`, `docker exec`, `core.hooksPath`, `branch -D`,
or a list-valued `command` — grep-confirmed. So each of these deny paths works today but has no
test holding it: a mutation that breaks one survives silently. Line 433 (`exit 2`→`exit 0`,
fail-closed backstop) live-fired: a non-string `command` payload flips baseline exit 2 → mutant
exit 0 (**fail-open**), and the full suite still passes.

Highest-severity clusters (all fail-open unless noted):

| Cluster | Lines | Untested bypass |
|---|---|---|
| Internal-error backstop | 431, 433 | any gate crash (non-string `command` → Python `AttributeError`) → ALLOW. **Live-verified.** |
| Prefix-wrapper unwrap | 152–207 (17 fail-open + 3 gate-hang) | `sudo`/`env`/`env -u`/`nice`/`xargs`/`docker exec`-wrapped `rm -rf` → ALLOW; the `argv0,rest` `=`→`!=` mutants (165b/175b/182b) hang the gate in an infinite loop |
| `-c core.hooksPath=` bypass | 236a/236d/237b/239 | the `--no-verify`-equivalent hook-bypass → ALLOW; zero coverage |
| review-pr allowlist revival | 405/406a/406b | mutation revives dead-code allowlist → `git worktree add --detach -b evil /tmp/review-pr-1` → ALLOW |
| `git branch` force-delete | 328/329×3/330 | `git branch -D` / `--delete --force` → ALLOW (fail-open); legit `git branch newbranch` → over-block (fail-closed) |

17 fail-CLOSED mutants (over-block legit input: `find . -name x`, `git checkout -q other`,
`git stash list`, `dd if=/dev/zero of=/tmp/x`, worktree-add in sentinel-less non-kbg repos) are
lower-risk (annoyance, not a security hole) but equally untested.

**Compliance-audit correction (2026-08-23, fresh-context verifier):** the precise 36-fail-open /
17-fail-closed split among the 37 un-re-verified gate-criticals is NOT reliable — "survives the
suite" (established) ≠ "fail-open" (a separate targeted-probe determination the triage did not
independently confirm for all members). An audit verifier tested the `i=0`→`i!=0` wrapper-unwrap
mutants the triage labeled fail-open (152 env, 167 nice, 177 sudo) and found them **fail-CLOSED**
in the single-command case: unbound `i` → `NameError` → the 431/433 backstop fires → exit 2. The
triage's fail-open label for those rests on a "multi-window global-`i` persistence" precondition
never independently reproduced. **What IS independently confirmed:** the wrapper-unwrap fail-open
CLASS is real — the same verifier reproduced line 180 (`>=`→`<`, sudo-unwrap) as a true fail-open
(`sudo rm -rf` baseline deny → mutant ALLOW, full suite still green). Treat "36 fail-open" as an
upper bound on the un-re-verified 37; the ≥19 full-suite-re-verified floor stands, and the
untested-deny-path gap (the actionable finding) is unaffected either way.

Note the 3 equivalents (258a/258b/280) and 16 not-covered non-critical (crash-to-backstop edges
that preserve fail-closed) — real survivors, no action needed.

## Engine caveats (measured, reproduce-able)

1. **Two-strings-per-line rule silencing:** a line containing ≥2 double-quoted strings silences
   some literal rules on that line (reproduced minimally: `z = a != "X" and b != "Y"` yields only
   the `and` mutant; the same `!=` fires on one-string lines). Effect: under-sampling on
   string-heavy lines, not wrong results. Comparison mutants still fired file-wide (19 in
   memory-lint).
2. **False survivors:** 2/19 verify-preserved "survivors" are killed when re-run manually —
   survivor lists must be spot-verified before acting on them. Kill results were consistent
   everywhere checked.
3. Kill-rate is inflated by trivially-dying syntax-invalid mutants (text-level engine) — survivors
   are the actionable metric, kill % is secondary by design.

## Verdict & recommendation

**The probe paid for itself.** Across 4 SUTs (451 mutants) it surfaced defects no line-coverage
number would show — the strongest being in the two safety-critical gates, which is exactly where
Uncle Bob's "score, not read" thesis predicts weak oracles hide.

| SUT | Survived | Real weak oracles / fail-opens | Headline |
|---|---|---|---|
| memory-lint.py | 53/160 | 13 weak-oracle | 37 not-covered concentrate in ONE untested feature (`--auto-archive` action path) |
| verify-preserved.py | 19/21 | 2 weak-oracle | mostly coverage (fence body + `main()`); the predicted `:53` oracle confirmed |
| worktree-guard.py | 57/111 | **17 proven fail-open** | `classify()` core + `sed -e`/`--in-place`, `cp -t`, `tar -C`, `dd` idioms allow writes to protected checkouts, untested |
| irrecoverable.sh | 84/159 | **≥19 fail-open (56 reported)** | wrapper-unwrap, `-c core.hooksPath`, `git branch -D`, and the fail-closed backstop itself all untested |

**The finding that matters most:** both deny gates — the harness's own computational safety layer,
the thing CLAUDE.md calls the verifier the model can't argue with — have real, proven paths where
a destructive command is ALLOWED and no test notices. That is the highest-value class of defect a
harness can carry, and mutation testing found it where the existing green suite reported success.

**Recommendation (operator's call):**
1. **Fix the gates first** (highest severity, both hand-verified). Add the missing deny tests named
   above — start with the `irrecoverable.sh` internal-error backstop (finding #1: one malformed
   non-string `command` payload asserting exit 2) and the `worktree-guard.py` `classify()` branch
   cases, then the wrapper/idiom bypasses. Each is a small test addition; the gate code itself
   appears correct today — the gap is coverage, so mostly no gate-logic change is needed.
2. **Re-verify the 37 un-re-run irrecoverable gate-criticals** before acting on any single one
   (residual ≤10% false-survivor risk); the 19 proven ones are safe to act on now.
3. **Promote-or-park the harness:** PARK recommended. The probe is a periodic hand-run, not a
   gauntlet gate — the engine is a 26-star third-party dep, kill-% is noisy (text-level mutants),
   and per-SUT wall time (irrecoverable 22 min) is too slow for pre-commit. Its value is the
   one-time audit it just delivered. Re-run the committed XMLs against the gates after any gate
   edit. Promotion to a `scripts/` surface would be a separate, version-bumped change.

**Engine verdict:** domohuhn/mutation-test 1.8.0 is fit for a periodic probe with two documented
caveats (string-line rule silencing → under-sample; ~≤10% false-survivor → spot-verify before
acting). mutmut was the wrong tool here for a demonstrated reason, not a guessed one.

## Open items

- **Gate deny-test gaps (actionable):** irrecoverable.sh — internal-error backstop (431/433,
  non-string `command`), all prefix wrappers (`sudo`/`env`/`nice`/`xargs`/`docker exec`),
  `-c core.hooksPath=`, `git branch -D`; worktree-guard.py — `classify()` branch/worktree cases,
  `sed -e`/`--in-place`, `cp -t`, `tar -C`, `dd of=`. Each closes a proven fail-open.
- **memory-lint.py:** the `--auto-archive` action path (30 survivors) has no test at all; the
  `_git_fold_commits` fold-attribution (L777) is truthy-checked but never value-asserted.
- Re-verify the 37 un-re-run irrecoverable gate-criticals before acting individually.
- Reproduce anytime: `mutation_test -r <rules> -f md -o <out> <input>.xml` from a fresh skeleton
  copy at the recorded commit, using the XMLs in `mutation-probe-2026-08-23/`.
