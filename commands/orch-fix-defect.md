---
description: Orchestrate fixing a bug — reproduce it as a failing regression test, fix to green, review, gated commit. Wrapper for the orch-fix-defect skill.
---

# /orch-fix-defect

Manually launch the **orch-fix-defect** orchestrator: prove the bug with a red
test, then fix to green.

## Usage

```
/orch-fix-defect <what is broken>
```

Examples:

```
/orch-fix-defect poller crashes on empty NWS response
/orch-fix-defect login returns 500 when email has a plus sign
```

Use this only when behavior is **broken/wrong** — not for intentional changes
(`/orch-change-feature`) or new capability (`/orch-add-feature`).

If `$ARGUMENTS` is empty, ask the user to describe the defect.
