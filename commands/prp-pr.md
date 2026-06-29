---
description: "Forward to /pr — use /pr directly for all PR creation (covers .claude/PRPs/* artifact paths)."
argument-hint: "[base-branch] (default: main)"
---

# /prp-pr — use /pr instead

This command is retained for the PRP-workflow name only. All PR creation now
goes through `/pr`, which already covers the `.claude/PRPs/{reports,plans,prds}/`
artifact paths (alongside `.claude/prds/`, `.claude/plans/`).

Run:

```
/pr $ARGUMENTS
```