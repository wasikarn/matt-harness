---
name: review-lens-fix-authenticity
description: "Fix-authenticity checklist for code-reviewer's fix: dispatch. Use when a diff's commit is labeled fix:. Don't use for features, refactors, hardening diffs, or standalone review."
bucket: review
metadata:
  origin: kbg
model: inherit
effort: xhigh
---

# Fix-Authenticity Lens

Loaded by `code-reviewer` when a diff's own commit message/PR title is labeled a fix
(Conventional Commits `fix:`, or the dispatch context says so explicitly) — never applied
to a feature, refactor, or hardening diff. Adapted from `thedotmack/claude-mem`'s
merge-rubric (see this repo's README attribution).

The question this lens asks: does the diff correct the logic at its root
cause, or does it notice a failure and arrange to survive it? The second one
looks like a fix in the diff stat but leaves the actual defect in place,
just quieter — flag it **HIGH** (escalate to CRITICAL if the masked bug is
itself a Security or DB-mutation issue per `agents/code-reviewer.md`'s Security
section or `kbg:review-lens-db-sql`).

Costumes a non-fix wears as a `fix:` commit:

- **Guard** — a `try/catch` that logs-and-continues, a never-throws wrapper,
  "best-effort by design." After it fires, the failure still exists and is
  now quieter.
- **Fallback** — try X, fall back to Y when X is empty/broken. The
  fallback's existence is an admission X is broken and nobody fixed X.
- **Retry** — a loop added as resilience around a call that fails
  deterministically (re-attempting doesn't help) or transiently (hides the
  defect that made the failure matter).
- **Fail-open/fail-soft** — "degrade gracefully," "never block X," swallow-
  and-warn. The error needed to surface loudly, not vanish.
- **Self-healing machinery** — a watchdog, reaper, or restart-on-wedge that
  manages the bug in production instead of removing it from the code.
- **Truncation** — capping/slicing/dropping data to make a symptom fit,
  instead of fixing whatever produced the wrong-sized output.
- **A second system** — a new background process, poller, lock/state file,
  or env-var-gated alternate mode added "as a backstop." An escape hatch
  that preserves the old broken behavior means the diff doesn't trust its
  own fix.

Not costumes — don't flag these under this lens: removing any of the above
(the best kind of diff), converting silent tolerance into a loud typed
error at the right boundary, or a plain correctness change (right sort
order, right flag, right quoting) even when it's `if`-shaped — an `if` is
fine when it *is* the correct logic, not a bouncer standing in front of
incorrect logic.

**Scale check:** fix size should track defect size. A one-line logic error
buried inside a 300-line diff means the other 299 lines are very likely one
of the costumes above — find which one before approving.

Confirm the diff against every costume above before verdict — done when each one is
either ruled out with a reason or, if present, filed at the severity this lens sets.
