# Abide (coldteadotai) drill-down — matt-harness, 2026-09-24

Source: Vibe Coding Thailand article on `coldteadotai/abide`, an MIT-licensed hook tool (not the
Jev API directly) that hooks Claude Code/Codex/OpenCode, sends each edit's diff + one project rule
to Jev, and gets back a single calibrated probability in ~300ms.

This is a **different decision** from the four prior Jev rounds (`typesafe-ai-system-one-jev-2026-09-18.md`
and its addenda, `jev-adoption-revisit-2026-09-20.md`, FAIL 2.45/10). Those rejected *Jev as a
scoring backend inside mh's own skills* — disqualified because Jev has no evidence field and mh's
`checker`/`attacker`/`verifier` schemas require `evidence`/`checked[]` with `minItems: 1`. Abide
sits entirely outside mh's skill schemas; it's an external hook layer, not a call mh's code would
make. That disqualifier does not transfer, so this gets its own score.

## What Abide would actually enforce here

Abide only sees file diffs. Most of matt-harness's own judgment rules (Rule 1 triad, Rule 13
delegation, branching model, "confirm before push") are about **actions and process**, not diff
content — invisible to a diff-only checker, already covered by PreToolUse gates, or both. The
diff-visible, judgment-only, currently-unenforced candidate set is thin:

- **Ponytail "no unrequested abstractions"** (no interface for one impl, no factory for one
  product) — direct structural match to Abide's own `single-use-abstraction` rule, which scored
  **6/8 = 75% confirmed** at turn-level in Abide's published benchmark. The one real strong
  candidate.
- **Ponytail "mark a cut corner with a `ponytail:` comment naming the ceiling"** — closest analog
  in Abide's own benchmark is `comment-volume`, which scored **2/10 = 20% confirmed**. Weak
  candidate, same failure shape (subjective wording → noisy edit-level flags).
- **Ponytail "non-trivial logic needs one runnable check"** — no benchmark analog; unverified
  precision, would need its own rubric and calibration.
- Skill-description word-count/pronoun rules (`docs/reference/skill-authoring-conventions.md`) are
  confirmed **not** checked by `harness-audit/scripts/audit.sh` today (`rg` for word-count logic
  returned no match) — technically diff-visible and gap-covered, but trivially regex-lintable
  in-repo; doesn't need an LLM judge.

