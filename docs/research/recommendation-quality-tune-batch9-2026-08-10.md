# Recommendation-quality tune — Level-B batch 9 (issue #45)

Date: 2026-08-10. Closes issue #45 — the 2 `skills/decide/SKILL.md` gaps dropped at the
#43 → batch-8 seam: both sat in #43's own body table as "Still open," but batch 8 scoped decide
to the single ambiguous HONEST-CONFIDENCE gap and never dispositioned these two, and #43 then
closed on file granularity ("7 of 7 files addressed") — true per file, false per gap.

Level B only, unmeasured — no fixtures ran; gaps reported as found/closed, never a scored delta
(rule 2, `docs/research/scored-eval-method.md`).

## Re-grade before edit (batch discipline)

Both citations re-verified against `3ab6767` (v0.68.259) content before any edit:

- **EVIDENCE-REASON** — `Rejected: ... (reason)` in the Output format's Decision block carried
  no evidence-citation requirement (contrast the `Selected` line's `driven by:` and the
  Confidence line's evidence anchor immediately below it). Confirmed open.
- **ASK-CONSEQUENCES** — Mode: clarify step 3's ask path had no per-option consequence
  requirement; zero occurrences of "consequence" anywhere in the 330-line file. Confirmed open.

## What closed

| File | Gap | Fix |
|---|---|---|
| `skills/decide/SKILL.md` | EVIDENCE-REASON | `Rejected:` line now requires the specific fact or constraint that ruled the option out — same evidence standard as `Selected`'s driven-by line; a generic quality adjective with no cited fact explicitly doesn't count |
| `skills/decide/SKILL.md` | ASK-CONSEQUENCES | Clarify step 3: when the fork fires via `AskUserQuestion`, every option's description carries a one-line consequence (what changes, what it costs, or what breaks if picked); a plain-text fork keeps the lighter prose shape — options + recommended pick + the one-line reason it wins |
| `docs/reference/judgment-ladder.md` | EVIDENCE-REASON (review-driven propagation) | The fuller high-stakes Decision template's `Rejected options: - ... (reason)` mirrored to the same standard — review round 1 caught that tightening only the compact template left the *higher*-stakes path with the weaker bar (the sync-seam defect class, again) |

2 of 2 gaps in issue #45's scope closed, plus 1 review-driven propagation into the template file
`SKILL.md` itself routes one-way-door decisions to (`docs/reference/**` is runtime-loaded, so
the same version bump covers it).

## Char delta (>20% flags: none hit)

| File | Before | After | Delta |
|---|---|---|---|
| `skills/decide/SKILL.md` | 20,149 | 20,658 | +2.53% |
| `docs/reference/judgment-ladder.md` | 14,093 | 14,210 | +0.83% |

## Post-edit review (maker≠checker)

**Round 1** (`kbg:code-reviewer`, briefed on machinery-contradiction, checkability, and
fleet-consistency risks): 0 CRITICAL/HIGH, 2 MEDIUM, 2 LOW.

- MEDIUM — `judgment-ladder.md`'s fuller template still carried the bare `(reason)` bar the
  diff had just replaced in the compact one. Fixed (propagation above).
- MEDIUM — the first-draft consequence rule ("every option presented carries a one-line
  consequence", unscoped) was stricter than `output-styles/staff-eng.md`'s own documented
  prose-fallback formats (<3 options: one compressed line; 3+: labeled list + one shared
  reason below it). Fixed by scoping the per-option requirement to the `AskUserQuestion` path
  and naming the lighter plain-text shape explicitly.
- LOW — a 107-char unwrapped-line artifact from the insertion. Fixed (paragraph rewrapped).
- LOW — manifest bump not yet in the diff. By design; lands with the commit.

**Round 2** (second fresh-context verifier, handed the findings as claims to verify against
disk, not as facts): all 4 RESOLVED with supporting quotes; both original gap closures
confirmed not weakened by the rewording; no new defects. The verifier specifically
cross-checked the plain-text-fork sentence against staff-eng's actual prose formats —
compatible, no per-option requirement smuggled into the prose path.

## Backlog status

- **Issue #45: closed by this batch** — the last unmeasured Level-B leftover from the original
  39-file sweep.
- **Issue #46** (opened same day): `output-styles/staff-eng.md` EVIDENCE-REASON — the #38
  round's explicitly-unmeasurable candidate (fixture ceilinged 6/6; method rule 6) now has a
  tracker home for a future measured round with a non-ceiling fixture design. Deliberately not
  touched here: eval-controlled surface, changes ship only with Level A evidence.

## Verification

- Re-grade of both citations against pre-edit HEAD recorded above. Rule-8-style inventory
  check ran: both cited line locations, the zero-"consequence" grep, and every count and byte
  figure in this report re-derived from disk, not end-of-session recall.
- Two-round review trail above; round 2 independent and fresh-context.
- Version bump v0.68.259 → v0.68.260 in the same commit (pre-commit gate enforces the
  pairing and manifest agreement).
- Pre-push gauntlet result recorded in issue #45's close comment with the commit SHA.
