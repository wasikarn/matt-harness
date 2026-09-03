# Branching model

Moved out of the root `CLAUDE.md` 2026-09-03; the one-line rule stays there, the coverage
notes and concurrent-session discipline live here.

Single branch: `develop` only. No feature branches. Commit and push direct — "direct" means
no PR/feature-branch flow; *when* to push still follows the global confirm-before-push
policy (`~/.claude/CLAUDE.md`'s Background Session Git Discipline section).

**Computationally enforced for the Bash entry point only** by the `git worktree add -b`
block in `gate:bash:irrecoverable` (`PreToolUse:Bash`). Opt-in per repo via a
`/.kbg-no-worktree` or `/.mh-no-worktree` sentinel — the gate accepts either name (expand,
not rename, so a sentinel already dropped into some other repo under the old name keeps
working). Present in the matt-harness repo; absent from other client/ECC/scratch repos,
which keep their existing `gate:write:worktree-guard` redirect. The former allowlist for
detached `review-pr-<N>` worktrees was removed with the review pipeline, 2026-08-24 #82.

**Not covered: the native `claude --worktree <name>` CLI flag**
(`code.claude.com/docs/en/common-workflows.md`, confirmed 2026-08-20 — the doc's own
recommended way to run a parallel session). It never routes through the Bash tool, so the
gate above never sees it. A prior companion gate on the native
`WorktreeCreate`/`WorktreeRemove` events was removed 2026-07-31: its deny logic was dead
code (those events never send `tool_name`/`tool_input`) and would have silently broken every
legitimate worktree creation if left registered, so removing it was correct. But it means
this doctrine's coverage was never — and still isn't — anything more than the literal
`git worktree add -b` typed into Bash. Full writeup:
`docs/research/official-docs-audit-2026-07-31.md`.

**Also not covered: the PowerShell tool.** `irrecoverable.sh` (this gate, plus the other 2
`PreToolUse (Bash)` deny/ask gates — `verifier-protect.sh`'s Bash leg, `worktree-guard.py`'s
Bash branch) matches on the `Bash` tool only. `tools-reference.md:361` (confirmed
2026-08-20) prescribes matching `Bash|PowerShell` for any hook inspecting shell commands.
Deliberately not done here: a matcher-only fix would claim coverage this repo's
POSIX-specific deny logic doesn't have and can't be tested on this dev box. See
`docs/reference/hook-lifecycle-contracts.md` for the full note.

**`/branch` and `claude --continue --fork-session` are session branches, not git branches.**
They fork the conversation (try a different approach, keep the original session intact)
without touching the filesystem's single-`develop`-branch model above. Neither interacts
with the worktree gate; both are safe to reach for when you want to try something without
losing your place. Neither is a substitute for the git-branch discipline this section
enforces.

**Never run `mattpocock-skills:git-guardrails-claude-code`'s setup in this repo.** It wires a
PreToolUse hook blocking *all* `git push` unconditionally, not just `--force` — a direct
conflict with this section's workflow. Not installed here; a standing caveat, not an active
problem. The skill's install step is a Write/Edit to an existing `.claude/settings.json`
merging a new entry into `hooks.PreToolUse` — `config-write-guard.sh` (#98) now asks on
exactly that edit shape (any change to the `hooks` or `enabledPlugins` keys), so the mechanism
has a backstop; the instruction itself still stands regardless — the gate covers this one edit
shape, it doesn't make the workflow a fit for this repo's own hook architecture.

## Concurrent sessions

The single-branch, no-worktree design above means concurrent Claude Code sessions on this
repo share one working tree. There's no isolation to fall back on, so discipline substitutes
for it:

- **Stage by explicit path only** (root `CLAUDE.md`'s "Stage by name" rule). Before staging, run
  `git status --porcelain` and confirm every listed file is one you actually touched this
  session. A file you don't recognize is probably another session's in-progress work, not
  junk.
- **Re-read `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` immediately
  before writing a commit message that references the version.** Another session may have
  bumped it since you last checked, and a stale version number in a commit message is worse
  than no version number. This works because Claude reads files fresh on every tool call, so
  a `Read` here always sees whatever the other session last wrote
  (`code.claude.com/docs/en/common-workflows.md`, confirmed 2026-08-20) — the mechanism this
  whole bullet list quietly depends on.
- **A scratch/workspace dir reappearing after you thought it was cleaned up** (e.g. a
  fixture workspace, `skills/pr-workspace/`) is a signal another session owns it right now.
  Leave it alone rather than deleting or restaging over it.
- **`/rewind` can revert another session's work, not just your own.** If two sessions edit
  the same file, a Restore-code in one can silently undo the other's in-flight changes. It's
  the one operation nobody here treats as destructive; check `git status` before trusting it
  in a shared-working-tree session, and recover through git if it did.
