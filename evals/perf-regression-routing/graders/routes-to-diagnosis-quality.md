---
type: llm
focus: trace
---
This is a reported regression with a before/after (5ms to 2s after a specific merged change) —
the diagnosing-bugs loop's literal trigger: reproduce, find what changed, root-cause it. Score 1
only if the session takes a root-cause diagnostic approach — looking at what changed in the recent
merge, reproducing the slowdown, or explicitly reaching for `mattpocock-skills:diagnosing-bugs` —
rather than immediately proposing generic "optimizations" (memoization, caching, algorithmic
rewrites) without first identifying what the merged change actually broke. Score 0 if it jumps
straight to applying speculative performance fixes without any attempt to find the specific
regression cause first.
