---
name: deep-audit
description: "Post-implementation adversarial audit: reconstruct session state, verify every claim against evidence, score before/after on a defined rubric, implement only evidence-backed fixes, re-score. Use after a significant implementation pass to check it actually improved something. Don't use for a first-pass code review — see mattpocock-skills:code-review."
model: inherit
effort: xhigh
---

Drill down, verify, and audit **everything implemented or changed in this session**.

Do not assume the current implementation is correct. Treat the entire session output as something that must be independently verified.

### **Objectives**

1.  **Reconstruct the current state**

    -   Review all relevant files, changes, decisions, and implementation made in this session.
    -   Trace how the pieces work together end-to-end.
    -   Identify assumptions, implicit behavior, edge cases, and areas that were not explicitly verified.

2.  **Perform a deep audit**
    Audit for:

    -   Correctness
    -   Completeness
    -   Consistency
    -   Edge cases
    -   Failure modes
    -   Hidden assumptions
    -   Regression risks
    -   Unnecessary complexity
    -   Missing validation / quality gates
    -   Gaps between intended behavior and actual implementation
    -   Opportunities to improve precision, reliability, maintainability, and clarity

3.  **Establish a measurable baseline**
    Before making improvements, assign a quantitative score to the current state.

    Define a clear scoring rubric and score each relevant dimension separately, then calculate an overall score.

    The score must be based on observable evidence from the code, tests, verification results, or other concrete artifacts --- **not subjective confidence**.

4.  **Find improvement opportunities**
    Identify the highest-impact weaknesses and prioritize them by:
    -   Severity
    -   Impact
    -   Likelihood
    -   Confidence
    -   Effort to fix

    **Zero or few findings is a valid outcome of this step, not evidence the pass was too shallow.**
    Do not manufacture findings — filler nits, speculative "consider using X," or a hypothetical
    edge case with no concrete trigger — to give step 5 something to fix. This matches the standard
    already held elsewhere in this fleet: `agents/blind-spot-hunter.md`'s severity-earning discipline
    (no finding ships without a traced path to an earned severity). An already-high baseline score
    is a legitimate baseline. This doesn't relax the Critical Rule below — if the score genuinely
    doesn't improve, say so explicitly; it just means "nothing worth fixing" and "under-audited" are
    not the same finding, and only evidence tells them apart.
5.  **Implement improvements**
    Make the necessary changes to address the identified weaknesses.

    Do not make cosmetic changes just to increase the score. Every change must have a concrete quality rationale.

6.  **Re-verify everything**
    After making changes:
    -   Re-run relevant tests and checks.
    -   Re-audit affected areas.
    -   Check for regressions — including ones the fix itself just introduced, not only
        pre-existing weaknesses. If a self-inflicted regression is cheap to close (e.g. an
        unbounded collection that now needs an eviction policy), fix it in the same pass
        instead of just naming it as a remaining risk. Then check that fix's own mechanism
        for a new regression before scoring the affected dimension as resolved — a fix for
        one problem (e.g. adding eviction) can silently reopen a different one (e.g. an
        evicted entry resets its own rate-limit history), and a test that merely documents
        the new behavior as a passing case can hide this instead of catching it.
    -   Verify that the original problems were actually resolved.
7.  **Re-score using the exact same rubric**\
    Apply the **same scoring criteria and methodology** used for the baseline.

    Report:

    -   Before score
    -   After score
    -   Absolute improvement
    -   Percentage improvement
    -   Which dimensions improved
    -   Which dimensions did not improve
    -   Any remaining risks or gaps

    If a dimension's baseline score is zero, or the overall baseline is at or near zero, a percentage-improvement figure computed from it is a mathematical artifact that can read as stronger evidence than it is. In that case, report the absolute delta and say plainly that a percentage isn't meaningful — don't silently omit the percentage field, and don't publish a large ratio without that caveat.

### **Critical Rule**

**Never claim that something is better merely because it looks better or feels more correct.**

An improvement is only considered valid when there is measurable evidence showing that the post-change state performs better against the predefined criteria.

If the score does not improve, say so explicitly and investigate why.

If you cannot measure a dimension reliably, mark it as **unverified** rather than inventing a score.

A fix that produces new evidence for a claim that was false when originally made does not make the original claim retroactively true. Score claim-accuracy or narrative-integrity dimensions on whether the claim was true at the time it was made, and report new evidence as separate, current-state work — not as something that resolves the original discrepancy.

### **Final Output**

**Lead with the verdict.** Open the report with a one-line **Final Verdict** headline — pass/fail
against the rubric, stated plainly — before any supporting detail. A reader should know the
outcome from the first line, not after reading through the full build-up.

Then provide the concise audit report containing:

1.  **Baseline Score**
2.  **Findings / Gaps**
3.  **Changes Made**
4.  **Verification Evidence**
5.  **Final Score**
6.  **Before → After Comparison**
7.  **Remaining Risks / Unverified Areas**
8.  **Final Verdict** — restated in full here, with the reasoning behind it

The goal is not to produce a reassuring review.

The goal is to produce **evidence-backed proof of whether the work actually improved**.