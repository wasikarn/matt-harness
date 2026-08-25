# Cyclomatic complexity tooling and metric validity — research

**Date:** 2026-08-26 · **Trigger:** Operator asked whether this harness had any surface managing
code complexity (it did not), then asked for a drill-down before building one. · **Method:**
`deep-research` workflow run `wf_2eb743e4-16b` (107 agents, 5 angles, 25 sources fetched, 113
claims extracted, 25 verified by 3-vote adversarial panels → 22 confirmed / 3 refuted / 0
unverified). Tool defaults independently re-verified by running `lizard` 1.24.0 locally; the
arXiv preprint's peer-review status re-checked directly against its abstract page.

**Outcome:** shipped `skills/review/complexity-check` (v0.68.499 → v0.68.501). This file is the
evidence behind that skill's design choices, kept so the survey does not have to be re-run.

---

## 1. Tool landscape and documented defaults

| Language | Tool | Default threshold | Gating mechanism |
|---|---|---|---|
| Python | `radon` | A–F letter grades (A = 1-5 … F = 41+) | reporting only |
| Python | `xenon` (radon wrapper) | none; `-b`/`-m`/`-a` set per-block / per-module / average | non-zero exit |
| JS/TS | ESLint `complexity` rule | **max 20** | lint error |
| JS/TS | `eslint-plugin-sonarjs` cognitive-complexity | **max 15** | lint error |
| Go | `gocyclo` | **none** — `-over N` only, caller must choose | non-zero exit |
| Go | `gocognit` | none; `-over N` | exit 1 |
| 27 languages | `lizard` | **CCN 15** (`-C`) | non-zero exit |
| Multi | CodeClimate / Qlty | proprietary, cognitive-style | platform gate |

**Cross-tool finding (high confidence, 4 primary sources):** every dedicated complexity CLI
converges on the same wiring — filter to over-threshold functions, return non-zero exit. **None
is inherently advisory.** Blocking vs advisory is entirely a property of how the caller treats
that exit code. This directly corrected a wrong claim in the first version of the shipped skill.

`gocyclo`'s "no default threshold" is worth noting: a WebSearch summarizer asserted a default of
9; the verifier checked the CLI source, found a hardcoded 0 (no filtering), and killed the claim
as fabricated.

## 2. Metric validity — the part that should govern policy

**Cognitive complexity is not better than cyclomatic complexity, or even than plain LOC**, for
predicting code understandability. Two independent peer-reviewed studies agree:

- *Journal of Systems and Software* 197 (2023), Muñoz Barón et al. follow-up: models using
  Cognitive Complexity perform "extremely close to" models using only traditional measures; the
  metric "does not appear to fulfil the promise of being a significant improvement."
- ESEM '20 (arXiv:2007.12520): meta-analysis, 10 studies / 427 snippets / ~24,000 human
  evaluations.

**Cyclomatic-derived features are weak defect predictors.** arXiv:2504.00477 (2025) reports the
best-performing feature set at ~0.55–0.58 accuracy with **24–30% recall on the faulty class** —
barely above chance, missing most real defects. **Caveat, load-bearing:** this is a preprint with
no journal reference (verified directly on the arXiv abstract page — arXiv DOI only), one
classifier (linear-kernel SVM), one split. Treat as illustrative, not established. An earlier
draft of the shipped skill mis-cited this as "peer-reviewed"; that was wrong and was corrected.

Contrarian corroboration: Shepperd's classic critique found LOC outperformed v(G) in over a third
of validation studies surveyed; arXiv:1912.04014 measured cyclomatic complexity alone at adjusted
R² = 0.195 across 3,659 subroutines.

**Design consequence:** a metric this noisy does not justify blocking a commit. The shipped skill
is advisory by explicit design, enforced mechanically via `lizard -i -1`.

## 3. Prior art in the agent-harness ecosystem

The research pass found **no confirmed evidence** that Claude Code plugins or comparable harnesses
ship a first-class complexity gate — but this was an absence-of-evidence result (0 confirmed
claims either way), so it was followed up manually. That follow-up **did** find real prior art:

- **paulmduvall.com (2026-02-24)** — a genuine Claude Code `PostToolUse` hook that blocks on code
  smells. Python via stdlib `ast` (six checks, zero deps); JS/TS/Java/Go/Rust/C/C++/C# via
  `lizard` (three checks — no nesting depth, which needs language-specific AST). **CC threshold
  10.** Returns `{"decision":"block"}`. Blocks on pre-existing violations in files Claude didn't
  author — deliberate, and the author flags it as surprising. Fails open if the hook crashes.
  *Verified against raw HTML, not just a WebFetch summary.*
- **ECC `codehealth-mcp`** — CodeScene MCP, 1–10 structural health scores, pre-commit and PR
  gates. Not adopted: needs an external MCP server plus an access token.
- **ECC `plankton-code-quality`** — PostToolUse linter bundle including flake8-mccabe `C901`.
  Not adopted: requires copying a whole hook directory and config set per repo.
- Two other candidate sources (`aiproductivity.ai`, a dev.to husky guide) were fetched and
  **refuted** — neither actually covers complexity metrics, despite ranking for the query.

## 4. What was refuted

Three claims were killed by the adversarial panel and are worth not re-introducing:

1. That CodeClimate implements a formal four-mode blocking/advisory gate system (0-3 votes).
2. Two mischaracterisations of SonarSource's own cyclomatic-vs-cognitive framing (1-2 and 0-3).

## 5. Open questions

- No study found comparing complexity-metric predictiveness for **AI-generated** vs human-written
  code specifically. All validity evidence above is from general SE literature.
- No data on real-world false-positive/override rates when these documented defaults are used as
  hard CI gates.
- Given cognitive complexity measures no better than cyclomatic or LOC, whether a separate Sonar
  plugin dependency is justified over a linter's built-in rule is unresolved.

## Sources

Primary: radon, xenon, ESLint `complexity`, eslint-plugin-sonarjs, gocyclo, gocognit, lizard,
Qlty/CodeClimate docs; SonarSource cognitive-complexity whitepaper; JSS 197 (2023);
arXiv:2007.12520, 2504.00477, 1912.04014, 1912.01142, 1408.4523; Shepperd's critique.
Secondary/blog: paulmduvall.com, getdx.com. Full per-claim vote records in the workflow journal
for run `wf_2eb743e4-16b`.