**Correction (2026-09-24, verified via `bash skills/meta/harness-audit/scripts/audit.sh --only 77`
on planted fixtures):** this gap was closed the same day, in commit `5ace2d65`, by
`skills/meta/harness-audit/scripts/checks/77-description-word-count-and-voice-skills.sh`
(`/mh:deep-audit` ran afterward and only fixed this doc's stale wording, not the check itself).
The sentence above was accurate when the drill-down was written (before that check existed); it is
included here as the record of what prompted the fix, not as current state. Current state: check
77 WARNs past the 25-word cap and on first/second-person pronouns. This does not change the
coverage verdict below — the closed item was already excluded from the "one strong, one weak, one
unverified" count.

Verdict on coverage: one strong candidate, one weak, one unverified. Below the bar for a
dedicated rubric investment.

## Verified against primary source (not the article)

Fetched `coldteadotai/abide`'s own `benchmarks/replay/README.md` directly. Confirms and sharpens
the article's numbers:

- The 39-flagged/10-confirmed (26%) edit-level and 15-flagged/11-confirmed (73%) turn-level
  numbers are **already at the production 0.8+ interrupt threshold** — not diluted by counting
  the 0.5–0.8 note-only band. Edit-level noise is real, not an artifact of the aggregate stat.
- Turn-level structural rules score well (`single-use-abstraction` 6/8, `file-length-500` 3/3,
  `rust-bare-string-user-error` 3/3); edit-level subjective-wording rules score poorly
  (`comment-volume` 2/10, `plain-error-for-expected-failure` 1/11). The pattern holds exactly
  where mh's own candidate rules fall.
- Numbers are pre-`abide calibrate`/`abide tune` — a pessimistic floor per the source's own text.

## Other factors (from the article, not independently re-verified)

- **Vendor trust**: every diff leaves the machine to TypeSafe under the operator's own API key.
  Same vendor already flagged in `vendor-trust-surface-eval-criterion`. Default install scope is
  machine-wide across all projects unless `--project` is passed — a hard requirement here, not
  optional, given dotfiles/mh both being public-repo-adjacent.
- **Fail-open**: hooks always exit 0; missing key or network outage → silent pass, logged only to
  `.abide/events.jsonl`. Same failure class matt-harness's own `matt-harness-gap-audit-2026-09-20`
  flagged CRITICAL in the irrecoverable gate — acceptable here only because Abide would be
  advisory, never a hard gate.
- **Hook stacking**: mh already registers `SessionStart`/`PreToolUse`/`PostToolUse`/`Stop` hooks
  (`hooks/hooks.json`). Abide adds 4 more hooks per agent on the same lifecycle events. Claude
  Code runs hook arrays sequentially (not a conflict), but per-edit latency stacks on top of mh's
  existing gates — not quantified here, would need a live timing check before install.

## Rule 14 scored verdict

Decision: install Abide (`--project`, turn-level rules only) in matt-harness to enforce the
diff-visible judgment-rule gap. Score 0–10 per criterion (10 = strongly supports adoption),
weighted.

| Criterion | Weight | Score | Reason |
|---|---:|---:|---|
| Rule coverage (real gap it fills) | 25% | 4 | One strong match (`single-use-abstraction`), one weak, one unverified; most mh rules are process/action rules a diff-only checker structurally can't see. *A 4 looks like: a real but narrow match, not a rule-book-wide fit.* |
| Precision cost, scoped to turn-level rules only | 25% | 7 | Turn-level 73% confirmed at production threshold is workable; the same rule-class match (`single-use-abstraction`) is the strongest performer in the published benchmark. *A 7 looks like: the one rule class that would work is also the one the vendor's own data backs.* |
| Precision cost, if edit-level subjective rules included | (folded into above if scope not held) | 3 | 26% edit-level precision at the real interrupt threshold means 3 of 4 interrupts would be noise. *A 3 looks like: the agent gets stopped and told to fix things that aren't broken, three times out of four.* |
| Vendor trust / data exfil | 20% | 4 | Same vendor as the already-rejected Jev path; mitigable with `--project` + Vercel AI Gateway `zeroDataRetention`, but that's added setup burden, not a default. *A 4 looks like: a real mitigation path exists but isn't the out-of-box behavior.* |
| Fail-open safety | 15% | 5 | Acceptable only because Abide would be advisory-only, never a hard gate; same failure class mh flagged CRITICAL elsewhere. *A 5 looks like: a known risk pattern that's tolerable purely because of where it sits, not because it's fixed.* |
| Operational cost | 5% | 9 | ~$0.0001/edit, ~0.1¢/turn. Trivially cheap. |
| Hook-stacking latency | 10% | 6 | Not a conflict, unquantified added latency on every edit stacked on mh's existing gates. *A 6 looks like: plausible fine, unverified.* |

**Weighted score (turn-level-only scoping held): 0.25(4) + 0.25(7) + 0.20(4) + 0.15(5) + 0.05(9) +
0.10(6) = 5.35 / 10 → FAIL** (bar set at ≥6/10, consistent with the Jev revisit's bar).

If scope isn't held to turn-level rules (i.e. `plain-error-for-expected-failure`/`comment-volume`-
class edit-level subjective rules get added later): **4.35/10**, further FAIL.

**Confidence: medium.** Grounded in the vendor's own primary-source benchmark and mh's real hook
inventory, but the rule-coverage enumeration is a single-pass read (no second independent lens),
and hook-stacking latency wasn't empirically timed.

## Verdict

**No adoption, distinct from and consistent with the Jev FAIL.** The gap Abide targets is real
but thin in mh's specific rule set — one confirmed-strong match
(`single-use-abstraction` ↔ ponytail's "no unrequested abstractions"), not enough to justify the
vendor-trust and fail-open costs of installing a machine-wide hook tool. If matt-harness later
wants an automated YAGNI/single-use-abstraction catcher specifically, the shape that would clear
the bar is: `--project` scope, turn-level rules only (no edit-level subjective rules), routed
through Vercel AI Gateway with `zeroDataRetention: true`. As described in the article, unscoped,
it doesn't reach the bar.

## Sources

- Article (local file, read in full): `Abide_ใช้_Jev_ตรวจทุก_edit_ภายใน_300_ms...md`
- `https://github.com/coldteadotai/abide/blob/master/benchmarks/replay/README.md` (fetched and
  indexed 2026-09-24, primary-source benchmark table cross-checked against the article's numbers)
- `matt-harness/skills/meta/harness-audit/scripts/audit.sh` (grep, confirms no description
  word-count check exists) — see correction above: closed same day, commit `5ace2d65`
- `matt-harness/hooks/hooks.json` (grep, confirms existing hook event registrations)
- Memory: `jev-typesafe-usecase-survey-2026-09-19.md`, `jev-adoption-revisit-scored-2026-09-20.md`,
  `vendor-trust-surface-eval-criterion-2026-09-19.md`, `matt-harness-gap-audit-2026-09-20.md`
