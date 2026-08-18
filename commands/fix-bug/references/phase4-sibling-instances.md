# Phase 4: sibling-instance exception — rationale

Full context for the "all sibling instances of the same root defect" exception to the
Surgical-by-default fix shape (see COMMAND.md Phase 4 step 1).

**Scope correction**: the earlier wording scoped this exception to *a workaround elsewhere
that exists because of the same root-cause defect*. That left a sibling symptom with no
workaround history still broken — producing the same "silently wrong" residue and the same
point-fix-then-regress loop. The corrected scope: every caller that exhibits the same defect
counts as a sibling instance, whether or not a prior workaround existed for it.

**Incident precedent**: patching only the reported caller and leaving every sibling still
broken is the exact pattern that stretched the tathep `compliance-audit-round-2` loop past
10 rounds.

**Consequence of leaving one unfixed**: ships code that's silently wrong about why the guard
exists. Consolidating every sibling into the fix is part of confirming the fix's blast
radius, not scope creep.

**Test for "is this a sibling"**: does this caller share the defect my fix resolves — not
"is this caller physically near the bug" and not "did a workaround already exist for it."

**Finding callers**: code-review-graph MCP `query_graph_tool` if the repo's graph is built —
check `mcp__code-review-graph__list_repos_tool` first; else Grep.
