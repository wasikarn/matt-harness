# Mutation testing as a deterministic verifier for this harness — feasibility research

**Date:** 2026-08-23 · **Trigger:** Uncle Bob agent-workflow article audit (2026-08-22, memory
`uncle-bob-fundamentals-article-audit-2026-08-22`) flagged mutation testing as the one real gap;
operator asked for deep research. · **Method:** `deep-research` workflow run `wf_6deca908-e26`
(104 agents, 22 sources fetched, 97 claims extracted, 25 verified by 3-vote adversarial panels →
18 confirmed / 7 refuted; 72 lower-ranked claims dropped by the verify cap, unverified) plus two
targeted manual sweeps (2026-08-23, first-hand source reads) for the legs where zero claims
survived, and local runtime measurements on this repo.

**Bottom line:** the core premise is verified — mutation score catches vacuous tests that line
coverage misses, which is exactly the `vacuous-test` blind-spot shape this harness currently
detects only by model judgment. Off-the-shelf tooling now covers ~48% of this repo's
deterministically-tested source lines (the Python half, via mutmut) at trivial runtime cost. The
bash half has one maintained-but-tiny language-agnostic option (regex-based) or a custom loop.
Nothing was built; this doc is the evidence base for that decision.

---

## 1. Verified findings (workflow, 3-vote adversarial verification)

### 1.1 Mutation score vs coverage — the core premise holds (HIGH confidence)

- Branch vs mutation coverage correlate **weakly to moderately** (Kendall τ 0.25 industrial,
  0.11–0.71 open-source; Parsai & Demeyer, STTT 2020, arXiv:2104.11767). The ISSRE 2023 study's
  own r=0.757 is conventionally *moderate* — the defensible phrasing is "moderate overall, much
  weaker at high coverage," not flatly "weak."
- Above ~75% line coverage, coverage becomes **a much weaker predictor of mutation score**
  (residual variance 823 vs 25 in the lowest bucket; Jain, Le Goues, Groce et al., IEEE ISSRE
  2023, arXiv:2309.02395).
- Direct confirmation of the weak-oracle failure mode: manual inspection of 26 files with >80%
  coverage but <20% mutation score found 12 with multiple missing asserts, 7 with one missing
  assertion type — and **7 false positives** (message-string/log mutations), a **~27% FP rate**
  in the signal. An echo-heavy bash gate script should expect to reproduce or exceed that FP
  rate unless string mutations are excluded from the rule set.

### 1.2 Mutation score is complementary, not a completeness guarantee (MEDIUM confidence)

29.6% of methods with a **perfect** mutation kill score (38.2% with perfect line coverage) still
contained ≥1 untested documented behavior; ≥17.5% of documented behaviors entirely untested
across ten mature Java suites (Paul & Holmes, arXiv:2606.10417 — single non-peer-reviewed June
2026 preprint, one group, Java-only, one 2–1 vote; hence medium). For this harness: a green
mutation run over the gates would still not prove every documented gate behavior has a test.

### 1.3 Python tooling status (HIGH confidence, verified against live sources 2026-08-22)

| Tool | Status | Notes |
|---|---|---|
| **mutmut** | Current (3.5.0 on PyPI) | Incremental caching, per-function test selection. Hard constraint: requires `fork()` — fine on macOS. |
| **cosmic-ray** | Current (8.7.0, Beta classifier) | Python 3.9–3.13. Classic per-mutant full-suite re-run — slowest execution model. |
| **mutatest** | Stale (~2021, Python 3.8-era) | Distinctive `__pycache__`-only mutation + coverage filtering, but not a safe pick. |

