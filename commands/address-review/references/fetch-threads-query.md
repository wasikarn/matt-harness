# Address Review — Fetch Threads Query

The exact GraphQL query for Phase 1 step 2 (`/address-review`) — fetches every review thread with its resolved/outdated status and root comment ids. REST `pulls/<n>/comments` has no resolved-status field at all, so it cannot answer "is this thread open" — GraphQL is required, not optional.

```graphql
query($owner:String!, $repo:String!, $number:Int!, $cursor:String) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$number) {
      reviewThreads(first:100, after:$cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id                # PRRT_... thread node id — needed only if resolving in Phase 5
          isResolved
          isOutdated
          path
          line
          comments(first:100) {
            nodes {
              databaseId    # == REST comment id → reply target for Phase 5
              author { login }
              body
              createdAt
              originalCommit { oid }   # Phase 4 author-aware dedup input
            }
          }
        }
      }
    }
  }
}
```

Run via `gh api graphql -F owner=<owner> -F repo=<repo> -F number=<n> -f query='<above>'`. **Loop on `pageInfo.hasNextPage`/`endCursor` until false** — a PR can accumulate more threads than one page; a single unpaged call silently drops the overflow, which breaks "don't lose any." `comments(first:100)` is a per-thread ceiling covering all but pathological threads — `ponytail:` no nested-cursor loop yet, add one only if a thread ever exceeds 100 replies.
