# Branching model

Single branch: `develop` only. No feature branches. Commit direct; *when* to push follows the
operator's confirm-before-push policy (`~/.claude/CLAUDE.md`, `# Git`).

Nothing enforces the single-branch rule computationally. The former `git worktree add -b` deny
was removed in the v1.0.0 rebuild; `claude --worktree` and `/branch` never routed through it
anyway. `/branch` and `claude --continue --fork-session` are session branches, not git branches:
they fork the conversation without touching the working tree.

**Never run `mattpocock-skills:git-guardrails-claude-code`'s setup here.** It wires a PreToolUse
hook blocking *all* `git push`, not just `--force`. `gate:write:config-guard` asks on exactly
that settings edit shape (any change to `hooks` or `enabledPlugins`), so there is a backstop;
the instruction still stands.

## Concurrent sessions

Each interactive session gets its own working tree (2026-09-28): `EnterWorktree`/`claude
--worktree` creates a linked worktree under `.claude/worktrees/<name>/` (gitignored), torn down
via `ExitWorktree`/`git worktree remove` when the session ends — this replaces the old
one-tree-for-everyone model, which needed manual path-claiming discipline to avoid stepping on a
peer's uncommitted edits. What's still shared across every worktree of this repo, and still needs
discipline:

- **The memory store is one shared directory, not per-worktree.** `scripts/_lib/memory-dir.py`
  resolves the same encoded key from every worktree (keyed off `--git-common-dir`, not
  `--show-toplevel`), so `hooks/stop/memory-audit-commit.sh` serializes its own commit across
  concurrent sessions via an atomic lock — see the script's own header for the lock protocol.
- **A subagent shares its parent session's worktree**, not a worktree of its own — the same
  stage-by-path discipline still applies to it (`gate:bash:subagent-git-guard` denies a bare
  `stash`/`reset`/`clean`; verify `git diff --cached --name-only` before committing).
- **`ListAgents`/`SendMessage` file-claim discipline** (`~/.claude/CLAUDE.md`, injected globally)
  still applies to anyone touching a file another live session might also touch — worktree
  isolation removes the *working-tree* collision, not a collision in a file both sessions read
  from or write to outside git (e.g. this repo's own manifests, or the shared memory store above).
- **Re-read both manifests right before writing a version into a commit message.** A peer session
  in a different worktree can still push a bump first; `Read` always sees the latest committed
  state, not what was true when this session started.
- **`/rewind` only reverts this session's own worktree.** It can no longer touch a peer's tree at
  all, since each session now has its own — this constraint from the old shared-tree model is
  gone, not merely mitigated.
