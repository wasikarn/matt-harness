# Spawn brief

The shape every dispatched subagent prompt takes. Short on purpose; the constraints line is METHODOLOGY Rule 13.

```
# Task: <one line>
[role: builder|validator|fixer|re-validator|research|other]

## What
<the deliverable, in the dispatcher's own words; tracker text paraphrased, never pasted>

## FILES YOU OWN
<explicit paths; everything else is read-only>

## Done-when
<observable and pre-stated before starting: exit status plus a task-relevant assertion on the
output — a literal string, a count (tests run/failed/skipped), or a structured field, whichever
fits. Exit 0 alone is not evidence (a skipped suite exits 0). A file existing is not evidence
either — check the content that has to be there, not just presence, or a stale file passes free.
Exercise a negative control before trusting an absence claim (a check that fails on a known-bad
input); measure a stated number independently before writing it into Done-when as its own proof.>

Builder/fixer: before returning, re-read your diff once against Done-when's own assertions and fix
what's cheap to fix. This is a private pass, not the pass/fail decision, and you don't report having
done it — the fresh-context validator still independently re-verifies every claim, and its brief is
never narrowed on the strength of "already self-checked."

Constraints: stage by explicit path only, never stash/reset/checkout/add -A; delete with `trash`;
return `NEEDS-DECISION <question>` instead of guessing; a ruling made within your own authority
(not escalated) logs `Ruling: <what>—<why>—<cost if wrong>`; cite one checkable fact per claim —
illegible evidence is unverified, not absent.
```

When the brief goes to Codex (`/codex:rescue`), name the reasoning effort as an invocation flag,
`--effort <none|minimal|low|medium|high|xhigh>` (the set `codex@openai-codex` 1.0.6 validates), never
as a line inside the task text: the rescue agent strips runtime flags from the prompt and a
prose `REASONING:` line reaches nothing. Omitting the flag runs the operator's configured default;
say so when you relay the result. Model and effort are the dispatcher's call, never the lane's.
Select both using `docs/reference/codex-integration-map.md`'s task/account-cost table. This
operator-authorized policy permits explicit `--model <selected-model> --effort <selected-effort>`
on rescue dispatches; bounded verification starts at Terra/medium, adversarial judgment at
Sol/medium. Escalate effort for a concrete reasoning need, not merely the word "audit".
The live Codex catalog also lists `max` and `ultra`, but this plugin rejects both.
Empty-diff handling: `docs/reference/codex-integration-map.md`, "Silent-refusal gotcha".

A validator returns `{pass, findings[], scope_ok, unexpected_files[]}` and nothing else;
`scope_ok` fails on either an unexpected file or an owned file the diff never touches.
A fixer brief carries those findings verbatim and narrows FILES YOU OWN to the files the
findings name; a returned unit that may touch anything grows into a diff nobody reviewed.

Launch a wave's Agent calls together, before reading any of their results: dispatching one, waiting
on it, then dispatching the next serializes what Rule 13's per-wave cap assumes runs concurrently.

If a wave's launch fails partway — an Agent call itself errors rather than a subagent returning a
finding — do not read results from the launched subset as if the wave completed; note which leaves
never launched and either retry them or say so plainly in the report.

When two leaves' FILES YOU OWN sets aren't disjoint — one owns a path that is an ancestor or
descendant of the other's, or they name the same file — dispatch them sequentially instead of
trusting a glance across the wave.
