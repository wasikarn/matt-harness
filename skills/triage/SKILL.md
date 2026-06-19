---
name: triage
description: "Single-issue triage: classify a bug, feature request, or task by severity, scope, and owner. Use when the user dumps a single issue and you need to decide whether to route it to /feature-dev, /fix-bug, /deep-dive, or kbg:orchestrate. Also fires on Thai routing requests like 'triage', 'จัดลำดับ', 'ประเมิน priority', 'นี่ควรทำอะไร'. Don't use for: prioritizing a batch (use kbg:orchestrate), or building a feature (use /feature-dev)."
---

# Triage

Classify one incoming item by asking 3 questions:
1. **Severity:** P0 (production down), P1 (blocked), P2 (annoyance), P3 (nice-to-have)
2. **Scope:** Single file, component, cross-component, or architecture
3. **Owner:** Which agent in the fleet owns this concern? (See BOUNDARY.md file ownership table)

Then route:
- P0 bug → `/fix-bug` + spawn `incident-commander` if production
- P1 bug / feature → `/feature-dev` or `kbg:orchestrate` if batch
- Research / unknown → `/deep-dive`
- Architecture question → `kbg:probe`

Done-when: a one-line classification + recommended next command.
