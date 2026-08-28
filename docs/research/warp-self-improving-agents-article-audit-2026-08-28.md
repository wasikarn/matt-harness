# "How Warp builds self-improving agents on Claude" (Anthropic, Michael Segner) vs matt-harness

**Date:** 2026-08-28
**Source:** https://claude.com/blog/how-warp-builds-self-improving-agents-on-claude
**Verdict:** One gap, independently corroborated from three different angles by three fresh-context
forks: matt-harness collects operational feedback signal (gate-verdict journal, cost telemetry,
`mh:learn` transcript scans) but has **no loop that mines that signal and folds it back into a
skill's own file content, on a schedule, without a human re-triggering it per round.** Everything
else the article names is either a genuine match already shipped, or a narrower/partial version of
the same idea. Nothing built — this is a comparison audit only, per the user's request.

## Method

Three parallel fresh-context forks, one per article section (architecture / skill-writing tips /
Q&A table), each independently verifying claims against actual repo state (file:line citations,
not memory of what mh "probably" has). No fork saw the others' output before reporting.

## The corroborated gap

Three independent entry points converged on the same structural hole:

- **Architecture fork**: no scheduled trigger exists anywhere in the repo (`.github/workflows/
  validate.yml` is the only workflow, push/PR-triggered `plugin validate --strict`, not a
  feedback-mining job). The gate-verdict journal (`hooks/dispatch-pretooluse.py:68-93`,
  `~/.local/share/kbg/metrics/gate-decisions.jsonl`) is write-only — grepped, its only readers are
  the writer itself and its own test file.
- **Skill-writing-tips fork**: no base-skill/improver-skill *pair* mechanism exists. The closest
  analog, `skills/meta/recursive-improve/SKILL.md`, is driven by harness-audit CRIT/WARN +
  `MEMORY.md`, not by a corpus of specific human inline comments, and it revises the harness
  generically rather than pairing 1:1 with one skill's own accumulated feedback.
- **Q&A-table fork**: same write-only finding on the telemetry side (`gate-decisions.jsonl`,
  `costs.jsonl` — the latter read only for display by `mh:cost-report`, feeding no improver), plus
  a narrower version on the input side: `mh:learn` gates memory *writes* with `AskUserQuestion`,
  but nothing sanity-checks a human comment before it edits a *skill file*, because nothing lets a
  human comment edit a skill file in the first place.

Three forks, three different repo areas read, one answer. Treat this as high-confidence, not a
single agent's read.

## Section-by-section findings

### Architecture (inner/base skill + human feedback + scheduled outer/improver skill)

| Article concept | mh equivalent | Status | Evidence |
|---|---|---|---|
| Scheduled outer/improver skill mining accumulated feedback | none | **GAP** | No cron/scheduled workflow beyond `validate.yml`; `recursive-improve` is `disable-model-invocation: true`, user-triggered only, by design |
| Feedback corpus feeding the improver | gate-verdict journal | **GAP** | `hooks/dispatch-pretooluse.py:68-93` journals non-allow verdicts; zero readers besides its own test |
| Base skill / improver skill split | `recursive-improve` | **PARTIAL** | Same Observe→Propose→Ask→Act→Verify shape, but input is harness-audit+MEMORY.md not per-skill human comments, and it revises the harness broadly, not one paired base skill |
| Human merges the actual edit before it takes effect | `recursive-improve`'s mandatory `AskUserQuestion` + git discipline | **MATCH** | Step 3 gate before Act; commit/push confirm-before-push policy |
| Model shouldn't unilaterally rewrite its own governing instructions | maker≠checker crux | **MATCH** | CLAUDE.md Architecture section — same instinct, independently arrived at |

### Skill-writing tips

| Tip | Status | Evidence |
|---|---|---|
| Put extra effort into the improver skill (it's reusable) | **GAP** | No base/improver pair exists to invest in |
| Frictionless feedback capture where people work; quality > volume | **GAP** | `mh:learn` scans transcripts → memory store, never back into the skill that produced the behavior; no PR/issue-comment capture path |
| Small skills, progressive disclosure | **PARTIAL** | Doctrine genuinely adopted (`docs/skill-authoring-conventions.md:10-19` names `writing-for-agents` as canonical, near-verbatim match); practiced in 9/59 `SKILL.md` files with a `references/` subdir — real but not universal |
| Write principles, not rules | **MATCH** | `writing-for-agents/SKILL.md:61-74` (Leading words, Negation) |
| Explain the why | **MATCH** | `writing-for-agents/SKILL.md:79`; CLAUDE.md's own comment rule mirrors it for code |

### Q&A table

| Row | Status | Evidence |
|---|---|---|
| Skills vs memory boundary | **MATCH** | CLAUDE.md's memory taxonomy excludes "code patterns, conventions, architecture" from memory-eligibility; `memory-lint.py:436` draws the same line in code |
| Shared vs per-agent improver loop | **MATCH** | 15 bespoke skills under `skills/review/`, no shared scaffold — matches the article's own "a handful can each own one" threshold |
| Feedback could be wrong — sanity-check before it lands | **PARTIAL** | `mh:learn`'s `AskUserQuestion` gate + maker≠checker fresh-context verification exist, but both are scoped to memory writes / plan-compliance, not "a human PR comment is about to edit a skill file" |
| Build the verification harness first, then tune | **MATCH (strong)** | `docs/research/scored-eval-method.md` — frozen instruments, Level A/B never blended, n=3 trials, blind grading, pre-declared acceptance; already run twice |
| Deterministic evals against golden outputs | **MATCH (strong)** | Same doc |
| Track global metrics, feed them back into the improver | **GAP** | `gate-decisions.jsonl` + `costs.jsonl` exist and are exactly this kind of signal, but neither feeds anything self-improving — write-only telemetry, the article's own named anti-pattern |

## Candidates named, not built

1. **Feed the gate-verdict journal into `recursive-improve`'s Observe step.** The collection half
   already exists (`gate-decisions.jsonl`); the mining half doesn't. Lowest-effort way to close
   part of the corroborated gap without inventing new infrastructure — `recursive-improve` already
   has the Observe→Propose→Ask→Act shape, it just isn't reading this file today.
2. **A per-skill feedback capture convention**, if a specific skill starts accumulating repeated
   human corrections worth compounding (mirrors the article's PR/issue-comment capture, adapted to
   this repo's memory-type "feedback" mechanism rather than inventing a new store).
3. **Scheduled trigger** for any of the above — deliberately last and most speculative. mh's
   `recursive-improve` is user-triggered by design (no autonomous/unattended mode is a stated
   invariant, not an oversight); making the *mining* scheduled without also re-litigating that
   invariant needs its own decision, not a silent extension of items 1–2.

None of these is scoped or approved — named for the user's call, per this audit's own mandate to
compare, not build.

## Unresolved

- Not checked: whether `mh:learn`'s transcript-scan cadence could be repointed at
  `gate-decisions.jsonl` cheaply, or whether that file's current shape (verdict + tool + reason,
  no free-text human comment) even carries the kind of "why" signal Warp's design depends on —
  the journal was built for volume/audit, not commentary, so candidate 1 may need a schema change
  first.
- Not checked: how the six MATCH verdicts above were originally arrived at chronologically — i.e.,
  whether mh's design already resembled Warp's independently, or converged after seeing similar
  prior art. Not load-bearing for this audit either way.
