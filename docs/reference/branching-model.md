# Branching model

`develop` is protected (2026-09-28, Phase B of the SDLC-playbook reversal): no direct push, PR
required. Work on a `feat/<slug>` or `claude/<slug>` branch, `gh pr create` against `develop`,
review via the already-installed `mattpocock-skills:code-review` (verified installed:
`skills/engineering/code-review` in the `mattpocock-skills` plugin cache) — this repo does not
rebuild that flow as its own skill (composer-not-creator,
`docs/reference/composer-not-creator.md`). Merge method: merge-commit or rebase, never squash —
a squashed feature branch is not merged by ancestry, so only `git branch -D` removes it locally
(the gate allowed that only from 2026-09-30, for a plain `git branch -D <names>` without main/master/develop).
`delete_branch_on_merge: true` on the remote handles cleanup.

Enforcement layers, weakest to strongest:
- `git-hooks/pre-push` refuses a direct push whose remote ref is `refs/heads/develop`, before the
  gauntlet even runs — local, defense-in-depth, one manual retry if a stdin ref line is malformed.
- `gate:bash:irrecoverable` asks (not denies — a merge can be a legitimate, operator-approved
  action) on `gh pr merge` / `gh api .../merge` from an interactive Claude Code session. This
  covers only a session running with mh loaded — it does **not** constrain the GitHub web UI, a
  raw API call, or any credential used outside such a session (a cloud Routine, notably —
  `docs/adr/0004-operator-authorized-routine-self-launch.md`, `status: proposed`, is where that
  threat model is actually being worked through; mh has no self-launch path shipped today).
- GitHub branch protection on `develop` (PR required, `enforce_admins`, live-applied 2026-09-28;
  required status checks removed 2026-10-03 along with GitHub Actions) enforces the PR flow only; a single-maintainer repo means
  `required_pull_request_reviews.required_approving_review_count` stays at **0** (GitHub refuses to
  let a PR author approve their own PR, so any higher count would make every PR permanently
  unmergeable with only one account) — merging still requires nothing more than a write-access
  credential. "Review" here is this repo's own operating custom, not something
  branch protection mechanically enforces. An admin editing the protection rule itself is a
  separate, named, accepted residual risk, not something any of the above closes.
  There is no CI (2026-10-03): the pre-commit and pre-push hooks are the only gates, so a clone with
  `core.hooksPath` unset, or a push from another machine, skips them. Re-add a workflow and the
  required contexts together if that stops being acceptable.

The former `git worktree add -b` deny predates this and was removed in the v1.0.0 rebuild;
`claude --worktree` and `/branch` never routed through it anyway. `/branch` and
`claude --continue --fork-session` are session branches, not git branches: they fork the
conversation without touching the working tree.

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
  `stash`/`reset`/`clean`; verify `git diff --cached --name-only` before committing). **Opt-in
  exception (2026-09-28):** a builder dispatch that already trips Rule 13's validator requirement
  may instead get its own worktree, merged back only on a clean validator pass —
  `docs/reference/spawn-brief.md`'s "Isolated checkout dispatch" section. Not the default; the
  shared-worktree-plus-discipline model above still applies to every other dispatch.
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
