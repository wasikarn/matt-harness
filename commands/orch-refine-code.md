---
description: Orchestrate a behavior-preserving refactor — confirm tests green, restructure without changing behavior, keep green, review, gated commit. Wrapper for the orch-refine-code skill.
---

# /orch-refine-code

Manually launch the **orch-refine-code** orchestrator: improve structure while
behavior stays identical, with the existing test suite as the safety net.

## Usage

```
/orch-refine-code <what to restructure>
```

Examples:

```
/orch-refine-code extract the NWS HTTP client out of poller.py
/orch-refine-code remove dead code and duplication in the dashboard module
```

Use this only when behavior must **not** change. If behavior should change at
all, use `/orch-change-feature` or `/orch-fix-defect`.

If `$ARGUMENTS` is empty, ask the user what to refine.
