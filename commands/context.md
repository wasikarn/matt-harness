---
name: context
description: "Load a lightweight working-frame for the session — dev, review, or research. A posture-setter (how you work), lighter than running a full skill and distinct from output-styles (which set voice). Use when the user says 'dev mode', 'review mode', 'research mode', 'set context', 'switch frame', or 'โหมด dev', 'โหมด review', 'ตั้งโหมด'. Don't use for: running an actual workflow (use the matching skill — kbg:research-brief, kbg:review-pr, kbg:backend-dev) or changing voice register (use /output-style)."
argument-hint: dev | review | research
---

# /context — load a working-frame

Read the requested mode file and adopt that working posture for the rest of the session. This sets *how you work*, not *what you say* (output-styles) and not a full workflow (a skill).

## Steps

1. Parse `$ARGUMENTS` for the mode. Valid modes: `dev`, `review`, `research`.
2. **If empty or unrecognized**, show the three options and stop — do not guess:
   - `dev` — implementation posture (TDD, surgical diffs, verify before done)
   - `review` — reviewer posture (confidence×severity, defer-don't-absorb)
   - `research` — exploration posture (read-before-write, cite evidence, no edits)
3. Read `${KBG_PLUGIN_ROOT}/contexts/<mode>.md` and adopt the frame it describes for subsequent turns. Confirm in one line which frame is now active.

Read-only posture-setter — it loads a frame, it does not run a workflow or edit files. The frame persists until another is loaded or the session ends.

## Relation to other surfaces

- **Skills** are the heavier mode entry-points that *do the work* (`kbg:research-brief`, `kbg:review-pr`, `kbg:backend-dev`); `/context` just sets the frame.
- **output-styles** (`senior-eng`, `staff-eng`) set the *voice register*; `/context` sets the *task posture*. Orthogonal — combine them freely.