Both "cosmic-ray is the most mature / superior" claims were **refuted** (0–3, 1–2) against the
cited NSF paper's own full text — no tool ranking survives; mutmut vs cosmic-ray is a
coin-flip on evidence, so pick on ergonomics (mutmut's incremental mode).

### 1.4 Equivalent mutants — real, manageable, not automatable away (HIGH confidence)

<10% of ~18,000 manually created mutants were semantically equivalent; TCE auto-detects 16.7%
of those, TCE+ 41.5% (Straubinger, Degenhart, Fraser, ICSTW 2024, arXiv:2404.09241 — Java,
student population). **Caveat carried forward:** tool-generated mutants — the shape a scripted
flip-the-operator harness produces — historically show *higher* equivalence rates. Budget human
triage of survivors; don't promise full automation.

### 1.5 Refuted — do not cite these numbers

- All three quantified flaky-test-impact claims (5–10% score inflation; 1%-flakiness threshold;
  case-specific sensitivity numbers) — refuted 0–3 each: the quotes were misattributed to Shi
  et al. ISSTA 2019 but actually originate in FlakiMe (arXiv:1912.03197) with different numbers.
  **No reliable flakiness-impact numbers exist in this verified set** — directly relevant since
  this repo's gate tests build git fixtures and shell out. Budget empirically; quarantine-first.
- Cosmic-ray superiority claims (see 1.3).
- The "developers misclassify equivalents at 35%/65%" rate (1–2).

## 2. Legs the workflow could not answer — filled manually (first-hand reads, 2026-08-23)

The verified set was **silent** on bash tooling, StrykerJS, and agent-written-test studies
(absence of surviving claims ≠ empty space). Targeted sweeps found:

### 2.1 Bash/shell mutation tooling

No bash-specific or bash-AST-aware mutation tool surfaced in a targeted GitHub/registry sweep
(results were all unit-test frameworks — bats, shunit2 — not mutation tools). One real
off-the-shelf option exists: **domohuhn/mutation-test** (github.com/domohuhn/mutation-test,
read 2026-08-23) — language-agnostic by design: mutations are regex/literal text replacements
defined in XML, test commands run as subprocesses judged by exit code, per-command timeouts
(kills infinite-loop mutants), lcov integration to skip uncovered lines, exclusion zones
(comments, loop conditions), threshold/quality gates, html/junit/md/xml reports, self-contained
Dart binary, BSD-3. Maintained (commits through May 2026, 215 commits, CI green) but **tiny
adoption (26 stars)** — treat as "cheap trial," not "proven dependency." The honest alternative
remains a custom ~100-line mutate-and-rerun loop, which is also Uncle Bob's own stated advice
(don't download his tools; build a version fitting your repo).

### 2.2 StrykerJS for the one vanilla Node test file

Stryker's **command test runner** runs any CLI command and judges by exit code
(stryker-mutator.io/docs/stryker-js/guides/nodejs/), so `node tiered-pipeline.test.js` works —
but requires `coverageAnalysis: "off"` (all tests per mutant; irrelevant at this repo's 0.024s
suite). A `@stryker-mutator/tap-runner` exists for `node:test`. Community thresholds: high 80 /
low 60 / break 60. **Stryker only mutates JS/TS source** — it does not generalize to the bash
half. For one 255-line file, the dependency probably isn't worth it vs folding the file into
whatever loop the bash side uses.

### 2.3 CRAP score for bash (side question, not workflow-verified)

Both inputs are computable: **kcov** does line coverage for bash (multiple independent
confirmations, incl. CI usage in a Claude Code-adjacent repo); **shellmetrics**/lizard measure
CCN for shell. So CRAP-for-bash is buildable in principle. Not built; lower priority than
mutation (CRAP needs the coverage plumbing anyway).

### 2.4 Mutation testing on AI-agent-written tests specifically

Still an open literature gap — no verified study connects them (the workflow's [17]
missing-assert failure mode is exactly the vacuous-test shape agents are suspected of producing,
but no source links the two). One unverified secondary claim (augmentcode.com): vanilla-LLM
test suites reached high coverage at only 53% mutation score, mutation-feedback prompting
reached 89.5% — plausible, matches the premise, **unverified — do not cite as fact**.

## 3. Local feasibility numbers (measured on this repo, 2026-08-22)

| Surface | Lines | Test entry | Suite runtime |
|---|---|---|---|
| Python (memory-lint.py 1,520; worktree-guard.py 498; verify-preserved.py 163) | 2,181 (~48%) | `test_memory_lint.py`, `test-worktree-guard.sh`, `test_verify_preserved.py` | ~1.0s / 1.5s / — |
| Bash gates (irrecoverable, convergence-merge, verifier-protect, etc.) | ~2,114 | `test-gates.sh` + siblings | ~8.6s (test-gates) |
| Node (tiered-pipeline.js) | 255 | `tiered-pipeline.test.js` | ~0.024s |

Targeted per-file mutation (run only the covering test file per mutant) lands in
minutes-to-tens-of-minutes — e.g. ~1,000 mutants over memory-lint.py at ~1s ≈ 17 min, a few
hundred bash mutants at ~8.6s ≈ 30–60 min. **Periodic job territory, not per-commit.** The
gate tests' git-fixture setup is the flakiness risk with no verified impact numbers (§1.5) —
quarantine flaky tests before trusting survivor counts.

## 4. Recommendation (not built — operator's call)

> **Executed 2026-08-23:** the probe below was run — results, triage tables, and engine caveats in
> `mutation-probe-results-2026-08-23.md` (repro configs in `mutation-probe-2026-08-23/`). Note
> §4.1's "zero custom code" mutmut claim did not survive contact: mutmut's test-selection cannot
> attribute coverage through `spec_from_file_location`-loaded SUTs — the probe used
> domohuhn/mutation-test instead.

1. **Cheapest first probe:** `mutmut` on `skills/memory-lint/scripts/memory-lint.py` — ~33% of
   the tested surface (the Python trio combined is ~48%; this single file is ~33%), 1s suite,
   answers "do this repo's tests have weak oracles" with an off-the-shelf tool in under an hour
   of wall time.
2. **If the probe finds real survivors:** trial `domohuhn/mutation-test` over 1–2 gate scripts
   with string/echo mutations excluded (the ~27% FP lesson), before considering a custom loop.
3. **Node file:** fold into whichever loop the bash side uses; skip the Stryker dependency.
4. This updates the standing revisit trigger at `harness-coverage-metric-design.md:166` ("revisit
   when a non-model judge lands for behaviour"): the landing is now cheap for the Python half.

## Open questions (carried from the workflow)

- Real quantified flaky-test impact on mutation score (all candidate numbers refuted).
- Any direct study of mutation testing on AI-agent-written test suites (gap in the literature).

## Sources

Verified primary: arXiv:2104.11767 (STTT 2020) · arXiv:2309.02395 (ISSRE 2023) ·
arXiv:2404.09241 (ICSTW 2024) · arXiv:2606.10417 (preprint) · github.com/boxed/mutmut ·
mutmut.readthedocs.io · github.com/sixty-north/cosmic-ray · pypi.org/project/cosmic-ray ·
github.com/EvanKepner/mutatest. Manual first-hand (2026-08-23):
github.com/domohuhn/mutation-test · stryker-mutator.io/docs/stryker-js/guides/nodejs/.
Full source table, refuted-claims table with counter-sources, and per-agent journal:
workflow run `wf_6deca908-e26` (`tasks/wpti7q0f1.output`, session
`9731d795-bf01-442e-b629-9a618f3dc741`).
