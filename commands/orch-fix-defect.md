---
description: Manual launcher for the orch-fix-defect orchestrator (bug → red regression test → green fix → review → gated commit). Use when behavior is broken/wrong. Don't use for intentional behavior changes (orch-change-feature), new features (orch-add-feature), or behavior-preserving refactors (orch-refine-code).
name: orch-fix-defect
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
