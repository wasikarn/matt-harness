# Governance Evidence Journal — Schema Contract

One append-only JSONL stream at `~/.claude/governance-events.jsonl` replaces the
scatter of bespoke per-hook TSV logs. This file is the **language-agnostic
contract** every producer honors: bash hooks emit via `journal_append` (in
`_lib.sh`); python hooks build the same dict with `json.dumps`. The consumer
(`scripts/governance/governance-summary.py`) reads this shape. Change the shape here
first, then update producers and consumer together.

## Envelope (nested)

```jsonc
{
  "id":      "<ms>-<hook>-<rand>",   // unique across parallel appends (epoch-ms + hook + random)
  "ts":      "2026-06-08T16:45:12.345Z",  // ISO8601 with ms; minted via python (BSD date has no %N)
  "session": "<session-id|hook-id-fallback|no-sid>",   // CLAUDE_SESSION_ID env, else hook id, else "no-sid"
  "hook":    "<hook-id>",
  "event":   "<event-name>",         // OPEN taxonomy — consumer WARNS on unknown, never drops
  "source":  "journal_append|legacy_tsv|legacy_security_hook",
  "fields":  { /* event-specific payload — category lives HERE, not top-level */ }
}
```

The `fields{}` nesting is deliberate (audit decision #6): top-level keys stay
fixed across all events; per-event payload is isolated in `fields`, so the
consumer reads `e["fields"]["category"]` uniformly instead of guessing which
top-level key holds the category for each stream.

### `source` enum

| value | meaning |
|---|---|
| `journal_append` | emitted by the `journal_append` helper (bash `_lib.sh` or python `_lib.py` — same byte shape, lockstep invariant) |
| `legacy_tsv` | reserved — a TSV stream mirrored into JSONL during migration |
| `legacy_security_hook` | `security-diff-review.py`, migrated from its old flat shape |

## Event registry

Consumer warns (not errors) on an `event` not listed here — the taxonomy is open
so a new producer can ship before this doc is updated. Keep this table current.

| `event` | producer | `fields` keys |
|---|---|---|
| `security_finding` | `security-diff-review.py` | `file`, `category`, `severity`, `detail` |
| `config_change` | `config-change-log.sh` | `path`, `source` |
| `fabrication_verdict` | `fabrication-verdict-log.sh` (future JSONL) | `tool`, `version`, `verdict` |
| `bypass_audit` | `bypass-audit-log.sh` (future JSONL) | `tool`, `profile`, `disabled_hooks` |
| `review_finding` | `/review-pr` (Phase II) | `file`, `line`, `tier`, `agent`, `summary` |
| `verification_verdict` | `/review-pr` (Phase II) | `subject_id`, `disposition`, `tier`, `decision`, `rejected_reason` |
| `verification_summary` | `verification-gate.sh` (SessionEnd) | `features`, `tdd_provenance`, `analyzer_pass`, `no_trail`, `gaps`, `exit_reason` |
| `l3_cycle` | `recursive-improve --auto` (ADR 0003) | `run_id`, `iteration`, `outcome` (`green`\|`red`\|`skipped`), `files`, `failing_checks` |

`review_finding` + `verification_verdict` are the Phase-II ground-truth pair: the
former is the per-finding evidence (file/line/tier/agent/summary), the latter is
the SCRUTINIZE-4 disposition. `subject_id` links a verdict back to the `id` of
the finding it judges. `disposition` aligns to review-pr SCRUTINIZE-4
(`survived|rejected`); `tier` to the severity rubric (`Critical|Important|Minor`);
`decision` to the user-chosen action (`fix-now|fix-later|proceed`).

`verification_summary` is the session-end posture event from `verification-gate.sh`
(harness-recursive-improvement Phase 3): integer counts of the session's
`.scratch/*/verification-trail.md` files by `verification_tier` (evidence
**strength** — `tdd_provenance|analyzer_pass|no_trail`, a different axis from the
severity `tier` above) plus `gaps` (no-trail without a named reason). It carries
the real session id (SessionEnd `hook_init` sets `$SID`), so it is the one
session-scopable verification feed for Phase 4 — unlike `verification_verdict`,
whose journaler emits under its own hook id.

`exit_reason` carries the session's posture as ONE of the "Five Honest Exit
Reasons" (Production Pipeline corpus): `complete | blocked | stalled |
degrading | timeout`. Derivation (first match wins, in `verification-gate.sh`):
- `gaps > 0` → `"degrading"` (no-trail without a reason, or undeclared tier)
- `features > 0` → `"complete"` (trails exist; gaps branch already caught the bad case)
- `features == 0` is unreachable (the gate exits 0 silently when there are no trails)

`blocked`, `stalled`, and `timeout` are intentionally deferred — they require
per-trail `verification_status` markers and wall-clock correlation that are out
of scope for the F4 fix. The field is additive; the consumer can introduce the
other enum values later without a schema break.

`l3_cycle` is the per-cycle record of an L3 bounded-autonomy run (`recursive-improve
--auto`, ADR 0003). `run_id` (a uuid minted at launch) is the **correlation key**:
every cycle of one unattended run shares it, so `scripts/l3-run-report.sh <run-id>`
reconstructs the whole run (cycles, green/red/skipped outcomes, files touched) from
the append-only journal at Gate-2 review time — the journal is the durable audit
trail of what the loop did while the operator was away, not write-only. `outcome`
is `green` (gauntlet passed, committed local), `red` (gauntlet failed, reset to the
pre-cycle tag), or `skipped` (the candidate hit a caged path / tamper at `check-act`).
The loop NEVER pushes (the `l3-push-gate` hook enforces it), so there is no
`l3_cycle` event for a push — the batch ships only after the human Gate-2 review.

`findings.jsonl` (the on-disk per-line shape `/review-pr` writes, sibling of
`rejected.md` / `ledger.md` in `.scratch/review-pr-<ts>/`) is the source of these
events and is a superset of the `review_finding.fields` shape, plus
`local_id` (the model's scratch-dedup id — preserved in the journal for
human-readability, NOT used for cross-event linkage), `decision` (the user
choice), and `rejected_reason` (the SCRUTINIZE justification). The per-line
shape is: `{local_id, file, line, tier, disposition, decision, agent,
rejected_reason, summary}` (9 fields). The journaler (`scripts/pr/review-pr-journal.py`) validates `tier`, `disposition`, `decision` against the
enums above and surfaces a `WARNING` on stderr for a miss — but does NOT block
the emit (Q3=a "silent FYI, never unwinds" — the journaler is best-effort, not
a submit gate).

### Two-layer design: validator (Layer 2, ask-gate) + journaler (Layer 1, best-effort)

The journaler's WARNING-only behavior is deliberate (Q3=a), but a fresh-context
audit on 2026-06-11 (FLAG-4) found that an enum-miss verdict silently landing
in the governance stream gets aggregated downstream as if it were a strict-tier
verdict — polluting the digest. **The fix is additive, not contract-changing:**

- **Layer 2 — `scripts/pr/review-pr-journal-pre-emit-validator.py` (pre-emit ask-gate).** CLI
  preflight that `/review-pr` SKILL.md step 4 calls BEFORE the journaler.
  - Re-imports the journaler's enum regexes (`TIER_OK`, `DISPOSITION_OK`, `DECISION_OK`)
    so a schema change there propagates here — DO NOT redeclare the enums.
  - Reads `findings.jsonl` from the scratch dir, skips `local_id`s already in
    `.journaled` (the manifest proves they passed the gate previously), and
    surfaces enum-misses for new findings on stderr (e.g. `local_id=b: tier='CRITICAL_TYPO'`).
  - Exits **0** if all findings pass (or are already in the manifest), **2** if
    any new finding has an enum-miss (or a missing/non-string `local_id`).
  - **The validator is an ASK gate, not a deny gate.** On exit 2, `/review-pr`
    surfaces the validator's named summary via `AskUserQuestion` and the human
    chooses: *proceed anyway (downgrade to journaler WARNING)* / *pause to fix
    the finding* / *cancel the journal step*. The autonomy invariant
    (`recursive-improve stays disable-model-invocation:true` — no autonomous
    multi-iteration loop) is preserved: the validator hands the choice back to
    the human, never decides for them.
- **Layer 1 — `scripts/pr/review-pr-journal.py` (best-effort, never unwinds).** Unchanged.
  WARNINGs on enum-miss but emits anyway. The two-layer design is the answer
  to "the journaler should warn but not block" (Q3=a) AND "we should still
  catch the drift before it pollutes the stream" (audit FLAG-4) — Layer 2
  surfaces the drift to the human (ask), Layer 1 documents the
  best-effort/never-unwinds contract (warn-and-emit).

## Invariants

- **Atomicity** — a single `>>` append of one envelope line is atomic at these
  line sizes (verified empirically: 50 procs × 20 appends of ~880-byte lines →
  1000/1000 lines intact). No `flock`, no truncation-for-safety. The `id`'s
  random suffix guarantees uniqueness even when two appends land in the same ms.
- **Fail-loud** — `journal_append` exits **2** if `jq` is missing; it never
  silently drops an event. The consumer logs+warns every corrupt line with its
  line number instead of crashing the whole digest.
- **Redaction** — `journal_append` applies a thin deny-list backstop
  (`password|api_key|secret|token|credential`, case-insensitive) over `fields`
  keys and string values → `[redacted]`. Primary defense is source
  minimization: don't put secrets in `fields` in the first place.
- **Dedup** — during migration a logger may dual-write TSV + JSONL. The consumer
  dedups on `(hook, ts_truncated_to_second, category)` with **JSONL-wins**
  precedence, so a dual-written event counts once.
- **Gate↔evidence separation** — a hook that emits a `permissionDecision`
  (`hook_decision`) must NOT also call `journal_append` in the same file. Gate
  hooks decide; audit hooks journal. (`hook_decision` exits 0, so any
  `journal_append` near it is either dead code or a decision path that journals
  before deciding — both wrong.) Enforced by `harness-audit` check #29.

## Test override

`CLAUDE_JOURNAL_PATH` redirects the append target. Test-only — set a unique
per-test path and clean it up locally. Never set in production hooks.
