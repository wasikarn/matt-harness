Resolve-mutation call and worked example for Phase 5 (pointed to from `SKILL.md`'s Phase 5 section).

## Resolve mutation (for `actionable + fixed` threads, when auto-resolve was chosen)

```graphql
mutation($threadId:ID!) {
  resolveReviewThread(input:{threadId:$threadId}) { thread { id isResolved } }
}
```

Call via `gh api graphql -F threadId=<id> -f query='<above>'`, using the thread node `id` from Phase 1 (not the comment `databaseId`). Requires repo write access (a PR author's PAT qualifies — verified against GitHub's docs: resolving needs write access, not authorship of the original thread). `unresolveReviewThread` (same shape) reverses it if needed. If the user chose "leave open" in step 1, skip resolution entirely — the reply alone is this thread's Phase 5 output.

## Worked example (step 4 summary)

3 line-level threads (2 fixed, 1 wontfix) + 1 non-empty review body acknowledged →

```
3 threads addressed (2 fixed / 1 wontfix / 0 clarify / 0 out-of-scope)
1 review-body item acknowledged
```

Not `4 threads addressed` — the review-body item is a separate tally, never folded into the line-level thread count or its breakdown.
