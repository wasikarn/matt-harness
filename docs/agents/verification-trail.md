# Verification Trail — schema

A `verification-trail.md` records **how strongly** a shipped feature was
verified. One file per feature at `.scratch/<feature>/verification-trail.md` — a
working-tree artifact (`.scratch/` is gitignored), written by the model at the
end of a feature/fix and read at session end by `verification-gate.sh`.

It is the evidence-**strength** signal — a different axis from the severity
`tier` (Critical/Important/Minor) used in review. It feeds the harness-health
loop: `verification-gate.sh` → the `verification_summary` journal event (see
[`hooks/JOURNAL-SCHEMA.md`](../../hooks/JOURNAL-SCHEMA.md)) →
`recursive-improve-observe.py`.

## Format

A markdown file. Two fields are **parsed** — both by `verification-gate.sh` (the SessionEnd
counter). `verification-tier-audit.py` reads only `verification_tier`, and
`recursive-improve-observe.py` reads neither (it consumes the journal, not the trail — see
Consumers below). Parsing is order-independent; surrounding prose is ignored:

| Field | Required | Values | Meaning |
|---|---|---|---|
| `verification_tier` | yes | `tdd-provenance` \| `analyzer-pass` \| `no-trail` | evidence strength (see Tiers) |
| `optout_reason` | for `no-trail` | free text (blank / `n/a` / `none` / `-` = no reason) | why no test provenance exists |

The rest are **informational** — recorded for human/audit readability (and shown
in the test fixtures) but **not read by any consumer**, so they are never
validated and may be omitted:

| Field | Used when | Example | Meaning |
|---|---|---|---|
| `red_green` | `tdd-provenance` | `aaa111 → bbb222` | the failing→passing commit pair, as human-readable evidence of a real red→green cycle |
| `pr_test_analyzer` | `analyzer-pass` | `pass` / `not-run` | the `pr-test-analyzer` result, for the record |

## Tiers (evidence strength, strongest first)

- **`tdd-provenance`** — declared to mean a real red→green cycle happened
  (record the `red_green` shas as evidence). Consumers take the **declared** tier
  at face value — it is read only from an explicit trail, never inferred; the
  strongest signal.
- **`analyzer-pass`** — no red→green provenance, but the `pr-test-analyzer` gate
  vouched for the test coverage.
- **`no-trail`** — no test provenance. Legitimate for doc-only / no-behavior
  work **if** `optout_reason` names why. A `no-trail` with a **blank**
  `optout_reason` (or a malformed / undeclared tier) is the one fully-reliable
  **verification gap** that `verification-gate.sh` counts and flags.

## Examples

```markdown
# Verification trail: feat-a
- verification_tier: tdd-provenance
- red_green: aaa111 → bbb222
- pr_test_analyzer: pass
- optout_reason: n/a
```

```markdown
# Verification trail: docs-only-change
- verification_tier: no-trail
- optout_reason: docs-only, no behavior to assert
```

## Consumers

- `hooks/verification-gate.sh` (SessionEnd) — counts every trail present in `.scratch`
  at session end (trails are not session-tagged; `.scratch` is conventionally per-session), emits
  the `verification_summary` event, and prints a gap advisory.
  **Advisory only** — it journals but never blocks session end.
- `scripts/verification-tier-audit.py` — retro-grades a feature from its trail
  (and other evidence) against this rubric.
- `scripts/recursive-improve-observe.py` — surfaces sessions with `gaps > 0` as
  harness-improvement triggers.
