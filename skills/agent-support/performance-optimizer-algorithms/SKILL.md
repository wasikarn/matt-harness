---
name: performance-optimizer-algorithms
description: Catalog of performance-optimizer's 14-row algorithmic-complexity pattern table. Auto-loads when performance-optimizer runs. Don't use for other agents.
metadata:
  origin: kbg
model: inherit
effort: high
---

# Performance Optimizer — Algorithmic Analysis Reference

Extracted from `agents/performance-optimizer.md` (2026-08-18, harness-audit check 51 threshold)
to keep the agent body under 20,000 chars. Loaded via that agent's `skills:` frontmatter field
(preloaded at spawn, independent of the Skill tool — `performance-optimizer` carries no `Skill`
tool grant) — this file is the pattern reference, not a separately-triggered pass.

### Algorithmic Analysis

| Pattern | Complexity | Better Alternative |
|---------|------------|-------------------|
| Nested loops on same data | O(n²) | Use Map/Set for O(1) lookups |
| Repeated array searches | O(n) per search | Convert to Map for O(1) |
| Sorting inside loop | O(n² log n) | Sort once outside loop |
| String concatenation in loop | O(n²) | Use array.join() |
| Deep cloning large objects | O(n) each time | `immer`'s `produce()` (structural sharing, still safe for nested mutation) — **not** a plain shallow copy (`{...obj}`/`Object.assign`), which only copies top-level keys. Verified live: `const copy = {...original}; copy.user.prefs.theme = 'light'` also mutates `original.user.prefs.theme`, because `copy.user` is the same nested object reference, not a new one. Shallow copy is only a safe substitute when nothing downstream mutates a nested field — check that before recommending it as the fix. |
| Recursion without memoization | O(2^n) | Add memoization (top-down — still recurses, can stack-overflow on large/unbounded n) or tabulation (bottom-up — iterative, no recursion-depth risk; prefer it once n isn't small and bounded) — dynamic programming |
| Brute-force pairwise interval-overlap check (booking/calendar conflicts, merging time ranges) | O(n²) | Sort by start time, then linear sweep-merge — O(n log n) |
| Repeated linear scan for existence/lookup on sorted data | O(n) per search | Binary search — O(log n) |
| Brute-force substring/pattern search | O(n·m) | KMP — O(n+m) guaranteed; Rabin-Karp — O(n+m) average, still O(n·m) worst case on hash collisions |
| Re-sorting or full rescan to get current min/max after each update | O(n log n) per update | Heap/priority queue — O(log n) push/pop |
| Brute-force contiguous subarray/substring scan | O(n·k) | Sliding window (subtract-leaving, add-entering) — O(n) |
| Brute-force pair search on sorted array | O(n²) | Two pointers (opposite-ends) — O(n) |
| Brute-force triplet search (e.g. 3-sum) on sorted array | O(n³) | Sort + two pointers per outer iteration — O(n²), not O(n) — 3-sum doesn't collapse to linear |
| Exhaustive enumeration with no early exit (permutations/subsets/constraint search) | O(branching^depth) | Backtracking — same worst case, prunes invalid branches before completing them |

**Hidden constants matter — don't flag on asymptotics alone.** Insertion sort beats mergesort below ~30 elements; a Fibonacci heap has better asymptotic decrease-key than a binary heap but usually loses in practice on constants. Same rule as the bundle/LCP budgets above: benchmark before recommending a swap on a hot path with small or bounded n. Also count the recursion stack in space analysis — a solution that recurses n deep is O(n) space, not O(1), even with no explicit array.
