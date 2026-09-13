---
type: llm
focus: last_message
---
Idea `i2` (in-process LRU cache of seen event IDs) sounds attractive — no extra DB round trip —
but is a trap: it's per-process state, so the moment the handler runs on more than one worker
instance (or restarts), duplicates seen by a different instance/after a restart slip straight
through, silently defeating the dedup it claims to provide. Score 1 if `scores.i2.trap` is set to a
non-null reason that identifies this specific hidden cost (in-memory/per-process state not shared
across instances or surviving restarts — not a generic "could have bugs" reason), `i2` appears in
the top-level `traps` array, and `i2` is excluded from `shortlist`. Score 0 if `i2`'s `trap` is
null, the reason is generic/doesn't name the real hidden cost, or `i2` still appears in `shortlist`.
