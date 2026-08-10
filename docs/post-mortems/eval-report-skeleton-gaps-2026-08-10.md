# Post-Mortem: Eval-report skeleton gaps missed by two review passes (eval-report-skeleton-gaps-2026-08-10)

## 1. Summary
The EVIDENCE-REASON eval-round report (`docs/research/staff-eng-evidence-reason-eval-2026-08-10.md`)
shipped in commit `872f78f` with two report-skeleton defects relative to this repo's own
`scored-eval-method.md` standard. Both had already passed through two review layers
(`mattpocock-skills:code-review` and an `advisor()` consult) undetected. A subsequent
`/kbg:compliance-audit` run, dispatching 4 fresh-context verifiers against a requirement checklist
re-derived from the actual instrument texts, caught both gaps; fixed in commit `b6d5db9`.

## 2. Symptom
A committed research report claiming conformance with `scored-eval-method.md`'s report skeleton,
where two skeleton items were not actually satisfied: (a) method rule 9 (post-grading edit rule)
was absent from the report with no N/A disposition, unlike rules 1–8 which each got explicit
CONFORMS-or-disclosed-N/A treatment; (b) the Verification section named
`claude plugin validate . --strict` where the skeleton's own text specifies `harness-audit
before/after`, with no acknowledgment that a substitution had occurred.

## 3. Root Cause (Mechanism)
Two prior review passes each checked a narrower slice of the requirement space than the full report
skeleton. `mattpocock-skills:code-review`'s Standards sub-agent was briefed to compare the report
against `scored-eval-method.md` generally, without being handed the method doc's 9 numbered rules or
its report-skeleton checklist as an explicit line-by-line list — its actual findings (missing
per-trial table, unquoted acceptance rule) came from a general read of the standard, not a
rule-by-rule pass. `advisor()`'s catch (a rule-8 violation: the Verification section claimed trial
files were on disk when none had been written) came from a holistic transcript read, not a
systematic checklist either. Neither review layer enumerated all 9 rules plus all 7 skeleton items
as discrete, individually-checkable line items.

## 4. Symptom Linkage
Because neither code-review nor advisor were given, or generated for themselves, an explicit
enumerated checklist, each pass caught only the defects salient to its own scan pattern — a missing
table is visually obvious, and an inventory claim contradicted by "nothing was ever written to disk"
is a striking logical gap. A *silent absence* (rule 9 never mentioned) and a *silent substitution*
(harness-audit → plugin-validate, both plausible-sounding checks) are exactly the kind of omission a
non-checklist-driven read tends to skip — there's no negative space to notice without an explicit
list to check off against.

## 5. Fix
Commit `b6d5db9` on `kbg-harness/develop`: added an explicit rule-9 N/A line to the report's
Limitations section; added an explicit harness-audit N/A line to the Verification section, citing
the precedent set by `docs/research/recommendation-quality-tune-2026-08-10.md`'s own Follow-up 1
for an identical docs-only, no-shipped-surface case; converted the "What was changed" section from
prose to the skeleton's required table format.

## 6. Discovery Method
`/kbg:compliance-audit`, run on user request against the finished eval round. Phase 1 re-derived a
24-item requirement checklist from four ground-truth sources (GitHub issue #46, `scored-eval-
method.md`, the session's `FREEZE.md` instrument, and three prior `AskUserQuestion` approvals)
rather than trusting the implementing session's own account. Phase 3 dispatched 4 fresh-context
verifiers with no memory of the drafting session; verifier V2, scoped to method-doc rule
conformance plus report skeleton, found both gaps by walking `scored-eval-method.md`'s 9 rules and
skeleton checklist against the report line-by-line and flagging every item with no explicit
disposition.

## 7. Escape Reason
Two review layers ran before the compliance audit and both are effective at catching salient,
structurally-obvious defects, but neither was scoped or prompted to walk the full method-doc rule
list and skeleton checklist as discrete, enumerable items. No automated check exists in this repo
that validates a `docs/research/` report against `scored-eval-method.md`'s skeleton — verified by
grepping `scripts/`, `hooks/`, and the method doc itself; the only hits are unrelated citation
comments. The check is currently only as thorough as whichever review pass happens to run.

## 8. Validation Proof
**No automated regression test exists** — this is a markdown research report, not code, and this
repo has no linter for `docs/research/*.md` against `scored-eval-method.md`'s skeleton (confirmed
via grep, not assumed). Validation was manual: the same 4-verifier compliance-audit that surfaced
the two gaps was used to re-confirm, within that same pass, that the fixed report now explicitly
addresses rule 9 and names the harness-audit substitution.

## 9. Follow-Ups
- [ ] Turn `scored-eval-method.md`'s 9 rules + report-skeleton checklist into an explicit, literal
      checklist that a Standards-axis code-review prompt can be handed directly, instead of a
      general "compare against this doc" brief. Owner: Unowned — needs assignment. Done when: a
      future code-review pass on a `docs/research/` eval report is given the literal 9-rule +
      skeleton list as part of its prompt, not just the doc path.
- [ ] Decide whether every measured-eval-round report should get a compliance-audit pass by default
      before commit, rather than only on explicit user request — i.e., fold the checklist-audit step
      into `scored-eval-method.md`'s own workflow. Owner: Unowned — needs assignment. Done when: the
      method doc either recommends this explicitly, or a considered decision is recorded for why
      not.
- [ ] No automated structural check exists for `docs/research/` reports against the skeleton —
      evaluate whether a lightweight script check is worth adding given this repo's existing
      harness-audit-style tooling, or whether that's over-engineering for a low-frequency artifact
      type. Owner: Unowned — needs assignment. Done when: a decision is recorded either way.
