# Branching model

Single branch: `develop` only. No feature branches. Commit direct; *when* to push follows the
operator's confirm-before-push policy (`~/.claude/CLAUDE.md`, Background Session Git Discipline).

Nothing enforces the single-branch rule computationally. The former `git worktree add -b` deny
was removed in the v1.0.0 rebuild; `claude --worktree` and `/branch` never routed through it
anyway. `/branch` and `claude --continue --fork-session` are session branches, not git branches:
they fork the conversation without touching the working tree.

**Never run `mattpocock-skills:git-guardrails-claude-code`'s setup here.** It wires a PreToolUse
hook blocking *all* `git push`, not just `--force`. `gate:write:config-guard` asks on exactly
that settings edit shape (any change to `hooks` or `enabledPlugins`), so there is a backstop;
the instruction still stands.

## Concurrent sessions

Concurrent Claude Code sessions on this repo share one working tree, so discipline substitutes
for isolation:

- **Stage by explicit path only.** Run `git status --porcelain` first and confirm every listed
  file is one you touched; an unfamiliar file is another session's in-progress work.
- **Re-read both manifests right before writing a version into a commit message.** Another
  session may have bumped it; `Read` always sees the latest write.
- **A scratch dir that reappears after cleanup belongs to another session.** Leave it alone.
- **`/rewind` can revert another session's work.** Check `git status` before trusting it in a
  shared tree; recover through git if it did.
- **Subagents never stash, reset, or checkout** (`gate:bash:subagent-git-guard` denies it) and
  verify `git diff --cached --name-only` before committing.
