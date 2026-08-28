# "How Warp builds self-improving agents on Claude" (Anthropic, Michael Segner) vs matt-harness

**Date:** 2026-08-28
**Source:** https://claude.com/blog/how-warp-builds-self-improving-agents-on-claude
**Verdict:** One gap, independently corroborated from three different angles by three fresh-context
forks: matt-harness collects operational feedback signal (gate-verdict journal, cost telemetry,
`mh:learn` transcript scans) but has **no loop that mines that signal and folds it back into a
skill's own file content, on a schedule, without a human re-triggering it per round.** Everything
else the article names is either a genuine match already shipped, or a narrower/partial version of
the same idea. **Update:** candidates 1 and 2 below have since been built (v0.68.535, v0.68.536),
narrowing the gap to candidate 3 (a scheduled trigger) only, which is deliberately unbuilt pending
its own explicit decision.

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

## Candidates

1. **Built (`3a2c90a8`, v0.68.535).** Feed the gate-verdict journal into `recursive-improve`'s
   Observe step. New `scripts/gate-journal-summary.sh` aggregates `gate-decisions.jsonl` by
   (gate id, decision); wired as a new Observe bullet. Frequency signal only — journal carries no
   free-text reason field, documented as a caveat in the bullet itself (resolves the "Unresolved"
   note below).
2. **Built (v0.68.536).** A per-skill feedback capture *signal*, redesigned from the original
   "capture convention" framing after checking the actual store first: a new writing convention
   was rejected because native ambient auto-memory is the majority writer (~97% of this repo's own
   memory files per `skills/meta/learn/SKILL.md`) and wouldn't follow a new tagging field anyway.
   Instead, `scripts/feedback-surface-scan.py` mines the *existing* prose in `type: feedback`
   memories for repo-path mentions and clusters by surface (skills/hooks/scripts/docs). Empirically
   validated against this repo's real store before building: 83 feedback memories, real clustering
   (`hooks/gates/` ×4, `hooks/hooks.json` ×3, `docs/METHODOLOGY.md` ×3) — but 3 of the top 10
   mentioned paths no longer existed (renamed/retired surfaces), so an existence filter is load-
   bearing, not polish, and is regression-tested (`tests/skills/
   test-recursive-improve-feedback-surface-scan.sh`, case 5). This also confirms the "if a specific
   skill starts accumulating repeated corrections" trigger from the original candidate framing was
   already met, not speculative.
   - **Bonus fix, same commit:** discovered while checking recursive-improve's own path-resolution
     convention (needed to place the new script consistently) — both pre-existing Observe-step
     wrappers, `scripts/audit.sh` and `scripts/inventory-witness.sh`, had an off-by-one `../../..`
     that resolved to `<repo>/skills` instead of `<repo>`, causing every invocation to exit 127
     (command not found). Confirmed by direct execution before the fix (both exited 127) and after
     (both exited 0 with real output). Unrelated to this audit's own findings, but recursive-improve
     could not have completed its documented Observe step 1 at all until this was fixed.
3. **Not built.** Scheduled trigger for either of the above — deliberately last and most
   speculative. mh's `recursive-improve` is user-triggered by design (no autonomous/unattended mode
   is a stated invariant, not an oversight); making the *mining* scheduled without also
   re-litigating that invariant needs its own decision, not a silent extension of items 1–2.

## Unresolved

- **Resolved by the build**: candidate 1's journal schema question — the journal was left
  frequency-only (no schema change), and the Observe bullet says so explicitly rather than
  overclaiming a "why". Still not checked: whether `mh:learn`'s transcript-scan cadence could be
  repointed at `gate-decisions.jsonl` cheaply if a free-text reason ever gets added later.
- Not checked: how the six MATCH verdicts above were originally arrived at chronologically — i.e.,
  whether mh's design already resembled Warp's independently, or converged after seeing similar
  prior art. Not load-bearing for this audit either way.
