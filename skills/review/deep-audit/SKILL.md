---
name: deep-audit
description: "Deep-audit: post-implementation audit — verify every claim, score before/after, fix evidence-backed gaps, re-score. Use after an implementation pass. Don't use for a first-pass review (/code-review)."
model: inherit
effort: xhigh
---

Audit everything implemented or changed in this session as if someone else built it. The
session output is a set of claims; each one is true only once evidence outside the model's own
memory says so.

## 1. Reconstruct scope from the tree, not from memory

Scope is what git shows, since a compacted session remembers a retelling, not the work. Find
the session's first commit from the reflog or the session start time, then list:

```bash
git log --oneline --since="<session start>"        # or <first-sha>^..HEAD
git diff <first-sha>^..HEAD --stat; git status --porcelain
```

Uncommitted-only work is the diff alone. Add files edited outside git (memory store, settings,
sibling repos) by name. When the session worked from a plan's file list, re-sweep every tracked
file with a fresh grep for the changed names and paths: the plan's list is a claim about which
files were affected, not the set itself. Then read the diff and trace how the pieces work
together end to end, noting assumptions, implicit behaviour, and anything the session claimed
but never ran. Done when every changed file is listed with the session's claim about it and
your own note on it.

## 2. Score the baseline on the fixed rubric

Score each dimension 0–10 from evidence and take the weighted average (weights sum to 10);
pass is 7.0 or more with no dimension under 5. Same rubric every run, so runs compare.

| dimension | weight | evidence that earns the score |
|---|---|---|
| Correctness | 3 | tests, checks, or a reproduced command exit code |
| Completeness | 2 | every item of the request traced to a file or an explicit "left out" |
| Claim accuracy | 2 | each claim in commits, docs, and replies re-run or re-read |
| Regression safety | 2 | gauntlet or equivalent green; sibling callers of changed code checked |
| Simplicity | 1 | no abstraction, file, or line without a caller or a reader |

Evidence is read in the operating-model order: deterministic result, then this run's
trajectory, then rollback history, then model confidence last. A dimension with no evidence is
marked **insufficient evidence**, left out of the total, and named in the report for the operator to
decide; a guessed score is worse than none (Rule 14).

Claim accuracy is scored on whether the claim was true when made; later evidence that makes it
true is separate current-state work.

## 3. Hunt gaps with a Codex-primary fresh-context checker

The maker never grades its own work (`docs/reference/operating-model.md`). Build the checker's
brief in the `docs/reference/spawn-brief.md` shape, with the scope list and notes from step 1
and this task: assume the session is complacent; find what it missed across correctness, edge
cases, failure modes, hidden assumptions, regressions, missing checks, consistency between files
(doc versus code, two docs disagreeing), and drift between intent and code; every finding cites
one checkable fact (a path, a command, a line). Add one line to the brief itself: this run is
investigation-only — reading files and running read-only commands (`git log`, `git diff`, `cat`,
`rg`) is expected and required.

**Fingerprint scope before dispatch.** For every path step 1 put in scope (committed-diff files,
any staged/untracked/uncommitted files, any named out-of-git file — memory store, settings),
record whether it exists and, if so, a content hash of its bytes on disk. Keep this manifest.

