---
type: llm
focus: last_message
weight: 1
---
`mh:ideate-critic`'s documented contract: the final message is a single JSON object, nothing before
the opening `{` or after the closing `}` — no preamble narrating process, no trailing caveat, no
closing summary in any language, no markdown code fence wrapping the JSON. The object must contain
`scores` (per-idea novelty/viability/fit/total/trap), `clusters` (each with `label`, `ideaIds`,
`frameCount`), `shortlist`, `shortlistReasons`, `nonObviousPick`, `nonObviousPickReason`,
`runnerUp`, `confidence`, `traps`, `deepened` (sketch + childIdeas per shortlisted idea), and
`provocation`. Score 1 if the relayed message parses as valid JSON, contains all of these top-level
keys with plausible content, and has zero characters outside the JSON object (no fences, no
surrounding prose). Score 0 if it's wrapped in prose/fences, missing required keys, or isn't valid
JSON.
