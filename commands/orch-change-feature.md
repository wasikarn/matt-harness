---
description: "Change an existing feature to new behavior: update tests, fix impl, review, gated commit. Wrapper for orch-change-feature."
name: orch-change-feature
---

# /orch-change-feature

Manually launch the **orch-change-feature** orchestrator: change behavior that
already works to a new desired spec, tests-first.

## Usage

```
/orch-change-feature <the new desired behavior>
```

Examples:

```
/orch-change-feature make nws-poller alert at 2 warnings instead of 3
/orch-change-feature instead of sorting by date, sort by priority
```

Use this only when the feature **works** but should behave differently — not for
bugs (`/orch-fix-defect`) or net-new capability (`/orch-add-feature`).

If `$ARGUMENTS` is empty, ask the user what behavior should change.
