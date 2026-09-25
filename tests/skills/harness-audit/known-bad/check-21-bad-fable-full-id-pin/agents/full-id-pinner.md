---
name: full-id-pinner
description: "Fixture agent for check 21. Use when proving a full claude-fable-* model ID pin fires the same WARN as the bare fable alias."
bucket: utility
tools: Read
model: claude-fable-5-1
effort: low
---

Fixture body; `claude-fable-5-1` is the full model ID form of the same fable pin the bare
`fable` alias fixture covers, matched by check 21's separate `claude-fable-*` case arm. Check 21
must WARN here too, independent of whether the bare-alias arm still fires.
