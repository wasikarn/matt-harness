---
description: "Bootstrap an MVP from a design/spec doc: slice, scaffold, TDD, review, gated commit. Wrapper for the orch-build-mvp skill."
---

# /orch-build-mvp

Manually launch the **orch-build-mvp** orchestrator: turn an SDD/PRD/system-design
document into a running vertical slice.

## Usage

```
/orch-build-mvp <path to design/spec doc>
```

Examples:

```
/orch-build-mvp civicpulse/docs/SDD-v0.6.md
```

If `$ARGUMENTS` is empty, ask the user for the path to the design/spec doc.