**Dispatch, Codex primary:**
```
codex exec --sandbox read-only --model <selected-model> -c model_reasoning_effort=<selected-effort> --cd <repo-root> \
  --output-last-message <file> --output-schema <schema-file>
```
Choose `<selected-model>` and `<selected-effort>` using
`docs/reference/codex-integration-map.md`'s task/account-cost policy; normally Sol/medium
for this adversarial checker. Check availability and remaining quota before a substantial run.
Raise effort only for a concrete reasoning need; acceptance criteria below never weaken.
`<schema-file>` is `references/checker-output-schema.json` (this skill's own JSON Schema for
`{pass, findings[], scope_ok, unexpected_files[]}`). This is sandboxed against model-generated
shell commands (`codex exec --help`'s own wording) plus the brief's no-mutation line above — not
an unqualified "read-only, guaranteed," since neither layer alone covers every tool an
environment might load.

**Accept the result only if all of:** `codex exec` exits 0; the output-last-message file parses
against the schema with all four fields present; and the result shows real review evidence —
findings that each cite one checkable fact, or an explicit, legitimate zero-findings pass (see
below) — and does not state or imply it couldn't or didn't complete the review. Schema-valid
JSON that still refuses in prose is not review evidence. A `pass: false` result **with real,
evidenced findings is a successful run that found problems** — never a failure, never a fallback
trigger.

**On any other outcome** — non-zero exit, empty or malformed output, a schema mismatch, timeout,
auth failure, or a semantic refusal — fall back to a Claude `Explore`/review agent (same brief)
and note "independence reduced for this pass" in the final report, matching
`docs/reference/codex-integration-map.md`'s established fallback language.

**Re-fingerprint after the checker returns.** A mismatch against the pre-dispatch manifest — a
changed hash, a path that appeared or disappeared — means a concurrent session touched scope
mid-check (this repo runs concurrent sessions on one working tree): rebuild scope from git and
re-run the checker once.

**If the fallback also fails to produce a valid result, or the manifest is still unstable after
that retry**, this is not a soft note: it hard-forces the Final Verdict below to **fail,
reason "verification incomplete"** — overriding whatever step 2's rubric total would otherwise
say, since its "insufficient evidence, left out of the total" allowance would otherwise let a
checker-less run still pass on its remaining dimensions. Say plainly this means the audit
couldn't verify the work, not that the work is wrong — the two are different claims.

The checker returns `{pass, findings[], scope_ok, unexpected_files[]}` — its own return value,
distinct from this skill's Final Verdict and report in "Final output" below.

Reconcile its findings with your own. A finding survives only with a concrete trigger; a
speculative "consider X" is dropped. Rank survivors by severity, impact, likelihood, confidence,
and effort. Zero survivors is a valid result: an already-high baseline is a legitimate baseline,
and only evidence separates "nothing worth fixing" from "under-audited".

## 4. Confirm, then fix

Present the ranked findings and confirm with one **AskUserQuestion**:

- `Apply all fixes now` (findings low-risk and inside the session's scope)
- `Apply only some` (a finding is out of scope or needs its own decision); ask which
- `Skip fixes, report findings only` (review-only pass); go to step 6 with the baseline as both scores

Skip the ask only when the same turn already said "audit and fix"; an earlier or implied
authorization is not that.

Each fix names its failure class (Rule 4: missing_context, bad_tool_contract, missing_guardrail,
weak_verification) and lands test-first where a test can express it: the new test is red on the
pre-fix code and green after, and that red run is part of the evidence. Every change carries a
quality rationale; a change that only moves the score is left out.

## 5. Re-verify

- Re-run the tests and checks the fixes touch, plus the repo gate (`scripts/run-gauntlet.sh` or
  the project's equivalent).
- Check each fix's own mechanism for a new regression before scoring its dimension resolved: a
  fix for one problem can reopen another, and a test that only documents the new behaviour
  hides that. Close a self-inflicted regression in the same pass when it is cheap.
- A fix touching 2+ files or a test gets the fresh-context validator again (Rule 13).
- A fix in a hook, gate, or plugin file is correct in the repo before it protects a session: the
  running copy (plugin cache version, restarted session) is a separate claim; say which one the
  evidence covers.

## 6. Re-score on the same rubric

Report before, after, absolute delta, and percentage, per dimension and overall. When a baseline
is zero or near it, give the absolute delta and say the percentage is not meaningful.

An improvement counts only when post-change evidence beats the baseline on the predefined
criteria. If the score did not move, say so and say why.

## Final output

Line one is the **Final Verdict**: pass or fail against the threshold in step 2, with the
reason and a confidence level, stated plainly — check step 3's hard-fail override first; when it
fires, it wins regardless of the step-2 total. Then:

1. Baseline score (per dimension, weighted total)
2. Findings, with the checker's and your own marked
3. Changes made, each with its failure class
4. Verification evidence (commands and exit codes)
5. Final score and before → after
6. Remaining risks, **insufficient evidence** dimensions, and the scope boundary: the audit
   covers the diff it was pointed at, not the neighbourhood around it

The report is evidence-backed proof of whether the work improved, written for a reader who
did not watch the session.
