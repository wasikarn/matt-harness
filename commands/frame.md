---
name: frame
description: "Load a working-frame: dev/review/research (posture-setter, not a workflow or voice change). Say 'dev mode/โหมด dev/ตั้งโหมด'. Don't use for skills or /output-style."
argument-hint: dev | review | research
---

# /frame — load a working-frame

Read the requested mode file and adopt that working posture for the rest of the session. This sets *how you work*, not *what you say* (output-styles) and not a full workflow (a skill).

## Steps

1. Parse `$ARGUMENTS` for the mode. Valid modes: `dev`, `review`, `research`.
2. **If empty or unrecognized**, show the three options and stop — do not guess:
   - `dev` — implementation posture
   - `review` — reviewer posture
   - `research` — exploration posture (read-before-write, cite evidence, no edits)
3. Read the frame file via Bash (the Read tool does not expand env vars): `cat "${KBG_PLUGIN_ROOT}/contexts/<mode>.md"` and adopt the frame it describes for subsequent turns. Confirm in one line which frame is now active.

Read-only posture-setter — it loads a frame, it does not run a workflow or edit files. The frame persists until another is loaded or the session ends.

## Relation to other surfaces

- **Skills** are the heavier mode entry-points that *do the work* (`research`, `kbg:review-pr`, `kbg:backend-patterns`); `/frame` just sets the frame.
- **output-styles** (`staff-eng`) set the *voice register*; `/frame` sets the *task posture*. Orthogonal — combine them freely.

> Renamed from `/context` (v0.4.6) — it shadowed Claude Code's built-in `/context`
> (token-usage view), making the built-in unreachable. `/frame` is kbg's working-frame
> loader; the built-in `/context` is unaffected by it.
