---
description: Orchestrate building a brand-new feature end to end — research, plan, TDD, review, gated commit. Wrapper that kicks off the orch-add-feature skill.
name: orch-add-feature
---

# /orch-add-feature

Manually launch the **orch-add-feature** orchestrator: a gated
Research → Plan → TDD → Review → Commit pipeline for net-new capability.

## Usage

```
/orch-add-feature <what to add>
```

Examples:

```
/orch-add-feature add OAuth2 login to nws-poller
/orch-add-feature support CSV export in the dashboard
```

If `$ARGUMENTS` is empty, ask the user what capability to add.
