Resolve-mutation call and worked example for Phase 5 (pointed to from `SKILL.md`'s Phase 5 section).

## Per category (Phase 5 step 2, moved verbatim from `SKILL.md`)

   - **actionable + fixed** → post the `Fixed in <sha>: …` reply; if auto-resolve was chosen in step 1, resolve the thread's node `id` (not `databaseId`) via `resolveReviewThread` — see `references/phase5-reply-mechanics.md` for the exact call, write-access requirement, and `unresolveReviewThread` reversal. If "leave open" was chosen, skip resolution — the reply alone is this thread's output.
   - **wontfix** → post the rationale reply. Leave thread open.
   - **clarify** → post the question reply. Leave thread open.
   - **out-of-scope** → post the `Tracked as #<issue-number>` reply. Leave thread open — same as wontfix and clarify, per step 1's auto-resolve rule (only `actionable + fixed` is ever eligible).

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
