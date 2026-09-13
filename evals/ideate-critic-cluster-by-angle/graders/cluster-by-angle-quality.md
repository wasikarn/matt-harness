---
type: llm
focus: last_message
---
Ideas `i1`, `i2`, and `i3` are near-paraphrases of each other from three different frames (perf
engineer, backend engineer, caching specialist) — same store (Redis), same key (product ID), same
TTL (30 seconds), same mechanism (read-through cache in front of the slow call). There is no
substantive engineering distinction between them; they are the same idea worded three ways. `i4`
(push-based denormalization via an event stream — never calls the API at all) and `i5` (batch
multiple calls into one — same pull model, fewer calls) are each a genuinely different angle from
the cache group and from each other. Score 1 if the output's `clusters` puts `i1`, `i2`, and `i3`
together in one cluster whose `label` names the shared angle (read-through/TTL caching — not a
literal frame name or generic label like "caching ideas" with no substance), that cluster's
`frameCount` is 3, and `i4`/`i5` are not folded into that same cluster. Score 0 if `i1`/`i2`/`i3`
are split into separate clusters (i.e. near-identical restatements were treated as distinct
angles), or if `frameCount` doesn't match the actual distinct frames in that cluster's `ideaIds`.
