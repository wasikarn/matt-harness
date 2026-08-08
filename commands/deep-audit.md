---
name: deep-audit
description: "Post-implementation adversarial audit: reconstruct session state, verify every claim against evidence, score before/after on a defined rubric, implement only evidence-backed fixes, re-score. Use after a significant implementation pass to check it actually improved something. Don't use for a first-pass code review — see /kbg:review-pr."
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
5.  **Implement improvements**
    Make the necessary changes to address the identified weaknesses.

    Do not make cosmetic changes just to increase the score. Every change must have a concrete quality rationale.

6.  **Re-verify everything**
    After making changes:
    -   Re-run relevant tests and checks.
    -   Re-audit affected areas.
    -   Check for regressions.
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

### **Critical Rule**

**Never claim that something is better merely because it looks better or feels more correct.**

An improvement is only considered valid when there is measurable evidence showing that the post-change state performs better against the predefined criteria.

If the score does not improve, say so explicitly and investigate why.

If you cannot measure a dimension reliably, mark it as **unverified** rather than inventing a score.

### **Final Output**

Provide a concise audit report containing:

1.  **Baseline Score**
2.  **Findings / Gaps**
3.  **Changes Made**
4.  **Verification Evidence**
5.  **Final Score**
6.  **Before → After Comparison**
7.  **Remaining Risks / Unverified Areas**
8.  **Final Verdict**

The goal is not to produce a reassuring review.

The goal is to produce **evidence-backed proof of whether the work actually improved**.