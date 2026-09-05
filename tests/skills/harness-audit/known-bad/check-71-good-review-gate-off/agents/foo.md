---
name: foo
description: "Fixture agent for check 71. Use when testing the Codex review-gate check."
bucket: utility
tools: Read
model: sonnet
effort: low
---

Fixture body; the test harness writes a stopReviewGate:false state.json at this fixture's
computed path before running the check, so check 71 must stay silent.
