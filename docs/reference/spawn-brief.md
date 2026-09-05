# Spawn brief

The shape every dispatched subagent prompt takes. Short on purpose; the constraints line is METHODOLOGY Rule 13.

```
# Task: <one line>
[role: builder|validator|research|other]

## What
<the deliverable, in the dispatcher's own words; tracker text paraphrased, never pasted>

## FILES YOU OWN
<explicit paths; everything else is read-only>

## Done-when
<observable: a passing command, a file that exists, a grep that returns 0 hits>

Constraints: stage by explicit path only, never stash/reset/checkout/add -A; delete with `trash`;
return `NEEDS-DECISION <question>` instead of guessing; cite one checkable fact per claim.
```

A validator returns `{pass, findings[], scope_ok, unexpected_files[]}` and nothing else.
